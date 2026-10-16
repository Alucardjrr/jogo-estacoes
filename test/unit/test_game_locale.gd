extends GutTest
## Integração do idioma no `Game` (D-024): troca, persistência e recusa.
## Usa uma instância própria do script (não o autoload) e um arquivo temporário,
## para não mexer nas preferências reais de quem roda os testes.

const TMP := "user://test_game_locale.json"
const GameScript := preload("res://scripts/game.gd")

var game: Node
var _old_locale: String


func before_each() -> void:
	_old_locale = TranslationServer.get_locale()
	DirAccess.remove_absolute(TMP)
	game = GameScript.new()
	game.settings_path = TMP


func after_each() -> void:
	game.free()
	TranslationServer.set_locale(_old_locale)
	DirAccess.remove_absolute(TMP)


func _saved_locale() -> Variant:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(TMP))
	return data.get("locale") if data is Dictionary else null


func test_trocar_idioma_alterna_e_salva() -> void:
	TranslationServer.set_locale("pt_BR")
	game.cycle_locale()
	assert_eq(TranslationServer.get_locale(), "en")
	assert_eq(_saved_locale(), "en")
	game.cycle_locale()
	assert_eq(TranslationServer.get_locale(), "pt_BR")
	assert_eq(_saved_locale(), "pt_BR")


func test_escolha_salva_vale_na_proxima_abertura() -> void:
	TranslationServer.set_locale("pt_BR")
	game.cycle_locale()  # salva "en"
	var next: Node = GameScript.new()
	next.settings_path = TMP
	TranslationServer.set_locale("pt_BR")
	next._apply_settings()
	assert_eq(TranslationServer.get_locale(), "en")
	next.free()


func test_idioma_nao_suportado_e_recusado() -> void:
	TranslationServer.set_locale("pt_BR")
	assert_false(game._set_locale("klingon", true))
	assert_eq(TranslationServer.get_locale(), "pt_BR")
	assert_false(FileAccess.file_exists(TMP), "recusa não grava nada")


func test_idioma_temporario_nao_salva() -> void:
	# Mesmo caminho do argumento --locale= da linha de comando.
	assert_true(game._set_locale("en", false))
	assert_eq(TranslationServer.get_locale(), "en")
	assert_false(FileAccess.file_exists(TMP))


func test_save_em_caminho_invalido_retorna_false() -> void:
	var s := GameSettings.new()
	assert_false(s.save_to("user://pasta_que_nao_existe/settings.json"))
