extends Node

## Separate-process Continue from home after a different workshop finishes.
## The clock placement, two applicants, paid funds/materials, nearly complete
## workshop and worker positions are fixtures; normal needs remain enabled.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const HOME_PATH: String = "res://scenes/player_home_interior/player_home_interior.tscn"
const CITY_PATH: String = "res://scenes/content_scene/content_scene.tscn"
const SAVE: String = "user://parked_navigation_continue/checkpoint.json"
const EVIDENCE: String = "user://parked_navigation_continue/evidence.json"
const A_ID: String = "parked_completion_builder"
const B_ID: String = "parked_travelling_builder"
const HOUSE_ORDER: String = "construction:citizen_house_1"
var failures: int = 0
var launched: bool = false

func _ready() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _hire(id: String) -> WorkerData:
	var person := CitizenData.new()
	person.citizen_id = id
	person.display_name = id
	person.population_status = CitizenData.PopulationStatus.RESIDENT
	person.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	person.satisfaction = 0.95
	person.visual_profile = VisualProfile.new()
	CitizenManager.add_citizen(person)
	_expect(CitizenManager.register_applicant(id, WorkerData.Profession.LABORER), "The fixture citizen is eligible to apply")
	var worker: WorkerData = WorkerDatabase.hire_applicant(id, 1, 9)
	_expect(worker != null and not worker.is_payroll_blocked(), "The fixture worker has a paid contract")
	return worker

func _worker_state(order: String) -> Node:
	for state: Node in WorkStateRuntime.get_node("CitySave").city_plots.values():
		if state.order_id == order:
			return state
	return null

func _run() -> void:
	var phase: String = ""
	var kind: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			phase = arg.trim_prefix("--phase=")
		if arg.begins_with("--kind="):
			kind = arg.trim_prefix("--kind=")
	_expect(phase in ["write", "read"] and kind in ["pending", "walking"], "Choose write/read and pending/walking")
	if failures > 0:
		_finish()
		return
	if phase == "write":
		await _write(kind)
	else:
		await _read(kind)
	_finish()

func _write(kind: String) -> void:
	_expect(not FileAccess.file_exists(SAVE), "The fixture writes only to an empty isolated checkpoint")
	if failures > 0:
		return
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var city: Node = CONTENT.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	for frame: int in range(7):
		await get_tree().process_frame
	var runtime: Node = city.get_node("YSortWorld/WorkerRuntime")
	var visuals: Node = runtime.get_node("WorkerVisuals")
	visuals.set_process(false)
	var player: Player = city.get_node("YSortWorld/Player")
	_expect(not player.debug_disable_player_needs and not player.debug_disable_fatigue, "Player needs and fatigue remain enabled")
	Inventory.max_load = 200 # Explicit fixture capacity for both material kits.
	Inventory.add_item("shekel", 100)
	var worker_a: WorkerData = _hire(A_ID)
	var worker_b: WorkerData = _hire(B_ID)
	if worker_a == null or worker_b == null:
		return
	var workshop: Node2D = city.get_node("YSortWorld/WorkshopPlot2")
	var house: Node2D = city.get_node("YSortWorld/CitizenHousePlot")
	var first: Node = workshop.construction
	var second: Node = house.construction
	first.phase = "empty"
	second.phase = "empty"
	first.changed.emit()
	second.changed.emit()
	for frame: int in range(7):
		await get_tree().process_frame
	Inventory.add_bulk_item(first.get_requirements())
	_expect(bool(first.start_build([A_ID] as Array[String]).get("success", false)), "The paid workshop build starts")
	Inventory.add_bulk_item(second.get_requirements())
	_expect(bool(second.start_build([B_ID] as Array[String]).get("success", false)), "The paid house build starts")
	for frame: int in range(7):
		await get_tree().process_frame
	_expect(runtime.can_simulate_plot_travel(), "The live city geometry is synchronized")
	var first_target: Vector2 = workshop.get_worker_entry_position()
	var first_origin: Vector2 = Vector2.INF
	for direction: Vector2 in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
		if runtime.worksite_navigation.segment_clear(first_target + direction * 8.0, first_target):
			first_origin = first_target + direction * 8.0
			break
	var second_target: Vector2 = house.get_worker_entry_position()
	var second_origin: Vector2 = Vector2.INF
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized(), Vector2(-1, 1).normalized()]:
		var candidate: Vector2 = second_target + direction * 220.0
		if runtime.worksite_navigation.is_clear(candidate):
			second_origin = candidate
			break
	_expect(first_origin.is_finite() and second_origin.is_finite(), "Both fixture positions are outside collision")
	if not first_origin.is_finite() or not second_origin.is_finite():
		return
	worker_a.begin_physical_approach("plot", first.order_id + ":building", first.order_id, first_origin, first_target)
	worker_b.begin_physical_approach("plot", second.order_id + ":building", second.order_id, second_origin, second_target)
	visuals.plot_presence.states.clear()
	_expect(TimeComponentManager.advance_minutes(1) and worker_a.physical_approach.get("arrived", false),
		"The first worker actually reaches the workshop before completion")
	_expect(not worker_b.physical_approach.get("arrived", false), "The house worker is still approaching")
	first.completes_at = first._latest_time + 1 # Explicit near-completion fixture.
	first.payroll_work_remainder = 0
	var store: Node = WorkStateRuntime.get_node("CitySave")
	store.disk.path = SAVE
	_expect(store.prepare_home_departure(city, HOME_PATH), "The real handoff retains the worksite runtime")
	_expect(get_tree().change_scene_to_file(HOME_PATH) == OK, "Enter the actual home scene")
	for frame: int in range(8):
		await get_tree().process_frame
	_expect(store.parked_worksite == runtime and runtime.can_simulate_plot_travel(), "The initial parked geometry is ready")
	var revision: int = runtime.worksite_navigation.revision
	_expect(TimeComponentManager.advance_minutes(1) and first.phase == "built", "The workshop completes while at home")
	_expect(runtime.can_simulate_plot_travel() and runtime.worksite_navigation.revision > revision,
		"The retained collision geometry is refreshed in the same transition")
	var after_completion: Vector2 = worker_b.physical_approach.position
	if kind == "pending":
		# Deliberately exhaust this fixture frame to save an unfinished search.
		visuals.plot_presence.route_budget_frame = Engine.get_process_frames()
		visuals.plot_presence.route_budget_usec = 0
		visuals.plot_presence.route_budget_operations = 0
		var before_wait: int = second._remaining_work_units()
		_expect(TimeComponentManager.advance_minutes(30), "Thirty budget-limited minutes advance")
		var route_state: Dictionary = visuals.plot_presence.states.get(B_ID, {})
		_expect(route_state.get("status") == "pending" and not worker_b.physical_approach.arrived
			and worker_b.physical_approach.position == after_completion and second._remaining_work_units() == before_wait,
			"Budget exhaustion keeps the worker still and grants no work throughout the skipped interval")
		print("PARKED_PENDING_BUDGET_WAIT minutes=30 position=", after_completion, " remaining=", before_wait)
	else:
		for minute: int in range(8):
			await get_tree().process_frame
			_expect(TimeComponentManager.advance_minutes(1), "The worker travels after the collider changes")
			if worker_b.physical_approach.position != after_completion:
				break
		_expect(worker_b.physical_approach.position != after_completion and not worker_b.physical_approach.arrived,
			"The checkpoint is taken during genuine physical travel")
	var position: Vector2 = worker_b.physical_approach.position
	var remaining: int = second._remaining_work_units()
	_expect(store.save_checkpoint(), "The pending or travelling home checkpoint is accepted: " + store.last_error)
	if failures > 0:
		return
	var evidence := {"kind": kind, "clock": _now(), "x": position.x, "y": position.y, "remaining": remaining}
	var file := FileAccess.open(EVIDENCE, FileAccess.WRITE)
	_expect(file != null, "The isolated evidence file opens")
	if file != null:
		file.store_string(JSON.stringify(evidence))
		file.close()
	print("PARKED_SAVE kind=", kind, " clock=", _now(), " position=", position, " remaining=", remaining)

func _read(kind: String) -> void:
	_expect(FileAccess.file_exists(SAVE) and FileAccess.file_exists(EVIDENCE), "The preceding isolated checkpoint exists")
	if failures > 0:
		return
	var evidence: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE))
	_expect(evidence is Dictionary and evidence.get("kind") == kind, "The checkpoint matches the requested fixture")
	if not evidence is Dictionary:
		return
	var original: PackedByteArray = FileAccess.get_file_as_bytes(SAVE)
	TimeComponentManager.set_process(false)
	get_tree().current_scene = null
	var menu: Node = MENU.instantiate()
	menu.checkpoint_file.path = SAVE
	menu.session_started.connect(func(_continued: bool): launched = true)
	get_tree().root.add_child(menu)
	menu.continue_button.pressed.emit()
	var store: Node = null
	for frame: int in range(1200):
		await get_tree().process_frame
		store = WorkStateRuntime.get_node_or_null("CitySave")
		if launched and is_instance_valid(store) and is_instance_valid(get_tree().current_scene) and get_tree().current_scene.scene_file_path == HOME_PATH and store.status == "Loaded":
			break
	_expect(launched and is_instance_valid(store) and is_instance_valid(get_tree().current_scene) and get_tree().current_scene.scene_file_path == HOME_PATH
		and store.status == "Loaded", "Actual Continue restores the player to the home scene")
	if failures > 0:
		return
	TimeComponentManager.set_process(false)
	var runtime: Node = store.parked_worksite
	var visuals: Node = runtime.get_node("WorkerVisuals") if is_instance_valid(runtime) else null
	if visuals != null:
		visuals.set_process(false)
	var worker: WorkerData = WorkerDatabase.get_worker_data(B_ID)
	var state: Node = _worker_state(HOUSE_ORDER)
	_expect(is_instance_valid(runtime) and visuals != null and worker != null and state != null,
		"Continue restores the retained runtime, the same worker and house work")
	if failures > 0:
		return
	var saved_position := Vector2(float(evidence.x), float(evidence.y))
	_expect(_now() == int(evidence.clock) and FileAccess.get_file_as_bytes(SAVE) == original,
		"Continue neither advances the clock nor rewrites checkpoint bytes")
	_expect(worker.physical_approach.position.distance_to(saved_position) < 0.01
		and not worker.physical_approach.arrived and state._remaining_work_units() == int(evidence.remaining),
		"Continue preserves the exact pending/travelling position and unfinished work")
	_expect(runtime.can_simulate_plot_travel(), "The restored home runtime has current retained collision")
	var remaining: int = state._remaining_work_units()
	for minute: int in range(150):
		await get_tree().process_frame
		var before: Vector2 = worker.physical_approach.position
		var old_route: Dictionary = visuals.plot_presence.states.get(B_ID, {}).duplicate(true)
		_expect(TimeComponentManager.advance_minutes(1), "The restored worker advances a minute")
		var after: Vector2 = worker.physical_approach.position
		var new_route: Dictionary = visuals.plot_presence.states.get(B_ID, {})
		_expect(_walked_segments_clear(runtime.worksite_navigation, before, after, old_route, new_route),
			"The reconstructed route obeys retained collision and walking speed")
		if worker.physical_approach.arrived:
			break
	_expect(worker.physical_approach.arrived and state._remaining_work_units() == remaining,
		"After Continue the worker really arrives before any work is credited")
	_expect(TimeComponentManager.advance_minutes(1) and state._remaining_work_units() == remaining - 1,
		"One paid shift minute is credited only after restored arrival")
	print("PARKED_CONTINUE kind=", kind, " clock=", _now(), " saved_position=", saved_position,
		" current_position=", worker.physical_approach.position, " remaining=", state._remaining_work_units())
	var parked_geometry: Array[PackedVector2Array] = runtime.worksite_navigation.polygons.duplicate()
	var before_return: int = state._remaining_work_units()
	var clock_before_return: int = _now()
	var home: Node = get_tree().current_scene
	home.get_node("YSortWorld/ExitDoor")._on_body_entered(home.get_node("YSortWorld/Player"))
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if is_instance_valid(get_tree().current_scene) and get_tree().current_scene.scene_file_path == CITY_PATH and not SceneTransition.is_transitioning:
			break
	_expect(is_instance_valid(get_tree().current_scene) and get_tree().current_scene.scene_file_path == CITY_PATH
		and not SceneTransition.is_transitioning, "The real exit returns to the city")
	if failures > 0:
		return
	for frame: int in range(8):
		await get_tree().process_frame
	var city: Node = get_tree().current_scene
	var returned_runtime: Node = city.get_node("YSortWorld/WorkerRuntime")
	var returned_worker: WorkerData = WorkerDatabase.get_worker_data(B_ID)
	var returned_state: Node = city.get_node("YSortWorld/CitizenHousePlot").construction
	_expect(not is_instance_valid(store.parked_worksite) and returned_runtime.can_simulate_plot_travel(),
		"The city adopts the parked runtime state and has refreshed geometry")
	_expect(_same_polygons(parked_geometry, returned_runtime.worksite_navigation.polygons),
		"The returned city's actual colliders exactly match the updated parked snapshot")
	_expect(_now() == clock_before_return and returned_worker != null and returned_worker.physical_approach.arrived
		and returned_state._remaining_work_units() == before_return,
		"Returning to the city neither invents time nor changes the worker's progress")
	_expect(city.get_node("YSortWorld/WorkshopPlot2").construction.phase == "built",
		"The workshop completed at home remains built after the city returns")
	print("PARKED_RETURN kind=", kind, " clock=", _now(), " remaining=", returned_state._remaining_work_units())

func _same_polygons(a: Array[PackedVector2Array], b: Array[PackedVector2Array]) -> bool:
	var remaining: Array[PackedVector2Array] = b.duplicate()
	for polygon: PackedVector2Array in a:
		var index: int = remaining.find(polygon)
		if index < 0:
			return false
		remaining.remove_at(index)
	return remaining.is_empty()

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
	return distance <= 24.001

func _finish() -> void:
	print("ParkedNavigationContinueTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
