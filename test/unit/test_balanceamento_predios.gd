extends GutTest
## Regressão de balanceamento dos prédios (D-032; critérios do diretor). 10 sementes.
## Plano "constrói no ano 1, aproveita depois" achado por busca no runner.

const Run := preload("res://tools/balance/balance_run.gd")
const SEEDS := 10
const YEARS := 3
const MIXED := ["cisterna", "silo", "abrigo", "canteiro", "cisterna", "silo", "abrigo"]
const TYPES := ["cisterna", "silo", "canteiro", "abrigo"]


static func _a(w: int, f: int, c: int, b: int, s: int) -> Dictionary:
	return {"water": w, "farm": f, "care": c, "build": b, "salvage": s}


static func _with_buildings(builds: Array) -> Dictionary:
	return {"builds": builds, "by_year": {
		1: {"seca": _a(27, 0, 3, 0, 0), "janela_1": _a(6, 12, 6, 2, 4),
			"chuvas": _a(0, 21, 9, 0, 0), "janela_2": _a(6, 18, 3, 3, 0)},
		2: {"seca": _a(21, 0, 9, 0, 0), "janela_1": _a(21, 6, 3, 0, 0),
			"chuvas": _a(0, 21, 6, 3, 0), "janela_2": _a(6, 21, 0, 3, 0)}}}


const NO_BUILDINGS := {"by_season": {
	"seca": {"water": 27, "farm": 0, "care": 3}, "janela_1": {"water": 6, "farm": 15, "care": 9},
	"chuvas": {"water": 0, "farm": 21, "care": 9}, "janela_2": {"water": 6, "farm": 21, "care": 3}}}


func test_predios_vencem_o_melhor_plano_sem_predios() -> void:
	var with := Run.summary(_with_buildings(MIXED), SEEDS, YEARS)
	var without := Run.summary(NO_BUILDINGS, SEEDS, YEARS)
	assert_gt(with.mean, without.mean + 3.0, "com %.1f × sem %.1f" % [with.mean, without.mean])


func test_nenhum_predio_sozinho_domina() -> void:
	# Domina = ordem só de um prédio vence a mista em ≥ 7 de 10 sementes (pop. fim do ano 2).
	var mixed_y2 := []
	for s in SEEDS:
		mixed_y2.append(Run.play(_with_buildings(MIXED), s + 1, 2).population)
	for t in TYPES:
		var wins := 0
		for s in SEEDS:
			var r: Dictionary = Run.play(_with_buildings([t, t, t, t, t, t, t]), s + 1, 2)
			if r.population > mixed_y2[s]:
				wins += 1
		assert_lt(wins, 7, "só %s vence a mista em %d/10" % [t, wins])


func test_d013_canteiro_cobra_manutencao_pelas_chuvas() -> void:
	# Métrica = dívida de manutenção criada (desgaste em pontos de obra), não o reparo pago:
	# o reparo tende a ir para a janela, onde custa metade (preparar > reagir).
	var r: Dictionary = Run.play(_with_buildings(["canteiro", "canteiro", "canteiro"]), 1, YEARS)
	var wear: Dictionary = r.wear_by_season
	assert_gt(wear.get("chuvas", 0.0), 0.0, "desgaste mensurável nas chuvas")
	for sid in wear:
		if sid != "chuvas":
			assert_gt(wear.chuvas, wear[sid], "chuvas %.1f × %s %.1f" % [wear.chuvas, sid, wear[sid]])
	var repaired := 0.0
	for sid in r.repair_by_season:
		repaired += r.repair_by_season[sid]
	assert_gt(repaired, 0.0, "a dívida é paga com mão de obra")


func test_saque_esgota() -> void:
	var r: Dictionary = Run.play({"fixed": _a(6, 12, 3, 0, 9)}, 1, YEARS)
	var sim := Simulation.new()
	assert_true(sim.setup(1))
	assert_eq(r.built, 0)
	# com 9 no saque por 3 anos, as ruínas ficam quase vazias e o rendimento cai
	var run2 := Simulation.new()
	run2.setup(1)
	run2.enqueue({"type": "set_labor", "task": "salvage", "value": 9})
	for _d in 360 * YEARS:
		run2.step_day()
	assert_lt(run2.buildings.ruins_remaining, run2.buildings.ruins_initial * 0.2)
	assert_almost_eq(run2.buildings.materials + run2.buildings.ruins_remaining,
		run2.buildings.ruins_initial, 1e-6, "material não surge do nada")
