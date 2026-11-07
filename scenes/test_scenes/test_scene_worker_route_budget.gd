extends Node

## Uses the actual city, clock, payroll and work state. Citizens, funds,
## cleaned plot, positions and enclosing walls are controlled test fixtures.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const NAV = preload("res://scenes/content_scene/worksites/worksite_navigation.gd")
const HOUSE_ID: String = "construction:citizen_house_1"
var failures: int = 0
var runtime: Node
var visuals: Node
var state: Node
var navigation: RefCounted
var fixture_geometry: Node2D
var gate: CollisionPolygon2D
var blocked: Array[WorkerData] = []
var open_worker: WorkerData
var credited: int = 0
var open_at: int = -1
var reopened: bool = false
var last_positions: Dictionary = {}
var unsafe_movement: bool = false

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _hire(id: String) -> WorkerData:
	var citizen := CitizenData.new()
	citizen.citizen_id = id
	citizen.display_name = id
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	citizen.satisfaction = 0.95
	citizen.visual_profile = VisualProfile.new()
	CitizenManager.add_citizen(citizen)
	_expect(CitizenManager.register_applicant(id, WorkerData.Profession.LABORER), "The fixture citizen can apply")
	var worker: WorkerData = WorkerDatabase.hire_applicant(id, 1, 9)
	_expect(worker != null and not worker.is_payroll_blocked(), "The fixture worker has a paid contract")
	return worker

func _observe(next_minute: int) -> void:
	var current: int = next_minute - 1
	for worker: WorkerData in blocked + [open_worker]:
		var position: Vector2 = worker.physical_approach.get("position", Vector2.INF)
		if last_positions.has(worker.worker_id) and position.distance_to(last_positions[worker.worker_id]) > 0.001:
			if position.distance_to(last_positions[worker.worker_id]) > 24.01 or not navigation.is_clear(position):
				unsafe_movement = true
		last_positions[worker.worker_id] = position
	if current % 1440 >= 7 * 60 and current % 1440 < 15 * 60:
		for id: String in state.worker_ids:
			var worker: WorkerData = WorkerDatabase.get_worker_data(id)
			if worker != null and worker.get_resolved_satisfaction() > 0.0 and not worker.resignation_pending:
				credited += worker.get_arrived_paid_minutes(current, next_minute, "plot", HOUSE_ID + ":building", HOUSE_ID)

func _change_collision(_minute: int) -> void:
	if not reopened and _now() >= open_at:
		# Change an actual fixture collider during a synchronous skip, with no
		# frame; configure uses the normal collision-geometry revision.
		gate.disabled = true
		navigation.configure(fixture_geometry)
		reopened = true

func _wall(center: Vector2, a: Vector2, b: Vector2) -> PackedVector2Array:
	return PackedVector2Array([center + a, center + Vector2(b.x, a.y), center + b, center + Vector2(a.x, b.y)])

func _add_collider(points: PackedVector2Array) -> CollisionPolygon2D:
	var body := StaticBody2D.new()
	fixture_geometry.add_child(body)
	var shape := CollisionPolygon2D.new()
	shape.polygon = points
	body.add_child(shape)
	return shape

func _test_resumable_detour() -> void:
	var nav: RefCounted = NAV.new()
	nav.polygons.append(_wall(Vector2.ZERO, Vector2(-8, -8), Vector2(8, 8)))
	var origin := Vector2(-40, 0)
	var target := Vector2(40, 0)
	var baseline: PackedVector2Array = nav.route(origin, target)
	var search: RefCounted = nav.begin_bounded_route(origin, target)
	var rounds: int = 0
	while search.status == "pending" and rounds < 10000:
		var used: int = search.step(64, Time.get_ticks_usec() + 10000)
		_expect(used <= 64, "Each incremental search slice respects its work budget")
		if search.status == "pending":
			_expect(search.path.is_empty(), "An unfinished search never returns a partial route")
		rounds += 1
	_expect(not baseline.is_empty() and search.status == "found" and search.path == baseline and rounds > 1,
		"A real detour resumes over multiple slices and matches the existing route")
	for index: int in range(1, search.path.size()):
		_expect(nav.segment_clear(search.path[index - 1], search.path[index]), "Every completed detour segment clears collision")
	print("ROUTE_DETOUR slices=", rounds, " operations=", search.operations, " status=", search.status)

func _run() -> void:
	_test_resumable_detour()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	TimeComponentManager.emit_time_signal()
	var content: Node = CONTENT.instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	for frame: int in range(4):
		await get_tree().process_frame
	runtime = content.get_node("YSortWorld/WorkerRuntime")
	visuals = runtime.get_node("WorkerVisuals")
	visuals.set_process(false)
	state = content.get_node("YSortWorld/CitizenHousePlot").construction
	var player: Player = content.get_node("YSortWorld/Player")
	_expect(not player.debug_disable_player_needs and not player.debug_disable_fatigue, "Player needs remain enabled")
	Inventory.add_item("shekel", 100)
	var ids: Array[String] = []
	for index: int in range(5):
		var worker: WorkerData = _hire("route_budget_%d" % index)
		if worker == null:
			_finish()
			return
		ids.append(worker.worker_id)
		if index < 4:
			blocked.append(worker)
		else:
			open_worker = worker
	TimeComponentManager.current_day = 1
	TimeComponentManager.current_hour = 7
	TimeComponentManager.current_minute = 0
	TimeComponentManager.emit_time_signal()
	state.phase = "empty" # Cleaning is covered by the full house integration test.
	state.changed.emit()
	Inventory.add_bulk_item({"wood_log": 4, "clay_lump": 8, "reed_bundle": 6})
	_expect(bool(state.start_build(ids).get("success", false)), "Five paid workers can start the fixture house")
	for frame: int in range(5):
		await get_tree().process_frame
	_expect(runtime.can_simulate_plot_travel(), "The real runtime has current geometry")
	var target: Vector2 = state.worker_entry_position
	var trapped_origin: Vector2 = target + Vector2(-64, 0)
	navigation = NAV.new()
	fixture_geometry = Node2D.new()
	add_child(fixture_geometry)
	_add_collider(_wall(trapped_origin, Vector2(-16, -16), Vector2(16, -12)))
	_add_collider(_wall(trapped_origin, Vector2(-16, 12), Vector2(16, 16)))
	_add_collider(_wall(trapped_origin, Vector2(-16, -12), Vector2(-12, 12)))
	gate = _add_collider(_wall(trapped_origin, Vector2(12, -12), Vector2(16, 12)))
	_add_collider(_wall(Vector2(10000, 10000), Vector2.ZERO, Vector2(100, 100)))
	navigation.configure(fixture_geometry)
	runtime.worksite_navigation = navigation
	_expect(navigation.is_clear(trapped_origin) and navigation.is_clear(target), "The trapped origin and destination are both clear")
	for worker: WorkerData in blocked:
		worker.begin_physical_approach("plot", HOUSE_ID + ":building", HOUSE_ID, trapped_origin, target)
	open_worker.begin_physical_approach("plot", HOUSE_ID + ":building", HOUSE_ID, target + Vector2(0, 8), target)
	visuals.plot_presence.states.clear()
	TimeComponentManager.simulated_minute_started.connect(_observe)
	var initial_work: int = state._remaining_work_units()
	var before: int = _now()
	var start_usec: int = Time.get_ticks_usec()
	_expect(TimeComponentManager.advance_minutes(2), "Two fixture minutes advance")
	_expect(open_worker.physical_approach.get("arrived", false), "A worker with a valid route is not starved by four blocked workers")
	for worker: WorkerData in blocked:
		_expect(not worker.physical_approach.get("arrived", false) and worker.physical_approach.position == trapped_origin,
			"An enclosed worker neither arrives nor teleports")
	_expect(initial_work - state._remaining_work_units() == credited and credited == 1,
		"Only the physically arrived, paid worker contributes the first work unit")
	player.fatigue = 0.0
	var overlay: Node = content.get_node("TimeDebugOverlay")
	overlay._refresh_controls()
	_expect(overlay.can_advance() and not overlay.step_buttons[1].disabled, "The actual Debug +1d control is available")
	overlay.step_buttons[1].pressed.emit()
	var elapsed_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	_expect(_now() == before + 1442, "The Debug control advances exactly one full day")
	for worker: WorkerData in blocked:
		_expect(not worker.physical_approach.get("arrived", false) and worker.physical_approach.position == trapped_origin,
			"An enclosed worker still has no false arrival or movement after +1d")
	_expect(initial_work - state._remaining_work_units() == credited,
		"The whole skip credits only real arrival, shift, contract and satisfaction")
	_expect(visuals.plot_presence.route_budget_operations >= 0,
		"Route-search work stays within the shared per-frame operation budget")
	print("ROUTE_BUDGET +1d elapsed_ms=", elapsed_ms, " credited=", credited,
		" remaining_ops=", visuals.plot_presence.route_budget_operations,
		" remaining_usec=", visuals.plot_presence.route_budget_usec)
	open_at = _now() + 2
	TimeComponentManager.minute_changed.connect(_change_collision)
	_expect(TimeComponentManager.advance_minutes(10) and reopened, "The fixture opens the collider during a frame-free skip")
	TimeComponentManager.minute_changed.disconnect(_change_collision)
	for worker: WorkerData in blocked:
		_expect(not worker.physical_approach.get("arrived", false), "A newly opened route is never assumed to have been traveled")
	await get_tree().process_frame
	_expect(TimeComponentManager.advance_minutes(120), "The next frame can resume bounded searches")
	for worker: WorkerData in blocked:
		_expect(worker.physical_approach.get("arrived", false), "A worker retries and reaches the plot after geometry revision")
	_expect(initial_work - state._remaining_work_units() == credited,
		"Reopening geometry does not create false work or duplicate credit")
	# Now enclose the destination, rather than the origins. The far collider
	# made the old unbounded grid search run for more than fifteen seconds.
	_add_collider(_wall(target, Vector2(-16, -16), Vector2(16, -12)))
	_add_collider(_wall(target, Vector2(-16, 12), Vector2(16, 16)))
	_add_collider(_wall(target, Vector2(-16, -12), Vector2(-12, 12)))
	_add_collider(_wall(target, Vector2(12, -12), Vector2(16, 12)))
	navigation.configure(fixture_geometry)
	var outside: Vector2 = target + Vector2(64, 0)
	_expect(navigation.is_clear(outside) and navigation.is_clear(target) and not navigation.segment_clear(outside, target),
		"A clear origin and a clear destination are separated by an enclosed target")
	for worker: WorkerData in blocked + [open_worker]:
		worker.begin_physical_approach("plot", HOUSE_ID + ":building", HOUSE_ID, outside, target)
		last_positions[worker.worker_id] = outside # This fixture repositions the workers.
	visuals.plot_presence.states.clear()
	await get_tree().process_frame
	player.fatigue = 0.0
	overlay._refresh_controls()
	_expect(overlay.can_advance() and not overlay.step_buttons[1].disabled, "The second Debug +1d is available")
	var sealed_work: int = state._remaining_work_units()
	var sealed_clock: int = _now()
	start_usec = Time.get_ticks_usec()
	overlay.step_buttons[1].pressed.emit()
	var sealed_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	_expect(_now() == sealed_clock + 1440 and state._remaining_work_units() == sealed_work,
		"An enclosed target advances a day without granting work")
	for worker: WorkerData in blocked + [open_worker]:
		_expect(not worker.physical_approach.get("arrived", false), "No worker arrives inside the enclosed target")
	_expect(visuals.plot_presence.route_budget_operations >= 0,
		"The enclosed-target skip stays inside the shared operation budget")
	var frame_before: int = Engine.get_process_frames()
	var budget_before: int = visuals.plot_presence.route_budget_usec
	var operations_before: int = visuals.plot_presence.route_budget_operations
	visuals.plot_presence.update(visuals, 0.0)
	_expect(Engine.get_process_frames() == frame_before and visuals.plot_presence.route_budget_usec <= budget_before
		and visuals.plot_presence.route_budget_operations <= operations_before,
		"A normal visual update in the same frame cannot reset the skip's planning budget")
	print("ROUTE_SEALED_TARGET +1d elapsed_ms=", sealed_ms,
		" remaining_ops=", visuals.plot_presence.route_budget_operations,
		" remaining_usec=", visuals.plot_presence.route_budget_usec)
	_expect(not unsafe_movement, "Each simulated move stays within walking speed and ends clear of colliders")
	TimeComponentManager.simulated_minute_started.disconnect(_observe)
	_finish()

func _finish() -> void:
	print("WorkerRouteBudgetTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
