extends Node
## Separate-process real New Game/Continue coverage for a payroll-paused city Hauler.
## Only this test grants two shekels and seeds the existing 69-site/3-ground Wood fixture.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const HAULING: Script = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_hauling.gd")
const CHECKPOINT_PATH: String = "user://payroll_cargo_continue/checkpoint.json"
const HAULER_ID: String = "initial_worksite_hauler"
const CART_UNIT_ID: String = "initial_worksite_cart"
const WOOD_SITE: StringName = &"WoodSite"
const FIRST_PERIOD_RATE: int = 1
const CARGO_QUANTITY: int = 3

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
		if argument.begins_with("--cargo-phase="):
			phase = argument.trim_prefix("--cargo-phase=")
	_check(phase in ["write", "paused", "resume", "deliver"],
		"Known --cargo-phase is required: write, paused, resume, or deliver.")
	if failures > 0:
		_finish()
		return

	get_tree().current_scene = null
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	WorkerDatabase.onboarding_period_rates = {WorkerData.Profession.HAULER: FIRST_PERIOD_RATE}
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
	if phase == "write":
		await _write_paused_cargo(city, store)
	else:
		if failures == 0:
			if phase == "paused":
				await _fund_after_pause(store)
			elif phase == "resume":
				await _resume_after_next_morning(store)
			else:
				await _deliver_once(store)
	_finish()



func _on_session_started(continued: bool) -> void:
	_check(continued == (phase != "write"),
		"The real start menu reports New Game for write and Continue for later phases.")
	if continued:
		# This signal is synchronous with the real menu handoff. Capture here before
		# the next frame can populate the transient day-scoped commute cache.
		var city: Node = get_tree().current_scene
		var store: Node = WorkStateRuntime.get_node("CitySave")
		_assert_exact_continue(city, store, phase)
	launched = true


func _write_paused_cargo(city: Node, store: Node) -> void:
	_check(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(),
		"Actual New Game starts without fixture inventory or hired workers.")
	var day: int = TimeComponentManager.current_day
	_place_clock(day * 1440 + 16 * 60 + 59)
	var worker: WorkerData = WorkerDatabase.hire_applicant(HAULER_ID, 1)
	_check(worker != null and worker.is_waiting_for_first_payment()
		and worker.payroll_start_day == TimeComponentManager.current_day + 1,
		"The authored main-map Hauler is hired through the worker API and starts tomorrow.")
	if worker == null:
		return

	# The main-map start test's authored city Cart is explicitly assigned to this worker.
	var city_tools: Node = WorkStateRuntime.get_node("CityToolStorage")
	_check(city_tools.units.size() == 1 and city_tools.units.has(CART_UNIT_ID),
		"New Game supplies exactly the authored initial City Cart.")
	_check(city_tools.allocate(CART_UNIT_ID, HAULER_ID)
		and city_tools.has_equipped(HAULER_ID, "cart"),
		"The Hauler receives the real city-owned Cart before starting work.")

	# Two fixture shekels cover this Hauler's first period and one later explicit top-up.
	Inventory.add_item("shekel", 2)
	_check(CityStockManager.deposit_wallet_shekel(1)
		and CityStockManager.treasury_shekel == 1
		and Inventory.items.get("shekel", 0) == 1,
		"The fixture deposits one wallet shekel for the first seven-day period.")
	var first_paid_boundary: int = worker.payroll_start_day * 1440 + 480
	_place_clock(first_paid_boundary - 1)
	var runtime: Node = city.get_node("YSortWorld/WorkerRuntime")
	runtime.daily.last_tick = _now()
	runtime.daily.last_stock_day = TimeComponentManager.current_day
	TimeComponentManager.advance_minutes(1)
	_check(_now() == first_paid_boundary and worker.payroll_paid_from_day == worker.payroll_start_day
		and worker.payroll_paid_until_day == worker.payroll_start_day + 6
		and worker.payroll_period_rate == FIRST_PERIOD_RATE
		and CityStockManager.treasury_shekel == 0,
		"One elapsed 08:00 boundary buys the authored Hauler's first seven-day period.")
	if worker.is_payroll_blocked():
		_check(false, "The first paid period must leave the Hauler eligible for assignment.")
		return

	var destination: Node = runtime.get_node("CityStorageArea/DeliveryPoint")
	_check(runtime.daily.select_hauler(WOOD_SITE, HAULER_ID,
		runtime.get_path_to(destination), destination.display_name, CARGO_QUANTITY),
		"The actual Daily scheduler selects the paid Hauler and configured City Storage destination.")
	var marker: Marker2D = runtime.get_node("WorksiteMarkers/WoodSite")
	var started: bool = runtime.daily.start(WOOD_SITE, runtime._drop_daily_output.bind(marker))
	_check(started and runtime.daily.jobs.has(WOOD_SITE)
		and runtime.daily.jobs[WOOD_SITE].ids == [HAULER_ID],
		"The actual Daily scheduler starts and reserves the Hauler assignment.")
	if not started:
		return

	# Match the existing CitySave economy seed: 72 total wood, with 69 in the site
	# and three produced logs on the ground for the scheduled Hauler to collect.
	var session = runtime.daily.sites[WOOD_SITE]
	session.stock = 69
	_check(runtime._drop_daily_output(CARGO_QUANTITY, marker)
		and runtime._daily_output_count(WOOD_SITE) == CARGO_QUANTITY,
		"The labeled CitySave fixture seed places three real Wood pickups at the live site.")
	_place_clock((worker.payroll_paid_until_day + 1) * 1440 + 7 * 60 + 58)
	runtime.daily.last_tick = _now()
	runtime.daily.last_stock_day = TimeComponentManager.current_day
	TimeComponentManager.advance_minutes(1)
	var hauling = runtime.daily.hauling
	var route: Dictionary = hauling.routes.get(HAULER_ID, {})
	_check(_now() == (worker.payroll_paid_until_day + 1) * 1440 + 7 * 60 + 59
		and route.get("phase", "") == HAULING.PHASE_OUTBOUND
		and route.get("cargo", {}).get("item_id", "") == "wood_log"
		and int(route.get("cargo", {}).get("quantity", 0)) == CARGO_QUANTITY
		and runtime._daily_output_count(WOOD_SITE) == 0,
		"At 07:59 the actual Hauling route takes the three seeded logs into outbound cargo.")
	if route.is_empty() or route.get("phase", "") != HAULING.PHASE_OUTBOUND:
		return

	# One elapsed minute reaches the real renewal callback. Five more unpaid minutes
	# prove that route time shifts while its in-flight visual position stays fixed.
	TimeComponentManager.advance_minutes(1)
	_check(worker.is_payroll_blocked() and worker.payroll_last_attempt_day == TimeComponentManager.current_day
		and CityStockManager.treasury_shekel == 0,
		"Unfunded renewal pauses the worker at the actual next 08:00 boundary.")
	var paused_position: Vector2 = _visual_position(hauling)
	_check(_route_is_in_flight(runtime, worker, city_tools),
		"The new pause contains the original assignment, three cargo logs, and no delivery.")
	_check(paused_position.distance_to(route.origin) > 0.001
		and paused_position.distance_to(route.target) > 0.001,
		"The saved Hauler is partway between the WoodSite and real City Storage.")
	_check(_wood_total(runtime, city_tools) == 72,
		"The 69 site logs and three paused cargo logs preserve the existing 72-log fixture total.")
	TimeComponentManager.advance_minutes(5)
	_check(worker.is_payroll_blocked() and _visual_position(hauling).is_equal_approx(paused_position),
		"Five unpaid elapsed minutes leave the Hauler's world position stationary.")
	_check(_route_is_in_flight(runtime, worker, city_tools),
		"Paused elapsed time preserves the cargo, route, assigned worksite, and stock total.")
	_save_and_assert_checkpoint(city, store, "new-game pause")


func _fund_after_pause(store: Node) -> void:
	var city: Node = get_tree().current_scene
	var runtime: Node = city.get_node("YSortWorld/WorkerRuntime")
	var worker: WorkerData = WorkerDatabase.get_worker_data(HAULER_ID)
	var hauling = runtime.daily.hauling
	var before_position: Vector2 = _visual_position(hauling)
	_check(_route_is_in_flight(runtime, worker, WorkStateRuntime.get_node("CityToolStorage")),
		"Separate-process Continue restores the unpaid Hauler and its in-flight cargo.")

	# Place the fixture clock at noon, flush only the worksite scheduler's paused interval,
	# and confirm an afternoon deposit cannot resume work before the next morning.
	var noon: int = TimeComponentManager.current_day * 1440 + 12 * 60
	_place_clock(noon)
	runtime.daily.tick()
	TimeComponentManager.emit_time_signal()
	_check(_visual_position(hauling).is_equal_approx(before_position),
		"A fixture clock placement to noon preserves the paused route's exact position.")
	_check(CityStockManager.deposit_wallet_shekel(1)
		and CityStockManager.treasury_shekel == 1
		and Inventory.items.get("shekel", 0) == 0,
		"The player explicitly deposits the remaining fixture shekel after the failed morning.")
	_check(worker.is_payroll_blocked() and _route_is_in_flight(runtime, worker,
		WorkStateRuntime.get_node("CityToolStorage")),
		"The afternoon top-up leaves the worker paused with the same cargo and assignment.")
	TimeComponentManager.advance_minutes(1)
	_check(worker.is_payroll_blocked() and _visual_position(hauling).is_equal_approx(before_position),
		"Elapsed time after a deposit cannot restart the route before the next 08:00 boundary.")
	_save_and_assert_checkpoint(city, store, "funded pause")


func _resume_after_next_morning(store: Node) -> void:
	var city: Node = get_tree().current_scene
	var runtime: Node = city.get_node("YSortWorld/WorkerRuntime")
	var city_tools: Node = WorkStateRuntime.get_node("CityToolStorage")
	var worker: WorkerData = WorkerDatabase.get_worker_data(HAULER_ID)
	var hauling = runtime.daily.hauling
	var old_position: Vector2 = _visual_position(hauling)
	var next_morning: int = (worker.payroll_paid_until_day + 2) * 1440 + 480
	# Preserve daily.last_tick across this test-only boundary placement. The real
	# pre-settlement tick shifts the route by unpaid elapsed minutes before payment.
	_place_clock(next_morning - 1)
	TimeComponentManager.advance_minutes(1)
	var route: Dictionary = hauling.routes.get(HAULER_ID, {})
	_check(_now() == next_morning and not worker.is_payroll_blocked()
		and worker.payroll_paid_from_day == TimeComponentManager.current_day
		and worker.payroll_paid_until_day == TimeComponentManager.current_day + 6
		and worker.payroll_last_attempt_day == TimeComponentManager.current_day,
		"The next elapsed 08:00 funding boundary renews the waiting Hauler exactly once.")
	_check(CityStockManager.treasury_shekel == 0 and Inventory.items.get("shekel", 0) == 0,
		"The one explicit city deposit is spent once; no wallet withdrawal happens at renewal.")
	_check(_route_is_in_flight(runtime, worker, city_tools)
		and route.get("phase", "") == HAULING.PHASE_OUTBOUND
		and int(route.get("start", -1)) == _now() - 1
		and int(route.get("arrival", -1)) > _now()
		and _visual_position(hauling).is_equal_approx(old_position),
		"The same outbound load resumes at its frozen position after payroll succeeds.")
	TimeComponentManager.advance_minutes(1)
	_check(not _visual_position(hauling).is_equal_approx(old_position)
		and int(route.get("cargo", {}).get("quantity", 0)) == CARGO_QUANTITY
		and int(city_tools.items.get("wood_log", 0)) == 0,
		"After funding, one paid minute advances the same route without duplicate delivery.")
	_save_and_assert_checkpoint(city, store, "resumed route")


func _deliver_once(store: Node) -> void:
	var city: Node = get_tree().current_scene
	var runtime: Node = city.get_node("YSortWorld/WorkerRuntime")
	var worker: WorkerData = WorkerDatabase.get_worker_data(HAULER_ID)
	var city_tools: Node = WorkStateRuntime.get_node("CityToolStorage")
	var hauling = runtime.daily.hauling
	var route: Dictionary = hauling.routes.get(HAULER_ID, {})
	_check(_route_is_in_flight(runtime, worker, city_tools)
		and route.get("phase", "") == HAULING.PHASE_OUTBOUND,
		"Continue restores the renewed worker's same outbound assignment and cargo.")
	var remaining: int = int(route.get("arrival", _now())) - _now()
	_check(remaining > 0, "The restored route still has a future delivery boundary.")
	TimeComponentManager.advance_minutes(remaining)
	_check(int(city_tools.items.get("wood_log", 0)) == CARGO_QUANTITY
		and route.get("phase", "") == HAULING.PHASE_RETURNING
		and int(route.get("cargo", {}).get("quantity", -1)) == 0
		and hauling.delivered_on_day(HAULER_ID, TimeComponentManager.current_day) == CARGO_QUANTITY,
		"The resumed route delivers all three logs atomically, exactly once.")
	_check(runtime.daily.sites[WOOD_SITE].stock == 72
		and runtime._daily_output_count(WOOD_SITE) == 0
		and int(city_tools.items.get("wood_log", 0)) == CARGO_QUANTITY,
		"The resumed load reaches City Storage once while next-day site stock stays intact.")
	var return_remaining: int = int(route.get("arrival", _now())) - _now()
	TimeComponentManager.advance_minutes(maxi(return_remaining, 1) + 1)
	_check(int(city_tools.items.get("wood_log", 0)) == CARGO_QUANTITY
		and hauling.delivered_on_day(HAULER_ID, TimeComponentManager.current_day) == CARGO_QUANTITY
		and runtime.daily.jobs.has(WOOD_SITE)
		and runtime.daily.jobs[WOOD_SITE].ids == [HAULER_ID],
		"Return completion and another elapsed minute cannot duplicate delivery or discard assignment.")
	_check(runtime.daily.sites[WOOD_SITE].stock == 72
		and runtime._daily_output_count(WOOD_SITE) == 0
		and int(city_tools.items.get("wood_log", 0)) == CARGO_QUANTITY,
		"Return completion keeps the delivered stack at three without duplication.")


func _assert_exact_continue(city: Node, store: Node, label: String) -> void:
	var disk: Variant = _read_checkpoint_snapshot(label)
	var restored: Dictionary = store.snapshot.capture(city)
	var difference: String = _snapshot_difference(restored, disk, "$") if disk is Dictionary else "checkpoint is not a dictionary"
	_check(difference.is_empty(),
		"Separate-process %s Continue restores the complete CitySave snapshot exactly before elapsed time. %s" % [label, difference])


func _save_and_assert_checkpoint(city: Node, store: Node, label: String) -> void:
	var expected: Dictionary = store.snapshot.capture(city)
	var saved: bool = store.save_checkpoint()
	_check(saved, "Save the %s full CitySave checkpoint: %s" % [label, store.last_error])
	if not saved:
		return
	var disk: Variant = _read_checkpoint_snapshot(label)
	var serialized_expected: Variant = JSON.parse_string(JSON.stringify(expected, "\t", true, true))
	var difference: String = _snapshot_difference(serialized_expected, disk, "$") if disk is Dictionary else "checkpoint is not a dictionary"
	_check(difference.is_empty(),
		"The %s pre-save full CitySave capture is the persisted checkpoint. %s" % [label, difference])


func _read_checkpoint_snapshot(label: String) -> Variant:
	if not FileAccess.file_exists(CHECKPOINT_PATH):
		_check(false, "The %s CitySave checkpoint exists on disk." % label)
		return null
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	_check(disk is Dictionary, "The %s CitySave checkpoint is valid JSON." % label)
	return disk


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


func _route_is_in_flight(runtime: Node, worker: WorkerData, city_tools: Node) -> bool:
	if worker == null or runtime == null or not runtime.daily.jobs.has(WOOD_SITE):
		return false
	var hauling = runtime.daily.hauling
	var route: Dictionary = hauling.routes.get(HAULER_ID, {})
	var assigned: bool = runtime.daily.jobs[WOOD_SITE].ids == [HAULER_ID]
	var quantity: int = int(route.get("cargo", {}).get("quantity", 0))
	return assigned and worker.current_order_id == str(runtime.daily.jobs[WOOD_SITE].order) \
		and worker.is_reserved() and route.get("phase", "") == HAULING.PHASE_OUTBOUND \
		and route.get("site_id", &"") == WOOD_SITE \
		and route.get("destination_path", NodePath("")) == runtime.get_path_to(
		runtime.get_node("CityStorageArea/DeliveryPoint")) \
		and route.get("cargo", {}).get("item_id", "") == "wood_log" \
		and quantity == CARGO_QUANTITY and runtime._daily_output_count(WOOD_SITE) == 0 \
		and int(city_tools.items.get("wood_log", 0)) == 0


func _wood_total(runtime: Node, city_tools: Node) -> int:
	var route: Dictionary = runtime.daily.hauling.routes.get(HAULER_ID, {})
	return int(runtime.daily.sites[WOOD_SITE].stock) \
		+ int(runtime._daily_output_count(WOOD_SITE)) \
		+ int(city_tools.items.get("wood_log", 0)) \
		+ int(route.get("cargo", {}).get("quantity", 0))


func _visual_position(hauling) -> Vector2:
	var visual: Dictionary = hauling.get_visual(HAULER_ID, float(_now()))
	return visual.get("position", Vector2.ZERO)


func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute


func _place_clock(target_minute: int) -> void:
	var target_day: int = floori(float(target_minute) / 1440.0)
	TimeComponentManager.current_day = target_day
	var minute_of_day: int = target_minute % 1440
	TimeComponentManager.current_hour = minute_of_day / 60
	TimeComponentManager.current_minute = minute_of_day % 60
	TimeComponentManager._timer = 0.0
	TimeComponentManager.emit_time_signal()


func _finish() -> void:
	get_tree().paused = false
	print("PayrollCargoContinue %s: %s" % [phase, "PASS" if failures == 0 else "FAIL (%d)" % failures])
	get_tree().quit(0 if failures == 0 else 1)
