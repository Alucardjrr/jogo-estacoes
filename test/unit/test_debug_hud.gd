extends GutTest
## Tela de debug: retorno de obras e recusas no log, linha de trabalho com pedido
## acima dos trabalhadores, dica de materiais, formatação de números.

const HudScene := preload("res://scenes/debug/debug_hud.tscn")
const Hud := preload("res://scripts/ui/debug_hud.gd")

var hud: Control


func before_each() -> void:
	hud = HudScene.instantiate()
	add_child_autofree(hud)


func after_each() -> void:
	Game.sim.loop.take_commands()  # nada de comando sobrando no autoload


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


func test_dica_considera_ajuste_pendente() -> void:
	hud._pending = {"salvage": 1}
	assert_eq(hud.waiting_hint({"ruins_remaining": 800.0}, {"desired": {"salvage": 0}}),
		tr("HUD_HINT_SALVAGING"))
	hud._pending.clear()


func test_real_exibido_bate_com_sim_labor() -> void:
	var sim := Simulation.new()
	assert_true(sim.setup(1))
	for t in ["water", "farm", "care", "build", "salvage"]:
		sim.enqueue({"type": "set_labor", "task": t, "value": [7, 13, 5, 4, 2][["water", "farm", "care", "build", "salvage"].find(t)]})
	sim.population.families.resize(5)  # ~ 21 pessoas → 12 trabalhadores, pedido 31
	sim.step_day()
	var lab: Dictionary = sim.snapshot().labor
	var text: String = hud.labor_text(lab, {})
	for t in DataRegistry.TASK_IDS:
		assert_true(text.contains("%d→%d" % [lab.desired[t], roundi(lab.assigned[t])]),
			"%s: %s" % [t, text])


func test_simulacao_publica_posicao_na_fila() -> void:
	var sim := Simulation.new()
	assert_true(sim.setup(1))
	sim.enqueue({"type": "build", "building": "silo"})
	sim.enqueue({"type": "build", "building": "cisterna"})
	sim.step_day()
	var q := sim.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "build_queued")
	assert_eq(q.map(func(e: Dictionary) -> int: return e.position), [1, 2])
	assert_eq(q[0].max, int(sim.data.section("buildings").max_queue))


func test_campanha_na_tela() -> void:
	var c := {"years": 6, "year": 6, "days_left": 40, "final_year": true, "measures_locked": false,
		"ended": false, "outcome": ""}
	var text: String = hud.campaign_text(c)
	assert_true(text.contains(tr("HUD_CAMPAIGN_YEAR").format({"year": 6, "years": 6})), text)
	assert_true(text.contains(tr("HUD_CAMPAIGN_DAYS_LEFT").format({"days": 40})), text)
	c.days_left = 1
	c.measures_locked = true
	text = hud.campaign_text(c)
	assert_true(text.contains(tr("HUD_CAMPAIGN_LAST_DAY")), text)
	assert_true(text.contains(tr("HUD_CAMPAIGN_LOCKED")), text)


func test_resumo_do_fim() -> void:
	assert_eq(hud.end_text({}), "")
	var text: String = hud.end_text({"outcome": "de_pe", "population": 33, "initial": 50,
		"deaths": 4, "left": 3, "built": 2, "pop_by_year": [45, 40, 33], "worst_year": 1,
		"worst_lost": 5, "measures": {"racionamento": 2}})
	for part in [tr("OUTCOME_DE_PE"), tr("HUD_END_SURVIVORS").format({"population": 33, "initial": 50}),
			"45 / 40 / 33", tr("HUD_END_WORST").format({"year": 1, "lost": 5}),
			tr("MEASURE_RACIONAMENTO") + " ×2"]:
		assert_true(text.contains(part), "%s em %s" % [part, text])
