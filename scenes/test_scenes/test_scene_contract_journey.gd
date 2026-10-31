extends "res://scenes/test_scenes/mvp_first_playthrough.gd"
## Normal income, authored applicants, approved temporary rates, live needs.
## Actual income and physical UI; no grants, clock edits, RNG overrides or disabled needs.
# This records payroll_changed signals, including the routine 07:00/08:00 refreshes;
# only wallet deltas establish that a payment happened.
var settlements: Array[Dictionary] = []
var wallet_paid: int = 0
var payroll_day: int = -1
var first_payment_observed: bool = false
var assignment_observed: bool = false
var arrival_observed: bool = false
var output_observed: int = 0
var expired_observed: bool = false
var renewal_observed: bool = false
var output_after_renewal: int = 0
const EXPECTED_PATH: String = "user://contract_journey/expected.json"
const EVIDENCE_PATH: String = "user://contract_journey/flow-evidence.json"

func _press_input(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)
	await _frames(2)
	event = InputEventAction.new()
	event.action = action
	get_viewport().push_input(event)
	await _frames(2)

func eat() -> void:
	var amount: int = mini(int(Inventory.items.get("date_cluster", 0)), floori(player.hunger / 0.04))
	if amount <= 0 or stopped:
		return
	var inventory_ui: InventoryUI = content.get_node("InventoryUI")
	await _press_input("open_inventory")
	_expect(inventory_ui.visible, "Inventory opens through its normal input")
	if stopped:
		return
	var dates: ItemSlot
	for slot: ItemSlot in inventory_ui.grid.get_children():
		if slot._item_id == "date_cluster":
			dates = slot
			break
	_expect(is_instance_valid(dates), "Earned dates are visible in Inventory")
	if stopped:
		return
	var before: int = int(Inventory.items.get("date_cluster", 0))
	await press(dates)
	_expect(is_instance_valid(inventory_ui.active_option_panel), "Date options open through the item slot")
	if stopped:
		return
	await press(inventory_ui.active_option_panel.use_button)
	var confirm: ItemActionConfirmPanel = inventory_ui.active_action_confirm_panel
	_expect(is_instance_valid(confirm), "Use opens its quantity and confirmation panel")
	if stopped:
		return
	for _index: int in range(amount - 1):
		confirm.plus_button.pressed.emit()
	_expect(confirm.current_quantity == amount, "The normal quantity control selects the intended dates")
	await press(confirm.confirm_button)
	await press(confirm.confirm_actions.confirm_button)
	while inventory_ui.is_inventory_action_busy and not stopped:
		await get_tree().process_frame
	var consumed: int = before - int(Inventory.items.get("date_cluster", 0))
	_expect(consumed == amount, "Eating consumes the selected earned dates through Inventory")
	eaten += consumed
	await press(inventory_ui.close_button)

func gather(site_name: String) -> void:
	await upkeep()
	if stopped:
		return
	var marker: Marker2D = runtime.get_node("WorksiteMarkers/" + site_name)
	await walk(marker.global_position)
	await interact()
	_expect(runtime.inspector.visible, "E opens " + site_name)
	if stopped:
		return
	await press(runtime.inspector.hourly_button)
	await press(runtime.inspector.next_button)
	await press(runtime.inspector.start_button)
	while runtime._working and not stopped:
		await get_tree().process_frame
	_expect(runtime.last_work_result.minutes == 180 and not runtime.last_work_result.interrupted, "Normal three-hour gathering " + site_name)
	await eat()
	measure("gather_" + site_name)

func supply_city() -> void:
	if stopped:
		return
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var need: int = maxi(CitizenNeedsManager.get_food_consumer_count() * 2 - storage.get_food_supply_points(), 0)
	var amount: int = mini(need, maxi(int(Inventory.items.get("date_cluster", 0)) - 8, 0))
	if amount <= 0:
		return
	var area: Node = runtime.get_node("CityStorageArea")
	# Approach the authored front board, inside the current physical access shape.
	await walk(area.get_node("Board").global_position + Vector2(-17, 13))
	if stopped:
		return
	await interact(area)
	var menu: CanvasLayer = area.menu
	_expect(is_instance_valid(menu) and area.has_player_access(), "Physical City Storage opens at its front board")
	if stopped:
		return
	var before_dates: int = int(Inventory.items.get("date_cluster", 0))
	var before_food: int = storage.get_food_supply_points()
	await press(menu.deposit_button)
	var transfer: ItemTransferUI = menu.transfer_ui
	_expect(is_instance_valid(transfer), "City Storage Deposit opens its actual transfer screen")
	if stopped:
		return
	var dates: ItemSlot
	for slot: ItemSlot in transfer.grid_container.get_children():
		if slot._item_id == "date_cluster":
			dates = slot
			break
	_expect(is_instance_valid(dates), "Earned dates are offered in the physical deposit screen")
	if stopped:
		return
	for _index: int in range(amount):
		dates.pressed.emit()
	_expect(int(transfer.selected_items.get("date_cluster", 0)) == amount, "Deposit selects only the intended earned dates")
	await press(transfer.confirm_button)
	_expect(int(Inventory.items.get("date_cluster", 0)) == before_dates - amount and storage.get_food_supply_points() == before_food + amount, "Confirmed deposit moves earned dates to city food exactly once")
	if stopped:
		return
	await press(transfer.back_button)
	await press(menu.view.get_node("Margin/Content/Footer/Back"))
	_expect(not get_tree().paused and player.can_move, "Closing City Storage restores normal play")

func sleep_home() -> void:
	if stopped:
		return
	await super.sleep_home()

func trade() -> void:
	var merchant = content.get_node("YSortWorld/TravelingMerchant")
	if not merchant.state.is_present() or stopped:
		return
	var visit_key: int = TimeComponentManager.current_day
	if not seen_visits.has(visit_key):
		seen_visits[visit_key] = true
		visits.append({"day": visit_key, "catalog": merchant.state.get_catalog()})
		print("MVP_VISIT ", JSON.stringify(visits.back()))
	var sellable: bool = false
	for row: Dictionary in merchant.state.get_catalog():
		if row.demand > 0 and Inventory.items.get(row.item_id, 0) > 0:
			sellable = true
	if not sellable:
		return
	await walk(merchant.global_position + Vector2(0, 6))
	await interact(merchant)
	await accept_greeting(merchant)
	if stopped:
		return
	var menu: TravelingMerchantUI = merchant.menu
	await press(menu.sell_tab)
	for id: String in ["wood_log", "sun_dried_mudbrick"]:
		if int(Inventory.items.get(id, 0)) <= 0:
			continue
		var item_button: Button
		for child: Node in menu.catalog_list.get_children():
			if str(child.get_meta("merchant_item_id", "")) == id:
				item_button = child as Button
				break
		if item_button == null:
			continue
		await press(item_button)
		if menu.max_button.disabled:
			continue
		await press(menu.max_button)
		if menu.confirm_button.disabled:
			continue
		var before: int = int(Inventory.items.get("shekel", 0))
		var count: int = int(Inventory.items.get(id, 0))
		await press(menu.confirm_button)
		earned += int(Inventory.items.get("shekel", 0)) - before
		if id == "wood_log":
			sold_wood += count - int(Inventory.items.get(id, 0))
		else:
			sold_bricks += count - int(Inventory.items.get(id, 0))
	await _capture("sale")
	await press(menu.back_button)
	measure("sale")

func _run() -> void:
	checkpoint_path = "user://contract_journey/checkpoint.json"
	WorkerDatabase.payroll_changed.connect(_observe_payroll)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--journey-phase="):
			phase = arg.trim_prefix("--journey-phase=")
	get_tree().current_scene = null
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = checkpoint_path
	menu.session_started.connect(func(continued: bool):
		if continued:
			restored_snapshot = WorkStateRuntime.get_node("CitySave").snapshot.capture(get_tree().current_scene)
		launched = true)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	if phase == "read":
		await press(menu.continue_button)
	else:
		_expect(menu.continue_button.disabled, "Fresh isolated normal-journey directory required")
		await press(menu.new_game_button)
	while not launched and not stopped:
		await get_tree().process_frame
	bind_map()
	if phase == "read":
		await verify_continue()
		return
	_expect(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty()
		and CityStockManager.treasury_shekel == 0, "Normal New Game has no wallet, workers or city cash")
	_expect(preload("res://resources/traveling_merchant/common_merchant.tres").randomize_requests, "No forced merchant requests")
	measure("new_game")
	while earned == 0 and TimeComponentManager.current_day < 16 and not stopped:
		await upkeep()
		await trade()
		if earned > 0 or stopped:
			break
		if Inventory.items.get("wood_log", 0) < 8 and player.fatigue < 0.55:
			await gather("WoodSite")
		else:
			await wait_minutes(60)
	if earned == 0 or stopped:
		await finish()
		return
	await hire()
	if stopped or worker == null:
		await finish()
		return
	payroll_day = worker.payroll_paid_from_day
	first_payment_observed = worker.payroll_period_rate == 1 and worker.payroll_paid_until_day == payroll_day + 3
	_expect(first_payment_observed and CityStockManager.treasury_shekel == 0, "Immediate three-day contract leaves city cash untouched")
	_expect(settlements.size() == 1 and settlements[0].minute == worker.payroll_paid_start_minute, "Hire pays exactly once at the actual purchase minute")
	measure("first_payment")
	await assign_woodsite()
	await observe_output(0, false)
	while not stopped and not worker.is_payroll_blocked():
		await upkeep()
		await wait_minutes(30)
	if not stopped:
		expired_observed = now() >= worker.get_paid_end_minute() and worker.is_payroll_blocked()
		_expect(expired_observed, "The paid contract expires naturally without auto-renewal")
		measure("expired")
		var expired_output: int = worksite_output()
		_expect(expired_output >= output_observed, "The standing assignment and its output remain present at expiry")
		await wait_minutes(15)
		_expect(worker.is_payroll_blocked() and worksite_output() == expired_output, "An expired worker produces no output during the observed interval")
		await renew_expired()
		await observe_output(expired_output, true)
	# Save through the real bed, never a synthetic snapshot or a resource grant.
	while not stopped and not player.can_sleep():
		await upkeep()
		await wait_minutes(60)
	if not stopped:
		await sleep_home()
		_expect(FileAccess.file_exists(checkpoint_path), "Real bed persists the earned paid-worker journey")
		var file := FileAccess.open(EXPECTED_PATH, FileAccess.WRITE)
		file.store_string(FileAccess.get_file_as_string(checkpoint_path))
		file.close()
		file = FileAccess.open(EVIDENCE_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify({"output_after_renewal": output_after_renewal,
			"paid_until": worker.payroll_paid_until_day, "wallet": int(Inventory.items.get("shekel", 0))}))
		file.close()
	await finish()

func worksite_output() -> int:
	if runtime == null or not runtime.daily.jobs.has(&"WoodSite"):
		return -1
	var job: Dictionary = runtime.daily.jobs[&"WoodSite"]
	return int(job.stats[worker.worker_id].output) if job.stats.has(worker.worker_id) else -1

func assign_woodsite() -> void:
	if stopped:
		return
	var marker: Marker2D = runtime.get_node("WorksiteMarkers/WoodSite")
	await walk(marker.global_position)
	await interact()
	_expect(runtime.inspector.visible, "The authored Wood worksite opens through E")
	if stopped:
		return
	var inspector = runtime.inspector
	await press(inspector.daily_button)
	var assignment = inspector.assignment_ui
	await press(assignment.slot_grid.get_child(0))
	var card: Button = assignment.worker_list.get_node_or_null("Participant_" + worker.worker_id)
	await press(card)
	await _capture("assignment")
	await press(assignment.next_button)
	await press(inspector.start_button)
	assignment_observed = runtime.daily.jobs.has(&"WoodSite") and runtime.daily.jobs[&"WoodSite"].ids.has(worker.worker_id)
	_expect(assignment_observed, "Daily work starts through the worksite assignment UI")
	measure("assigned")

func observe_output(previous: int, after_renewal: bool) -> void:
	var deadline: int = now() + 3 * 1440
	var arrival_in_period: bool = false
	while not stopped and now() < deadline:
		var approach: Dictionary = worker.physical_approach
		if approach.get("kind", "") == "site" and approach.get("owner", "") == "WoodSite" and approach.get("arrived", false):
			arrival_observed = true
			arrival_in_period = true
		var current: int = worksite_output()
		if arrival_in_period and current > previous:
			_expect(runtime._daily_output_count(&"WoodSite") >= current, "Worker output is present as a real WoodSite ground pickup")
			if after_renewal:
				output_after_renewal = current
			else:
				output_observed = current
			measure("output_after_renewal" if after_renewal else "first_output")
			await _capture("output-after-renewal" if after_renewal else "first-output")
			return
		await upkeep()
		await wait_minutes(10)
	_expect(false, "Physical arrival and worker output occur in the natural three-day observation window")

func renew_expired() -> void:
	if stopped:
		return
	await _press_input("open_worker_hub")
	var hub: WorkerControlUI = runtime.worker_control
	_expect(hub.visible, "K opens the actual Worker Hub")
	if stopped:
		return
	await press(hub._find_manage_button(worker.worker_id))
	_expect(hub.manage_window.visible and hub._manage_worker_id == worker.worker_id,
		"Manage opens for the hired worker through its roster button")
	if stopped:
		return
	await press(hub.manage_contract_button)
	_expect(hub.contract_window.visible and not hub.manage_window.visible,
		"Manage opens the worker's Contract popup")
	if stopped:
		return
	var selected_days: int = _select_worker_contract_days(hub, 3)
	var wallet_before: int = int(Inventory.items.get("shekel", 0))
	var cash_before: int = CityStockManager.treasury_shekel
	var price: int = WorkerDatabase.get_contract_price(worker.profession, 3)
	var signals_before: int = settlements.size()
	_expect(selected_days == 3 and hub.renew_price_label.text == "Price: %d" % price and hub.renew_price_icon.visible,
		"The three-day renewal displays the exact wallet quote")
	await _capture("worker-contract")
	await press(hub.contract_close_button)
	_expect(not hub.contract_window.visible and hub.manage_window.visible
		and int(Inventory.items.get("shekel", 0)) == wallet_before
		and CityStockManager.treasury_shekel == cash_before
		and worker.is_payroll_blocked() and settlements.size() == signals_before,
		"Closing Contract returns to Manage without spending or extending the expired contract")
	await press(hub.manage_contract_button)
	selected_days = _select_worker_contract_days(hub, 3)
	_expect(selected_days == 3 and hub.renew_price_label.text == "Price: %d" % price and hub.renew_price_icon.visible,
		"Reopening Contract retains the correct three-day renewal quote")
	await press(hub.manage_renew_button)
	renewal_observed = int(Inventory.items.get("shekel", 0)) == wallet_before - price \
		and CityStockManager.treasury_shekel == cash_before and not worker.is_payroll_blocked() \
		and worker.payroll_contract_days == 3 and worker.payroll_paid_until_day == TimeComponentManager.current_day + 3 \
		and settlements.size() == signals_before + 1
	_expect(renewal_observed, "Renew charges the wallet once and starts a new three-day period")
	var wallet_after_renew: int = int(Inventory.items.get("shekel", 0))
	var renewed_until: int = worker.payroll_paid_until_day
	_expect(hub.manage_renew_button.disabled, "A completed selection cannot be renewed a second time")
	hub.manage_renew_button.pressed.emit()
	await _frames()
	_expect(int(Inventory.items.get("shekel", 0)) == wallet_after_renew
		and worker.payroll_paid_until_day == renewed_until
		and settlements.size() == signals_before + 1,
		"Repeated stale Renew input cannot charge or extend the contract twice")
	await _capture("worker-renewed")
	await _press_input("open_worker_hub")
	_expect(not hub.visible and not get_tree().paused, "Closing Worker Hub returns to the live world")
	measure("renewed")

func _select_worker_contract_days(hub: WorkerControlUI, days: int) -> int:
	for button: Button in hub.contract_day_buttons:
		var button_days: int = int(button.get_meta("contract_days", -1))
		if button_days != days:
			continue
		button.pressed.emit()
		return hub._selected_contract_days if button.button_pressed else -1
	return -1

func hire() -> void:
	while not stopped:
		await upkeep()
		# Leave walking margin before closing; do not change the world clock.
		if TimeComponentManager.current_hour >= 8 and TimeComponentManager.current_hour < 16:
			break
		await wait_minutes(30)
	var board = content.get_node("YSortWorld/InitialWorksites/JobBoard")
	await walk(board.get_node("InteractableComponent").global_position + Vector2(0, 8))
	await interact(board)
	if stopped:
		return
	var panel: JobBoardUI = board.job_board_ui
	_expect(is_instance_valid(panel), "Job Board open during its normal hours")
	if not is_instance_valid(panel):
		return
	var before: int = Inventory.items.get("shekel", 0)
	var hired_day: int = TimeComponentManager.current_day
	await _capture("job-board")
	for index: int in range(panel.applicants.size()):
		if panel.applicants[index].citizen_id == "initial_workshop_laborer":
			panel.applicant_list.select(index)
			panel.applicant_list.item_selected.emit(index)
			await press(panel.hire_button)
			_expect(panel.confirmation_open and Inventory.items.get("shekel", 0) == before, "Opening contract choices does not spend earned funds")
			await press(panel.cancel_hire_button)
			_expect(not panel.confirmation_open and Inventory.items.get("shekel", 0) == before
				and WorkerDatabase.get_worker_data("initial_workshop_laborer") == null, "Back cancels hire without a charge or worker")
			await press(panel.hire_button)
			await press(panel.confirm_hire_button)
			break
	worker = WorkerDatabase.get_worker_data("initial_workshop_laborer")
	_expect(worker != null and not worker.is_payroll_blocked(), "Normal hire can work immediately")
	_expect(worker.payroll_paid_from_day == hired_day and worker.payroll_paid_until_day == hired_day + 3, "Hire covers remaining today plus three full days")
	wallet_paid = before - int(Inventory.items.get("shekel", 0))
	_expect(Inventory.items.get("shekel", 0) == before - 1 and CityStockManager.treasury_shekel == 0, "Hiring takes exactly one earned wallet Shekel")
	await press(panel.close_button)
	measure("immediate_hire")

func measure(stage: String) -> void:
	super.measure(stage)
	var row: Dictionary = measurements.back()
	row["city_cash"] = CityStockManager.treasury_shekel
	row["wallet_paid"] = wallet_paid
	if worker != null:
		row["payroll_start"] = worker.payroll_start_day
		row["paid_from"] = worker.payroll_paid_from_day
		row["paid_until"] = worker.payroll_paid_until_day
		row["period_rate"] = worker.payroll_period_rate

func verify_continue() -> void:
	var expected = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED_PATH))
	var evidence = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE_PATH))
	_expect(expected is Dictionary and evidence is Dictionary, "A completed write phase supplied the checkpoint and flow evidence")
	if stopped:
		return
	_expect(same(expected, restored_snapshot), "Separate-process Continue restores every earned owner exactly")
	_expect(worker != null and worker.payroll_period_rate == 1 and not worker.is_payroll_blocked()
		and worker.payroll_paid_until_day == int(evidence.paid_until)
		and int(Inventory.items.get("shekel", 0)) == int(evidence.wallet), "Continue preserves the renewed contract and wallet")
	measure("continued")
	await leave_home()
	_expect(worksite_output() >= int(evidence.output_after_renewal), "Continue restores the standing worksite assignment and its output")
	await walk(runtime.get_node("WorksiteMarkers/WoodSite").global_position)
	await _capture("continued-city")
	await _press_input("open_worker_hub")
	_expect(runtime.worker_control.visible, "Worker Hub remains available after Continue")
	await _capture("continued-worker-hub")
	await _press_input("open_worker_hub")
	await upkeep()
	measure("continued_city")
	await finish()

func finish() -> void:
	release_input()
	var complete: bool = phase == "read" or (earned > 0 and wallet_paid == 1 and first_payment_observed
		and assignment_observed and arrival_observed and output_observed > 0 and expired_observed
		and renewal_observed and output_after_renewal > output_observed and FileAccess.file_exists(checkpoint_path)
		and FileAccess.file_exists(EVIDENCE_PATH))
	var status: String = "FAIL" if failures > 0 else ("PASS" if complete else "PARTIAL")
	var result: Dictionary = {"phase": phase, "status": status, "failures": failures,
		"visits": visits, "measurements": measurements, "normal_income": earned,
		"wallet_paid": wallet_paid, "first_payment_observed": first_payment_observed,
		"assignment_observed": assignment_observed, "arrival_observed": arrival_observed,
		"output_observed": output_observed, "expired_observed": expired_observed,
		"renewal_observed": renewal_observed, "output_after_renewal": output_after_renewal,
		"settlements": settlements}
	DirAccess.make_dir_recursive_absolute("user://contract_journey")
	var file := FileAccess.open("user://contract_journey/" + phase + "-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("ContractJourney ", phase, ": ", status)
	get_tree().paused = false
	var scene: Node = get_tree().current_scene
	get_tree().current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
	await _frames()
	get_tree().quit(1 if failures > 0 else (0 if complete else 2))

func _observe_payroll() -> void:
	var employee: WorkerData = WorkerDatabase.get_worker_data("initial_workshop_laborer")
	if employee != null and employee.payroll_paid_from_day >= 0:
		settlements.append({"minute": now(), "from_day": employee.payroll_paid_from_day,
			"until_day": employee.payroll_paid_until_day, "amount": employee.payroll_period_rate,
			"city_cash": CityStockManager.treasury_shekel})

func _capture(label: String) -> void:
	await _frames()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("user://contract_journey")
		_expect(get_viewport().get_texture().get_image().save_png("user://contract_journey/" + label + ".png") == OK, "Save " + label)
