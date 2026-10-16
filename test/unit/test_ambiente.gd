extends GutTest
## Ambiente dev/prod (D-029): ferramentas de debug só em dev.

const GameScript := preload("res://scripts/game.gd")


func test_build_de_debug_e_dev() -> void:
	assert_true(GameScript.is_dev_environment(true, false, false))


func test_build_de_release_e_prod() -> void:
	assert_false(GameScript.is_dev_environment(false, false, false))


func test_tag_dev_liga_em_release() -> void:
	assert_true(GameScript.is_dev_environment(false, true, false))


func test_tag_prod_vence_tudo() -> void:
	assert_false(GameScript.is_dev_environment(true, true, true))


func test_testes_rodam_em_dev() -> void:
	assert_true(Game.dev_mode, "editor/headless de teste é build de debug")
