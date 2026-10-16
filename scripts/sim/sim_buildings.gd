class_name SimBuildings
extends RefCounted
## Prédios (GDD 10, sistema 9; D-032). Dois momentos no tick:
##   5a. publish_effects(): antes de Labor, para Labor já ler farm_mult/gather_mult
##       do dia (estação de hoje; condição e falta de água do fim de ontem).
##   6.  step(): depois de Labor — saque, desgaste e obras.
## Sem mapa: prédios são instâncias abstratas {type, condition}; o mapa futuro só lê.
##
## step():
##   1. Saque: trabalhadores do saque (efetivos, de Labor) tiram materiais das
##      ruínas; rendimento × fração restante. Fadiga do saque = salvage_fatigue ×
##      (fração da força no saque) × (fração já esgotada).
##   2. Desgaste: cada prédio perde wear[estação]% de condição; abaixo do limiar,
##      × low_condition_wear_mult.
##   3. Obras: pontos = trabalhadores de obras efetivos × work_points_per_worker.
##      Primeiro reparo (pior condição primeiro; 1% custa points_per_condition ×
##      repair_cost_mult[estação]), depois a fila de construção. Materiais são
##      reservados quando a obra começa.
## publish_effects(): efeitos na pilha (fonte "buildings"), × condição/100.
##   add: soma; mul: 1 − (1 − mul) × condição/100, multiplicado por prédio.
##   Filtro de estação; requires_water pula o efeito se ontem faltou água.

const SOURCE := "buildings"
const SALVAGE_SOURCE := "salvage"

var instances: Array[Dictionary] = []  # [{type, condition}]
var queue: Array[Dictionary] = []      # [{type, progress, started}]
var materials := 0.0
var ruins_initial := 0.0
var ruins_remaining := 0.0
## Pontos de obra gastos em reparo no último dia (métrica de balanceamento, D-032).
var last_repair_points := 0.0
## Condição perdida por desgaste no último dia, em pontos de obra (dívida de manutenção criada).
var last_wear_points := 0.0

var _cfg: Dictionary
var _types: Dictionary


func _init(cfg: Dictionary) -> void:
	_cfg = cfg
	_types = cfg.types
	for id in _types:
		if _types[id].ruins:
			ruins_initial += _types[id].materials
	ruins_remaining = ruins_initial


func buildable_types() -> PackedStringArray:
	var out: PackedStringArray = []
	for id in _types:
		if not _types[id].ruins:
			out.append(id)
	out.sort()
	return out


func is_buildable(id: String) -> bool:
	return _types.has(id) and not _types[id].ruins


func can_enqueue() -> bool:
	return queue.size() < int(_cfg.max_queue)


func enqueue(id: String) -> void:
	queue.append({"type": id, "progress": 0.0, "started": false})


func count(id: String) -> int:
	return instances.filter(func(b: Dictionary) -> bool: return b.type == id).size()


## labor: SimLabor do dia (efetivos e força).
func step(labor: SimLabor, season_id: String, modifiers: ModifierStack) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	modifiers.clear_source(SALVAGE_SOURCE)

	# 1. Saque
	if ruins_initial > 0.0:
		var frac_left := ruins_remaining / ruins_initial
		var got := minf(ruins_remaining,
			labor.effective.salvage * _cfg.salvage_per_worker * frac_left)
		ruins_remaining -= got
		materials += got
		if labor.workers > 0:
			var share: float = labor.assigned.salvage / labor.workers
			modifiers.add("health_drift", SALVAGE_SOURCE,
				-_cfg.salvage_fatigue * share * (1.0 - ruins_remaining / ruins_initial))

	# 2. Desgaste
	last_wear_points = 0.0
	for b in instances:
		var wear: float = _types[b.type].wear.get(season_id, 0.0)
		if b.condition < _cfg.low_condition_threshold:
			wear *= _cfg.low_condition_wear_mult
		var lost := minf(wear, b.condition)
		b.condition -= lost
		last_wear_points += lost * _cfg.points_per_condition

	# 3. Obras: reparo primeiro (pior condição primeiro), depois construção
	var points: float = labor.effective.build * _cfg.work_points_per_worker
	var points_before := points
	var per_pct: float = _cfg.points_per_condition * _cfg.repair_cost_mult.get(season_id, 1.0)
	var order := range(instances.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return instances[a].condition < instances[b].condition \
			or (instances[a].condition == instances[b].condition and a < b))
	for i in order:
		if points <= 0.0:
			break
		var b: Dictionary = instances[i]
		var missing: float = 100.0 - b.condition
		if missing <= 0.0:
			continue
		var pct := missing if per_pct <= 0.0 else minf(missing, points / per_pct)
		b.condition += pct
		points -= pct * per_pct
	last_repair_points = points_before - points
	while points > 0.0 and not queue.is_empty():
		var job: Dictionary = queue[0]
		var t: Dictionary = _types[job.type]
		if not job.started:
			if materials < t.cost_materials:
				break  # espera materiais; a fila não pula (ordem do jogador)
			materials -= t.cost_materials
			job.started = true
			events.append({"type": "building_started", "building": job.type})
		var use := minf(points, t.cost_points - job.progress)
		job.progress += use
		points -= use
		if job.progress >= t.cost_points - 1e-9:
			queue.pop_front()
			instances.append({"type": job.type, "condition": 100.0})
			events.append({"type": "building_completed", "building": job.type})
	return events


## water_short_yesterday: houve falta de água no último dia processado.
func publish_effects(season_id: String, water_short_yesterday: bool,
		modifiers: ModifierStack) -> void:
	modifiers.clear_source(SOURCE)
	var muls := {}
	for b in instances:
		var k: float = b.condition / 100.0
		for e in _types[b.type].effects:
			if not e.seasons.is_empty() and not e.seasons.has(season_id):
				continue
			if e.requires_water and water_short_yesterday:
				continue
			if e.has("mul"):
				muls[e.key] = muls.get(e.key, 1.0) * (1.0 - (1.0 - e.mul) * k)
			else:
				modifiers.add(e.key, SOURCE, e.add * k)
	for key in muls:
		modifiers.mul(key, SOURCE, muls[key])


## Condição prevista no fim da estação sem reparo (para a tela).
func forecast_condition(b: Dictionary, season_id: String, days_left: int) -> float:
	var c: float = b.condition
	for _d in days_left:
		var wear: float = _types[b.type].wear.get(season_id, 0.0)
		if c < _cfg.low_condition_threshold:
			wear *= _cfg.low_condition_wear_mult
		c = maxf(c - wear, 0.0)
	return c


func snapshot() -> Dictionary:
	return {"materials": materials, "ruins_remaining": ruins_remaining,
		"ruins_initial": ruins_initial, "instances": instances.duplicate(true),
		"queue": queue.map(func(j: Dictionary) -> Dictionary:
			var d := j.duplicate()
			d.cost_points = _types[j.type].cost_points
			d.cost_materials = _types[j.type].cost_materials
			return d)}
