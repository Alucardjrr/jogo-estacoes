extends Control
## Tela de debug do protótipo: data, estação, velocidade e log de viradas.
## Só lê o estado de `Game`; não altera a simulação. Textos via tr() (data/text/ui.csv).

const LOG_LINES := 8

var _date_label := Label.new()
var _season_label := Label.new()
var _status_label := Label.new()
var _log_label := Label.new()
var _log: PackedStringArray = []


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
	for l in [_date_label, _season_label, _status_label]:
		box.add_child(l)

	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	var pause_button := Button.new()
	pause_button.text = tr("HUD_PAUSE_BUTTON")
	pause_button.pressed.connect(func() -> void: Game.set_paused(true))
	buttons.add_child(pause_button)
	for i in Game.speeds().size():
		var b := Button.new()
		b.text = "%d×" % Game.speeds()[i]
		b.pressed.connect(Game.set_speed_index.bind(i))
		buttons.add_child(b)

	var help := Label.new()
	help.text = tr("HUD_HELP")
	help.modulate = Color(1, 1, 1, 0.6)
	box.add_child(help)
	box.add_child(_log_label)

	if not Game.ready_ok:
		_date_label.text = tr("HUD_DATA_ERROR")
		_season_label.text = "\n".join(Game.sim.data.errors)
		buttons.visible = false
		return

	Game.day_passed.connect(_on_day_passed)
	Game.speed_changed.connect(_on_speed_changed)
	_refresh(Game.sim.snapshot())
	_on_speed_changed(Game.paused, Game.current_speed())


func _unhandled_input(event: InputEvent) -> void:
	if not Game.ready_ok or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			if Game.paused:
				Game.set_speed_index(Game.speed_index)
			else:
				Game.set_paused(true)
		KEY_1, KEY_2, KEY_3:
			Game.set_speed_index(event.keycode - KEY_1)


func _on_day_passed(snapshot: Dictionary, events: Array[Dictionary]) -> void:
	_refresh(snapshot)
	for e in events:
		match e.type:
			"season_changed":
				_push_log(tr("EVENT_SEASON_CHANGED").format(
					{"season": _season_name(e.to), "year": e.year}))
			"year_changed":
				_push_log(tr("EVENT_YEAR_CHANGED").format({"year": e.year}))


func _on_speed_changed(paused: bool, speed: int) -> void:
	_status_label.text = tr("HUD_PAUSED") if paused else tr("HUD_SPEED").format({"speed": speed})


func _refresh(s: Dictionary) -> void:
	_date_label.text = tr("HUD_DATE").format(
		{"day": s.day, "month": tr("MONTH_%d" % s.month), "year": s.year})
	_season_label.text = tr("HUD_SEASON").format(
		{"season": _season_name(s.season), "day": s.day_in_season, "total": s.season_days})
	_season_label.modulate = Color("ffb36b") if s.season_severe else Color("cfe8c4")


func _season_name(id: String) -> String:
	return tr("SEASON_" + id.to_upper())


func _push_log(line: String) -> void:
	_log.append(line)
	if _log.size() > LOG_LINES:
		_log.remove_at(0)
	_log_label.text = "\n".join(_log)
