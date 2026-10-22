extends "res://scenes/test_scenes/mvp_first_playthrough.gd"
## Rendered review from an earned checkpoint; no grants or clock/needs overrides.
const SAVE_PATH := "user://payroll_ui_review/checkpoint.json"

func _run() -> void:
	checkpoint_path = SAVE_PATH
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-phase="):
			phase = arg.trim_prefix("--ui-phase=")
	_expect(phase in ["capture", "write", "read"], "Known UI review phase")
	_expect(FileAccess.file_exists(SAVE_PATH), "Copy an earned v6 checkpoint to the isolated review directory")
	if stopped:
		return
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	get_tree().current_scene = null
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = SAVE_PATH
	menu.session_started.connect(func(_continued: bool):
		restored_snapshot = WorkStateRuntime.get_node("CitySave").snapshot.capture(get_tree().current_scene)
		launched = true)
	get_tree().root.add_child(menu)
	await _frames()
	await press(menu.continue_button)
	while not launched and not stopped:
		await get_tree().process_frame
	bind_map()
	_expect(same(expected, restored_snapshot), "Continue restores the complete earned UI-review checkpoint")
	_expect(not player.debug_disable_player_needs and not player.debug_disable_fatigue, "Needs and fatigue remain enabled")
	await leave_home()
	if phase != "read":
		var board = content.get_node("YSortWorld/InitialWorksites/JobBoard")
		await walk(board.get_node("InteractableComponent").global_position + Vector2(0, 8))
		await interact(board)
		var panel: JobBoardUI = board.job_board_ui
		var wallet: int = Inventory.items.get("shekel", 0)
		var treasury: int = CityStockManager.treasury_shekel
		await _capture("job-board")
		var amount_rect: Rect2 = panel.deposit_amount.get_global_rect()
		await _click(amount_rect.position + Vector2(amount_rect.size.x - 3, 3))
		_expect(panel.deposit_amount.value == 2, "Up arrow increments amount")
		await _click(amount_rect.end - Vector2(3, 3))
		_expect(panel.deposit_amount.value == 1, "Down arrow decrements amount")
		await _click(amount_rect.end - Vector2(3, 3))
		_expect(panel.deposit_amount.value == 1, "Down arrow respects minimum")
		panel.deposit_amount.value = 2
		await _capture("deposit-amount")
		_expect(Inventory.items.get("shekel", 0) == wallet and CityStockManager.treasury_shekel == treasury, "Changing amount alone transfers no money")
		await press(panel.close_button)
		await interact(board)
		panel = board.job_board_ui
		await _frames()
		_expect(panel.deposit_amount.value == 1, "Recreated panel resets amount without a transfer")
		await press(panel.close_button)
		var hub = runtime.worker_control
		hub.open()
		await _capture("worker-hub")
		hub._show_details(worker.worker_id)
		await _capture("worker-details")
		var visuals: Control = hub.details_scroll.get_node("Visuals")
		_expect(visuals.size.x <= hub.details_scroll.size.x, "Payroll details fit without horizontal scrolling")
		hub._show_manage(worker.worker_id)
		await press(hub.manage_fire_button)
		await _capture("fire-confirmation")
		_expect(hub._confirm_label.get_line_count() <= hub._confirm_label.get_visible_line_count(), "Confirmation text fits")
		await press(hub._confirm_no_button)
		hub.close()
		_expect(WorkerDatabase.has_worker_data(worker.worker_id) and Inventory.items.get("shekel", 0) == wallet and CityStockManager.treasury_shekel == treasury, "Review and cancel leave worker and money unchanged")
		if phase == "write":
			while not player.can_sleep() and not stopped:
				await upkeep()
				await wait_minutes(30)
			await sleep_home()
			_expect(WorkStateRuntime.get_node("CitySave").status == "Saved", "Real bed saves after UI review")
	else:
		_expect(worker != null and not worker.is_payroll_blocked(), "Paid worker survives Continue after UI review")
	measure("ui_review_" + phase)
	release_input()
	print("PayrollUIReview ", phase, ": ", "PASS" if failures == 0 else "FAIL")
	get_tree().paused = false
	var current: Node = get_tree().current_scene
	get_tree().current_scene = null
	current.queue_free()
	await _frames()
	get_tree().quit(0 if failures == 0 else 1)

func _capture(label: String) -> void:
	await _frames()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_expect(get_viewport().get_texture().get_image().save_png("user://payroll_ui_review/" + label + ".png") == OK, "Save " + label + " screenshot")

func _click(position: Vector2) -> void:
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.global_position = position
		event.pressed = down
		get_viewport().push_input(event, true)
		await _frames()
