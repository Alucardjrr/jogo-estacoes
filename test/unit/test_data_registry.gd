extends GutTest
## DataRegistry: dados reais carregam; dados inválidos são recusados com erro claro, sem travar.

const TMP_DIR := "user://test_data_registry"

const SIM_OK := {"seconds_per_day": 3.0, "speeds": [1, 2, 3],
	"max_days_per_frame": 10, "default_seed": 42}
const CAL_OK := {"days_per_month": 30, "months_per_year": 12, "seasons": [
	{"id": "seca", "months": 6, "severe": true},
	{"id": "chuvas", "months": 6, "severe": true}]}


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)


func after_each() -> void:
	for f in DirAccess.get_files_at(TMP_DIR):
		DirAccess.remove_absolute(TMP_DIR.path_join(f))


func _write(name: String, content: Variant) -> void:
	var text: String = content if content is String else JSON.stringify(content)
	var f := FileAccess.open(TMP_DIR.path_join(name), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _load_with(sim: Variant, cal: Variant) -> DataRegistry:
	_write("sim.json", sim)
	_write("calendar.json", cal)
	var reg := DataRegistry.new()
	reg.load_all(TMP_DIR)
	return reg


func _has_error(reg: DataRegistry, fragment: String) -> bool:
	for e in reg.errors:
		if e.contains(fragment):
			return true
	return false


func test_dados_reais_do_projeto_carregam() -> void:
	var reg := DataRegistry.new()
	assert_true(reg.load_all(), "erros: %s" % [reg.errors])
	assert_eq(reg.section("calendar").seasons.size(), 4)
	assert_typeof(reg.section("sim").max_days_per_frame, TYPE_INT)


func test_dados_validos_normalizam_inteiros() -> void:
	var reg := _load_with(SIM_OK, CAL_OK)
	assert_true(reg.is_loaded(), "erros: %s" % [reg.errors])
	assert_typeof(reg.section("calendar").days_per_month, TYPE_INT)
	assert_typeof(reg.section("calendar").seasons[0].months, TYPE_INT)


func test_arquivo_ausente() -> void:
	_write("sim.json", SIM_OK)
	var reg := DataRegistry.new()
	assert_false(reg.load_all(TMP_DIR))
	assert_true(_has_error(reg, "calendar.json: arquivo não encontrado"))


func test_json_corrompido() -> void:
	var reg := _load_with(SIM_OK, "{ \"days_per_month\": 30,, }")
	assert_false(reg.is_loaded())
	assert_true(_has_error(reg, "JSON inválido"))


func test_raiz_que_nao_e_objeto() -> void:
	var reg := _load_with(SIM_OK, "[1, 2]")
	assert_true(_has_error(reg, "a raiz precisa ser um objeto"))


func test_chave_faltando_e_chave_desconhecida() -> void:
	var sim := SIM_OK.duplicate(true)
	sim.erase("default_seed")
	sim["secondz_per_day"] = 1
	var reg := _load_with(sim, CAL_OK)
	assert_false(reg.is_loaded())
	assert_true(_has_error(reg, "falta a chave 'default_seed'"))
	assert_true(_has_error(reg, "chave desconhecida 'secondz_per_day'"))


func test_tipo_errado_e_inteiro_com_fracao() -> void:
	var cal := CAL_OK.duplicate(true)
	cal.days_per_month = "30"
	cal.seasons[0].months = 6.5
	var reg := _load_with(SIM_OK, cal)
	assert_true(_has_error(reg, "days_per_month: precisa ser inteiro"))
	assert_true(_has_error(reg, "months: precisa ser inteiro"))


func test_fora_da_faixa() -> void:
	var sim := SIM_OK.duplicate(true)
	sim.seconds_per_day = 0
	sim.max_days_per_frame = 1000
	var reg := _load_with(sim, CAL_OK)
	assert_true(_has_error(reg, "seconds_per_day = 0"))
	assert_true(_has_error(reg, "1000 fora da faixa"))


func test_velocidades_precisam_ser_crescentes() -> void:
	var sim := SIM_OK.duplicate(true)
	sim.speeds = [1, 3, 2]
	assert_true(_has_error(_load_with(sim, CAL_OK), "crescente"))
	sim.speeds = []
	assert_true(_has_error(_load_with(sim, CAL_OK), "speeds não pode ser vazio"))


func test_estacoes_somam_o_ano() -> void:
	var cal := CAL_OK.duplicate(true)
	cal.seasons[1].months = 5
	assert_true(_has_error(_load_with(SIM_OK, cal), "soma dos meses"))


func test_id_repetido_e_id_invalido() -> void:
	var cal := CAL_OK.duplicate(true)
	cal.seasons[1].id = "seca"
	assert_true(_has_error(_load_with(SIM_OK, cal), "id repetido 'seca'"))
	cal.seasons[1].id = "Chuvas Fortes"
	assert_true(_has_error(_load_with(SIM_OK, cal), "id inválido"))


func test_falha_nao_deixa_dados_parciais() -> void:
	var sim := SIM_OK.duplicate(true)
	sim.speeds = "rápido"
	var reg := _load_with(sim, CAL_OK)
	assert_false(reg.is_loaded())
	assert_eq(reg.section("calendar"), {})
