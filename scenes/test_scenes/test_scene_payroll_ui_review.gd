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
		_expect(panel.find_child("Deposit", true, false) == null,
			"Job Board has no currency deposit controls")
		_expect(panel.quote_label.text.contains("Next 08:00"),
			"Job Board shows the next payroll quote")
		await _capture("job-board")
		await press(panel.close_button)

		var area: Area2D = runtime.get_node("CityStorageArea")
		await walk(area.global_position + Vector2(0, 8))
		_expect(area.has_player_access(), "Reach physical City Storage for the earned Shekel deposit")
		await interact(area)
		var storage_menu = area.menu
		_expect(is_instance_valid(storage_menu), "Physical City Storage menu opens")
		if not is_instance_valid(storage_menu):
			return
		var storage = WorkStateRuntime.get_node("CityToolStorage")
		var wallet_before: int = Inventory.items.get("shekel", 0)
		var treasury_before: int = CityStockManager.treasury_shekel
		_expect(not storage.items.has("shekel"), "Earned review checkpoint has no physical Shekel stack")
		await press(storage_menu.deposit_button)
		var transfer: ItemTransferUI = storage_menu.transfer_ui
		_expect(is_instance_valid(transfer), "Physical City Storage opens the shared item selector")
		if not is_instance_valid(transfer):
			return
		var shekel_slot: ItemSlot = _find_transfer_slot(transfer, "shekel")
		_expect(is_instance_valid(shekel_slot) and shekel_slot._quantity >= 1,
			"Earned wallet contains a selectable Shekel")
		if not is_instance_valid(shekel_slot) or shekel_slot._quantity < 1:
			return
		shekel_slot.pressed.emit()
		_expect(int(transfer.selected_items.get("shekel", 0)) == 1,
			"Item selector stages exactly one Shekel")
		await _capture("deposit-selector")
		await press(transfer.close_button)
		_expect(Inventory.items.get("shekel", 0) == wallet_before
			and CityStockManager.treasury_shekel == treasury_before
			and not storage.items.has("shekel"),
			"Cancelling the selected Shekel leaves wallet, treasury and physical stock unchanged")
		await press(storage_menu.deposit_button)
		transfer = storage_menu.transfer_ui
		_expect(is_instance_valid(transfer), "Reopened City Storage opens a fresh item selector")
		if not is_instance_valid(transfer):
			return
		shekel_slot = _find_transfer_slot(transfer, "shekel")
		_expect(is_instance_valid(shekel_slot) and shekel_slot._quantity >= 1,
			"Reopened item selector still exposes the earned Shekel")
		if not is_instance_valid(shekel_slot) or shekel_slot._quantity < 1:
			return
		shekel_slot.pressed.emit()
		await press(transfer.confirm_button)
		_expect(Inventory.items.get("shekel", 0) == wallet_before - 1
			and CityStockManager.treasury_shekel == treasury_before + 1
			and not storage.items.has("shekel"),
			"Confirmed City Storage deposit transfers one Shekel to treasury without a physical coin stack")
		_expect(storage_menu.stock_summary.get_line_count() == 2, "Storage cash and stock summaries fit two explicit lines")
		await _capture("city-storage")
		var storage_close: BaseButton = storage_menu.view.get_node("Close") as BaseButton
		await press(storage_close)

		var inventory_after_deposit: Dictionary = Inventory.items.duplicate(true)
		var treasury_after_deposit: int = CityStockManager.treasury_shekel
		var raid_bootstrap: Node = content.get_node_or_null("RaidBootstrap")
		var city_management: RaidUI
		if is_instance_valid(raid_bootstrap):
			city_management = raid_bootstrap.get("raid_ui") as RaidUI
		_expect(is_instance_valid(city_management), "Live RaidBootstrap exposes City Management")
		if is_instance_valid(city_management):
			city_management.open_details()
			_expect(city_management.treasury_summary.text == "City cash: %d Shekel" % treasury_after_deposit, "Management shows the deposited city balance")
			await _capture("city-management")
			city_management._select_hub_tab(true)
			await _capture("city-supply")
			_expect(city_management.treasury_summary.is_visible_in_tree(), "Supply keeps the cash summary visible")
			_expect(city_management.details_panel.visible
				and Inventory.items == inventory_after_deposit
				and CityStockManager.treasury_shekel == treasury_after_deposit,
				"Opening read-only City Management preserves earned balances")
			city_management.close_details()

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
		_expect(WorkerDatabase.has_worker_data(worker.worker_id)
			and Inventory.items.get("shekel", 0) == wallet_before - 1
			and CityStockManager.treasury_shekel == treasury_before + 1,
			"Worker review and cancel preserve the hire and post-deposit balances")
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

func _find_transfer_slot(transfer: ItemTransferUI, item_id: String) -> ItemSlot:
	for child: Node in transfer.grid_container.get_children():
		var slot: ItemSlot = child as ItemSlot
		if is_instance_valid(slot) and slot._item_id == item_id:
			return slot
	return null
