class_name SimLabor
extends RefCounted
## Mão de obra (GDD 10, sistema 8; D-031). Passo 5 do tick: lê pessoas e saúde do
## fim do dia anterior e os multiplicadores da estação (gather_mult, farm_mult,
## publicados por Season) e publica a produção como modificadores "add" da fonte
## "labor" — Resources e Population não sabem que Labor existe.
##
## - Trabalhadores = floor(pessoas × worker_share).
## - `desired` é o que o jogador pediu. Se passar dos trabalhadores (mortes,
##   partidas), todas as tarefas encolhem na mesma proporção → `effective`.
## - Produtividade: 1 com saúde ≥ full_productivity_health; abaixo, linear até
##   min_productivity com saúde 0.
## - Água/comida = efetivos × produção por trabalhador × produtividade × mult. da estação.
## - Cuidado: saúde + min(care_health_max, care_health_per_share × cuidadores/pessoas),
##   cuidadores já com produtividade.
## - Fadiga: fração da força buscando água acima de fatigue_threshold tira saúde
##   (fatigue_health × excesso/(1 − limiar)) — custo que atravessa a estação.

const SOURCE := "labor"

var desired: Dictionary = {}    # tarefa -> int (pedido do jogador)
var assigned: Dictionary = {}   # tarefa -> float (após o corte proporcional)
var effective: Dictionary = {}  # tarefa -> float (assigned × produtividade)
var workers := 0
var productivity := 1.0
## true depois que o jogador mexeu na distribuição (a tela mostra "inicial" até lá).
var changed := false

var _cfg: Dictionary


func _init(cfg: Dictionary) -> void:
	_cfg = cfg
	for id in DataRegistry.TASK_IDS:
		desired[id] = int(cfg.initial_allocation[id])
		assigned[id] = 0.0
		effective[id] = 0.0


func idle() -> float:
	var used := 0.0
	for id in DataRegistry.TASK_IDS:
		used += assigned[id]
	return maxf(workers - used, 0.0)


func total_desired() -> int:
	var n := 0
	for id in DataRegistry.TASK_IDS:
		n += desired[id]
	return n


## Comando set_labor/adjust_labor já validado: aplica e marca como alterado.
func set_desired(id: String, value: int) -> void:
	desired[id] = maxi(value, 0)
	changed = true


func step(people: int, health: float, modifiers: ModifierStack) -> void:
	modifiers.clear_source(SOURCE)
	workers = int(floor(people * float(_cfg.worker_share)))
	var full: float = _cfg.full_productivity_health
	var lo: float = _cfg.min_productivity
	productivity = 1.0 if health >= full else lo + (1.0 - lo) * maxf(health, 0.0) / full
	var total := total_desired()
	var scale := minf(1.0, float(workers) / total) if total > 0 else 0.0
	for id in DataRegistry.TASK_IDS:
		assigned[id] = desired[id] * scale
		effective[id] = assigned[id] * productivity

	modifiers.add("water_inflow", SOURCE,
		effective.water * _cfg.water_per_worker * modifiers.value("gather_mult"))
	modifiers.add("food_inflow", SOURCE,
		effective.farm * _cfg.food_per_worker * modifiers.value("farm_mult"))

	var dh := 0.0
	if people > 0:
		dh += minf(_cfg.care_health_max, _cfg.care_health_per_share * effective.care / people)
	if workers > 0:
		var share: float = assigned.water / workers  # sem produtividade: é carga, não rendimento
		var th: float = _cfg.fatigue_threshold
		dh -= _cfg.fatigue_health * maxf(0.0, share - th) / (1.0 - th)
	modifiers.add("health_drift", SOURCE, dh)


func snapshot() -> Dictionary:
	return {"workers": workers, "idle": idle(), "productivity": productivity,
		"desired": desired.duplicate(), "assigned": assigned.duplicate(),
		"effective": effective.duplicate(), "changed": changed}
