class_name SimSeason
extends RefCounted
## Intensidade da estação + escalada anual (GDD 10, sistema 4).
## Não guarda estado próprio: tudo deriva do calendário, então save/replay não
## precisam de nada extra. Publica as taxas da estação atual como modificadores
## "add" da fonte "season"; Resources não conhece estações.
##
## Intensidade = min(intensity_max, 1 + intensity_per_year × (ano − 1)) nas
## estações severas; 1 nas brandas. Cada grandeza da estação é multiplicada por
## intensidade^expoente (escalation). Expoente negativo = piora reduzindo
## (ex.: menos chuva na seca); positivo = piora aumentando.

const SOURCE := "season"

var _per_year: float
var _max: float
var _seasons: Dictionary


func _init(cfg: Dictionary) -> void:
	_per_year = cfg.intensity_per_year
	_max = cfg.intensity_max
	_seasons = cfg.seasons


func intensity(calendar: SimCalendar) -> float:
	if not calendar.season_is_severe():
		return 1.0
	return minf(_max, 1.0 + _per_year * (calendar.year() - 1))


## Valor efetivo de uma grandeza (ex.: "water_inflow") hoje.
func rate(calendar: SimCalendar, key: String) -> float:
	var s: Dictionary = _seasons[calendar.season_id()]
	var exponent: float = s.escalation.get(key, 0.0)
	return s[key] * pow(intensity(calendar), exponent)


func publish(calendar: SimCalendar, modifiers: ModifierStack) -> void:
	modifiers.clear_source(SOURCE)
	for key in DataRegistry.SEASON_KEYS:
		modifiers.add(key, SOURCE, rate(calendar, key))
