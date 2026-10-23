extends Node

const WORKSITE_FIXTURE_PATH: String = "res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn"
const SITE_ID: StringName = &"ClaySiteA"
const SHIFT_START_MINUTE: int = 7 * 60
const EXPECTED_SCENARIOS: int = 3

var failures: int = 0
var checks: int = 0
var completed_scenarios: int = 0
var original_clock_processing: bool = true
var original_clock_paused: bool = false
var original_seconds_per_minute: float = 1.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	original_clock_processing = TimeComponentManager.is_processing()
	original_clock_paused = TimeComponentManager.is_paused
	original_seconds_per_minute = TimeComponentManager.seconds_per_minute
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = true
	# Keep automatic visual fractions negligible; this test advances visuals directly.
	TimeComponentManager.seconds_per_minute = 1000000.0
	print("LateCommuteVisualSentinel: started")

	_set_clock(6, 0)
	await _test_early_assignment_keeps_seven_am_arrival()
	_set_clock(6, 59)
	await _test_assignment_after_planned_departure()
	_set_clock(12, 0)
	await _test_midshift_assignment_and_reassignment()

	_expect(completed_scenarios == EXPECTED_SCENARIOS,
		"All early, late-morning, and midshift commute scenarios completed.")
	print("LateCommuteVisualSentinel: completed %d/%d scenarios; %d checks; %d failures" % [
		completed_scenarios, EXPECTED_SCENARIOS, checks, failures])
	var passed: bool = failures == 0 and completed_scenarios == EXPECTED_SCENARIOS
	print("LateCommuteVisualTest %s" % ("PASSED" if passed else "FAILED"))
	TimeComponentManager.seconds_per_minute = original_seconds_per_minute
	TimeComponentManager.is_paused = original_clock_paused
	TimeComponentManager.set_process(original_clock_processing)
	get_tree().quit(0 if passed else 1)


func _test_early_assignment_keeps_seven_am_arrival() -> void:
	const worker_id: String = "late_commute_early_worker"
	var fixture = await _create_fixture(worker_id)
	if not is_instance_valid(fixture):
		await _finish_fixture(fixture, worker_id)
		return
	if not _start_assignment(fixture, worker_id, "06:00"):
		await _finish_fixture(fixture, worker_id)
		return
	var route: Dictionary = fixture.worker_journey(SITE_ID, worker_id, TimeComponentManager.current_day)
	if not _valid_route(route):
		_expect(false, "The 06:00 assignment creates a complete commute route.")
		await _finish_fixture(fixture, worker_id)
		return
	var now: int = _now()
	var shift_start: int = TimeComponentManager.current_day * 1440 + SHIFT_START_MINUTE
	_expect(float(route.start) > now and float(route.start) < shift_start and int(route.arrival) == shift_start,
		"A 06:00 assignment keeps its planned commute and still arrives at 07:00.")
	var visuals = fixture.get_node("WorkerVisuals")
	_visual_tick(visuals, 0.0)
	var actor: Node2D = visuals.actors.get(worker_id) as Node2D
	_expect(actor != null and not actor.visible,
		"The early worker stays hidden until the planned departure time.")
	completed_scenarios += 1
	await _finish_fixture(fixture, worker_id)


func _test_assignment_after_planned_departure() -> void:
	const worker_id: String = "late_commute_0659_worker"
	var fixture = await _create_fixture(worker_id)
	if not is_instance_valid(fixture):
		await _finish_fixture(fixture, worker_id)
		return
	if not _start_assignment(fixture, worker_id, "06:59"):
		await _finish_fixture(fixture, worker_id)
		return
	var route: Dictionary = fixture.worker_journey(SITE_ID, worker_id, TimeComponentManager.current_day)
	if not _valid_route(route):
		_expect(false, "The 06:59 assignment creates a complete commute route.")
		await _finish_fixture(fixture, worker_id)
		return
	var now: int = _now()
	_expect(float(route.start) >= now and int(route.arrival) > now,
		"A 06:59 assignment starts its visual journey now instead of retaining a past departure.")
	_expect(route.origin.is_equal_approx(fixture.worker_spawn(SITE_ID, worker_id)),
		"The first late assignment starts from the worker's authored origin.")
	var actor: Node2D = _check_route_visual_progress(fixture, worker_id, route, "06:59")
	if actor == null:
		await _finish_fixture(fixture, worker_id)
		return
	TimeComponentManager.advance_minutes(1)
	_visual_tick(fixture.get_node("WorkerVisuals"), 0.0)
	_expect(_now() == TimeComponentManager.current_day * 1440 + SHIFT_START_MINUTE
		and int(fixture.daily.minutes_by_worker.get(worker_id, 0)) == 0,
		"The shift boundary itself adds no work minute before 07:00.")
	TimeComponentManager.advance_minutes(1)
	_visual_tick(fixture.get_node("WorkerVisuals"), 0.0)
	_expect(int(fixture.daily.minutes_by_worker.get(worker_id, 0)) == 1
		and actor.global_position.distance_to(route.target) > 0.1,
		"Production starts at 07:00 while the late-assigned worker is still visibly travelling.")
	_advance_visual_to_arrival(fixture, worker_id, route, actor)
	completed_scenarios += 1
	await _finish_fixture(fixture, worker_id)


func _test_midshift_assignment_and_reassignment() -> void:
	const worker_id: String = "late_commute_midshift_worker"
	var fixture = await _create_fixture(worker_id)
	if not is_instance_valid(fixture):
		await _finish_fixture(fixture, worker_id)
		return
	if not _start_assignment(fixture, worker_id, "12:00"):
		await _finish_fixture(fixture, worker_id)
		return
	var initial_route: Dictionary = fixture.worker_journey(SITE_ID, worker_id, TimeComponentManager.current_day)
	if not _valid_route(initial_route):
		_expect(false, "The 12:00 assignment creates a complete commute route.")
		await _finish_fixture(fixture, worker_id)
		return
	_expect(float(initial_route.start) >= _now() and int(initial_route.arrival) > _now(),
		"A 12:00 assignment begins its visual journey at or after the current time.")
	var actor: Node2D = _check_route_visual_progress(fixture, worker_id, initial_route, "12:00")
	if actor == null:
		await _finish_fixture(fixture, worker_id)
		return
	TimeComponentManager.advance_minutes(1)
	_visual_tick(fixture.get_node("WorkerVisuals"), 0.0)
	_expect(int(fixture.daily.minutes_by_worker.get(worker_id, 0)) == 1
		and actor.global_position.distance_to(initial_route.target) > 0.1,
		"A midshift assignment records one production minute while its actor is still travelling.")

	var position_before_reassignment: Vector2 = actor.global_position
	var withdrawn: bool = fixture.daily.withdraw(SITE_ID, worker_id)
	_expect(withdrawn, "The moving worker can be withdrawn from the site.")
	if not withdrawn or not _start_assignment(fixture, worker_id, "12:01 reassign"):
		await _finish_fixture(fixture, worker_id)
		return
	var reassigned_route: Dictionary = fixture.worker_journey(SITE_ID, worker_id, TimeComponentManager.current_day)
	if not _valid_route(reassigned_route):
		_expect(false, "The reassignment creates a complete replacement commute route.")
		await _finish_fixture(fixture, worker_id)
		return
	_expect(reassigned_route.origin.is_equal_approx(position_before_reassignment)
		and not reassigned_route.origin.is_equal_approx(initial_route.origin),
		"Reassignment uses the actor's moved position instead of the previous route origin.")
	_expect(float(reassigned_route.start) >= _now(),
		"The replacement route does not inherit a departure earlier than the reassignment time.")
	var visuals = fixture.get_node("WorkerVisuals")
	_visual_tick(visuals, 0.0)
	_expect(actor.global_position.is_equal_approx(position_before_reassignment),
		"The reassigned actor remains at its current position before the new route advances.")
	var moved_actor: Node2D = _check_route_visual_progress(fixture, worker_id, reassigned_route, "12:01 reassign")
	if moved_actor == null:
		await _finish_fixture(fixture, worker_id)
		return
	_advance_visual_to_arrival(fixture, worker_id, reassigned_route, moved_actor)
	completed_scenarios += 1
	await _finish_fixture(fixture, worker_id)


func _create_fixture(worker_id: String) -> Variant:
	var worker := WorkerData.new()
	worker.worker_id = worker_id
	worker.display_name = worker_id
	worker.profession = WorkerData.Profession.LABORER
	worker.wage_shekel_per_day = 1
	worker.payroll_start_day = TimeComponentManager.current_day
	worker.payroll_paid_from_day = TimeComponentManager.current_day
	worker.payroll_paid_until_day = TimeComponentManager.current_day + 3
	worker.payroll_period_rate = 1
	worker.payroll_contract_days = 3
	worker.payroll_paid_start_minute = TimeComponentManager.current_day * 1440
	WorkerDatabase.workers_by_id[worker_id] = worker
	_expect(worker.get_linked_citizen() == null and not worker.is_payroll_blocked(),
		"The worker fixture is explicitly paid and has no linked citizen or needs management.")

	var packed: PackedScene = load(WORKSITE_FIXTURE_PATH) as PackedScene
	if packed == null:
		_expect(false, "The existing clay worksite fixture loads.")
		return null
	var fixture = packed.instantiate()
	fixture.prepare_nightmare_test = false
	fixture.enable_worker_commute = true
	var player: Player = fixture.get_node("Player") as Player
	player.debug_disable_player_needs = true
	_expect(player.debug_disable_player_needs, "The fixture explicitly disables player needs.")
	add_child(fixture)
	await get_tree().process_frame
	return fixture


func _start_assignment(fixture: Variant, worker_id: String, scenario: String) -> bool:
	var selected: bool = fixture.daily.toggle(SITE_ID, worker_id)
	_expect(selected, "%s assignment selects the eligible worker." % scenario)
	if not selected:
		return false
	var drop: Callable = fixture._drop_daily_output.bind(fixture.get_node("WorksiteMarkers/ClaySiteA"))
	var started: bool = fixture.daily.start(SITE_ID, drop)
	_expect(started, "%s assignment starts the standing worksite job." % scenario)
	return started


func _check_route_visual_progress(fixture: Variant, worker_id: String, route: Dictionary, scenario: String) -> Node2D:
	var visuals = fixture.get_node("WorkerVisuals")
	_visual_tick(visuals, 0.0)
	var actor: Node2D = visuals.actors.get(worker_id) as Node2D
	if actor == null:
		_expect(false, "%s assignment creates a visible worker actor." % scenario)
		return null
	_expect(actor.visible and actor.global_position.is_equal_approx(route.origin),
		"%s actor appears at the route origin without teleporting." % scenario)
	var before_step: Vector2 = actor.global_position
	_visual_tick(visuals, 0.5)
	var after_step: Vector2 = actor.global_position
	_expect(after_step.distance_to(before_step) > 0.1
		and after_step.distance_to(route.target) > 0.1,
		"%s actor advances along the route while remaining short of its destination." % scenario)
	var after_first_frame: Dictionary = fixture.worker_journey(SITE_ID, worker_id, TimeComponentManager.current_day)
	_expect(_same_route(route, after_first_frame),
		"%s route stays stable after the first visual frame." % scenario)
	_visual_tick(visuals, 0.5)
	var after_second_frame: Vector2 = actor.global_position
	_expect(after_second_frame.distance_to(after_step) > 0.1,
		"%s actor continues walking on the next visual frame." % scenario)
	var after_second_route: Dictionary = fixture.worker_journey(SITE_ID, worker_id, TimeComponentManager.current_day)
	_expect(_same_route(route, after_second_route),
		"%s route origin, target, and timing remain stable across frames." % scenario)
	return actor


func _advance_visual_to_arrival(fixture: Variant, worker_id: String, route: Dictionary, actor: Node2D) -> void:
	while _now() < int(route.arrival):
		TimeComponentManager.advance_minutes(1)
		_visual_tick(fixture.get_node("WorkerVisuals"), 0.0)
	_expect(actor.visible and actor.global_position.is_equal_approx(route.target),
		"The travelling actor reaches its assigned site target.")


func _finish_fixture(fixture: Variant, worker_id: String) -> void:
	if is_instance_valid(fixture):
		if fixture.daily.jobs.has(SITE_ID) and fixture.daily.jobs[SITE_ID].ids.has(worker_id):
			fixture.daily.withdraw(SITE_ID, worker_id)
		fixture.queue_free()
	await get_tree().process_frame
	WorkerDatabase.workers_by_id.erase(worker_id)


func _valid_route(route: Dictionary) -> bool:
	return route.has("origin") and route.origin is Vector2 \
		and route.has("target") and route.target is Vector2 \
		and route.has("start") and route.has("arrival")


func _same_route(first: Dictionary, second: Dictionary) -> bool:
	return _valid_route(first) and _valid_route(second) \
		and first.origin.is_equal_approx(second.origin) \
		and first.target.is_equal_approx(second.target) \
		and is_equal_approx(float(first.start), float(second.start)) \
		and int(first.arrival) == int(second.arrival)


func _visual_tick(visuals: Variant, delta: float) -> void:
	var seconds_per_minute: float = TimeComponentManager.seconds_per_minute
	TimeComponentManager.seconds_per_minute = 1.0
	visuals.call("_process", delta)
	TimeComponentManager.seconds_per_minute = seconds_per_minute


func _set_clock(hour: int, minute: int) -> void:
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute


func _now() -> int:
	return TimeComponentManager.current_day * 1440 \
		+ TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("LateCommuteVisualTest: " + message)
