class_name Simulation
extends RefCounted
## Raiz da simulação (D-020). Roda sem tela: a apresentação só lê snapshot()
## e envia comandos. Ordem do tick conforme GDD 10; existem os passos
## 0 (comandos), 1 (Calendar), 2 (Season), 7 (Resources) e 8 (Population).

var data := DataRegistry.new()
var loop: SimLoop
var calendar: SimCalendar
var season: SimSeason
var resources: SimResources
var population: SimPopulation
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
	population = SimPopulation.new(data.section("population"))
	season.publish(calendar, modifiers)  # tela já mostra as taxas do dia 1
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
	# 3..6: Forecast, Social, Labor, Buildings — próximas etapas.
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
		"resources": _resources_snapshot(),
		"modifiers": modifiers.entries(),
		"seed": loop.seed_value,
		"rng_state": loop.rng.state,
	}


func _resources_snapshot() -> Dictionary:
	var out := {}
	for id in DataRegistry.RESOURCE_IDS:
		out[id] = resources.last_flow[id].duplicate()
		out[id].stock = resources.stock[id]
		out[id].capacity = resources.capacity(id)
	return out


func _apply_command(command: Dictionary) -> void:
	# Nenhum comando de jogo existe ainda; desconhecido vira evento, não erro fatal.
	_events.append({"type": "command_rejected", "command": command.get("type"),
		"reason": "tipo desconhecido"})
