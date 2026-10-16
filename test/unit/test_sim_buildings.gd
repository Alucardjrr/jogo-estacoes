extends GutTest
## SimBuildings: saque, desgaste, reparo, fila de obras, efeitos; comando build.

const W := {"seca": 1.0, "chuvas": 4.0}
const CFG := {"work_points_per_worker": 1.0, "points_per_condition": 2.0,
	"low_condition_threshold": 60.0, "low_condition_wear_mult": 1.5,
	"repair_cost_mult": {"seca": 1.0, "chuvas": 0.5}, "salvage_per_worker": 2.0,
	"salvage_fatigue": 2.0, "max_queue": 2, "types": {
		"ruinas": {"ruins": true, "materials": 100.0},
		"cist": {"ruins": false, "cost_materials": 50.0, "cost_points": 10.0, "wear": W,
			"effects": [{"key": "water_capacity", "add": 1000.0, "seasons": [], "requires_water": false}]},
		"silo": {"ruins": false, "cost_materials": 10.0, "cost_points": 4.0, "wear": W,
			"effects": [{"key": "food_loss_rate", "mul": 0.5, "seasons": ["chuvas"], "requires_water": false}]},
		"cant": {"ruins": false, "cost_materials": 0.0, "cost_points": 1.0, "wear": W,
			"effects": [{"key": "farm_mult", "add": 1.0, "seasons": [], "requires_water": true}]}}}

const LAB_CFG := {"worker_share": 1.0, "full_productivity_health": 60.0, "min_productivity": 0.5,
	"water_per_worker": 1.0, "food_per_worker": 1.0, "care_health_per_share": 0.0,
	"care_health_max": 0.0, "fatigue_threshold": 0.5, "fatigue_health": 0.0,
	"initial_allocation": {"water": 0, "farm": 0, "care": 0, "build": 0, "salvage": 0}}


## Labor com `build` e `salvage` trabalhadores efetivos (10 pessoas, todos trabalham).
func _labor(build: int, salvage: int) -> SimLabor:
	var cfg := LAB_CFG.duplicate(true)
	cfg.initial_allocation.build = build
	cfg.initial_allocation.salvage = salvage
	var l := SimLabor.new(cfg)
	var m := ModifierStack.new()
	m.add("gather_mult", "t", 1.0)
	m.add("farm_mult", "t", 1.0)
	l.step(10, 100.0, m)
	return l


func _value(m: ModifierStack, key: String, base: float = 0.0) -> float:
	return m.value(key, base)


func test_saque_rende_e_esgota() -> void:
	var b := SimBuildings.new(CFG)
	var m := ModifierStack.new()
	b.step(_labor(0, 5), "seca", false, m)
	assert_almost_eq(b.materials, 10.0, 1e-9, "5 × 2 × 100% restante")
	b.step(_labor(0, 5), "seca", false, m)
	assert_almost_eq(b.materials, 19.0, 1e-9, "5 × 2 × 90% restante")
	assert_almost_eq(b.materials + b.ruins_remaining, 100.0, 1e-9)


func test_fadiga_do_saque_cresce_com_o_esgotamento() -> void:
	var b := SimBuildings.new(CFG)
	var m := ModifierStack.new()
	b.step(_labor(0, 5), "seca", false, m)
	var first := _value(m, "health_drift")
	for _i in 20:
		b.step(_labor(0, 5), "seca", false, m)
	assert_lt(_value(m, "health_drift"), first, "mais fundo nas ruínas, mais fadiga")
	assert_almost_eq(first, -2.0 * 0.5 * 0.1, 1e-9, "metade da força, 10% esgotado")


func test_fila_reserva_materiais_e_constroi() -> void:
	var b := SimBuildings.new(CFG)
	b.materials = 60.0
	b.enqueue("cist")
	var ev := b.step(_labor(5, 0), "seca", false, ModifierStack.new())
	assert_eq(b.materials, 10.0, "reservado ao começar")
	assert_eq(ev[0].type, "building_started")
	ev = b.step(_labor(5, 0), "seca", false, ModifierStack.new())
	assert_eq(b.count("cist"), 1)
	assert_eq(ev.back().type, "building_completed")
	assert_true(b.queue.is_empty())


func test_fila_espera_materiais_sem_pular() -> void:
	var b := SimBuildings.new(CFG)
	b.materials = 20.0
	b.enqueue("cist")  # 50: não dá
	b.enqueue("silo")  # 10: daria, mas não pula a ordem
	b.step(_labor(5, 0), "seca", false, ModifierStack.new())
	assert_eq(b.instances, [])
	assert_eq(b.materials, 20.0)
	assert_false(b.can_enqueue(), "max_queue = 2")


func test_desgaste_por_estacao_e_abaixo_do_limiar() -> void:
	var b := SimBuildings.new(CFG)
	b.instances.append({"type": "cist", "condition": 100.0})
	b.step(_labor(0, 0), "chuvas", false, ModifierStack.new())
	assert_eq(b.instances[0].condition, 96.0)
	b.instances[0].condition = 50.0
	b.step(_labor(0, 0), "chuvas", false, ModifierStack.new())
	assert_eq(b.instances[0].condition, 44.0, "abaixo de 60: × 1,5")
	assert_almost_eq(b.last_wear_points, 12.0, 1e-9)


func test_reparo_pior_primeiro_e_mais_barato_na_janela() -> void:
	var b := SimBuildings.new(CFG)
	b.instances.append({"type": "silo", "condition": 90.0})
	b.instances.append({"type": "silo", "condition": 70.0})
	b.step(_labor(2, 0), "seca", false, ModifierStack.new())  # 2 pontos, 2 por 1%
	assert_almost_eq(b.instances[1].condition, 70.0 - 1.0 + 1.0, 1e-9, "o pior recebe o reparo")
	assert_almost_eq(b.instances[0].condition, 89.0, 1e-9)
	b.instances[1].condition = 50.0
	b.step(_labor(2, 0), "chuvas", false, ModifierStack.new())  # custo × 0,5 → 2%
	assert_almost_eq(b.instances[1].condition, 50.0 - 6.0 + 2.0, 1e-9)
	assert_almost_eq(b.last_repair_points, 2.0, 1e-9)


func test_reparo_antes_da_construcao() -> void:
	var b := SimBuildings.new(CFG)
	b.instances.append({"type": "cist", "condition": 50.0})
	b.materials = 100.0
	b.enqueue("silo")
	b.step(_labor(3, 0), "seca", false, ModifierStack.new())
	assert_false(b.queue[0].started and b.queue[0].progress > 0.0, "pontos foram para o reparo")


func test_efeitos_escalam_com_a_condicao() -> void:
	var b := SimBuildings.new(CFG)
	b.instances.append({"type": "cist", "condition": 100.0})
	b.instances.append({"type": "cist", "condition": 50.0})
	var m := ModifierStack.new()
	b.step(_labor(0, 0), "seca", false, m)
	assert_almost_eq(_value(m, "water_capacity"), 1000.0 * 0.99 + 1000.0 * 0.485, 1e-6)


func test_efeito_mul_com_filtro_de_estacao() -> void:
	var b := SimBuildings.new(CFG)
	b.instances.append({"type": "silo", "condition": 100.0})
	b.instances.append({"type": "silo", "condition": 100.0})
	var m := ModifierStack.new()
	b.step(_labor(0, 0), "seca", false, m)
	assert_eq(_value(m, "food_loss_rate", 1.0), 1.0, "só nas chuvas")
	b.instances[0].condition = 100.0
	b.instances[1].condition = 100.0
	b.step(_labor(0, 0), "chuvas", false, m)
	var k := 0.96  # depois do desgaste do dia
	assert_almost_eq(_value(m, "food_loss_rate", 1.0), pow(1.0 - 0.5 * k, 2), 1e-9)


func test_efeito_que_exige_agua() -> void:
	var b := SimBuildings.new(CFG)
	b.instances.append({"type": "cant", "condition": 100.0})
	var m := ModifierStack.new()
	b.step(_labor(0, 0), "seca", true, m)
	assert_eq(_value(m, "farm_mult"), 0.0, "faltou água ontem: sem bônus")
	b.step(_labor(0, 0), "seca", false, m)
	assert_gt(_value(m, "farm_mult"), 0.0)


# --- Integração ---

func test_capacidade_dos_recursos_segue_os_predios() -> void:
	var sim := Simulation.new()
	assert_true(sim.setup(1))
	var base := sim.resources.capacity("water")
	sim.buildings.instances.append({"type": "cisterna", "condition": 100.0})
	sim.step_day()
	assert_gt(sim.resources.capacity("water"), base)
	assert_eq(sim.snapshot().resources.water.capacity, sim.resources.capacity("water"))


func test_comando_build() -> void:
	var sim := Simulation.new()
	assert_true(sim.setup(1))
	for cmd in [{"type": "build", "building": "ruinas"}, {"type": "build", "building": "castelo"},
			{"type": "build"}, {"type": "build", "building": "silo"}]:
		sim.enqueue(cmd)
	sim.step_day()
	var types := sim.drain_events().map(func(e: Dictionary) -> String: return e.type)
	assert_eq(types.count("command_rejected"), 3)
	assert_eq(types.count("build_queued"), 1)
	assert_eq(sim.buildings.queue.size(), 1)


func test_fila_cheia_recusa() -> void:
	var sim := Simulation.new()
	assert_true(sim.setup(1))
	var max_q: int = sim.data.section("buildings").max_queue
	for _i in max_q + 1:
		sim.enqueue({"type": "build", "building": "silo"})
	sim.step_day()
	var rejected := sim.drain_events().filter(func(e: Dictionary) -> bool:
		return e.type == "command_rejected")
	assert_eq(rejected.size(), 1)
	assert_eq(rejected[0].reason, "fila de obras cheia")


func test_simulacao_com_predios_deterministica() -> void:
	var run := func() -> Dictionary:
		var sim := Simulation.new()
		sim.setup(3)
		sim.enqueue({"type": "set_labor", "task": "salvage", "value": 6})
		sim.enqueue({"type": "set_labor", "task": "build", "value": 3})
		sim.enqueue({"type": "build", "building": "silo"})
		for _d in 400:
			sim.step_day()
		return sim.snapshot()
	assert_eq(run.call(), run.call())
