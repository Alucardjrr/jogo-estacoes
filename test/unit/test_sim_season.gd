extends GutTest
## SimSeason: intensidade só nas severas, escalada anual com teto, expoentes.

const CAL := {"days_per_month": 30, "months_per_year": 12, "seasons": [
	{"id": "seca", "months": 6, "severe": true},
	{"id": "janela", "months": 6, "severe": false}]}
const CFG := {"intensity_per_year": 0.5, "intensity_max": 2.0, "seasons": {
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
