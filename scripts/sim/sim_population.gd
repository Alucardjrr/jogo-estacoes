class_name SimPopulation
extends RefCounted
## Famílias agregadas (GDD 10, sistema 7; D-016). Uma saúde só para a colônia
## (0..health_max). Lê o fluxo do dia de Resources (déficit) e a pilha de
## modificadores (health_drift, publicado por Season). Toda aleatoriedade vem
## do RNG único passado pela Simulation (D-020).
##
## Ordem do dia:
##   1. saúde: + health_drift; com falta: − água×fração − comida×fração;
##      sem falta: + recuperação. Limitada a [0, health_max].
##   2. mortes: abaixo do limiar, cada pessoa contribui com
##      death_rate_max × (limiar − saúde)/limiar; frações acumulam e cada
##      pessoa inteira morre (pessoa sorteada → família dela perde 1).
##   3. partida: departure_shortage_days dias seguidos com falta → uma família
##      sorteada vai embora e o contador zera.

var families: Array[Dictionary] = []  # [{id, size}] — família com size 0 sai da lista
var health: float
var shortage_streak := 0

var _cfg: Dictionary
var _death_acc := 0.0
var _empty_reported := false


func _init(cfg: Dictionary) -> void:
	_cfg = cfg
	for f in cfg.families:
		families.append({"id": f.id, "size": int(f.size)})
	health = cfg.health_initial


func people() -> int:
	var n := 0
	for f in families:
		n += f.size
	return n


## flow: SimResources.last_flow do mesmo dia. Retorna eventos.
func step(flow: Dictionary, modifiers: ModifierStack, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var fw := _deficit_fraction(flow, "water")
	var ff := _deficit_fraction(flow, "food")
	var short := fw > 0.0 or ff > 0.0

	# 1. Saúde
	var dh := modifiers.value("health_drift")
	if short:
		dh -= _cfg.water_shortage_health * fw + _cfg.food_shortage_health * ff
		shortage_streak += 1
	else:
		dh += _cfg.health_recovery_per_day
		shortage_streak = 0
	health = clampf(health + dh, 0.0, _cfg.health_max)

	# 2. Mortes
	var threshold: float = _cfg.death_health_threshold
	if health < threshold and people() > 0:
		_death_acc += people() * _cfg.death_rate_max * (threshold - health) / threshold
		while _death_acc >= 1.0 and people() > 0:
			_death_acc -= 1.0
			events.append(_kill_random_person(rng))
	else:
		_death_acc = 0.0  # saiu da zona de risco: fração pendente não "cobra" depois

	# 3. Partida
	# Coesão baixa (Social) encurta o prazo; nunca menos de 1 dia.
	var departure_days := maxi(1, ceili(_cfg.departure_shortage_days
		* modifiers.value("departure_days_mult", 1.0)))
	if shortage_streak >= departure_days and not families.is_empty():
		var i := rng.randi_range(0, families.size() - 1)
		var f: Dictionary = families[i]
		families.remove_at(i)
		shortage_streak = 0
		events.append({"type": "family_left", "family": f.id, "size": f.size})

	if people() == 0 and not _empty_reported:
		_empty_reported = true
		_death_acc = 0.0
		events.append({"type": "colony_empty"})
	return events


func _deficit_fraction(flow: Dictionary, id: String) -> float:
	var f: Dictionary = flow.get(id, {})
	var demand: float = f.get("demand", 0.0)
	if demand <= 0.0:
		return 0.0
	return clampf(f.get("deficit", 0.0) / demand, 0.0, 1.0)


## Sorteia uma pessoa (famílias maiores têm mais chance), tira 1 da família dela.
func _kill_random_person(rng: RandomNumberGenerator) -> Dictionary:
	var pick := rng.randi_range(0, people() - 1)
	for i in families.size():
		var f: Dictionary = families[i]
		if pick < f.size:
			f.size -= 1
			if f.size == 0:
				families.remove_at(i)
			return {"type": "death", "family": f.id}
		pick -= f.size
	return {}  # inalcançável: people() > 0 garantido por quem chama
