extends GutTest
## Campanha com prazo (D-046, D-047): desfecho por faixa, aviso do último ano, bloqueio
## final de medidas, fim no último dia (ou com a colônia vazia) e simulação parada depois.


func _sim() -> Simulation:
	var sim := Simulation.new()
	assert_true(sim.setup(1))
	return sim


func _of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func test_faixas_por_fracao_da_inicial() -> void:
	var c := _sim().campaign
	assert_eq(c.initial, 50)
	assert_eq(c.outcome_for(0), "cai")
	assert_eq(c.outcome_for(14), "cai")
	assert_eq(c.outcome_for(15), "resistiu")
	assert_eq(c.outcome_for(29), "resistiu")
	assert_eq(c.outcome_for(30), "de_pe")
	assert_eq(c.outcome_for(39), "de_pe")
	assert_eq(c.outcome_for(40), "terra_boa")
	assert_eq(c.outcome_for(50), "terra_boa")


func test_bloqueio_final_vem_dos_dados() -> void:
	var sim := _sim()
	var longest := 0
	for m in sim.data.section("social").measures.values():
		longest = maxi(longest, m.after_days)
	assert_gt(longest, 0)
	assert_eq(sim.campaign.lock_days, longest)


func test_aviso_do_ultimo_ano_e_fala_do_morador_da_campanha() -> void:
	var sim := _sim()
	var years: int = sim.campaign.years
	sim.calendar.day_index = (years - 1) * sim.calendar.days_per_year() - 1
	sim.step_day()
	var ev := sim.drain_events()
	assert_eq(sim.calendar.year(), years)
	assert_eq(_of(ev, "campaign_final_year").size(), 1)
	var speech := _of(ev, "speech")
	assert_eq(speech.size(), 1)
	assert_true(String(speech[0].key).begins_with("REACT_CAMPAIGN_FINAL_YEAR_"), speech[0].key)
	assert_eq(speech[0].resident, "RESIDENT_%02d" % sim.data.section("narrative").campaign_resident)
	assert_true(sim.snapshot().campaign.final_year)


func test_medidas_bloqueadas_no_fim() -> void:
	var sim := _sim()
	var last := sim.campaign.last_day(sim.calendar)
	# Fora do bloqueio: o motivo é outro (estação), nunca o da campanha.
	sim.calendar.day_index = last - sim.campaign.lock_days - 1
	sim.enqueue({"type": "enact_measure", "measure": "racionamento"})
	sim.step_day()
	assert_eq(_of(sim.drain_events(), "command_rejected")[0].reason, "wrong_season")
	assert_false(sim.snapshot().campaign.measures_locked)
	# Primeiro dia do bloqueio: até a de desespero com a água no fundo é recusada.
	sim.resources.stock.water = 0.0
	sim.enqueue({"type": "enact_measure", "measure": "confisco"})
	sim.step_day()
	var rej := _of(sim.drain_events(), "command_rejected")
	assert_eq(rej.size(), 1)
	assert_eq(rej[0].reason, "campaign_final")
	assert_eq(sim.campaign.days_left(sim.calendar), sim.campaign.lock_days)
	assert_eq(sim.social.uses, {})


func test_fim_no_ultimo_dia_e_simulacao_parada() -> void:
	var sim := _sim()
	var last := sim.campaign.last_day(sim.calendar)
	sim.calendar.day_index = last - 2
	sim.step_day()
	assert_eq(_of(sim.drain_events(), "campaign_ended").size(), 0)
	sim.step_day()
	var ev := sim.drain_events()
	assert_eq(sim.calendar.day_index, last)
	var ended := _of(ev, "campaign_ended")
	assert_eq(ended.size(), 1)
	var s: Dictionary = ended[0].summary
	assert_eq(s.population, sim.population.people())
	assert_eq(ended[0].outcome, sim.campaign.outcome_for(s.population))
	var diary := _of(ev, "diary").filter(func(e: Dictionary) -> bool: return e.mood == "END")
	assert_eq(diary.size(), 1)
	assert_eq(diary[0].key, "DIARY_END_" + String(ended[0].outcome).to_upper())
	# Depois do fim, nada muda e o relógio não conta mais dias.
	var before := sim.snapshot()
	sim.enqueue({"type": "set_labor", "task": "water", "value": 3})
	sim.step_day()
	assert_eq(sim.drain_events(), [])
	assert_eq(sim.snapshot(), before)
	assert_eq(sim.advance(100.0, 3), 0)
	assert_true(before.campaign.ended)


func test_colonia_vazia_encerra() -> void:
	var sim := _sim()
	sim.population.families.clear()  # última família se foi: Population avisa colony_empty
	sim.step_day()
	var ev := sim.drain_events()
	assert_eq(_of(ev, "colony_empty").size(), 1)
	assert_eq(_of(ev, "campaign_ended").size(), 1)
	assert_true(sim.campaign.ended)
	assert_eq(sim.campaign.outcome, "cai")
	assert_eq(sim.population.people(), 0)


func test_populacao_por_ano_e_maior_perda() -> void:
	var c := SimCampaign.new({"years": 3, "outcomes": [{"id": "a"}, {"id": "b", "from": 0.5}]},
		{"measures": {}}, 50)
	c.pop_by_year.assign([40, 20, 18])
	c.ended = true
	var s := c.summary()
	assert_eq(s.worst_year, 2)
	assert_eq(s.worst_lost, 20)
	assert_eq(s.population, 18)
