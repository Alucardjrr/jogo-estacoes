extends GutTest
## Regressão de balanceamento (D-031, ajuste 4 do diretor): 10 sementes, 3 anos.
## Se um número de data/balance mudar e quebrar a curva de dificuldade ou o
## critério D-013, estes testes falham. Ajuste os números, não os testes — ou
## registre a nova decisão antes de mudar os limites aqui.

const Run := preload("res://tools/balance/balance_run.gd")
const SEEDS := 10
const YEARS := 3

const BEST_FIXED := {"fixed": {"water": 6, "farm": 21, "care": 3}}
## Plano rígido de referência. Janela_1 era 6/15/9 antes da variação (D-042); com o clima
## incerto, estocar comida antes das chuvas (6/21/3) é o melhor rígido (runner, D-044).
const PLAN := {
	"seca": {"water": 27, "farm": 0, "care": 3}, "janela_1": {"water": 6, "farm": 21, "care": 3},
	"chuvas": {"water": 0, "farm": 21, "care": 9}, "janela_2": {"water": 6, "farm": 21, "care": 3}}

var _base: Dictionary
var _fixed: Dictionary
var _plan: Dictionary


func before_all() -> void:
	_base = Run.summary({}, SEEDS, YEARS)
	_fixed = Run.summary(BEST_FIXED, SEEDS, YEARS)
	_plan = Run.summary({"by_season": PLAN}, SEEDS, YEARS)


func test_linha_de_base_sobrevive_ao_ano_1() -> void:
	for s in SEEDS:
		var r: Dictionary = Run.play({}, s + 1, 1)
		assert_eq(r.population, 50, "semente %d" % (s + 1))


func test_linha_de_base_quebra_no_ano_2() -> void:
	assert_lt(_base.by_year[1], 40.0, "perda significativa no ano 2 (média %.1f)" % _base.by_year[1])


func test_por_estacao_vence_fixa_que_vence_linha_de_base() -> void:
	# +5 restaurado (D-044) com o plano de referência revisto; era +3 provisório (D-043).
	assert_gt(_plan.mean, _fixed.mean + 5.0, "por estação %.1f × fixa %.1f" % [_plan.mean, _fixed.mean])
	assert_gt(_fixed.mean, _base.mean, "fixa %.1f × base %.1f" % [_fixed.mean, _base.mean])


func test_bom_jogo_chega_ao_ano_3_com_perdas() -> void:
	assert_between(_plan.mean, 30.0, 49.0, "por estação: %.1f" % _plan.mean)


func test_d013_plano_da_seca_nas_chuvas_custa() -> void:
	var wrong := PLAN.duplicate(true)
	wrong.chuvas = PLAN.seca
	var r := Run.summary({"by_season": wrong}, SEEDS, YEARS)
	assert_lt(r.mean, _plan.mean - 5.0, "seca nas chuvas %.1f × plano %.1f" % [r.mean, _plan.mean])


func test_d013_plano_das_chuvas_na_seca_custa() -> void:
	var wrong := PLAN.duplicate(true)
	wrong.seca = PLAN.chuvas
	var r := Run.summary({"by_season": wrong}, SEEDS, YEARS)
	assert_lt(r.mean, _plan.mean - 5.0, "chuvas na seca %.1f × plano %.1f" % [r.mean, _plan.mean])


func test_partida_deterministica() -> void:
	assert_eq(Run.play({"by_season": PLAN}, 7, 2), Run.play({"by_season": PLAN}, 7, 2))


func test_dados_invalidos_nao_travam() -> void:
	var r: Dictionary = Run.play({}, 1, 1, "user://nao_existe")
	assert_true(r.has("error"))


func test_adaptativo_vence_o_rigido() -> void:
	# Estratégia que lê previsão, estoques e saúde (tools/balance/adaptive_policy.gd).
	var ad := Run.summary({"policy": preload("res://tools/balance/adaptive_policy.gd").new()}, SEEDS, YEARS)
	var wins := range(SEEDS).filter(func(i: int) -> bool: return ad.pops[i] >= _plan.pops[i]).size()
	assert_eq(wins, SEEDS, "adaptativo ≥ rígido em todas as sementes: %s × %s" % [ad.pops, _plan.pops])
	assert_gt(ad.mean, _plan.mean + 3.0, "adaptativo %.1f × rígido %.1f" % [ad.mean, _plan.mean])
