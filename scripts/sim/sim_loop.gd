class_name SimLoop
extends RefCounted
## Relógio e infraestrutura do tick (GDD 10, sistema 2).
## - RNG único com semente: toda aleatoriedade da simulação sai daqui (D-020).
## - Fila de comandos: UI -> sim, aplicados no início do tick (permite replay).
## - Relógio: converte tempo real em dias. Só a apresentação usa; testes e o
##   runner de balanceamento chamam Simulation.step_day() direto.

var rng := RandomNumberGenerator.new()
var seed_value: int
var seconds_per_day: float
var max_days_per_frame: int

var _commands: Array[Dictionary] = []
var _accumulator := 0.0


func _init(cfg: Dictionary, seed_number: int) -> void:
	seconds_per_day = cfg.seconds_per_day
	max_days_per_frame = cfg.max_days_per_frame
	seed_value = seed_number
	rng.seed = seed_number


## Comando precisa de "type" (String). Validação do conteúdo fica com quem aplica.
func enqueue(command: Dictionary) -> bool:
	if not command.get("type") is String:
		return false
	_commands.append(command.duplicate(true))
	return true


func take_commands() -> Array[Dictionary]:
	var out := _commands
	_commands = []
	return out


## Quantos dias devem passar neste frame. speed = multiplicador (0 = pausado).
## O excedente acima do teto por frame é descartado para não "engasgar" depois
## de um travamento longo.
func days_due(delta: float, speed: int) -> int:
	if speed <= 0 or delta <= 0.0:
		return 0
	_accumulator += delta * speed
	# Tolerância: somas de frames (ex.: 180 × 1/60) dão 2,9999… em float.
	var days := int(floor(_accumulator / seconds_per_day + 1e-6))
	_accumulator = maxf(_accumulator - days * seconds_per_day, 0.0)
	if days > max_days_per_frame:
		days = max_days_per_frame
		_accumulator = 0.0
	return days


## Fração do dia atual já decorrida (0..1), para animar a apresentação.
func day_progress() -> float:
	return clampf(_accumulator / seconds_per_day, 0.0, 1.0)
