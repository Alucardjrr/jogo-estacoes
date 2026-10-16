extends GutTest
## GameSettings: idioma automático, escolha salva, arquivo ruim não trava.

const TMP := "user://test_settings.json"

var s: GameSettings


func before_each() -> void:
	s = GameSettings.new()
	DirAccess.remove_absolute(TMP)


func after_all() -> void:
	DirAccess.remove_absolute(TMP)


func _write(text: String) -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_auto_segue_o_sistema() -> void:
	assert_eq(s.resolve_locale("pt_BR"), "pt_BR")
	assert_eq(s.resolve_locale("pt_PT"), "pt_BR")
	assert_eq(s.resolve_locale("en_US"), "en")
	assert_eq(s.resolve_locale("es_AR"), "en", "idioma sem tradução cai no inglês")
	assert_eq(s.resolve_locale(""), "en")


func test_escolha_explicita_vence_o_sistema() -> void:
	s.locale = "en"
	assert_eq(s.resolve_locale("pt_BR"), "en")


func test_sem_arquivo_usa_auto() -> void:
	s.load_from(TMP)
	assert_eq(s.locale, GameSettings.LOCALE_AUTO)
	assert_eq(s.warnings.size(), 0)


func test_salva_e_carrega() -> void:
	s.locale = "pt_BR"
	assert_true(s.save_to(TMP))
	var other := GameSettings.new()
	other.load_from(TMP)
	assert_eq(other.locale, "pt_BR")


func test_arquivo_corrompido_nao_trava() -> void:
	_write("{ isso não é json")
	s.load_from(TMP)
	assert_eq(s.locale, GameSettings.LOCALE_AUTO)
	assert_eq(s.warnings.size(), 1)


func test_valores_editados_a_mao_sao_ignorados() -> void:
	for bad in ['{"locale": "klingon"}', '{"locale": 42}', '[1, 2]', '"pt_BR"']:
		_write(bad)
		s.load_from(TMP)
		assert_eq(s.locale, GameSettings.LOCALE_AUTO, bad)
		assert_eq(s.warnings.size(), 1, bad)


func test_proximo_idioma_alterna() -> void:
	assert_eq(s.next_locale("pt_BR"), "en")
	assert_eq(s.next_locale("en"), "pt_BR")
	assert_eq(s.next_locale("xx"), "pt_BR", "desconhecido volta ao primeiro")
