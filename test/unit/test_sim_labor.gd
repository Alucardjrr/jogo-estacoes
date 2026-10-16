extends GutTest
## SimLabor: trabalhadores, corte proporcional, produtividade, produção, cuidado,
## fadiga; comandos set_labor/adjust_labor na Simulation.

const CFG := {"worker_share": 0.6, "full_productivity_health": 60.0, "min_productivity": 0.5,
	"water_per_worker": 2.5, "food_per_worker": 3.5, "care_health_per_share": 10.0,
	"care_health_max": 2.0, "fatigue_threshold": 0.5, "fatigue_health": 0.4,
	"initial_allocation": {"water": 9, "farm": 18, "care": 3}}


func _mods(gather: float = 1.0, farm: float = 1.0) -> ModifierStack:
	var m := ModifierStack.new()
	m.add("gather_mult", "season", gather)
	m.add("farm_mult", "season", farm)
	return m


func _labor_value(m: ModifierStack, key: String) -> float:
	var v := 0.0
	for e in m.entries():
		if e.key == key and e.source == SimLabor.SOURCE:
			v += e.add
	return v


func _lab(alloc: Dictionary = {}) -> SimLabor:
	var cfg := CFG.duplicate(true)
	cfg.initial_allocation.merge(alloc, true)
	return SimLabor.new(cfg)


func test_trabalhadores_e_producao_basica() -> void:
	var l := _lab()
	var m := _mods(0.9, 0.2)
	l.step(50, 100.0, m)
	assert_eq(l.workers, 30)
	assert_almost_eq(_labor_value(m, "water_inflow"), 9 * 2.5 * 0.9, 1e-9)
	assert_almost_eq(_labor_value(m, "food_inflow"), 18 * 3.5 * 0.2, 1e-9)
	assert_almost_eq(_labor_value(m, "health_drift"), 10.0 * 3 / 50, 1e-9)
	assert_eq(l.idle(), 0.0)


func test_trabalhadores_arredonda_para_baixo() -> void:
	var l := _lab()
	l.step(49, 100.0, _mods())  # 29,4 → 29
	assert_eq(l.workers, 29)


func test_corte_proporcional_quando_falta_gente() -> void:
	var l := _lab()
	var m := _mods()
	l.step(25, 100.0, m)  # 15 trabalhadores para 30 pedidos → metade
	assert_almost_eq(l.assigned.water, 4.5, 1e-9)
	assert_almost_eq(l.assigned.farm, 9.0, 1e-9)
	assert_almost_eq(_labor_value(m, "water_inflow"), 4.5 * 2.5, 1e-9)
	assert_eq(l.desired.water, 9, "o pedido do jogador não muda")


func test_ociosos() -> void:
	var l := _lab({"water": 5, "farm": 5, "care": 0})
	l.step(50, 100.0, _mods())
	assert_eq(l.idle(), 20.0)


func test_produtividade_cai_com_a_saude() -> void:
	var l := _lab()
	l.step(50, 60.0, _mods())
	assert_eq(l.productivity, 1.0, "no limiar ainda é 100%")
	l.step(50, 30.0, _mods())
	assert_almost_eq(l.productivity, 0.75, 1e-9)
	var m := _mods()
	l.step(50, 0.0, m)
	assert_almost_eq(l.productivity, 0.5, 1e-9)
	assert_almost_eq(_labor_value(m, "water_inflow"), 9 * 2.5 * 0.5, 1e-9)


func test_cuidado_tem_teto() -> void:
	var l := _lab({"water": 0, "farm": 0, "care": 30})
	var m := _mods()
	l.step(50, 100.0, m)
	assert_eq(_labor_value(m, "health_drift"), 2.0)


func test_sem_pessoas_nao_divide_por_zero() -> void:
	var l := _lab()
	var m := _mods()
	l.step(0, 0.0, m)
	assert_eq(l.workers, 0)
	assert_eq(_labor_value(m, "health_drift"), 0.0)
	assert_eq(_labor_value(m, "water_inflow"), 0.0)


func test_fadiga_acima_do_limiar_na_agua() -> void:
	var l := _lab({"water": 27, "farm": 0, "care": 3})
	var m := _mods()
	l.step(50, 100.0, m)
	# fração 0,9 → excesso 0,4/0,5 = 0,8 → −0,32; cuidado +0,6
	assert_almost_eq(_labor_value(m, "health_drift"), 0.6 - 0.32, 1e-9)


func test_fadiga_usa_alocacao_real_apos_corte() -> void:
	# 30 na água pedidos, 15 trabalhadores: fração real 100% (não 200%)
	var l := _lab({"water": 30, "farm": 0, "care": 0})
	var m := _mods()
	l.step(25, 100.0, m)
	assert_almost_eq(_labor_value(m, "health_drift"), -0.4, 1e-9)


func test_fadiga_nao_cai_com_produtividade() -> void:
	# saúde baixa reduz produção, não a carga: fadiga igual
	var a := _mods()
	var b := _mods()
	_lab({"water": 27, "farm": 0, "care": 0}).step(50, 100.0, a)
	_lab({"water": 27, "farm": 0, "care": 0}).step(50, 0.0, b)
	assert_almost_eq(_labor_value(a, "health_drift"), _labor_value(b, "health_drift"), 1e-9)


func test_publicacao_substitui_a_anterior() -> void:
	var l := _lab()
	var m := _mods()
	l.step(50, 100.0, m)
	l.step(50, 100.0, m)
	assert_almost_eq(_labor_value(m, "water_inflow"), 9 * 2.5, 1e-9)


# --- Comandos ---

func _sim() -> Simulation:
	var s := Simulation.new()
	assert_true(s.setup(1))
	return s


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> String: return e.type)


func test_set_labor_vale_no_proximo_tick() -> void:
	var s := _sim()
	s.enqueue({"type": "set_labor", "task": "water", "value": 20})
	assert_eq(s.labor.desired.water, 9, "nada muda antes do tick")
	s.step_day()
	assert_eq(s.labor.desired.water, 20)
	assert_true(s.labor.changed)
	assert_true(_types(s.drain_events()).has("labor_changed"))


func test_adjust_labor_soma_e_compoe() -> void:
	var s := _sim()
	s.enqueue({"type": "adjust_labor", "task": "farm", "delta": -3})
	s.enqueue({"type": "adjust_labor", "task": "farm", "delta": -2})
	s.step_day()
	assert_eq(s.labor.desired.farm, 13)


func test_comandos_invalidos_recusados() -> void:
	var s := _sim()
	for cmd in [
		{"type": "set_labor", "task": "pesca", "value": 1},
		{"type": "set_labor", "task": "water", "value": -1},
		{"type": "set_labor", "task": "water", "value": 2.5},
		{"type": "set_labor", "task": "water", "value": "10"},
		{"type": "set_labor", "task": "water"},
		{"type": "adjust_labor", "task": "care", "delta": -4},
		{"type": "set_labor", "value": 3},
	]:
		s.enqueue(cmd)
	s.step_day()
	var events := s.drain_events()
	assert_eq(_types(events).count("command_rejected"), 7)
	assert_eq(s.labor.desired, {"water": 9, "farm": 18, "care": 3})
	assert_false(s.labor.changed)


func test_valor_inteiro_vindo_como_float_e_aceito() -> void:
	var s := _sim()
	s.enqueue({"type": "set_labor", "task": "care", "value": 6.0})  # JSON/replay
	s.step_day()
	assert_eq(s.labor.desired.care, 6)


func test_adjust_labor_float_inteiro_e_valores_estranhos() -> void:
	var s := _sim()
	s.enqueue({"type": "adjust_labor", "task": "care", "delta": 2.0})
	s.enqueue({"type": "adjust_labor", "task": "care", "delta": NAN})
	s.enqueue({"type": "adjust_labor", "task": "care", "delta": INF})
	s.step_day()
	assert_eq(s.labor.desired.care, 5)
	assert_eq(_types(s.drain_events()).count("command_rejected"), 2)


func test_set_labor_zero_e_aceito() -> void:
	var s := _sim()
	s.enqueue({"type": "set_labor", "task": "water", "value": 0})
	s.step_day()
	assert_eq(s.labor.desired.water, 0)


func test_labor_le_estado_do_fim_do_dia_anterior() -> void:
	# Se a população cair hoje, a produção de hoje ainda usa os trabalhadores de ontem.
	var s := _sim()
	s.step_day()
	var before: int = s.labor.workers
	s.population.families.clear()  # todos saem "durante" o dia seguinte, depois do Labor
	s.step_day()
	assert_eq(s.labor.workers, 0, "Labor do novo dia já vê a colônia vazia")
	assert_eq(before, 30)
