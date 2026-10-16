class_name DataRegistry
extends RefCounted
## Carrega e valida os dados de balanceamento (`data/balance/*.json`, D-019).
## Validação estrita: chave faltando, tipo errado, valor fora da faixa ou chave
## desconhecida viram erro. Os erros são acumulados em `errors` (nada de
## push_error aqui); quem chama decide como mostrar. Se houver erro, nenhum dado
## fica disponível — a simulação não roda com dados parcialmente válidos.

const DEFAULT_DIR := "res://data/balance"

var errors: PackedStringArray = []

var _data: Dictionary = {}
var _id_regex := RegEx.create_from_string("^[a-z][a-z0-9_]*$")


func load_all(dir: String = DEFAULT_DIR) -> bool:
	errors.clear()
	_data.clear()
	var loaded := {
		"sim": _load_json(dir.path_join("sim.json")),
		"calendar": _load_json(dir.path_join("calendar.json")),
	}
	var parsed := {}
	if loaded.sim is Dictionary:
		parsed.sim = _parse_sim(loaded.sim, "sim.json")
	if loaded.calendar is Dictionary:
		parsed.calendar = _parse_calendar(loaded.calendar, "calendar.json")
	if not errors.is_empty():
		return false
	_data = parsed
	return true


func is_loaded() -> bool:
	return not _data.is_empty()


## Dados já normalizados (ints como int) de um sistema: "sim" ou "calendar".
func section(name: String) -> Dictionary:
	return _data.get(name, {})


# --- Leitura -----------------------------------------------------------------

func _load_json(path: String) -> Variant:
	var file_name := path.get_file()
	if not FileAccess.file_exists(path):
		errors.append("%s: arquivo não encontrado (%s)" % [file_name, path])
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s: JSON inválido na linha %d (%s)" % [
			file_name, json.get_error_line(), json.get_error_message()])
		return null
	if not json.data is Dictionary:
		errors.append("%s: a raiz precisa ser um objeto {}" % file_name)
		return null
	return json.data


# --- Esquemas ----------------------------------------------------------------

func _parse_sim(d: Dictionary, src: String) -> Dictionary:
	_check_keys(d, ["seconds_per_day", "speeds", "max_days_per_frame", "default_seed"], src)
	var out := {
		"seconds_per_day": _float(d, "seconds_per_day", src, 0.05, 60.0),
		"max_days_per_frame": _int(d, "max_days_per_frame", src, 1, 100),
		"default_seed": _int(d, "default_seed", src, 0, 2147483647),
		"speeds": [],
	}
	var speeds := _array(d, "speeds", src)
	var last := 0
	for i in speeds.size():
		var v: int = _int_value(speeds[i], "%s: speeds[%d]" % [src, i], 1, 10)
		if v <= last:
			errors.append("%s: speeds precisa ser crescente e sem repetição" % src)
		last = v
		out.speeds.append(v)
	if speeds.is_empty() and d.has("speeds"):
		errors.append("%s: speeds não pode ser vazio" % src)
	return out


func _parse_calendar(d: Dictionary, src: String) -> Dictionary:
	_check_keys(d, ["days_per_month", "months_per_year", "seasons"], src)
	var out := {
		"days_per_month": _int(d, "days_per_month", src, 1, 365),
		"months_per_year": _int(d, "months_per_year", src, 1, 24),
		"seasons": [],
	}
	var seasons := _array(d, "seasons", src)
	if seasons.is_empty() and d.has("seasons"):
		errors.append("%s: seasons não pode ser vazio" % src)
	var ids := {}
	var total_months := 0
	for i in seasons.size():
		var where := "%s: seasons[%d]" % [src, i]
		if not seasons[i] is Dictionary:
			errors.append("%s: precisa ser um objeto {}" % where)
			continue
		var s: Dictionary = seasons[i]
		_check_keys(s, ["id", "months", "severe"], where)
		var id := _id(s, "id", where)
		if ids.has(id):
			errors.append("%s: id repetido '%s'" % [where, id])
		ids[id] = true
		var months := _int(s, "months", where, 1, 24)
		total_months += months
		out.seasons.append({"id": id, "months": months, "severe": _bool(s, "severe", where)})
	if not seasons.is_empty() and d.has("months_per_year") and total_months != out.months_per_year:
		errors.append("%s: soma dos meses das estações (%d) difere de months_per_year (%d)" % [
			src, total_months, out.months_per_year])
	return out


# --- Validadores -------------------------------------------------------------

func _check_keys(d: Dictionary, allowed: Array, where: String) -> void:
	for k in allowed:
		if not d.has(k):
			errors.append("%s: falta a chave '%s'" % [where, k])
	for k in d.keys():
		if not allowed.has(k):
			errors.append("%s: chave desconhecida '%s'" % [where, k])


func _int(d: Dictionary, key: String, where: String, lo: int, hi: int) -> int:
	if not d.has(key):
		return lo
	return _int_value(d[key], "%s: %s" % [where, key], lo, hi)


func _int_value(v: Variant, where: String, lo: int, hi: int) -> int:
	# JSON entrega números como float; aceita só valores inteiros.
	if not (v is float or v is int) or float(v) != floorf(float(v)):
		errors.append("%s: precisa ser inteiro (veio %s)" % [where, str(v)])
		return lo
	var n := int(v)
	if n < lo or n > hi:
		errors.append("%s: %d fora da faixa [%d, %d]" % [where, n, lo, hi])
		return lo
	return n


func _float(d: Dictionary, key: String, where: String, lo: float, hi: float) -> float:
	if not d.has(key):
		return lo
	var v: Variant = d[key]
	if not (v is float or v is int):
		errors.append("%s: %s precisa ser número (veio %s)" % [where, key, str(v)])
		return lo
	var n := float(v)
	if n < lo or n > hi:
		errors.append("%s: %s = %s fora da faixa [%s, %s]" % [where, key, n, lo, hi])
		return lo
	return n


func _bool(d: Dictionary, key: String, where: String) -> bool:
	if not d.has(key):
		return false
	if not d[key] is bool:
		errors.append("%s: %s precisa ser true/false (veio %s)" % [where, key, str(d[key])])
		return false
	return d[key]


func _array(d: Dictionary, key: String, where: String) -> Array:
	if not d.has(key):
		return []
	if not d[key] is Array:
		errors.append("%s: %s precisa ser uma lista []" % [where, key])
		return []
	return d[key]


func _id(d: Dictionary, key: String, where: String) -> String:
	if not d.has(key):
		return ""
	var v: Variant = d[key]
	if not v is String or _id_regex.search(v) == null:
		errors.append("%s: %s inválido '%s' (use minúsculas, dígitos e _)" % [where, key, str(v)])
		return ""
	return v
