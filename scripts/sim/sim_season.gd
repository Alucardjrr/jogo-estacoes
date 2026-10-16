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
##
## Transição (D-027): janela de transition_days centrada na virada. Dentro dela
## o valor é a mistura das duas estações com curva smoothstep; cada lado usa a
## intensidade do próprio ano. O 1º dia do jogo não tem estação anterior.

const SOURCE := "season"

var _per_year: float
var _max: float
var _seasons: Dictionary
var _transition: int
## Fator de variação por estação severa (D-042): "ano/estação" -> f. Preenchido por
## SimForecast; ausente = 1.
var factors: Dictionary = {}


func _init(cfg: Dictionary) -> void:
	_per_year = cfg.intensity_per_year
	_max = cfg.intensity_max
	_seasons = cfg.seasons
	_transition = cfg.transition_days


## Intensidade da estação atual (sem mistura; é o que a tela mostra).
func intensity(calendar: SimCalendar) -> float:
	return _intensity_of(calendar.info_at(calendar.day_index))


## Valor efetivo de uma grandeza (ex.: "water_inflow") hoje, já com transição.
func rate(calendar: SimCalendar, key: String) -> float:
	var day := calendar.day_index
	var info := calendar.info_at(day)
	if _transition <= 0:
		return _raw(info, key)
	var half := _transition / 2.0
	var ds: int = info.day_in_season - 1  # 0-based
	var length: int = info.length
	var from: Dictionary
	var to: Dictionary
	var t: float
	if ds >= length - half:
		from = info
		to = calendar.info_at(day + (length - ds))  # 1º dia da próxima estação
		t = (ds - (length - half) + 0.5) / _transition
	elif ds < half and day - ds - 1 >= 0:
		from = calendar.info_at(day - ds - 1)  # último dia da estação anterior
		to = info
		t = (ds + half + 0.5) / _transition
	else:
		return _raw(info, key)
	var a := _raw(from, key)
	var b := _raw(to, key)
	return a + (b - a) * smoothstep(0.0, 1.0, t)


func _intensity_of(info: Dictionary) -> float:
	if not info.severe:
		return 1.0
	var f: float = factors.get("%d/%s" % [info.year, info.id], 1.0)
	return minf(_max, base_intensity(info.year) * f)  # teto sobre a efetiva (D-025)


## Intensidade da fórmula do ano, sem variação nem teto.
func base_intensity(year: int) -> float:
	return 1.0 + _per_year * (year - 1)


## Intensidade efetiva de uma estação severa de um ano (para a previsão).
func intensity_for(year: int, season_id: String) -> float:
	return _intensity_of({"severe": true, "year": year, "id": season_id})


func _raw(info: Dictionary, key: String) -> float:
	var s: Dictionary = _seasons[info.id]
	var exponent: float = s.escalation.get(key, 0.0)
	return s[key] * pow(_intensity_of(info), exponent)


func publish(calendar: SimCalendar, modifiers: ModifierStack) -> void:
	modifiers.clear_source(SOURCE)
	for key in DataRegistry.SEASON_KEYS:
		modifiers.add(key, SOURCE, rate(calendar, key))
