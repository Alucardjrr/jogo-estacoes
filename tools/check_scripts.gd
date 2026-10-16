extends Node
## Compila todos os .gd do projeto (fora de addons/) e sai com código 1 se algum falhar.
## O import do Godot só compila scripts usados por cenas; este passo pega o resto.
## Roda como cena (não com -s) para que o autoload `Game` exista na compilação.
## Uso: godot --headless --path . res://tools/check_scripts.tscn

const ROOTS: PackedStringArray = ["res://scripts", "res://test", "res://tools"]


func _ready() -> void:
	var failed: PackedStringArray = []
	var count := 0
	var own_path: String = get_script().resource_path
	for path in _gd_files():
		if path == own_path:
			continue  # recompilar o script em execução corrompe a VM
		count += 1
		var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
		if script == null or not script.can_instantiate():
			failed.append(path)
	for path in failed:
		printerr("SCRIPT_CHECK_FAIL ", path)
	print("check_scripts: %d scripts, %d com erro" % [count, failed.size()])
	get_tree().quit(1 if not failed.is_empty() or count == 0 else 0)


func _gd_files() -> PackedStringArray:
	var out: PackedStringArray = []
	var stack: Array[String] = []
	stack.append_array(ROOTS)
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				out.append(dir.path_join(f))
		for d in DirAccess.get_directories_at(dir):
			stack.append(dir.path_join(d))
	return out
