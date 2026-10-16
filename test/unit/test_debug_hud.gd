extends GutTest
## Tela de debug: retorno de obras e recusas no log, linha de trabalho com pedido
## acima dos trabalhadores, dica de materiais, formatação de números.

const HudScene := preload("res://scenes/debug/debug_hud.tscn")
const Hud := preload("res://scripts/ui/debug_hud.gd")

var hud: Control


func before_each() -> void:
	hud = HudScene.instantiate()
	add_child_autofree(hud)


func _lab(desired: Dictionary, workers: int, changed: bool = true) -> Dictionary:
	return {"desired": desired, "workers": workers, "productivity": 1.0, "changed": changed}


func test_pedido_acima_dos_trabalhadores_mostra_real_e_aviso() -> void:
	var text: String = hud.labor_text(_lab({"water": 3, "farm": 16, "care": 3, "build": 0,
		"salvage": 0}, 11), {})
	assert_true(text.contains("16→8"), text)  # 16 × 11/22
	assert_true(text.contains(tr("HUD_LABOR_OVER").format({"asked": 22, "workers": 11})), text)


func test_pedido_normal_sem_seta() -> void:
	var text: String = hud.labor_text(_lab({"water": 9, "farm": 18, "care": 3, "build": 0,
		"salvage": 0}, 30, false), {})
	assert_false(text.contains("→"))
	assert_true(text.contains(tr("HUD_LABOR_INITIAL")))


func test_ajuste_pendente_entra_na_conta_e_nao_trava() -> void:
	var lab := _lab({"water": 3, "farm": 16, "care": 3, "build": 0, "salvage": 0}, 12)
	hud._last_snapshot = Game.sim.snapshot()
	hud._last_snapshot.labor = lab
	hud._adjust_labor("salvage", 1)
	assert_eq(hud._pending.salvage, 1, "+1 aceito mesmo com pedido acima dos trabalhadores")
	assert_true(hud.labor_text(lab, hud._pending).contains("1→"))
	hud._pending.clear()
	Game.sim.loop.take_commands()  # não deixar comando no autoload para outros testes


func test_dica_de_materiais() -> void:
	var lab := {"desired": {"salvage": 0}}
	assert_eq(hud.waiting_hint({"ruins_remaining": 800.0}, lab), tr("HUD_HINT_SALVAGE"))
	lab.desired.salvage = 3
	assert_eq(hud.waiting_hint({"ruins_remaining": 800.0}, lab), tr("HUD_HINT_SALVAGING"))
	assert_eq(hud.waiting_hint({"ruins_remaining": 0.0}, lab), tr("HUD_HINT_RUINS_EMPTY"))


func test_log_mostra_fila_conclusao_e_recusa() -> void:
	var events: Array[Dictionary] = [
		{"type": "build_queued", "building": "cisterna", "position": 2, "max": 5},
		{"type": "building_completed", "building": "silo"},
		{"type": "command_rejected", "command": "build", "reason": "queue_full"}]
	hud._on_day_passed(Game.sim.snapshot(), events)
	var text: String = hud._log_label.text
	assert_true(text.contains(tr("BUILDING_CISTERNA")) and text.contains("2/5"), text)
	assert_true(text.contains(tr("REJECT_QUEUE_FULL")), text)
	assert_false(text.contains("{") or text.contains("REJECT_") or text.contains("EVENT_"), text)


func test_diario_antes_da_troca_de_estacao() -> void:
	var events: Array[Dictionary] = [
		{"type": "season_changed", "from": "seca", "to": "janela_1", "year": 1},
		{"type": "diary", "key": "DIARY_SECA_CALM_1", "params": {}}]
	var ordered := Hud.log_order(events)
	assert_eq(ordered.map(func(e: Dictionary) -> String: return e.type), ["diary", "season_changed"])


func test_formatacao_de_numeros() -> void:
	assert_eq(Hud._num(0.0), "0")
	assert_eq(Hud.signed(0.0), "0")
	assert_eq(Hud.signed(-0.0), "0")
	assert_eq(Hud.signed(2.0), "+2.0")
	assert_eq(Hud.signed(-0.5), "-0.5")
	assert_eq(Hud.signed(0.004), "+0.0040")


func test_pedido_de_obra_aparece_antes_do_dia_passar() -> void:
	hud._last_snapshot = Game.sim.snapshot()
	hud._pending_builds.append("silo")
	var text: String = hud._buildings_text(hud._last_snapshot)
	assert_true(text.contains(tr("BUILDING_SILO")), text)
	hud._pending_builds.clear()
