extends GutTest
## SimSeason: intensidade só nas severas, escalada anual com teto, expoentes.

const CAL := {"days_per_month": 30, "months_per_year": 12, "seasons": [
	{"id": "seca", "months": 6, "severe": true},
	{"id": "janela", "months": 6, "severe": false}]}
const CFG := {"intensity_per_year": 0.5, "intensity_max": 2.0, "transition_days": 0, "seasons": {
	"seca": {"water_inflow": 10.0, "water_loss_rate": 0.01, "food_inflow": 20.0,
		"food_loss_rate": 0.0, "health_drift": -0.5,
		"escalation": {"water_inflow": -1.0, "water_loss_rate": 1.0, "health_drift": 1.0}},
	"janela": {"water_inflow": 50.0, "water_loss_rate": 0.0, "food_inflow": 60.0,
		"food_loss_rate": 0.0, "health_drift": 0.0, "escalation": {"water_inflow": 1.0}}}}


func _cal(year: int, severe: bool) -> SimCalendar:
	var c := SimCalendar.new(CAL)
	c.day_index = (year - 1) * 360 + (0 if severe else 180)
	return c


func test_ano_1_intensidade_1() -> void:
	var s := SimSeason.new(CFG)
	assert_eq(s.intensity(_cal(1, true)), 1.0)
	assert_eq(s.rate(_cal(1, true), "water_inflow"), 10.0)


func test_escalada_anual_e_expoentes() -> void:
	var s := SimSeason.new(CFG)
	var c := _cal(2, true)
	assert_almost_eq(s.intensity(c), 1.5, 1e-9)
	assert_almost_eq(s.rate(c, "water_inflow"), 10.0 / 1.5, 1e-9)
	assert_almost_eq(s.rate(c, "water_loss_rate"), 0.015, 1e-9)
	assert_eq(s.rate(c, "food_inflow"), 20.0, "sem expoente não escala")
	assert_almost_eq(s.rate(c, "health_drift"), -0.75, 1e-9, "negativo escala para pior")


func test_teto_da_intensidade() -> void:
	var s := SimSeason.new(CFG)
	assert_eq(s.intensity(_cal(3, true)), 2.0)
	assert_eq(s.intensity(_cal(10, true)), 2.0)


func test_estacao_branda_nao_escala_mesmo_com_expoente() -> void:
	var s := SimSeason.new(CFG)
	var c := _cal(5, false)
	assert_eq(s.intensity(c), 1.0)
	assert_eq(s.rate(c, "water_inflow"), 50.0)


func test_publish_substitui_os_valores_anteriores() -> void:
	var s := SimSeason.new(CFG)
	var m := ModifierStack.new()
	m.mul("water_inflow", "outro", 0.5)
	s.publish(_cal(1, true), m)
	s.publish(_cal(1, false), m)
	assert_eq(m.value("water_inflow"), 25.0, "50 da janela × 0,5 de outra fonte, sem acumular")
	assert_eq(m.entries().size(), DataRegistry.SEASON_KEYS.size() + 1)



# --- Transição (D-027) ---

func _blend(days: int) -> SimSeason:
	var cfg := CFG.duplicate(true)
	cfg.transition_days = days
	return SimSeason.new(cfg)


func _at(day: int) -> SimCalendar:
	var c := SimCalendar.new(CAL)
	c.day_index = day
	return c


func test_fora_da_transicao_valor_puro() -> void:
	var s := _blend(20)
	assert_eq(s.rate(_at(100), "water_inflow"), 10.0)
	assert_eq(s.rate(_at(169), "water_inflow"), 10.0, "último dia antes da janela de transição")
	assert_eq(s.rate(_at(190), "water_inflow"), 50.0)


func test_primeiro_dia_do_jogo_nao_mistura() -> void:
	assert_eq(_blend(20).rate(_at(0), "water_inflow"), 10.0)


func test_transicao_simetrica_na_virada() -> void:
	# último dia da seca + 1º da janela = soma das duas taxas (smoothstep é simétrica)
	var s := _blend(20)
	assert_almost_eq(s.rate(_at(179), "water_inflow") + s.rate(_at(180), "water_inflow"), 60.0, 1e-9)


func test_transicao_monotona_e_dentro_dos_limites() -> void:
	var s := _blend(20)
	var last := s.rate(_at(169), "water_inflow")
	for d in range(170, 190):
		var v := s.rate(_at(d), "water_inflow")
		assert_gt(v, last, "dia %d" % d)
		assert_lt(v, 50.0)
		last = v


func test_transicao_na_virada_do_ano_usa_intensidade_do_ano_novo() -> void:
	# janela (ano 1) → seca (ano 2, intensidade 1,5: entrada 10/1,5).
	var s := _blend(20)
	var first_dry := 10.0 / 1.5
	assert_almost_eq(s.rate(_at(359), "water_inflow") + s.rate(_at(360), "water_inflow"),
		50.0 + first_dry, 1e-9)
	assert_almost_eq(s.rate(_at(370), "water_inflow"), first_dry, 1e-9)


func test_transicao_zero_e_brusca() -> void:
	var s := _blend(0)
	assert_eq(s.rate(_at(179), "water_inflow"), 10.0)
	assert_eq(s.rate(_at(180), "water_inflow"), 50.0)


func test_estacoes_de_tamanhos_diferentes_continuas() -> void:
	# seca 30 dias, janela 330; T = 30 (igual à mais curta): seca nunca fica pura.
	var cal := {"days_per_month": 30, "months_per_year": 12, "seasons": [
		{"id": "seca", "months": 1, "severe": true}, {"id": "janela", "months": 11, "severe": false}]}
	var cfg := CFG.duplicate(true)
	cfg.transition_days = 30
	var s := SimSeason.new(cfg)
	var c := SimCalendar.new(cal)
	var values: Array[float] = []
	for d in range(345, 405):  # fim da janela do ano 1 até depois da seca do ano 2
		c.day_index = d
		values.append(s.rate(c, "water_inflow"))
	for v in values:
		assert_between(v, 10.0 / 1.5 - 1e-9, 50.0 + 1e-9)
	for i in range(1, 30):
		assert_lt(values[i], values[i - 1] + 1e-9, "desce até o meio da seca (i=%d)" % i)
	for i in range(31, 60):
		assert_gt(values[i], values[i - 1] - 1e-9, "sobe depois do meio (i=%d)" % i)


func test_calendario_de_uma_estacao_so() -> void:
	var cal := {"days_per_month": 30, "months_per_year": 12, "seasons": [
		{"id": "seca", "months": 12, "severe": true}]}
	var cfg := CFG.duplicate(true)
	cfg.seasons = {"seca": CFG.seasons.seca}
	cfg.transition_days = 20
	var s := SimSeason.new(cfg)
	var c := SimCalendar.new(cal)
	c.day_index = 100
	assert_eq(s.rate(c, "water_inflow"), 10.0)
	c.day_index = 359
	var before := s.rate(c, "water_inflow")
	c.day_index = 360
	var after := s.rate(c, "water_inflow")
	assert_almost_eq(before + after, 10.0 + 10.0 / 1.5, 1e-9, "escalada anual vira rampa")
