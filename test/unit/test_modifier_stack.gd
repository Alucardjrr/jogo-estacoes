extends GutTest
## ModifierStack: soma dos add, produto dos mul, limpeza por fonte.


func test_sem_modificador_retorna_base() -> void:
	var m := ModifierStack.new()
	assert_eq(m.value("x"), 0.0)
	assert_eq(m.value("x", 5.0), 5.0)


func test_add_soma_e_mul_multiplica() -> void:
	var m := ModifierStack.new()
	m.add("x", "a", 10.0)
	m.add("x", "b", 5.0)
	m.mul("x", "c", 0.5)
	m.mul("x", "d", 0.5)
	m.add("y", "a", 99.0)
	assert_almost_eq(m.value("x", 1.0), 4.0, 1e-9)  # (1 + 15) × 0.25


func test_ordem_de_publicacao_nao_importa() -> void:
	var a := ModifierStack.new()
	a.mul("x", "s", 0.6)
	a.add("x", "t", 50.0)
	var b := ModifierStack.new()
	b.add("x", "t", 50.0)
	b.mul("x", "s", 0.6)
	assert_eq(a.value("x"), b.value("x"))


func test_clear_source_remove_so_a_fonte() -> void:
	var m := ModifierStack.new()
	m.add("x", "season", 10.0)
	m.add("x", "social", 1.0)
	m.clear_source("season")
	assert_eq(m.value("x"), 1.0)
	assert_eq(m.entries().size(), 1)


func test_entries_e_copia() -> void:
	var m := ModifierStack.new()
	m.add("x", "a", 1.0)
	m.entries()[0].add = 999.0
	assert_eq(m.value("x"), 1.0)
