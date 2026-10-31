extends "res://scenes/test_scenes/test_scene_contract_journey.gd"
## Continue an earned normal-journey checkpoint; isolate old assets through
## actual City Storage UI, collect worker output, sell, renew and bed-save.
## No grants, direct wallet edits, clock edits, RNG overrides or needs bypass.

const SOURCE_SAVE: String = "res://scenes/test_scenes/fixtures/payroll-worker-proceeds-origin.json"
const PROCEEDS_DIR: String = "user://worker_proceeds_journey"
const PROCEEDS_SAVE: String = PROCEEDS_DIR + "/checkpoint.json"
const PROCEEDS_EXPECTED: String = PROCEEDS_DIR + "/expected.json"
const PROCEEDS_EVIDENCE: String = PROCEEDS_DIR + "/flow-evidence.json"
const WORKER_ID: String = "initial_workshop_laborer"
const SALE_ITEM: String = "wood_log"

var proceeds_phase: String = "write"
var initial_wallet: int = 0
var initial_player_wood: int = 0
var city_cash_after_isolation: int = 0
var worker_wood_collected: int = 0
var worker_wood_kept: int = 0
var worker_wood_sold: int = 0
var worker_sale_income: int = 0
var wallet_after_renew: int = -1
var renewed_until: int = -1
var insufficient_checked: bool = false
var sale_visits: Array[Dictionary] = []


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--proceeds-phase="):
			proceeds_phase = arg.trim_prefix("--proceeds-phase=")
	_expect(proceeds_phase in ["write", "read"], "Use --proceeds-phase=write or read.")
	if stopped:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROCEEDS_DIR))
	if proceeds_phase == "write":
		_expect(not FileAccess.file_exists(PROCEEDS_SAVE), "Write requires a new isolated proceeds checkpoint.")
		if stopped:
			return
		var source := FileAccess.open(SOURCE_SAVE, FileAccess.READ)
		_expect(source != null, "The previously earned normal-journey checkpoint is readable.")
		if stopped:
			return
		var destination := FileAccess.open(PROCEEDS_SAVE, FileAccess.WRITE)
		_expect(destination != null, "The isolated proceeds checkpoint can be created.")
		if stopped:
			return
		destination.store_buffer(source.get_buffer(source.get_length()))
		destination.close()
		source.close()
	else:
		_expect(FileAccess.file_exists(PROCEEDS_SAVE) and FileAccess.file_exists(PROCEEDS_EVIDENCE),
			"Read requires the completed proceeds write phase in the same isolated profile.")
		if stopped:
			return

	get_tree().current_scene = null
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = PROCEEDS_SAVE
	menu.session_started.connect(func(continued: bool):
		if continued:
			restored_snapshot = WorkStateRuntime.get_node("CitySave").snapshot.capture(get_tree().current_scene)
		launched = continued)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	await press(menu.continue_button)
	while not launched and not stopped:
		await get_tree().process_frame
	bind_map()
	if proceeds_phase == "read":
		await _verify_proceeds_continue()
	else:
		await _run_proceeds_write()


func _run_proceeds_write() -> void:
	_expect(content.name == "PlayerHomeInterior" and worker != null,
		"The normal-journey checkpoint restores at home with the hired Laborer.")
	if stopped:
		return
	initial_wallet = int(Inventory.items.get("shekel", 0))
	initial_player_wood = int(Inventory.items.get(SALE_ITEM, 0))
	_expect(initial_wallet > 0 and initial_player_wood > 0 and not worker.is_payroll_blocked(),
		"The prior normal journey has earned wallet and personal wood, and a renewed worker.")
	await leave_home()
	await eat()
	await _deposit_items({"shekel": initial_wallet, SALE_ITEM: initial_player_wood})
	city_cash_after_isolation = CityStockManager.treasury_shekel
	_expect(int(Inventory.items.get("shekel", 0)) == 0 and int(Inventory.items.get(SALE_ITEM, 0)) == 0,
		"The physical City Storage deposit separates pre-existing wallet and personal wood.")
	await _check_unfunded_renew()
	await _collect_worker_wood()
	if stopped:
		return
	# Leave capacity for food and carry no more than the configured maximum request.
	worker_wood_kept = mini(worker_wood_collected, 6)
	var excess: int = worker_wood_collected - worker_wood_kept
	if excess > 0:
		await _deposit_items({SALE_ITEM: excess})
	_expect(int(Inventory.items.get(SALE_ITEM, 0)) == worker_wood_kept,
		"Every carried wood log after the deposit came from the worker pickup.")
	measure("worker_wood_carried")
	var deadline: int = now() + 20 * 1440
	while worker_sale_income == 0 and now() < deadline and not stopped:
		await upkeep()
		await _sell_worker_wood_if_requested()
		if worker_sale_income == 0 and not stopped:
			await wait_minutes(30)
	if worker_sale_income == 0 and not stopped:
		await _finish_proceeds("PARTIAL", "No natural merchant wood request appeared in the observation window.")
		return
	var price: int = WorkerDatabase.get_contract_price(worker.profession, 3)
	if int(Inventory.items.get("shekel", 0)) < price:
		await _finish_proceeds("PARTIAL", "The observed worker sale did not cover the current renewal quote.")
		return
	await _renew_from_proceeds(price)
	while not stopped and not player.can_sleep():
		await upkeep()
		await wait_minutes(30)
	if stopped:
		return
	await sleep_home()
	_expect(FileAccess.file_exists(PROCEEDS_SAVE), "The real bed saves the worker-proceeds journey.")
	if stopped:
		return
	var expected := FileAccess.open(PROCEEDS_EXPECTED, FileAccess.WRITE)
	expected.store_string(FileAccess.get_file_as_string(PROCEEDS_SAVE))
	expected.close()
	var evidence := FileAccess.open(PROCEEDS_EVIDENCE, FileAccess.WRITE)
	evidence.store_string(JSON.stringify(_proceeds_summary(), "\t"))
	evidence.close()
	await _finish_proceeds("PASS", "Worker proceeds were sold and paid for renewal.")


func _deposit_items(selection: Dictionary) -> void:
	if stopped:
		return
	var area: Node = runtime.get_node("CityStorageArea")
	var before_wallet: int = int(Inventory.items.get("shekel", 0))
	var before_wood: int = int(Inventory.items.get(SALE_ITEM, 0))
	var before_cash: int = CityStockManager.treasury_shekel
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var before_storage_wood: int = int(storage.items.get(SALE_ITEM, 0))
	await walk(area.get_node("Board").global_position + Vector2(-17, 13))
	await interact(area)
	var menu: CanvasLayer = area.menu
	_expect(is_instance_valid(menu) and area.has_player_access(), "Reach and open physical City Storage.")
	if stopped:
		return
	await press(menu.deposit_button)
	var transfer: ItemTransferUI = menu.transfer_ui
	_expect(is_instance_valid(transfer), "City Storage opens the actual deposit screen.")
	if stopped:
		return
	for id: String in selection:
		var item_slot: ItemSlot
		for child: Node in transfer.grid_container.get_children():
			if child is ItemSlot and child._item_id == id:
				item_slot = child as ItemSlot
				break
		_expect(is_instance_valid(item_slot), "The selected inventory item is offered for city deposit: " + id)
		if stopped:
			return
		for _index: int in range(int(selection[id])):
			item_slot.pressed.emit()
		_expect(int(transfer.selected_items.get(id, 0)) == int(selection[id]), "The UI stages the exact deposit: " + id)
	await press(transfer.confirm_button)
	_expect(int(Inventory.items.get("shekel", 0)) == before_wallet - int(selection.get("shekel", 0))
		and int(Inventory.items.get(SALE_ITEM, 0)) == before_wood - int(selection.get(SALE_ITEM, 0))
		and CityStockManager.treasury_shekel == before_cash + int(selection.get("shekel", 0))
		and int(storage.items.get(SALE_ITEM, 0)) == before_storage_wood + int(selection.get(SALE_ITEM, 0)),
		"Confirm moves exactly the selected wallet and wood into city storage.")
	await press(transfer.back_button)
	await press(menu.view.get_node("Margin/Content/Footer/Back"))
	_expect(not get_tree().paused and player.can_move, "Closing City Storage returns to live play.")


func _open_manage() -> WorkerControlUI:
	await _press_input("open_worker_hub")
	var hub: WorkerControlUI = runtime.worker_control
	_expect(hub.visible, "The actual Worker Hub opens through its input action.")
	if stopped:
		return hub
	await press(hub._find_manage_button(WORKER_ID))
	_expect(hub.renew_days_option.get_selected_id() == 3, "The UI offers its standard three-day renewal.")
	return hub


func _check_unfunded_renew() -> void:
	var old_until: int = worker.payroll_paid_until_day
	var hub: WorkerControlUI = await _open_manage()
	await press(hub.manage_renew_button)
	await press(hub._confirm_yes_button)
	insufficient_checked = int(Inventory.items.get("shekel", 0)) == 0 \
		and CityStockManager.treasury_shekel == city_cash_after_isolation \
		and worker.payroll_paid_until_day == old_until \
		and hub.renew_price_label.text == "Renewal failed; check wallet."
	_expect(insufficient_checked, "Renew rejects an empty wallet despite city cash, without changing the contract.")
	await _capture_proceeds("insufficient-wallet")
	await _press_input("open_worker_hub")
	_expect(not hub.visible and not get_tree().paused, "Close Worker Hub after the failed renewal.")


func _collect_worker_wood() -> void:
	var pile: PickUpItem
	for candidate: Node in runtime.get_node("GroundOutput").get_children():
		if candidate is PickUpItem and candidate.get_meta("daily_site", "") == "WoodSite" \
			and candidate.item_id == SALE_ITEM and not candidate.is_collecting:
			pile = candidate as PickUpItem
			break
	_expect(is_instance_valid(pile) and worksite_output() > 0,
		"The continued worker assignment has a tagged WoodSite output pile.")
	if stopped:
		return
	await walk(pile.global_position + Vector2(0, -5))
	_expect(player.current_interactable == pile, "Walking selects the actual worker-output pickup.")
	if stopped:
		return
	var available: int = pile.quantity
	var before: int = int(Inventory.items.get(SALE_ITEM, 0))
	await _capture_proceeds("worker-pickup")
	await interact(pile)
	worker_wood_collected = int(Inventory.items.get(SALE_ITEM, 0)) - before
	_expect(before == 0 and worker_wood_collected > 0 and worker_wood_collected <= available,
		"The E pickup adds only worker-produced wood to the empty personal wood stack.")
	measure("worker_wood_collected")


func _sell_worker_wood_if_requested() -> void:
	var merchant: Node = content.get_node("YSortWorld/TravelingMerchant")
	if not merchant.state.is_present() or stopped:
		return
	var day: int = TimeComponentManager.current_day
	if not seen_visits.has(day):
		seen_visits[day] = true
		var record: Dictionary = {"day": day, "catalog": merchant.state.get_catalog()}
		sale_visits.append(record)
		print("WorkerProceedsVisit ", JSON.stringify(record))
	var price: int = 0
	for row: Dictionary in merchant.state.get_catalog():
		if str(row.item_id) == SALE_ITEM and int(row.demand) > 0:
			price = int(row.sell_price)
	if price <= 0:
		return
	await walk(merchant.global_position + Vector2(0, 6))
	await interact(merchant)
	await accept_greeting(merchant)
	if stopped:
		return
	var menu: TravelingMerchantUI = merchant.menu
	await press(menu.sell_tab)
	var item_button: Button
	for child: Node in menu.catalog_list.get_children():
		if str(child.get_meta("merchant_item_id", "")) == SALE_ITEM:
			item_button = child as Button
			break
	_expect(is_instance_valid(item_button), "The merchant offers the requested wood in the real Sell UI.")
	if stopped:
		return
	await press(item_button)
	await press(menu.max_button)
	var before_wallet: int = int(Inventory.items.get("shekel", 0))
	var before_wood: int = int(Inventory.items.get(SALE_ITEM, 0))
	var before_cash: int = CityStockManager.treasury_shekel
	await press(menu.confirm_button)
	worker_wood_sold = before_wood - int(Inventory.items.get(SALE_ITEM, 0))
	worker_sale_income = int(Inventory.items.get("shekel", 0)) - before_wallet
	_expect(before_wallet == 0 and worker_wood_sold > 0 and worker_wood_sold <= worker_wood_kept
		and worker_sale_income == worker_wood_sold * price and CityStockManager.treasury_shekel == before_cash,
		"A real sale credits the empty player wallet exactly for the worker wood sold.")
	measure("worker_wood_sold")
	await _capture_proceeds("worker-sale")
	await press(menu.back_button)


func _renew_from_proceeds(price: int) -> void:
	var wallet_before: int = int(Inventory.items.get("shekel", 0))
	var cash_before: int = CityStockManager.treasury_shekel
	var old_until: int = worker.payroll_paid_until_day
	var was_active: bool = not worker.is_payroll_blocked()
	var expected_until: int = (old_until if was_active else TimeComponentManager.current_day) + 3
	var hub: WorkerControlUI = await _open_manage()
	await press(hub.manage_renew_button)
	await press(hub._confirm_no_button)
	_expect(int(Inventory.items.get("shekel", 0)) == wallet_before and worker.payroll_paid_until_day == old_until,
		"Canceling the funded renewal changes neither wallet nor contract.")
	await press(hub.manage_renew_button)
	await _capture_proceeds("renew-confirm")
	await press(hub._confirm_yes_button)
	wallet_after_renew = int(Inventory.items.get("shekel", 0))
	renewed_until = worker.payroll_paid_until_day
	_expect(wallet_before == worker_sale_income and wallet_after_renew == wallet_before - price
		and CityStockManager.treasury_shekel == cash_before and renewed_until == expected_until
		and not worker.is_payroll_blocked(),
		"Confirmation pays the three-day renewal once from worker-sale proceeds, not city cash.")
	hub._confirm_yes_button.pressed.emit()
	await _frames()
	_expect(int(Inventory.items.get("shekel", 0)) == wallet_after_renew and worker.payroll_paid_until_day == renewed_until,
		"A stale repeat confirmation cannot charge the renewal twice.")
	await _press_input("open_worker_hub")
	_expect(not hub.visible and not get_tree().paused, "Close Worker Hub after renewal.")
	measure("worker_proceeds_renewed")


func _verify_proceeds_continue() -> void:
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROCEEDS_EXPECTED))
	var evidence: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROCEEDS_EVIDENCE))
	_expect(expected is Dictionary and evidence is Dictionary and same(expected, restored_snapshot),
		"Separate-process Continue restores the exact bed checkpoint.")
	if stopped:
		return
	_expect(worker != null and not worker.is_payroll_blocked()
		and worker.payroll_paid_until_day == int(evidence.renewed_until)
		and int(Inventory.items.get("shekel", 0)) == int(evidence.wallet_after_renew)
		and CityStockManager.treasury_shekel == int(evidence.city_cash_after_isolation),
		"Continue preserves the worker-funded renewal, wallet and city cash.")
	initial_wallet = int(evidence.initial_wallet)
	initial_player_wood = int(evidence.initial_player_wood)
	city_cash_after_isolation = int(evidence.city_cash_after_isolation)
	insufficient_checked = bool(evidence.insufficient_checked)
	worker_wood_collected = int(evidence.worker_wood_collected)
	worker_wood_kept = int(evidence.worker_wood_kept)
	worker_wood_sold = int(evidence.worker_wood_sold)
	worker_sale_income = int(evidence.worker_sale_income)
	wallet_after_renew = int(evidence.wallet_after_renew)
	renewed_until = int(evidence.renewed_until)
	await leave_home()
	_expect(runtime.daily.jobs.has(&"WoodSite") and runtime.daily.jobs[&"WoodSite"].ids.has(WORKER_ID),
		"Continue retains the worker's standing WoodSite assignment.")
	await _capture_proceeds("continued-city")
	await _finish_proceeds("PASS", "Separate-process Continue preserved the completed cycle.")


func _proceeds_summary() -> Dictionary:
	return {"initial_wallet": initial_wallet, "initial_player_wood": initial_player_wood,
		"city_cash_after_isolation": city_cash_after_isolation, "insufficient_checked": insufficient_checked,
		"worker_wood_collected": worker_wood_collected, "worker_wood_kept": worker_wood_kept,
		"worker_wood_sold": worker_wood_sold, "worker_sale_income": worker_sale_income,
		"wallet_after_renew": wallet_after_renew, "renewed_until": renewed_until,
		"sale_visits": sale_visits, "measurements": measurements}


func _capture_proceeds(label: String) -> void:
	await _frames()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_expect(get_viewport().get_texture().get_image().save_png(PROCEEDS_DIR.path_join(label + ".png")) == OK,
			"Save the rendered evidence: " + label)


func _finish_proceeds(status: String, detail: String) -> void:
	release_input()
	var result: Dictionary = _proceeds_summary()
	result["phase"] = proceeds_phase
	result["status"] = status
	result["detail"] = detail
	result["failures"] = failures
	var file := FileAccess.open(PROCEEDS_DIR.path_join(proceeds_phase + "-result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("WorkerProceedsJourney ", proceeds_phase, ": ", status, " ", detail)
	get_tree().paused = false
	var current: Node = get_tree().current_scene
	get_tree().current_scene = null
	if is_instance_valid(current):
		current.queue_free()
	await _frames()
	get_tree().quit(0 if status == "PASS" else 2)
