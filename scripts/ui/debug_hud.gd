extends Control
## Tela de debug do protótipo: data, estação, velocidade, idioma e log de viradas.
## Só lê o estado de `Game`; não altera a simulação. Textos via tr() (data/text/ui.csv)
## e refeitos quando o idioma muda.

const LOG_LINES := 8

var _date_label := Label.new()
var _season_label := Label.new()
var _status_label := Label.new()
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
	for l in [_date_label, _season_label, _status_label]:
		box.add_child(l)

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


func _on_day_passed(snapshot: Dictionary, events: Array[Dictionary]) -> void:
	_refresh(snapshot)
	for e in events:
		if e.type in ["season_changed", "year_changed"]:
			_log_events.append(e)
	while _log_events.size() > LOG_LINES:
		_log_events.remove_at(0)
	_render_log()


func _on_speed_changed() -> void:
	_status_label.text = tr("HUD_PAUSED") if Game.paused \
		else tr("HUD_SPEED").format({"speed": Game.current_speed()})


func _refresh(s: Dictionary) -> void:
	_date_label.text = tr("HUD_DATE").format(
		{"day": s.day, "month": tr("MONTH_%d" % s.month), "year": s.year})
	_season_label.text = tr("HUD_SEASON").format(
		{"season": _season_name(s.season), "day": s.day_in_season, "total": s.season_days})
	_season_label.modulate = Color("ffb36b") if s.season_severe else Color("cfe8c4")


func _render_log() -> void:
	var lines: PackedStringArray = []
	for e in _log_events:
		match e.type:
			"season_changed":
				lines.append(tr("EVENT_SEASON_CHANGED").format(
					{"season": _season_name(e.to), "year": e.year}))
			"year_changed":
				lines.append(tr("EVENT_YEAR_CHANGED").format({"year": e.year}))
	_log_label.text = "\n".join(lines)


func _season_name(id: String) -> String:
	return tr("SEASON_" + id.to_upper())
