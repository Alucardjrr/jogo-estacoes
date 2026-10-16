extends GutTest
## SimNarrative: diário de fim de estação, falas de reação, determinismo e
## isolamento do RNG da simulação (texto não muda balanceamento).

const CFG := {"hard_shortage_days": 3, "residents": 12, "diary_lines": 3,
	"season_group": {"seca": "SECA", "janela_1": "JANELA", "chuvas": "CHUVAS", "janela_2": "JANELA"},
	"reaction_lines": {"DEATH": 4, "FAMILY_LEFT": 4, "BUILDING_DONE": 4, "SHORTAGE_WATER": 3,
		"SHORTAGE_FOOD": 3, "SEASON_SECA": 2, "SEASON_CHUVAS": 2, "SEASON_JANELA": 2}}


func _ev(list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(list)
	return out


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> String: return e.type)


func test_diario_calmo_sem_perdas() -> void:
	var n := SimNarrative.new(CFG)
	var out := n.step(90, 1, 50, _ev([{"type": "season_changed", "from": "seca", "to": "janela_1", "year": 1}]))
	assert_eq(out[0].type, "diary")
	assert_true(out[0].key.begins_with("DIARY_SECA_CALM_"))
	assert_eq(out[0].mood, "CALM")
	assert_eq(out[0].params, {"year": 1, "population": 50, "deaths": 0, "left": 0, "built": 0})


func test_diario_duro_conta_a_estacao_e_zera() -> void:
	var n := SimNarrative.new(CFG)
	n.step(10, 1, 49, _ev([{"type": "death", "family": "f01"}]))
	n.step(11, 1, 45, _ev([{"type": "family_left", "family": "f02", "size": 4}]))
	n.step(12, 1, 45, _ev([{"type": "building_completed", "building": "silo"}]))
	var out := n.step(90, 1, 45, _ev([{"type": "season_changed", "from": "seca", "to": "janela_1", "year": 1}]))
	assert_true(out[0].key.begins_with("DIARY_SECA_DEATH_"), "morte é a causa mais grave")
	assert_eq([out[0].params.deaths, out[0].params.left, out[0].params.built], [1, 1, 1])
	out = n.step(180, 1, 45, _ev([{"type": "season_changed", "from": "janela_1", "to": "chuvas", "year": 1}]))
	assert_true(out[0].key.begins_with("DIARY_JANELA_CALM_"), "zerou ao virar")


func test_dias_de_falta_tornam_a_estacao_dura() -> void:
	var n := SimNarrative.new(CFG)
	for d in 3:
		n.step(d, 1, 50, _ev([{"type": "shortage", "resource": "water", "deficit": 1.0}]))
	var out := n.step(90, 1, 50, _ev([{"type": "season_changed", "from": "seca", "to": "janela_1", "year": 1}]))
	assert_eq(out[0].mood, "SHORT")


func test_diario_da_virada_de_ano_usa_o_ano_que_acabou() -> void:
	var n := SimNarrative.new(CFG)
	var out := n.step(360, 2, 50, _ev([{"type": "year_changed", "year": 2},
		{"type": "season_changed", "from": "janela_2", "to": "seca", "year": 2}]))
	assert_eq(out[0].params.year, 1)


func test_uma_fala_por_dia_pela_prioridade() -> void:
	var n := SimNarrative.new(CFG)
	var out := n.step(5, 1, 49, _ev([{"type": "building_completed", "building": "silo"},
		{"type": "death", "family": "f01"}, {"type": "family_left", "family": "f02", "size": 3}]))
	var speeches := out.filter(func(e: Dictionary) -> bool: return e.type == "speech")
	assert_eq(speeches.size(), 1)
	assert_true(speeches[0].key.begins_with("REACT_DEATH_"))
	assert_true(speeches[0].resident.begins_with("RESIDENT_"))


func test_fala_de_obra_leva_o_predio() -> void:
	var n := SimNarrative.new(CFG)
	var out := n.step(5, 1, 50, _ev([{"type": "building_completed", "building": "cisterna"}]))
	assert_eq(out[0].building, "cisterna")


func test_falta_so_fala_no_primeiro_dia() -> void:
	var n := SimNarrative.new(CFG)
	var short := _ev([{"type": "shortage", "resource": "food", "deficit": 2.0}])
	assert_eq(_types(n.step(1, 1, 50, short)), ["speech"])
	assert_eq(n.step(2, 1, 50, short), [], "falta contínua não repete a fala")
	n.step(3, 1, 50, _ev([]))
	assert_eq(_types(n.step(4, 1, 50, short)), ["speech"], "voltou a faltar: fala de novo")


func test_chaves_dentro_das_quantidades() -> void:
	var n := SimNarrative.new(CFG)
	for d in 400:
		for e in n.step(d, 1, 50, _ev([{"type": "death", "family": "f01"}])):
			var idx := int(e.key.get_slice("_", 2))
			assert_between(idx, 1, 4, e.key)
			assert_between(int(e.resident.trim_prefix("RESIDENT_")), 1, 12)


func test_narrativa_nao_mexe_no_rng_da_simulacao() -> void:
	var a := Simulation.new()
	a.setup(4)
	for _d in 500:
		a.step_day()
	var state := a.loop.rng.state
	var b := Simulation.new()
	b.setup(4)
	b.narrative = SimNarrative.new({"hard_shortage_days": 1, "residents": 1, "diary_lines": 1,
		"season_group": {}, "reaction_lines": {}})
	for _d in 500:
		b.step_day()
	assert_eq(b.loop.rng.state, state)
	assert_eq(a.population.people(), b.population.people())


func test_diario_em_cada_virada_na_simulacao() -> void:
	var sim := Simulation.new()
	sim.setup(1)
	var diaries := 0
	for _d in 360:
		sim.step_day()
		for e in sim.drain_events():
			if e.type == "diary":
				diaries += 1
	assert_eq(diaries, 4)


func test_causa_de_cada_diario() -> void:
	var cases := [
		[[{"type": "family_left", "family": "f", "size": 3}], "LEFT"],
		[[{"type": "building_completed", "building": "silo"}], "BUILT"],
		[[], "CALM"],
	]
	for c in cases:
		var n := SimNarrative.new(CFG)
		n.step(5, 1, 50, _ev(c[0]))
		var out := n.step(90, 1, 50, _ev([{"type": "season_changed", "from": "seca", "to": "janela_1", "year": 1}]))
		assert_eq(out[0].mood, c[1])


func test_diario_da_virada_de_ano_na_simulacao() -> void:
	var sim := Simulation.new()
	sim.setup(1)
	var years := []
	for _d in 361:
		sim.step_day()
		for e in sim.drain_events():
			if e.type == "diary":
				years.append(e.params.year)
	assert_eq(years, [1, 1, 1, 1], "a janela_2 do ano 1 fecha com ano 1")


func test_calendario_de_uma_estacao() -> void:
	var cfg := CFG.duplicate(true)
	cfg.season_group = {"seca": "SECA"}
	var n := SimNarrative.new(cfg)
	var out := n.step(360, 2, 50, _ev([{"type": "year_changed", "year": 2},
		{"type": "season_changed", "from": "seca", "to": "seca", "year": 2}]))
	assert_eq(out[0].params.year, 1)
	assert_true(out[0].key.begins_with("DIARY_SECA_"))
