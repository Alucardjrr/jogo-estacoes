class_name Simulation
extends RefCounted
## Raiz da simulação (D-020). Roda sem tela: a apresentação só lê snapshot()
## e envia comandos. Ordem do tick conforme GDD 10; existem os passos
## 0 (comandos), 1 (Calendar), 2 (Season), 5 (Labor), 7 (Resources) e 8 (Population).
##
## Comandos de jogo:
##   {"type": "set_labor", "task": "water"|"farm"|"care", "value": int ≥ 0}
##   {"type": "adjust_labor", "task": ..., "delta": int} — soma ao pedido atual
## Recusados viram evento "command_rejected" com o motivo; aceitos, "labor_changed".

var data := DataRegistry.new()
var loop: SimLoop
var calendar: SimCalendar
var season: SimSeason
var resources: SimResources
var population: SimPopulation
var labor: SimLabor
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
	season.publish(calendar, modifiers)  # tela já mostra as taxas do dia 1
	labor.step(population.people(), population.health, modifiers)
	_events.clear()
	return true


func is_ready() -> bool:
	return calendar != null


func enqueue(command: Dictionary) -> bool:
	return loop.enqueue(command)


func step_day() -> void:
	# 0. Comandos
	for command in loop.take_commands():
		_apply_command(command)
	# 1. Calendar (virada de estação/ano)
	_events.append_array(calendar.advance())
	# 2. Season publica as taxas do dia
	season.publish(calendar, modifiers)
	# 3..4: Forecast, Social — próximas etapas.
	# 5. Labor publica a produção do dia (lê pessoas/saúde do fim de ontem)
	labor.step(population.people(), population.health, modifiers)
	# 6: Buildings — próxima etapa.
	# 7. Resources
	_events.append_array(resources.step(population.people(), modifiers))
	# 8. Population (lê o déficit do dia em Resources)
	_events.append_array(population.step(resources.last_flow, modifiers, loop.rng))
	# 9..10: Social, Narrative — próximas etapas.


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
		_:
			_reject(command, "tipo desconhecido")


func _apply_labor(command: Dictionary) -> void:
	var task: Variant = command.get("task")
	if not task is String or not DataRegistry.TASK_IDS.has(task):
		_reject(command, "tarefa inválida")
		return
	var key := "value" if command.type == "set_labor" else "delta"
	var raw: Variant = command.get(key)
	# Inteiro de verdade: JSON/replay entregam float; 2.5, texto ou null são recusados.
	if not (raw is int or (raw is float and raw == floorf(raw) and absf(raw) < 1e6)):
		_reject(command, "%s precisa ser inteiro" % key)
		return
	var n := int(raw)
	var value: int = n if command.type == "set_labor" else labor.desired[task] + n
	if value < 0:
		_reject(command, "valor negativo")
		return
	labor.set_desired(task, value)
	_events.append({"type": "labor_changed", "task": task, "value": value})


func _reject(command: Dictionary, reason: String) -> void:
	_events.append({"type": "command_rejected", "command": command.get("type"), "reason": reason})
