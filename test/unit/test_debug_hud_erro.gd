extends GutTest
## Tela de debug com dados inválidos: mostra o erro e só o botão de idioma
## (observação do QA no PR #4).

const HudScene := preload("res://scenes/debug/debug_hud.tscn")

var _old_ready: bool
var _old_errors: PackedStringArray


func before_each() -> void:
	_old_ready = Game.ready_ok
	_old_errors = Game.sim.data.errors.duplicate()
	Game.ready_ok = false
	Game.sim.data.errors = PackedStringArray(["sim.json: falta a chave 'speeds'"])


func after_each() -> void:
	Game.ready_ok = _old_ready
	Game.sim.data.errors = _old_errors


func test_so_o_botao_de_idioma_fica_visivel() -> void:
	var hud: Control = HudScene.instantiate()
	add_child_autofree(hud)
	var visible_buttons: Array = hud._buttons.get_children().filter(func(b: Node) -> bool: return b.visible)
	assert_eq(visible_buttons, [hud._locale_button])
	assert_eq(hud._date_label.text, tr("HUD_DATA_ERROR"))
	assert_true(hud._season_label.text.contains("falta a chave 'speeds'"))


func test_teclas_de_jogo_ignoradas_com_erro() -> void:
	var hud: Control = HudScene.instantiate()
	add_child_autofree(hud)
	var paused_before: bool = Game.paused
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	hud._unhandled_input(ev)
	assert_eq(Game.paused, paused_before, "sem dados válidos, espaço não faz nada")
