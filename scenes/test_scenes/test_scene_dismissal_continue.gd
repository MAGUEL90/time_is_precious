extends Node
## Separate-process real New Game/Continue coverage for dismissal payroll edges.
## Fixture-only rates, shekels, applicant eligibility, and clock placement are explicit.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const WORKER_MANAGEMENT: Script = preload("res://scenes/test_scenes/clay_worksite_test/clay_worker_management.gd")
const VALUES: Script = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const CHECKPOINT_PATH: String = "user://dismissal_continue/checkpoint.json"
const LABORER_ID: String = "initial_workshop_laborer"
const PENDING_HAULER_ID: String = "initial_worksite_hauler"
const UNKNOWN_WORKER_ID: String = "dismissal_missing_worker"
const LABORER_XP: int = 9
const PENDING_HAULER_XP: int = 4
const FIXTURE_WALLET_GRANT: int = 3
const INITIAL_CITY_DEPOSIT: int = 1
const PERIOD_RATE: int = 1

var failures: int = 0
var phase: String = "write"
var launched: bool = false
var payroll_change_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--dismissal-phase="):
			phase = argument.trim_prefix("--dismissal-phase=")
	_check(phase in ["write", "rehire", "pay", "expired"],
		"Known --dismissal-phase is required: write, rehire, pay, or expired.")
	if failures > 0:
		_finish()
		return

	get_tree().current_scene = null
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	WorkerDatabase.onboarding_period_rates = {
		WorkerData.Profession.LABORER: PERIOD_RATE,
		WorkerData.Profession.HAULER: PERIOD_RATE,
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
	var player: Player = city.get_node("YSortWorld/Player")
	_check(not player.debug_disable_player_needs and not player.debug_disable_fatigue,
		"The fixture keeps player needs and fatigue enabled.")
	var store: Node = WorkStateRuntime.get_node("CitySave")
	_check(store.disk.path == CHECKPOINT_PATH,
		"The real CitySave owner uses this fixture's isolated checkpoint.")
	WorkerDatabase.payroll_changed.connect(_on_payroll_changed)
	if failures == 0:
		match phase:
			"write":
				await _write_dismissals(city, store)
			"rehire":
				await _rehire_after_expiry(city, store)
			"pay":
				await _pay_rehire_once(city, store)
			"expired":
				await _dismiss_expired_rehire(city, store)
	_finish()


func _on_session_started(continued: bool) -> void:
	_check(continued == (phase != "write"),
		"The real start menu reports New Game for write and Continue for later phases.")
	if continued:
		var city: Node = get_tree().current_scene
		var store: Node = WorkStateRuntime.get_node("CitySave")
		_assert_exact_continue(city, store, phase)
	launched = true


func _write_dismissals(city: Node, store: Node) -> void:
	_check(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(),
		"Actual New Game starts without fixture inventory or hired workers.")
	_check(CityStockManager.treasury_shekel == 0,
		"Actual New Game starts without fixture city funds.")
	_place_clock(_now() - TimeComponentManager.current_hour * 60 - TimeComponentManager.current_minute + 8 * 60)
	var laborer: WorkerData = WorkerDatabase.hire_applicant(LABORER_ID, 1)
	var hauler: WorkerData = WorkerDatabase.hire_applicant(PENDING_HAULER_ID, 1)
	_check(laborer != null and hauler != null,
		"Fixture hires the two authored applicants through the WorkerDatabase API.")
	if laborer == null or hauler == null:
		return
	laborer.profession_xp = LABORER_XP
	hauler.profession_xp = PENDING_HAULER_XP
	_check(laborer.is_waiting_for_first_payment() and hauler.is_waiting_for_first_payment()
		and laborer.payroll_start_day == TimeComponentManager.current_day + 1
		and hauler.payroll_start_day == TimeComponentManager.current_day + 1,
		"Both hires are pending until tomorrow's 08:00 boundary.")

	# The fixture grants three wallet shekels, then explicitly deposits only one.
	Inventory.add_item("shekel", FIXTURE_WALLET_GRANT)
	_check(CityStockManager.deposit_wallet_shekel(INITIAL_CITY_DEPOSIT)
		and CityStockManager.treasury_shekel == INITIAL_CITY_DEPOSIT
		and Inventory.items.get("shekel", 0) == FIXTURE_WALLET_GRANT - INITIAL_CITY_DEPOSIT,
		"One explicitly deposited city shekel funds only the active Laborer's first period.")
	var management = _worker_management(city)
	var pending_quote_day: int = hauler.payroll_start_day
	_check(_fire_worker(management, PENDING_HAULER_ID, pending_quote_day, 2, 2,
		"No payment made yet.", "Pending Hauler dismissal"),
		"The pending Hauler dismissal removes its first-payday quote.")
	_check(WorkerDatabase.dismissed_workers.has(PENDING_HAULER_ID)
		and WorkerDatabase.dismissed_workers[PENDING_HAULER_ID].profession_xp == PENDING_HAULER_XP
		and WorkerDatabase.dismissed_workers[PENDING_HAULER_ID].payroll_paid_from_day == -1,
		"Pending dismissal archives XP and its unpaid first-period state.")

	var first_boundary: int = laborer.payroll_start_day * 1440 + 8 * 60
	_place_clock(first_boundary - 1)
	TimeComponentManager.advance_minutes(1)
	_check(_now() == first_boundary and laborer.payroll_paid_from_day == laborer.payroll_start_day
		and laborer.payroll_paid_until_day == laborer.payroll_start_day + 6
		and laborer.payroll_period_rate == PERIOD_RATE
		and CityStockManager.treasury_shekel == 0,
		"The elapsed 08:00 boundary pays only the active Laborer; the pending dismissal costs nothing.")
	_check(Inventory.items.get("shekel", 0) == FIXTURE_WALLET_GRANT - INITIAL_CITY_DEPOSIT,
		"The automatic payroll payment does not read or alter the personal wallet.")
	_check(_fire_worker(management, LABORER_ID, laborer.payroll_paid_until_day + 1, 1, 1,
		"Unused pay is not refunded.", "Paid Laborer dismissal"),
		"The paid idle Laborer dismissal removes its future renewal quote.")
	_check(CityStockManager.treasury_shekel == 0
		and Inventory.items.get("shekel", 0) == FIXTURE_WALLET_GRANT - INITIAL_CITY_DEPOSIT,
		"Dismissing a paid worker refunds neither city funds nor wallet shekels.")
	_check(WorkerDatabase.dismissed_workers.has(LABORER_ID)
		and WorkerDatabase.dismissed_workers[LABORER_ID].profession_xp == LABORER_XP
		and WorkerDatabase.dismissed_workers[LABORER_ID].payroll_paid_from_day == laborer.payroll_paid_from_day
		and WorkerDatabase.get_worker_data(LABORER_ID) == null,
		"Paid dismissal archives XP and prepaid dates while removing the worker from payroll.")
	_test_dismissed_worker_plot_validation(city, store)
	_save_and_assert_checkpoint(city, store, "paid and pending dismissals")


func _rehire_after_expiry(city: Node, store: Node) -> void:
	var dismissed: WorkerData = WorkerDatabase.dismissed_workers.get(LABORER_ID)
	var pending: WorkerData = WorkerDatabase.dismissed_workers.get(PENDING_HAULER_ID)
	_check(dismissed != null and pending != null and WorkerDatabase.get_all_workers().is_empty(),
		"Continue restores both archived workers and an empty hired roster.")
	if dismissed == null or pending == null:
		return
	_check(dismissed.profession_xp == LABORER_XP and dismissed.payroll_paid_from_day >= 0
		and pending.profession_xp == PENDING_HAULER_XP and pending.payroll_paid_from_day == -1,
		"Continue preserves paid and pending dismissal records with their XP.")
	var city_cash_before: int = CityStockManager.treasury_shekel
	var wallet_before: int = Inventory.items.get("shekel", 0)
	var expiry_boundary: int = (dismissed.payroll_paid_until_day + 1) * 1440 + 8 * 60
	_place_clock(expiry_boundary - 1)
	TimeComponentManager.advance_minutes(1)
	_check(_now() == expiry_boundary and WorkerDatabase.get_all_workers().is_empty()
		and CityStockManager.treasury_shekel == city_cash_before
		and Inventory.items.get("shekel", 0) == wallet_before,
		"After Continue, the dismissed paid and pending workers draw no payroll at the next due morning.")

	var citizen: CitizenData = CitizenManager.get_citizen(LABORER_ID)
	_check(citizen != null and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED,
		"Dismissal restores the Laborer's linked citizen to unemployed status.")
	if citizen == null:
		return
	# Restore the authored applicant threshold as an explicit fixture eligibility grant.
	citizen.satisfaction = maxf(citizen.satisfaction, CitizenData.MIN_APPLICANT_SATISFACTION)
	_check(CitizenManager.register_applicant(LABORER_ID, WorkerData.Profession.LABORER),
		"The fixture makes the dismissed citizen an eligible applicant through CitizenManager.")
	var rehired: WorkerData = WorkerDatabase.hire_applicant(LABORER_ID, 3)
	_check(rehired != null, "The same citizen can be rehired through the WorkerDatabase API.")
	if rehired == null:
		return
	_check(rehired.profession_xp == LABORER_XP and rehired.payroll_start_day == TimeComponentManager.current_day + 1
		and rehired.is_waiting_for_first_payment() and rehired.payroll_paid_from_day == -1
		and rehired.payroll_paid_until_day == -1 and rehired.payroll_period_rate == 0
		and rehired.payroll_last_attempt_day == -1,
		"Rehire preserves XP, starts tomorrow, and clears all old paid-period entitlement fields.")
	_check(not WorkerDatabase.dismissed_workers.has(LABORER_ID),
		"Successful rehire removes the worker from the dismissed archive.")
	_check(CityStockManager.deposit_wallet_shekel(1)
		and CityStockManager.treasury_shekel == 1
		and Inventory.items.get("shekel", 0) == wallet_before - 1,
		"The fixture explicitly deposits one shekel to fund the pending rehire.")
	_save_and_assert_checkpoint(city, store, "pending rehire")


func _pay_rehire_once(city: Node, store: Node) -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	var pending: WorkerData = WorkerDatabase.dismissed_workers.get(PENDING_HAULER_ID)
	_check(worker != null and worker.is_waiting_for_first_payment()
		and worker.payroll_start_day == TimeComponentManager.current_day + 1
		and pending != null and pending.payroll_paid_from_day == -1,
		"Continue restores the pending rehire and unpaid pending dismissal exactly.")
	if worker == null or pending == null:
		return
	var city_cash_before: int = CityStockManager.treasury_shekel
	var wallet_before: int = Inventory.items.get("shekel", 0)
	_check(city_cash_before == 1, "The pending rehire has one explicit city shekel available.")
	var boundary: int = worker.payroll_start_day * 1440 + 8 * 60
	_place_clock(boundary - 1)
	var event_count_before: int = payroll_change_count
	TimeComponentManager.advance_minutes(1)
	_check(_now() == boundary and worker.payroll_paid_from_day == worker.payroll_start_day
		and worker.payroll_paid_until_day == worker.payroll_start_day + 6
		and worker.payroll_period_rate == PERIOD_RATE
		and worker.payroll_last_attempt_day == worker.payroll_start_day,
		"Continue pays the rehired worker exactly once at the next elapsed 08:00 boundary.")
	_check(CityStockManager.treasury_shekel == city_cash_before - PERIOD_RATE
		and Inventory.items.get("shekel", 0) == wallet_before,
		"The rehire payment spends only its one city shekel and leaves the wallet unchanged.")
	_check(payroll_change_count == event_count_before + 1,
		"One successful payroll settlement emits one payroll_changed refresh.")
	var event_count_after_payment: int = payroll_change_count
	TimeComponentManager.emit_time_signal()
	TimeComponentManager.hour_changed.emit(8)
	_check(CityStockManager.treasury_shekel == city_cash_before - PERIOD_RATE
		and payroll_change_count == event_count_after_payment,
		"A same-day signal replay neither charges twice nor emits a second settlement refresh.")
	_check(WorkerDatabase.dismissed_workers[PENDING_HAULER_ID].payroll_paid_from_day == -1,
		"The pending dismissed Hauler remains unpaid while the rehire is paid.")
	_save_and_assert_checkpoint(city, store, "paid rehire")


func _dismiss_expired_rehire(city: Node, store: Node) -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	_check(worker != null and worker.payroll_paid_from_day >= 0,
		"Continue restores the paid rehire before its next renewal attempt.")
	if worker == null:
		return
	var boundary: int = (worker.payroll_paid_until_day + 1) * 1440 + 8 * 60
	_place_clock(boundary - 1)
	TimeComponentManager.advance_minutes(1)
	_check(_now() == boundary and worker.is_payroll_blocked()
		and worker.payroll_last_attempt_day == TimeComponentManager.current_day
		and CityStockManager.treasury_shekel == 0,
		"An unfunded elapsed renewal leaves the active worker's entitlement expired.")
	var management = _worker_management(city)
	_check(_fire_worker(management, LABORER_ID, TimeComponentManager.current_day, 1, 1,
		"Paid period has ended. No refund.", "Expired rehire dismissal"),
		"The expired idle worker dismissal removes its failed renewal quote.")
	var archived: WorkerData = WorkerDatabase.dismissed_workers.get(LABORER_ID)
	_check(archived != null and archived.payroll_paid_until_day < TimeComponentManager.current_day
		and archived.payroll_last_attempt_day == TimeComponentManager.current_day,
		"Expired dismissal keeps the prior paid dates and failed attempt in the archive.")
	var wallet_before: int = Inventory.items.get("shekel", 0)
	_check(CityStockManager.treasury_shekel == 0 and wallet_before == 1,
		"Expired dismissal leaves city and wallet balances unchanged.")
	_check(CityStockManager.deposit_wallet_shekel(1)
		and CityStockManager.treasury_shekel == 1
		and Inventory.items.get("shekel", 0) == wallet_before - 1,
		"The fixture explicitly tops up city funds after dismissing the expired worker.")
	var next_boundary: int = (TimeComponentManager.current_day + 1) * 1440 + 8 * 60
	_place_clock(next_boundary - 1)
	TimeComponentManager.advance_minutes(1)
	_check(_now() == next_boundary and WorkerDatabase.get_all_workers().is_empty()
		and CityStockManager.treasury_shekel == 1,
		"A funded next morning skips the expired dismissed worker without another payroll charge.")
	_save_and_assert_checkpoint(city, store, "expired dismissal after top-up")


func _worker_management(city: Node):
	var management = WORKER_MANAGEMENT.new()
	management.storage = WorkStateRuntime.get_node("CityToolStorage")
	management.schedule = city.get_node("YSortWorld/WorkerRuntime").daily
	return management


func _fire_worker(management, worker_id: String, quote_day: int, before_count: int,
	before_total: int, warning_fragment: String, label: String) -> bool:
	var warning: String = _dismissal_warning(management.rows(), worker_id)
	_check(warning.contains(warning_fragment),
		"%s presents the expected dismissal payroll warning: %s" % [label, warning])
	var before_quote: Dictionary = WorkerDatabase.get_payroll_quote(quote_day)
	_check(int(before_quote.count) == before_count and int(before_quote.total) == before_total,
		"%s begins with the expected next payroll quote." % label)
	var events_before: int = payroll_change_count
	var result: String = management.fire(worker_id)
	_check(result == "Worker fired. Tools returned to City Storage.",
		"%s uses clay_worker_management.fire successfully." % label)
	_check(payroll_change_count == events_before + 1,
		"%s emits payroll_changed once so the payroll quote refreshes." % label)
	var after_quote: Dictionary = WorkerDatabase.get_payroll_quote(quote_day)
	_check(int(after_quote.count) == before_count - 1 and int(after_quote.total) == before_total - PERIOD_RATE,
		"%s removes the dismissed worker from the next payroll quote." % label)
	return result == "Worker fired. Tools returned to City Storage."


func _dismissal_warning(rows: Array[Dictionary], worker_id: String) -> String:
	for row: Dictionary in rows:
		if str(row.get("id", "")) == worker_id:
			return str(row.get("dismissal_payroll_warning", ""))
	return ""


func _on_payroll_changed() -> void:
	payroll_change_count += 1


func _test_dismissed_worker_plot_validation(city: Node, store: Node) -> void:
	var current: Dictionary = store.snapshot.capture(city)
	_check(not current.is_empty(), "Capture the live map before isolated plot validation probes.")
	if current.is_empty():
		return
	var built_case: Dictionary = _plot_worker_case(current, "built", LABORER_ID)
	var building_case: Dictionary = _plot_worker_case(current, "building", LABORER_ID)
	var unknown_case: Dictionary = _plot_worker_case(current, "built", UNKNOWN_WORKER_ID)
	_check(not built_case.is_empty() and store.snapshot.prepare(built_case, city),
		"A completed plot may retain the ID of a dismissed archived worker.")
	_check(not building_case.is_empty() and not store.snapshot.prepare(building_case, city),
		"An in-progress plot cannot retain a worker who is no longer hired.")
	_check(not unknown_case.is_empty() and not store.snapshot.prepare(unknown_case, city),
		"A completed plot cannot retain an ID absent from both worker rosters.")
	_check(_snapshot_difference(store.snapshot.capture(city), current, "$").is_empty(),
		"Isolated plot validation probes do not mutate the live map.")
	_check(store.snapshot.prepare(current, city),
		"Restore the live snapshot as the validator's prepared state after the negative probes.")


func _plot_worker_case(document: Dictionary, phase_name: String, worker_id: String) -> Dictionary:
	var changed: Dictionary = document.duplicate(true)
	var values = VALUES.new()
	var raw: Dictionary = values.decode(changed.state)
	if not values.error.is_empty() or raw.plots.is_empty():
		_check(false, "Decode a snapshot with at least one workshop plot for validation probes.")
		return {}
	var plot_id: String = str(raw.plots.keys()[0])
	var plot: Dictionary = raw.plots[plot_id]
	plot["phase"] = phase_name
	plot["worker_ids"] = [worker_id]
	changed["state"] = values.encode(raw)
	if not values.error.is_empty():
		_check(false, "Encode the isolated %s plot validation case: %s" % [phase_name, values.error])
		return {}
	return changed


func _assert_exact_continue(city: Node, store: Node, label: String) -> void:
	if not FileAccess.file_exists(CHECKPOINT_PATH):
		_check(false, "The %s Continue checkpoint exists on disk." % label)
		return
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	_check(disk is Dictionary, "The %s Continue checkpoint is valid JSON." % label)
	if not disk is Dictionary:
		return
	var restored: Dictionary = store.snapshot.capture(city)
	var difference: String = _snapshot_difference(restored, disk, "$")
	_check(difference.is_empty(),
		"Separate-process %s Continue restores every captured CitySave field exactly before elapsed time. %s" % [label, difference])


func _save_and_assert_checkpoint(city: Node, store: Node, label: String) -> void:
	var expected: Dictionary = store.snapshot.capture(city)
	var saved: bool = store.save_checkpoint()
	_check(saved, "Save the %s full CitySave checkpoint: %s" % [label, store.last_error])
	if not saved:
		return
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	var serialized_expected: Variant = JSON.parse_string(JSON.stringify(expected, "\t", true, true))
	var difference: String = _snapshot_difference(serialized_expected, disk, "$") if disk is Dictionary else "checkpoint is not a dictionary"
	_check(difference.is_empty(),
		"The %s pre-save full CitySave capture matches its persisted checkpoint. %s" % [label, difference])


func _snapshot_difference(left: Variant, right: Variant, path: String) -> String:
	var left_type: int = typeof(left)
	var right_type: int = typeof(right)
	if left_type == TYPE_DICTIONARY and right_type == TYPE_DICTIONARY:
		if left.size() != right.size():
			return "%s has dictionary sizes %d and %d" % [path, left.size(), right.size()]
		for key: Variant in left:
			if not right.has(key):
				return "%s.%s is missing from the persisted snapshot" % [path, key]
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


func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute


func _place_clock(target_minute: int) -> void:
	TimeComponentManager.current_day = floori(float(target_minute) / 1440.0)
	var minute_of_day: int = target_minute % 1440
	TimeComponentManager.current_hour = minute_of_day / 60
	TimeComponentManager.current_minute = minute_of_day % 60
	TimeComponentManager._timer = 0.0
	TimeComponentManager.emit_time_signal()


func _finish() -> void:
	get_tree().paused = false
	print("DismissalContinue %s: %s" % [phase, "PASS" if failures == 0 else "FAIL (%d)" % failures])
	get_tree().quit(0 if failures == 0 else 1)
