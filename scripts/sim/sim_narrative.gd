class_name SimNarrative
extends RefCounted
## Narrativa mínima (GDD 7, GDD 10 sistema 11; D-034). Passo 10 do tick: lê os
## eventos do dia e devolve eventos de texto — a tela só traduz.
##   - "diary": ao virar a estação, uma entrada sobre a estação que acabou
##     ({year}, {population}, {deaths}, {left} = famílias que partiram, {built}).
##     HARD se houve morte, partida ou ≥ hard_shortage_days dias de falta; senão CALM.
##   - "speech": no máximo uma fala por dia, de um morador nomeado, reagindo ao
##     evento mais importante (morte > partida > obra pronta > início de falta > estação).
## Escolha de linha e de morador é determinística pelo dia (sem usar o RNG da
## simulação: texto não pode mudar o balanceamento).

var _cfg: Dictionary
var _deaths := 0
var _left := 0
var _built := 0
var _shortage_days := 0
var _short_yesterday := {}  # recurso -> bool


func _init(cfg: Dictionary) -> void:
	_cfg = cfg


func step(day: int, year: int, population: int, events: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var speech := {}
	var short_today := {}
	var priority := 99
	for e in events:
		match e.type:
			"season_changed":
				# o diário fala da estação que terminou, com o ano dela
				var ended_year := year - 1 if _year_turned(events) else year
				out.append(_diary(e.from, ended_year, day, population))
				var group: String = _cfg.season_group.get(e.to, "")
				if group != "" and priority > 4:
					priority = 4
					speech = {"line": "SEASON_" + group}
			"death":
				_deaths += 1
				if priority > 0:
					priority = 0
					speech = {"line": "DEATH"}
			"family_left":
				_left += 1
				if priority > 1:
					priority = 1
					speech = {"line": "FAMILY_LEFT"}
			"building_completed":
				_built += 1
				if priority > 2:
					priority = 2
					speech = {"line": "BUILDING_DONE", "building": e.building}
			"shortage":
				short_today[e.resource] = true
				if not _short_yesterday.get(e.resource, false) and priority > 3:
					priority = 3
					speech = {"line": "SHORTAGE_" + String(e.resource).to_upper()}
	if not short_today.is_empty():
		_shortage_days += 1
	_short_yesterday = short_today
	if not speech.is_empty():
		var n: int = _cfg.reaction_lines.get(speech.line, 0)
		if n > 0:
			var ev := {"type": "speech", "key": "REACT_%s_%d" % [speech.line, _pick(day, 7, n) + 1],
				"resident": "RESIDENT_%02d" % (_pick(day, 13, int(_cfg.residents)) + 1)}
			if speech.has("building"):
				ev.building = speech.building
			out.append(ev)
	return out


func _year_turned(events: Array[Dictionary]) -> bool:
	return events.any(func(e: Dictionary) -> bool: return e.type == "year_changed")


func _diary(season_id: String, year: int, day: int, population: int) -> Dictionary:
	var group: String = _cfg.season_group.get(season_id, "")
	var hard := _deaths > 0 or _left > 0 or _shortage_days >= int(_cfg.hard_shortage_days)
	var ev := {"type": "diary", "season": season_id,
		"key": "DIARY_%s_%s_%d" % [group, "HARD" if hard else "CALM", _pick(day, 3, int(_cfg.diary_lines)) + 1],
		"params": {"year": year, "population": population, "deaths": _deaths, "left": _left,
			"built": _built}}
	_deaths = 0
	_left = 0
	_built = 0
	_shortage_days = 0
	return ev


## Escolha estável e espalhada: mesma entrada → mesma linha, sem RNG.
static func _pick(day: int, salt: int, n: int) -> int:
	return absi((day * 2654435761 + salt * 40503) % 1000003) % n
