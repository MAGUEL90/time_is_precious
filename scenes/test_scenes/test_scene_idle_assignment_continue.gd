extends Node
## Real New Game/Continue coverage for transient idle workshop assignment canonicalization.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const VALUES: Script = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const WORKER_MANAGEMENT: Script = preload("res://scenes/test_scenes/clay_worksite_test/clay_worker_management.gd")
const JOB: JobData = preload("res://resources/job_data/mudbrick_make.tres")
const CHECKPOINT_PATH: String = "user://idle_assignment_continue/checkpoint.json"
const PRIMARY_ID: String = "initial_workshop_laborer"
const RESERVED_ID: String = "initial_worksite_hauler"
const PERIOD_DAYS: int = 7
const PRIMARY_RATE: int = 1
const RESERVED_RATE: int = 2
const WALLET_GRANT: int = 3
const CITY_DEPOSIT: int = 2
const INGREDIENT_GRANT: Dictionary = {"clay_lump": 3, "straw_bundle": 3, "water_jar": 3}

var failures: int = 0
var phase: String = "write"
var launched: bool = false
var restored_snapshot: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--idle-assignment-phase="):
			phase = argument.trim_prefix("--idle-assignment-phase=")
	_check(phase in ["write", "read"], "Known --idle-assignment-phase is required: write or read.")
	if failures > 0:
		_finish()
		return
	get_tree().current_scene = null
	get_tree().paused = false
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	WorkerDatabase.onboarding_period_rates = {
		WorkerData.Profession.LABORER: PRIMARY_RATE,
		WorkerData.Profession.HAULER: RESERVED_RATE,
	}
	if phase == "write":
		_check(not FileAccess.file_exists(CHECKPOINT_PATH),
			"The write phase requires a fresh isolated user-data directory; it never removes checkpoints.")
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
	var store: Node = WorkStateRuntime.get_node("CitySave")
	_check(store.disk.path == CHECKPOINT_PATH,
		"The real CitySave owner uses this fixture's isolated checkpoint.")
	var player: Player = city.get_node("YSortWorld/Player")
	_check(not player.debug_disable_player_needs and not player.debug_disable_fatigue,
		"The fixture leaves player needs and fatigue enabled.")
	if failures == 0:
		if phase == "write":
			await _write_checkpoint(city, store)
		else:
			await _continue_checkpoint(city, store)
	_finish()


func _on_session_started(continued: bool) -> void:
	_check(continued == (phase == "read"),
		"The real start menu reports New Game for write and Continue for read.")
	if continued:
		var store: Node = WorkStateRuntime.get_node("CitySave")
		var captured: Dictionary = store.snapshot.capture(get_tree().current_scene)
		restored_snapshot = JSON.parse_string(JSON.stringify(captured, "\t", true, true))
	launched = true


func _write_checkpoint(city: Node, store: Node) -> void:
	_check(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(),
		"Actual New Game starts without fixture inventory or hired workers.")
	_check(CityStockManager.treasury_shekel == 0,
		"Actual New Game starts without fixture city funds.")
	if failures > 0:
		return

	# These fixture grants keep payroll fields meaningful while leaving all needs systems active.
	TimeComponentManager.current_day = 2
	TimeComponentManager.current_hour = 9
	TimeComponentManager.current_minute = 0
	TimeComponentManager._timer = 0.0
	TimeComponentManager.emit_time_signal()
	WorkManager._last_total_minutes = _current_total_minutes()
	Inventory.add_item("shekel", WALLET_GRANT)
	_check(CityStockManager.deposit_wallet_shekel(CITY_DEPOSIT)
		and Inventory.items.get("shekel", 0) == WALLET_GRANT - CITY_DEPOSIT
		and CityStockManager.treasury_shekel == CITY_DEPOSIT,
		"The fixture explicitly splits its wallet grant and city deposit.")
	var primary: WorkerData = WorkerDatabase.hire_applicant(PRIMARY_ID, 17)
	var reserved: WorkerData = WorkerDatabase.hire_applicant(RESERVED_ID, 8)
	_check(primary != null and reserved != null,
		"Fixture hires the authored Laborer and Hauler through WorkerDatabase.")
	if primary == null or reserved == null:
		return
	_grant_paid_period(primary, PRIMARY_RATE)
	_grant_paid_period(reserved, RESERVED_RATE)
	primary.profession_xp = 17
	reserved.profession_xp = 8
	var primary_citizen: CitizenData = primary.get_linked_citizen()
	var reserved_citizen: CitizenData = reserved.get_linked_citizen()
	_check(primary_citizen != null and reserved_citizen != null,
		"Both hired workers retain their authored linked citizens.")
	if primary_citizen == null or reserved_citizen == null:
		return
	primary_citizen.satisfaction = 0.63
	primary_citizen.reliability = 0.77
	primary_citizen.food_fulfilled = true
	primary_citizen.clothing_fulfilled = false
	primary_citizen.shelter_fulfilled = true
	primary_citizen.experience = 12.5
	_check(WorkerDatabase.assign_worker(PRIMARY_ID)
		and primary_citizen.employment_status == CitizenData.EmploymentStatus.ASSIGNED,
		"The paid idle Laborer enters the same ASSIGNED state used by the workshop selector.")
	_check(WorkerDatabase.assign_worker(RESERVED_ID)
		and reserved_citizen.employment_status == CitizenData.EmploymentStatus.ASSIGNED,
		"The paid Hauler enters ASSIGNED before starting reserved work.")
	Inventory.add_bulk_item(INGREDIENT_GRANT)
	var reserved_job: JobData = JOB.duplicate(true)
	reserved_job.requirement_profession = WorkerData.Profession.HAULER
	var order_id: String = WorkManager.start_job(
		reserved_job, WorkOrder.Worker_Type.NPC, RESERVED_ID, null, Inventory, WorkShopStorage, 0, 1
	)
	_check(not order_id.is_empty() and reserved.is_reserved() and reserved.is_working(),
		"The fixture starts one genuine reserved NPC workshop order for the Hauler: " + WorkManager.get_last_start_job_error())
	if failures > 0:
		return

	var values = VALUES.new()
	var live_primary_before: Variant = values.encode(primary_citizen)
	var live_worker_before: Variant = values.encode(primary)
	var live_reserved_citizen_before: Variant = values.encode(reserved_citizen)
	var live_reserved_worker_before: Variant = values.encode(reserved)
	var wallet_before: Dictionary = Inventory.items.duplicate(true)
	var city_cash_before: int = CityStockManager.treasury_shekel
	var captured: Dictionary = store.snapshot.capture(city)
	_check(not captured.is_empty(), "Capture the live New Game state: " + store.snapshot.error)
	if captured.is_empty():
		return
	var captured_raw: Dictionary = values.decode(captured.state)
	var captured_primary: CitizenData = captured_raw.citizens.citizens_by_id[PRIMARY_ID]
	var captured_reserved: CitizenData = captured_raw.citizens.citizens_by_id[RESERVED_ID]
	_check(captured_primary.employment_status == CitizenData.EmploymentStatus.HIRED,
		"New capture saves an idle, unreserved ASSIGNED citizen as HIRED.")
	_check(captured_reserved.employment_status == CitizenData.EmploymentStatus.ASSIGNED
		and captured_raw.workers.workers_by_id[RESERVED_ID].is_reserved(),
		"Capture preserves the ASSIGNED status of a worker with a real active reservation.")
	_check(_snapshot_difference(live_primary_before, values.encode(primary_citizen), "$live_primary").is_empty()
		and primary_citizen.employment_status == CitizenData.EmploymentStatus.ASSIGNED,
		"Capture leaves the live draft citizen unchanged as ASSIGNED.")
	_check(_snapshot_difference(live_worker_before, values.encode(primary), "$live_worker").is_empty()
		and _snapshot_difference(live_reserved_citizen_before, values.encode(reserved_citizen), "$live_reserved_citizen").is_empty()
		and _snapshot_difference(live_reserved_worker_before, values.encode(reserved), "$live_reserved_worker").is_empty(),
		"Capture does not mutate either worker's payroll fields, reservation, XP, or other citizen fields.")
	_check(Inventory.items == wallet_before and CityStockManager.treasury_shekel == city_cash_before,
		"Capture leaves wallet and city balances unchanged.")
	if failures > 0:
		return

	_test_v6_prepare_probe(captured, city, store, primary, reserved, values)
	if failures > 0:
		return
	var management = WORKER_MANAGEMENT.new()
	management.storage = WorkStateRuntime.get_node("CityToolStorage")
	management.schedule = city.get_node("YSortWorld/WorkerRuntime").daily
	_check(management.fire(PRIMARY_ID) == "Release the workshop assignment first."
		and WorkerDatabase.has_worker_data(PRIMARY_ID)
		and primary_citizen.employment_status == CitizenData.EmploymentStatus.ASSIGNED,
		"Before load, the live draft still blocks dismissal and remains guarded as ASSIGNED.")
	if failures > 0:
		return
	_check(store.save_checkpoint(), "The real CitySave owner writes the canonical checkpoint: " + store.last_error)
	if not FileAccess.file_exists(CHECKPOINT_PATH):
		_check(false, "The fixture checkpoint exists after the real save.")
		return
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	var serialized_expected: Variant = JSON.parse_string(JSON.stringify(captured, "\t", true, true))
	_check(disk is Dictionary and serialized_expected is Dictionary
		and _snapshot_difference(serialized_expected, disk, "$.checkpoint").is_empty(),
		"The persisted v6 document exactly matches the canonical New Game capture.")


func _grant_paid_period(worker: WorkerData, rate: int) -> void:
	# Explicit fixture-only payroll entitlement; no clock settlement or gameplay rate is changed.
	worker.payroll_start_day = 2
	worker.payroll_paid_from_day = 2
	worker.payroll_paid_until_day = 2 + PERIOD_DAYS - 1
	worker.payroll_period_rate = rate
	worker.payroll_last_attempt_day = 2


func _test_v6_prepare_probe(
	captured: Dictionary,
	city: Node,
	store: Node,
	primary: WorkerData,
	reserved: WorkerData,
	values: CitySaveValues
) -> void:
	var legacy_document: Dictionary = captured.duplicate(true)
	var legacy_raw: Dictionary = values.decode(legacy_document.state)
	# This is the stale v6 shape written before the correction: an idle draft remained ASSIGNED.
	legacy_raw.citizens.citizens_by_id[PRIMARY_ID].employment_status = CitizenData.EmploymentStatus.ASSIGNED
	# Advance only the probe's document clock beyond the active order's paid period.
	# The live world remains frozen and unchanged; the running order is therefore a payroll-paused preservation case.
	var paused_worker: WorkerData = legacy_raw.workers.workers_by_id[RESERVED_ID]
	legacy_raw.clock.current_day = paused_worker.payroll_paid_until_day + 1
	legacy_raw.clock.current_hour = 8
	legacy_raw.clock.current_minute = 0
	legacy_document.state = values.encode(legacy_raw)
	_check(values.error.is_empty(), "Encode an old v6-shaped assigned-idle probe.")
	var supplied_document: Dictionary = legacy_document.duplicate(true)
	var live_primary_before: Variant = values.encode(primary.get_linked_citizen())
	var live_primary_worker_before: Variant = values.encode(primary)
	var live_reserved_before: Variant = values.encode(reserved)
	var wallet_before: Dictionary = Inventory.items.duplicate(true)
	var city_cash_before: int = CityStockManager.treasury_shekel
	_check(store.snapshot.prepare(legacy_document, city),
		"Prepare an old v6-shaped ASSIGNED idle checkpoint: " + store.snapshot.error)
	if not store.snapshot.prepared.is_empty():
		var prepared: Dictionary = store.snapshot.prepared
		var prepared_primary: CitizenData = prepared.citizens.citizens_by_id[PRIMARY_ID]
		var prepared_reserved: CitizenData = prepared.citizens.citizens_by_id[RESERVED_ID]
		var prepared_order_worker: WorkerData = prepared.workers.workers_by_id[RESERVED_ID]
		_check(prepared_primary.employment_status == CitizenData.EmploymentStatus.HIRED,
			"Prepare canonicalizes stale idle ASSIGNED status in a v6 document.")
		_check(prepared_reserved.employment_status == CitizenData.EmploymentStatus.ASSIGNED
			and prepared_order_worker.is_reserved()
			and prepared_order_worker.current_work_status == WorkerData.WorkStatus.WORKING
			and prepared_order_worker.payroll_paid_until_day < prepared.clock.current_day,
			"Prepare keeps a payroll-paused reserved worker ASSIGNED.")
		_check(_citizen_equal_except_employment(primary.get_linked_citizen(), prepared_primary, values)
			and _snapshot_difference(values.encode(reserved.get_linked_citizen()), values.encode(prepared_reserved), "$reserved_citizen").is_empty()
			and _snapshot_difference(values.encode(primary), values.encode(prepared.workers.workers_by_id[PRIMARY_ID]), "$primary_worker").is_empty()
			and _snapshot_difference(values.encode(reserved), values.encode(prepared_order_worker), "$reserved_worker").is_empty(),
			"Prepare changes only the idle citizen's employment status; citizen details and both payroll records remain exact.")
		_check(prepared.stock.treasury_shekel == city_cash_before
			and prepared.inventory.items == wallet_before,
			"Prepare preserves the explicitly granted city and wallet balances.")
	_check(_snapshot_difference(values.encode(primary.get_linked_citizen()), live_primary_before, "$live_primary_after_prepare").is_empty()
		and _snapshot_difference(values.encode(primary), live_primary_worker_before, "$live_primary_worker_after_prepare").is_empty()
		and _snapshot_difference(values.encode(reserved), live_reserved_before, "$live_reserved_after_prepare").is_empty(),
		"Prepare leaves all live resources untouched before load.")
	_check(_snapshot_difference(legacy_document, supplied_document, "$.supplied_v6_document").is_empty(),
		"Prepare does not mutate the supplied old v6 document.")


func _citizen_equal_except_employment(left: CitizenData, right: CitizenData, values: CitySaveValues) -> bool:
	var left_encoded: Dictionary = values.encode(left)
	var right_encoded: Dictionary = values.encode(right)
	left_encoded.fields.erase("employment_status")
	right_encoded.fields.erase("employment_status")
	return _snapshot_difference(left_encoded, right_encoded, "$citizen") == ""


func _continue_checkpoint(city: Node, store: Node) -> void:
	_check(FileAccess.file_exists(CHECKPOINT_PATH), "Continue has a fixture checkpoint on disk.")
	if not FileAccess.file_exists(CHECKPOINT_PATH):
		return
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	_check(disk is Dictionary, "The Continue checkpoint is valid JSON.")
	if not disk is Dictionary:
		return
	_check(not restored_snapshot.is_empty()
		and _snapshot_difference(restored_snapshot, disk, "$.continued").is_empty(),
		"Separate-process Continue restores every captured CitySave field exactly before clock advancement.")
	var values = VALUES.new()
	var expected: Dictionary = values.decode(disk.state)
	var primary: WorkerData = WorkerDatabase.get_worker_data(PRIMARY_ID)
	var reserved: WorkerData = WorkerDatabase.get_worker_data(RESERVED_ID)
	var primary_citizen: CitizenData = CitizenManager.get_citizen(PRIMARY_ID)
	var reserved_citizen: CitizenData = CitizenManager.get_citizen(RESERVED_ID)
	_check(primary != null and reserved != null and primary_citizen != null and reserved_citizen != null,
		"Both fixture hires and linked citizens survive Continue.")
	if primary == null or reserved == null or primary_citizen == null or reserved_citizen == null:
		return
	_check(primary_citizen.employment_status == CitizenData.EmploymentStatus.HIRED
		and reserved_citizen.employment_status == CitizenData.EmploymentStatus.ASSIGNED
		and reserved.is_reserved() and reserved.is_working(),
		"Continue restores the idle worker as HIRED and the active reserved worker as ASSIGNED.")
	_check(_snapshot_difference(values.encode(primary), values.encode(expected.workers.workers_by_id[PRIMARY_ID]), "$continued_primary_worker").is_empty()
		and _snapshot_difference(values.encode(reserved), values.encode(expected.workers.workers_by_id[RESERVED_ID]), "$continued_reserved_worker").is_empty(),
		"Continue preserves both workers' XP, work state, and payroll values.")
	var wallet_before: Dictionary = Inventory.items.duplicate(true)
	var city_cash_before: int = CityStockManager.treasury_shekel
	var control: WorkerControlUI = city.get_node("YSortWorld/WorkerRuntime/WorkerControlUI")
	control.open()
	control._show_manage(PRIMARY_ID)
	_check(not control.manage_fire_button.disabled,
		"The Worker Hub can fire the continued idle worker without workshop reselection or release.")
	if control.manage_fire_button.disabled:
		control.close()
		return
	control.manage_fire_button.pressed.emit()
	await get_tree().process_frame
	_check(control._confirmation_overlay.visible,
		"Worker Hub opens its normal dismissal confirmation directly after Continue.")
	control._confirm_yes_button.pressed.emit()
	await get_tree().process_frame
	_check(not WorkerDatabase.has_worker_data(PRIMARY_ID)
		and WorkerDatabase.dismissed_workers.has(PRIMARY_ID)
		and primary_citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED,
		"Worker Hub dismisses the idle worker through its normal confirmation action.")
	_check(WorkerDatabase.dismissed_workers.get(PRIMARY_ID).profession_xp == 17,
		"Direct post-Continue dismissal retains the worker's earned XP.")
	_check(Inventory.items == wallet_before and CityStockManager.treasury_shekel == city_cash_before,
		"Direct dismissal leaves wallet and city balances unchanged.")
	control.close()


func _snapshot_difference(left: Variant, right: Variant, path: String) -> String:
	var left_type: int = typeof(left)
	var right_type: int = typeof(right)
	if left_type == TYPE_DICTIONARY and right_type == TYPE_DICTIONARY:
		if left.size() != right.size():
			return "%s has dictionary sizes %d and %d" % [path, left.size(), right.size()]
		for key: Variant in left:
			if not right.has(key):
				return "%s.%s is missing" % [path, key]
			var nested: String = _snapshot_difference(left[key], right[key], "%s.%s" % [path, key])
			if not nested.is_empty():
				return nested
		return ""
	if left_type == TYPE_ARRAY and right_type == TYPE_ARRAY:
		if left.size() != right.size():
			return "%s has array sizes %d and %d" % [path, left.size(), right.size()]
		for index: int in range(left.size()):
			var nested: String = _snapshot_difference(left[index], right[index], "%s[%d]" % [path, index])
			if not nested.is_empty():
				return nested
		return ""
	if left_type in [TYPE_INT, TYPE_FLOAT] and right_type in [TYPE_INT, TYPE_FLOAT]:
		if left_type == right_type:
			return "" if left == right else "%s numeric values differ: %s vs %s" % [path, left, right]
		var integer_value: int = int(left) if left_type == TYPE_INT else int(right)
		if absi(integer_value) <= 9007199254740992 and float(left) == float(right):
			return ""
		return "%s numeric values differ: %s vs %s" % [path, left, right]
	if left_type != right_type or left != right:
		return "%s differs: %s vs %s" % [path, left, right]
	return ""


func _finish() -> void:
	get_tree().paused = false
	print("IdleAssignmentContinue %s: %s" % [phase, "PASS" if failures == 0 else "FAIL (%d)" % failures])
	get_tree().quit(0 if failures == 0 else 1)


func _current_total_minutes() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
