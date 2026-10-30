extends "res://scenes/test_scenes/mvp_first_playthrough.gd"
## Normal income, authored applicants, approved temporary rates, live needs.
## Actual income and physical UI; no grants, clock edits, RNG overrides or disabled needs.
var settlements: Array[Dictionary] = []
var wallet_paid: int = 0
var payroll_day: int = -1
var first_payment_observed: bool = false
var assignment_observed: bool = false
const EXPECTED_PATH: String = "user://contract_journey/expected.json"

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
	await construct()
	assignment_observed = plot.construction.phase == "clearing"
	_expect(assignment_observed, "Immediately paid worker starts normal clearing through workshop UI")
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
	_expect(same(expected, restored_snapshot), "Separate-process Continue restores every earned owner exactly")
	_expect(worker != null and worker.payroll_period_rate == 1 and not worker.is_waiting_for_first_payment(), "Continue preserves the first paid period")
	measure("continued")
	await leave_home()
	await upkeep()
	measure("continued_city")
	await finish()

func finish() -> void:
	release_input()
	var complete: bool = phase == "read" or (earned > 0 and wallet_paid == 1 and first_payment_observed and assignment_observed and FileAccess.file_exists(checkpoint_path))
	var status: String = "FAIL" if failures > 0 else ("PASS" if complete else "PARTIAL")
	var result: Dictionary = {"phase": phase, "status": status, "failures": failures,
		"visits": visits, "measurements": measurements, "normal_income": earned,
		"wallet_paid": wallet_paid, "first_payment_observed": first_payment_observed,
		"assignment_observed": assignment_observed, "settlements": settlements}
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
