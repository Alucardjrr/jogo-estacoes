class_name BalanceRun
extends RefCounted
## Partida headless para balanceamento (BACKLOG P2, D-031). Joga uma estratégia de
## mão de obra com a simulação real, sem tela, e devolve o resultado.
## Usado pelo runner de linha de comando (tools/balance_runner.gd) e pelos testes
## de regressão de balanceamento.
##
## Estratégia (Dictionary):
##   {}                                   → distribuição inicial dos dados (linha de base)
##   {"fixed": {"water": 6, "farm": 21, "care": 3}}
##   {"by_season": {"seca": {...}, "janela_1": {...}, ...}}  → aplicada no início de cada estação
##   {"by_year": {1: {by_season...}, 2: {...}}}  → plano por estação de cada ano (o último vale para os seguintes)
##   + opcional "builds": ["cisterna", "silo", ...] → postos na fila de obras no dia 1
##   + opcional "measures": {"seca": "racionamento", ...} → medida ativada no início da estação
##   + opcional "desperation": true → ativa a medida de desespero (confisco) assim que liberar
## A troca entra pela fila de comandos, como o jogador faria (vale no dia seguinte).


static func play(strategy: Dictionary, seed_number: int, years: int,
		data_dir: String = DataRegistry.DEFAULT_DIR) -> Dictionary:
	var sim := Simulation.new()
	if not sim.setup(seed_number, data_dir):
		return {"error": "\n".join(sim.data.errors)}
	var days: int = sim.calendar.days_per_year() * years
	var out := {"deaths": 0, "left": 0, "shortage_days": 0, "health_min": sim.population.health,
		"population_by_year": [], "rejected": 0}
	_apply(sim, strategy, sim.calendar.season_id(), 1)
	_measure(sim, strategy, sim.calendar.season_id())
	for b in strategy.get("builds", []):
		sim.enqueue({"type": "build", "building": b})
	out.built = 0
	out.repair_by_season = {}
	out.wear_by_season = {}
	out.building_water_by_season = {}
	out.water_deficit_by_season = {}
	for _d in days:
		sim.step_day()
		var short := false
		for e in sim.drain_events():
			match e.type:
				"death": out.deaths += 1
				"family_left": out.left += e.size
				"shortage": short = true
				"command_rejected": out.rejected += 1
				"season_changed":
					_apply(sim, strategy, e.to, e.year)
					_measure(sim, strategy, e.to)
				"building_completed": out.built += 1
		if short:
			out.shortage_days += 1
		if strategy.get("desperation", false) \
				and not (strategy.get("desperation_once", false) and out.get("desperation_used", 0) > 0) \
				and sim.social.check("confisco", sim.calendar.season_id(), sim.calendar.year(),
					sim.water_fraction()) == "":
			sim.enqueue({"type": "enact_measure", "measure": "confisco"})
			out.desperation_used = out.get("desperation_used", 0) + 1
		var sid := sim.calendar.season_id()
		out.repair_by_season[sid] = out.repair_by_season.get(sid, 0.0) + sim.buildings.last_repair_points
		out.wear_by_season[sid] = out.wear_by_season.get(sid, 0.0) + sim.buildings.last_wear_points
		var bw := 0.0
		for m in sim.modifiers.entries():
			if m.key == "water_consumption" and m.source == SimBuildings.SOURCE:
				bw += m.add
		out.building_water_by_season[sid] = out.building_water_by_season.get(sid, 0.0) + bw
		out.water_deficit_by_season[sid] = out.water_deficit_by_season.get(sid, 0.0) \
			+ sim.resources.last_flow.water.deficit
		out.health_min = minf(out.health_min, sim.population.health)
		if sim.calendar.day_index % sim.calendar.days_per_year() == 0:
			out.population_by_year.append(sim.population.people())
	out.population = sim.population.people()
	out.social = sim.social.snapshot()
	return out


## Média de várias sementes: população final, mortes, saídas, pior população.
static func summary(strategy: Dictionary, seeds: int, years: int,
		data_dir: String = DataRegistry.DEFAULT_DIR) -> Dictionary:
	var pops: Array[int] = []
	var deaths := 0
	var left := 0
	var by_year: Array[float] = []
	for y in years:
		by_year.append(0.0)
	for s in seeds:
		var r := play(strategy, s + 1, years, data_dir)
		if r.has("error"):
			return r
		pops.append(r.population)
		deaths += r.deaths
		left += r.left
		for y in years:
			by_year[y] += r.population_by_year[y]
	var total := 0
	for p in pops:
		total += p
	for y in years:
		by_year[y] /= seeds
	return {"mean": float(total) / seeds, "worst": pops.min(), "deaths": float(deaths) / seeds,
		"left": float(left) / seeds, "by_year": by_year, "pops": pops}


static func _measure(sim: Simulation, strategy: Dictionary, season_id: String) -> void:
	var m: Variant = strategy.get("measures", {}).get(season_id)
	if m is String:
		sim.enqueue({"type": "enact_measure", "measure": m})


static func _apply(sim: Simulation, strategy: Dictionary, season_id: String, year: int) -> void:
	var alloc: Dictionary = {}
	if strategy.has("fixed"):
		alloc = strategy.fixed
	elif strategy.has("by_season"):
		alloc = strategy.by_season.get(season_id, {})
	elif strategy.has("by_year"):
		var y := year
		while y > 1 and not strategy.by_year.has(y):
			y -= 1
		alloc = strategy.by_year.get(y, {}).get(season_id, {})
	for task in alloc:
		sim.enqueue({"type": "set_labor", "task": task, "value": alloc[task]})
