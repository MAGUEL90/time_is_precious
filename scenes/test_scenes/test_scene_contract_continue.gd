extends Node
## Separate-process real New Game / Continue coverage for prepaid contracts.
## Wallet grants and clock placement below are explicit fixture setup only.

const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const VALUES: Script = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const CHECKPOINT_PATH: String = "user://contract_continue/checkpoint.json"
const WORKER_ID: String = "initial_workshop_laborer"
const HAULER_ID: String = "initial_worksite_hauler"
const INITIAL_APPLICANTS = preload("res://scenes/content_scene/startup/initial_worksites.gd")
const LEGACY_PENDING_ID: String = "contract_legacy_pending_fixture"
const WOOD_SITE: StringName = &"WoodSite"
const START_HOUR: int = 10
const START_MINUTE: int = 15
const ASSIGNMENT_PROGRESS_MINUTES: int = 3
const INITIAL_WALLET_GRANT: int = 8
const ACTIVE_RENEWAL_WALLET_GRANT: int = 5
const EXPIRED_RENEWAL_WALLET_GRANT: int = 2
const LEGACY_RENEWAL_WALLET_GRANT: int = 2

var failures: int = 0
var phase: String = "write"
var launched: bool = false
var phase_completed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--contract-phase="):
			phase = argument.trim_prefix("--contract-phase=")
	_check(phase in ["write", "read", "readrenew", "legacy-read", "legacy-renew-read", "assignment-write", "assignment-read"],
		"Known --contract-phase is required: write, read, readrenew, legacy-read, legacy-renew-read, assignment-write, or assignment-read.")
	if failures > 0:
		_finish()
		return

	get_tree().current_scene = null
	TimeComponentManager.set_process(false)
	# The fixture's package prices are explicit test rates, independent of runtime defaults.
	WorkerDatabase.onboarding_period_rates = {
		WorkerData.Profession.LABORER: 1,
		WorkerData.Profession.HAULER: 1,
	}
	if phase == "write":
		_check(not _checkpoint_exists(),
			"The write phase requires a fresh isolated user-data directory and never deletes a checkpoint.")
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
	_check(launched, "The real startup menu must finish the %s phase." % phase)
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
	_check(store.disk.path == CHECKPOINT_PATH,
		"The real CitySave owner uses the isolated contract fixture checkpoint.")

	match phase:
		"write":
			await _write_initial_checkpoint(city, store)
		"read":
			await _continue_and_renew_active(city, store)
		"readrenew":
			await _continue_expire_and_write_legacy(city, store)
		"legacy-read":
			await _continue_legacy_and_renew_pending(city, store)
		"legacy-renew-read":
			await _continue_after_legacy_renewal(city, store)
		"assignment-write":
			await _write_midshift_assignment(city, store)
		"assignment-read":
			await _read_midshift_assignment(city, store)
	_finish()


func _on_session_started(_continued: bool) -> void:
	launched = true


func _write_initial_checkpoint(city: Node, store: Node) -> void:
	_check(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(),
		"Real New Game begins without fixture wallet funds or hired workers.")
	var legacy_hauler: CitizenData = CitizenManager.get_citizen(HAULER_ID)
	_check(legacy_hauler != null and legacy_hauler.display_name == INITIAL_APPLICANTS.HAULER_NAME,
		"New Game creates the initial Hauler with its individual name.")
	if legacy_hauler == null:
		return
	# This fixture saves the exact old placeholder to exercise a pre-existing checkpoint.
	legacy_hauler.display_name = "Worksite Hauler"
	_set_clock(TimeComponentManager.current_day, START_HOUR, START_MINUTE)
	Inventory.add_item("shekel", INITIAL_WALLET_GRANT)
	var worker: WorkerData = WorkerDatabase.hire_applicant(WORKER_ID, 1, 3)
	_check(worker != null, "The authored Laborer is hired with a three-day wallet contract.")
	if worker == null:
		return
	var price: int = WorkerDatabase.get_contract_price(worker.profession, 3)
	var purchase_minute: int = _now()
	_check(price == 1 and Inventory.items.get("shekel", 0) == INITIAL_WALLET_GRANT - price,
		"The explicit wallet grant pays the three-day Laborer package immediately.")
	_check(CityStockManager.treasury_shekel == 0,
		"Immediate hiring draws from the player's explicitly granted wallet, not city funds.")
	_check(worker.payroll_start_day == TimeComponentManager.current_day
		and worker.payroll_paid_from_day == TimeComponentManager.current_day
		and worker.payroll_paid_until_day == TimeComponentManager.current_day + 3
		and worker.payroll_contract_days == 3
		and worker.payroll_paid_start_minute == purchase_minute
		and worker.get_paid_end_minute() == (worker.payroll_paid_until_day + 1) * 1440 + 7 * 60
		and worker.payroll_period_rate == price
		and not worker.is_payroll_blocked(),
		"The new hire receives an active three-day contract at the exact purchase minute with its 07:00 expiry.")
	var raid: Node = WorkStateRuntime.get_node("CityRaid")
	raid.notification_seen_keys = {"warning": "contract-fixture-raid-7"}
	_check(store.save_checkpoint(), "Save the initial paid-contract checkpoint: " + store.last_error)
	_assert_saved_capture(city, store, "initial contract")
	phase_completed = true


func _continue_and_renew_active(city: Node, store: Node) -> void:
	_check(_assert_exact_continue(city, store, "initial contract"),
		"Continue restores the initial contract snapshot exactly before fixture changes.")
	var legacy_hauler: CitizenData = CitizenManager.get_citizen(HAULER_ID)
	_check(legacy_hauler != null and legacy_hauler.display_name == "Worksite Hauler",
		"Continue restores the legacy applicant without altering the checkpoint.")
	if legacy_hauler == null:
		return
	var checkpoint_before: PackedByteArray = FileAccess.get_file_as_bytes(CHECKPOINT_PATH)
	var hauler_profession: WorkerData.Profession = legacy_hauler.profession
	var hauler_status: CitizenData.EmploymentStatus = legacy_hauler.employment_status
	var counter_before: int = CitizenGenerator.counter_id
	var wallet_before_board: int = Inventory.items.get("shekel", 0)
	var board: JobBoardUI = preload("res://scenes/ui/job_board_ui/job_board_ui.tscn").instantiate()
	city.add_child(board)
	board.open()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(legacy_hauler.display_name == INITIAL_APPLICANTS.HAULER_NAME
		and legacy_hauler.citizen_id == HAULER_ID and legacy_hauler.profession == hauler_profession
		and legacy_hauler.employment_status == hauler_status and CitizenGenerator.counter_id == counter_before
		and Inventory.items.get("shekel", 0) == wallet_before_board
		and FileAccess.get_file_as_bytes(CHECKPOINT_PATH) == checkpoint_before,
		"Opening Job Board resolves the exact old name without changing its ID, profession, status, wallet, generator counter, or disk checkpoint.")
	board.close()
	board.queue_free()
	await get_tree().process_frame
	var worker: WorkerData = WorkerDatabase.get_worker_data(WORKER_ID)
	if worker == null:
		_check(false, "Continue restores the immediately hired Laborer.")
		return
	var raid: Node = WorkStateRuntime.get_node("CityRaid")
	var wallet_before: int = Inventory.items.get("shekel", 0)
	_check(worker.payroll_contract_days == 3
		and worker.payroll_paid_start_minute == TimeComponentManager.current_day * 1440 + START_HOUR * 60 + START_MINUTE
		and wallet_before == INITIAL_WALLET_GRANT - 1
		and CityStockManager.treasury_shekel == 0,
		"Continue retains the exact paid start and wallet without charging the three-day contract twice.")
	_check(raid.notification_seen_keys == {"warning": "contract-fixture-raid-7"},
		"Continue restores the saved raid notification acknowledgement.")
	_test_current_schema_validation(store, city)
	if failures > 0:
		return

	var old_from: int = worker.payroll_paid_from_day
	var old_until: int = worker.payroll_paid_until_day
	var old_paid_start: int = worker.payroll_paid_start_minute
	Inventory.add_item("shekel", ACTIVE_RENEWAL_WALLET_GRANT)
	var wallet_with_grant: int = Inventory.items.get("shekel", 0)
	var active_price: int = WorkerDatabase.get_contract_price(worker.profession, 6)
	_check(active_price == 2 and WorkerDatabase.renew_contract(WORKER_ID, 6),
		"An active Laborer can manually append a six-day wallet contract.")
	_check(worker.payroll_paid_from_day == old_from
		and worker.payroll_paid_until_day == old_until + 6
		and worker.payroll_paid_start_minute == old_paid_start
		and worker.payroll_contract_days == 6
		and worker.payroll_period_rate == active_price
		and Inventory.items.get("shekel", 0) == wallet_with_grant - active_price
		and CityStockManager.treasury_shekel == 0,
		"Active renewal appends days, preserves the original paid start, and charges only the explicit wallet price.")
	_check(store.save_checkpoint(), "Save the manually renewed contract: " + store.last_error)
	_assert_saved_capture(city, store, "active renewal")
	phase_completed = true


func _continue_expire_and_write_legacy(city: Node, store: Node) -> void:
	_check(_assert_exact_continue(city, store, "active renewal"),
		"A separate Continue restores the renewed contract and all captured owners exactly.")
	var restored_hauler: CitizenData = CitizenManager.get_citizen(HAULER_ID)
	_check(restored_hauler != null and restored_hauler.display_name == INITIAL_APPLICANTS.HAULER_NAME,
		"The corrected applicant name survives the next ordinary save and Continue.")
	var worker: WorkerData = WorkerDatabase.get_worker_data(WORKER_ID)
	if worker == null:
		_check(false, "Continue restores the actively renewed Laborer.")
		return
	var wallet_before_expiry: int = Inventory.items.get("shekel", 0)
	var treasury_before_expiry: int = CityStockManager.treasury_shekel
	_check(worker.payroll_contract_days == 6 and worker.payroll_paid_until_day == worker.payroll_paid_from_day + 9,
		"Continue retains the six-day manual extension after the original three-day package.")
	_check(wallet_before_expiry == INITIAL_WALLET_GRANT - 1 + ACTIVE_RENEWAL_WALLET_GRANT - 2
		and treasury_before_expiry == 0,
		"Continue does not charge the saved active contract again.")
	_test_current_schema_validation(store, city)
	if failures > 0:
		return

	# Explicit test clock placement to one minute before the new contract's exact 07:00 expiry.
	var expiry_minute: int = worker.get_paid_end_minute()
	_check(expiry_minute == (worker.payroll_paid_until_day + 1) * 1440 + 7 * 60,
		"A new contract's entitlement ends at 07:00 after its final paid day.")
	_set_clock_from_global_minute(expiry_minute - 1)
	TimeComponentManager.advance_minutes(1)
	_check(_now() == expiry_minute and worker.is_payroll_blocked(),
		"The worker becomes unpaid at its exact next-day 07:00 expiry boundary.")
	_check(Inventory.items.get("shekel", 0) == wallet_before_expiry
		and CityStockManager.treasury_shekel == treasury_before_expiry
		and worker.payroll_paid_until_day == expiry_minute / 1440 - 1,
		"Expiry is independent: crossing 07:00 neither extends the contract nor charges either cash owner.")

	Inventory.add_item("shekel", EXPIRED_RENEWAL_WALLET_GRANT)
	var expired_wallet: int = Inventory.items.get("shekel", 0)
	var expired_day: int = TimeComponentManager.current_day
	var expired_price: int = WorkerDatabase.get_contract_price(worker.profession, 3)
	_check(expired_price == 1 and WorkerDatabase.renew_contract(WORKER_ID, 3),
		"An expired worker can resume only after a manual three-day wallet renewal.")
	_check(worker.payroll_start_day == expired_day
		and worker.payroll_paid_from_day == expired_day
		and worker.payroll_paid_until_day == expired_day + 3
		and worker.payroll_contract_days == 3
		and worker.payroll_paid_start_minute == _now()
		and worker.payroll_period_rate == expired_price
		and not worker.is_payroll_blocked()
		and Inventory.items.get("shekel", 0) == expired_wallet - expired_price
		and CityStockManager.treasury_shekel == treasury_before_expiry,
		"Manual renewal after expiry starts a new exact paid interval and deducts only the wallet price.")
	_check(store.save_checkpoint(), "Save the post-expiry manual renewal: " + store.last_error)
	_assert_saved_capture(city, store, "post-expiry renewal")
	if failures > 0:
		return

	var current: Dictionary = store.snapshot.capture(city)
	var legacy_v6: Dictionary = _make_legacy_v6(current, store)
	if legacy_v6.is_empty():
		return
	var file: FileAccess = FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
	_check(file != null, "The fixture can replace its own isolated checkpoint with the encoded v6 document.")
	if file == null:
		return
	file.store_string(JSON.stringify(legacy_v6, "\t", true, true))
	file.close()
	var written: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	_check(written is Dictionary and written.get("schema_version") == 6,
		"The next separate process receives a genuine schema-six checkpoint.")
	phase_completed = true


func _continue_legacy_and_renew_pending(city: Node, store: Node) -> void:
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	_check(disk is Dictionary and disk.get("schema_version") == 6,
		"The legacy-read phase opens the fixture's downgraded v6 checkpoint.")
	if not disk is Dictionary:
		return
	var legacy_values = VALUES.new()
	legacy_values.allow_legacy_contract_fields = true
	legacy_values.allow_legacy_approach_field = true
	var expected_raw: Variant = legacy_values.decode(disk.get("state"))
	_check(legacy_values.error.is_empty() and expected_raw is Dictionary,
		"The encoded v6 test document decodes with its missing contract and approach fields enabled.")
	if not legacy_values.error.is_empty() or not expected_raw is Dictionary:
		return
	var expected_workers: Variant = expected_raw.get("workers")
	var expected_inventory: Variant = expected_raw.get("inventory")
	var expected_stock: Variant = expected_raw.get("stock")
	if not expected_workers is Dictionary or not expected_inventory is Dictionary or not expected_stock is Dictionary:
		_check(false, "The decoded v6 document contains worker, inventory, and stock groups.")
		return
	var expected_worker_map: Variant = expected_workers.get("workers_by_id")
	var expected_items: Variant = expected_inventory.get("items")
	if not expected_worker_map is Dictionary or not expected_items is Dictionary:
		_check(false, "The decoded v6 document contains worker records and wallet items.")
		return
	var expected_paid_value: Variant = expected_worker_map.get(WORKER_ID)
	var expected_pending_value: Variant = expected_worker_map.get(LEGACY_PENDING_ID)
	if not expected_paid_value is WorkerData or not expected_pending_value is WorkerData:
		_check(false, "The v6 document contains its paid and pending fixture workers.")
		return
	var expected_paid: WorkerData = expected_paid_value
	var expected_pending: WorkerData = expected_pending_value
	var expected_wallet: int = expected_items.get("shekel", 0)
	var expected_treasury: int = expected_stock.get("treasury_shekel", -1)
	_check(expected_paid.payroll_paid_until_day == expected_paid.payroll_paid_from_day + 6,
		"The downgraded paid legacy worker carries a complete seven-day v6 period.")
	_check(expected_pending.payroll_paid_from_day == -1 and expected_pending.payroll_paid_until_day == -1,
		"The downgraded pending legacy worker has no prepaid interval.")

	var restored_value: Variant = store.snapshot.capture(city)
	if not restored_value is Dictionary or not restored_value.has("state"):
		_check(false, "Continue captures the migrated current-schema state after the v6 load.")
		return
	# Contract-field omission is permitted only while reading v6 data. Decode the
	# post-migration capture with a fresh current-schema codec.
	var current_values = VALUES.new()
	var restored_raw_value: Variant = current_values.decode(restored_value.get("state"))
	_check(current_values.error.is_empty() and restored_raw_value is Dictionary,
		"Continue's migrated current-schema state decodes with the current codec.")
	if not current_values.error.is_empty() or not restored_raw_value is Dictionary:
		return
	var restored_raw: Dictionary = restored_raw_value
	var paid: WorkerData = WorkerDatabase.get_worker_data(WORKER_ID)
	var pending: WorkerData = WorkerDatabase.get_worker_data(LEGACY_PENDING_ID)
	if paid == null or pending == null:
		_check(false, "Continue restores both paid and pending workers from the v6 fixture.")
		return
	_check(paid.payroll_start_day == expected_paid.payroll_start_day
		and paid.payroll_paid_from_day == expected_paid.payroll_paid_from_day
		and paid.payroll_paid_until_day == expected_paid.payroll_paid_until_day
		and paid.payroll_period_rate == expected_paid.payroll_period_rate
		and paid.payroll_last_attempt_day == expected_paid.payroll_last_attempt_day
		and paid.payroll_contract_days == 0
		and paid.payroll_paid_start_minute == -1
		and paid.get_paid_end_minute() == (paid.payroll_paid_until_day + 1) * 1440 + 8 * 60,
		"V6 Continue preserves all paid seven-day dates and rate while marking its legacy time basis.")
	_check(pending.payroll_start_day == expected_pending.payroll_start_day
		and pending.payroll_paid_from_day == -1
		and pending.payroll_paid_until_day == -1
		and pending.payroll_contract_days == 0
		and pending.payroll_paid_start_minute == -1
		and pending.is_waiting_for_first_payment(),
		"V6 Continue leaves the legacy pending hire unpaid without inventing entitlement.")
	_check(Inventory.items.get("shekel", 0) == expected_wallet
		and CityStockManager.treasury_shekel == expected_treasury,
		"Loading v6 never charges wallet or city cash for paid or pending workers.")
	_check(restored_raw.raid.notification_seen_keys.is_empty(),
		"V6 migration initializes the absent raid notification acknowledgement dictionary.")
	var legacy_expiry_minute: int = paid.get_paid_end_minute()
	var wallet_before_legacy_expiry: int = Inventory.items.get("shekel", 0)
	var treasury_before_legacy_expiry: int = CityStockManager.treasury_shekel
	_set_clock_from_global_minute(legacy_expiry_minute - 1)
	TimeComponentManager.advance_minutes(1)
	_check(_now() == legacy_expiry_minute and paid.is_payroll_blocked()
		and legacy_expiry_minute == (paid.payroll_paid_until_day + 1) * 1440 + 8 * 60,
		"The migrated seven-day legacy worker retains its original next-day 08:00 expiry.")
	_check(Inventory.items.get("shekel", 0) == wallet_before_legacy_expiry
		and CityStockManager.treasury_shekel == treasury_before_legacy_expiry,
		"Legacy expiry also leaves both cash owners unchanged without an automatic charge.")

	_test_current_schema_validation(store, city)
	if failures > 0:
		return
	Inventory.add_item("shekel", LEGACY_RENEWAL_WALLET_GRANT)
	var wallet_with_grant: int = Inventory.items.get("shekel", 0)
	var before_day: int = TimeComponentManager.current_day
	var before_now: int = _now()
	_check(WorkerDatabase.renew_contract(LEGACY_PENDING_ID, 3),
		"A migrated pending legacy hire can be renewed manually from an explicit wallet grant.")
	_check(pending.payroll_start_day == before_day
		and pending.payroll_paid_from_day == before_day
		and pending.payroll_paid_until_day == before_day + 3
		and pending.payroll_contract_days == 3
		and pending.payroll_paid_start_minute == before_now
		and not pending.is_payroll_blocked()
		and Inventory.items.get("shekel", 0) == wallet_with_grant - 1
		and CityStockManager.treasury_shekel == expected_treasury,
		"Manual legacy renewal creates a new contract at the exact minute and charges only the explicit wallet price.")
	_check(store.save_checkpoint(), "Save after manually renewing the pending legacy hire: " + store.last_error)
	phase_completed = true


func _continue_after_legacy_renewal(city: Node, store: Node) -> void:
	_check(_assert_exact_continue(city, store, "legacy pending renewal"),
		"A separate Continue restores the manually renewed legacy worker and all save owners exactly.")
	var disk_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	if not disk_value is Dictionary or not disk_value.has("state"):
		_check(false, "The renewed legacy checkpoint is readable for exact cash comparison.")
		return
	var values = VALUES.new()
	var expected_raw_value: Variant = values.decode(disk_value.get("state"))
	_check(values.error.is_empty() and expected_raw_value is Dictionary,
		"The saved post-migration checkpoint decodes with the current schema.")
	if not values.error.is_empty() or not expected_raw_value is Dictionary:
		return
	var expected_raw: Dictionary = expected_raw_value
	var inventory: Variant = expected_raw.get("inventory")
	var stock: Variant = expected_raw.get("stock")
	if not inventory is Dictionary or not stock is Dictionary or not inventory.get("items") is Dictionary:
		_check(false, "The renewed checkpoint includes readable wallet and city cash owners.")
		return
	var expected_wallet: int = inventory.items.get("shekel", 0)
	var expected_treasury: int = stock.get("treasury_shekel", -1)
	var pending: WorkerData = WorkerDatabase.get_worker_data(LEGACY_PENDING_ID)
	if pending == null:
		_check(false, "Continue restores the manually renewed legacy worker.")
		return
	_check(pending.payroll_contract_days == 3
		and pending.payroll_paid_from_day == pending.payroll_start_day
		and pending.payroll_paid_until_day == pending.payroll_start_day + 3
		and pending.payroll_paid_start_minute == _now()
		and not pending.is_payroll_blocked(),
		"The exact Continue preserves the manual contract started for the migrated pending worker.")
	_check(Inventory.items.get("shekel", 0) == expected_wallet
		and CityStockManager.treasury_shekel == expected_treasury,
		"A further Continue does not charge the wallet or city a second time.")
	phase_completed = true


func _write_midshift_assignment(city: Node, store: Node) -> void:
	if not _assert_exact_continue(city, store, "legacy renewal before worksite assignment"):
		return
	var worker: WorkerData = WorkerDatabase.get_worker_data(LEGACY_PENDING_ID)
	var runtime: Node = city.get_node_or_null("YSortWorld/WorkerRuntime")
	if worker == null or runtime == null:
		_check(false, "Continue restores the paid fixture Laborer and the authored WorkerRuntime.")
		return
	var start_minute: int = TimeComponentManager.current_day * 1440 + START_HOUR * 60 + START_MINUTE
	_set_clock(TimeComponentManager.current_day, START_HOUR, START_MINUTE)
	runtime.daily.last_tick = start_minute
	runtime.daily.last_stock_day = TimeComponentManager.current_day
	WorkManager._last_total_minutes = start_minute
	var paid_for_start: bool = (worker.profession == WorkerData.Profession.LABORER
		and not worker.is_payroll_blocked()
		and worker.get_paid_start_minute() <= start_minute
		and start_minute < worker.get_paid_end_minute())
	_check(paid_for_start,
		"The manually renewed Laborer is paid for the fixture's 10:15 worksite start.")
	if not paid_for_start:
		return
	var wallet_before: int = Inventory.items.get("shekel", 0)
	var treasury_before: int = CityStockManager.treasury_shekel
	var toggled: bool = runtime.daily.toggle(WOOD_SITE, LEGACY_PENDING_ID)
	_check(toggled,
		"The real Daily scheduler accepts the paid Laborer for the standing Wood Site assignment.")
	if not toggled:
		return
	var marker: Marker2D = runtime.get_node_or_null("WorksiteMarkers/WoodSite") as Marker2D
	if marker == null:
		_check(false, "The authored Wood Site marker exists on the live map.")
		return
	var started: bool = runtime.daily.start(
		WOOD_SITE, runtime._drop_daily_output.bind(marker)
	)
	_check(started and runtime.daily.jobs.has(WOOD_SITE),
		"The real Daily scheduler starts the Laborer's standing Wood Site job.")
	if not started:
		return
	var pending_job: Dictionary = runtime.daily.jobs[WOOD_SITE]
	_check(not worker.physical_approach.is_empty() and not worker.physical_approach.arrived
		and worker.current_work_status == WorkerData.WorkStatus.TRAVELLING
		and is_zero_approx(float(pending_job.progress.get(LEGACY_PENDING_ID, -1.0)))
		and int(runtime.daily.minutes_by_worker.get(LEGACY_PENDING_ID, 0)) == 0,
		"Starting the paid standing assignment synchronously reserves a pending physical route with zero production.")
	if worker.physical_approach.is_empty():
		return
	var origin: Vector2 = worker.physical_approach.position
	var target: Vector2 = worker.physical_approach.target
	var approach_task: String = worker.physical_approach.task
	var visuals: Node = runtime.get_node("WorkerVisuals")
	for _frame: int in range(2000):
		if worker.physical_approach.arrived:
			break
		visuals._process(0.05)
	var reached: bool = worker.physical_approach.arrived
	_check(reached and worker.physical_approach.position.distance_to(origin) > 0.0
		and worker.physical_approach.position.distance_to(target) <= 0.1
		and worker.matches_physical_approach("site", approach_task, str(WOOD_SITE))
		and int(worker.physical_approach.arrival_minute) == start_minute
		and _now() == start_minute
		and worker.current_work_status == WorkerData.WorkStatus.WORKING,
		"Real physical movement reaches the worksite target before WORKING, without advancing the fixture clock.")
	if not reached:
		return
	TimeComponentManager.advance_minutes(ASSIGNMENT_PROGRESS_MINUTES)
	var job: Dictionary = runtime.daily.jobs[WOOD_SITE]
	_check(_now() == start_minute + ASSIGNMENT_PROGRESS_MINUTES
		and job.ids == [LEGACY_PENDING_ID]
		and int(job.starts[LEGACY_PENDING_ID]) == start_minute
		and is_equal_approx(float(job.progress[LEGACY_PENDING_ID]), float(ASSIGNMENT_PROGRESS_MINUTES))
		and worker.is_reserved()
		and worker.current_work_status == WorkerData.WorkStatus.WORKING,
		"The live Wood Site job keeps its 10:15 start and three minutes of midshift progress.")
	_check(Inventory.items.get("shekel", 0) == wallet_before
		and CityStockManager.treasury_shekel == treasury_before,
		"Starting midshift work and advancing three minutes do not charge either cash owner.")
	_assert_saved_capture(city, store, "midshift Wood Site assignment")
	if failures == 0:
		phase_completed = true


func _read_midshift_assignment(city: Node, store: Node) -> void:
	var exact_continue: bool = _assert_exact_continue(city, store, "midshift Wood Site assignment")
	_check(exact_continue,
		"A separate Continue restores the complete midshift worksite checkpoint exactly.")
	if not exact_continue:
		return
	var worker: WorkerData = WorkerDatabase.get_worker_data(LEGACY_PENDING_ID)
	var runtime: Node = city.get_node_or_null("YSortWorld/WorkerRuntime")
	if worker == null or runtime == null or not runtime.daily.jobs.has(WOOD_SITE):
		_check(false, "Continue restores the assigned Laborer, WorkerRuntime, and standing Wood Site job.")
		return
	var job: Dictionary = runtime.daily.jobs[WOOD_SITE]
	var expected_start: int = TimeComponentManager.current_day * 1440 + START_HOUR * 60 + START_MINUTE
	_check(TimeComponentManager.current_hour == START_HOUR
		and TimeComponentManager.current_minute == START_MINUTE + ASSIGNMENT_PROGRESS_MINUTES
		and job.ids == [LEGACY_PENDING_ID]
		and int(job.starts.get(LEGACY_PENDING_ID, -1)) == expected_start
		and is_equal_approx(float(job.progress.get(LEGACY_PENDING_ID, -1.0)), float(ASSIGNMENT_PROGRESS_MINUTES))
		and int(runtime.daily.minutes_by_worker.get(LEGACY_PENDING_ID, -1)) == ASSIGNMENT_PROGRESS_MINUTES
		and worker.current_order_id == str(job.order)
		and worker.current_job_id == "clay_daily"
		and worker.is_reserved()
		and worker.current_work_status == WorkerData.WorkStatus.WORKING,
		"Continue preserves the 10:15 start, three minutes of progress, and reserved standing assignment.")
	var saved_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	var values = VALUES.new()
	var saved_raw: Variant = values.decode(saved_document.state)
	_check(values.error.is_empty() and saved_raw is Dictionary,
		"Decode the saved physical-arrival evidence with the current strict codec.")
	if not values.error.is_empty() or not saved_raw is Dictionary:
		return
	var saved_approach: Dictionary = saved_raw.workers.workers_by_id[LEGACY_PENDING_ID].physical_approach
	var approach_task: String = runtime.site_approach_task(WOOD_SITE, LEGACY_PENDING_ID, TimeComponentManager.current_day)
	_check(not saved_approach.is_empty() and worker.physical_approach == saved_approach
		and worker.matches_physical_approach("site", approach_task, str(WOOD_SITE))
		and worker.physical_approach.arrived
		and int(worker.physical_approach.arrival_minute) == expected_start,
		"Continue preserves the exact saved physical pose, target, arrival identity and arrived state.")
	if failures == 0:
		phase_completed = true


func _test_current_schema_validation(store: Node, city: Node) -> void:
	var current: Dictionary = store.snapshot.capture(city)
	_check(not current.is_empty(), "Capture a valid current contract snapshot for strict-schema checks.")
	if current.is_empty():
		return
	var malformed: Dictionary = current.duplicate(true)
	_strip_contract_fields(malformed.state)
	_check(not store.snapshot.prepare(malformed, city),
		"Current schema rejects WorkerData payloads missing the contract fields.")
	var values = VALUES.new()
	var raw: Variant = values.decode(current.state)
	_check(values.error.is_empty() and raw is Dictionary,
		"Decode a complete snapshot before testing malformed contract values.")
	if not raw is Dictionary:
		return
	var worker: WorkerData = raw.workers.workers_by_id.get(WORKER_ID)
	if worker == null:
		_check(false, "A saved fixture worker exists for malformed contract checks.")
		return
	worker.payroll_contract_days = 4
	malformed = current.duplicate(true)
	malformed.state = values.encode(raw)
	_check(not store.snapshot.prepare(malformed, city),
		"Current schema rejects a contract length outside the supported package set.")
	raw = values.decode(current.state)
	if values.error.is_empty() and raw is Dictionary:
		raw.raid.notification_seen_keys["warning"] = 4
		malformed = current.duplicate(true)
		malformed.state = values.encode(raw)
		_check(not store.snapshot.prepare(malformed, city),
			"Current schema rejects malformed persisted raid notification acknowledgements.")
	_check(store.snapshot.prepare(current, city),
		"The valid current contract snapshot still prepares after malformed input rejection.")


func _assert_exact_continue(city: Node, store: Node, label: String) -> bool:
	_check(FileAccess.file_exists(CHECKPOINT_PATH), "The %s Continue checkpoint exists." % label)
	if not FileAccess.file_exists(CHECKPOINT_PATH):
		return false
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	_check(disk is Dictionary, "The %s Continue checkpoint is valid JSON." % label)
	if not disk is Dictionary:
		return false
	var restored: Dictionary = store.snapshot.capture(city)
	var exact: bool = _canonical(restored) == _canonical(disk)
	_check(exact, "Separate-process %s Continue restores every captured owner exactly." % label)
	return exact


func _assert_saved_capture(city: Node, store: Node, label: String) -> void:
	var captured: Dictionary = store.snapshot.capture(city)
	_check(not captured.is_empty(), "Capture the %s checkpoint before saving." % label)
	if captured.is_empty():
		return
	_check(store.save_checkpoint(), "Save the %s checkpoint: %s" % [label, store.last_error])
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	_check(disk is Dictionary and _canonical(captured) == _canonical(disk),
		"The %s disk checkpoint exactly matches every captured save owner." % label)


func _make_legacy_v6(current: Dictionary, store: Node) -> Dictionary:
	_check(not current.is_empty(), "Capture the complete post-renewal current-schema fixture before downgrade.")
	if current.is_empty():
		return {}
	var values = VALUES.new()
	var raw: Variant = values.decode(current.state)
	_check(values.error.is_empty() and raw is Dictionary,
		"Decode current saved values before creating the v6-shaped document.")
	if not raw is Dictionary:
		return {}
	var paid: WorkerData = raw.workers.workers_by_id.get(WORKER_ID)
	if paid == null or paid.payroll_paid_from_day < 0:
		_check(false, "The fixture has a paid worker to convert to the v6 seven-day record.")
		return {}
	# Schema six stored the old seven-day paid interval but knew neither new contract field.
	paid.payroll_paid_until_day = paid.payroll_paid_from_day + 6
	var source_citizen: CitizenData = raw.citizens.citizens_by_id.get(WORKER_ID)
	if source_citizen == null:
		_check(false, "The fixture can clone an existing resident for its pending legacy worker.")
		return {}
	var pending_citizen: CitizenData = source_citizen.duplicate(true)
	pending_citizen.citizen_id = LEGACY_PENDING_ID
	pending_citizen.display_name = "Legacy Pending Contract Fixture"
	pending_citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	pending_citizen.employment_status = CitizenData.EmploymentStatus.HIRED
	pending_citizen.profession = WorkerData.Profession.LABORER
	raw.citizens.citizens_by_id[LEGACY_PENDING_ID] = pending_citizen
	var pending_worker: WorkerData = WorkerData.new()
	pending_worker.worker_id = LEGACY_PENDING_ID
	pending_worker.display_name = pending_citizen.display_name
	pending_worker.profession = WorkerData.Profession.LABORER
	pending_worker.wage_shekel_per_day = 1
	pending_worker.payroll_start_day = TimeComponentManager.current_day
	pending_worker.payroll_paid_from_day = -1
	pending_worker.payroll_paid_until_day = -1
	pending_worker.payroll_period_rate = 0
	pending_worker.payroll_last_attempt_day = -1
	raw.workers.workers_by_id[LEGACY_PENDING_ID] = pending_worker
	raw.raid.erase("notification_seen_keys")
	var encoded_state: Variant = values.encode(raw)
	_check(values.error.is_empty() and encoded_state is Dictionary,
		"Encode the legacy fixture through CitySaveValues before removing fields absent in schema six.")
	if values.error != "" or not encoded_state is Dictionary:
		return {}
	_strip_contract_fields(encoded_state)
	_strip_approach_field(encoded_state)
	var legacy: Dictionary = current.duplicate(true)
	legacy.schema_version = 6
	legacy.state = encoded_state
	_check(store.snapshot.prepare(legacy, get_tree().current_scene),
		"The generated paid and pending v6 document prepares before it is written.")
	_check(store.snapshot.prepare(current, get_tree().current_scene),
		"The original current-schema snapshot remains valid after checking its v6 copy.")
	return legacy


func _strip_contract_fields(value: Variant) -> void:
	if value is Dictionary:
		if value.get("$type") == "object" and value.get("class") == "WorkerData":
			for field: String in VALUES.CONTRACT_FIELDS:
				value.fields.erase(field)
		for child: Variant in value.values():
			_strip_contract_fields(child)
	elif value is Array:
		for child: Variant in value:
			_strip_contract_fields(child)


func _strip_approach_field(value: Variant) -> void:
	if value is Dictionary:
		if value.get("$type") == "object" and value.get("class") == "WorkerData":
			value.fields.erase("physical_approach")
		for child: Variant in value.values():
			_strip_approach_field(child)
	elif value is Array:
		for child: Variant in value:
			_strip_approach_field(child)


func _set_clock(day: int, hour: int, minute: int) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute
	TimeComponentManager.current_weather = "clear"
	TimeComponentManager._timer = 0.0
	TimeComponentManager.emit_time_signal()


func _set_clock_from_global_minute(global_minute: int) -> void:
	TimeComponentManager.current_day = floori(float(global_minute) / 1440.0)
	var minute_of_day: int = global_minute % 1440
	TimeComponentManager.current_hour = minute_of_day / 60
	TimeComponentManager.current_minute = minute_of_day % 60
	TimeComponentManager._timer = 0.0


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
	var passed: bool = failures == 0 and phase_completed
	if not phase_completed:
		push_error("The %s phase did not reach its completion sentinel." % phase)
	print("ContractContinue ", phase, ": ", "PASS" if passed else "FAIL")
	var exit_code: int = 0 if passed else 1
	var scene: Node = get_tree().current_scene
	get_tree().current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(exit_code)
