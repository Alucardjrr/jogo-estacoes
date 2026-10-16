extends GutTest
## Simulation + SimLoop: determinismo, fila de comandos e relógio de tempo real.


func _new_sim(seed_number: int = 7) -> Simulation:
	var sim := Simulation.new()
	assert_true(sim.setup(seed_number), "erros: %s" % [sim.data.errors])
	return sim


func _run(sim: Simulation, days: int) -> Array:
	# Consome o RNG a cada dia para provar que a sequência é reproduzível.
	var draws := []
	for _i in days:
		sim.step_day()
		draws.append(sim.loop.rng.randi())
	return draws


func test_mesma_semente_mesmo_resultado() -> void:
	var a := _new_sim(123)
	var b := _new_sim(123)
	assert_eq(_run(a, 500), _run(b, 500))
	assert_eq(a.snapshot(), b.snapshot())
	assert_eq(a.drain_events(), b.drain_events())


func test_sementes_diferentes_divergem() -> void:
	assert_ne(_run(_new_sim(1), 50), _run(_new_sim(2), 50))


func test_semente_padrao_vem_dos_dados() -> void:
	var sim := Simulation.new()
	assert_true(sim.setup())
	assert_eq(sim.loop.seed_value, sim.data.section("sim").default_seed)


func test_setup_com_dados_invalidos_nao_monta_sistemas() -> void:
	var sim := Simulation.new()
	assert_false(sim.setup(1, "user://pasta_que_nao_existe"))
	assert_false(sim.is_ready())
	assert_gt(sim.data.errors.size(), 0)


func test_snapshot_reflete_o_calendario() -> void:
	var sim := _new_sim()
	_run(sim, 95)
	var s := sim.snapshot()
	assert_eq([s.day, s.month, s.year, s.season, s.day_in_season, s.season_days],
		[6, 4, 1, "janela_1", 6, 90])


func test_eventos_sao_drenados_uma_vez() -> void:
	var sim := _new_sim()
	_run(sim, 90)
	var events := sim.drain_events()
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "season_changed").size(), 1)
	assert_eq(sim.drain_events(), [])


func test_comando_aplicado_no_inicio_do_tick() -> void:
	var sim := _new_sim()
	assert_true(sim.enqueue({"type": "nao_existe"}))
	assert_eq(sim.drain_events(), [], "comando não pode ser aplicado antes do tick")
	sim.step_day()
	var events := sim.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0].type, "command_rejected")


func test_comando_sem_tipo_e_recusado() -> void:
	var sim := _new_sim()
	assert_false(sim.enqueue({}))
	assert_false(sim.enqueue({"type": 5}))


# --- Relógio (3 s por dia nos dados do projeto) ---

func test_relogio_um_dia_a_cada_3s_em_1x() -> void:
	var sim := _new_sim()
	assert_eq(sim.advance(2.9, 1), 0)
	assert_eq(sim.advance(0.1, 1), 1)
	assert_eq(sim.calendar.day_index, 1)


func test_relogio_velocidades() -> void:
	var sim := _new_sim()
	assert_eq(sim.advance(3.0, 2), 2)
	assert_eq(sim.advance(3.0, 3), 3)


func test_relogio_pausado_nao_avanca() -> void:
	var sim := _new_sim()
	assert_eq(sim.advance(100.0, 0), 0)
	assert_eq(sim.calendar.day_index, 0)


func test_relogio_limita_dias_por_frame() -> void:
	var sim := _new_sim()
	assert_eq(sim.advance(1000.0, 3), sim.loop.max_days_per_frame)
	assert_eq(sim.advance(0.0, 3), 0, "excedente descartado, sem rajada depois")


func test_relogio_acumula_frames_pequenos() -> void:
	var sim := _new_sim()
	var days := 0
	for _i in 180:  # 3 s a 60 fps
		days += sim.advance(1.0 / 60.0, 1)
	assert_eq(days, 1)


# --- Season + Resources com os dados do projeto ---

func _shortages(events: Array[Dictionary], resource: String) -> int:
	return events.filter(func(e: Dictionary) -> bool:
		return e.type == "shortage" and e.resource == resource).size()


func test_ano_1_sem_jogador_sobrevive_sem_falta() -> void:
	var sim := _new_sim()
	_run(sim, 359)  # até o último dia do ano 1
	assert_eq(sim.calendar.year(), 1)
	var events := sim.drain_events()
	assert_eq(_shortages(events, "water"), 0)
	assert_eq(_shortages(events, "food"), 0)


func test_ano_2_sem_jogador_falta_comida_na_seca() -> void:
	var sim := _new_sim()
	_run(sim, 359)
	sim.drain_events()
	_run(sim, 90)  # seca do ano 2
	assert_eq(sim.calendar.season_id(), "seca")
	var cfg: Dictionary = sim.data.section("season")
	assert_almost_eq(sim.snapshot().intensity, 1.0 + cfg.intensity_per_year, 1e-9)
	var events := sim.drain_events()
	assert_gt(_shortages(events, "food") + _shortages(events, "water"), 0,
		"linha de base precisa quebrar no ano 2")


func test_transicao_gradual_entre_estacoes() -> void:
	var sim := _new_sim()
	var seasons: Dictionary = sim.data.section("season").seasons
	var half: int = sim.data.section("season").transition_days / 2
	var inflows: Array[float] = []
	for _i in 90 + half + 5:  # da seca até depois do fim da transição
		sim.step_day()
		inflows.append(sim.modifiers.value("water_inflow") - _labor_part(sim, "water_inflow"))
	var start := 90 - half - 1  # índice do 1º dia da transição (inflows[0] = dia 1)
	assert_eq(inflows[start - 1], seasons.seca.water_inflow, "antes da transição: seca pura")
	for i in range(start, 90 + half - 1):
		assert_gt(inflows[i], inflows[i - 1], "sobe aos poucos (dia %d)" % i)
		assert_lt(inflows[i], seasons.janela_1.water_inflow)
	assert_eq(inflows[-1], seasons.janela_1.water_inflow, "depois da transição: janela pura")


## Parte de um modificador publicada pela mão de obra (para isolar a da estação).
func _labor_part(sim: Simulation, key: String) -> float:
	var total := 0.0
	for e in sim.modifiers.entries():
		if e.key == key and e.source == SimLabor.SOURCE:
			total += e.add
	return total


func test_snapshot_de_recursos_e_modificadores() -> void:
	var sim := _new_sim()
	var s := sim.snapshot()
	assert_eq(s.population, 50)
	assert_eq(s.families, 12)
	assert_eq(s.health, 80.0)
	assert_eq(s.resources.water.stock, 4500.0)
	assert_eq(s.resources.water.capacity, 6000.0)
	assert_eq(s.modifiers.size(), DataRegistry.SEASON_KEYS.size() + 3, "estação + mão de obra do dia 1")
	assert_eq(s.labor.desired, sim.data.section("labor").initial_allocation)
	_run(sim, 1)
	assert_eq(sim.snapshot().resources.food.consumed, 50.0)


func test_recursos_deterministicos() -> void:
	var a := _new_sim(5)
	var b := _new_sim(5)
	_run(a, 1000)
	_run(b, 1000)
	assert_eq(a.snapshot().resources, b.snapshot().resources)


func test_setup_reinicia_recursos() -> void:
	var sim := _new_sim()
	_run(sim, 100)
	assert_true(sim.setup(7))
	assert_eq(sim.resources.stock.water, 4500.0)
	assert_eq(sim.modifiers.entries().size(), DataRegistry.SEASON_KEYS.size() + 3)
	assert_false(sim.labor.changed)


# --- Population com os dados do projeto ---

func test_ano_2_sem_jogador_familias_vao_embora_na_seca() -> void:
	var sim := _new_sim()
	_run(sim, 359)
	assert_eq(sim.snapshot().population, 50, "ano 1 sem perdas")
	sim.drain_events()
	_run(sim, 90)
	var left := sim.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "family_left")
	assert_gt(left.size(), 0)
	assert_lt(sim.snapshot().population, 50)
	assert_lt(sim.snapshot().health, 80.0)


func test_chuvas_derrubam_a_saude() -> void:
	var sim := _new_sim()
	_run(sim, 180)  # fim da janela_1: saúde no teto
	sim.enqueue({"type": "set_labor", "task": "care", "value": 0})  # sem cuidado, a doença aparece
	var before: float = sim.snapshot().health
	_run(sim, 90)  # chuvas
	assert_lt(sim.snapshot().health, before)


func test_falta_de_agua_mata() -> void:
	var sim := _new_sim()
	sim.resources.stock.water = 0.0
	_run(sim, 60)
	var deaths := sim.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "death")
	assert_gt(deaths.size(), 0)


func test_consumo_acompanha_a_populacao() -> void:
	var sim := _new_sim()
	sim.population.families.pop_back()  # 3 pessoas a menos
	_run(sim, 1)
	assert_eq(sim.snapshot().resources.food.demand, 47.0)


func test_populacao_deterministica() -> void:
	var a := _new_sim(11)
	var b := _new_sim(11)
	a.resources.stock.water = 0.0
	b.resources.stock.water = 0.0
	_run(a, 400)
	_run(b, 400)
	assert_eq(a.population.families, b.population.families)
	assert_eq(a.drain_events(), b.drain_events())
