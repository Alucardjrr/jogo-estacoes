extends Node
## Autoload único `Game` (D-020): dono da Simulation e do relógio de tempo real.
## Pausa e velocidade são da apresentação, não da simulação — não entram em
## replay nem afetam o determinismo.

signal day_passed(snapshot: Dictionary, events: Array[Dictionary])
signal speed_changed(paused: bool, speed: int)

var sim := Simulation.new()
var ready_ok := false
var paused := true
var speed_index := 0


func _ready() -> void:
	TranslationServer.set_locale("pt_BR")
	ready_ok = sim.setup()
	if not ready_ok:
		for e in sim.data.errors:
			push_error("[dados] " + e)
		return
	# Playtest/captura: `godot --path . -- --speed=3` começa rodando nessa velocidade.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--speed="):
			var i := speeds().find(arg.trim_prefix("--speed=").to_int())
			if i >= 0:
				set_speed_index(i)


func _process(delta: float) -> void:
	if not ready_ok or paused:
		return
	if sim.advance(delta, current_speed()) > 0:
		day_passed.emit(sim.snapshot(), sim.drain_events())


func speeds() -> Array:
	return sim.data.section("sim").get("speeds", [1])


func current_speed() -> int:
	return speeds()[speed_index]


func set_paused(value: bool) -> void:
	paused = value
	speed_changed.emit(paused, current_speed())


func set_speed_index(index: int) -> void:
	speed_index = clampi(index, 0, speeds().size() - 1)
	paused = false
	speed_changed.emit(paused, current_speed())
