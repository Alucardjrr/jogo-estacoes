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
			var f: Dictionary = sim.forecast.forecast(sim.calendar, sim.season)
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
