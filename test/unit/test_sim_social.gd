extends GutTest
## SimSocial: medidores, curvas, custo/teto/repetição, regras de ativação, expiração,
## efeitos "depois"; integração com o comando enact_measure.

const CFG := {"trust_initial": 75.0, "cohesion_initial": 75.0, "recovery_per_day": 0.05,
	"shortage_trust_per_day": 0.3, "death_cohesion": 1.0, "left_cohesion": 2.0, "low_threshold": 30.0,
	"trust_productivity": {"full_at": 70.0, "mid_at": 30.0, "mid_mult": 0.9, "zero_mult": 0.7},
	"cohesion_departure": {"full_at": 70.0, "mid_at": 30.0, "mid_mult": 0.8, "zero_mult": 0.5},
	"residual_fraction": 0.25, "repeat_cost_increase": 0.5, "one_per_season": true,
	"measures": {
		"a": {"seasons": ["seca"], "trust_cost": 10.0, "cohesion_cost": 0.0, "full_residual": false,
			"exempt_one_per_season": false, "unlock_water_below": 0.0, "instant_water_days": 0.0,
			"after_days": 2, "effects": [{"key": "health_drift", "add": -1.0}],
			"after_effects": [{"key": "productivity_mult", "mul": 0.5}]},
		"b": {"seasons": ["seca"], "trust_cost": 0.0, "cohesion_cost": 10.0, "full_residual": false,
			"exempt_one_per_season": false, "unlock_water_below": 0.0, "instant_water_days": 0.0,
			"after_days": 0, "effects": [{"key": "farm_mult", "add": 0.3}], "after_effects": []},
		"d": {"seasons": [], "trust_cost": 30.0, "cohesion_cost": 20.0, "full_residual": true,
			"exempt_one_per_season": true, "unlock_water_below": 0.1, "instant_water_days": 12.0,
			"after_days": 0, "effects": [], "after_effects": []}}}


func _value(m: ModifierStack, key: String, base: float = 0.0) -> float:
	return m.value(key, base)


func test_curva_sem_penhasco() -> void:
	var c: Dictionary = CFG.trust_productivity
	assert_eq(SimSocial.curve(80.0, c), 1.0)
	assert_eq(SimSocial.curve(70.0, c), 1.0)
	assert_almost_eq(SimSocial.curve(50.0, c), 0.95, 1e-9)
	assert_almost_eq(SimSocial.curve(30.0, c), 0.9, 1e-9)
	assert_almost_eq(SimSocial.curve(15.0, c), 0.8, 1e-9)
	assert_almost_eq(SimSocial.curve(0.0, c), 0.7, 1e-9)


func test_custo_teto_e_repeticao() -> void:
	var s := SimSocial.new(CFG)
	s.enact("a", "seca", 1)
	assert_eq(s.trust, 65.0)
	assert_eq(s.trust_ceiling, 97.5)
	assert_eq(s.cost("a").trust, 15.0, "segunda vez custa ×1,5")
	s.enact("a", "seca", 2)
	assert_eq(s.trust, 50.0)
	assert_eq(s.trust_ceiling, 93.75)


func test_residual_integral_e_teto_limita_o_medidor() -> void:
	var s := SimSocial.new(CFG)
	s.trust = 100.0
	s.enact("d", "chuvas", 1)
	assert_eq(s.trust_ceiling, 70.0)
	assert_eq(s.trust, 70.0)
	for _i in 100:
		s.update(false, 0, 0)
	assert_eq(s.trust, 70.0, "recupera só até o teto")


func test_regras_de_ativacao() -> void:
	var s := SimSocial.new(CFG)
	assert_eq(s.check("x", "seca", 1, 0.5), "invalid_measure")
	assert_eq(s.check("a", "chuvas", 1, 0.5), "wrong_season")
	assert_eq(s.check("d", "seca", 1, 0.5), "locked")
	assert_eq(s.check("d", "seca", 1, 0.05), "")
	assert_eq(s.check("a", "seca", 1, 0.5), "")
	s.enact("a", "seca", 1)
	assert_eq(s.check("a", "seca", 1, 0.5), "already_enacted")
	assert_eq(s.check("b", "seca", 1, 0.5), "one_per_season")
	assert_eq(s.check("d", "seca", 1, 0.05), "", "desespero fica fora da regra")
	assert_eq(s.check("b", "seca", 2, 0.5), "", "nova estação (ano seguinte) libera")


func test_uma_por_estacao_pode_ser_desligada() -> void:
	var cfg := CFG.duplicate(true)
	cfg.one_per_season = false
	var s := SimSocial.new(cfg)
	s.enact("a", "seca", 1)
	assert_eq(s.check("b", "seca", 1, 0.5), "")


func test_efeitos_ativos_expiram_e_depois_dura_n_dias() -> void:
	var s := SimSocial.new(CFG)
	var m := ModifierStack.new()
	s.enact("a", "seca", 1)
	s.trust = 90.0  # isola o efeito da medida da curva de confiança
	s.publish("seca", 1, m)
	assert_eq(_value(m, "health_drift"), -1.0)
	var ev := s.publish("janela_1", 1, m)
	assert_eq(ev, [{"type": "measure_expired", "measure": "a"}])
	assert_eq(_value(m, "health_drift"), 0.0)
	assert_almost_eq(_value(m, "productivity_mult", 1.0), 0.5, 1e-9, "dia 1 do depois")
	s.publish("janela_1", 1, m)
	assert_almost_eq(_value(m, "productivity_mult", 1.0), 0.5, 1e-9, "dia 2")
	s.publish("janela_1", 1, m)
	assert_eq(_value(m, "productivity_mult", 1.0), 1.0, "acabou")


func test_medidores_reagem_ao_dia_e_avisam_uma_vez() -> void:
	var s := SimSocial.new(CFG)
	s.update(true, 2, 1)
	assert_almost_eq(s.trust, 74.7, 1e-9)
	assert_almost_eq(s.cohesion, 71.0, 1e-9)
	s.cohesion = 31.0
	assert_eq(s.update(false, 0, 1), [{"type": "meter_low", "meter": "cohesion"}])
	assert_eq(s.update(false, 0, 0), [], "aviso só ao cruzar")


func test_curvas_publicadas() -> void:
	var s := SimSocial.new(CFG)
	s.trust = 30.0
	s.cohesion = 0.0
	var m := ModifierStack.new()
	s.publish("seca", 1, m)
	assert_almost_eq(_value(m, "productivity_mult", 1.0), 0.9, 1e-9)
	assert_almost_eq(_value(m, "departure_days_mult", 1.0), 0.5, 1e-9)


# --- Integração ---

func _sim() -> Simulation:
	var sim := Simulation.new()
	assert_true(sim.setup(1))
	return sim


func test_comando_e_recusas() -> void:
	var sim := _sim()
	sim.enqueue({"type": "enact_measure", "measure": "quarentena"})
	sim.enqueue({"type": "enact_measure", "measure": "confisco"})
	sim.enqueue({"type": "enact_measure"})
	sim.enqueue({"type": "enact_measure", "measure": "racionamento"})
	sim.enqueue({"type": "enact_measure", "measure": "agua_na_roca"})
	sim.step_day()
	var ev := sim.drain_events()
	var reasons := ev.filter(func(e: Dictionary) -> bool: return e.type == "command_rejected") \
		.map(func(e: Dictionary) -> String: return e.reason)
	assert_eq(reasons, ["wrong_season", "locked", "invalid_measure", "one_per_season"])
	assert_eq(ev.filter(func(e: Dictionary) -> bool: return e.type == "measure_enacted").size(), 1)
	assert_true(sim.social.is_active("racionamento"))


func test_partilha_reduz_o_consumo_de_agua() -> void:
	var sim := _sim()
	sim.step_day()
	var before: float = sim.snapshot().resources.water.demand
	sim.enqueue({"type": "enact_measure", "measure": "racionamento"})
	sim.step_day()
	assert_almost_eq(sim.snapshot().resources.water.demand, before * 0.6, 1e-6)


func test_requisicao_da_agua_na_hora() -> void:
	var sim := _sim()
	sim.resources.stock.water = 100.0
	sim.enqueue({"type": "enact_measure", "measure": "confisco"})
	sim.step_day()
	var ev := sim.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "measure_enacted")
	assert_eq(ev.size(), 1)
	var days: float = sim.data.section("social").measures.confisco.instant_water_days
	assert_almost_eq(ev[0].water, days * 50.0, 1e-6)


func test_mutirao_dobra_obras_e_saque() -> void:
	var run := func(mutirao: bool) -> float:
		var sim := _sim()
		sim.calendar.day_index = 180  # 1º dia das chuvas
		sim.enqueue({"type": "set_labor", "task": "salvage", "value": 5})
		if mutirao:
			sim.enqueue({"type": "enact_measure", "measure": "mutirao"})
		sim.step_day()
		return sim.buildings.materials
	assert_almost_eq(run.call(true), run.call(false) * 2.0, 1e-6)


func test_confianca_baixa_reduz_a_producao() -> void:
	var sim := _sim()
	sim.step_day()
	var full: float = sim.snapshot().resources.water.inflow
	var sim2 := _sim()
	sim2.social.trust = 0.0
	sim2.step_day()
	assert_lt(sim2.snapshot().resources.water.inflow, full)



func test_medida_no_ultimo_dia_vale_na_estacao_nova() -> void:
	# QA PR #15: pedida no último dia da seca, vale como medida das janela (recusada lá).
	var sim := _sim()
	sim.calendar.day_index = 89  # último dia da seca
	sim.enqueue({"type": "enact_measure", "measure": "agua_na_roca"})
	sim.step_day()
	assert_eq(sim.calendar.season_id(), "janela_1")
	var ev := sim.drain_events()
	assert_eq(ev.filter(func(e: Dictionary) -> bool: return e.type == "command_rejected")[0].reason, "wrong_season")
	assert_eq(sim.social.after, [], "nada de efeito 'depois' sem a medida")
	assert_eq(sim.social.cohesion, sim.data.section("social").cohesion_initial + 0.05, "sem custo")


func test_medida_no_primeiro_dia_vale_o_dia_inteiro() -> void:
	var sim := _sim()
	sim.calendar.day_index = 179  # vira chuvas no próximo passo
	sim.enqueue({"type": "enact_measure", "measure": "quarentena"})
	sim.step_day()
	assert_true(sim.social.is_active("quarentena"))
	assert_eq(sim.calendar.season_id(), "chuvas")


func test_check_nao_muda_estado() -> void:
	var s := SimSocial.new(CFG)
	s.enact("a", "seca", 1)
	var before := s.snapshot()
	s.check("b", "chuvas", 1, 0.5)
	s.check("b", "seca", 2, 0.5)
	assert_eq(s.snapshot(), before)
	assert_eq(s.check("b", "seca", 1, 0.5), "one_per_season")


func test_descricao_tem_todos_os_numeros() -> void:
	var sim := _sim()
	var marker := RegEx.create_from_string("\\{([a-z_]+)\\}")
	var csv := FileAccess.open("res://data/text/ui.csv", FileAccess.READ)
	var rows := {}
	while not csv.eof_reached():
		var line := csv.get_csv_line()
		if line.size() >= 3:
			rows[line[0]] = [line[1], line[2]]
	for id in sim.social.measure_ids():
		var params := sim.social.describe(id)
		for text in rows["MEASURE_%s_DESC" % id.to_upper()]:
			for m in marker.search_all(text):
				assert_true(params.has(m.get_string(1)), "%s: {%s} sem valor em social.json" % [id, m.get_string(1)])
