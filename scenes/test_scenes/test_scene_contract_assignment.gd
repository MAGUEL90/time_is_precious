extends Node

const WORKSITE_SCENE: PackedScene = preload("res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn")
const PAID_ID: String = "contract_assignment_paid"
const EXPIRED_ID: String = "contract_assignment_expired"
const PRE_SHIFT_ID: String = "contract_assignment_before_shift"
const AFTER_SHIFT_ID: String = "contract_assignment_after_shift"
const CAP_ID: String = "contract_assignment_daily_cap"
const HAULER_ID: String = "contract_assignment_midshift_hauler"
const HAUL_SITE: StringName = &"ClaySiteB"

var failures: int = 0
var fixture
var schedule
var site
var base_day: int
var saved_clock: Dictionary = {}
var saved_workers: Dictionary[String, WorkerData] = {}
var saved_dismissed: Dictionary[String, WorkerData] = {}
var saved_tree_paused: bool = false
var saved_time_paused: bool = false
var saved_time_processing: bool = false
var saved_timer: float = 0.0
var completed_case_count: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_save_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = true
	base_day = maxi(TimeComponentManager.current_day + 10, 20)
	for id: String in [PAID_ID, EXPIRED_ID, PRE_SHIFT_ID, AFTER_SHIFT_ID, CAP_ID, HAULER_ID]:
		WorkerDatabase.workers_by_id.erase(id)
		WorkerDatabase.dismissed_workers.erase(id)
	WorkerDatabase.workers_by_id[PAID_ID] = _worker(PAID_ID, 20)
	WorkerDatabase.workers_by_id[EXPIRED_ID] = _worker(EXPIRED_ID, -1)
	WorkerDatabase.workers_by_id[PRE_SHIFT_ID] = _worker(PRE_SHIFT_ID, 20)
	WorkerDatabase.workers_by_id[AFTER_SHIFT_ID] = _worker(AFTER_SHIFT_ID, 20)
	WorkerDatabase.workers_by_id[CAP_ID] = _worker(CAP_ID, 20)
	var hauler: WorkerData = _worker(HAULER_ID, 20)
	hauler.profession = WorkerData.Profession.HAULER
	WorkerDatabase.workers_by_id[HAULER_ID] = hauler

	fixture = WORKSITE_SCENE.instantiate()
	fixture.enable_worker_commute = false
	fixture.test_hauler_carts = 1
	add_child(fixture)
	await get_tree().process_frame
	get_tree().paused = true
	schedule = fixture.daily
	site = fixture.sites[&"ClaySiteA"]
	site.minutes_per_unit = 1000.0
	site.daily_stock_min = 10000
	site.daily_stock_max = 10000
	site.stock = 10000
	_test_paid_midshift_and_expired_worker()
	_test_before_shift_start()
	_test_after_shift_start()
	_test_reassignment_keeps_daily_cap()
	_test_midshift_hauler_only_carries_new_output()
	_finish()

func _save_globals() -> void:
	saved_clock = {"day": TimeComponentManager.current_day, "hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute, "weather": TimeComponentManager.current_weather,
		"timer": TimeComponentManager._timer}
	saved_workers = WorkerDatabase.workers_by_id.duplicate()
	saved_dismissed = WorkerDatabase.dismissed_workers.duplicate()
	saved_tree_paused = get_tree().paused
	saved_time_paused = TimeComponentManager.is_paused
	saved_time_processing = TimeComponentManager.is_processing()
	saved_timer = TimeComponentManager._timer

func _worker(id: String, paid_until_offset: int) -> WorkerData:
	var worker := WorkerData.new()
	worker.worker_id = id
	worker.display_name = id
	worker.profession = WorkerData.Profession.LABORER
	worker.payroll_start_day = base_day - 7
	worker.payroll_paid_from_day = base_day - 7
	worker.payroll_paid_until_day = base_day + paid_until_offset
	worker.payroll_period_rate = 1
	worker.payroll_last_attempt_day = base_day - 7
	worker.payroll_contract_days = 3
	worker.payroll_paid_start_minute = (base_day - 7) * 1440 + 480
	return worker

func _set_case_time(day: int, hour: int, minute: int) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute
	schedule.last_tick = schedule.now()
	schedule.ledger_day = day
	schedule.minutes_by_worker.clear()
	schedule.last_stock_day = day
	site.stock = 10000

func _test_paid_midshift_and_expired_worker() -> void:
	_set_case_time(base_day, 12, 0)
	_expect(not WorkerDatabase.get_worker_data(PAID_ID).is_payroll_blocked(), "Paid prepaid worker remains eligible during the active period.")
	_expect(WorkerDatabase.get_worker_data(EXPIRED_ID).is_payroll_blocked(), "Expired worker remains blocked independently of the paid worker.")
	_expect(schedule.toggle(&"ClaySiteA", PAID_ID), "Paid worker can join the current-day shift.")
	_expect(not schedule.toggle(&"ClaySiteA", EXPIRED_ID), "Expired worker cannot join the paid assignment.")
	_expect(schedule.start(&"ClaySiteA", _accept_output), "Paid worker assignment starts mid-shift.")
	var start: int = schedule.now()
	_expect(int(schedule.jobs[&"ClaySiteA"].starts[PAID_ID]) == start, "Mid-shift assignment starts at its actual minute.")
	_expect(schedule.start_day_text(&"ClaySiteA") == "Start work: Day %d" % base_day, "Mid-shift confirmation shows today.")
	_expect(float(schedule.jobs[&"ClaySiteA"].progress[PAID_ID]) == 0.0
		and int(schedule.minutes_by_worker.get(PAID_ID, 0)) == 0, "Assignment creates no retroactive work.")
	TimeComponentManager.advance_minutes(60)
	_expect(int(schedule.minutes_by_worker.get(PAID_ID, 0)) == 60
		and float(schedule.jobs[&"ClaySiteA"].progress.get(PAID_ID, 0.0)) == 60.0,
		"An hour of progress contains only minutes after the paid worker joined.")
	TimeComponentManager.advance_minutes(schedule.SHIFT_END - 13 * 60)
	_expect(int(schedule.minutes_by_worker.get(PAID_ID, 0)) == schedule.SHIFT_END - 12 * 60,
		"Mid-shift worker receives only the remaining paid shift minutes.")
	schedule.withdraw(&"ClaySiteA", PAID_ID)
	completed_case_count += 1

func _test_before_shift_start() -> void:
	_set_case_time(base_day + 1, 6, 0)
	_expect(schedule.toggle(&"ClaySiteA", PRE_SHIFT_ID), "Paid worker can be assigned before the shift.")
	var draft_day_label: String = schedule.start_day_text(&"ClaySiteA")
	_expect(draft_day_label == "Start work: Day %d" % (base_day + 1),
		"Before-shift draft confirmation shows today: %s" % draft_day_label)
	_expect(schedule.start(&"ClaySiteA", _accept_output), "Before-shift assignment is accepted.")
	var expected_start: int = (base_day + 1) * 1440 + schedule.SHIFT_START
	_expect(int(schedule.jobs[&"ClaySiteA"].starts[PRE_SHIFT_ID]) == expected_start,
		"Before-shift assignment starts at 07:00 today.")
	TimeComponentManager.advance_minutes(schedule.SHIFT_START - 6 * 60)
	_expect(int(schedule.minutes_by_worker.get(PRE_SHIFT_ID, 0)) == 0,
		"Before-shift worker does not accrue work before 07:00.")
	TimeComponentManager.advance_minutes(1)
	_expect(int(schedule.minutes_by_worker.get(PRE_SHIFT_ID, 0)) == 1,
		"Before-shift worker begins on the first minute of the shift.")
	schedule.withdraw(&"ClaySiteA", PRE_SHIFT_ID)
	completed_case_count += 1

func _test_after_shift_start() -> void:
	_set_case_time(base_day + 2, 15, 0)
	_expect(schedule.toggle(&"ClaySiteA", AFTER_SHIFT_ID), "Paid worker can be assigned after today's shift.")
	_expect(schedule.start(&"ClaySiteA", _accept_output), "After-shift assignment is accepted.")
	var expected_start: int = (base_day + 3) * 1440 + schedule.SHIFT_START
	_expect(int(schedule.jobs[&"ClaySiteA"].starts[AFTER_SHIFT_ID]) == expected_start,
		"After-shift assignment starts at 07:00 the following day.")
	_expect(not WorkerDatabase.get_worker_data(AFTER_SHIFT_ID).is_working(), "After-shift worker rests until the next shift.")
	TimeComponentManager.advance_minutes(16 * 60)
	_expect(schedule.now() == expected_start and WorkerDatabase.get_worker_data(AFTER_SHIFT_ID).is_working(),
		"Next-day work starts exactly at 07:00 without another day of waiting.")
	TimeComponentManager.advance_minutes(1)
	_expect(int(schedule.minutes_by_worker.get(AFTER_SHIFT_ID, 0)) == 1,
		"Next-day assignment begins producing on the first shift minute.")
	schedule.withdraw(&"ClaySiteA", AFTER_SHIFT_ID)
	completed_case_count += 1

func _test_reassignment_keeps_daily_cap() -> void:
	_set_case_time(base_day + 3, 7, 0)
	_expect(schedule.toggle(&"ClaySiteA", CAP_ID), "Worker can be assigned at shift start.")
	_expect(schedule.start(&"ClaySiteA", _accept_output), "Daily-cap assignment starts.")
	TimeComponentManager.advance_minutes(schedule.DAILY_LIMIT - 2)
	_expect(int(schedule.minutes_by_worker.get(CAP_ID, 0)) == schedule.DAILY_LIMIT - 2,
		"Daily minute budget records work before worker replacement.")
	_expect(schedule.withdraw(&"ClaySiteA", CAP_ID), "Worker can be removed before the end of the shift.")
	_expect(schedule.toggle(&"ClaySiteA", CAP_ID), "Removed worker can be reassigned to the same worksite.")
	_expect(schedule.start(&"ClaySiteA", _accept_output), "Reassignment starts for the shift remainder.")
	TimeComponentManager.advance_minutes(2)
	_expect(int(schedule.minutes_by_worker.get(CAP_ID, 0)) == schedule.DAILY_LIMIT,
		"Removing and reassigning preserves the same-day eight-hour cap.")
	TimeComponentManager.advance_minutes(30)
	_expect(int(schedule.minutes_by_worker.get(CAP_ID, 0)) == schedule.DAILY_LIMIT,
		"Reassignment cannot earn work beyond the daily cap or shift end.")
	completed_case_count += 1

func _test_midshift_hauler_only_carries_new_output() -> void:
	_set_case_time(base_day + 4, 12, 0)
	var site = fixture.sites[HAUL_SITE]
	var site_marker: Marker2D = fixture.get_node("WorksiteMarkers/ClaySiteB") as Marker2D
	site.minutes_per_unit = 1.0
	site.daily_stock_min = 10000
	site.daily_stock_max = 10000
	site.stock = 10000
	var storage = preload("res://scenes/test_scenes/clay_worksite_test/hauler_test_storage.gd").new()
	storage.name = "ContractAssignmentStorage"
	fixture.add_child(storage)
	var destination: StorageDestination = preload("res://scenes/storage_destination/storage_destination.tscn").instantiate()
	destination.name = "ContractAssignmentDestination"
	destination.global_position = site_marker.global_position + Vector2(125, 0)
	fixture.add_child(destination)
	destination.storage_path = destination.get_path_to(storage)
	_expect(fixture.worker_management.equip(HAULER_ID, "test_cart_0") == "Tool equipped.",
		"The mid-shift Hauler has its required cart before assignment.")
	_expect(schedule.toggle(HAUL_SITE, PRE_SHIFT_ID), "A paid Laborer can join the Hauler's worksite mid-shift.")
	_expect(schedule.select_hauler(HAUL_SITE, HAULER_ID, fixture.get_path_to(destination),
		destination.display_name, 3), "A paid Hauler can join a configured route mid-shift.")
	var output: Callable = fixture._drop_daily_output.bind(site_marker)
	_expect(schedule.start(HAUL_SITE, output), "The mid-shift Laborer and Hauler assignment starts.")
	var assigned_at: int = schedule.now()
	var job: Dictionary = schedule.jobs[HAUL_SITE]
	var route: Dictionary = fixture.hauling.routes[HAULER_ID]
	_expect(int(job.starts[PRE_SHIFT_ID]) == assigned_at and int(job.starts[HAULER_ID]) == assigned_at,
		"Both workers' same-day assignments begin at the paid assignment minute.")
	_expect(int(schedule.minutes_by_worker.get(PRE_SHIFT_ID, 0)) == 0
		and int(schedule.minutes_by_worker.get(HAULER_ID, 0)) == 0
		and float(job.progress[PRE_SHIFT_ID]) == 0.0 and int(job.stats[PRE_SHIFT_ID].output) == 0
		and fixture._daily_output_count(HAUL_SITE) == 0
		and route.phase == "idle" and int(route.cargo.quantity) == 0,
		"Starting a mid-shift Hauler assignment creates no past labor, cargo, or output.")
	TimeComponentManager.advance_minutes(1)
	_expect(int(schedule.minutes_by_worker.get(PRE_SHIFT_ID, 0)) == 1
		and int(job.stats[PRE_SHIFT_ID].output) == 1 and route.phase == "idle"
		and int(route.cargo.quantity) == 0,
		"The first post-assignment Laborer minute creates new output without a Hauler pickup.")
	TimeComponentManager.advance_minutes(2)
	_expect(int(schedule.minutes_by_worker.get(PRE_SHIFT_ID, 0)) == 3
		and int(job.stats[PRE_SHIFT_ID].output) == 3 and route.phase == "outbound"
		and int(route.cargo.quantity) == 3 and int(route.start) == schedule.now()
		and int(job.stats[HAULER_ID].output) == 0,
		"The real Hauler route picks up only the three items produced after assignment and starts at that minute.")
	_expect(schedule.withdraw(HAUL_SITE, PRE_SHIFT_ID), "The Laborer can leave after producing the tested load.")
	var trip_arrival: int = int(route.arrival)
	TimeComponentManager.advance_minutes(trip_arrival - schedule.now())
	_expect(storage.quantity == 3 and int(route.cargo.quantity) == 0
		and fixture.hauling.delivered_on_day(HAULER_ID, base_day + 4) == 3
		and int(job.stats[HAULER_ID].output) == 3,
		"Only the post-assignment load is credited when the real trip reaches storage.")
	completed_case_count += 1

func _accept_output(_quantity: int) -> bool:
	return true

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _finish() -> void:
	_expect(completed_case_count == 5, "Every assignment contract case completed without a script interruption.")
	get_tree().paused = false
	fixture.queue_free()
	await get_tree().process_frame
	WorkerDatabase.workers_by_id = saved_workers
	WorkerDatabase.dismissed_workers = saved_dismissed
	TimeComponentManager.current_day = int(saved_clock.day)
	TimeComponentManager.current_hour = int(saved_clock.hour)
	TimeComponentManager.current_minute = int(saved_clock.minute)
	TimeComponentManager.current_weather = str(saved_clock.weather)
	TimeComponentManager._timer = saved_timer
	TimeComponentManager.is_paused = saved_time_paused
	TimeComponentManager.set_process(saved_time_processing)
	get_tree().paused = saved_tree_paused
	print("ContractAssignmentTest %s" % ("PASSED" if failures == 0 else "FAILED: %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)
