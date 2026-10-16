extends GutTest
## SimResources: entrada → consumo → teto → perda; falta vira evento.

const CFG := {"resources": {
	"water": {"initial": 100.0, "capacity": 200.0, "per_capita_daily": 1.0},
	"food": {"initial": 50.0, "capacity": 100.0, "per_capita_daily": 2.0}}}


func _mods(water_in: float, water_loss: float, food_in: float, food_loss: float) -> ModifierStack:
	var m := ModifierStack.new()
	m.add("water_inflow", "t", water_in)
	m.add("water_loss_rate", "t", water_loss)
	m.add("food_inflow", "t", food_in)
	m.add("food_loss_rate", "t", food_loss)
	return m


func test_estoque_inicial_vem_dos_dados() -> void:
	var r := SimResources.new(CFG)
	assert_eq(r.stock.water, 100.0)
	assert_eq(r.stock.food, 50.0)


func test_ordem_entrada_consumo_perda() -> void:
	var r := SimResources.new(CFG)
	var events := r.step(10, _mods(20.0, 0.1, 0.0, 0.0))
	# água: 100 + 20 − 10 = 110; perda 10% = 11 → 99
	assert_almost_eq(r.stock.water, 99.0, 1e-9)
	assert_almost_eq(r.last_flow.water.lost, 11.0, 1e-9)
	assert_eq(r.last_flow.water.consumed, 10.0)
	# comida: 50 − 20 = 30
	assert_eq(r.stock.food, 30.0)
	assert_eq(events, [])


func test_teto_descarta_o_excesso() -> void:
	var r := SimResources.new(CFG)
	r.step(10, _mods(500.0, 0.0, 0.0, 0.0))
	assert_eq(r.stock.water, 200.0)
	assert_eq(r.last_flow.water.overflow, 390.0)  # 100 + 500 − 10 − 200


func test_teto_antes_da_perda() -> void:
	var r := SimResources.new(CFG)
	r.step(10, _mods(500.0, 0.1, 0.0, 0.0))
	# 100 + 500 − 10 = 590 → teto 200 (overflow 390) → perda 10% = 20
	assert_almost_eq(r.stock.water, 180.0, 1e-9)
	assert_almost_eq(r.last_flow.water.overflow, 390.0, 1e-9)
	assert_almost_eq(r.last_flow.water.lost, 20.0, 1e-9)


func test_entrada_antes_do_consumo() -> void:
	var cfg := CFG.duplicate(true)
	cfg.resources.water.initial = 0.0
	var r := SimResources.new(cfg)
	var events := r.step(10, _mods(20.0, 0.0, 30.0, 0.0))
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.resource == "water"), [],
		"entrada do dia cobre o consumo do dia")
	assert_eq(r.last_flow.water.consumed, 10.0)
	assert_eq(r.stock.water, 10.0)


func test_falta_gera_evento_e_estoque_nao_fica_negativo() -> void:
	var r := SimResources.new(CFG)
	var events := r.step(40, _mods(0.0, 0.0, 0.0, 0.0))  # comida: 50 − 80
	assert_eq(r.stock.food, 0.0)
	assert_eq(r.last_flow.food.deficit, 30.0)
	assert_eq(events.size(), 1)
	assert_eq(events[0], {"type": "shortage", "resource": "food", "deficit": 30.0})
	events = r.step(40, _mods(0.0, 0.0, 0.0, 0.0))
	assert_eq(events.size(), 1, "água 60 − 40 = 20 não falta; só a comida")
	assert_eq(events[0].deficit, 80.0)
	assert_eq(r.stock.water, 20.0)


func test_perda_total_e_taxa_acima_de_1_limitada() -> void:
	var r := SimResources.new(CFG)
	r.step(0, _mods(0.0, 5.0, 0.0, 1.0))
	assert_eq(r.stock.water, 0.0)
	assert_eq(r.stock.food, 0.0)


func test_entrada_negativa_vira_zero() -> void:
	var r := SimResources.new(CFG)
	r.step(0, _mods(-50.0, 0.0, 0.0, 0.0))
	assert_eq(r.stock.water, 100.0)


func test_multiplicador_de_consumo() -> void:
	var r := SimResources.new(CFG)
	var m := _mods(0.0, 0.0, 0.0, 0.0)
	m.mul("water_consumption", "racionamento", 0.6)
	r.step(10, m)
	assert_almost_eq(r.stock.water, 94.0, 1e-9)
	assert_eq(r.stock.food, 30.0, "multiplicador só da água")


func test_populacao_zero_nao_consome() -> void:
	var r := SimResources.new(CFG)
	assert_eq(r.step(0, _mods(0.0, 0.0, 0.0, 0.0)), [])
	assert_eq(r.stock.water, 100.0)
