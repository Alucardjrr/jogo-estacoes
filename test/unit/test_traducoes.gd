extends GutTest
## Traduções completas (D-024): todo texto existe em todos os idiomas suportados,
## com os mesmos marcadores {x}, e toda chave usada no código existe no CSV.

const CSV_PATH := "res://data/text/ui.csv"
const CODE_DIRS: PackedStringArray = ["res://scripts"]

var _rows: Dictionary = {}  # chave -> PackedStringArray de textos (ordem do cabeçalho)
var _header: PackedStringArray = []
var _placeholder := RegEx.create_from_string("\\{[a-z_]+\\}")


func before_all() -> void:
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	_header = f.get_csv_line()
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() == 1 and line[0] == "":
			continue
		_rows[line[0]] = line.slice(1)
	f.close()


func _placeholders(text: String) -> Array:
	var found := _placeholder.search_all(text).map(func(m: RegExMatch) -> String: return m.get_string())
	found.sort()
	return found


func test_cabecalho_tem_os_idiomas_suportados() -> void:
	assert_eq(_header.slice(1), GameSettings.SUPPORTED_LOCALES)


func test_toda_linha_tem_todos_os_idiomas() -> void:
	for key in _rows:
		var texts: PackedStringArray = _rows[key]
		assert_eq(texts.size(), _header.size() - 1, "colunas em %s" % key)
		for i in texts.size():
			assert_ne(texts[i].strip_edges(), "", "%s sem texto em %s" % [key, _header[i + 1]])


func test_marcadores_iguais_em_todos_os_idiomas() -> void:
	for key in _rows:
		var texts: PackedStringArray = _rows[key]
		var expected := _placeholders(texts[0])
		for i in range(1, texts.size()):
			assert_eq(_placeholders(texts[i]), expected, "marcadores de %s em %s" % [key, _header[i + 1]])


func test_chaves_literais_do_codigo_existem() -> void:
	var tr_call := RegEx.create_from_string("tr\\(\"([A-Z0-9_]+)\"\\)")
	var used := 0
	for path in _gd_files():
		for m in tr_call.search_all(FileAccess.get_file_as_string(path)):
			used += 1
			assert_true(_rows.has(m.get_string(1)), "%s usa chave ausente %s" % [path, m.get_string(1)])
	assert_gt(used, 0, "a busca precisa achar chaves no código")


func test_chaves_dinamicas_dos_dados_existem() -> void:
	var reg := DataRegistry.new()
	assert_true(reg.load_all())
	var cal := reg.section("calendar")
	for m in range(1, cal.months_per_year + 1):
		assert_true(_rows.has("MONTH_%d" % m), "falta MONTH_%d" % m)
	for season in cal.seasons:
		assert_true(_rows.has("SEASON_" + season.id.to_upper()), "falta SEASON_%s" % season.id.to_upper())
	for id in DataRegistry.RESOURCE_IDS:
		assert_true(_rows.has("RESOURCE_" + id.to_upper()), "falta RESOURCE_%s" % id.to_upper())
	var nar: Dictionary = reg.section("narrative")
	for i in nar.residents:
		assert_true(_rows.has("RESIDENT_%02d" % (i + 1)), "falta RESIDENT_%02d" % (i + 1))
	for grp in nar.season_group.values():
		for mood in SimNarrative.MOODS:
			for i in nar.diary_lines:
				var k := "DIARY_%s_%s_%d" % [grp, mood, i + 1]
				assert_true(_rows.has(k), "falta " + k)
				if not _rows.has(k):
					continue
				# QA PR #11: só os contadores que a causa garante (nada de "perdemos 0")
				for ph in _placeholders(_rows[k][0]):
					assert_true(SimNarrative.MOOD_PARAMS[mood].has(ph.trim_prefix("{").trim_suffix("}")),
						"%s usa %s, que não cabe na causa %s" % [k, ph, mood])
	for line in nar.reaction_lines:
		for i in nar.reaction_lines[line]:
			var k := "REACT_%s_%d" % [line, i + 1]
			assert_true(_rows.has(k), "falta " + k)
	assert_true(_rows.has("SETTLEMENT_NAME"))
	for mid in reg.section("social").measures:
		for suffix in ["", "_DESC"]:
			var k: String = "MEASURE_" + String(mid).to_upper() + suffix
			assert_true(_rows.has(k), "falta " + k)
	for meter in ["TRUST", "COHESION"]:
		assert_true(_rows.has("METER_" + meter), "falta METER_" + meter)
	for r in Simulation.REJECT_REASONS:
		assert_true(_rows.has("REJECT_" + r.to_upper()), "falta REJECT_" + r.to_upper())
	# Todo motivo emitido pela simulação está em REJECT_REASONS.
	var sim_code := FileAccess.get_file_as_string("res://scripts/sim/simulation.gd")
	var found := RegEx.create_from_string("_reject\\(command, \"([a-z_]+)\"\\)").search_all(sim_code)
	assert_gt(found.size(), 0, "a busca precisa achar os _reject")
	for m in found:
		assert_true(Simulation.REJECT_REASONS.has(m.get_string(1)), "motivo fora da lista: " + m.get_string(1))
	for id in reg.section("buildings").types:
		assert_true(_rows.has("BUILDING_" + id.to_upper()), "falta BUILDING_%s" % id.to_upper())


func test_traducao_carregada_no_jogo() -> void:
	var old := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	assert_eq(tr("SEASON_SECA"), "Drought")
	TranslationServer.set_locale("pt_BR")
	assert_eq(tr("SEASON_SECA"), "Seca")
	TranslationServer.set_locale(old)


func _gd_files() -> PackedStringArray:
	var out: PackedStringArray = []
	var stack: Array[String] = []
	stack.append_array(CODE_DIRS)
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				out.append(dir.path_join(f))
		for d in DirAccess.get_directories_at(dir):
			stack.append(dir.path_join(d))
	return out
