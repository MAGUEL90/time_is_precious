extends Node

const DAILY = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_daily.gd")
const HAULING = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_hauling.gd")
const SESSION = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_session.gd")
const MANAGEMENT = preload("res://scenes/test_scenes/clay_worksite_test/clay_worker_management.gd")
const CITY_TOOLS = preload("res://scenes/storage_destination/city_tool_storage.gd")
const SITE: StringName = &"ResignationSite"

class Destination extends RefCounted:
	var accepting: bool = true
	var quantity: int = 0
	var position: Vector2 = Vector2(30, 0)
	var on_receipt: Callable
	func get_arrival_position() -> Vector2:
		return position
	func accepts_cargo(_item_id: String, quantity_value: int) -> bool:
		return accepting and quantity_value > 0
	func try_deliver_at_position(_position_value: Vector2, cargo: Dictionary) -> bool:
		if not accepting:
			return false
		quantity += int(cargo.quantity)
		# Match the real destination's synchronous storage.changed ordering.
		if on_receipt.is_valid():
			on_receipt.call()
		cargo.quantity = 0
		return true

var failures: int = 0
var schedule
var hauling
var session
var management
var destination: Destination
var city_tools: Node
var available: int = 0
var dropped: int = 0
var drop_allowed: bool = true
var pickup_calls: int = 0
var ready_ids: Array[String] = []
var receipt_reentries: int = 0
var receipt_signal_guarded: bool = false
var direct_receipts: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = true
	city_tools = CITY_TOOLS.new()
	add_child(city_tools)
	_test_overnight_progress_and_replacement()
	_test_draft_resignation()
	_test_multiple_partial_items()
	_test_failed_output_is_retained()
	_test_gather_callback_reentry()
	_test_loaded_delivery_and_reentry()
	_test_rejected_return_resumes_same_load()
	_test_direct_receipt_clock_guard()
	_cleanup()
	print("WorksiteResignationTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _setup(minute_of_day: int = 420) -> void:
	_cleanup()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	CitizenManager.citizens_by_id.clear()
	city_tools.units.clear()
	_set_time(minute_of_day)
	available = 0
	dropped = 0
	drop_allowed = true
	pickup_calls = 0
	ready_ids.clear()
	receipt_reentries = 0
	receipt_signal_guarded = false
	session = SESSION.new()
	session.minutes_per_unit = 10.0
	session.stock = 1000
	schedule = DAILY.new()
	schedule.setup({SITE: session})
	schedule.equipment_storage = city_tools
	management = MANAGEMENT.new()
	management.schedule = schedule
	schedule.gathered.connect(management.record_contribution)
	schedule.resignation_ready.connect(_on_resignation_ready)
	hauling = HAULING.new()
	destination = Destination.new()
	hauling.speed = 10.0
	hauling.origin_provider = func(_site: StringName, _id: String) -> Vector2: return Vector2.ZERO
	hauling.assigned_destination_provider = func(_path: NodePath): return destination
	hauling.item_provider = func(_site: StringName) -> String: return "clay_lump"
	hauling.output_count = func(_site: StringName) -> int: return available
	hauling.take_output = _take
	hauling.return_output = _return
	hauling.delivered.connect(management.record_contribution)
	schedule.hauling = hauling
	schedule.hauler_ready = func(_site: StringName, _count: int) -> String: return ""

func _worker(id: String, profession: WorkerData.Profession = WorkerData.Profession.LABORER) -> WorkerData:
	var worker := WorkerData.new()
	worker.worker_id = id
	worker.display_name = id
	worker.profession = profession
	worker.satisfaction = 0.8
	WorkerDatabase.workers_by_id[id] = worker
	return worker

func _select(id: String) -> void:
	_expect(schedule.toggle(SITE, id), "Select " + id)

func _start() -> void:
	_expect(schedule.start(SITE, _drop), "Start assignment")

func _set_time(total: int) -> void:
	TimeComponentManager.current_day = total / 1440
	TimeComponentManager.current_hour = (total % 1440) / 60
	TimeComponentManager.current_minute = total % 60

func _advance(minutes: int) -> void:
	for _index: int in range(minutes):
		_set_time(schedule.now() + 1)
		schedule.tick()

func _drop(quantity: int) -> bool:
	if not drop_allowed:
		return false
	dropped += quantity
	return true

func _take(_site: StringName, maximum: int) -> int:
	pickup_calls += 1
	var taken: int = mini(available, maximum)
	available -= taken
	return taken

func _return(_site: StringName, quantity: int) -> bool:
	available += quantity
	return true

func _on_resignation_ready(id: String) -> void:
	_expect(not schedule.is_settlement_busy(), "Completion is emitted after the worksite transaction.")
	_expect(not schedule.jobs.has(SITE) or not schedule.jobs[SITE].ids.has(id), "Completion follows assignment removal.")
	_expect(not hauling.routes.has(id), "Completion follows route removal.")
	ready_ids.append(id)

func _test_overnight_progress_and_replacement() -> void:
	_setup(14 * 60 + 58)
	var departing: WorkerData = _worker("overnight_departing")
	_worker("overnight_coworker")
	_select(departing.worker_id)
	_select("overnight_coworker")
	_start()
	_advance(2)
	var job: Dictionary = schedule.jobs[SITE]
	_expect(is_equal_approx(float(job.progress[departing.worker_id]), 2.1)
		and is_equal_approx(float(job.progress.overnight_coworker), 2.1), "Both workers retain their own partial item at 15:00.")
	_set_time(1440)
	_expect(schedule.flush_before_needs(), "The old work interval flushes at midnight.")
	departing.resignation_pending = true
	_expect(schedule.request_resignation(departing.worker_id), "The gatherer releases immediately.")
	_expect(schedule.jobs[SITE].ids == ["overnight_coworker"]
		and is_equal_approx(float(schedule.pending_progress[SITE][0]), 2.1)
		and is_equal_approx(float(schedule.jobs[SITE].progress.overnight_coworker), 2.1), "Resignation preserves only the departing worker's work and the coworker continues.")
	_worker("overnight_replacement")
	_select("overnight_replacement")
	_start()
	_expect(not schedule.pending_progress.has(SITE)
		and is_equal_approx(float(job.progress.overnight_replacement), 2.1), "One replacement claims the saved partial item once.")
	_set_time(1440 + 7 * 60)
	schedule.tick()
	_advance(8)
	_expect(int(job.stats.overnight_replacement.output) == 1
		and is_equal_approx(float(job.progress.overnight_replacement), 0.5), "The replacement finishes the same item using the retained progress.")

func _test_multiple_partial_items() -> void:
	_setup()
	var a: WorkerData = _worker("partial_a")
	var b: WorkerData = _worker("partial_b")
	_select(a.worker_id)
	_select(b.worker_id)
	_start()
	schedule.jobs[SITE].progress[a.worker_id] = 2.0
	schedule.jobs[SITE].progress[b.worker_id] = 7.0
	a.resignation_pending = true
	b.resignation_pending = true
	_expect(schedule.request_resignation(a.worker_id) and schedule.request_resignation(b.worker_id), "Both gatherers leave immediately.")
	_expect(schedule.pending_progress[SITE] == [2.0, 7.0], "Separate incomplete items are not combined.")
	_worker("replacement_a")
	_worker("replacement_b")
	_select("replacement_a")
	_select("replacement_b")
	_start()
	_expect(float(schedule.jobs[SITE].progress.replacement_a) == 2.0
		and float(schedule.jobs[SITE].progress.replacement_b) == 7.0
		and not schedule.pending_progress.has(SITE), "Two replacements claim distinct items exactly once.")

func _test_draft_resignation() -> void:
	_setup()
	var worker: WorkerData = _worker("draft_hauler", WorkerData.Profession.HAULER)
	_expect(schedule.select_hauler(SITE, worker.worker_id, NodePath("Destination"), "Destination", 3), "Configure a draft Hauler.")
	worker.resignation_pending = true
	_expect(schedule.request_resignation(worker.worker_id) and not schedule.selected[SITE].has(worker.worker_id)
		and not schedule.hauler_setups.has(worker.worker_id), "Resignation clears an unstarted selection and its destination plan.")

func _test_failed_output_is_retained() -> void:
	_setup()
	var worker: WorkerData = _worker("failed_drop")
	_select(worker.worker_id)
	_start()
	schedule.jobs[SITE].units = 3
	drop_allowed = false
	worker.resignation_pending = true
	_expect(schedule.request_resignation(worker.worker_id) and not schedule.jobs.has(SITE), "Last worker leaves even when output cannot spawn.")
	_expect(int(schedule.pending_output[SITE].quantity) == 3 and dropped == 0, "The completed output retains a durable site owner.")
	drop_allowed = true
	_advance(2)
	_expect(dropped == 3 and not schedule.pending_output.has(SITE), "A later retry materializes the output exactly once.")
	_expect(schedule.request_resignation(worker.worker_id), "Repeating a completed request is harmless.")

func _test_gather_callback_reentry() -> void:
	_setup()
	var worker: WorkerData = _worker("reentrant_gatherer")
	_worker("reentrant_coworker")
	_select(worker.worker_id)
	_select("reentrant_coworker")
	_start()
	schedule.jobs[SITE].progress[worker.worker_id] = 9.2
	schedule.gathered.connect(func(id: String, _quantity: int):
		if id == worker.worker_id:
			worker.resignation_pending = true
			_expect(not schedule.request_resignation(id), "A reentrant request waits for the current tick.")
			_expect(not schedule.flush_before_needs(), "Needs flush does not reenter a worksite tick.")
	)
	_advance(1)
	_expect(dropped == 1 and ready_ids == [worker.worker_id]
		and schedule.jobs[SITE].ids == ["reentrant_coworker"]
		and is_equal_approx(float(schedule.pending_progress[SITE][0]), 0.25), "Reentry preserves output and fraction while leaving the coworker intact.")

func _test_loaded_delivery_and_reentry() -> void:
	_setup(14 * 60 + 57)
	var worker: WorkerData = _worker("loaded_hauler", WorkerData.Profession.HAULER)
	_expect(city_tools.add_tool_unit("loaded_cart", "cart", "Cart") and city_tools.allocate("loaded_cart", worker.worker_id), "Allocate a real fixture-local cart.")
	var endpoint: StorageDestination = preload("res://scenes/content_scene/worksites/worksite_stockpile.tscn").instantiate()
	endpoint.position = Vector2(30, 0)
	add_child(endpoint)
	var competing_endpoint: StorageDestination = preload("res://scenes/content_scene/worksites/worksite_stockpile.tscn").instantiate()
	competing_endpoint.position = Vector2(60, 0)
	add_child(competing_endpoint)
	var real_storage: Node = endpoint.get_storage()
	var competing_storage: Node = competing_endpoint.get_storage()
	hauling.assigned_destination_provider = func(_path: NodePath): return endpoint
	available = 6
	_expect(schedule.select_hauler(SITE, worker.worker_id, NodePath("Destination"), "Destination", 9), "Configure hauler.")
	_start()
	_advance(1)
	_expect(hauling.routes[worker.worker_id].cargo.quantity == 3 and available == 3, "Pickup moves exactly one load into cargo.")
	worker.resignation_pending = true
	_expect(not schedule.request_resignation(worker.worker_id) and not schedule.request_resignation(worker.worker_id), "Repeated loaded requests keep one pending trip.")
	_expect(bool(hauling.routes[worker.worker_id].resigning), "The pending reason is recorded independently of ordinary removal.")
	worker.payroll_start_day = 0
	worker.payroll_paid_from_day = -1
	_expect(worker.is_payroll_blocked() and schedule.activity(SITE, worker.worker_id) == WorkerData.WorkStatus.TRAVELLING,
		"An expired contract cannot strand the final trip or misreport a moving hauler.")
	endpoint.accepting_deliveries = false
	_advance(3)
	_expect(hauling.routes[worker.worker_id].cargo.quantity == 3 and real_storage.quantity == 0
		and ready_ids.is_empty(), "A rejected delivery keeps the load and does not resign early.")
	real_storage.changed.connect(func():
		receipt_reentries += 1
		var cargo: Dictionary = hauling.routes[worker.worker_id].cargo
		_expect(endpoint.is_delivery_busy(), "The receiving endpoint stays locked during storage callbacks.")
		_expect(not endpoint.try_deliver_at_position(endpoint.get_arrival_position(), cargo), "A same-endpoint reentry cannot credit the load twice.")
		_expect(not competing_endpoint.try_deliver_at_position(competing_endpoint.get_arrival_position(), cargo), "A different endpoint cannot reenter with the same cargo.")
		_expect(not schedule.request_resignation(worker.worker_id), "Receipt reentry waits until the cargo transaction ends.")
	)
	endpoint.delivery_received.connect(func(_item_id: String, _quantity: int): receipt_signal_guarded = endpoint.is_delivery_busy())
	endpoint.accepting_deliveries = true
	_advance(1)
	_expect(real_storage.quantity == 3 and competing_storage.quantity == 0 and available == 3
		and pickup_calls == 1 and receipt_reentries == 1 and receipt_signal_guarded and not endpoint.is_delivery_busy(),
		"One accepted delivery finishes after shift with no extra pickup or duplicate cargo.")
	_expect(ready_ids == [worker.worker_id] and not WorkerDatabase.has_worker_data(worker.worker_id)
		and worker.profession_xp == 3 and not city_tools.has_equipped(worker.worker_id, "cart"),
		"Resignation completes synchronously once, awards delivery XP, and releases local equipment.")
	_advance(10)
	_expect(real_storage.quantity == 3 and available == 3 and pickup_calls == 1 and ready_ids.size() == 1,
		"Subsequent ticks cannot repeat the completed shipment or callback.")
	endpoint.queue_free()
	competing_endpoint.queue_free()

func _test_rejected_return_resumes_same_load() -> void:
	_setup()
	var worker: WorkerData = _worker("returning_hauler", WorkerData.Profession.HAULER)
	available = 3
	_expect(schedule.select_hauler(SITE, worker.worker_id, NodePath("Destination"), "Destination", 3), "Configure returning hauler.")
	_start()
	_advance(1)
	destination.accepting = false
	_advance(3)
	_expect(hauling.routes[worker.worker_id].phase == "returning" and hauling.routes[worker.worker_id].cargo.quantity == 3,
		"A rejection before resignation is returning with its original load.")
	worker.resignation_pending = true
	_expect(not schedule.request_resignation(worker.worker_id), "Returning cargo keeps resignation pending.")
	destination.accepting = true
	_advance(6)
	_expect(destination.quantity == 3 and available == 0 and pickup_calls == 1 and ready_ids == [worker.worker_id],
		"The same rejected load reaches its destination once without a new pickup.")

func _test_direct_receipt_clock_guard() -> void:
	_setup()
	var endpoint: StorageDestination = preload("res://scenes/content_scene/worksites/worksite_stockpile.tscn").instantiate()
	add_child(endpoint)
	var storage: Node = endpoint.get_storage()
	var cargo: Dictionary = {"item_id": "clay_lump", "quantity": 3}
	direct_receipts = 0
	_expect(TimeComponentManager.can_advance_time(), "The clock starts unblocked outside any transaction.")
	storage.changed.connect(func():
		direct_receipts += 1
		_expect(StorageDestination.is_any_delivery_busy(), "Direct receipt raises the global delivery guard.")
		_expect(not TimeComponentManager.advance_minutes(1), "A storage callback cannot advance time before cargo clears.")
		_expect(not endpoint.try_deliver_at_position(endpoint.get_arrival_position(), cargo), "A direct receipt cannot be repeated synchronously.")
	)
	var before: int = schedule.now()
	_expect(endpoint.try_deliver_at_position(endpoint.get_arrival_position(), cargo)
		and int(storage.quantity) == 3 and int(cargo.quantity) == 0 and direct_receipts == 1
		and not cargo.has("_delivery_in_progress") and not StorageDestination.is_any_delivery_busy()
		and schedule.now() == before, "Direct receipt commits once and releases every guard.")
	endpoint.queue_free()

func _cleanup() -> void:
	if schedule != null:
		schedule.cleanup()
		schedule = null

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
