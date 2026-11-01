extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const DAILY: Script = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_daily.gd")
const SESSION: Script = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_session.gd")
const HAULING: Script = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_hauling.gd")
const SITE: StringName = &"ClockGuardSite"
const WORKER_ID: String = "clock_guard_worker"

class CheckpointProbe:
	extends Node
	var _busy: bool = false

class DeliveryProbe:
	extends RefCounted
	var received: int = 0
	func try_deliver_at_position(_position: Vector2, cargo: Dictionary) -> bool:
		received += int(cargo.quantity)
		cargo.quantity = 0
		return true

var failures: int = 0
var player: Player
var schedule
var session
var output: int = 0
var probe_enabled: bool = false
var probes: Array[Dictionary] = []
var sleep_events: int = 0
var collapse_events: int = 0
var capture_boundaries: bool = false
var boundaries: Array[String] = []
var shift_attempt: bool = true
var shift_was_dispatching: bool = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 1
	TimeComponentManager.current_hour = 7
	TimeComponentManager.current_minute = 0
	WorkerDatabase.workers_by_id.clear()
	CitizenManager.citizens_by_id.clear()
	var worker := WorkerData.new()
	worker.worker_id = WORKER_ID
	worker.display_name = WORKER_ID
	worker.satisfaction = 0.5
	WorkerDatabase.workers_by_id[WORKER_ID] = worker

	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	await get_tree().process_frame
	player.debug_disable_player_needs = false
	player.debug_disable_fatigue = false
	player.fatigue = 0.5
	player.hunger = 0.2
	player.last_sleep_day = -1
	player.sleep_completed.connect(func(_minutes: int, _quality: float): sleep_events += 1)
	player.collapse_completed.connect(func(_minutes: int): collapse_events += 1)

	session = SESSION.new()
	session.stock = 20
	session.minutes_per_unit = 1.0
	schedule = DAILY.new()
	schedule.setup({SITE: session})
	schedule.gathered.connect(_on_gathered)
	_expect(schedule.toggle(SITE, WORKER_ID) and schedule.start(SITE, _drop),
		"The real daily scheduler accepts the gathering assignment.")
	TimeComponentManager.minute_changed.connect(_tick_schedule)
	TimeComponentManager.new_day_started.connect(_record_new_day)
	TimeComponentManager.day_changed.connect(_record_day)
	TimeComponentManager.weather_changed.connect(_record_weather)
	TimeComponentManager.hour_changed.connect(_record_hour)
	TimeComponentManager.minute_changed.connect(_record_minute)
	TimeComponentManager.time_changed.connect(_record_time)

	probe_enabled = true
	var before: int = _now()
	_expect(TimeComponentManager.advance_minutes(3), "A normal three-minute advance completes synchronously.")
	_expect(_now() == before + 3 and output == 3 and schedule.last_tick == _now(),
		"Each outer minute is settled once despite the gathering callback.")
	_expect(probes.size() == 1, "The gathering callback attempted one reentrant advance.")
	_check_probe(0, true, false)

	# Move the clock by one minute without dispatching it, as an overdue work
	# interval can be flushed by a contract renewal outside clock advancement.
	TimeComponentManager.current_minute += 1
	Inventory.items["shekel"] = WorkerDatabase.get_contract_price(worker.profession, 3)
	probe_enabled = true
	before = _now()
	_expect(WorkerDatabase.renew_contract(WORKER_ID, 3), "A real contract renewal settles the outstanding work interval.")
	_expect(_now() == before and output == 4 and schedule.last_tick == before,
		"Payroll settlement completes once without advancing the clock.")
	_expect(probes.size() == 2, "The payroll-driven gathering callback attempted one reentrant advance.")
	_check_probe(1, true, true)

	# The same schedule can also be called independently of payroll or a clock
	# signal. Its own busy guard must protect the still-open worksite transaction.
	TimeComponentManager.current_minute += 1
	probe_enabled = true
	before = _now()
	schedule.tick()
	_expect(_now() == before and output == 5 and schedule.last_tick == before,
		"An independently flushed worksite completes without a nested clock jump.")
	_expect(probes.size() == 3, "The independently flushed gathering callback attempted one reentrant advance.")
	_check_probe(2, true, false)

	_test_delivery_callback()
	_test_busy_guards()
	_test_sleep_over_midnight()
	_test_shift_dispatch()
	_test_nightmare_consequences()
	schedule.cleanup()
	print("TimeTransactionGuardTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _tick_schedule(_minute: int) -> void:
	schedule.tick()

func _drop(quantity: int) -> bool:
	output += quantity
	return true

func _on_gathered(_id: String, _quantity: int) -> void:
	if not probe_enabled:
		return
	probe_enabled = false
	var before: int = _now()
	var hunger: float = player.hunger
	var fatigue: float = player.fatigue
	var last_day: int = player.last_sleep_day
	var movement: bool = player.can_move
	var sleeping: bool = player.is_sleeping
	var dispatching: bool = TimeComponentManager.is_dispatching_time()
	var ticking: bool = schedule.is_settlement_busy()
	var payroll: bool = WorkerDatabase._payroll_settling
	var one: bool = TimeComponentManager.advance_one_minute()
	var many: bool = TimeComponentManager.advance_minutes(2000)
	var sleep: bool = player.sleep_for_minutes(2000)
	var collapse: bool = player.apply_nightmare_consequences(2000)
	probes.append({"dispatching": dispatching, "ticking": ticking, "payroll": payroll,
		"one": one, "many": many, "sleep": sleep, "collapse": collapse,
		"unchanged": _now() == before and is_equal_approx(player.hunger, hunger)
			and is_equal_approx(player.fatigue, fatigue) and player.last_sleep_day == last_day
			and player.can_move == movement and player.is_sleeping == sleeping
			and sleep_events == 0 and collapse_events == 0})

func _check_probe(index: int, ticking: bool, payroll: bool) -> void:
	if probes.size() <= index:
		return
	var result: Dictionary = probes[index]
	_expect(result.ticking == ticking and result.payroll == payroll,
		"The probe ran inside the intended worksite and payroll transaction.")
	_expect(result.dispatching == (index in [0, 3]),
		"Payroll and independent worksite flushes run outside a clock dispatch.")
	_expect(not result.one and not result.many and not result.sleep and not result.collapse and result.unchanged,
		"Nested one-minute, multi-minute, sleep and collapse requests fail without side effects.")

func _test_delivery_callback() -> void:
	# Use a real loaded route and destination; delivery callbacks run inside the
	# same scheduler transaction as gathering and must not duplicate the load.
	session.minutes_per_unit = 1000.0
	var hauling = HAULING.new()
	schedule.hauling = hauling
	var destination := DeliveryProbe.new()
	var hauler_id: String = "clock_guard_hauler"
	hauling.begin(hauler_id, SITE, _now())
	var route: Dictionary = hauling.routes[hauler_id]
	route.phase = hauling.PHASE_OUTBOUND
	route.cargo.quantity = 3
	route.origin = Vector2.ZERO
	route.target = Vector2(1, 0)
	route.destination = destination
	route.arrival = _now() + 1
	hauling.delivered.connect(_on_gathered)
	probe_enabled = true
	var before: int = _now()
	_expect(TimeComponentManager.advance_minutes(1) and _now() == before + 1,
		"The loaded Hauler arrives during one ordinary clock minute.")
	_expect(destination.received == 3 and int(route.cargo.quantity) == 0
		and int(route.delivered_today) == 3 and route.phase == hauling.PHASE_RETURNING,
		"The three-item load is received once and the empty Hauler begins returning.")
	_expect(probes.size() == 4, "The actual delivery callback attempted one reentrant advance.")
	_check_probe(3, true, false)

func _test_busy_guards() -> void:
	for property: String in ["_processing_daily_needs", "_processing_food", "_processing_clothing", "_daily_needs_retry_pending"]:
		CitizenNeedsManager.set(property, true)
		var before: int = _now()
		var allowed: bool = TimeComponentManager.advance_minutes(1)
		var slept: bool = player.sleep_for_minutes(1)
		_expect(not allowed and not slept and _now() == before and player.last_sleep_day == -1,
			"A pending needs transaction blocks time and sleep: " + property)
		CitizenNeedsManager.set(property, false)
	var checkpoint: Node = WorkStateRuntime.get_node_or_null("CitySave")
	var created: bool = checkpoint == null
	if created:
		checkpoint = CheckpointProbe.new()
		checkpoint.name = "CitySave"
		WorkStateRuntime.add_child(checkpoint)
	checkpoint.set("_busy", true)
	TimeComponentManager._timer = 0.25
	var before: int = _now()
	_expect(not TimeComponentManager.advance_minutes(1) and not player.sleep_for_minutes(1)
		and _now() == before and is_equal_approx(TimeComponentManager._timer, 0.25),
		"A busy checkpoint blocks explicit advancement without resetting the clock timer.")
	TimeComponentManager._process(3.0)
	_expect(_now() == before and is_equal_approx(TimeComponentManager._timer, 0.25),
		"The frame clock and its accumulated fraction freeze during restoration.")
	checkpoint.set("_busy", false)
	TimeComponentManager._process(TimeComponentManager.seconds_per_minute - 0.25)
	_expect(_now() == before + 1 and is_equal_approx(TimeComponentManager._timer, 0.0),
		"The frame clock resumes from its preserved fraction after restoration.")
	if created:
		checkpoint.free()

func _test_sleep_over_midnight() -> void:
	TimeComponentManager.current_hour = 23
	TimeComponentManager.current_minute = 58
	schedule.last_tick = _now()
	TimeComponentManager.day_cycle()
	player.sleep_duration_minutes = 4
	player.fatigue = 0.8
	player.hunger = 0.2
	player.last_sleep_day = -1
	var day_before: int = TimeComponentManager.current_day
	var before: int = _now()
	boundaries.clear()
	capture_boundaries = true
	var slept: bool = player.sleep_for_minutes(4)
	capture_boundaries = false
	_expect(slept and _now() == before + 4 and TimeComponentManager.current_day == day_before + 1,
		"Normal sleep completes all elapsed minutes synchronously across midnight.")
	_expect(player.last_sleep_day == TimeComponentManager.current_day and not player.can_sleep()
		and not player.is_sleeping and player.can_move and sleep_events == 1,
		"Sleep completes recovery and its daily latch before returning.")
	_expect(is_equal_approx(player.hunger, 0.204) and is_equal_approx(player.fatigue, 0.2475),
		"All sleep minutes add hunger, then apply the existing recovery quality once.")
	_expect(CitizenNeedsManager.last_processed_day == TimeComponentManager.current_day
		and not CitizenNeedsManager._daily_needs_retry_pending,
		"Midnight needs complete synchronously without a deferred retry.")
	_expect(boundaries == ["new_day", "day", "weather", "hour", "minute", "time"],
		"Midnight preserves the existing day, weather, hour, minute and snapshot order.")

func _test_shift_dispatch() -> void:
	TimeComponentManager.current_hour = 4
	TimeComponentManager.current_minute = 59
	TimeComponentManager.day_cycle()
	TimeComponentManager.morning_shift.connect(_try_shift_advance)
	var before: int = _now()
	_expect(TimeComponentManager.advance_minutes(1) and _now() == before + 1,
		"A shift-boundary advance completes exactly one minute.")
	_expect(not shift_attempt and shift_was_dispatching,
		"A shift listener cannot reenter the clock before day_cycle finishes.")
	TimeComponentManager.morning_shift.disconnect(_try_shift_advance)
	TimeComponentManager.afternoon_shift.connect(_try_shift_advance)
	TimeComponentManager.current_hour = 10
	before = _now()
	shift_attempt = true
	shift_was_dispatching = false
	TimeComponentManager.day_cycle()
	_expect(not shift_attempt and shift_was_dispatching and _now() == before,
		"A standalone day_cycle also refuses nested clock advances.")
	TimeComponentManager.afternoon_shift.disconnect(_try_shift_advance)

func _try_shift_advance() -> void:
	shift_was_dispatching = TimeComponentManager.is_dispatching_time()
	shift_attempt = TimeComponentManager.advance_one_minute()

func _test_nightmare_consequences() -> void:
	player.hunger = 0.2
	player.fatigue = 0.8
	player.last_sleep_day = -1
	var before: int = _now()
	_expect(player.apply_nightmare_consequences(3) and _now() == before + 3,
		"An ordinary nightmare return advances its full duration synchronously.")
	_expect(is_equal_approx(player.hunger, 0.403) and is_equal_approx(player.fatigue, 0.5)
		and player.last_sleep_day == TimeComponentManager.current_day
		and player.last_collapse_day == TimeComponentManager.current_day
		and not player.is_sleeping and collapse_events == 1,
		"Nightmare consequences apply once after all elapsed minutes.")

func _record_new_day(_day: int) -> void:
	if capture_boundaries:
		boundaries.append("new_day")

func _record_day(_day: int) -> void:
	if capture_boundaries:
		boundaries.append("day")

func _record_weather(_weather: String) -> void:
	if capture_boundaries:
		boundaries.append("weather")

func _record_hour(_hour: int) -> void:
	if capture_boundaries:
		boundaries.append("hour")

func _record_minute(minute: int) -> void:
	if capture_boundaries and minute == 0:
		boundaries.append("minute")

func _record_time(_day: int, hour: int, minute: int, _weather: String) -> void:
	if capture_boundaries and hour == 0 and minute == 0:
		boundaries.append("time")

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
