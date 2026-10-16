extends Control
## Tela de debug do protótipo: data, estação, intensidade, população, recursos, modificadores,
## velocidade, idioma e log de viradas.
## Só lê o estado de `Game`; não altera a simulação. Textos via tr() (data/text/ui.csv)
## e refeitos quando o idioma muda.

const LOG_LINES := 12

var _date_label := Label.new()
var _season_label := Label.new()
var _status_label := Label.new()
var _intensity_label := Label.new()
var _resource_labels := {}  # id do recurso -> Label
var _modifiers_label := Label.new()
var _labor_label := Label.new()
## Ajustes de mão de obra já enviados e ainda não aplicados (aplicam no próximo dia).
var _pending := {}
## Obras pedidas por tecla e ainda não processadas pelo próximo dia.
var _pending_builds: Array[String] = []
var _last_snapshot := {}
const LABOR_KEYS := {KEY_Q: ["water", 1], KEY_A: ["water", -1], KEY_W: ["farm", 1],
	KEY_S: ["farm", -1], KEY_E: ["care", 1], KEY_D: ["care", -1], KEY_R: ["build", 1],
	KEY_F: ["build", -1], KEY_T: ["salvage", 1], KEY_G: ["salvage", -1]}
## Teclas da fila de obras (só debug). Id sem tecla não pode ser pedido por aqui.
const BUILD_KEYS := {KEY_Z: "cisterna", KEY_X: "silo", KEY_C: "canteiro", KEY_V: "abrigo"}
var _buildings_label := Label.new()
var _help_label := Label.new()
var _log_label := Label.new()
var _pause_button := Button.new()
var _locale_button := Button.new()
var _buttons := HBoxContainer.new()
## Eventos guardados crus, para retraduzir o log quando o idioma muda.
var _log_events: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("2b1d14")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.position = Vector2(32, 32)
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	_date_label.add_theme_font_size_override("font_size", 32)
	_season_label.add_theme_font_size_override("font_size", 22)
	_help_label.modulate = Color(1, 1, 1, 0.6)
	for l in [_date_label, _season_label, _intensity_label]:
		box.add_child(l)
	for id in DataRegistry.RESOURCE_IDS:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 20)
		_resource_labels[id] = l
		box.add_child(l)
	_labor_label.add_theme_font_size_override("font_size", 20)
	box.add_child(_labor_label)
	_buildings_label.add_theme_font_size_override("font_size", 18)
	box.add_child(_buildings_label)
	_modifiers_label.modulate = Color(1, 1, 1, 0.6)
	_modifiers_label.visible = Game.dev_mode  # detalhe interno: só em dev (D-029)
	box.add_child(_modifiers_label)
	box.add_child(_status_label)

	box.add_child(_buttons)
	_pause_button.pressed.connect(func() -> void: Game.set_paused(true))
	_buttons.add_child(_pause_button)
	for i in Game.speeds().size():
		var b := Button.new()
		b.text = "%d×" % Game.speeds()[i]
		b.pressed.connect(Game.set_speed_index.bind(i))
		_buttons.add_child(b)
	_locale_button.pressed.connect(Game.cycle_locale)
	_buttons.add_child(_locale_button)

	box.add_child(_help_label)
	box.add_child(_log_label)

	if Game.ready_ok:
		Game.day_passed.connect(_on_day_passed)
		Game.speed_changed.connect(_on_speed_changed.unbind(2))
	_refresh_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_all()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_L:
		Game.cycle_locale()
		return
	if not Game.ready_ok:
		return
	match event.keycode:
		KEY_SPACE:
			if Game.paused:
				Game.set_speed_index(Game.speed_index)
			else:
				Game.set_paused(true)
		KEY_1, KEY_2, KEY_3:
			Game.set_speed_index(event.keycode - KEY_1)
		_:
			if LABOR_KEYS.has(event.keycode):
				_adjust_labor(LABOR_KEYS[event.keycode][0], LABOR_KEYS[event.keycode][1])
			elif BUILD_KEYS.has(event.keycode):
				_pending_builds.append(BUILD_KEYS[event.keycode])
				Game.build(BUILD_KEYS[event.keycode])
				if not _last_snapshot.is_empty():
					_refresh(_last_snapshot)


func _adjust_labor(task: String, delta: int) -> void:
	if _last_snapshot.is_empty():
		return
	var lab: Dictionary = _last_snapshot.labor
	var current: int = lab.desired[task] + _pending.get(task, 0)
	if current + delta < 0:
		return
	# Sem trava: se o pedido passar dos trabalhadores, a simulação reduz todos na
	# mesma proporção e a tela mostra isso (antes a tecla travava sem explicar).
	_pending[task] = _pending.get(task, 0) + delta
	Game.adjust_labor(task, delta)
	_refresh(_last_snapshot)


func _refresh_all() -> void:
	_pause_button.text = tr("HUD_PAUSE_BUTTON")
	_locale_button.text = tr("HUD_LANGUAGE")
	_help_label.text = tr("HUD_HELP")
	if not Game.ready_ok:
		_date_label.text = tr("HUD_DATA_ERROR")
		_season_label.text = "\n".join(Game.sim.data.errors)
		for b in _buttons.get_children():
			b.visible = b == _locale_button  # só o idioma continua disponível
		return
	_refresh(Game.sim.snapshot())
	_on_speed_changed()
	_render_log()


const LOGGED := ["season_changed", "year_changed", "death", "family_left", "colony_empty",
	"diary", "speech", "build_queued", "building_completed", "command_rejected"]


func _on_day_passed(snapshot: Dictionary, events: Array[Dictionary]) -> void:
	_pending.clear()  # já aplicados no início do tick
	_pending_builds.clear()
	_refresh(snapshot)
	for e in log_order(events):
		if e.type in LOGGED:
			_log_events.append(e)
	while _log_events.size() > LOG_LINES:
		_log_events.remove_at(0)
	_render_log()


## Ordem do log de um dia: o diário da estação que acabou vem antes de "Começou: …".
static func log_order(events: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if e.type == "diary":
			out.append(e)
	for e in events:
		if e.type != "diary":
			out.append(e)
	return out


func _on_speed_changed() -> void:
	_status_label.text = tr("HUD_PAUSED") if Game.paused \
		else tr("HUD_SPEED").format({"speed": Game.current_speed()})


func _refresh(s: Dictionary) -> void:
	_last_snapshot = s
	_date_label.text = tr("SETTLEMENT_NAME") + " — " + tr("HUD_DATE").format(
		{"day": s.day, "month": tr("MONTH_%d" % s.month), "year": s.year})
	_season_label.text = tr("HUD_SEASON").format(
		{"season": _season_name(s.season), "day": s.day_in_season, "total": s.season_days})
	_season_label.modulate = Color("ffb36b") if s.season_severe else Color("cfe8c4")
	_intensity_label.text = tr("HUD_INTENSITY").format({"value": "%.2f" % s.intensity}) \
		+ "   " + tr("HUD_POPULATION").format({"people": s.population,
			"families": s.families, "health": roundi(s.health)})
	for id in DataRegistry.RESOURCE_IDS:
		var r: Dictionary = s.resources[id]
		var label: Label = _resource_labels[id]
		label.text = tr("HUD_RESOURCE").format({
			"name": tr("RESOURCE_" + id.to_upper()),
			"stock": roundi(r.stock), "capacity": roundi(r.capacity),
			"inflow": _num(r.inflow), "consumed": _num(r.consumed), "lost": _num(r.lost)})
		var net: float = r.inflow - r.demand - r.lost
		if net < 0.0:
			label.text += "  " + tr("HUD_DAYS_LEFT").format({"days": days_left(r.stock, net)})
		else:
			label.text += "  " + tr("HUD_STABLE")
		if r.overflow > 0.0:
			label.text += "  " + tr("HUD_OVERFLOW").format({"amount": _num(r.overflow)})
		if r.deficit > 0.0:
			label.text += "  " + tr("HUD_SHORTAGE").format({"amount": _num(r.deficit)})
			label.modulate = Color("ff6b6b")
		elif r.stock < r.capacity * 0.1:
			label.modulate = Color("ffb36b")
		else:
			label.modulate = Color.WHITE
	_labor_label.text = labor_text(s.labor, _pending)
	_buildings_label.text = _buildings_text(s)
	var mods: PackedStringArray = []
	for m in s.modifiers:
		mods.append("%s %s" % [m.key, ("×%.2f" % m.mul) if m.mul != 1.0 else signed(m.add)])
	_modifiers_label.text = tr("HUD_MODIFIERS") + " " + " · ".join(mods)


## Linha de trabalho. Com pedido acima dos trabalhadores, cada tarefa mostra
## "pedido→real" e um aviso; a conta do "real" é a mesma da simulação.
func labor_text(lab: Dictionary, pending: Dictionary) -> String:
	var shown := {}
	var total := 0
	for id in DataRegistry.TASK_IDS:
		shown[id] = lab.desired[id] + pending.get(id, 0)
		total += shown[id]
	var workers: int = lab.workers
	var over := total > workers
	var scale := float(workers) / total if over else 1.0
	var parts := {}
	for id in DataRegistry.TASK_IDS:
		parts[id] = ("%d→%d" % [shown[id], roundi(shown[id] * scale)]) if over else str(shown[id])
	var idle := maxi(workers - total, 0)
	var text := tr("HUD_LABOR").format({"water": parts.water, "farm": parts.farm,
		"care": parts.care, "build": parts.build, "salvage": parts.salvage,
		"idle": idle, "workers": workers, "productivity": roundi(lab.productivity * 100.0)})
	if over:
		text += "\n" + tr("HUD_LABOR_OVER").format({"asked": total, "workers": workers})
	elif not lab.changed and pending.is_empty():
		text += "  " + tr("HUD_LABOR_INITIAL")
	return text


func _buildings_text(s: Dictionary) -> String:
	var b: Dictionary = s.buildings
	var days_left: int = s.season_days - s.day_in_season
	var parts: PackedStringArray = []
	var by_type := {}
	for inst in b.instances:
		by_type[inst.type] = by_type.get(inst.type, []) + [inst]
	var types := by_type.keys()
	types.sort()
	for t in types:
		var cond := 0.0
		var end := 0.0
		for inst in by_type[t]:
			cond += inst.condition
			end += Game.sim.buildings.forecast_condition(inst, s.season, days_left)
		var n: int = by_type[t].size()
		parts.append(tr("HUD_BUILDING").format({"name": tr("BUILDING_" + t.to_upper()),
			"count": n, "condition": roundi(cond / n), "end": roundi(end / n)}))
	var text := tr("HUD_BUILDINGS") + " " + (" · ".join(parts) if not parts.is_empty() else "—")
	text += "\n" + tr("HUD_MATERIALS").format({"materials": roundi(b.materials),
		"ruins": roundi(b.ruins_remaining), "ruins_total": roundi(b.ruins_initial)})
	if not b.queue.is_empty():
		var job: Dictionary = b.queue[0]
		var key := "HUD_QUEUE_WORKING" if job.started else "HUD_QUEUE_WAITING"
		text += "  " + tr(key).format({"name": tr("BUILDING_" + job.type.to_upper()),
			"progress": roundi(job.progress), "cost": roundi(job.cost_points),
			"materials": roundi(job.cost_materials), "queued": b.queue.size()})
		if not job.started:
			text += " " + waiting_hint(b, s.labor)
	if not _pending_builds.is_empty():
		var names: PackedStringArray = []
		for id in _pending_builds:
			names.append(tr("BUILDING_" + id.to_upper()))
		text += "\n" + tr("HUD_BUILD_REQUESTED").format({"names": ", ".join(names)})
	return text


## Por que a obra parada não anda e o que fazer.
func waiting_hint(b: Dictionary, lab: Dictionary) -> String:
	if b.ruins_remaining <= 0.0:
		return tr("HUD_HINT_RUINS_EMPTY")
	if lab.desired.salvage == 0:
		return tr("HUD_HINT_SALVAGE")
	return tr("HUD_HINT_SALVAGING")


## Dias até o estoque acabar com o saldo diário `net` (< 0). Arredonda para cima:
## 0,4 dia de estoque ainda é "1 dia"; estoque zerado é 0.
static func days_left(stock: float, net: float) -> int:
	if stock <= 0.0:
		return 0
	return ceili(stock / -net)


## Número curto para a tela: 0 como "0"; inteiro se >= 10; 1 casa se >= 0,1;
## senão 4 casas (taxas pequenas).
static func _num(v: float) -> String:
	if absf(v) < 1e-9:
		return "0"
	if absf(v) >= 10.0:
		return str(roundi(v))
	if absf(v) >= 0.1:
		return "%.1f" % v
	return "%.4f" % v


## "+2.0", "-0.5", "0" (sem "+-").
static func signed(v: float) -> String:
	var t := _num(v)
	return t if t == "0" or v < 0.0 else "+" + t


func _render_log() -> void:
	var lines: PackedStringArray = []
	for e in _log_events:
		match e.type:
			"season_changed":
				lines.append(tr("EVENT_SEASON_CHANGED").format(
					{"season": _season_name(e.to), "year": e.year}))
			"year_changed":
				lines.append(tr("EVENT_YEAR_CHANGED").format({"year": e.year}))
			"death":
				lines.append(tr("EVENT_DEATH").format({"family": e.family}))
			"family_left":
				lines.append(tr("EVENT_FAMILY_LEFT").format({"family": e.family, "size": e.size}))
			"colony_empty":
				lines.append(tr("EVENT_COLONY_EMPTY"))
			"diary":
				lines.append(tr("HUD_DIARY") + " " + tr(e.key).format(e.params))
			"build_queued":
				lines.append(tr("EVENT_BUILD_QUEUED").format({
					"name": tr("BUILDING_" + String(e.building).to_upper()),
					"position": e.position, "max": e.max}))
			"building_completed":
				lines.append(tr("EVENT_BUILDING_COMPLETED").format({
					"name": tr("BUILDING_" + String(e.building).to_upper())}))
			"command_rejected":
				lines.append(tr("EVENT_REJECTED") + " " + tr("REJECT_" + String(e.reason).to_upper()))
			"speech":
				var params := {"name": tr(e.resident)}
				if e.has("building"):
					params.building = tr("BUILDING_" + String(e.building).to_upper())
				lines.append(tr(e.key).format(params))
	_log_label.text = "\n".join(lines)


func _season_name(id: String) -> String:
	return tr("SEASON_" + id.to_upper())
