extends Node
## Separate-process payroll-renewal fixture using the real New Game and Continue
## paths. Its shekels, one raw input, and long recipe are test-only grants.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const CHECKPOINT_PATH: String = "user://renewal_continue/checkpoint.json"
const LABORER_ID: String = "initial_workshop_laborer"
const HAULER_ID: String = "initial_worksite_hauler"
const PLOT_LABORER_ID: String = "renewal_plot_laborer"
const RECIPE_ID: String = "renewal_continue_long_job"
const PERIOD_RATE: int = 1
const JOB_MINUTES: int = 8 * 1440
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")

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
		if argument.begins_with("--renewal-phase="):
			phase = argument.trim_prefix("--renewal-phase=")
	_check(phase in ["write", "expire", "resume", "finish"], "Known --renewal-phase is required.")
	if failures > 0:
		_finish()
		return

	get_tree().current_scene = null
	TimeComponentManager.set_process(false)
	WorkerDatabase.onboarding_period_rates = {
		WorkerData.Profession.LABORER: PERIOD_RATE,
		WorkerData.Profession.HAULER: PERIOD_RATE,
	}
	if phase == "write":
		_check(not FileAccess.file_exists(CHECKPOINT_PATH),
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
	_check(store.disk.path == CHECKPOINT_PATH,
		"The real city save owner uses the isolated renewal fixture checkpoint.")

	if phase == "write":
		await _write_paid_checkpoint(city, store)
	else:
		_check(_assert_exact_continue(city, store, phase),
			"Continue must restore the complete checkpoint before the %s phase." % phase)
		if failures == 0:
			if phase == "expire":
				await _expire_period(city, store)
			elif phase == "resume":
				await _deposit_and_resume(store)
			else:
				await _finish_remaining_work(store)
	_finish()


func _on_session_started(_continued: bool) -> void:
	launched = true


func _write_paid_checkpoint(city: Node, store: Node) -> void:
	_check(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(),
		"Real New Game begins without fixture inventory or hired workers.")
	var day: int = TimeComponentManager.current_day
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = 16
	TimeComponentManager.current_minute = 59
	TimeComponentManager.current_weather = "clear"
	TimeComponentManager._timer = 0.0
	TimeComponentManager.emit_time_signal()
	var worker: WorkerData = WorkerDatabase.hire_applicant(LABORER_ID, 1)
	var hauler: WorkerData = WorkerDatabase.hire_applicant(HAULER_ID, 1)
	_check(worker != null and hauler != null
		and worker.is_waiting_for_first_payment() and hauler.is_waiting_for_first_payment(),
		"The authored Laborer and Hauler remain pending after fixture hiring.")
	if worker == null or hauler == null:
		return

	# Fixture-only wallet funding covers the staggered first periods and one later
	# explicit group deposit. No passive income or automatic transfer occurs.
	Inventory.add_item("shekel", 6)
	_check(CityStockManager.deposit_wallet_shekel(2),
		"The fixture explicitly deposits two wallet shekels for the first two workers.")
	_check(CityStockManager.treasury_shekel == 2 and Inventory.items.get("shekel", 0) == 4,
		"The initial fixture grant is split between city cash and the player's wallet.")

	TimeComponentManager.current_day = worker.payroll_start_day
	TimeComponentManager.current_hour = 7
	TimeComponentManager.current_minute = 59
	TimeComponentManager._timer = 0.0
	TimeComponentManager.emit_time_signal()
	TimeComponentManager.advance_minutes(1)
	_check(TimeComponentManager.current_hour == 8 and TimeComponentManager.current_minute == 0,
		"The first paid period begins on one real elapsed 08:00 boundary.")
	_check(not worker.is_payroll_blocked() and not hauler.is_payroll_blocked()
		and worker.payroll_paid_from_day == TimeComponentManager.current_day
		and hauler.payroll_paid_from_day == TimeComponentManager.current_day
		and worker.payroll_paid_until_day == worker.payroll_paid_from_day + 6
		and hauler.payroll_paid_until_day == hauler.payroll_paid_from_day + 6
		and worker.payroll_period_rate == PERIOD_RATE,
		"The authored Laborer and Hauler receive prepaid seven-day periods.")
	_check(CityStockManager.treasury_shekel == 0 and Inventory.items.get("shekel", 0) == 4,
		"Only the two deposited city shekels pay the first periods.")
	if failures > 0:
		return

	Inventory.add_item("clay_lump", 1)
	var recipe: JobData = _long_recipe()
	_check(WorkerDatabase.assign_worker(LABORER_ID), "The paid Laborer can be assigned.")
	var order_id: String = WorkManager.start_job(
		recipe, WorkOrder.Worker_Type.NPC, LABORER_ID, null, Inventory, Inventory, 0, 1
	)
	_check(not order_id.is_empty() and WorkManager.active_orders.size() == 1,
		"The paid Laborer starts the long-running authored work-manager fixture order.")
	_check(Inventory.items.get("clay_lump", 0) == 0,
		"The work order consumes its single test input exactly once at start.")
	var active_worker: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	_check(active_worker.current_order_id == order_id and active_worker.is_working(),
		"The NPC keeps its real WorkManager assignment for the whole order.")
	if failures > 0:
		return

	var city_plot: Node = city.get_node("YSortWorld/WorkshopPlot")
	var construction: Node = city_plot.construction
	var hauler_ids: Array[String] = [HAULER_ID]
	_check(bool(construction.start_clearing(hauler_ids, false).get("success", false)),
		"The paid Hauler starts clearing the authored construction site.")
	TimeComponentManager.advance_minutes(construction.CLEARING_MINUTES)
	_check(construction.phase == "empty", "The authored construction site clears through elapsed time.")
	if construction.phase != "empty":
		return

	# A third authored-like applicant is a fixture worker. Hiring it one day later
	# creates a real one-day payroll offset, so the construction team is mixed at
	# the first worker's renewal boundary.
	var fixture_applicant: CitizenData = CitizenData.new()
	fixture_applicant.citizen_id = PLOT_LABORER_ID
	fixture_applicant.display_name = "Renewal Plot Laborer"
	fixture_applicant.population_status = CitizenData.PopulationStatus.RESIDENT
	CitizenManager.add_citizen(fixture_applicant)
	_check(CitizenManager.register_applicant(PLOT_LABORER_ID, WorkerData.Profession.LABORER),
		"The clearly labeled plot fixture worker registers as a Laborer applicant.")
	var plot_laborer: WorkerData = WorkerDatabase.hire_applicant(PLOT_LABORER_ID, 1)
	_check(plot_laborer != null and plot_laborer.payroll_start_day == TimeComponentManager.current_day + 1,
		"The plot fixture worker starts payroll one day after the authored pair.")
	if plot_laborer == null:
		return
	_check(CityStockManager.deposit_wallet_shekel(1),
		"The fixture explicitly deposits one wallet shekel for the staggered hire.")
	Inventory.add_bulk_item({"wood_log": 6, "clay_lump": 12, "reed_bundle": 8})
	var next_start: int = plot_laborer.payroll_start_day * 1440 + 479
	_place_clock(next_start)
	TimeComponentManager.advance_minutes(1)
	_check(not plot_laborer.is_payroll_blocked()
		and plot_laborer.payroll_paid_until_day == plot_laborer.payroll_paid_from_day + 6,
		"The staggered plot worker receives its real seven-day first payment.")
	_check(CityStockManager.treasury_shekel == 0,
		"The staggered hire uses only its explicit one-shekel city deposit.")

	# Start two-worker construction one minute before the Hauler expires. At 08:01
	# exactly one paid worker-minute remains modulo the team size.
	var build_at: int = (worker.payroll_paid_until_day + 1) * 1440 + 479
	_place_clock(build_at)
	var build_ids: Array[String] = [HAULER_ID, PLOT_LABORER_ID]
	var build_result: Dictionary = construction.start_build(build_ids)
	_check(bool(build_result.get("success", false)),
		"The two paid fixture workers start the authored main Workshop construction.")
	if not bool(build_result.get("success", false)):
		return
	TimeComponentManager.advance_minutes(1)
	_check(_now() == (worker.payroll_paid_until_day + 1) * 1440 + 480
		and worker.is_payroll_blocked() and hauler.is_payroll_blocked()
		and construction.payroll_work_remainder == 0,
		"At the exact renewal boundary, expired workers pause and the mixed team has no fractional minute yet.")
	TimeComponentManager.advance_minutes(1)
	_check(_now() == build_at + 2 and construction.payroll_work_remainder == 1,
		"At 08:01, mixed paid/unpaid construction stores one fractional team minute.")
	_check(hauler.is_payroll_blocked() and not plot_laborer.is_payroll_blocked()
		and construction.worker_ids == build_ids,
		"The expired Hauler remains assigned beside the still-paid fixture Laborer.")
	_check(worker.current_order_id == order_id and worker.is_working()
		and construction.worker_ids.find(worker.worker_id) == -1,
		"The paused WorkManager order and construction team use separate workers.")
	_check(Inventory.items.get("wood_log", 0) == 0
		and Inventory.items.get("clay_lump", 0) == 0
		and Inventory.items.get("reed_bundle", 0) == 0,
		"Construction consumes each fixture material once while the WorkManager input remains consumed.")
	# Test clock placement skips interim daily settlement, but real elapsed-time
	# consumers receive the full interval and 08:00 payroll uses its actual callback.
	if failures == 0:
		_check(store.save_checkpoint(), "Save the paid work checkpoint: " + store.last_error)


func _expire_period(city: Node, store: Node) -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	var hauler: WorkerData = WorkerDatabase.get_worker_data(HAULER_ID)
	var plot_laborer: WorkerData = WorkerDatabase.get_worker_data(PLOT_LABORER_ID)
	var order: WorkOrder = _active_order()
	var construction: Node = city.get_node("YSortWorld/WorkshopPlot").construction
	if worker == null or hauler == null or plot_laborer == null or order == null:
		_check(false, "Continue restores all workers and the active WorkOrder.")
		return
	_check(_now() == (worker.payroll_paid_until_day + 1) * 1440 + 481,
		"Continue reopens immediately after the exact unpaid 08:00 boundary.")
	_check(worker.current_order_id == order.order_id and worker.is_working(),
		"The NPC assignment survives Continue before payroll expiration.")
	_check(Inventory.items.get("clay_lump", 0) == 0,
		"Continue does not restore or consume the already-consumed recipe input again.")
	_check(worker.is_payroll_blocked()
		and worker.payroll_last_attempt_day == worker.payroll_paid_until_day + 1
		and worker.payroll_paid_from_day < worker.payroll_paid_until_day + 1,
		"An unfunded renewal pauses the worker without changing its paid interval.")
	_check(worker.current_order_id == order.order_id and worker.is_working()
		and WorkManager.active_orders.size() == 1,
		"The expired worker remains assigned to the same active NPC job.")
	_check(is_equal_approx(_progress_ratio(), 7.0 / 8.0),
		"The job advances for its seven paid days, then stops at seven-eighths progress.")
	_check(hauler.is_payroll_blocked() and not plot_laborer.is_payroll_blocked()
		and construction.phase == "building" and construction.payroll_work_remainder == 1,
		"The Continue snapshot preserves the two-worker mixed-pay remainder of one.")
	_check(Inventory.items.get("clay_lump", 0) == 0,
		"The unpaid boundary never consumes the recipe input a second time.")
	_check(CityStockManager.treasury_shekel == 0 and Inventory.items.get("shekel", 0) == 3,
		"No city funds means no renewal charge; the remaining wallet shekels stay explicit.")
	if failures == 0:
		_check(store.save_checkpoint(), "Save the paused renewal checkpoint: " + store.last_error)


func _deposit_and_resume(store: Node) -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	var hauler: WorkerData = WorkerDatabase.get_worker_data(HAULER_ID)
	var plot_laborer: WorkerData = WorkerDatabase.get_worker_data(PLOT_LABORER_ID)
	var order: WorkOrder = _active_order()
	var city: Node = get_tree().current_scene
	var construction: Node = city.get_node("YSortWorld/WorkshopPlot").construction
	if worker == null or hauler == null or plot_laborer == null or order == null:
		_check(false, "Continue restores all unpaid workers and the active WorkOrder.")
		return
	_check(worker.is_payroll_blocked() and worker.current_order_id == order.order_id,
		"The exact paused snapshot retains the assignment and payroll pause.")
	_check(is_equal_approx(_progress_ratio(), 7.0 / 8.0)
		and Inventory.items.get("clay_lump", 0) == 0,
		"Continue preserves frozen progress and the one-time input consumption.")
	_check(construction.payroll_work_remainder == 1
		and construction.worker_ids == [HAULER_ID, PLOT_LABORER_ID],
		"A separate Continue restores the mixed construction team's fractional worker-minute.")
	var end_before: int = order.end_time_total_minutes
	var midday: int = (worker.payroll_paid_until_day + 1) * 1440 + 12 * 60
	_place_clock(midday)
	_check(_now() == midday,
		"The fixture reaches midday after the failed morning renewal.")
	_check(is_equal_approx(_progress_ratio(), 7.0 / 8.0)
		and order.end_time_total_minutes == end_before + (midday - ((worker.payroll_paid_until_day + 1) * 1440 + 481)),
		"The expired WorkManager job stays frozen while unpaid minutes extend its end.")
	var next_day: int = TimeComponentManager.current_day + 1
	var next_quote: Dictionary = WorkerDatabase.get_payroll_quote(next_day)
	_check(next_quote.count == 3 and next_quote.total == 3 and next_quote.shortfall == 3,
		"The next morning quote includes all three workers due as one indivisible batch.")
	_check(CityStockManager.deposit_wallet_shekel(3),
		"The player explicitly deposits the fixture funds for the full waiting payroll group at midday.")
	var funded_quote: Dictionary = WorkerDatabase.get_payroll_quote(next_day)
	_check(funded_quote.count == 3 and funded_quote.total == 3 and funded_quote.shortfall == 0,
		"The explicit deposit funds all three workers as a single batch.")
	TimeComponentManager.advance_minutes(60)
	_check(is_equal_approx(_progress_ratio(), 7.0 / 8.0)
		and order.end_time_total_minutes == end_before + 60 + (midday - ((worker.payroll_paid_until_day + 1) * 1440 + 481)),
		"A midday deposit cannot restart the job; unpaid elapsed time only extends its end.")
	var next_morning: int = (worker.payroll_paid_until_day + 2) * 1440 + 480
	_place_clock(next_morning - 1)
	TimeComponentManager.advance_minutes(1)
	_check(_now() == next_morning and not worker.is_payroll_blocked(),
		"The next elapsed 08:00 boundary resumes work after one explicit deposit.")
	_check(worker.payroll_paid_from_day == TimeComponentManager.current_day
		and worker.payroll_paid_until_day == TimeComponentManager.current_day + 6
		and worker.payroll_period_rate == PERIOD_RATE
		and hauler.payroll_paid_from_day == TimeComponentManager.current_day
		and hauler.payroll_paid_until_day == TimeComponentManager.current_day + 6
		and plot_laborer.payroll_paid_from_day == TimeComponentManager.current_day
		and plot_laborer.payroll_paid_until_day == TimeComponentManager.current_day + 6,
		"The complete waiting group receives fresh seven-day periods on the next morning.")
	_check(worker.current_order_id == order.order_id and WorkManager.active_orders.size() == 1,
		"Renewal preserves the same assigned order instead of creating a replacement.")
	_check(CityStockManager.treasury_shekel == 0 and Inventory.items.get("shekel", 0) == 0,
		"The explicit deposit pays the full waiting group once, with no arrears or later wallet withdrawal.")
	_check(order.end_time_total_minutes - _now() == 24 * 60,
		"The resumed job has only its one remaining paid workday left.")
	_check(hauler.payroll_paid_from_day == TimeComponentManager.current_day
		and plot_laborer.payroll_paid_from_day == TimeComponentManager.current_day
		and construction.worker_ids == [HAULER_ID, PLOT_LABORER_ID],
		"All waiting employees resume together while construction keeps its original team.")
	_check(Inventory.items.get("clay_lump", 0) == 0,
		"Renewal does not re-consume the original input.")
	if failures == 0:
		_check(store.save_checkpoint(), "Save the renewed active-work checkpoint: " + store.last_error)


func _finish_remaining_work(store: Node) -> void:
	var city: Node = get_tree().current_scene
	var worker: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	var order: WorkOrder = _active_order()
	if worker == null or order == null:
		_check(false, "Continue restores the renewed worker and its same active WorkOrder.")
		return
	_check(worker.current_order_id == order.order_id and not worker.is_payroll_blocked()
		and worker.payroll_paid_until_day == worker.payroll_paid_from_day + 6,
		"The resumed seven-day entitlement and assignment survive exact Continue.")
	_check(order.end_time_total_minutes - _now() == 24 * 60,
		"Continue preserves exactly one remaining workday.")
	_check(Inventory.items.get("clay_lump", 0) == 0
		and Inventory.items.get("wet_mudbrick", 0) == 0,
		"The recipe input remains consumed and output remains unclaimed before completion.")
	_test_plot_schema(city, store)
	if failures > 0:
		return
	_place_clock(_now() + 24 * 60 - 1)
	_check(WorkManager.active_orders.size() == 1 and Inventory.items.get("wet_mudbrick", 0) == 0,
		"The job does not finish one minute before its remaining work elapses.")
	TimeComponentManager.advance_minutes(1)
	_check(WorkManager.active_orders.is_empty() and worker.current_order_id.is_empty()
		and not worker.is_working(),
		"The paused NPC completes once after only its remaining paid work time.")
	_check(Inventory.items.get("wet_mudbrick", 0) == 1,
		"The resumed job produces exactly one output.")
	TimeComponentManager.advance_minutes(1)
	_check(WorkManager.active_orders.is_empty() and Inventory.items.get("wet_mudbrick", 0) == 1,
		"Further elapsed time cannot duplicate the completed output.")
	if failures == 0:
		_check(store.save_checkpoint(), "Save the completed renewal checkpoint: " + store.last_error)


func _long_recipe() -> JobData:
	var recipe: JobData = JobData.new()
	recipe.job_id = RECIPE_ID
	recipe.display_name = "Renewal Continue Test Recipe"
	recipe.short_name = "Renewal Test"
	recipe.inputs = {"clay_lump": 1}
	recipe.outputs = {"wet_mudbrick": 1}
	recipe.base_duration_minutes = JOB_MINUTES
	recipe.requirement_profession = WorkerData.Profession.LABORER
	recipe.workshop_fee_amount = 0
	return recipe


func _assert_exact_continue(city: Node, store: Node, label: String) -> bool:
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	var restored: Dictionary = store.snapshot.capture(city)
	var equal: bool = _canonical(restored) == _canonical(disk)
	_check(equal, "Separate-process %s Continue restores every captured owner exactly." % label)
	return equal


func _canonical(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))


func _test_plot_schema(city: Node, store: Node) -> void:
	var current: Dictionary = store.snapshot.capture(city)
	_check(not current.is_empty(), "Capture current schema-six state for plot migration checks.")
	if current.is_empty():
		return
	var values = VALUES.new()
	var raw: Dictionary = values.decode(current.state)
	_check(values.error.is_empty(), "Decode the actual current full snapshot for migration checks.")
	if not values.error.is_empty():
		return
	var plot_id: String = ""
	for id: String in raw.plots:
		plot_id = id
		break
	_check(not plot_id.is_empty(), "The current checkpoint contains the authored Workshop plot.")
	if plot_id.is_empty():
		return
	var treasury_before: int = CityStockManager.treasury_shekel
	var wallet_before: int = Inventory.items.get("shekel", 0)

	var malformed_raw: Dictionary = raw.duplicate(true)
	malformed_raw.plots[plot_id].erase("payroll_work_remainder")
	var malformed: Dictionary = current.duplicate(true)
	malformed.state = values.encode(malformed_raw)
	_check(not store.snapshot.prepare(malformed, city),
		"Current schema rejects a missing payroll_work_remainder.")
	malformed_raw = raw.duplicate(true)
	malformed_raw.plots[plot_id].payroll_work_remainder = -1
	malformed = current.duplicate(true)
	malformed.state = values.encode(malformed_raw)
	_check(not store.snapshot.prepare(malformed, city),
		"Current schema rejects a negative payroll_work_remainder.")
	malformed_raw = raw.duplicate(true)
	var outside_team: int = maxi(raw.plots[plot_id].worker_ids.size(), 1)
	malformed_raw.plots[plot_id].payroll_work_remainder = outside_team
	malformed = current.duplicate(true)
	malformed.state = values.encode(malformed_raw)
	_check(not store.snapshot.prepare(malformed, city),
		"Current schema rejects a remainder outside the two-worker team range.")

	# A genuine v5-shaped document removes the plot field from its encoded state,
	# while preserving the five payroll fields that v5 already knew how to store.
	var v5_raw: Dictionary = raw.duplicate(true)
	for plot: Dictionary in v5_raw.plots.values():
		plot.erase("payroll_work_remainder")
	var v5: Dictionary = current.duplicate(true)
	v5.schema_version = 5
	v5.state = values.encode(v5_raw)
	_check(store.snapshot.prepare(v5, city),
		"A real schema-five snapshot without the new plot field migrates.")
	if store.snapshot.prepared is Dictionary and not store.snapshot.prepared.is_empty():
		var migrated_worker: WorkerData = store.snapshot.prepared.workers.workers_by_id[LABORER_ID]
		var original_worker: WorkerData = raw.workers.workers_by_id[LABORER_ID]
		_check(store.snapshot.prepared.plots[plot_id].payroll_work_remainder == 0
			and migrated_worker.payroll_start_day == original_worker.payroll_start_day
			and migrated_worker.payroll_paid_from_day == original_worker.payroll_paid_from_day
			and migrated_worker.payroll_paid_until_day == original_worker.payroll_paid_until_day
			and migrated_worker.payroll_period_rate == original_worker.payroll_period_rate
			and migrated_worker.payroll_last_attempt_day == original_worker.payroll_last_attempt_day,
			"V5 injects zero plot remainder and preserves every existing payroll field without charging.")
		_check(CityStockManager.treasury_shekel == treasury_before
			and Inventory.items.get("shekel", 0) == wallet_before,
			"Preparing a legacy snapshot never charges city or wallet funds.")

	for version: int in [1, 2, 3, 4]:
		var old_raw: Dictionary = raw.duplicate(true)
		for plot: Dictionary in old_raw.plots.values():
			plot.erase("payroll_work_remainder")
		if version == 3:
			var palms: Dictionary = {}
			for id: String in old_raw.pickup_sources:
				if id.begins_with("DatePalm_"):
					palms[id] = old_raw.pickup_sources[id].duplicate(true)
					palms[id].erase("config")
			old_raw["date_palms"] = palms
		if version < 4:
			old_raw.erase("pickup_sources")
		var older: Dictionary = current.duplicate(true)
		older.schema_version = version
		if version == 1:
			older.erase("location")
		older.state = values.encode(old_raw)
		if version < 5:
			_strip_payroll(older.state)
		_check(store.snapshot.prepare(older, city),
			"Schema v%d removes the original payroll fields and migrates its own plot shape." % version)
		if store.snapshot.prepared is Dictionary and not store.snapshot.prepared.is_empty():
			var legacy_worker: WorkerData = store.snapshot.prepared.workers.workers_by_id[LABORER_ID]
			_check(legacy_worker.payroll_start_day == -1
				and legacy_worker.payroll_paid_from_day == -1
				and legacy_worker.payroll_paid_until_day == -1
				and legacy_worker.payroll_period_rate == 0
				and legacy_worker.payroll_last_attempt_day == -1,
				"Schema v%d defaults only the payroll fields absent from its original worker payload." % version)

	_check(store.snapshot.prepare(current, city),
		"Current schema-six checkpoint remains valid after migration rejection checks.")


func _strip_payroll(value: Variant) -> void:
	if value is Dictionary:
		if value.get("$type") == "object" and value.get("class") == "WorkerData":
			for field: String in VALUES.PAYROLL_FIELDS:
				value.fields.erase(field)
		for child: Variant in value.values():
			_strip_payroll(child)
	elif value is Array:
		for child: Variant in value:
			_strip_payroll(child)


func _active_order() -> WorkOrder:
	if WorkManager.active_orders.size() != 1:
		return null
	return WorkManager.active_orders.values()[0] as WorkOrder


func _progress_ratio() -> float:
	var entries: Array[Dictionary] = WorkManager.get_active_progress_entries()
	if entries.size() != 1:
		return -1.0
	return float(entries[0].get("progress_ratio", -1.0))


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
	print("RenewalContinue ", phase, ": ", "PASS" if failures == 0 else "FAIL")
	var exit_code: int = 0 if failures == 0 else 1
	var scene: Node = get_tree().current_scene
	get_tree().current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(exit_code)
