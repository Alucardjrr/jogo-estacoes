class_name DataRegistry
extends RefCounted
## Carrega e valida os dados de balanceamento (`data/balance/*.json`, D-019).
## Validação estrita: chave faltando, tipo errado, valor fora da faixa ou chave
## desconhecida viram erro. Os erros são acumulados em `errors` (nada de
## push_error aqui); quem chama decide como mostrar. Se houver erro, nenhum dado
## fica disponível — a simulação não roda com dados parcialmente válidos.

const DEFAULT_DIR := "res://data/balance"
## Recursos do protótipo. Fixos no código porque cada um tem regra própria em
## SimResources; os números de cada um vêm de resources.json.
const RESOURCE_IDS: PackedStringArray = ["water", "food"]
## Grandezas que Season publica por estação (uma por recurso e tipo).
const SEASON_KEYS: PackedStringArray = [
	"water_inflow", "water_loss_rate", "food_inflow", "food_loss_rate", "health_drift"]

var errors: PackedStringArray = []

var _data: Dictionary = {}
var _id_regex := RegEx.create_from_string("^[a-z][a-z0-9_]*$")


func load_all(dir: String = DEFAULT_DIR) -> bool:
	errors.clear()
	_data.clear()
	var loaded := {
		"sim": _load_json(dir.path_join("sim.json")),
		"calendar": _load_json(dir.path_join("calendar.json")),
		"season": _load_json(dir.path_join("season.json")),
		"resources": _load_json(dir.path_join("resources.json")),
		"population": _load_json(dir.path_join("population.json")),
	}
	var parsed := {}
	if loaded.sim is Dictionary:
		parsed.sim = _parse_sim(loaded.sim, "sim.json")
	var calendar_ok := false
	if loaded.calendar is Dictionary:
		var before := errors.size()
		parsed.calendar = _parse_calendar(loaded.calendar, "calendar.json")
		calendar_ok = errors.size() == before
	if loaded.season is Dictionary:
		# Checagem cruzada só com calendário válido, para não somar ruído ao erro real.
		parsed.season = _parse_season(loaded.season, "season.json",
			parsed.calendar if calendar_ok else {})
	if loaded.resources is Dictionary:
		parsed.resources = _parse_resources(loaded.resources, "resources.json")
	if loaded.population is Dictionary:
		parsed.population = _parse_population(loaded.population, "population.json")
	if not errors.is_empty():
		return false
	_data = parsed
	return true


func is_loaded() -> bool:
	return not _data.is_empty()


## Dados já normalizados (ints como int) de um sistema: "sim", "calendar",
## "season", "resources" ou "population".
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


## Referência cruzada: as estações de season.json precisam ser exatamente as de
## calendar.json (nem faltando, nem sobrando).
func _parse_season(d: Dictionary, src: String, calendar: Dictionary) -> Dictionary:
	_check_keys(d, ["intensity_per_year", "intensity_max", "transition_days", "seasons"], src)
	var out := {
		"intensity_per_year": _float(d, "intensity_per_year", src, 0.0, 1.0),
		"intensity_max": _float(d, "intensity_max", src, 1.0, 5.0),
		"transition_days": _int(d, "transition_days", src, 0, 365),
		"seasons": {},
	}
	# Par: metade exata de cada lado da virada (ímpar perderia 1 dia de mistura).
	if d.has("transition_days") and out.transition_days % 2 != 0:
		errors.append("%s: transition_days (%d) precisa ser par" % [src, out.transition_days])
	# Transição não pode passar da estação mais curta (metade de cada lado).
	if d.has("transition_days") and not calendar.is_empty():
		var shortest := 1 << 30
		for cs in calendar.seasons:
			shortest = mini(shortest, int(cs.months) * int(calendar.days_per_month))
		if out.transition_days > shortest:
			errors.append("%s: transition_days (%d) maior que a estação mais curta (%d dias)" % [
				src, out.transition_days, shortest])
	if not d.has("seasons"):
		return out
	if not d.seasons is Dictionary:
		errors.append("%s: seasons precisa ser um objeto {}" % src)
		return out
	var seasons: Dictionary = d.seasons
	var allowed: Array = SEASON_KEYS.duplicate()
	allowed.append("escalation")
	for id in seasons.keys():
		var where := "%s: seasons.%s" % [src, id]
		if not id is String or _id_regex.search(id) == null:
			errors.append("%s: id inválido (use minúsculas, dígitos e _)" % where)
			continue
		if not seasons[id] is Dictionary:
			errors.append("%s: precisa ser um objeto {}" % where)
			continue
		var s: Dictionary = seasons[id]
		_check_keys(s, allowed, where)
		var entry := {
			"water_inflow": _float(s, "water_inflow", where, 0.0, 100000.0),
			"water_loss_rate": _float(s, "water_loss_rate", where, 0.0, 1.0),
			"food_inflow": _float(s, "food_inflow", where, 0.0, 100000.0),
			"food_loss_rate": _float(s, "food_loss_rate", where, 0.0, 1.0),
			"health_drift": _float(s, "health_drift", where, -10.0, 10.0),
			"escalation": {},
		}
		if s.has("escalation"):
			if not s.escalation is Dictionary:
				errors.append("%s: escalation precisa ser um objeto {}" % where)
			else:
				var esc: Dictionary = s.escalation
				for k in esc.keys():
					if not SEASON_KEYS.has(k):
						errors.append("%s.escalation: chave desconhecida '%s'" % [where, k])
						continue
					entry.escalation[k] = _float(esc, k, where + ".escalation", -3.0, 3.0)
		out.seasons[id] = entry
	var cal_ids := []
	for cs in calendar.get("seasons", []):
		cal_ids.append(cs.id)
	for cid in cal_ids:
		if not seasons.has(cid):
			errors.append("%s: falta a estação '%s' (definida em calendar.json)" % [src, cid])
	if not cal_ids.is_empty():
		for id in seasons.keys():
			if not cal_ids.has(id):
				errors.append("%s: estação '%s' não existe em calendar.json" % [src, str(id)])
	return out


func _parse_resources(d: Dictionary, src: String) -> Dictionary:
	_check_keys(d, ["resources"], src)
	var out := {"resources": {}}
	if not d.has("resources"):
		return out
	if not d.resources is Dictionary:
		errors.append("%s: resources precisa ser um objeto {}" % src)
		return out
	var res: Dictionary = d.resources
	_check_keys(res, Array(RESOURCE_IDS), src + ": resources")
	for id in RESOURCE_IDS:
		if not res.has(id):
			continue
		var where := "%s: resources.%s" % [src, id]
		if not res[id] is Dictionary:
			errors.append("%s: precisa ser um objeto {}" % where)
			continue
		var r: Dictionary = res[id]
		_check_keys(r, ["initial", "capacity", "per_capita_daily"], where)
		var entry := {
			"initial": _float(r, "initial", where, 0.0, 1000000.0),
			"capacity": _float(r, "capacity", where, 1.0, 1000000.0),
			"per_capita_daily": _float(r, "per_capita_daily", where, 0.0, 100.0),
		}
		if r.has("initial") and r.has("capacity") and entry.initial > entry.capacity:
			errors.append("%s: initial (%s) maior que capacity (%s)" % [
				where, entry.initial, entry.capacity])
		out.resources[id] = entry
	return out


func _parse_population(d: Dictionary, src: String) -> Dictionary:
	_check_keys(d, ["families", "health_initial", "health_max", "health_recovery_per_day",
		"water_shortage_health", "food_shortage_health", "death_health_threshold",
		"death_rate_max", "departure_shortage_days"], src)
	var out := {
		"families": [],
		"health_initial": _float(d, "health_initial", src, 0.0, 1000.0),
		"health_max": _float(d, "health_max", src, 1.0, 1000.0),
		"health_recovery_per_day": _float(d, "health_recovery_per_day", src, 0.0, 100.0),
		"water_shortage_health": _float(d, "water_shortage_health", src, 0.0, 100.0),
		"food_shortage_health": _float(d, "food_shortage_health", src, 0.0, 100.0),
		"death_health_threshold": _float(d, "death_health_threshold", src, 0.0, 1000.0),
		"death_rate_max": _float(d, "death_rate_max", src, 0.0, 1.0),
		"departure_shortage_days": _int(d, "departure_shortage_days", src, 1, 1000),
	}
	if d.has("health_initial") and d.has("health_max") and out.health_initial > out.health_max:
		errors.append("%s: health_initial (%s) maior que health_max (%s)" % [
			src, out.health_initial, out.health_max])
	if d.has("death_health_threshold") and d.has("health_max") \
			and out.death_health_threshold > out.health_max:
		errors.append("%s: death_health_threshold maior que health_max" % src)
	var families := _array(d, "families", src)
	if families.is_empty() and d.has("families"):
		errors.append("%s: families não pode ser vazio" % src)
	var ids := {}
	for i in families.size():
		var where := "%s: families[%d]" % [src, i]
		if not families[i] is Dictionary:
			errors.append("%s: precisa ser um objeto {}" % where)
			continue
		var f: Dictionary = families[i]
		_check_keys(f, ["id", "size"], where)
		var id := _id(f, "id", where)
		if ids.has(id):
			errors.append("%s: id repetido '%s'" % [where, id])
		ids[id] = true
		out.families.append({"id": id, "size": _int(f, "size", where, 1, 50)})
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
