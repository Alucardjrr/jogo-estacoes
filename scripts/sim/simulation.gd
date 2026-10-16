class_name Simulation
extends RefCounted
## Raiz da simulação (D-020). Roda sem tela: a apresentação só lê snapshot()
## e envia comandos. Ordem do tick conforme GDD 10; por enquanto só os passos
## 0 (comandos) e 1 (Calendar) existem.

var data := DataRegistry.new()
var loop: SimLoop
var calendar: SimCalendar

var _events: Array[Dictionary] = []


## Carrega dados e monta os sistemas. seed_number < 0 usa a semente padrão dos dados.
## Retorna false com os motivos em data.errors.
func setup(seed_number: int = -1, data_dir: String = DataRegistry.DEFAULT_DIR) -> bool:
	if not data.load_all(data_dir):
		return false
	var sim_cfg := data.section("sim")
	loop = SimLoop.new(sim_cfg, seed_number if seed_number >= 0 else sim_cfg.default_seed)
	calendar = SimCalendar.new(data.section("calendar"))
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
	# 2..10: Season, Forecast, Social, Labor, Buildings, Resources,
	#        Population, Social, Narrative — entram nas próximas etapas.


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
		"seed": loop.seed_value,
		"rng_state": loop.rng.state,
	}


func _apply_command(command: Dictionary) -> void:
	# Nenhum comando de jogo existe ainda; desconhecido vira evento, não erro fatal.
	_events.append({"type": "command_rejected", "command": command.get("type"),
		"reason": "tipo desconhecido"})
