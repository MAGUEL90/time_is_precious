extends "res://scenes/test_scenes/mvp_first_playthrough.gd"
## UI review from an earned contract_journey checkpoint. No grants or clock edits.
const SAVE_PATH := "user://contract_ui/checkpoint.json"

func _run() -> void:
	checkpoint_path = SAVE_PATH
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--contract-ui-phase="):
			phase = arg.trim_prefix("--contract-ui-phase=")
	_expect(phase in ["prepare", "capture", "write", "read"], "Known UI review phase")
	_expect(FileAccess.file_exists(SAVE_PATH), "Seed isolated UI review with earned v7 checkpoint")
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
	_expect(same(expected, restored_snapshot), "Continue restores every earned owner and acknowledged notice")
	_expect(not player.debug_disable_player_needs and not player.debug_disable_fatigue, "Needs stay active")
	if content.name == "PlayerHomeInterior":
		await leave_home()
	if phase == "prepare":
		while TimeComponentManager.current_hour < 8 or TimeComponentManager.current_hour >= 16:
			await upkeep()
			await wait_minutes(30)
		_expect(WorkStateRuntime.get_node("CitySave").save_checkpoint(), "Prepare a normal daytime city checkpoint without changing world time")
	elif phase != "read":
		while TimeComponentManager.current_hour < 8 or TimeComponentManager.current_hour >= 16:
			await upkeep()
			await wait_minutes(30)
		var board = content.get_node("YSortWorld/InitialWorksites/JobBoard")
		await walk(board.get_node("InteractableComponent").global_position + Vector2(0, 8))
		await interact(board)
		var panel: JobBoardUI = board.job_board_ui
		_expect(is_instance_valid(panel), "Reach Job Board during normal opening hours")
		if not is_instance_valid(panel):
			return
		var before: int = Inventory.items.get("shekel", 0)
		var treasury: int = CityStockManager.treasury_shekel
		panel.hire_button.pressed.emit()
		panel._select_contract_days(6)
		_expect(panel.confirm_quote_amount_label.text == "2" and panel.confirm_quote_icon.visible, "Six-day Hauler package shows two with the currency icon")
		await _capture("job-board")
		await press(panel.close_button)
		_expect(Inventory.items.get("shekel", 0) == before, "Selecting package alone does not charge")
		var hub = runtime.worker_control
		hub.open()
		hub._show_manage(worker.worker_id)
		hub.renew_days_option.select(1)
		hub.renew_days_option.item_selected.emit(1)
		await _capture("worker-renew")
		var manage_position: Vector2 = hub.manage_window.position
		await press(hub.manage_renew_button)
		await _capture("renew-confirmation")
		await press(hub._confirm_no_button)
		_expect(Inventory.items.get("shekel", 0) == before, "Cancel renewal preserves wallet")
		var prior_end: int = worker.payroll_paid_until_day
		await press(hub.manage_renew_button)
		await press(hub._confirm_yes_button)
		_expect(Inventory.items.get("shekel", 0) == before - 2 and CityStockManager.treasury_shekel == treasury, "Only wallet pays manual six-day renewal")
		_expect(worker.payroll_paid_until_day == prior_end + 6, "Early renewal preserves all remaining paid time")
		# Stale duplicate confirmation has no pending purchase to apply.
		hub._confirm_yes_button.pressed.emit()
		_expect(Inventory.items.get("shekel", 0) == before - 2, "Repeated stale confirmation never pays twice")
		await _capture("renewed")
		_expect(hub.manage_window.position.is_equal_approx(manage_position), "Renewal refresh keeps the Manage popup anchored to its laid-out roster button")
		_expect(hub.manage_window.get_global_rect().encloses(hub.manage_renew_button.get_global_rect()), "Renew button stays inside the resized Manage frame")
		hub.close()
		if phase == "write":
			while not player.can_sleep() and not stopped:
				await upkeep()
				await wait_minutes(30)
			await sleep_home()
			_expect(WorkStateRuntime.get_node("CitySave").status == "Saved", "Real bed saves manual renewal")
	else:
		_expect(worker != null and worker.payroll_contract_days == 6 and not worker.is_payroll_blocked(), "Renewed worker survives Continue")
	measure("contract_ui_" + phase)
	release_input()
	print("ContractUIReview ", phase, ": ", "PASS" if failures == 0 else "FAIL")
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
		_expect(get_viewport().get_texture().get_image().save_png("user://contract_ui/" + label + ".png") == OK, "Save " + label)
