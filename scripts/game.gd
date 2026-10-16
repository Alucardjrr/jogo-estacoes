extends Node
## Autoload único `Game` (D-020): dono da Simulation e do relógio de tempo real.
## Pausa e velocidade são da apresentação, não da simulação — não entram em
## replay nem afetam o determinismo.

signal day_passed(snapshot: Dictionary, events: Array[Dictionary])
signal speed_changed(paused: bool, speed: int)

var sim := Simulation.new()
var settings := GameSettings.new()
## Caminho das preferências; os testes trocam para não mexer no arquivo real.
var settings_path := GameSettings.PATH
var ready_ok := false
## Ambiente (D-029): dev = editor/build de debug ou feature "dev"; prod = build
## de release ou feature "prod". Ferramentas de debug só existem em dev.
var dev_mode := is_dev_environment(OS.is_debug_build(), OS.has_feature("dev"), OS.has_feature("prod"))
var paused := true
var speed_index := 0


func _ready() -> void:
	_apply_settings()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--locale="):  # só nesta execução, não salva
			_set_locale(arg.trim_prefix("--locale="), false)
	ready_ok = sim.setup()
	if not ready_ok:
		for e in sim.data.errors:
			push_error("[dados] " + e)
		return
	# Playtest/captura (só dev): `godot --path . -- --speed=3` começa rodando nessa velocidade.
	if not dev_mode:
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--speed="):
			var i := speeds().find(arg.trim_prefix("--speed=").to_int())
			if i >= 0:
				set_speed_index(i)


## "prod" vence tudo; depois "dev"; sem tag, segue o tipo de build.
static func is_dev_environment(debug_build: bool, has_dev: bool, has_prod: bool) -> bool:
	if has_prod:
		return false
	return has_dev or debug_build


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


# --- Idioma (D-024) ---

func current_locale() -> String:
	return TranslationServer.get_locale()


## Alterna para o próximo idioma suportado e salva a escolha.
func cycle_locale() -> void:
	_set_locale(settings.next_locale(current_locale()), true)


func _apply_settings() -> void:
	settings.load_from(settings_path)
	for w in settings.warnings:
		push_warning("[settings] " + w)
	TranslationServer.set_locale(settings.resolve_locale(OS.get_locale()))


## Retorna false se o idioma não é suportado (nada muda).
func _set_locale(locale: String, persist: bool) -> bool:
	if not GameSettings.SUPPORTED_LOCALES.has(locale):
		push_warning("[settings] idioma não suportado: " + locale)
		return false
	TranslationServer.set_locale(locale)
	if persist:
		settings.locale = locale
		if not settings.save_to(settings_path):
			push_warning("[settings] não foi possível salvar " + settings_path)
	return true
