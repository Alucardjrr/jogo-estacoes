class_name SimSocial
extends RefCounted
## Sistema social (GDD 6, GDD 10 sistema 10; D-011, D-035..D-038).
##   Passo 4 — publish(): modificadores das medidas ativas e das curvas dos medidores
##     (confiança → productivity_mult; coesão → departure_days_mult). Expira medidas
##     da estação que acabou e começa os efeitos "depois".
##   Passo 9 — update(): medidores reagem ao dia (falta, mortes, partidas) e
##     recuperam até o teto.
##   Comando enact(): ativa uma medida (custo na hora, residual baixa o teto).
## Ids seguem o GDD 6; nomes de jogador ficam no CSV (D-036).

const SOURCE := "social"

var trust: float
var cohesion: float
var trust_ceiling := 100.0
var cohesion_ceiling := 100.0
## Medidas ativas: [{id, season, year}] — expiram quando (estação, ano) muda.
var active: Array[Dictionary] = []
## Efeitos "depois": [{id, days_left}]
var after: Array[Dictionary] = []
## Usos totais por medida (para o custo crescente).
var uses: Dictionary = {}
## Medidas sazonais já ativadas nesta (estação, ano) — regra uma por estação.
var _season_key := ""
var _enacted_this_season: Array[String] = []
var _low := {"trust": false, "cohesion": false}

var _cfg: Dictionary


func _init(cfg: Dictionary) -> void:
	_cfg = cfg
	trust = cfg.trust_initial
	cohesion = cfg.cohesion_initial


func measure_ids() -> PackedStringArray:
	var ids := PackedStringArray(_cfg.measures.keys())
	return ids


func is_active(id: String) -> bool:
	return active.any(func(a: Dictionary) -> bool: return a.id == id)


## Custo atual de uma medida (com o aumento por repetição).
func cost(id: String) -> Dictionary:
	var m: Dictionary = _cfg.measures[id]
	var k: float = 1.0 + _cfg.repeat_cost_increase * uses.get(id, 0)
	return {"trust": m.trust_cost * k, "cohesion": m.cohesion_cost * k}


## Motivo de recusa (código) ou "" se pode ativar agora.
func check(id: String, season_id: String, year: int, water_frac: float) -> String:
	if not _cfg.measures.has(id):
		return "invalid_measure"
	var m: Dictionary = _cfg.measures[id]
	if not m.seasons.is_empty() and not m.seasons.has(season_id):
		return "wrong_season"
	if m.unlock_water_below > 0.0 and water_frac >= m.unlock_water_below:
		return "locked"
	# Só leitura: se a (estação, ano) mudou, nada foi ativado nela ainda.
	var enacted: Array[String] = []
	if _season_key == _key(season_id, year):
		enacted = _enacted_this_season
	if enacted.has(id):
		return "already_enacted"
	if _cfg.one_per_season and not m.exempt_one_per_season:
		for other in enacted:
			if not _cfg.measures[other].exempt_one_per_season:
				return "one_per_season"
	return ""


## Ativa (já checada). Retorna o evento. Água instantânea é aplicada por quem chama.
func enact(id: String, season_id: String, year: int) -> Dictionary:
	var m: Dictionary = _cfg.measures[id]
	var c := cost(id)
	var residual: float = 1.0 if m.full_residual else _cfg.residual_fraction
	trust = maxf(trust - c.trust, 0.0)
	cohesion = maxf(cohesion - c.cohesion, 0.0)
	trust_ceiling = maxf(trust_ceiling - c.trust * residual, 0.0)
	cohesion_ceiling = maxf(cohesion_ceiling - c.cohesion * residual, 0.0)
	trust = minf(trust, trust_ceiling)
	cohesion = minf(cohesion, cohesion_ceiling)
	uses[id] = uses.get(id, 0) + 1
	_roll_season(season_id, year)
	_enacted_this_season.append(id)
	if not m.effects.is_empty():
		active.append({"id": id, "season": season_id, "year": year})
	return {"type": "measure_enacted", "measure": id, "trust_cost": c.trust,
		"cohesion_cost": c.cohesion}


## Parâmetros para a descrição da medida na tela (D-024: texto no CSV, números do dado).
## Chave = chave do efeito (ex.: "water_consumption"); depois: "after_<chave>",
## "after_days"; água na hora: "water_days". "<chave>__mul" marca multiplicador.
func describe(id: String) -> Dictionary:
	var m: Dictionary = _cfg.measures[id]
	var out := {"after_days": m.after_days, "water_days": m.instant_water_days,
		"unlock_pct": m.unlock_water_below * 100.0}
	for e in m.effects:
		out[e.key] = e.get("mul", e.get("add"))
		if e.has("mul"):
			out[e.key + "__mul"] = true
	for e in m.after_effects:
		out["after_" + e.key] = e.get("mul", e.get("add"))
		if e.has("mul"):
			out["after_" + e.key + "__mul"] = true
	return out


func instant_water(id: String, people: int) -> float:
	return _cfg.measures[id].instant_water_days * people


## Passo 4. Retorna eventos de expiração.
func publish(season_id: String, year: int, modifiers: ModifierStack) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	modifiers.clear_source(SOURCE)
	_roll_season(season_id, year)
	# Expira medidas da estação anterior e começa o "depois".
	var still: Array[Dictionary] = []
	for a in active:
		if a.season == season_id and a.year == year:
			still.append(a)
		else:
			events.append({"type": "measure_expired", "measure": a.id})
			var days: int = _cfg.measures[a.id].after_days
			if days > 0:
				after.append({"id": a.id, "days_left": days})
	active = still
	for a in active:
		_apply(_cfg.measures[a.id].effects, modifiers)
	var keep: Array[Dictionary] = []
	for f in after:
		_apply(_cfg.measures[f.id].after_effects, modifiers)
		f.days_left -= 1
		if f.days_left > 0:
			keep.append(f)
	after = keep
	modifiers.mul("productivity_mult", SOURCE, curve(trust, _cfg.trust_productivity))
	modifiers.mul("departure_days_mult", SOURCE, curve(cohesion, _cfg.cohesion_departure))
	return events


## Passo 9.
func update(short_today: bool, deaths: int, left: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if short_today:
		trust -= _cfg.shortage_trust_per_day
	else:
		trust += _cfg.recovery_per_day
		cohesion += _cfg.recovery_per_day
	cohesion -= deaths * _cfg.death_cohesion + left * _cfg.left_cohesion
	trust = clampf(trust, 0.0, trust_ceiling)
	cohesion = clampf(cohesion, 0.0, cohesion_ceiling)
	for meter in ["trust", "cohesion"]:
		var low: bool = get(meter) < _cfg.low_threshold
		if low and not _low[meter]:
			events.append({"type": "meter_low", "meter": meter})
		_low[meter] = low
	return events


## 1 em ≥ full_at; linear até mid_mult em mid_at; linear até zero_mult em 0.
static func curve(v: float, c: Dictionary) -> float:
	if v >= c.full_at:
		return 1.0
	if v >= c.mid_at:
		var span: float = c.full_at - c.mid_at
		return c.mid_mult + (1.0 - c.mid_mult) * ((v - c.mid_at) / span if span > 0.0 else 1.0)
	if c.mid_at <= 0.0:
		return c.mid_mult
	return c.zero_mult + (c.mid_mult - c.zero_mult) * maxf(v, 0.0) / c.mid_at


func snapshot() -> Dictionary:
	return {"trust": trust, "cohesion": cohesion, "trust_ceiling": trust_ceiling,
		"cohesion_ceiling": cohesion_ceiling, "active": active.map(func(a: Dictionary) -> String: return a.id),
		"after": after.duplicate(true), "uses": uses.duplicate(),
		"enacted_this_season": _enacted_this_season.duplicate()}


func _apply(effects: Array, modifiers: ModifierStack) -> void:
	for e in effects:
		if e.has("mul"):
			modifiers.mul(e.key, SOURCE, e.mul)
		else:
			modifiers.add(e.key, SOURCE, e.add)


static func _key(season_id: String, year: int) -> String:
	return "%s/%d" % [season_id, year]


func _roll_season(season_id: String, year: int) -> void:
	var key := _key(season_id, year)
	if key != _season_key:
		_season_key = key
		_enacted_this_season.clear()
