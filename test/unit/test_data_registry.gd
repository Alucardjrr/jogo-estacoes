extends GutTest
## DataRegistry: dados reais carregam; dados inválidos são recusados com erro claro, sem travar.

const TMP_DIR := "user://test_data_registry"

const SIM_OK := {"seconds_per_day": 3.0, "speeds": [1, 2, 3],
	"max_days_per_frame": 10, "default_seed": 42}
const CAL_OK := {"days_per_month": 30, "months_per_year": 12, "seasons": [
	{"id": "seca", "months": 6, "severe": true},
	{"id": "chuvas", "months": 6, "severe": true}]}
const SEASON_OK := {"intensity_per_year": 0.15, "intensity_max": 2.0, "transition_days": 20, "seasons": {
	"seca": {"water_inflow": 12, "water_loss_rate": 0.004, "food_inflow": 25,
		"food_loss_rate": 0.002, "health_drift": 0, "gather_mult": 0.9, "farm_mult": 0.2,
		"escalation": {"water_inflow": -1}},
	"chuvas": {"water_inflow": 110, "water_loss_rate": 0.0005, "food_inflow": 40,
		"food_loss_rate": 0.008, "health_drift": -0.35, "gather_mult": 0.35, "farm_mult": 0.6,
		"escalation": {"health_drift": 1}}}}
const RES_OK := {"resources": {
	"water": {"initial": 4500, "capacity": 6000, "per_capita_daily": 1.0},
	"food": {"initial": 3000, "capacity": 6000, "per_capita_daily": 1.0}}}
const POP_OK := {"families": [{"id": "f01", "size": 5}, {"id": "f02", "size": 3}],
	"health_initial": 80, "health_max": 100, "health_recovery_per_day": 0.2,
	"water_shortage_health": 8, "food_shortage_health": 3, "death_health_threshold": 40,
	"death_rate_max": 0.004, "departure_shortage_days": 10}
const LAB_OK := {"worker_share": 0.6, "full_productivity_health": 60, "min_productivity": 0.5,
	"water_per_worker": 2.5, "food_per_worker": 3.5, "care_health_per_share": 10,
	"care_health_max": 2.0, "fatigue_threshold": 0.5, "fatigue_health": 0.4,
	"initial_allocation": {"water": 9, "farm": 18, "care": 3, "build": 0, "salvage": 0}}
const SEASONS_2 := {"seca": 0.1, "chuvas": 0.3}
const NAR_OK := {"hard_shortage_days": 10, "residents": 12, "diary_lines": 3,
	"season_group": {"seca": "SECA", "chuvas": "CHUVAS"},
	"reaction_lines": {"DEATH": 4, "FAMILY_LEFT": 4, "BUILDING_DONE": 4, "SHORTAGE_WATER": 3,
		"SHORTAGE_FOOD": 3, "SEASON_SECA": 2, "SEASON_CHUVAS": 2}}
const BLD_OK := {"work_points_per_worker": 1.0, "points_per_condition": 2.0,
	"low_condition_threshold": 60, "low_condition_wear_mult": 1.5,
	"repair_cost_mult": {"seca": 1.0, "chuvas": 1.0}, "salvage_per_worker": 1.0,
	"salvage_fatigue": 2.0, "max_queue": 5, "types": {
		"ruinas": {"ruins": true, "materials": 800},
		"cisterna": {"cost_materials": 120, "cost_points": 60, "wear": SEASONS_2,
			"effects": [{"key": "water_capacity", "add": 1500}]},
		"silo": {"cost_materials": 100, "cost_points": 50, "wear": SEASONS_2,
			"effects": [{"key": "food_loss_rate", "mul": 0.7, "seasons": ["chuvas"]}]}}}


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


func _load_with(sim: Variant, cal: Variant, season: Variant = SEASON_OK,
		res: Variant = RES_OK, pop: Variant = POP_OK, lab: Variant = LAB_OK,
		bld: Variant = BLD_OK, nar: Variant = NAR_OK) -> DataRegistry:
	_write("sim.json", sim)
	_write("calendar.json", cal)
	_write("season.json", season)
	_write("resources.json", res)
	_write("population.json", pop)
	_write("labor.json", lab)
	_write("buildings.json", bld)
	_write("narrative.json", nar)
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
	assert_eq(reg.section("population").families.size(), 12)
	assert_eq(reg.section("season").seasons.size(), 4)
	assert_eq(reg.section("resources").resources.keys(), Array(DataRegistry.RESOURCE_IDS))
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


# --- season.json ---

func test_season_valida_e_normaliza() -> void:
	var reg := _load_with(SIM_OK, CAL_OK)
	assert_true(reg.is_loaded(), "erros: %s" % [reg.errors])
	assert_eq(reg.section("season").seasons.seca.escalation, {"water_inflow": -1.0})
	assert_eq(reg.section("season").seasons.chuvas.escalation, {"health_drift": 1.0})
	assert_eq(reg.section("season").seasons.chuvas.health_drift, -0.35)


func test_season_precisa_bater_com_o_calendario() -> void:
	var season := SEASON_OK.duplicate(true)
	season.seasons.erase("chuvas")
	season.seasons["inverno"] = SEASON_OK.seasons.seca.duplicate(true)
	var reg := _load_with(SIM_OK, CAL_OK, season)
	assert_false(reg.is_loaded())
	assert_true(_has_error(reg, "falta a estação 'chuvas'"))
	assert_true(_has_error(reg, "estação 'inverno' não existe em calendar.json"))


func test_season_taxa_fora_da_faixa_e_chave_errada() -> void:
	var season := SEASON_OK.duplicate(true)
	season.seasons.seca.water_loss_rate = 1.5
	season.seasons.seca.escalation = {"water_inflw": 1, "food_inflow": "muito"}
	season.seasons.chuvas["neve"] = 3
	var reg := _load_with(SIM_OK, CAL_OK, season)
	assert_true(_has_error(reg, "water_loss_rate = 1.5 fora da faixa"))
	assert_true(_has_error(reg, "escalation: chave desconhecida 'water_inflw'"))
	assert_true(_has_error(reg, "food_inflow precisa ser número"))
	assert_true(_has_error(reg, "chave desconhecida 'neve'"))


func test_season_tipos_errados_nao_travam() -> void:
	var season := SEASON_OK.duplicate(true)
	season.seasons.seca = [1, 2]
	season.seasons.chuvas.escalation = "nenhuma"
	var reg := _load_with(SIM_OK, CAL_OK, season)
	assert_true(_has_error(reg, "seasons.seca: precisa ser um objeto"))
	assert_true(_has_error(reg, "escalation precisa ser um objeto"))
	season.seasons = "x"
	assert_true(_has_error(_load_with(SIM_OK, CAL_OK, season), "seasons precisa ser um objeto"))


# --- resources.json ---

func test_resources_recurso_faltando_ou_desconhecido() -> void:
	var res := RES_OK.duplicate(true)
	res.resources.erase("food")
	res.resources["ouro"] = {"initial": 1, "capacity": 1, "per_capita_daily": 0}
	var reg := _load_with(SIM_OK, CAL_OK, SEASON_OK, res)
	assert_false(reg.is_loaded())
	assert_true(_has_error(reg, "falta a chave 'food'"))
	assert_true(_has_error(reg, "chave desconhecida 'ouro'"))


func test_resources_inicial_acima_da_capacidade() -> void:
	var res := RES_OK.duplicate(true)
	res.resources.water.initial = 7000
	assert_true(_has_error(_load_with(SIM_OK, CAL_OK, SEASON_OK, res), "initial (7000"))


func test_resources_valores_invalidos() -> void:
	var res := RES_OK.duplicate(true)
	res.resources.food.capacity = 0
	res.resources.water = "muita"
	var reg := _load_with(SIM_OK, CAL_OK, SEASON_OK, res)
	assert_true(_has_error(reg, "capacity = 0"))
	assert_true(_has_error(reg, "resources.water: precisa ser um objeto"))


func test_calendario_invalido_nao_gera_ruido_na_checagem_cruzada() -> void:
	var cal := CAL_OK.duplicate(true)
	cal.seasons[1].id = "Chuvas Fortes"
	var reg := _load_with(SIM_OK, cal)
	assert_true(_has_error(reg, "id inválido"))
	assert_false(_has_error(reg, "season.json"), "erros: %s" % [reg.errors])


# --- population.json ---

func test_population_valida_e_normaliza() -> void:
	var reg := _load_with(SIM_OK, CAL_OK)
	assert_true(reg.is_loaded(), "erros: %s" % [reg.errors])
	assert_typeof(reg.section("population").families[0].size, TYPE_INT)
	assert_typeof(reg.section("population").departure_shortage_days, TYPE_INT)


func test_population_familias_invalidas() -> void:
	var pop := POP_OK.duplicate(true)
	pop.families = [{"id": "f01", "size": 5}, {"id": "f01", "size": 0},
		{"id": "Família X", "size": 2}, "f04", {"id": "f05", "size": 2, "nome": "x"}]
	var reg := _load_with(SIM_OK, CAL_OK, SEASON_OK, RES_OK, pop)
	assert_false(reg.is_loaded())
	assert_true(_has_error(reg, "id repetido 'f01'"))
	assert_true(_has_error(reg, "families[1]: size: 0 fora da faixa"))
	assert_true(_has_error(reg, "families[2]: id inválido"))
	assert_true(_has_error(reg, "families[3]: precisa ser um objeto"))
	assert_true(_has_error(reg, "chave desconhecida 'nome'"))
	pop.families = []
	assert_true(_has_error(_load_with(SIM_OK, CAL_OK, SEASON_OK, RES_OK, pop), "families não pode ser vazio"))


func test_population_faixas_e_coerencia() -> void:
	var pop := POP_OK.duplicate(true)
	pop.health_initial = 120
	pop.death_rate_max = 2
	pop.departure_shortage_days = 0
	var reg := _load_with(SIM_OK, CAL_OK, SEASON_OK, RES_OK, pop)
	assert_true(_has_error(reg, "health_initial (120"))
	assert_true(_has_error(reg, "death_rate_max = 2"))
	assert_true(_has_error(reg, "departure_shortage_days: 0 fora da faixa"))
	pop = POP_OK.duplicate(true)
	pop.death_health_threshold = 150
	assert_true(_has_error(_load_with(SIM_OK, CAL_OK, SEASON_OK, RES_OK, pop), "death_health_threshold maior"))


func test_resources_nao_aceita_mais_populacao_provisoria() -> void:
	var res := RES_OK.duplicate(true)
	res["placeholder_population"] = 50
	assert_true(_has_error(_load_with(SIM_OK, CAL_OK, SEASON_OK, res), "chave desconhecida 'placeholder_population'"))



func test_transicao_maior_que_a_estacao() -> void:
	var season := SEASON_OK.duplicate(true)
	season.transition_days = 182  # estações de CAL_OK têm 180 dias
	var reg := _load_with(SIM_OK, CAL_OK, season)
	assert_true(_has_error(reg, "transition_days (182) maior que a estação mais curta (180 dias)"))
	season.transition_days = 180
	reg = _load_with(SIM_OK, CAL_OK, season)
	assert_true(reg.is_loaded(), "igual à estação mais curta é aceito: %s" % [reg.errors])
	season.transition_days = 2.5
	assert_true(_has_error(_load_with(SIM_OK, CAL_OK, season), "transition_days: precisa ser inteiro"))


func test_transicao_impar_recusada() -> void:
	var season := SEASON_OK.duplicate(true)
	season.transition_days = 5
	assert_true(_has_error(_load_with(SIM_OK, CAL_OK, season), "transition_days (5) precisa ser par"))


func test_transicao_limitada_pela_estacao_mais_curta_de_verdade() -> void:
	var cal := CAL_OK.duplicate(true)
	cal.seasons[0].months = 10
	cal.seasons[1].months = 2  # chuvas: 60 dias
	var season := SEASON_OK.duplicate(true)
	season.transition_days = 62
	assert_true(_has_error(_load_with(SIM_OK, cal, season), "maior que a estação mais curta (60 dias)"))
	season.transition_days = 60
	assert_true(_load_with(SIM_OK, cal, season).is_loaded())


# --- labor.json ---

func test_labor_valida_e_normaliza() -> void:
	var reg := _load_with(SIM_OK, CAL_OK)
	assert_true(reg.is_loaded(), "erros: %s" % [reg.errors])
	assert_typeof(reg.section("labor").initial_allocation.farm, TYPE_INT)


func test_labor_alocacao_invalida() -> void:
	var lab := LAB_OK.duplicate(true)
	lab.initial_allocation = {"water": -1, "farm": 2.5, "pesca": 3, "build": 0, "salvage": 0}
	var reg := _load_with(SIM_OK, CAL_OK, SEASON_OK, RES_OK, POP_OK, lab)
	assert_false(reg.is_loaded())
	assert_true(_has_error(reg, "water: -1 fora da faixa"))
	assert_true(_has_error(reg, "farm: precisa ser inteiro"))
	assert_true(_has_error(reg, "chave desconhecida 'pesca'"))
	assert_true(_has_error(reg, "falta a chave 'care'"))


func test_labor_faixas() -> void:
	var lab := LAB_OK.duplicate(true)
	lab.worker_share = 1.5
	lab.fatigue_threshold = 1.0
	lab.full_productivity_health = 0
	var reg := _load_with(SIM_OK, CAL_OK, SEASON_OK, RES_OK, POP_OK, lab)
	assert_true(_has_error(reg, "worker_share = 1.5"))
	assert_true(_has_error(reg, "fatigue_threshold = 1"))
	assert_true(_has_error(reg, "full_productivity_health = 0"))


# --- buildings.json ---

func _bld_errors(bld: Dictionary) -> DataRegistry:
	return _load_with(SIM_OK, CAL_OK, SEASON_OK, RES_OK, POP_OK, LAB_OK, bld)


func test_buildings_valido() -> void:
	var reg := _bld_errors(BLD_OK)
	assert_true(reg.is_loaded(), "erros: %s" % [reg.errors])
	assert_true(reg.section("buildings").types.ruinas.ruins)
	assert_eq(reg.section("buildings").types.silo.effects[0].seasons, ["chuvas"])


func test_buildings_desgaste_precisa_das_estacoes_do_calendario() -> void:
	var bld := BLD_OK.duplicate(true)
	bld.types.cisterna.wear = {"seca": 0.1, "inverno": 0.2}
	var reg := _bld_errors(bld)
	assert_true(_has_error(reg, "falta a chave 'chuvas'"))
	assert_true(_has_error(reg, "chave desconhecida 'inverno'"))


func test_buildings_efeito_invalido() -> void:
	var bld := BLD_OK.duplicate(true)
	bld.types.cisterna.effects = [{"key": "ouro", "add": 1}, {"key": "farm_mult"},
		{"key": "farm_mult", "add": 1, "mul": 2}, {"key": "farm_mult", "add": 1, "seasons": ["neve"]},
		{"key": "farm_mult", "add": 1, "extra": true}]
	var reg := _bld_errors(bld)
	assert_true(_has_error(reg, "key inválida 'ouro'"))
	assert_true(_has_error(reg, "effects[1]: precisa de add ou mul"))
	assert_true(_has_error(reg, "effects[2]: precisa de add ou mul"))
	assert_true(_has_error(reg, "estação 'neve' não existe"))
	assert_true(_has_error(reg, "chave desconhecida 'extra'"))


func test_buildings_ruinas_e_custos() -> void:
	var bld := BLD_OK.duplicate(true)
	bld.types.ruinas["cost_points"] = 3
	bld.types.silo.cost_points = 0
	bld.max_queue = 0
	var reg := _bld_errors(bld)
	assert_true(_has_error(reg, "types.ruinas: chave desconhecida 'cost_points'"))
	assert_true(_has_error(reg, "cost_points = 0"))
	assert_true(_has_error(reg, "max_queue: 0 fora da faixa"))


# --- narrative.json ---

func test_narrative_grupos_e_linhas() -> void:
	var nar := NAR_OK.duplicate(true)
	nar.season_group = {"seca": "seca", "inverno": "INV"}
	nar.reaction_lines.erase("DEATH")
	var reg := _load_with(SIM_OK, CAL_OK, SEASON_OK, RES_OK, POP_OK, LAB_OK, BLD_OK, nar)
	assert_false(reg.is_loaded())
	assert_true(_has_error(reg, "season_group.seca inválido"))
	assert_true(_has_error(reg, "falta a chave 'chuvas'"))
	assert_true(_has_error(reg, "chave desconhecida 'inverno'"))
	assert_true(_has_error(reg, "reaction_lines: falta a chave 'DEATH'"))
