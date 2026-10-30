extends Node

const DailySchedule: Script = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_daily.gd")
const WorksiteSession: Script = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_session.gd")
const Hauling: Script = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_hauling.gd")
const WorkerManagement: Script = preload("res://scenes/test_scenes/clay_worksite_test/clay_worker_management.gd")
const GATHER_SITE: StringName = &"PayrollGatherSite"
const HAUL_SITE: StringName = &"PayrollHaulSite"
const IDLE_HAUL_SITE: StringName = &"PayrollIdleHaulSite"
const BLOCKED_GATHERER: String = "clay_worksite_payroll_blocked_gatherer"
const PAID_GATHERER: String = "clay_worksite_payroll_paid_gatherer"
const HAULER: String = "clay_worksite_payroll_hauler"
const IDLE_HAULER: String = "clay_worksite_payroll_idle_hauler"
const DUE_DAY: int = 20
const RESUME_DAY: int = DUE_DAY + 1

class PayrollDestination:
	extends RefCounted
	var receipts: Array[Dictionary] = []

	func get_arrival_position() -> Vector2:
		return Vector2(60, 0)

	func accepts_cargo(item_id: String, quantity: int) -> bool:
		return item_id == "clay_lump" and quantity > 0

	func try_deliver_at_position(position: Vector2, cargo: Dictionary) -> bool:
		if position.distance_to(get_arrival_position()) > 0.001 or int(cargo.get("quantity", 0)) <= 0:
			return false
		receipts.append({"item_id": str(cargo.get("item_id", "")), "quantity": int(cargo.quantity)})
		cargo.quantity = 0
		return true

var failures: int = 0
var schedule
var hauling
var destination: PayrollDestination
var site_outputs: Dictionary = {}
var hauler_start_at_pause: int = -1
var hauler_arrival_at_pause: int = -1
var hauler_position_at_pause: Vector2 = Vector2.ZERO
var saved: Dictionary = {}
var restored: bool = false


func _ready() -> void:
	_run.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	_save_globals()
	_prepare_globals()
	_prepare_schedule()
	_start_assignments()
	_expect(WorkerDatabase.is_connected("payroll_settling", schedule.tick),
		"The Daily schedule listens for the pre-settlement work flush.")
	_test_gather_pause_and_paid_coworker()
	_test_hauler_pause_and_resume()
	_finish()


func _save_globals() -> void:
	saved = {
		"workers": WorkerDatabase.workers_by_id.duplicate(),
		"dismissed": WorkerDatabase.dismissed_workers.duplicate(),
		"citizens": CitizenManager.citizens_by_id.duplicate(),
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"weather": TimeComponentManager.current_weather,
		"timer": TimeComponentManager._timer,
		"paused": TimeComponentManager.is_paused,
		"processing": TimeComponentManager.is_processing(),
		"tree_paused": get_tree().paused
	}


func _prepare_globals() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = true
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id[BLOCKED_GATHERER] = _seed_worker(BLOCKED_GATHERER, WorkerData.Profession.LABORER, DUE_DAY - 7, DUE_DAY - 1)
	WorkerDatabase.workers_by_id[PAID_GATHERER] = _seed_worker(PAID_GATHERER, WorkerData.Profession.LABORER, DUE_DAY - 7, DUE_DAY + 6)
	WorkerDatabase.workers_by_id[HAULER] = _seed_worker(HAULER, WorkerData.Profession.HAULER, DUE_DAY - 7, DUE_DAY - 1)
	WorkerDatabase.workers_by_id[IDLE_HAULER] = _seed_worker(IDLE_HAULER, WorkerData.Profession.HAULER, DUE_DAY - 7, DUE_DAY - 1)
	site_outputs = {HAUL_SITE: 0, IDLE_HAUL_SITE: 0}
	_set_time(DUE_DAY - 1, 9, 0)


func _seed_worker(id: String, profession: WorkerData.Profession, paid_from: int, paid_until: int) -> WorkerData:
	var worker: WorkerData = WorkerData.new()
	worker.worker_id = id
	worker.display_name = id
	worker.profession = profession
	worker.payroll_start_day = paid_from
	worker.payroll_paid_from_day = paid_from
	worker.payroll_paid_until_day = paid_until
	worker.payroll_period_rate = 2
	return worker


func _prepare_schedule() -> void:
	var gather_session = WorksiteSession.new()
	gather_session.minutes_per_unit = 1000.0
	gather_session.daily_stock_min = 10000
	gather_session.daily_stock_max = 10000
	var haul_session = WorksiteSession.new()
	haul_session.minutes_per_unit = 1000.0
	haul_session.daily_stock_min = 10000
	haul_session.daily_stock_max = 10000
	var idle_haul_session = WorksiteSession.new()
	idle_haul_session.minutes_per_unit = 1000.0
	idle_haul_session.daily_stock_min = 10000
	idle_haul_session.daily_stock_max = 10000
	schedule = DailySchedule.new()
	schedule.setup({GATHER_SITE: gather_session, HAUL_SITE: haul_session, IDLE_HAUL_SITE: idle_haul_session})
	hauling = Hauling.new()
	destination = PayrollDestination.new()
	hauling.origin_provider = func(_site_id: StringName, _id: String) -> Vector2: return Vector2.ZERO
	hauling.assigned_destination_provider = func(_path: NodePath): return destination
	hauling.output_count = _hauler_output_count
	hauling.take_output = _take_hauler_output
	hauling.return_output = _return_hauler_output
	hauling.speed = 1.0
	hauling.delivered.connect(func(_id: String, _quantity: int): pass)
	schedule.hauling = hauling
	schedule.hauler_ready = func(_site_id: StringName, _count: int) -> String: return ""
	schedule.stock_min = 10000
	schedule.stock_max = 10000


func _start_assignments() -> void:
	_expect(schedule.toggle(GATHER_SITE, BLOCKED_GATHERER), "The soon-due gatherer can be assigned while its current period is paid.")
	_expect(schedule.toggle(GATHER_SITE, PAID_GATHERER), "The still-paid gatherer can join the same standing assignment.")
	_expect(schedule.start(GATHER_SITE, _drop_daily_output), "Both gatherers start a standing worksite assignment.")
	_expect(schedule.select_hauler(HAUL_SITE, HAULER, NodePath("PayrollStorage"), "Payroll Storage", 3),
		"The Hauler can be assigned a local fixture destination and daily receipt target.")
	_expect(schedule.start(HAUL_SITE, _drop_daily_output), "The Hauler starts a separate standing assignment.")
	_expect(schedule.select_hauler(IDLE_HAUL_SITE, IDLE_HAULER, NodePath("PayrollStorage"), "Payroll Storage", 3),
		"A second Hauler can be assigned for the no-new-load boundary check.")
	_expect(schedule.start(IDLE_HAUL_SITE, _drop_daily_output), "The second Hauler starts with no available cargo.")


func _test_gather_pause_and_paid_coworker() -> void:
	_drive_to(DUE_DAY, 7, 0)
	site_outputs[HAUL_SITE] = 3
	_drive_to(DUE_DAY, 7, 59)
	var gather_job: Dictionary = schedule.jobs[GATHER_SITE]
	var due_progress_before_settlement: float = float(gather_job.progress[BLOCKED_GATHERER])
	var paid_progress_before_settlement: float = float(gather_job.progress[PAID_GATHERER])
	_expect(due_progress_before_settlement == 59.0 and paid_progress_before_settlement == 59.0,
		"Both gatherers retain partial work through the minute before the renewal boundary.")
	site_outputs[IDLE_HAUL_SITE] = 3
	_set_time(DUE_DAY, 8, 0)
	WorkerDatabase.payroll_settling.emit()
	var route_at_pause: Dictionary = hauling.routes[HAULER]
	hauler_start_at_pause = int(route_at_pause.start)
	hauler_arrival_at_pause = int(route_at_pause.arrival)
	hauler_position_at_pause = hauling.get_visual(HAULER, float(schedule.now()) + 0.5).get("position", Vector2.ZERO)
	var flushed_due_progress: float = float(gather_job.progress[BLOCKED_GATHERER])
	var flushed_paid_progress: float = float(gather_job.progress[PAID_GATHERER])
	schedule.tick()
	_expect(schedule.last_tick == schedule.now()
		and float(gather_job.progress[BLOCKED_GATHERER]) == flushed_due_progress
		and float(gather_job.progress[PAID_GATHERER]) == flushed_paid_progress,
		"The ordinary minute signal after settlement is a no-op and cannot process the interval twice.")
	_expect(WorkerDatabase.get_worker_data(BLOCKED_GATHERER).is_payroll_blocked()
		and not WorkerDatabase.get_worker_data(PAID_GATHERER).is_payroll_blocked(),
		"Only the gatherer whose renewal is due is blocked.")
	_set_time(DUE_DAY, 8, 1)
	schedule.tick()
	_expect(float(gather_job.progress[BLOCKED_GATHERER]) == flushed_due_progress
		and float(gather_job.progress[PAID_GATHERER]) == flushed_paid_progress + 1.0,
		"Unpaid gathering pauses while a coworker with remaining paid days keeps progressing.")
	_expect(schedule.active_count(GATHER_SITE) == 1
		and schedule.activity(GATHER_SITE, BLOCKED_GATHERER) == WorkerData.WorkStatus.RESTING,
		"The paused assignment remains reserved and reports no active labor.")
	var idle_route: Dictionary = hauling.routes[IDLE_HAULER]
	_expect(idle_route.phase == Hauling.PHASE_IDLE and int(idle_route.cargo.quantity) == 0
		and int(site_outputs[IDLE_HAUL_SITE]) == 3,
		"The boundary flush cannot pick up a new load for a Hauler whose renewal is blocked.")
	var management = WorkerManagement.new()
	var blocked_wage: String = management._wage_text(WorkerDatabase.get_worker_data(BLOCKED_GATHERER))
	var paid_wage: String = management._wage_text(WorkerDatabase.get_worker_data(PAID_GATHERER))
	_expect(blocked_wage.contains("renewal blocked") and not blocked_wage.contains("paid days"),
		"The worker panel shows a blocked renewal instead of stale paid dates.")
	_expect(paid_wage.contains("next due Day %d, 08:00" % (DUE_DAY + 7)),
		"Paid workers see their next renewal date and 08:00 time.")
	_drive_to(DUE_DAY, 15, 0)
	_expect(float(gather_job.progress[BLOCKED_GATHERER]) == flushed_due_progress
		and float(gather_job.progress.get(PAID_GATHERER, 0.0)) == 0.0,
		"Shift-end cleanup preserves the unpaid worker's partial progress and keeps normal paid-worker cleanup.")
	_expect(schedule.reserved_count(GATHER_SITE) == 2
		and WorkerDatabase.get_worker_data(BLOCKED_GATHERER).is_reserved(),
		"Payroll pause keeps the worker assigned instead of releasing the standing job.")


func _test_hauler_pause_and_resume() -> void:
	var route: Dictionary = hauling.routes[HAULER]
	var cargo_before_pause: int = int(route.cargo.quantity)
	var output_before_pause: int = int(site_outputs[HAUL_SITE])
	var paused_at_boundary: Dictionary = hauling.get_visual(HAULER, float(schedule.now()) + 0.5)
	_expect(route.phase == Hauling.PHASE_OUTBOUND and cargo_before_pause == 3 and output_before_pause == 0,
		"The Hauler begins one bounded trip and carries its one consumed load.")
	_expect(not bool(paused_at_boundary.get("moving", true)),
		"Visual interpolation remains stationary while payroll is blocked.")
	var pause_position: Vector2 = paused_at_boundary.get("position", Vector2.ZERO)
	_expect(pause_position.is_equal_approx(hauler_position_at_pause),
		"The visual position captured at 08:00 remains the route's position for the unpaid interval.")
	_drive_to(DUE_DAY, 15, 0)
	var paused_visual: Dictionary = hauling.get_visual(HAULER, float(schedule.now()) + 0.5)
	_expect(not bool(paused_visual.get("moving", true))
		and paused_visual.get("position", Vector2.ZERO).is_equal_approx(pause_position),
		"The Hauler stays at the same position through the unpaid remainder of the shift.")
	_expect(int(route.cargo.quantity) == cargo_before_pause and int(site_outputs[HAUL_SITE]) == output_before_pause
		and destination.receipts.is_empty(),
		"A paused Hauler keeps its cargo and does not take or deliver a second load.")
	_expect(int(route.start) == hauler_start_at_pause + (15 * 60 - 8 * 60)
		and int(route.arrival) == hauler_arrival_at_pause + (15 * 60 - 8 * 60),
		"Both Hauler route boundaries shift by the unpaid minutes already elapsed.")
	_drive_to(RESUME_DAY, 8, 0)
	WorkerDatabase.payroll_settling.emit()
	var hauler_worker: WorkerData = WorkerDatabase.get_worker_data(HAULER)
	var route_after_settlement: Dictionary = hauling.routes[HAULER]
	_expect(schedule.last_tick == schedule.now()
		and int(route_after_settlement.start) == hauler_start_at_pause + 1440
		and int(route_after_settlement.arrival) == hauler_arrival_at_pause + 1440,
		"The pre-settlement flush shifts the route by the full unpaid day exactly once.")
	hauler_worker.payroll_paid_from_day = RESUME_DAY
	hauler_worker.payroll_paid_until_day = RESUME_DAY + 6
	var resumed_visual: Dictionary = hauling.get_visual(HAULER, float(schedule.now()) + 0.5)
	var resumed_x: float = resumed_visual.get("position", Vector2.ZERO).x
	_expect(bool(resumed_visual.get("moving", false))
		and resumed_x >= pause_position.x and resumed_x - pause_position.x <= 1.0,
		"After payment, the Hauler resumes just ahead of its frozen position without jumping.")
	_drive_to(RESUME_DAY, 8, 1)
	_expect(destination.receipts.size() == 1 and int(destination.receipts[0].quantity) == 3
		and int(route_after_settlement.cargo.quantity) == 0,
		"The carried load is delivered exactly once after the route's shifted arrival.")
	schedule.tick()
	hauling.tick(schedule.now(), func(_id: String) -> bool: return false,
		func(_site_id: StringName) -> bool: return false)
	_expect(destination.receipts.size() == 1,
		"Repeating the post-arrival tick does not duplicate the delivery.")


func _drive_to(day: int, hour: int, minute: int) -> void:
	var target: int = day * 1440 + hour * 60 + minute
	var current: int = schedule.now()
	while current < target:
		current += 1
		_set_absolute_minute(current)
		schedule.tick()


func _set_absolute_minute(value: int) -> void:
	_set_time(value / 1440, (value % 1440) / 60, value % 60)


func _set_time(day: int, hour: int, minute: int) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute


func _hauler_output_count(_site_id: StringName) -> int:
	return int(site_outputs.get(_site_id, 0))


func _take_hauler_output(_site_id: StringName, quantity: int) -> int:
	var available: int = int(site_outputs.get(_site_id, 0))
	var taken: int = mini(quantity, available)
	site_outputs[_site_id] = available - taken
	return taken


func _return_hauler_output(_site_id: StringName, quantity: int) -> bool:
	site_outputs[_site_id] = int(site_outputs.get(_site_id, 0)) + quantity
	return true


func _drop_daily_output(_quantity: int) -> bool:
	return true


func _finish() -> void:
	_restore()
	print("ClayWorksitePayrollTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)


func _restore() -> void:
	if restored or saved.is_empty():
		return
	restored = true
	if schedule != null:
		schedule.cleanup()
	WorkerDatabase.workers_by_id = saved.workers
	WorkerDatabase.dismissed_workers = saved.dismissed
	CitizenManager.citizens_by_id = saved.citizens
	TimeComponentManager.current_day = int(saved.day)
	TimeComponentManager.current_hour = int(saved.hour)
	TimeComponentManager.current_minute = int(saved.minute)
	TimeComponentManager.current_weather = str(saved.weather)
	TimeComponentManager._timer = float(saved.timer)
	TimeComponentManager.is_paused = bool(saved.paused)
	TimeComponentManager.set_process(bool(saved.processing))
	get_tree().paused = bool(saved.tree_paused)


func _exit_tree() -> void:
	_restore()
