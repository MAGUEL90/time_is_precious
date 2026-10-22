extends "res://scenes/test_scenes/mvp_first_playthrough.gd"
## Normal continuation of an earned paid-production checkpoint, no fixture grants.
## Copy the prior journey's actual checkpoint into this isolated test's path first.
const SAVE_PATH: String = "user://renewal_journey/checkpoint.json"
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
var initial_document: Dictionary
var initial_paid_until: int = -1
var renewals: Array[Dictionary] = []

func _run() -> void:
	checkpoint_path = SAVE_PATH
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--renewal-phase="):
			phase = arg.trim_prefix("--renewal-phase=")
	_expect(phase in ["write", "fund", "read"], "Known normal renewal phase")
	_expect(FileAccess.file_exists(SAVE_PATH), "Seed with actual earned production checkpoint, never fixture resources")
	initial_document = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
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
	var expected: Dictionary = initial_document.duplicate(true)
	if expected.schema_version == 5:
		var values = VALUES.new()
		var raw: Dictionary = values.decode(expected.state)
		for p: Dictionary in raw.plots.values():
			p["payroll_work_remainder"] = 0
		expected.state = values.encode(raw)
		expected.schema_version = 6
	_expect(same(expected, restored_snapshot), "Continue restores complete earned state, including explicit v5 migration")
	_expect(worker != null and worker.payroll_paid_from_day >= 0, "Earned worker already has a paid first period")
	if stopped:
		return
	initial_paid_until = worker.payroll_paid_until_day
	WorkerDatabase.payroll_changed.connect(_observe_renewal)
	measure("continued_" + phase)
	await leave_home()
	if phase == "write":
		_expect(CityStockManager.treasury_shekel == 0, "Prior journey has no remaining city payroll cash")
		while not worker.is_payroll_blocked() and not stopped:
			await upkeep()
			await wait_minutes(30)
		_expect(worker.payroll_paid_until_day == initial_paid_until and CityStockManager.treasury_shekel == 0, "Unfunded renewal leaves paid history and city funds unchanged")
		_expect(not WorkerDatabase.assign_worker(worker.worker_id), "Expired normal worker cannot accept new work")
		measure("unfunded_renewal")
		await _bed_checkpoint()
	elif phase == "fund":
		_expect(worker.is_payroll_blocked(), "Paused normal worker survives separate-process Continue")
		while TimeComponentManager.current_hour < 8 or TimeComponentManager.current_hour >= 16:
			await upkeep()
			await wait_minutes(30)
		var board = content.get_node("YSortWorld/InitialWorksites/JobBoard")
		await walk(board.get_node("InteractableComponent").global_position + Vector2(0, 8))
		await interact(board)
		var panel: JobBoardUI = board.job_board_ui
		var wallet: int = Inventory.items.get("shekel", 0)
		panel.deposit_amount.value = 1
		await press(panel.deposit_button)
		await press(panel.close_button)
		_expect(Inventory.items.get("shekel", 0) == wallet - 1 and CityStockManager.treasury_shekel == 1 and worker.is_payroll_blocked(), "Earned-wallet deposit does not resume midday")
		measure("deposited_waiting")
		while worker.is_payroll_blocked() and not stopped:
			await upkeep()
			await wait_minutes(30)
		_expect(worker.payroll_paid_until_day == worker.payroll_paid_from_day + 6 and CityStockManager.treasury_shekel == 0, "Next morning purchases seven full days without arrears")
		_expect(renewals.size() == 1 and renewals[0].minute == worker.payroll_paid_from_day * 1440 + 480, "One normal renewal occurs exactly at08")
		measure("renewed")
		await _bed_checkpoint()
	else:
		_expect(not worker.is_payroll_blocked(), "Renewed worker remains paid after Continue")
		await upkeep()
		measure("renewed_continue_city")
	await finish()

func _bed_checkpoint() -> void:
	while not player.can_sleep() and not stopped:
		await upkeep()
		await wait_minutes(30)
	await sleep_home()
	_expect(FileAccess.file_exists(SAVE_PATH), "Normal home bed saves the renewal journey")

func measure(stage: String) -> void:
	super.measure(stage)
	var row: Dictionary = measurements.back()
	row["city_cash"] = CityStockManager.treasury_shekel
	if worker != null:
		row["paid_from"] = worker.payroll_paid_from_day
		row["paid_until"] = worker.payroll_paid_until_day
		row["last_attempt"] = worker.payroll_last_attempt_day
		row["payroll_blocked"] = worker.is_payroll_blocked()

func _observe_renewal() -> void:
	if worker != null and worker.payroll_paid_until_day > initial_paid_until:
		renewals.append({"minute": now(), "from": worker.payroll_paid_from_day, "until": worker.payroll_paid_until_day})

func finish() -> void:
	release_input()
	var result := {"phase": phase, "status": "PASS" if failures == 0 else "FAIL", "failures": failures,
		"measurements": measurements, "renewals": renewals}
	var file := FileAccess.open("user://renewal_journey/" + phase + "-result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("NormalRenewalJourney ", phase, ": ", result.status)
	get_tree().paused = false
	var current: Node = get_tree().current_scene
	get_tree().current_scene = null
	if is_instance_valid(current):
		current.queue_free()
	await _frames()
	get_tree().quit(0 if failures == 0 else 1)
