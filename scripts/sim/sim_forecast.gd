class_name SimForecast
extends RefCounted
## Previsão mínima (GDD 4, GDD 10 sistema 5; D-042).
## - Cada estação severa de cada ano tem um fator f ∈ [1−v, 1+v] e um erro de
##   previsão e ∈ [−1, 1], sorteados no RNG único (D-020) em ponto fixo: no setup
##   (anos 1 e 2) e no dia em que o ano vira (ano seguinte). A tabela cobre sempre o
##   ano corrente e o próximo, para prever a seca de janeiro.
## - Previsão da próxima severa: margem m = v × I × k (k de k_far a k_near conforme a
##   distância); centro = I + e × m/2; faixa [centro − m, centro + m]. O valor real
##   sempre está dentro (|e × m/2| ≤ m/2 < m) — previsão honesta (pilar 3).

var table: Dictionary = {}  # "ano/estação" -> {f, e}
var _cfg: Dictionary
var _severe: PackedStringArray = []


func _init(cfg: Dictionary, calendar_cfg: Dictionary) -> void:
	_cfg = cfg
	for s in calendar_cfg.seasons:
		if s.severe:
			_severe.append(s.id)


## Sorteia o ano (se ainda não sorteado). Ordem fixa: estações na ordem do calendário.
func draw_year(year: int, rng: RandomNumberGenerator) -> void:
	for sid in _severe:
		var key := "%d/%s" % [year, sid]
		if table.has(key):
			continue
		# Sorteia sempre (sequência do RNG igual), mas antes de first_varied_year f = 1.
		var v: float = _cfg.variance
		var f := rng.randf_range(1.0 - v, 1.0 + v)
		var e := rng.randf_range(-1.0, 1.0)
		if year < int(_cfg.first_varied_year):
			f = 1.0
		table[key] = {"f": f, "e": e}


## Fatores no formato que SimSeason usa.
func factors() -> Dictionary:
	var out := {}
	for k in table:
		out[k] = table[k].f
	return out


func level(intensity: float) -> String:
	for l in _cfg.levels:
		if not l.has("below") or intensity < l.below:
			return l.id
	return _cfg.levels.back().id


## Previsão a partir do dia atual. Durante uma severa: estado real dela.
## include_real: só para testes/ferramentas — a tela nunca recebe o valor real futuro.
func forecast(calendar: SimCalendar, season: SimSeason, include_real := false) -> Dictionary:
	var day := calendar.day_index
	var cur := calendar.info_at(day)
	if cur.severe:
		var now := season.intensity_for(cur.year, cur.id)
		return {"now": true, "season": cur.id, "intensity": now, "level": level(now)}
	# Próxima severa
	var d := day + 1
	var info := calendar.info_at(d)
	while not info.severe:
		d += 1
		info = calendar.info_at(d)
		if d - day > calendar.days_per_year():
			return {}
	var days_until := d - day
	var real := season.intensity_for(info.year, info.id)
	var t := clampf(float(days_until) / float(_cfg.horizon_days), 0.0, 1.0)
	var k: float = _cfg.k_near + (_cfg.k_far - _cfg.k_near) * t
	var m: float = _cfg.variance * real * k
	var e: float = table.get("%d/%s" % [info.year, info.id], {"e": 0.0}).e
	var center := real + e * m / 2.0
	var lo := maxf(center - m, 0.0)
	var hi := center + m
	var out := {"now": false, "season": info.id, "days": days_until, "center": center, "low": lo,
		"high": hi, "level_low": level(lo), "level_high": level(hi)}
	if include_real:
		out.real = real
	return out


func snapshot() -> Dictionary:
	return table.duplicate(true)
