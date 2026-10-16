extends GutTest
## SimPopulation: saúde, mortes, partidas, determinismo.

const CFG := {"families": [{"id": "a", "size": 4}, {"id": "b", "size": 2}],
	"health_initial": 80.0, "health_max": 100.0, "health_recovery_per_day": 0.5,
	"water_shortage_health": 8.0, "food_shortage_health": 3.0,
	"death_health_threshold": 40.0, "death_rate_max": 0.1, "departure_shortage_days": 3}


func _flow(water_def: float, food_def: float, demand: float = 10.0) -> Dictionary:
	return {"water": {"demand": demand, "deficit": water_def},
		"food": {"demand": demand, "deficit": food_def}}


func _rng(seed_number: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_number
	return r


func _mods(drift: float = 0.0) -> ModifierStack:
	var m := ModifierStack.new()
	m.add("health_drift", "t", drift)
	return m


func _cfg(changes: Dictionary) -> Dictionary:
	var c := CFG.duplicate(true)
	c.merge(changes, true)
	return c


func test_estado_inicial_vem_dos_dados() -> void:
	var p := SimPopulation.new(CFG)
	assert_eq(p.people(), 6)
	assert_eq(p.health, 80.0)


func test_dados_nao_sao_alterados() -> void:
	var cfg := CFG.duplicate(true)
	var p := SimPopulation.new(cfg)
	p.families[0].size = 1
	assert_eq(cfg.families[0].size, 4, "estado da população não pode vazar para os dados")


func test_sem_falta_recupera_ate_o_teto() -> void:
	var p := SimPopulation.new(CFG)
	p.step(_flow(0, 0), _mods(), _rng())
	assert_eq(p.health, 80.5)
	for _i in 100:
		p.step(_flow(0, 0), _mods(), _rng())
	assert_eq(p.health, 100.0)


func test_falta_reduz_saude_pela_fracao_do_deficit() -> void:
	var p := SimPopulation.new(CFG)
	p.step(_flow(5.0, 10.0), _mods(), _rng())  # água 50% → −4; comida 100% → −3
	assert_almost_eq(p.health, 73.0, 1e-9)
	assert_eq(p.shortage_streak, 1)


func test_drift_da_estacao_soma_sempre() -> void:
	var p := SimPopulation.new(CFG)
	p.step(_flow(0, 0), _mods(-0.35), _rng())
	assert_almost_eq(p.health, 80.15, 1e-9)
	p.step(_flow(0, 10.0), _mods(-0.35), _rng())
	assert_almost_eq(p.health, 76.8, 1e-9)


func test_saude_nao_fica_negativa() -> void:
	var p := SimPopulation.new(_cfg({"death_rate_max": 0.0}))
	for _i in 30:
		p.step(_flow(10.0, 10.0), _mods(), _rng())
	assert_eq(p.health, 0.0)


func test_demanda_zero_nao_e_falta() -> void:
	var p := SimPopulation.new(CFG)
	p.step(_flow(0, 0, 0.0), _mods(), _rng())
	assert_eq(p.shortage_streak, 0)
	assert_eq(p.health, 80.5)


func test_sem_mortes_acima_do_limiar() -> void:
	var p := SimPopulation.new(_cfg({"health_initial": 40.0}))
	var events := p.step(_flow(0, 0), _mods(), _rng())
	assert_eq(events, [])
	assert_eq(p.people(), 6)


func test_mortes_acumulam_fracoes() -> void:
	# saúde fica em 0 → taxa cheia: 6 × 0,1 = 0,6/dia; 1ª morte no 2º dia (1,2).
	var p := SimPopulation.new(_cfg({"health_initial": 0.0, "health_recovery_per_day": 0.0}))
	assert_eq(p.step(_flow(0, 0), _mods(), _rng()), [])
	var events := p.step(_flow(0, 0), _mods(), _rng())
	assert_eq(events.size(), 1)
	assert_eq(events[0].type, "death")
	assert_eq(p.people(), 5)


func test_familia_que_zera_sai_da_lista() -> void:
	var p := SimPopulation.new(_cfg({"families": [{"id": "x", "size": 1}],
		"health_initial": 0.0, "health_recovery_per_day": 0.0, "death_rate_max": 1.0}))
	var events := p.step(_flow(0, 0), _mods(), _rng())
	assert_eq(p.families, [])
	assert_eq(events.map(func(e: Dictionary) -> String: return e.type), ["death", "colony_empty"])
	assert_eq(p.step(_flow(0, 0), _mods(), _rng()), [], "colônia vazia avisa uma vez só")


func test_partida_apos_dias_seguidos_de_falta() -> void:
	var p := SimPopulation.new(CFG)
	var rng := _rng()
	assert_eq(p.step(_flow(0, 1.0), _mods(), rng), [])
	assert_eq(p.step(_flow(0, 1.0), _mods(), rng), [])
	var events := p.step(_flow(0, 1.0), _mods(), rng)
	assert_eq(events.size(), 1)
	assert_eq(events[0].type, "family_left")
	assert_eq(p.families.size(), 1)
	assert_eq(p.people(), 6 - events[0].size)
	assert_eq(p.shortage_streak, 0, "contador zera após a partida")


func test_dia_sem_falta_zera_a_sequencia() -> void:
	var p := SimPopulation.new(CFG)
	p.step(_flow(0, 1.0), _mods(), _rng())
	p.step(_flow(0, 1.0), _mods(), _rng())
	p.step(_flow(0, 0), _mods(), _rng())
	assert_eq(p.step(_flow(0, 1.0), _mods(), _rng()), [])
	assert_eq(p.families.size(), 2)


func test_mesma_semente_mesmas_perdas() -> void:
	var a := SimPopulation.new(_cfg({"health_initial": 0.0}))
	var b := SimPopulation.new(_cfg({"health_initial": 0.0}))
	var ra := _rng(9)
	var rb := _rng(9)
	var ea: Array = []
	var eb: Array = []
	for _i in 20:
		ea.append_array(a.step(_flow(10.0, 10.0), _mods(), ra))
		eb.append_array(b.step(_flow(10.0, 10.0), _mods(), rb))
	assert_eq(ea, eb)
	assert_eq(a.families, b.families)
