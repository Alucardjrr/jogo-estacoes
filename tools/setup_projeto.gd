extends SceneTree
## Configura o projeto pela API do Godot (D-015: nada de editar project.godot à mão).
## A cena scenes/debug/debug_hud.tscn é texto simples versionado (não depende deste script).
## Uso: godot --headless --path . -s tools/setup_projeto.gd

func _init() -> void:
	ProjectSettings.set_setting("autoload/Game", "*res://scripts/game.gd")
	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/debug/debug_hud.tscn")
	ProjectSettings.set_setting("internationalization/locale/translations", PackedStringArray([
		"res://data/text/ui.pt_BR.translation", "res://data/text/ui.en.translation"]))
	ProjectSettings.set_setting("internationalization/locale/fallback", "en")
	var err := ProjectSettings.save()

	print("project.godot: ", error_string(err))
	quit(0 if err == OK else 1)
