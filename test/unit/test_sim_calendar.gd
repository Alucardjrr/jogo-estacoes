extends GutTest
## SimCalendar: datas, viradas de estação e de ano com o calendário real do projeto.

var cal: SimCalendar


func before_each() -> void:
	var reg := DataRegistry.new()
	assert_true(reg.load_all())
	cal = SimCalendar.new(reg.section("calendar"))


func _advance(days: int) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for _i in days:
		all.append_array(cal.advance())
	return all


func _of_type(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func test_comeca_no_dia_1_de_janeiro_ano_1_na_seca() -> void:
	assert_eq([cal.day_of_month(), cal.month(), cal.year()], [1, 1, 1])
	assert_eq(cal.season_id(), "seca")
	assert_eq(cal.day_in_season(), 1)
	assert_eq(cal.season_length_days(), 90)
	assert_true(cal.season_is_severe())


func test_virada_de_mes() -> void:
	_advance(29)
	assert_eq([cal.day_of_month(), cal.month()], [30, 1])
	_advance(1)
	assert_eq([cal.day_of_month(), cal.month()], [1, 2])
	assert_eq(cal.day_in_season(), 31)


func test_seca_dura_90_dias_e_vira_janela() -> void:
	var events := _advance(89)
	assert_eq(_of_type(events, "season_changed").size(), 0)
	assert_eq(cal.day_in_season(), 90)
	events = _advance(1)
	assert_eq(events, [{"type": "season_changed", "from": "seca", "to": "janela_1", "year": 1}])
	assert_eq(cal.month(), 4)
	assert_false(cal.season_is_severe())


func test_ordem_das_estacoes_no_ano() -> void:
	var events := _of_type(_advance(360), "season_changed")
	var seq := events.map(func(e: Dictionary) -> String: return e.to)
	assert_eq(seq, ["janela_1", "chuvas", "janela_2", "seca"])


func test_virada_de_ano() -> void:
	var events := _advance(359)
	assert_eq(_of_type(events, "year_changed").size(), 0)
	events = _advance(1)
	assert_eq(_of_type(events, "year_changed"), [{"type": "year_changed", "year": 2}])
	assert_eq([cal.day_of_month(), cal.month(), cal.year(), cal.season_id()], [1, 1, 2, "seca"])


func test_tres_anos_geram_tres_viradas_e_doze_estacoes() -> void:
	var events := _advance(360 * 3)
	assert_eq(_of_type(events, "year_changed").size(), 3)
	assert_eq(_of_type(events, "season_changed").size(), 12)
	assert_eq(cal.year(), 4)


func test_estado_e_so_o_day_index() -> void:
	cal.day_index = 360 + 150  # ano 2, dia 151 do ano
	assert_eq([cal.day_of_month(), cal.month(), cal.year()], [1, 6, 2])
	assert_eq(cal.season_id(), "janela_1")
	assert_eq(cal.day_in_season(), 61)


func test_ano_com_uma_estacao_ainda_emite_virada_de_estacao() -> void:
	var one := SimCalendar.new({"days_per_month": 10, "months_per_year": 1,
		"seasons": [{"id": "unica", "months": 1, "severe": false}]})
	var events: Array[Dictionary] = []
	for _i in 10:
		events.append_array(one.advance())
	assert_eq(_of_type(events, "season_changed").size(), 1)
	assert_eq(_of_type(events, "year_changed").size(), 1)
