class_name AdaptivePolicy
extends RefCounted
## Estratégia adaptativa do runner (BACKLOG P1, D-043): decide a mão de obra a cada
## estação (e a cada `review_days`) lendo a PREVISÃO, os estoques e a saúde — o que um
## jogador atento faria com a tela. Só usa o que a tela mostra (nunca o valor real futuro).
##
## Regras (parâmetros em `p`):
##   janelas: o que acaba nas duas severas é a COMIDA (a roça quase não rende na seca e
##     apodrece/rende menos na chuva dura); a cisterna já chega cheia. Se a previsão da
##     próxima severa chega a "dura" ou pior → roça no máximo, cuidado mínimo.
##   seca: quase todos na água; cuidado mínimo.
##   chuvas: roça + cuidado proporcional à intensidade real da estação.
##   em qualquer estação: se a comida dura menos que `food_alarm` dias, desloca gente
##     para a roça; se a água dura menos que `water_alarm`, para a água.

var p := {
	"workers_hint": 30, "review_days": 15,
	"window_water": 6, "window_care_normal": 6, "window_care_harsh": 0,
	"care_per_intensity": 6.0, "food_alarm": 30, "water_alarm": 20,
}


func _init(params: Dictionary = {}) -> void:
	p.merge(params, true)


func _severe_ahead(snap: Dictionary, level_from: String, sim: Simulation) -> bool:
	var f: Dictionary = snap.forecast
	if f.is_empty() or f.now:
		return false
	var order: Array = (sim.data.section("forecast").levels as Array).map(func(l: Dictionary) -> String: return l.id)
	return order.find(f.level_high) >= order.find(level_from)


## Comandos para hoje (vazio se não é dia de revisar).
func decide(sim: Simulation) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var day_in: int = sim.calendar.day_in_season()
	if day_in != 1 and day_in % int(p.review_days) != 1:
		return out
	var snap := sim.snapshot()
	var workers: int = maxi(snap.labor.workers, 1)
	var sid: String = snap.season
	var alloc := {"water": 0, "farm": 0, "care": 0, "build": 0, "salvage": 0}
	match sid:
		"seca":
			alloc.care = maxi(1, workers / 10)
			alloc.water = workers - alloc.care
		"chuvas":
			alloc.care = mini(workers / 2, roundi(p.care_per_intensity * snap.intensity))
			alloc.farm = workers - alloc.care
		_:
			var harsh: bool = _severe_ahead(snap, "dura", sim)
			alloc.water = int(p.window_water)
			alloc.care = int(p.window_care_harsh if harsh else p.window_care_normal)
			alloc.farm = maxi(workers - alloc.water - alloc.care, 0)
	# Alarmes de estoque (usam só o que a tela mostra: estoque e saldo do dia).
	var food: Dictionary = snap.resources.food
	var water: Dictionary = snap.resources.water
	var food_days: float = _days(food)
	var water_days: float = _days(water)
	if water_days < p.water_alarm and sid != "chuvas":
		var move := mini(alloc.farm, workers / 5)
		alloc.farm -= move
		alloc.water += move
	elif food_days < p.food_alarm and sid != "seca":
		var move := mini(alloc.care, maxi(alloc.care - 2, 0))
		alloc.care -= move
		alloc.farm += move
	for t in alloc:
		out.append({"type": "set_labor", "task": t, "value": maxi(alloc[t], 0)})
	return out


static func _days(r: Dictionary) -> float:
	var net: float = r.inflow - r.demand - r.lost
	return INF if net >= 0.0 else r.stock / -net
