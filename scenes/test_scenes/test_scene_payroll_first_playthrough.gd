extends "res://scenes/test_scenes/mvp_first_playthrough.gd"
## Normal income, authored applicants, approved temporary rates, live needs.
## Reuses the walking/food/merchant driver, never its old immediate-hire route.
var settlements: Array[Dictionary] = []
var deposited: int = 0
var payroll_day: int = -1
var first_payment_observed: bool = false
var assignment_observed: bool = false
const EXPECTED_PATH: String = "user://payroll_first_playthrough/expected.json"

func _run() -> void:
	checkpoint_path = "user://payroll_first_playthrough/checkpoint.json"
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
	while not stopped and worker != null and worker.is_waiting_for_first_payment() and TimeComponentManager.current_day < 18:
		await upkeep()
		if worker.is_waiting_for_first_payment():
			await wait_minutes(30)
	if stopped or worker == null or worker.is_waiting_for_first_payment():
		await finish()
		return
	payroll_day = worker.payroll_paid_from_day
	first_payment_observed = worker.payroll_period_rate == 1 and worker.payroll_paid_until_day == payroll_day + 6
	_expect(first_payment_observed and CityStockManager.treasury_shekel == 0, "First payment consumes exactly the explicit one-shekel deposit")
	_expect(settlements.size() == 1 and settlements[0].minute == payroll_day * 1440 + 480, "Normal first payment occurs at exactly 08:00")
	measure("first_payment")
	await construct()
	assignment_observed = plot.construction.phase == "clearing"
	_expect(assignment_observed, "Paid worker starts normal clearing through workshop UI")
	while not stopped and plot.construction.phase == "clearing":
		await upkeep()
		await wait_minutes(15)
	measure("cleared")
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
	await finish()

func hire() -> void:
	while not stopped:
		await upkeep()
		# Leave walking margin before closing; do not change the world clock.
		if TimeComponentManager.current_hour >= 8 and TimeComponentManager.current_hour < 16:
			break
		await wait_minutes(30)
	var before: int = Inventory.items.get("shekel", 0)
	deposited = await deposit_city_cash(1)
	_expect(deposited == 1 and CityStockManager.treasury_shekel == 1, "Physical City Storage deposits earned money explicitly")
	if stopped:
		return
	var board = content.get_node("YSortWorld/InitialWorksites/JobBoard")
	await walk(board.get_node("InteractableComponent").global_position + Vector2(0, 8))
	await interact(board)
	if stopped:
		return
	var panel: JobBoardUI = board.job_board_ui
	_expect(is_instance_valid(panel), "Job Board open during its normal hours")
	if not is_instance_valid(panel):
		return
	for index: int in range(panel.applicants.size()):
		if panel.applicants[index].citizen_id == "initial_workshop_laborer":
			panel.applicant_list.select(index)
			panel.applicant_list.item_selected.emit(index)
			await press(panel.hire_button)
			break
	worker = WorkerDatabase.get_worker_data("initial_workshop_laborer")
	_expect(worker != null and worker.is_waiting_for_first_payment(), "Normal hire remains pending")
	_expect(Inventory.items.get("shekel", 0) == before - 1 and CityStockManager.treasury_shekel == 1, "Hiring takes no immediate payment")
	await press(panel.close_button)
	measure("pending_hire")

func deposit_city_cash(amount: int) -> int:
	if amount <= 0:
		_expect(false, "Physical City Storage deposit amount must be positive")
		return 0
	var area: Area2D = runtime.get_node("CityStorageArea")
	var inventory_before: int = Inventory.items.get("shekel", 0)
	var treasury_before: int = CityStockManager.treasury_shekel
	await walk(area.global_position + Vector2(0, 8))
	if stopped:
		return 0
	_expect(area.has_player_access(), "Reach physical City Storage before depositing cash")
	await interact(area)
	if stopped:
		return 0
	var menu = area.menu
	_expect(is_instance_valid(menu), "Physical City Storage menu opens for cash deposit")
	if not is_instance_valid(menu):
		return 0
	await press(menu.deposit_button)
	var transfer: ItemTransferUI = menu.transfer_ui
	_expect(is_instance_valid(transfer), "City Storage opens ItemTransferUI for cash deposit")
	if not is_instance_valid(transfer):
		return 0
	var shekel_slot: ItemSlot
	for child: Node in transfer.grid_container.get_children():
		var slot: ItemSlot = child as ItemSlot
		if is_instance_valid(slot) and slot._item_id == "shekel":
			shekel_slot = slot
			break
	_expect(is_instance_valid(shekel_slot) and shekel_slot._quantity >= amount,
		"City Storage transfer exposes the requested earned Shekel quantity")
	if not is_instance_valid(shekel_slot) or shekel_slot._quantity < amount:
		return 0
	for index: int in range(amount):
		shekel_slot.pressed.emit()
	_expect(int(transfer.selected_items.get("shekel", 0)) == amount,
		"ItemTransferUI stages the exact requested Shekel quantity")
	await press(transfer.confirm_button)
	_expect(Inventory.items.get("shekel", 0) == inventory_before - amount
		and CityStockManager.treasury_shekel == treasury_before + amount,
		"Confirming physical City Storage cash transfers wallet Shekel to treasury")
	var close_button: BaseButton = menu.view.get_node("Close") as BaseButton
	await press(close_button)
	_expect(not is_instance_valid(area.menu) and not get_tree().paused,
		"Close City Storage before approaching the Job Board")
	return inventory_before - int(Inventory.items.get("shekel", 0))

func measure(stage: String) -> void:
	super.measure(stage)
	var row: Dictionary = measurements.back()
	row["city_cash"] = CityStockManager.treasury_shekel
	row["deposited"] = deposited
	if worker != null:
		row["payroll_start"] = worker.payroll_start_day
		row["paid_from"] = worker.payroll_paid_from_day
		row["paid_until"] = worker.payroll_paid_until_day
		row["period_rate"] = worker.payroll_period_rate

func verify_continue() -> void:
	var expected = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED_PATH))
	_expect(same(expected, restored_snapshot), "Separate-process Continue restores every earned owner exactly")
	_expect(worker != null and worker.payroll_period_rate == 1 and not worker.is_waiting_for_first_payment(), "Continue preserves the first paid period")
	measure("continued")
	await leave_home()
	await upkeep()
	measure("continued_city")
	await finish()

func finish() -> void:
	release_input()
	var complete: bool = phase == "read" or (earned > 0 and deposited == 1 and first_payment_observed and assignment_observed and FileAccess.file_exists(checkpoint_path))
	var status: String = "FAIL" if failures > 0 else ("PASS" if complete else "PARTIAL")
	var result: Dictionary = {"phase": phase, "status": status, "failures": failures,
		"visits": visits, "measurements": measurements, "normal_income": earned,
		"deposited": deposited, "first_payment_observed": first_payment_observed,
		"assignment_observed": assignment_observed, "settlements": settlements}
	DirAccess.make_dir_recursive_absolute("user://payroll_first_playthrough")
	var file := FileAccess.open("user://payroll_first_playthrough/" + phase + "-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PayrollFirstPlaythrough ", phase, ": ", status)
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
