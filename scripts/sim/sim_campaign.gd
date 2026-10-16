class_name SimCampaign
extends RefCounted
## Campanha com prazo (D-046, D-047). A partida termina no último dia do ano `years`
## (ou antes, se a colônia esvaziar). O desfecho vem da população final sobre a inicial,
## pelas faixas de `outcomes` (crescentes). Também guarda o resumo da tela de fim.
##   - Ao entrar no último ano: evento "campaign_final_year" (o aviso é só narrativo).
##   - Nos últimos `lock_days` dias: medidas novas recusadas, para nenhuma cobrança ficar
##     depois do fim. `lock_days` = maior duração de efeito "depois" das medidas (dados).
##   - Fim: eventos "campaign_ended" + entrada final do diário; a simulação para.

var years: int
var lock_days: int
var initial: int
var ended := false
var outcome := ""
## População no fim de cada ano já fechado (índice 0 = ano 1).
var pop_by_year: Array[int] = []
var deaths := 0
var left := 0
var built := 0

var _outcomes: Array
## População no fim do dia anterior (vira a do fim do ano quando o ano muda).
var _people_at_turn := 0


func _init(cfg: Dictionary, social_cfg: Dictionary, initial_people: int) -> void:
	years = cfg.years
	_outcomes = cfg.outcomes
	initial = initial_people
	_people_at_turn = initial_people
	lock_days = 0
	for m in social_cfg.get("measures", {}).values():
		lock_days = maxi(lock_days, int(m.after_days))


## Último day_index simulado da campanha.
func last_day(calendar: SimCalendar) -> int:
	return years * calendar.days_per_year() - 1


## Dias até o fim contando o de hoje (1 no último dia).
func days_left(calendar: SimCalendar) -> int:
	return last_day(calendar) - calendar.day_index + 1


func measures_locked(calendar: SimCalendar) -> bool:
	return days_left(calendar) <= lock_days


## Desfecho para uma população final (faixas por fração da inicial).
func outcome_for(people: int) -> String:
	var frac := float(people) / float(initial) if initial > 0 else 0.0
	var id: String = _outcomes[0].id
	for o in _outcomes:
		if frac >= o.get("from", 0.0) - 1e-9:
			id = o.id
	return id


## Aviso de entrada no último ano (antes da Narrative, que o transforma em fala).
func final_year_event(events: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if e.type == "year_changed" and e.year == years:
			out.append({"type": "campaign_final_year", "year": e.year, "years": years})
	return out


## Fim do passo do dia: conta o dia e decide se a campanha acabou.
func step(calendar: SimCalendar, people: int, events: Array[Dictionary],
		measures_used: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if ended:
		return out
	var empty := false
	for e in events:
		match e.type:
			"death":
				deaths += 1
			"family_left":
				left += 1
			"building_completed":
				built += 1
			"colony_empty":
				empty = true
			"year_changed":
				pop_by_year.append(_people_at_turn)
	_people_at_turn = people
	if calendar.day_index >= last_day(calendar) or empty:
		ended = true
		pop_by_year.append(people)
		outcome = outcome_for(people)
		var params := {"population": people, "initial": initial, "deaths": deaths, "left": left}
		out.append({"type": "diary", "season": calendar.season_id(), "mood": "END",
			"key": "DIARY_END_" + outcome.to_upper(), "params": params})
		out.append({"type": "campaign_ended", "outcome": outcome, "summary": summary(measures_used)})
	return out


func summary(measures_used: Dictionary = {}) -> Dictionary:
	var worst_year := 0
	var worst_lost := 0
	var prev := initial
	for i in pop_by_year.size():
		var lost := prev - pop_by_year[i]
		if lost > worst_lost:
			worst_lost = lost
			worst_year = i + 1
		prev = pop_by_year[i]
	return {"outcome": outcome, "population": pop_by_year.back() if ended else -1,
		"initial": initial, "deaths": deaths, "left": left, "built": built,
		"pop_by_year": pop_by_year.duplicate(), "worst_year": worst_year,
		"worst_lost": worst_lost, "measures": measures_used.duplicate()}


func snapshot(calendar: SimCalendar) -> Dictionary:
	return {"years": years, "year": mini(calendar.year(), years), "days_left": maxi(days_left(calendar), 0),
		"final_year": calendar.year() >= years, "measures_locked": measures_locked(calendar),
		"ended": ended, "outcome": outcome}
