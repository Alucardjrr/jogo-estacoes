class_name Simulation
extends RefCounted
## Raiz da simulação (D-020). Roda sem tela: a apresentação só lê snapshot()
## e envia comandos. Ordem do tick conforme GDD 10; existem os passos
## 0 (comandos), 1 (Calendar), 2 (Season), 5a (efeitos dos prédios), 5 (Labor),
## 6 (Buildings: saque, desgaste, obras), 7 (Resources), 8 (Population) e
## 10 (Narrative: diário e falas, só texto).
##
## Comandos de jogo:
##   {"type": "set_labor", "task": "water"|"farm"|"care", "value": int ≥ 0}
##   {"type": "adjust_labor", "task": ..., "delta": int} — soma ao pedido atual
##   {"type": "build", "building": id} — põe na fila de obras
##   {"type": "enact_measure", "measure": id} — ativa medida social (GDD 6)
## Recusados viram evento "command_rejected" com o motivo; aceitos, "labor_changed"
## ou "build_queued".

var data := DataRegistry.new()
var loop: SimLoop
var calendar: SimCalendar
var season: SimSeason
var resources: SimResources
var population: SimPopulation
var labor: SimLabor
var buildings: SimBuildings
var narrative: SimNarrative
var social: SimSocial
var forecast: SimForecast
var modifiers := ModifierStack.new()

var _events: Array[Dictionary] = []


## Carrega dados e monta os sistemas. seed_number < 0 usa a semente padrão dos dados.
## Retorna false com os motivos em data.errors.
func setup(seed_number: int = -1, data_dir: String = DataRegistry.DEFAULT_DIR) -> bool:
	if not data.load_all(data_dir):
		return false
	var sim_cfg := data.section("sim")
	loop = SimLoop.new(sim_cfg, seed_number if seed_number >= 0 else sim_cfg.default_seed)
	calendar = SimCalendar.new(data.section("calendar"))
	season = SimSeason.new(data.section("season"))
	resources = SimResources.new(data.section("resources"))
	modifiers = ModifierStack.new()
	modifiers.register_keys(_modifier_keys())
	population = SimPopulation.new(data.section("population"))
	labor = SimLabor.new(data.section("labor"))
	buildings = SimBuildings.new(data.section("buildings"))
	narrative = SimNarrative.new(data.section("narrative"))
	social = SimSocial.new(data.section("social"))
	forecast = SimForecast.new(data.section("forecast"), data.section("calendar"))
	# Clima dos anos 1 e 2 sorteado antes de qualquer outro uso do RNG (ordem fixa).
	forecast.draw_year(1, loop.rng)
	forecast.draw_year(2, loop.rng)
	season.factors = forecast.factors()
	season.publish(calendar, modifiers)  # tela já mostra as taxas do dia 1
	social.publish(calendar.season_id(), calendar.year(), modifiers)
	labor.step(population.people(), population.health, modifiers)
	_events.clear()
	return true


func is_ready() -> bool:
	return calendar != null


func enqueue(command: Dictionary) -> bool:
	return loop.enqueue(command)


func step_day() -> void:
	var first_event := _events.size()
	# 0. Comandos (medidas sociais ficam para depois da virada do calendário, para
	#    valerem na estação do dia que está sendo simulado — QA PR #15)
	var social_commands: Array[Dictionary] = []
	for command in loop.take_commands():
		if command.type == "enact_measure":
			social_commands.append(command)
		else:
			_apply_command(command)
	# 1. Calendar (virada de estação/ano)
	_events.append_array(calendar.advance())
	for command in social_commands:
		_apply_measure(command)
	# 1b. Forecast: ao virar o ano, sorteia o clima do ano SEGUINTE (ponto fixo; o do ano
	#     corrente já foi sorteado um ano antes, então Season deste dia não depende disto)
	if _events.slice(first_event).any(func(e: Dictionary) -> bool: return e.type == "year_changed"):
		forecast.draw_year(calendar.year() + 1, loop.rng)
		season.factors = forecast.factors()
	# 2. Season publica as taxas do dia
	season.publish(calendar, modifiers)
	# 4. Social publica medidas ativas e curvas dos medidores
	_events.append_array(social.publish(calendar.season_id(), calendar.year(), modifiers))
	# 5a. Efeitos dos prédios (estação de hoje; condição e falta de água de ontem),
	#     antes de Labor, que lê farm_mult/gather_mult
	buildings.publish_effects(calendar.season_id(), resources.last_flow.water.deficit > 0.0, modifiers)
	# 5. Labor publica a produção do dia (lê pessoas/saúde do fim de ontem)
	labor.step(population.people(), population.health, modifiers)
	# 6. Buildings: saque, desgaste, obras
	_events.append_array(buildings.step(labor, calendar.season_id(), modifiers))
	# 7. Resources
	_events.append_array(resources.step(population.people(), modifiers))
	# 8. Population (lê o déficit do dia em Resources)
	_events.append_array(population.step(resources.last_flow, modifiers, loop.rng))
	# 9. Social: medidores reagem ao dia
	var today := _events.slice(first_event)
	_events.append_array(social.update(
		resources.last_flow.water.deficit > 0.0 or resources.last_flow.food.deficit > 0.0,
		today.filter(func(e: Dictionary) -> bool: return e.type == "death").size(),
		today.filter(func(e: Dictionary) -> bool: return e.type == "family_left").size()))
	# 10. Narrative: lê os eventos do dia e acrescenta diário/falas
	_events.append_array(narrative.step(calendar.day_index, calendar.year(),
		population.people(), _events.slice(first_event)))


## Avança pelo relógio de tempo real. Retorna quantos dias passaram.
func advance(delta: float, speed: int) -> int:
	var days := loop.days_due(delta, speed)
	for _i in days:
		step_day()
	return days


func drain_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


func snapshot() -> Dictionary:
	return {
		"day_index": calendar.day_index,
		"year": calendar.year(),
		"month": calendar.month(),
		"day": calendar.day_of_month(),
		"season": calendar.season_id(),
		"season_severe": calendar.season_is_severe(),
		"day_in_season": calendar.day_in_season(),
		"season_days": calendar.season_length_days(),
		"intensity": season.intensity(calendar),
		"population": population.people(),
		"families": population.families.size(),
		"health": population.health,
		"shortage_streak": population.shortage_streak,
		"labor": labor.snapshot(),
		"buildings": buildings.snapshot(),
		"social": social.snapshot(),
		"forecast": forecast.forecast(calendar, season),
		"resources": _resources_snapshot(),
		"modifiers": modifiers.entries(),
		"seed": loop.seed_value,
		"rng_state": loop.rng.state,
	}


## Todas as chaves que algum sistema publica ou lê.
func _modifier_keys() -> PackedStringArray:
	var keys := DataRegistry.SEASON_KEYS.duplicate()
	for id in DataRegistry.RESOURCE_IDS:
		keys.append(id + "_consumption")
		keys.append(id + "_capacity")
	keys.append_array(["productivity_mult", "build_mult", "salvage_mult", "departure_days_mult"])
	return keys


func _resources_snapshot() -> Dictionary:
	var out := {}
	for id in DataRegistry.RESOURCE_IDS:
		out[id] = resources.last_flow[id].duplicate()
		out[id].stock = resources.stock[id]
		out[id].capacity = resources.capacity(id)
	return out


func _apply_command(command: Dictionary) -> void:
	match command.type:
		"set_labor", "adjust_labor":
			_apply_labor(command)
		"build":
			var id: Variant = command.get("building")
			if not id is String or not buildings.is_buildable(id):
				_reject(command, "invalid_building")
			elif not buildings.can_enqueue():
				_reject(command, "queue_full")
			else:
				buildings.enqueue(id)
				_events.append({"type": "build_queued", "building": id,
					"position": buildings.queue.size(), "max": int(data.section("buildings").max_queue)})
		_:
			_reject(command, "unknown_type")


func _apply_measure(command: Dictionary) -> void:
	var id: Variant = command.get("measure")
	if not id is String:
		_reject(command, "invalid_measure")
		return
	var why := social.check(id, calendar.season_id(), calendar.year(), water_fraction())
	if why != "":
		_reject(command, why)
		return
	var ev := social.enact(id, calendar.season_id(), calendar.year())
	var gain := social.instant_water(id, population.people())
	if gain > 0.0:
		var before: float = resources.stock.water
		resources.stock.water = minf(before + gain, resources.capacity("water"))
		ev.water = resources.stock.water - before
	_events.append(ev)


## Fração da capacidade de água (para medidas de desespero).
func water_fraction() -> float:
	var cap := resources.capacity("water")
	return resources.stock.water / cap if cap > 0.0 else 0.0


func _apply_labor(command: Dictionary) -> void:
	var task: Variant = command.get("task")
	if not task is String or not DataRegistry.TASK_IDS.has(task):
		_reject(command, "invalid_task")
		return
	var key := "value" if command.type == "set_labor" else "delta"
	var raw: Variant = command.get(key)
	# Inteiro de verdade: JSON/replay entregam float; 2.5, texto ou null são recusados.
	if not (raw is int or (raw is float and raw == floorf(raw) and absf(raw) < 1e6)):
		_reject(command, "not_integer")
		return
	var n := int(raw)
	var value: int = n if command.type == "set_labor" else labor.desired[task] + n
	if value < 0:
		_reject(command, "negative")
		return
	labor.set_desired(task, value)
	_events.append({"type": "labor_changed", "task": task, "value": value})


## Motivos são códigos (texto de jogador fica no CSV, D-024): a tela traduz
## REJECT_<MOTIVO>. Lista completa em REJECT_REASONS.
const REJECT_REASONS: PackedStringArray = ["unknown_type", "invalid_task", "not_integer",
	"negative", "invalid_building", "queue_full", "invalid_measure", "wrong_season", "locked",
	"already_enacted", "one_per_season"]


func _reject(command: Dictionary, reason: String) -> void:
	_events.append({"type": "command_rejected", "command": command.get("type"), "reason": reason})
