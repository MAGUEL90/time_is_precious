extends "res://scenes/test_scenes/mvp_first_playthrough.gd"
## Continue the earned renewal checkpoint. No grants, clock placements or needs overrides.
## Optional rendered write run captures the real confirmation before cancelling once.
const SAVE_PATH: String = "user://dismissal_journey/checkpoint.json"
const WORKER_ID: String = "initial_workshop_laborer"
var archived_xp: int = 0

func _run() -> void:
	checkpoint_path = SAVE_PATH
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dismissal-phase="):
			phase = arg.trim_prefix("--dismissal-phase=")
	_expect(phase in ["write", "read"], "Known dismissal journey phase")
	_expect(FileAccess.file_exists(SAVE_PATH), "Use the actual earned renewal checkpoint")
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
	get_tree().current_scene = menu
	await _frames()
	await press(menu.continue_button)
	while not launched and not stopped:
		await get_tree().process_frame
	bind_map()
	_expect(same(expected, restored_snapshot), "Continue restores the complete earned snapshot")
	measure("continued_" + phase)
	await leave_home()
	if phase == "write":
		_expect(worker != null and not worker.is_payroll_blocked() and not worker.is_reserved(), "Earned worker has unused paid time and is idle")
		if stopped:
			return
		# Release the saved workshop selection through its real assignment UI first.
		await open_workshop()
		await press(ui(WorkshopMenuUI).assign_button)
		await choose(ui(WorkshopProductionUI), JOB.job_id)
		var assignment = ui(WorkshopWorkerAssignmentUI)
		# Workshop selection is transient across Continue. Re-select through the UI
		# if needed, then release it so the linked employment status is consistent.
		if assignment._get_selected_worker_ids().is_empty():
			await press(assignment.slot_grid.get_child(0))
			await press(assignment.worker_list.get_child(0))
		await press(assignment.slot_grid.get_child(0))
		await press(assignment.close_button)
		_expect(worker.get_linked_citizen().employment_status == CitizenData.EmploymentStatus.HIRED, "Workshop selection released before dismissal")
		archived_xp = worker.profession_xp
		var wallet: int = Inventory.items.get("shekel", 0)
		var city: int = CityStockManager.treasury_shekel
		var hub = runtime.worker_control
		hub.open()
		hub._show_manage(WORKER_ID)
		await press(hub.manage_fire_button)
		_expect(hub._confirm_label.text.contains("remain.") and hub._confirm_label.text.contains("Unused pay is not refunded."), "Confirmation explains remaining paid time and no refund")
		await _frames()
		var label: Label = hub._confirm_label
		_expect(label.get_line_count() <= label.get_visible_line_count(), "All confirmation lines fit")
		_expect(label.get_global_rect().end.y <= hub._confirm_yes_button.global_position.y, "Text does not overlap confirmation buttons")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://dismissal_journey/confirmation.png")
		await press(hub._confirm_no_button)
		_expect(WorkerDatabase.has_worker_data(WORKER_ID) and Inventory.items.get("shekel", 0) == wallet and CityStockManager.treasury_shekel == city, "No preserves worker and both balances")
		await press(hub.manage_fire_button)
		await press(hub._confirm_yes_button)
		hub.close()
		_expect(not WorkerDatabase.has_worker_data(WORKER_ID) and WorkerDatabase.dismissed_workers[WORKER_ID].profession_xp == archived_xp, "Yes archives the earned worker and XP")
		_expect(Inventory.items.get("shekel", 0) == wallet and CityStockManager.treasury_shekel == city, "Dismissal refunds neither wallet nor city")
		worker = null
		measure("dismissed_without_refund")
		while not player.can_sleep() and not stopped:
			await upkeep()
			await wait_minutes(30)
		await sleep_home()
		var store: Node = WorkStateRuntime.get_node("CitySave")
		_expect(store.status == "Saved", "Normal bed successfully writes dismissed checkpoint: " + store.last_error)
	else:
		_expect(worker == null and WorkerDatabase.dismissed_workers.has(WORKER_ID), "Dismissal survives real Continue")
		var city: int = CityStockManager.treasury_shekel
		await upkeep()
		_expect(CityStockManager.treasury_shekel == city, "Dismissed worker has no new payroll charge")
		measure("dismissed_continue_city")
	await finish()

func measure(stage: String) -> void:
	super.measure(stage)
	measurements.back()["city_cash"] = CityStockManager.treasury_shekel
	measurements.back()["hired"] = WorkerDatabase.has_worker_data(WORKER_ID)
	measurements.back()["archived"] = WorkerDatabase.dismissed_workers.has(WORKER_ID)

func finish() -> void:
	release_input()
	var result := {"phase": phase, "status": "PASS" if failures == 0 else "FAIL", "failures": failures, "measurements": measurements}
	var file := FileAccess.open("user://dismissal_journey/" + phase + "-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("NormalDismissalJourney ", phase, ": ", result.status)
	get_tree().paused = false
	var current: Node = get_tree().current_scene
	get_tree().current_scene = null
	if is_instance_valid(current):
		current.queue_free()
	await _frames()
	get_tree().quit(0 if failures == 0 else 1)
