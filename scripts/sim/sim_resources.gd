class_name SimResources
extends RefCounted
## Estoques com perdas (GDD 10, sistema 6). Lê as taxas da pilha de
## modificadores; não conhece estações nem população (o consumo chega pronto).
##
## Ordem do dia, por recurso:
##   1. entrada (<id>_inflow)
##   2. consumo: atende o que der; o que faltar vira evento "shortage"
##   3. teto: o que passar de capacity é perdido (overflow)
##   4. perda: estoque × <id>_loss_rate
## Estoque nunca fica negativo. Tudo em float; a tela arredonda.

var _cfg: Dictionary          # id -> {initial, capacity, per_capita_daily}
var _capacity: Dictionary = {}  # id -> teto do dia (base + <id>_capacity da pilha)
var stock: Dictionary = {}    # id -> float
## Fluxo do último dia, para a tela de debug: id -> {inflow, demand, consumed,
## deficit, overflow, lost}.
var last_flow: Dictionary = {}


func _init(cfg: Dictionary) -> void:
	_cfg = cfg.resources
	for id in DataRegistry.RESOURCE_IDS:
		stock[id] = float(_cfg[id].initial)
		_capacity[id] = float(_cfg[id].capacity)
		last_flow[id] = _empty_flow()


## Teto usado no último dia (base dos dados + prédios via <id>_capacity).
func capacity(id: String) -> float:
	return _capacity[id]


## Demanda diária de um recurso para `population` pessoas, já com os
## multiplicadores de consumo (<id>_consumption) — ex.: racionamento no futuro.
func demand(id: String, population: int, modifiers: ModifierStack) -> float:
	var base: float = population * float(_cfg[id].per_capita_daily)
	return modifiers.value(id + "_consumption", base)


## Avança 1 dia. Retorna os eventos de falta (um por recurso em falta).
func step(population: int, modifiers: ModifierStack) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for id in DataRegistry.RESOURCE_IDS:
		var f := _empty_flow()
		var s: float = stock[id]
		_capacity[id] = maxf(modifiers.value(id + "_capacity", float(_cfg[id].capacity)), 0.0)
		f.inflow = maxf(modifiers.value(id + "_inflow"), 0.0)
		s += f.inflow
		f.demand = maxf(demand(id, population, modifiers), 0.0)
		f.consumed = minf(s, f.demand)
		f.deficit = f.demand - f.consumed
		s -= f.consumed
		if s > capacity(id):
			f.overflow = s - capacity(id)
			s = capacity(id)
		var rate := clampf(modifiers.value(id + "_loss_rate"), 0.0, 1.0)
		f.lost = s * rate
		s -= f.lost
		stock[id] = maxf(s, 0.0)
		last_flow[id] = f
		if f.deficit > 0.0:
			events.append({"type": "shortage", "resource": id, "deficit": f.deficit})
	return events


func _empty_flow() -> Dictionary:
	return {"inflow": 0.0, "demand": 0.0, "consumed": 0.0, "deficit": 0.0,
		"overflow": 0.0, "lost": 0.0}
