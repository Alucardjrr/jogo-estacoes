class_name GameSettings
extends RefCounted
## Preferências do jogador em `user://settings.json` (fora da simulação e do save).
## Protocolo 6: arquivo corrompido ou editado nunca trava o jogo — valores
## inválidos são ignorados e o padrão é usado.

const PATH := "user://settings.json"
const LOCALE_AUTO := "auto"
const SUPPORTED_LOCALES: PackedStringArray = ["pt_BR", "en"]
const FALLBACK_LOCALE := "en"

## "auto" segue o idioma do sistema; ou um de SUPPORTED_LOCALES.
var locale: String = LOCALE_AUTO
## Avisos do último load (arquivo inválido etc.), para log.
var warnings: PackedStringArray = []


func load_from(path: String = PATH) -> void:
	warnings.clear()
	locale = LOCALE_AUTO
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		warnings.append("%s inválido; usando padrões" % path)
		return
	var v: Variant = json.data.get("locale", LOCALE_AUTO)
	if v is String and (v == LOCALE_AUTO or SUPPORTED_LOCALES.has(v)):
		locale = v
	else:
		warnings.append("%s: locale '%s' não suportado; usando auto" % [path, str(v)])


func save_to(path: String = PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"locale": locale}, "  "))
	f.close()
	return true


## Idioma efetivo. `system_locale` vem de OS.get_locale() (ex.: "pt_BR", "en_US").
func resolve_locale(system_locale: String) -> String:
	if locale != LOCALE_AUTO:
		return locale
	return "pt_BR" if system_locale.begins_with("pt") else FALLBACK_LOCALE


## Próximo idioma da lista, a partir do efetivo (para o botão de troca).
func next_locale(current: String) -> String:
	var i := SUPPORTED_LOCALES.find(current)
	return SUPPORTED_LOCALES[(i + 1) % SUPPORTED_LOCALES.size()]
