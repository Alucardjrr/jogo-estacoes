extends GutTest
## Sanidade do setup: garante que decisões de configuração do projeto não regridam.


func test_renderizador_e_compatibility() -> void:
	# D-017: renderizador Compatibility (2D isométrico, hardware amplo).
	var metodo: String = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	assert_eq(metodo, "gl_compatibility")


func test_engine_fixada_em_4_7() -> void:
	# D-014: Godot 4.7.x; atualizar só em fronteira de fase.
	var versao: Dictionary = Engine.get_version_info()
	assert_eq(versao.major, 4)
	assert_eq(versao.minor, 7)
