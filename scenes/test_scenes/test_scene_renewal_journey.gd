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
	# Old earned checkpoints can retain a transient idle workshop selector status.
	var people_values = VALUES.new()
	var expected_raw: Dictionary = people_values.decode(expected.state)
	var prior_worker: WorkerData = expected_raw.workers.workers_by_id.get("initial_workshop_laborer")
	if prior_worker != null and not prior_worker.is_reserved() and prior_worker.current_work_status == WorkerData.WorkStatus.IDLE:
		var prior_citizen: CitizenData = expected_raw.citizens.citizens_by_id.get(prior_worker.worker_id)
		if prior_citizen != null and prior_citizen.employment_status == CitizenData.EmploymentStatus.ASSIGNED:
			prior_citizen.employment_status = CitizenData.EmploymentStatus.HIRED
		expected.state = people_values.encode(expected_raw)
	_expect(same(expected, restored_snapshot), "Continue restores complete earned state with explicit v5 and idle-selector repair")
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
		var wallet: int = Inventory.items.get("shekel", 0)
		var cash_deposited: int = await deposit_city_cash(1)
		_expect(cash_deposited == 1, "Fund renewal by depositing one earned Shekel at physical City Storage")
		if stopped:
			return
		while TimeComponentManager.current_hour < 8 or TimeComponentManager.current_hour >= 16:
			await upkeep()
			await wait_minutes(30)
		var board = content.get_node("YSortWorld/InitialWorksites/JobBoard")
		await walk(board.get_node("InteractableComponent").global_position + Vector2(0, 8))
		await interact(board)
		var panel: JobBoardUI = board.job_board_ui
		_expect(Inventory.items.get("shekel", 0) == wallet - 1 and CityStockManager.treasury_shekel == 1 and worker.is_payroll_blocked(), "Earned-wallet deposit does not resume midday")
		await press(panel.close_button)
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
	_expect(area.has_player_access(), "Reach physical City Storage before funding renewal")
	await interact(area)
	if stopped:
		return 0
	var menu = area.menu
	_expect(is_instance_valid(menu), "Physical City Storage menu opens for renewal funding")
	if not is_instance_valid(menu):
		return 0
	await press(menu.deposit_button)
	var transfer: ItemTransferUI = menu.transfer_ui
	_expect(is_instance_valid(transfer), "City Storage opens ItemTransferUI for renewal funding")
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
