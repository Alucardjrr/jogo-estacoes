extends GutTest
## Ambiente dev/prod (D-029): ferramentas de debug só em dev.

const GameScript := preload("res://scripts/game.gd")


func test_build_de_debug_e_dev() -> void:
	assert_true(GameScript.is_dev_environment(true, false, false))


func test_build_de_release_e_prod() -> void:
	assert_false(GameScript.is_dev_environment(false, false, false))


func test_tag_dev_liga_em_release() -> void:
	assert_true(GameScript.is_dev_environment(false, true, false))


func test_tag_prod_vence_tudo() -> void:
	assert_false(GameScript.is_dev_environment(true, true, true))


func test_testes_rodam_em_dev() -> void:
	assert_true(Game.dev_mode, "editor/headless de teste é build de debug")



func test_speed_por_argumento_so_em_dev() -> void:
	var args := PackedStringArray(["--speed=3"])
	assert_eq(GameScript.start_speed_index(args, [1, 2, 3], true), 2)
	assert_eq(GameScript.start_speed_index(args, [1, 2, 3], false), -1)
	assert_eq(GameScript.start_speed_index(PackedStringArray(["--speed=9"]), [1, 2, 3], true), -1)
	assert_eq(GameScript.start_speed_index(PackedStringArray(), [1, 2, 3], true), -1)


func test_hud_esconde_modificadores_em_prod() -> void:
	var old: bool = Game.dev_mode
	Game.dev_mode = false
	var hud: Control = preload("res://scenes/debug/debug_hud.tscn").instantiate()
	add_child_autofree(hud)
	assert_false(hud._modifiers_label.visible)
	Game.dev_mode = true
	var hud_dev: Control = preload("res://scenes/debug/debug_hud.tscn").instantiate()
	add_child_autofree(hud_dev)
	assert_true(hud_dev._modifiers_label.visible)
	Game.dev_mode = old


func test_log_mostra_diario_e_falas_traduzidos() -> void:
	var hud: Control = preload("res://scenes/debug/debug_hud.tscn").instantiate()
	add_child_autofree(hud)
	var events: Array[Dictionary] = [
		{"type": "diary", "season": "seca", "key": "DIARY_SECA_DEATH_1",
			"params": {"year": 1, "population": 40, "deaths": 2, "left": 1, "built": 0}},
		{"type": "speech", "key": "REACT_BUILDING_DONE_1", "resident": "RESIDENT_06", "building": "silo"}]
	hud._on_day_passed(Game.sim.snapshot(), events)
	var text: String = hud._log_label.text
	assert_false(text.contains("{"), "marcador sem valor: " + text)
	assert_false(text.contains("DIARY_") or text.contains("REACT_"), "chave sem tradução: " + text)
	assert_true(text.contains(tr("RESIDENT_06")))
	assert_true(text.contains(tr("BUILDING_SILO")))


func test_pulo_de_dev() -> void:
	assert_eq(GameScript.days_to_next_season(1, 90), 90)
	assert_eq(GameScript.days_to_next_season(90, 90), 1)
	assert_eq(GameScript.days_to_next_year(0, 360), 360)
	assert_eq(GameScript.days_to_next_year(359, 360), 1)
	assert_eq(GameScript.days_to_next_year(360, 360), 360)


func test_pulo_nao_existe_em_prod() -> void:
	var dev: bool = Game.dev_mode
	Game.dev_mode = false
	var before: int = Game.sim.calendar.day_index
	assert_eq(Game.dev_skip(360), 0)
	assert_eq(Game.sim.calendar.day_index, before)
	Game.dev_mode = dev



func test_pulo_em_dev_vai_ao_proximo_ano_e_para_no_fim() -> void:
	# Simulação própria no lugar da do autoload, para não sujar outros testes.
	var real: Simulation = Game.sim
	var dev: bool = Game.dev_mode
	var sim := Simulation.new()
	assert_true(sim.setup(1))
	Game.sim = sim
	Game.dev_mode = true
	watch_signals(Game)
	var dpy := sim.calendar.days_per_year()
	assert_eq(Game.dev_skip(GameScript.days_to_next_year(sim.calendar.day_index, dpy)), dpy)
	assert_eq(sim.calendar.day_index % dpy, 0)
	assert_eq(sim.calendar.year(), 2)
	assert_signal_emit_count(Game, "day_passed", 1)
	var left := sim.campaign.days_left(sim.calendar) - 1  # dias que ainda faltam simular
	assert_eq(Game.dev_skip(100000), left)
	assert_true(sim.campaign.ended)
	assert_eq(Game.dev_skip(10), 0)
	Game.sim = real
	Game.dev_mode = dev
