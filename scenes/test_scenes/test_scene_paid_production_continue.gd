extends Node

## Test-owned startup resources and construction; New Game, payroll, production,
## checkpointing, and Continue all use their normal owners and callbacks. Fixture
## assumptions: clear weather is explicitly granted, construction time is jumped
## to its completion boundary, and seed(42) fixes the production success roll.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const JOB: JobData = preload("res://resources/job_data/mudbrick_make.tres")
const CHECKPOINT_PATH: String = "user://paid_production_continue/checkpoint.json"
const LABORER_ID: String = "initial_workshop_laborer"
const DRYING_PROCESS_ID: String = "drying_mudbrick"

var failures: int = 0
var phase: String = "write"
var launched: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--production-phase="):
			phase = argument.trim_prefix("--production-phase=")
	_check(phase in ["write", "continue-shape", "continue-dry"], "Known --production-phase is required.")
	if failures > 0:
		_finish()
		return

	get_tree().current_scene = null
	TimeComponentManager.set_process(false)
	if phase == "write":
		_check(not _checkpoint_exists(),
			"The write phase requires a fresh isolated user data directory; it never deletes checkpoints.")
		if failures > 0:
			_finish()
			return
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = CHECKPOINT_PATH
	menu.session_started.connect(_on_session_started)
	get_tree().root.add_child(menu)
	if phase == "write":
		menu._request_new_game()
	else:
		menu.continue_button.pressed.emit()

	for _frame: int in range(600):
		if launched:
			break
		await get_tree().process_frame
	_check(launched, "The real start menu must finish %s." % phase)
	if not launched:
		_finish()
		return

	get_tree().paused = false
	TimeComponentManager.is_paused = false
	TimeComponentManager.set_process(false)
	var city: Node = get_tree().current_scene
	var player: Player = city.get_node("YSortWorld/Player")
	_check(not player.debug_disable_player_needs and not player.debug_disable_fatigue,
		"The fixture leaves player needs and fatigue active.")
	var store: Node = WorkStateRuntime.get_node("CitySave")
	_check(store.disk.path == CHECKPOINT_PATH, "The real city save owner uses the isolated fixture checkpoint.")

	if phase == "write":
		await _write_paid_work_checkpoint(city, player, store)
	elif phase == "continue-shape":
		await _continue_shape_and_write_drying(city, player, store)
	else:
		_continue_drying_and_check(city, player, store)
	_finish()


func _on_session_started(_continued: bool) -> void:
	launched = true


func _write_paid_work_checkpoint(city: Node, player: Player, store: Node) -> void:
	_check(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(),
		"Real New Game begins without fixture items or hired workers.")
	var plot: Node = city.get_node("YSortWorld/WorkshopPlot")
	var construction: Node = plot.construction
	_check(construction.phase == "uncleared", "The authored main Workshop Plot begins unbuilt.")
	var applicant: CitizenData = CitizenManager.get_citizen(LABORER_ID)
	_check(applicant != null
		and applicant.employment_status == CitizenData.EmploymentStatus.APPLICANT,
		"New Game provides its authored Laborer as an applicant.")
	_check(WorkerDatabase.get_onboarding_rate(WorkerData.Profession.LABORER) == 1,
		"The authored Laborer uses the approved one-shekel onboarding rate.")

	# Move the fixture clock to the real Job Board hiring window, then hire through
	# the authored applicant API. The next morning is crossed with one real minute.
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 16
	TimeComponentManager.current_minute = 59
	TimeComponentManager.current_weather = "clear"
	TimeComponentManager._timer = 0.0
	TimeComponentManager.emit_time_signal()
	var worker: WorkerData = WorkerDatabase.hire_applicant(LABORER_ID, 1)
	_check(worker != null and worker.is_waiting_for_first_payment(),
		"The authored hire remains pending before the first paid period.")
	if worker == null:
		return

	# Test-only grants cover the authored Workshop construction and one recipe.
	# Raw recipe inputs enter Workshop Storage; the fee wallet and payroll treasury
	# are separate balances by design.
	Inventory.add_item("shekel", 8)
	Inventory.add_item("wood_log", 6)
	Inventory.add_item("clay_lump", 15)
	Inventory.add_item("reed_bundle", 8)
	WorkShopStorage.add_bulk_item({"clay_lump": 3, "straw_bundle": 3, "water_jar": 3})
	_check(is_equal_approx(WorkShopStorage.max_load, 50.0),
		"The unbuilt map has its normal 50-unit Workshop Storage capacity.")
	var recipe_inputs: Dictionary = WorkShopStorage.items.duplicate(true)
	_check(not WorkerDatabase.assign_worker(LABORER_ID),
		"A pending hire is rejected by the real worker assignment API.")
	var rejected_order: String = WorkManager.start_job(
		JOB, WorkOrder.Worker_Type.NPC, LABORER_ID, null,
		WorkShopStorage, WorkShopStorage, JOB.workshop_fee_amount, 2
	)
	_check(rejected_order.is_empty() and WorkShopStorage.items == recipe_inputs,
		"Pending production is rejected before consuming Workshop inputs.")

	_check(CityStockManager.treasury_shekel == 0
		and CityStockManager.deposit_wallet_shekel(1),
		"The fixture deposits one of its eight wallet shekels into the city payroll treasury through the real deposit API.")
	TimeComponentManager.current_day = worker.payroll_start_day
	TimeComponentManager.current_hour = 7
	TimeComponentManager.current_minute = 59
	TimeComponentManager._timer = 0.0
	TimeComponentManager.emit_time_signal()
	TimeComponentManager.advance_minutes(1)
	_check(TimeComponentManager.current_hour == 8 and TimeComponentManager.current_minute == 0,
		"The fixture crosses exactly one elapsed 08:00 boundary.")
	_check(not worker.is_waiting_for_first_payment()
		and worker.payroll_paid_from_day == TimeComponentManager.current_day
		and worker.payroll_paid_until_day == worker.payroll_paid_from_day + 6
		and worker.payroll_period_rate == 1,
		"The real callback prepays one seven-day Laborer period at rate one.")
	_check(CityStockManager.treasury_shekel == 0 and Inventory.items.get("shekel", 0) == 7,
		"Payroll spends the one city shekel and leaves the player's fee wallet untouched.")

	# The map construction is real and uses the authored plot APIs. Three days of
	# build time are a fixture time grant; the player/citizen needs stay enabled.
	var worker_ids: Array[String] = [LABORER_ID]
	_check(construction.start_clearing(worker_ids, false).get("success", false),
		"The paid Laborer starts clearing the authored Workshop site.")
	TimeComponentManager.advance_minutes(construction.CLEARING_MINUTES)
	_check(construction.phase == "empty", "The authored site clears through elapsed time.")
	var build_result: Dictionary = construction.start_build(worker_ids)
	_check(bool(build_result.get("success", false)),
		"The paid Laborer starts the authored Workshop build.")
	if not bool(build_result.get("success", false)):
		return
	var build_complete: int = int(construction.completes_at)
	TimeComponentManager.current_day = floori(float(build_complete) / 1440.0)
	var minute_of_day: int = build_complete % 1440
	TimeComponentManager.current_hour = minute_of_day / 60
	TimeComponentManager.current_minute = minute_of_day % 60
	TimeComponentManager._timer = 0.0
	TimeComponentManager.emit_time_signal()
	_check(construction.phase == "built" and plot.has_node("BuiltWorkshop"),
		"Fixture time completes the authored construction and creates its real Workshop.")
	var workshop: WorkShop = plot.get_node_or_null("BuiltWorkshop") as WorkShop
	_check(workshop != null and is_equal_approx(WorkShopStorage.max_load, 200.0),
		"Built Workshop sets its normal 200-unit storage capacity.")
	if workshop == null:
		return

	_check(workshop.assign_workers(worker_ids),
		"The paid Laborer can be assigned by the built Workshop.")
	_check(workshop.start_job_from_storage(JOB, worker_ids),
		"Built Workshop starts Shape through its production API.")
	_check(WorkShopStorage.items.is_empty(),
		"Shape consumes its three recipe inputs from Workshop Storage exactly once.")
	_check(WorkerDatabase.get_worker_data(LABORER_ID).is_working()
		and WorkManager.active_orders.size() == 1,
		"The hired Laborer owns the actual running Shape WorkOrder.")
	TimeComponentManager.advance_minutes(JOB.base_duration_minutes / 2)
	var progress_entries: Array[Dictionary] = WorkManager.get_active_progress_entries()
	_check(progress_entries.size() == 1
		and is_equal_approx(float(progress_entries[0].get("progress_ratio", 0.0)), 0.5),
		"The paid Shape order reaches a real mid-work checkpoint.")
	_check(store.save_checkpoint(), "Save the mid-Shape checkpoint: " + store.last_error)


func _continue_shape_and_write_drying(city: Node, player: Player, store: Node) -> void:
	if not _assert_exact_continue(city, store, "mid-Shape"):
		return
	var worker: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	var player_still_active: bool = not player.debug_disable_player_needs and not player.debug_disable_fatigue
	_check(player_still_active and worker != null and worker.is_working()
		and worker.payroll_period_rate == 1 and not worker.is_waiting_for_first_payment(),
		"Continue preserves active needs, paid Laborer state, and the running job.")
	_check(city.get_node("YSortWorld/WorkshopPlot").construction.phase == "built"
		and city.get_node("YSortWorld/WorkshopPlot").has_node("BuiltWorkshop")
		and is_equal_approx(WorkShopStorage.max_load, 200.0),
		"Continue restores the built Workshop and its authored capacity.")
	if worker == null:
		return
	var order: WorkOrder = WorkManager.active_orders.values()[0] as WorkOrder
	_check(order.worker_id == LABORER_ID and order.job_id == JOB.job_id,
		"The continued WorkOrder still belongs to the authored Laborer and Shape recipe.")
	# Keep the existing worker success rule while fixing only the fixture RNG roll.
	seed(42)
	TimeComponentManager.advance_minutes(maxi(order.end_time_total_minutes - _now(), 1))
	_check(WorkManager.active_orders.is_empty() and not worker.is_working(),
		"The continued Shape WorkOrder completes and releases the worker.")
	_check(WorkShopStorage.output_lots.size() == 1
		and WorkShopStorage.output_lots[0].items.get("wet_mudbrick", 0) == 20,
		"Shape creates one held lot of twenty wet mudbricks.")
	var shape_fee: Dictionary = _find_fee("job", JOB.job_id)
	_check(not shape_fee.is_empty()
		and int(shape_fee.get("service_fee_shekel", 0)) == 5
		and not bool(shape_fee.get("is_paid", true)),
		"The held Shape lot owns its one unpaid five-shekel job fee.")
	if shape_fee.is_empty() or WorkShopStorage.output_lots.is_empty():
		return
	_check(WorkShopStorage.output_lots[0].fee_ids.has(str(shape_fee.get("fee_id", ""))),
		"The held Shape lot is linked to that single job fee.")

	var lot_id: String = str(WorkShopStorage.output_lots[0].get("lot_id", ""))
	var paid: Dictionary = WorkShopStorage.pay_output_lot(lot_id, Inventory)
	_check(bool(paid.get("success", false))
		and WorkShopStorage.get_free_item_quantity("wet_mudbrick") == 20,
		"Paying the Shape claim releases its wet bricks into Workshop Free Stock.")
	_check(Inventory.items.get("shekel", 0) == 2 and CityStockManager.treasury_shekel == 0,
		"The five-shekel Shape fee comes from the player wallet, not city treasury.")
	shape_fee = _find_fee("job", JOB.job_id)
	_check(bool(shape_fee.get("is_paid", false)), "The Shape job fee records payment once.")

	# The built Drying Yard uses its real material and facility upgrade API.
	WorkShopStorage.add_bulk_item({"wood_log": 2, "reed_bundle": 4, "clay_lump": 4})
	var upgrade: Dictionary = WorkshopFacilityManager.upgrade_facility("drying_yard", WorkShopStorage)
	_check(bool(upgrade.get("success", false))
		and WorkshopFacilityManager.get_facility_level("drying_yard") == 1,
		"Fixture materials build one real Drying Yard station.")
	_check(ProcessManager.start_registered_process(DRYING_PROCESS_ID, 20),
		"The real ProcessManager starts one full twenty-brick Drying batch.")
	var station: StationState = ProcessManager.stations.get("drying_yard") as StationState
	var batch: ProcessBatch = station.slots[0] as ProcessBatch if station != null else null
	_check(batch != null and batch.process_id == DRYING_PROCESS_ID
		and batch.quantity == 20 and batch.progress_minutes == 0,
		"Drying starts one registered ProcessBatch after consuming the free wet bricks.")
	var dry_fee: Dictionary = _find_fee("process", DRYING_PROCESS_ID)
	_check(not dry_fee.is_empty() and int(dry_fee.get("service_fee_shekel", 0)) == 2
		and not bool(dry_fee.get("is_paid", true)),
		"The running Drying batch owns one unpaid two-shekel facility fee.")
	if batch == null:
		return
	var half_duration: int = maxi(batch.duration_minutes / 2, 1)
	TimeComponentManager.advance_minutes(half_duration)
	_check(batch.progress_minutes == half_duration and WorkShopStorage.output_lots.is_empty(),
		"Drying is checkpointed mid-work before any output lot exists.")
	_check(store.save_checkpoint(), "Save the mid-Drying Continue checkpoint: " + store.last_error)


func _continue_drying_and_check(city: Node, player: Player, store: Node) -> void:
	if not _assert_exact_continue(city, store, "mid-Drying"):
		return
	_check(not player.debug_disable_player_needs and not player.debug_disable_fatigue,
		"The second Continue keeps player needs active.")
	var worker: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	_check(worker != null and worker.payroll_period_rate == 1
		and worker.payroll_paid_until_day == worker.payroll_paid_from_day + 6
		and CityStockManager.treasury_shekel == 0,
		"The saved Laborer remains paid for exactly one seven-day period.")
	var plot: Node = city.get_node("YSortWorld/WorkshopPlot")
	_check(plot.construction.phase == "built" and plot.has_node("BuiltWorkshop")
		and is_equal_approx(WorkShopStorage.max_load, 200.0),
		"The second Continue recreates the real built Workshop at its saved capacity.")
	var station: StationState = ProcessManager.stations.get("drying_yard") as StationState
	var batch: ProcessBatch = station.slots[0] as ProcessBatch if station != null else null
	_check(batch != null and batch.status == ProcessBatch.BatchStatus.RUNNING
		and batch.quantity == 20 and batch.progress_minutes > 0,
		"Continue restores the exact running Drying batch mid-work.")
	var before_count: int = WorkShopStorage.unpaid_claims_ledger.size()
	if batch == null:
		return
	TimeComponentManager.advance_minutes(maxi(batch.duration_minutes - batch.progress_minutes, 1))
	_check(station.slots[0] == null and WorkShopStorage.output_lots.size() == 1
		and WorkShopStorage.items.get("sun_dried_mudbrick", 0) == 20,
		"The continued batch completes into one held lot of twenty sun-dried bricks.")
	TimeComponentManager.advance_minutes(batch.duration_minutes + 1)
	_check(WorkShopStorage.output_lots.size() == 1
		and WorkShopStorage.items.get("sun_dried_mudbrick", 0) == 20
		and WorkShopStorage.unpaid_claims_ledger.size() == before_count,
		"Further time after Continue cannot duplicate production or fee entries.")
	_check(WorkShopStorage.get_held_item_quantity("sun_dried_mudbrick") == 20
		and WorkShopStorage.get_free_item_quantity("sun_dried_mudbrick") == 0,
		"The completed Drying output remains held behind its unpaid facility fee.")
	var shape_fee: Dictionary = _find_fee("job", JOB.job_id)
	var dry_fee: Dictionary = _find_fee("process", DRYING_PROCESS_ID)
	_check(WorkShopStorage.unpaid_claims_ledger.size() == 2
		and int(shape_fee.get("service_fee_shekel", 0)) == 5
		and bool(shape_fee.get("is_paid", false))
		and int(dry_fee.get("service_fee_shekel", 0)) == 2
		and not bool(dry_fee.get("is_paid", true)),
		"Continue retains one paid Shape fee of five and one unpaid Drying fee of two.")
	_check(WorkShopStorage.output_lots[0].get("source_type", "") == "process"
		and WorkShopStorage.output_lots[0].get("source_id", "") == DRYING_PROCESS_ID
		and WorkShopStorage.output_lots[0].fee_ids.has(str(dry_fee.get("fee_id", ""))),
		"The held sun-dried output links to its single Drying facility fee.")
	_check(Inventory.items.get("shekel", 0) == 2 and CityStockManager.treasury_shekel == 0,
		"Drying fee remains in the player wallet and does not touch city treasury.")


func _assert_exact_continue(city: Node, store: Node, label: String) -> bool:
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	_check(disk is Dictionary, "%s checkpoint is readable." % label)
	if not disk is Dictionary:
		return false
	var current: Dictionary = store.snapshot.capture(city)
	var exact_restore: bool = not current.is_empty() and _canonical(current) == _canonical(disk)
	_check(exact_restore,
		"Separate-process Continue restores the exact %s checkpoint." % label)
	return exact_restore


func _find_fee(source_type: String, source_id: String) -> Dictionary:
	for entry: Dictionary in WorkShopStorage.unpaid_claims_ledger:
		if entry.get("fee_source_type", "") == source_type and entry.get("fee_source_id", "") == source_id:
			return entry
	return {}


func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute


func _canonical(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))


func _checkpoint_exists() -> bool:
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		if FileAccess.file_exists(CHECKPOINT_PATH + suffix):
			return true
	return false


func _finish() -> void:
	print("PaidProductionContinue %s: %s" % [phase, "PASS" if failures == 0 else "FAIL (%d checks)" % failures])
	var current: Node = get_tree().current_scene
	if is_instance_valid(current):
		current.queue_free()
		await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
