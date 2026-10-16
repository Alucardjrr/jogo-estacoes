class_name SimCalendar
extends RefCounted
## Converte dias corridos em ano, mês, dia e estação (GDD 10, sistema 3).
## Estado único: `day_index` (0 = dia 1 do mês 1 do ano 1). O resto é derivado,
## então save/replay só precisam desse número.

var day_index: int = 0
var days_per_month: int
var months_per_year: int

var _seasons: Array = []                 # [{id, months, severe}] na ordem do ano
var _season_by_month := PackedInt32Array()  # mês (0-based) -> índice da estação
var _season_start_month := PackedInt32Array()


func _init(cfg: Dictionary) -> void:
	days_per_month = cfg.days_per_month
	months_per_year = cfg.months_per_year
	_seasons = cfg.seasons
	var month := 0
	for i in _seasons.size():
		_season_start_month.append(month)
		for _m in int(_seasons[i].months):
			_season_by_month.append(i)
			month += 1


func days_per_year() -> int:
	return days_per_month * months_per_year


@warning_ignore("integer_division")
func year() -> int:
	return day_index / days_per_year() + 1


@warning_ignore("integer_division")
func month() -> int:
	return (day_index % days_per_year()) / days_per_month + 1


func day_of_month() -> int:
	return day_index % days_per_month + 1


func season_id() -> String:
	return _seasons[_season_index()].id


func season_is_severe() -> bool:
	return _seasons[_season_index()].severe


## Dia dentro da estação atual, começando em 1.
func day_in_season() -> int:
	var start := _season_start_month[_season_index()]
	return (month() - 1 - start) * days_per_month + day_of_month()


func season_length_days() -> int:
	return int(_seasons[_season_index()].months) * days_per_month


## Avança 1 dia e devolve os eventos de virada (estação, ano).
func advance() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var old_season := season_id()
	var old_year := year()
	day_index += 1
	if year() != old_year:
		events.append({"type": "year_changed", "year": year()})
	if season_id() != old_season or (year() != old_year and _seasons.size() == 1):
		events.append({"type": "season_changed", "from": old_season,
			"to": season_id(), "year": year()})
	return events


func _season_index() -> int:
	return _season_by_month[month() - 1]
