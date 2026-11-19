extends Node

## Two test-only house plots use real retained construction, route and geometry.
## The first finishes in the city or while its runtime is parked at home.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const HOUSE: PackedScene = preload("res://scenes/citizen_house_plot/citizen_house_plot.tscn")
const HOME_PATH: String = "res://scenes/player_home_interior/player_home_interior.tscn"
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _worker(id: String) -> WorkerData:
	var worker := WorkerData.new()
	worker.worker_id = id
	worker.display_name = id
	worker.profession = WorkerData.Profession.LABORER
	worker.satisfaction = 0.95
	WorkerDatabase.workers_by_id[id] = worker
	return worker

func _run() -> void:
	var at_home: bool = OS.get_cmdline_user_args().has("--home")
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	TimeComponentManager.emit_time_signal()
	var city: Node = CONTENT.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	for frame: int in range(4):
		await get_tree().process_frame
	var runtime: Node = city.get_node("YSortWorld/WorkerRuntime")
	var visuals: Node = runtime.get_node("WorkerVisuals")
	visuals.set_process(false)
	var world: Node2D = city.get_node("YSortWorld")
	var first_house: Node2D = world.get_node("CitizenHousePlot")
	var unchanged_state: Node = world.get_node("WorkshopPlot2").construction
	var second_house: Node2D = HOUSE.instantiate()
	second_house.plot_id = "collision_fixture_second_house"
	world.add_child(second_house)
	first_house.global_position = Vector2(800, 400)
	second_house.global_position = Vector2(875, 406)
	second_house.get_node("WorkerEntrance").position = Vector2.ZERO
	var first_state: Node = first_house.construction
	var second_state: Node = second_house.construction
	first_state.worker_entry_position = first_house.get_worker_entry_position()
	second_state.worker_entry_position = second_house.get_worker_entry_position()
	first_state.phase = "empty"
	second_state.phase = "empty"
	first_state.changed.emit()
	second_state.changed.emit()
	for frame: int in range(4):
		await get_tree().process_frame
	runtime._refresh_navigation()
	var builder: WorkerData = _worker("collision_first")
	var traveller: WorkerData = _worker("collision_second")
	var target_a: Vector2 = first_house.get_worker_entry_position()
	var origin_b: Vector2 = first_house.global_position + Vector2(-75, 6)
	var target_b: Vector2 = second_house.get_worker_entry_position()
	_expect(runtime.worksite_navigation.segment_clear(origin_b, target_b), "The test route crosses the clear, unfinished house site")
	var actor_a: Node2D = visuals.ensure_actor(builder.worker_id, target_a + Vector2(0, -8))
	var actor_b: Node2D = visuals.ensure_actor(traveller.worker_id, origin_b - Vector2(0, 16))
	actor_a.global_position = target_a + Vector2(0, -8)
	actor_b.global_position = origin_b - Vector2(0, 16)
	Inventory.add_bulk_item({"wood_log": 8, "clay_lump": 16, "reed_bundle": 12})
	_expect(bool(first_state.start_build([builder.worker_id] as Array[String]).get("success", false)), "First house starts")
	_expect(bool(second_state.start_build([traveller.worker_id] as Array[String]).get("success", false)), "Second house starts")
	for frame: int in range(4):
		await get_tree().process_frame
	_expect(runtime.can_simulate_plot_travel(), "The unfinished plots have a fresh navigation snapshot")
	_expect(TimeComponentManager.advance_minutes(1) and builder.physical_approach.get("arrived", false),
		"The first builder actually follows the short clear route")
	_expect(not traveller.physical_approach.get("arrived", false), "The second builder is still on the crossing route")
	first_state.completes_at = first_state._latest_time + 1
	first_state.payroll_work_remainder = 0
	if at_home:
		var store: Node = WorkStateRuntime.get_node("CitySave")
		_expect(store.prepare_home_departure(city, HOME_PATH), "The normal city-to-home handoff retains the runtime")
		var change_result: Error = get_tree().change_scene_to_file(HOME_PATH)
		_expect(change_result == OK, "Open the actual home scene")
		for frame: int in range(5):
			await get_tree().process_frame
		_expect(store.parked_worksite == runtime and runtime.can_simulate_plot_travel(), "The parked city geometry remains current")
	_expect(TimeComponentManager.advance_minutes(1) and first_state.phase == "built", "The first house completes during skipped time")
	var stopped_at: Vector2 = traveller.physical_approach.position
	var first_body := Rect2(Vector2(781, 396), Vector2(38, 20))
	_expect(not first_body.has_point(stopped_at), "The second worker is outside the completed house")
	if at_home:
		_expect(runtime.can_simulate_plot_travel() and not runtime.worksite_navigation.segment_clear(origin_b, target_b),
			"The parked snapshot already includes the completed house before the next minute")
		var unchanged_revision: int = runtime.worksite_navigation.revision
		unchanged_state.phase = "clearing"
		unchanged_state.changed.emit()
		unchanged_state.phase = "empty"
		unchanged_state.changed.emit()
		_expect(runtime.can_simulate_plot_travel() and runtime.worksite_navigation.revision == unchanged_revision,
			"A clearing-to-empty transition with unchanged collision does not freeze or rebuild all routes")
		for frame: int in range(8):
			await get_tree().process_frame
		print("PARKED_HOUSE_RECHECK geometry_current=", runtime.can_simulate_plot_travel(),
			" phase=", first_state.phase, " position=", traveller.physical_approach.position)
		_expect(runtime.can_simulate_plot_travel(), "A completed house refreshes the retained geometry while the player remains home")
		_expect(not runtime.worksite_navigation.segment_clear(origin_b, target_b), "The parked navigation includes the completed house collider")
		for minute: int in range(20):
			await get_tree().process_frame
			var previous: Vector2 = traveller.physical_approach.position
			var old_route: Dictionary = visuals.plot_presence.states.get(traveller.worker_id, {}).duplicate(true)
			_expect(TimeComponentManager.advance_minutes(1), "The parked worker can advance after the collider update")
			var current: Vector2 = traveller.physical_approach.position
			var new_route: Dictionary = visuals.plot_presence.states.get(traveller.worker_id, {})
			_expect(_walked_segments_clear(runtime.worksite_navigation, previous, current, old_route, new_route),
				"Every inbound waypoint avoids the completed house")
			if traveller.physical_approach.arrived:
				break
		_expect(traveller.physical_approach.arrived, "The second builder arrives without the player leaving home")
		var before_work: int = second_state._remaining_work_units()
		_expect(TimeComponentManager.advance_minutes(3) and second_state._remaining_work_units() == before_work - 3,
			"Only minutes after the worker actually arrives contribute work")
		var to_close: int = 15 * 60 - TimeComponentManager.current_hour * 60 - TimeComponentManager.current_minute
		_expect(to_close > 0 and TimeComponentManager.advance_minutes(to_close)
			and int(traveller.physical_approach.arrival_minute) == WorkerData.PLOT_DEPARTURE_PENDING,
			"The next 15:00 shift close starts the retained outbound journey")
		var before_departure: Vector2 = traveller.physical_approach.position
		for frame: int in range(3):
			await get_tree().process_frame
		for minute: int in range(20):
			await get_tree().process_frame
			var previous: Vector2 = traveller.physical_approach.position
			var old_route: Dictionary = visuals.plot_presence.states.get(traveller.worker_id, {}).duplicate(true)
			_expect(TimeComponentManager.advance_minutes(1), "The parked worker advances outbound after shift")
			var current: Vector2 = traveller.physical_approach.position
			var new_route: Dictionary = visuals.plot_presence.states.get(traveller.worker_id, {})
			_expect(_walked_segments_clear(runtime.worksite_navigation, previous, current, old_route, new_route),
				"Every outbound waypoint avoids the completed house")
		_expect(traveller.physical_approach.position != before_departure and runtime.can_simulate_plot_travel(),
			"The outbound worker keeps moving with the player still at home")
		var route_before: Dictionary = visuals.plot_presence.states.get(traveller.worker_id, {})
		var status_before: String = str(route_before.get("status", "none"))
		var search_before: Variant = route_before.get("search")
		var operations_before: int = int(search_before.get("operations")) if is_instance_valid(search_before) else -1
		var phase_before: String = str(search_before.get("phase")) if is_instance_valid(search_before) else "none"
		var frame_before: int = Engine.get_process_frames()
		var position_before_staged: Vector2 = traveller.physical_approach.position
		var staged_result: Dictionary = await TimeComponentManager.advance_minutes_staged(1, self)
		var route_after: Dictionary = visuals.plot_presence.states.get(traveller.worker_id, {})
		print("HOME_STAGED_DIAGNOSTIC: status_before=", status_before,
			" phase_before=", phase_before, " operations_before=", operations_before,
			" result=", staged_result, " frames_waited=", Engine.get_process_frames() - frame_before,
			" route_after=", route_after.get("status", "none"),
			" moved=", traveller.physical_approach.position.distance_to(position_before_staged))
		var overnight_work: int = second_state._remaining_work_units()
		var until_open: int = 24 * 60 - TimeComponentManager.current_hour * 60 - TimeComponentManager.current_minute + 7 * 60
		_expect(TimeComponentManager.advance_minutes(until_open) and second_state._remaining_work_units() == overnight_work,
			"No work is credited overnight while the player remains home")
		for minute: int in range(180):
			await get_tree().process_frame
			var previous: Vector2 = traveller.physical_approach.position
			var old_route: Dictionary = visuals.plot_presence.states.get(traveller.worker_id, {}).duplicate(true)
			_expect(TimeComponentManager.advance_minutes(1), "The next shift can advance while still at home")
			var current: Vector2 = traveller.physical_approach.position
			var new_route: Dictionary = visuals.plot_presence.states.get(traveller.worker_id, {})
			_expect(_walked_segments_clear(runtime.worksite_navigation, previous, current, old_route, new_route),
				"The next-shift route still clears the completed house")
			if traveller.physical_approach.arrived:
				break
		_expect(traveller.physical_approach.arrived and second_state._remaining_work_units() == overnight_work,
			"The worker physically returns next shift before any work is credited")
		_expect(TimeComponentManager.advance_minutes(1) and second_state._remaining_work_units() == overnight_work - 1,
			"Work resumes only after the next-shift arrival")
	if not at_home:
		_expect(not runtime.can_simulate_plot_travel(), "The city snapshot is stale until deferred collider updates finish")
		_expect(TimeComponentManager.advance_minutes(5) and traveller.physical_approach.position == stopped_at
			and not traveller.physical_approach.arrived, "Skipped minutes never move the second builder through stale collision")
		visuals._process(1.0)
		_expect(traveller.physical_approach.position == stopped_at, "Ordinary frames also wait for refreshed city geometry")
		for frame: int in range(5):
			await get_tree().process_frame
		_expect(runtime.can_simulate_plot_travel(), "The city refreshes navigation after the collider is applied")
		_expect(not runtime.worksite_navigation.segment_clear(origin_b, target_b), "The finished house blocks the former straight route")
		for minute: int in range(20):
			await get_tree().process_frame
			var previous: Vector2 = traveller.physical_approach.position
			var old_route: Dictionary = visuals.plot_presence.states.get(traveller.worker_id, {}).duplicate(true)
			_expect(TimeComponentManager.advance_minutes(1), "The refreshed route advances")
			var current: Vector2 = traveller.physical_approach.position
			var new_route: Dictionary = visuals.plot_presence.states.get(traveller.worker_id, {})
			_expect(_walked_segments_clear(runtime.worksite_navigation, previous, current, old_route, new_route),
				"Every actual waypoint segment avoids the completed house")
			if traveller.physical_approach.arrived:
				break
		_expect(traveller.physical_approach.arrived, "The builder follows a safe replacement route after geometry refresh")
	print("SkippedHouseCollisionTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _walked_segments_clear(navigation: RefCounted, previous: Vector2, current: Vector2, old_state: Dictionary, new_state: Dictionary) -> bool:
	if previous.is_equal_approx(current):
		return navigation.is_clear(current)
	var route: PackedVector2Array = new_state.get("route", PackedVector2Array())
	if route.is_empty():
		return false
	var first_index: int = int(old_state.get("index", 0)) if old_state.get("route", PackedVector2Array()) == route else 0
	var end_index: int = mini(int(new_state.get("index", 0)), route.size())
	var cursor: Vector2 = previous
	var distance: float = 0.0
	for index: int in range(first_index, end_index):
		var waypoint: Vector2 = route[index]
		if not navigation.segment_clear(cursor, waypoint):
			return false
		distance += cursor.distance_to(waypoint)
		cursor = waypoint
	if not navigation.segment_clear(cursor, current):
		return false
	distance += cursor.distance_to(current)
	return distance <= 24.001 # One skipped minute uses at most one second of walking.
