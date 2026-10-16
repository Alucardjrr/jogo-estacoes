extends GutTest
## Regressão de balanceamento do Social (D-035..D-041; critérios do diretor). 10 sementes.
## D-039: "sempre certa" é medida contra planos COM decisões (por estação; com prédios) —
## uma política "usar X sempre que disponível" reprova se vencer o plano sem X em ≥ 7/10.
## A linha de base passiva não é plano: nela as medidas de água ajudam, e isso é contexto
## (valor dependente do estado), não estratégia dominante.

const Run := preload("res://tools/balance/balance_run.gd")
const P := preload("res://test/unit/test_balanceamento_predios.gd")
const SEEDS := 10


static func _a(w: int, f: int, c: int, b: int = 0, s: int = 0) -> Dictionary:
	return {"water": w, "farm": f, "care": c, "build": b, "salvage": s}


static func _plan() -> Dictionary:
	return {"by_season": {"seca": _a(27, 0, 3), "janela_1": _a(6, 15, 9),
		"chuvas": _a(0, 21, 9), "janela_2": _a(6, 21, 3)}}


const ALWAYS := {
	"racionamento": {"measures": {"seca": "racionamento"}},
	"agua_na_roca": {"measures": {"seca": "agua_na_roca"}},
	"quarentena": {"measures": {"chuvas": "quarentena"}},
	"mutirao": {"measures": {"chuvas": "mutirao"}},
	"confisco": {"desperation": true},
}


func _wins(with: Dictionary, without: Dictionary) -> int:
	return range(SEEDS).filter(func(i: int) -> bool: return with.pops[i] > without.pops[i]).size()


func test_linha_de_base_do_ano_1_nao_muda() -> void:
	# Medidores ficam na faixa sem efeito (≥ 70) o ano 1 inteiro e ninguém sai.
	var full: float = Simulation.new().data.section("social").get("trust_productivity", {}).get("full_at", 70.0)
	for s in SEEDS:
		var sim := Simulation.new()
		assert_true(sim.setup(s + 1))
		full = sim.data.section("social").trust_productivity.full_at
		for _d in 359:
			sim.step_day()
			assert_true(sim.social.trust >= full and sim.social.cohesion >= full,
				"semente %d dia %d: %.1f/%.1f" % [s + 1, sim.calendar.day_index, sim.social.trust, sim.social.cohesion])
			if sim.social.trust < full or sim.social.cohesion < full:
				return
		assert_eq(sim.population.people(), 50)


func test_nenhuma_medida_sempre_certa_nos_planos_bons() -> void:
	for base_name in ["plano", "predios"]:
		var base: Dictionary = _plan() if base_name == "plano" else P._with_buildings(P.MIXED)
		var without := Run.summary(base, SEEDS, 3)
		for id in ALWAYS:
			var with := Run.summary(base.merged(ALWAYS[id], true), SEEDS, 3)
			assert_lt(_wins(with, without), 7, "%s sempre, em %s: vence %d/10" % [id, base_name, _wins(with, without)])


func _improves(base: Dictionary, with: Dictionary, years: int = 3) -> bool:
	var x := Run.summary(base, SEEDS, years)
	var y := Run.summary(with, SEEDS, years)
	return y.mean > x.mean


func test_cada_medida_ajuda_em_algum_contexto() -> void:
	# Partilha e Rega: colônia sem decisões, com água apertada na seca.
	assert_true(_improves({}, ALWAYS.racionamento), "racionamento")
	assert_true(_improves({}, ALWAYS.agua_na_roca), "agua_na_roca")
	# Isolamento: chuvas sem ninguém cuidando dos doentes.
	var no_care := {"by_season": {"seca": _a(27, 0, 3), "janela_1": _a(6, 15, 9),
		"chuvas": _a(0, 30, 0), "janela_2": _a(6, 21, 3)}}
	assert_true(_improves(no_care, no_care.merged(ALWAYS.quarentena, true)), "quarentena")
	# Mutirão: prédios só reparados nas chuvas, por 5 anos.
	var repair_rains := {"builds": P.MIXED, "by_year": {
		1: {"seca": _a(27, 0, 3), "janela_1": _a(6, 12, 6, 2, 4), "chuvas": _a(0, 21, 9),
			"janela_2": _a(6, 18, 3, 3, 0)},
		2: {"seca": _a(21, 0, 9), "janela_1": _a(21, 6, 3), "chuvas": _a(0, 21, 7, 2, 0),
			"janela_2": _a(9, 21, 0)}}}
	assert_true(_improves(repair_rains, repair_rains.merged(ALWAYS.mutirao, true), 5), "mutirao")
	# Requisição: plano bom que ainda passa sede no pico da seca, usada uma vez.
	assert_true(_improves(_plan(), _plan().merged({"desperation": true, "desperation_once": true}, true)),
		"confisco")


func test_d013_rega_cobra_nas_chuvas() -> void:
	# A febre da água parada derruba a saúde no começo das chuvas e a vizinhança entra menor.
	# Sem cuidadores, para a febre não ser escondida pelo cuidado (que depende de quantos ficaram).
	var lows := {false: 0.0, true: 0.0}
	var coh := {false: 0.0, true: 0.0}
	for rega in [false, true]:
		for s in SEEDS:
			var sim := Simulation.new()
			sim.setup(s + 1)
			sim.enqueue({"type": "set_labor", "task": "care", "value": 0})
			var low := 100.0
			for _d in 210:
				if rega and sim.calendar.season_id() == "seca" and sim.calendar.day_in_season() == 1:
					sim.enqueue({"type": "enact_measure", "measure": "agua_na_roca"})
				sim.step_day()
				if sim.calendar.season_id() == "chuvas":
					if sim.calendar.day_in_season() == 1:
						coh[rega] += sim.social.cohesion
					if sim.calendar.day_in_season() <= 30:
						low = minf(low, sim.population.health)
			lows[rega] += low
	assert_lt(lows[true], lows[false], "saúde mínima no começo das chuvas: %.1f × %.1f" % [lows[true] / SEEDS, lows[false] / SEEDS])
	assert_lt(coh[true], coh[false])


func test_repetir_todo_ano_baixa_o_teto() -> void:
	# Alvo do designer/diretor: tetos entre 55 e 70 após 5 anos usando uma medida por estação.
	var trust := 0.0
	var coh := 0.0
	for s in SEEDS:
		var r: Dictionary = Run.play(P._with_buildings(P.MIXED).merged(
			{"measures": {"seca": "racionamento", "chuvas": "quarentena"}, "desperation": true}, true), s + 1, 5)
		trust += r.social.trust_ceiling
		coh += r.social.cohesion_ceiling
	assert_between(trust / SEEDS, 55.0, 70.0, "teto da fé")
	assert_between(coh / SEEDS, 55.0, 70.0, "teto da vizinhança")
