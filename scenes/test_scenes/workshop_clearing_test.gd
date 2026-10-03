extends Node

const STATE = preload("res://scenes/workshop_plot/workshop_construction_state.gd")
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	TimeComponentManager.is_paused = false
	TimeComponentManager.seconds_per_minute = 100000.0
	Inventory.items.clear()
	var worker := WorkerData.new()
	worker.worker_id = "clearing_test"
	worker.display_name = "Cleaner"
	WorkerDatabase.workers_by_id[worker.worker_id] = worker
	var state = STATE.new()
	add_child(state)
	var ids: Array[String] = [worker.worker_id]
	_expect(not state.start_build(ids).success, "Uncleared plot cannot be built.")
	_expect(not state.start_clearing([] as Array[String], false).success, "An assignee is required.")
	_expect(not state.start_clearing(ids, true).success, "Player plus worker is rejected.")
	_expect(not state.start_clearing([worker.worker_id, worker.worker_id] as Array[String], false).success, "Only one worker may clear.")
	_expect(state.start_clearing(ids, false).success and worker.is_reserved(), "Worker clearing starts without any materials and reserves the worker.")
	_expect(not state.start_clearing(ids, false).success, "Repeated start cannot duplicate work.")
	TimeComponentManager.advance_minutes(179)
	_expect(state.phase == "clearing", "Clearing takes the complete three hours.")
	TimeComponentManager.advance_minutes(1)
	_expect(state.phase == "empty" and not worker.is_reserved(), "Clearing completes and releases the worker at 180 minutes.")
	_expect(Inventory.items.is_empty(), "Clearing consumes or grants no materials.")
	state.free()
	state = STATE.new()
	add_child(state)
	state.start_clearing([] as Array[String], true)
	TimeComponentManager.advance_minutes(60)
	state.interrupt_player_clearing()
	_expect(state.phase == "uncleared" and state.clearing_remaining == 120, "Interrupted manual work retains completed progress.")
	TimeComponentManager.advance_minutes(60)
	_expect(state.clearing_remaining == 120, "Interrupted player work cannot progress unattended.")
	state.free()
	var content = preload("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	var plot = content.get_node("YSortWorld/WorkshopPlot")
	var player: Player = content.get_node("YSortWorld/Player")
	_expect(not plot.has_node("Footprint") and plot.get_node("ToBeClean").visible, "Uncleared plot uses authored debris without the old footprint.")
	player.debug_disable_player_needs = true
	player.global_position = plot.global_position
	await _frames()
	_expect(player.current_interactable != plot, "Standing in the plot center must not trigger Board access.")
	player.global_position = plot.get_node("InteractableComponent").global_position + Vector2(0, 12)
	await _frames()
	await _capture("clearing-hand.png")
	await _interact()
	_expect(player.current_interactable == plot, "Board edge shows an active hand-job target.")
	_expect(is_instance_valid(plot.menu), "E opens clearing UI from the visible prompt at the Board edge.")
	if not is_instance_valid(plot.menu):
		get_tree().quit(1)
		return
	_expect(not plot.menu.materials_list.visible, "Clearing UI hides material requirements.")
	plot.menu.player_button.button_pressed = true
	_expect(not plot.menu.build_button.disabled, "Player can clear without workers or materials.")
	await _capture("clearing-player-menu.png")
	var before: int = _now()
	plot.menu.build_button.pressed.emit()
	await plot.clearing_finished
	_expect(_now() - before == 180 and plot.construction.phase == "empty", "Player spends exactly three hours through the real UI.")
	_expect(not get_tree().paused and player.can_move, "Manual clearing restores controls.")
	_expect(not plot.get_node("ToBeClean").visible and plot.get_node("Plot").texture.resource_path.ends_with("plot_level_0.png"), "Clearing removes debris and retains level 0.")
	await _frames()
	await _capture("clearing-hammer.png")
	await _interact()
	_expect(plot.menu.materials_list.visible and not plot.menu.player_button.visible, "Cleared plot exposes construction materials and worker-only building.")
	plot.menu.close_menu()
	var retained = plot.construction
	content.free()
	content = preload("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	_expect(content.get_node("YSortWorld/WorkshopPlot").construction == retained and retained.phase == "empty", "Cleared state survives map reload.")
	print("WorkshopClearingTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _frames() -> void:
	for _index: int in range(5):
		await get_tree().physics_frame

func _interact() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventAction.new()
	event.action = "interact"
	get_viewport().push_input(event)
	await get_tree().process_frame

func _capture(filename: String) -> void:
	var directory: String = OS.get_environment("TIP_PLOT_CAPTURE_DIR")
	if directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join(filename))
