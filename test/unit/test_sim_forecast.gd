extends GutTest
## SimForecast (D-042): sorteio no RNG único, ano 1 conhecido, teto do D-025 sobre a
## efetiva, faixa honesta que encolhe, níveis, determinismo.


func _sim(seed_number: int = 1) -> Simulation:
	var sim := Simulation.new()
	assert_true(sim.setup(seed_number))
	return sim


func test_tabela_cobre_ano_corrente_e_o_seguinte() -> void:
	var sim := _sim()
	assert_true(sim.forecast.table.has("1/seca") and sim.forecast.table.has("2/chuvas"))
	assert_false(sim.forecast.table.has("3/seca"))
	sim.calendar.day_index = 359
	sim.step_day()  # vira o ano 2
	assert_true(sim.forecast.table.has("3/seca"), "sorteia o ano seguinte na virada")


func test_ano_1_conhecido_e_fatores_na_faixa() -> void:
	for s in 10:
		var sim := _sim(s + 1)
		var cfg: Dictionary = sim.data.section("forecast")
		assert_eq(sim.forecast.table["1/seca"].f, 1.0)
		assert_eq(sim.forecast.table["1/chuvas"].f, 1.0)
		for k in sim.forecast.table:
			var f: float = sim.forecast.table[k].f
			assert_between(f, 1.0 - cfg.variance, 1.0 + cfg.variance, k)


func test_teto_sobre_a_intensidade_efetiva() -> void:
	var sim := _sim()
	sim.season.factors = {"9/seca": 1.5}
	assert_eq(sim.season.intensity_for(9, "seca"), sim.data.section("season").intensity_max)


func test_valor_real_sempre_dentro_da_faixa() -> void:
	for s in 5:
		var sim := _sim(s + 1)
		for _d in 720:
			var f: Dictionary = sim.forecast.forecast(sim.calendar, sim.season, true)
			if not f.now:
				assert_true(f.low <= f.real and f.real <= f.high,
					"semente %d dia %d: %.3f fora de [%.3f, %.3f]" % [s + 1, sim.calendar.day_index, f.real, f.low, f.high])
				if not (f.low <= f.real and f.real <= f.high):
					return
			sim.step_day()


func test_faixa_encolhe_com_a_proximidade() -> void:
	var sim := _sim()
	sim.calendar.day_index = 90  # início da janela_1: chuvas em 90 dias
	var far: Dictionary = sim.forecast.forecast(sim.calendar, sim.season)
	sim.calendar.day_index = 175
	var near: Dictionary = sim.forecast.forecast(sim.calendar, sim.season)
	assert_eq(far.season, "chuvas")
	assert_gt(far.high - far.low, near.high - near.low)


func test_durante_a_severa_mostra_o_real() -> void:
	var sim := _sim()
	sim.calendar.day_index = 400  # seca do ano 2
	var f: Dictionary = sim.forecast.forecast(sim.calendar, sim.season)
	assert_true(f.now)
	assert_eq(f.intensity, sim.season.intensity(sim.calendar))


func test_niveis() -> void:
	var sim := _sim()
	assert_eq(sim.forecast.level(1.0), "branda")
	assert_eq(sim.forecast.level(1.3), "dura")
	assert_eq(sim.forecast.level(1.45), "implacavel")


func test_mesma_semente_mesmo_clima() -> void:
	assert_eq(_sim(7).forecast.table, _sim(7).forecast.table)
	assert_ne(_sim(7).forecast.table, _sim(8).forecast.table)


func test_previsao_na_tela_traduzida() -> void:
	var hud: Control = preload("res://scenes/debug/debug_hud.tscn").instantiate()
	add_child_autofree(hud)
	var sim := _sim()
	sim.calendar.day_index = 100
	var text: String = hud.forecast_text(sim.forecast.forecast(sim.calendar, sim.season))
	assert_false(text.contains("{") or text.contains("FORECAST_") or text.contains("HUD_"), text)


func test_snapshot_nao_entrega_o_valor_real_futuro() -> void:
	var sim := _sim()
	sim.calendar.day_index = 100
	assert_false(sim.snapshot().forecast.has("real"))


func test_ordem_do_rng_no_setup() -> void:
	# O clima dos anos 1 e 2 é o primeiro uso do RNG: refazendo à mão, mesma tabela.
	var sim := _sim(42)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var f := SimForecast.new(sim.data.section("forecast"), sim.data.section("calendar"))
	f.draw_year(1, rng)
	f.draw_year(2, rng)
	assert_eq(f.table, sim.forecast.table)
	assert_eq(rng.state, sim.loop.rng.state, "nada mais usou o RNG no setup")


func test_sorteio_da_virada_antes_da_populacao() -> void:
	# No tick da virada, o ano seguinte é sorteado antes de Population usar o RNG.
	var sim := _sim(5)
	sim.calendar.day_index = 359
	var rng := RandomNumberGenerator.new()
	rng.seed = sim.loop.rng.seed
	rng.state = sim.loop.rng.state  # estado no início do tick da virada
	var f := SimForecast.new(sim.data.section("forecast"), sim.data.section("calendar"))
	f.draw_year(3, rng)
	sim.step_day()
	assert_eq(sim.forecast.table["3/seca"], f.table["3/seca"])
	assert_eq(sim.forecast.table["3/chuvas"], f.table["3/chuvas"])


func test_calendario_sem_severas_e_com_uma_so() -> void:
	var cal_none := {"days_per_month": 30, "months_per_year": 12, "seasons": [
		{"id": "janela", "months": 12, "severe": false}]}
	var cfg: Dictionary = _sim().data.section("forecast")
	var c := SimCalendar.new(cal_none)
	var season := SimSeason.new({"intensity_per_year": 0.3, "intensity_max": 2.0, "transition_days": 0,
		"seasons": {"janela": {"water_inflow": 1.0, "water_loss_rate": 0.0, "food_inflow": 1.0,
			"food_loss_rate": 0.0, "health_drift": 0.0, "gather_mult": 1.0, "farm_mult": 1.0, "escalation": {}}}})
	assert_eq(SimForecast.new(cfg, cal_none).forecast(c, season), {})
	var cal_one := {"days_per_month": 30, "months_per_year": 12, "seasons": [
		{"id": "seca", "months": 3, "severe": true}, {"id": "janela", "months": 9, "severe": false}]}
	var c1 := SimCalendar.new(cal_one)
	c1.day_index = 200
	var s1 := SimSeason.new({"intensity_per_year": 0.3, "intensity_max": 2.0, "transition_days": 0,
		"seasons": {"seca": {"water_inflow": 1.0, "water_loss_rate": 0.0, "food_inflow": 1.0,
			"food_loss_rate": 0.0, "health_drift": 0.0, "gather_mult": 1.0, "farm_mult": 1.0, "escalation": {}},
			"janela": {"water_inflow": 1.0, "water_loss_rate": 0.0, "food_inflow": 1.0,
			"food_loss_rate": 0.0, "health_drift": 0.0, "gather_mult": 1.0, "farm_mult": 1.0, "escalation": {}}}})
	var fc := SimForecast.new(cfg, cal_one)
	var rng := RandomNumberGenerator.new()
	fc.draw_year(1, rng)
	fc.draw_year(2, rng)
	s1.factors = fc.factors()
	var out := fc.forecast(c1, s1, true)
	assert_eq(out.season, "seca")
	assert_eq(out.days, 160, "seca do ano seguinte")
	assert_true(out.low <= out.real and out.real <= out.high)
