extends Node

## Test-owned supplies; New Game, prepaid hiring, physical worker approaches,
## shifts, construction, production, checkpointing and Continue use real owners.
## The fixture drives the player's food and sleep APIs while both player and
## citizen needs remain active. This is not an unassisted player journey.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const JOB: JobData = preload("res://resources/job_data/mudbrick_make.tres")
const SHIFT_DRIVER = preload("res://scenes/test_scenes/workshop_shift_test_driver.gd")
const CHECKPOINT_PATH: String = "user://paid_production_continue/checkpoint.json"
const LABORER_ID: String = "initial_workshop_laborer"
const DRYING_PROCESS_ID: String = "drying_mudbrick"
const CONTRACT_DAYS: int = 9
const CONTRACT_PRICE: int = 3
const WALLET_GRANT: int = 12
const CITY_DEPOSIT: int = 2

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
	if applicant == null:
		return
	_check(WorkerDatabase.get_onboarding_rate(WorkerData.Profession.LABORER) == 1,
		"The authored Laborer uses the approved one-shekel onboarding rate.")

	# Start at an open Job Board and first demonstrate that an unfunded hire is
	# rejected without changing the applicant. The actual package is prepaid.
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_minute = 0
	TimeComponentManager.current_weather = "clear"
	TimeComponentManager._timer = 0.0
	TimeComponentManager.emit_time_signal()
	_check(WorkerDatabase.hire_applicant(LABORER_ID, 1, CONTRACT_DAYS) == null
		and applicant.employment_status == CitizenData.EmploymentStatus.APPLICANT,
		"An unfunded contract leaves the applicant and worker roster unchanged.")
	Inventory.add_item("shekel", WALLET_GRANT)
	_check(CityStockManager.deposit_wallet_shekel(CITY_DEPOSIT)
		and CityStockManager.treasury_shekel == CITY_DEPOSIT,
		"The fixture funds a separate city treasury sentinel through the wallet.")
	var wallet_before_hire: int = int(Inventory.items.get("shekel", 0))
	var worker: WorkerData = WorkerDatabase.hire_applicant(LABORER_ID, 1, CONTRACT_DAYS)
	_check(worker != null and wallet_before_hire - int(Inventory.items.get("shekel", 0)) == CONTRACT_PRICE,
		"Hiring debits the quoted nine-day package exactly once from the wallet.")
	if worker == null:
		return
	_check(worker.payroll_paid_from_day == 0 and worker.payroll_paid_until_day == CONTRACT_DAYS
		and worker.payroll_paid_start_minute == _now() and worker.payroll_contract_days == CONTRACT_DAYS
		and worker.payroll_period_rate == CONTRACT_PRICE and not worker.is_payroll_blocked()
		and CityStockManager.treasury_shekel == CITY_DEPOSIT,
		"The prepaid contract starts immediately and does not charge the city treasury.")

	# Explicit fixture supplies keep the real daily needs path active over the
	# longer shift-based build. Storage consumes them through its normal APIs.
	var city_storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var residents: int = CitizenManager.get_all_residents().size()
	var food_count: int = residents * 12
	var clothing_count: int = residents * 2
	Inventory.add_item("barley_bread", food_count)
	Inventory.add_item("simple_clothes", clothing_count)
	var deposit: Dictionary = city_storage.deposit_items_from_inventory({
		"barley_bread": food_count, "simple_clothes": clothing_count,
	})
	CityStockManager.add_shelter_capacity(residents)
	_check(residents > 0 and bool(deposit.get("ok", false))
		and city_storage.get_food_supply_points() == food_count
		and city_storage.get_clothing_item_count() == clothing_count,
		"The city receives registered food, clothing and shelter for daily settlement.")
	# Fixture grants cover construction and one recipe; outputs are never granted.
	Inventory.add_item("wood_log", 6)
	Inventory.add_item("clay_lump", 15)
	Inventory.add_item("reed_bundle", 8)
	WorkShopStorage.add_bulk_item({"clay_lump": 3, "straw_bundle": 3, "water_jar": 3})
	_check(is_equal_approx(WorkShopStorage.max_load, 50.0),
		"The unbuilt map has its normal 50-unit Workshop Storage capacity.")
	_check_legacy_pending_worker()
	var visuals: Node2D = city.get_node("YSortWorld/WorkerRuntime/WorkerVisuals")
	visuals.set_process(false)
	var inventory_ui: InventoryUI = city.get_node("InventoryUI") as InventoryUI
	var worker_ids: Array[String] = [LABORER_ID]
	var clearing_started: bool = bool(construction.start_clearing(worker_ids, false).get("success", false))
	_check(clearing_started,
		"The paid Laborer starts clearing the authored Workshop site.")
	if not clearing_started:
		return
	_check(not worker.physical_approach.is_empty() and not worker.physical_approach.arrived,
		"Clearing begins with the actual pending approach.")
	if not await _work_through_shifts(construction.CLEARING_MINUTES, construction, visuals, worker_ids, player, inventory_ui):
		return
	_check(construction.phase == "empty", "The authored site clears through elapsed time.")
	var inventory_before_build: Dictionary = Inventory.items.duplicate(true)
	var build_result: Dictionary = construction.start_build(worker_ids)
	_check(bool(build_result.get("success", false)),
		"The paid Laborer starts the authored Workshop build.")
	if not bool(build_result.get("success", false)):
		return
	for item_id: String in construction.REQUIREMENTS:
		_check(int(inventory_before_build.get(item_id, 0)) - int(Inventory.items.get(item_id, 0)) == int(construction.REQUIREMENTS[item_id]),
			"Construction consumes its %s requirement exactly once." % item_id)
	if not await _work_through_shifts(construction.SOLO_MINUTES, construction, visuals, worker_ids, player, inventory_ui):
		return
	_check(construction.phase == "built" and plot.has_node("BuiltWorkshop"),
		"Paid shift work completes the authored construction and creates its real Workshop.")
	_check(worker.get_resolved_satisfaction() >= 0.75 and not worker.is_payroll_blocked()
		and CityStockManager.treasury_shekel == CITY_DEPOSIT and Inventory.items.get("shekel", 0) == 7,
		"Daily provisions keep the worker satisfied and the prepaid contract costs no further funds.")
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
	_check(worker.is_reserved() and WorkManager.active_orders.size() == 1
		and not worker.physical_approach.is_empty(),
		"The hired Laborer owns the actual Shape order and physical approach.")
	if not await _work_through_shifts(JOB.base_duration_minutes / 2, construction, visuals, worker_ids, player, inventory_ui):
		return
	var progress_entries: Array[Dictionary] = WorkManager.get_active_progress_entries()
	_check(progress_entries.size() == 1
		and is_equal_approx(float(progress_entries[0].get("progress_ratio", 0.0)), 0.5)
		and worker.physical_approach.get("arrived", false) and worker.is_working(),
		"The physically arrived worker reaches a real mid-Shape checkpoint.")
	_check(store.save_checkpoint(), "Save the mid-Shape checkpoint: " + store.last_error)


func _check_legacy_pending_worker() -> void:
	# Prepaid hiring no longer creates pending workers, but old saves may contain
	# one. Keep the old assignment/production guards covered without reviving the
	# retired hiring flow or including this temporary fixture in the checkpoint.
	var pending := WorkerData.new()
	pending.worker_id = "legacy_pending_production_probe"
	pending.profession = WorkerData.Profession.LABORER
	pending.payroll_start_day = TimeComponentManager.current_day + 1
	WorkerDatabase.workers_by_id[pending.worker_id] = pending
	var before_items: Dictionary = WorkShopStorage.items.duplicate(true)
	var before_fees: Array = WorkShopStorage.unpaid_claims_ledger.duplicate(true)
	var before_orders: int = WorkManager.active_orders.size()
	_check(pending.is_waiting_for_first_payment() and pending.is_payroll_blocked()
		and not WorkerDatabase.assign_worker(pending.worker_id),
		"A legacy worker awaiting its first payment cannot be assigned.")
	var rejected: String = WorkManager.start_job(JOB, WorkOrder.Worker_Type.NPC,
		pending.worker_id, null, WorkShopStorage, WorkShopStorage, JOB.workshop_fee_amount, 2)
	_check(rejected.is_empty() and WorkShopStorage.items == before_items
		and WorkShopStorage.unpaid_claims_ledger == before_fees and WorkManager.active_orders.size() == before_orders
		and not pending.is_reserved(), "Legacy pending production cannot consume inputs, create an order or register a fee.")
	WorkerDatabase.workers_by_id.erase(pending.worker_id)


func _work_through_shifts(amount: int, construction: Node, visuals: Node2D,
	worker_ids: Array[String], player: Player, inventory_ui: InventoryUI) -> bool:
	while amount > 0:
		var minute: int = TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
		if minute >= 15 * 60:
			var worker: WorkerData = WorkerDatabase.get_worker_data(worker_ids[0])
			var remaining: int = construction._remaining_work_units()
			_check(worker != null and worker.physical_approach.get("arrival_minute", -1) == WorkerData.PLOT_DEPARTURE_PENDING,
				"The worker must depart at the 15:00 shift boundary.")
			if worker == null or not await _feed_player(player, inventory_ui):
				return false
			var before_sleep: int = _now()
			var slept: bool = player.sleep()
			_check(slept and _now() - before_sleep == player.sleep_duration_minutes,
				"The player uses the real sleep API during the off-shift interval.")
			if not slept or not await _feed_player(player, inventory_ui):
				return false
			var next_shift: int = (TimeComponentManager.current_day + 1) * 1440 + 7 * 60
			if TimeComponentManager.current_hour < 7:
				next_shift -= 1440
			var advanced: bool = TimeComponentManager.advance_minutes(next_shift - _now())
			_check(advanced and construction._remaining_work_units() == remaining
				and worker.physical_approach.get("arrival_minute", -1) == WorkerData.PLOT_DEPARTURE_PENDING,
				"Neither sleep nor the overnight interval grants construction work or bypasses departure.")
			if not advanced or not await _feed_player(player, inventory_ui):
				return false
			continue
		if minute < 7 * 60:
			_check(false, "The fixture enters each work interval at or after 07:00.")
			return false
		if not await _feed_player(player, inventory_ui):
			return false
		var step: int = mini(amount, 15 * 60 - minute)
		var before: int = _now()
		var is_construction: bool = construction.phase in ["clearing", "building"]
		var remaining_before: int = construction._remaining_work_units() if is_construction else -1
		var worked: bool = SHIFT_DRIVER.work_minutes(step, visuals, worker_ids)
		_check(worked and _now() - before == step and not player.is_collapsing,
			"The worker physically arrives and contributes only the requested paid shift minutes.")
		if is_construction:
			_check(construction._remaining_work_units() == maxi(remaining_before - step, 0),
				"Each worked minute advances the single-worker construction exactly once.")
		if not worked or player.is_collapsing:
			return false
		amount -= step
	return true


func _feed_player(player: Player, inventory_ui: InventoryUI) -> bool:
	if player.hunger <= player.min_hunger:
		return true
	var food: ItemData = ItemDatabase.get_item_data("barley_bread")
	if food == null or food.hunger_reduction <= 0.0 or inventory_ui == null:
		_check(false, "The fixture can use registered food through the real inventory UI.")
		return false
	var quantity: int = ceili((player.hunger - player.min_hunger) / food.hunger_reduction)
	var grant: int = maxi(0, quantity - int(Inventory.items.get("barley_bread", 0)))
	if grant > 0:
		Inventory.add_item("barley_bread", grant)
	await inventory_ui._execute_use_item("barley_bread", quantity)
	var fed: bool = player.hunger <= player.min_hunger + 0.001 and not player.is_collapsing
	_check(fed and not player.debug_disable_player_needs and not player.debug_disable_fatigue,
		"Fixture food is consumed through Inventory while player needs remain active.")
	return fed


func _continue_shape_and_write_drying(city: Node, player: Player, store: Node) -> void:
	if not _assert_exact_continue(city, store, "mid-Shape"):
		return
	var worker: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	var player_still_active: bool = not player.debug_disable_player_needs and not player.debug_disable_fatigue
	_check(player_still_active and worker != null and worker.is_working()
		and worker.payroll_period_rate == CONTRACT_PRICE and not worker.is_payroll_blocked(),
		"Continue preserves active needs, paid Laborer state, and the running job.")
	_check(city.get_node("YSortWorld/WorkshopPlot").construction.phase == "built"
		and city.get_node("YSortWorld/WorkshopPlot").has_node("BuiltWorkshop")
		and is_equal_approx(WorkShopStorage.max_load, 200.0),
		"Continue restores the built Workshop and its authored capacity.")
	if worker == null:
		return
	if WorkManager.active_orders.size() != 1:
		_check(false, "Continue restores exactly one active Shape order.")
		return
	var order: WorkOrder = WorkManager.active_orders.values()[0] as WorkOrder
	_check(order.worker_id == LABORER_ID and order.job_id == JOB.job_id,
		"The continued WorkOrder still belongs to the authored Laborer and Shape recipe.")
	var expected_output: int = roundi(float(JOB.outputs["wet_mudbrick"]) * worker.get_satisfaction_work_multiplier())
	_check(expected_output == 21, "Fulfilled daily needs yield the high-Satisfaction Shape quantity.")
	_check(TimeComponentManager.advance_minutes(maxi(order.end_time_total_minutes - _now(), 1)),
		"The final paid, arrived Shape minutes advance.")
	_check(WorkManager.active_orders.is_empty() and not worker.is_working(),
		"The continued Shape WorkOrder completes and releases the worker.")
	_check(WorkShopStorage.output_lots.size() == 1
		and WorkShopStorage.output_lots[0].items.get("wet_mudbrick", 0) == expected_output,
		"Shape creates one held lot with its exact Satisfaction-scaled quantity.")
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
		and WorkShopStorage.get_free_item_quantity("wet_mudbrick") == expected_output,
		"Paying the Shape claim releases its wet bricks into Workshop Free Stock.")
	_check(Inventory.items.get("shekel", 0) == 2 and CityStockManager.treasury_shekel == CITY_DEPOSIT,
		"The five-shekel Shape fee comes from the player wallet, not city treasury.")
	shape_fee = _find_fee("job", JOB.job_id)
	_check(bool(shape_fee.get("is_paid", false)), "The Shape job fee records payment once.")

	# The built Drying Yard uses its real material and facility upgrade API.
	WorkShopStorage.add_bulk_item({"wood_log": 2, "reed_bundle": 4, "clay_lump": 4})
	var upgrade: Dictionary = WorkshopFacilityManager.upgrade_facility("drying_yard", WorkShopStorage)
	_check(bool(upgrade.get("success", false))
		and WorkshopFacilityManager.get_facility_level("drying_yard") == 1,
		"Fixture materials build one real Drying Yard station.")
	TimeComponentManager.current_weather = "clear"
	TimeComponentManager.emit_time_signal()
	_check(ProcessManager.start_registered_process(DRYING_PROCESS_ID, 20),
		"The real ProcessManager starts one full twenty-brick Drying batch.")
	_check(WorkShopStorage.get_free_item_quantity("wet_mudbrick") == expected_output - 20,
		"Drying consumes exactly twenty free wet bricks and preserves any excess.")
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
	_check(worker != null and worker.payroll_period_rate == CONTRACT_PRICE
		and worker.payroll_paid_until_day == worker.payroll_paid_from_day + CONTRACT_DAYS
		and worker.payroll_contract_days == CONTRACT_DAYS
		and CityStockManager.treasury_shekel == CITY_DEPOSIT,
		"The saved Laborer retains the exact prepaid package and city balance.")
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
		and WorkShopStorage.get_free_item_quantity("sun_dried_mudbrick") == 0
		and WorkShopStorage.get_free_item_quantity("wet_mudbrick") == 1,
		"Drying remains held behind its fee and the extra wet brick is preserved.")
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
	_check(Inventory.items.get("shekel", 0) == 2 and CityStockManager.treasury_shekel == CITY_DEPOSIT,
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
