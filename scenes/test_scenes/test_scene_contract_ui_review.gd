extends "res://scenes/test_scenes/test_scene_contract_journey.gd"
## UI review from an earned checkpoint. No grants or clock edits; capture/write
## use existing citizen-pool names in the isolated review profile only.
## Reuse the journey's physical front-board City Storage helper.
const SAVE_PATH := "user://contract_ui/checkpoint.json"
const REVIEW_LABORER_NAME := "Naram"
const REVIEW_HAULER_NAME := "Lugal"

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
	if phase in ["capture", "write"]:
		_expect(CitizenGenerator.display_name_container.has(REVIEW_LABORER_NAME)
			and CitizenGenerator.display_name_container.has(REVIEW_HAULER_NAME), "Review names belong to the game's citizen name pool")
		var review_laborer: CitizenData = CitizenManager.get_citizen("initial_workshop_laborer")
		var review_hauler: CitizenData = CitizenManager.get_citizen("initial_worksite_hauler")
		_expect(review_laborer != null and review_hauler != null, "The isolated review checkpoint contains both candidates")
		if stopped:
			return
		review_laborer.display_name = REVIEW_LABORER_NAME
		review_hauler.display_name = REVIEW_HAULER_NAME
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
		var hauler_index: int = -1
		for index: int in range(panel.applicants.size()):
			if panel.applicants[index].citizen_id == "initial_worksite_hauler":
				hauler_index = index
				break
		_expect(hauler_index >= 0, "Job Board presents the review hauler candidate Lugal")
		if hauler_index < 0:
			return
		panel.applicant_list.select(hauler_index)
		panel.applicant_list.item_selected.emit(hauler_index)
		panel.hire_button.pressed.emit()
		panel._select_contract_days(6)
		_expect(panel.confirm_quote_amount_label.text == "2" and panel.confirm_quote_icon.visible, "Six-day Hauler package shows two with the currency icon")
		await _capture("lugal-job-board")
		await press(panel.close_button)
		_expect(Inventory.items.get("shekel", 0) == before, "Selecting package alone does not charge")
		var hub = runtime.worker_control
		hub.open()
		var manage_button: Button = hub._find_manage_button(worker.worker_id)
		_expect(is_instance_valid(manage_button), "Worker Hub lists the review worker Naram")
		if not is_instance_valid(manage_button):
			return
		await press(manage_button)
		await press(hub.manage_contract_button)
		var selected_days: int = _select_review_contract_days(hub, 6)
		var renewal_price: int = WorkerDatabase.get_contract_price(worker.profession, 6)
		_expect(selected_days == 6 and hub.contract_window.visible and hub.renew_price_label.text == "Price: %d" % renewal_price
			and hub.renew_price_icon.visible, "Naram's six-day Contract shows the exact renewal price")
		await _capture("naram-contract")
		var contract_position: Vector2 = hub.contract_window.position
		var old_until: int = worker.payroll_paid_until_day
		await press(hub.contract_close_button)
		_expect(not hub.contract_window.visible and hub.manage_window.visible
			and Inventory.items.get("shekel", 0) == before and worker.payroll_paid_until_day == old_until
			and CityStockManager.treasury_shekel == treasury,
			"Closing Contract returns to Manage without spending or extending Naram's renewal")
		await press(hub.manage_contract_button)
		selected_days = _select_review_contract_days(hub, 6)
		_expect(selected_days == 6 and hub.renew_price_label.text == "Price: %d" % renewal_price and hub.renew_price_icon.visible,
			"Reopened Contract still quotes the exact six-day price")
		await press(hub.manage_renew_button)
		var wallet_after_renew: int = int(Inventory.items.get("shekel", 0))
		var renewed_until: int = worker.payroll_paid_until_day
		_expect(wallet_after_renew == before - renewal_price and CityStockManager.treasury_shekel == treasury,
			"Only the player wallet pays the exact manual six-day renewal price")
		_expect(renewed_until == old_until + 6 and worker.payroll_contract_days == 6,
			"Early renewal preserves Naram's remaining time and adds exactly six days")
		_expect(hub.manage_renew_button.disabled, "A completed Contract selection cannot be renewed a second time")
		hub.manage_renew_button.pressed.emit()
		await _frames()
		_expect(Inventory.items.get("shekel", 0) == wallet_after_renew
			and worker.payroll_paid_until_day == renewed_until,
			"Repeated stale Renew input never charges or extends the six-day contract twice")
		await _capture("naram-renewed")
		_expect(hub.contract_window.position.is_equal_approx(contract_position), "Contract popup remains anchored to the selected roster row after renewal")
		_expect(hub.contract_window.get_global_rect().encloses(hub.manage_renew_button.get_global_rect()), "Renew button stays inside the resized Contract frame")
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

func _select_review_contract_days(hub: WorkerControlUI, days: int) -> int:
	for button: Button in hub.contract_day_buttons:
		var button_days: int = int(button.get_meta("contract_days", -1))
		if button_days != days:
			continue
		button.pressed.emit()
		return hub._selected_contract_days if button.button_pressed else -1
	return -1
