extends Node

const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const NAV = preload("res://scenes/content_scene/worksites/worksite_navigation.gd")
@export var mode: String = "actual"
@export var manual_kind: String = "workshop"
@export var expect_repaired: bool = false
@export var stop_kind: String = ""
@export var cross_shift: bool = false
@export var sealed: bool = false
var stop_applied: bool = false
var start_hunger: float
var start_fatigue: float
class PendingRouteSearch:
	extends "res://scenes/content_scene/worksites/worksite_route_search.gd"
	var pending_steps: int = 0
	func _init(navigation: RefCounted, origin: Vector2, target: Vector2, delay_steps: int = 0) -> void:
		super(navigation, origin, target)
		pending_steps = delay_steps
	func step(max_operations: int, deadline_usec: int) -> int:
		if pending_steps > 0:
			pending_steps -= 1
			return 0
		return super.step(max_operations, deadline_usec)

class FixtureNavigation:
	extends "res://scenes/content_scene/worksites/worksite_navigation.gd"
	var fixture: Node
	var pending_steps: int = 0
	func configure(_map: Node) -> void:
		super.configure(fixture)
	func begin_bounded_route(from: Vector2, to: Vector2) -> RefCounted:
		return PendingRouteSearch.new(self, from, to, pending_steps)
var failures: int = 0
var content: Node
var player: Player
var visuals: Node
var runtime: Node
var manual_plot: Node
var other_plot: Node
var worker: WorkerData
var start: int
var count: int = 0
var first_frame: int = -1
var last_frame: int = -1
var first_arrival: int = -1
var nav: RefCounted
var geometry: Node2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
func _process(_delta: float) -> void:
	if stop_applied or stop_kind.is_empty() or not is_instance_valid(manual_plot) or not is_instance_valid(visuals):
		return
	if not manual_plot._manual_clearing or not TimeComponentManager.is_staged_advance_active():
		return
	if not visuals.plot_presence.states.has(worker.worker_id) or visuals.plot_presence.states[worker.worker_id].get("status", "") != "pending":
		return
	stop_applied = true
	if stop_kind == "close_pending":
		manual_plot.close_menu()
	elif stop_kind == "critical_pending":
		player.fatigue = player.fatigue_critical_threshold
	elif stop_kind == "repeat_pending":
		manual_plot.menu.build_button.pressed.emit()

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _observe(_minute: int) -> void:
	count += 1
	if first_frame < 0:
		first_frame = Engine.get_process_frames()
	last_frame = Engine.get_process_frames()
	if worker.physical_approach.arrived and first_arrival < 0:
		first_arrival = _now()
func _box(pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	geometry.add_child(body)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = pos
	body.add_child(shape)
func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	TimeComponentManager.emit_time_signal()
	content = CONTENT.instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	for frame: int in range(4):
		await get_tree().process_frame
	player = content.get_node("YSortWorld/Player")
	runtime = content.get_node("YSortWorld/WorkerRuntime")
	visuals = runtime.get_node("WorkerVisuals")
	visuals.set_process(false)
	manual_plot = content.get_node("YSortWorld/WorkshopPlot" if manual_kind == "workshop" else "YSortWorld/CitizenHousePlot")
	other_plot = content.get_node("YSortWorld/CitizenHousePlot" if manual_kind == "workshop" else "YSortWorld/WorkshopPlot")
	player.hunger = 0.1
	player.fatigue = 0.1
	player.debug_disable_player_needs = false
	player.debug_disable_fatigue = false
	var citizen := CitizenData.new()
	citizen.citizen_id = "manual_routes_builder"
	citizen.display_name = "Nabu"
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	citizen.satisfaction = 0.95
	citizen.visual_profile = VisualProfile.new()
	CitizenManager.add_citizen(citizen)
	Inventory.add_item("shekel", 100)
	_expect(CitizenManager.register_applicant(citizen.citizen_id, WorkerData.Profession.LABORER), "Fixture can apply")
	worker = WorkerDatabase.hire_applicant(citizen.citizen_id, 1, 9)
	_expect(worker != null, "Fixture has a real paid contract")
	if worker == null:
		_finish()
		return
	TimeComponentManager.current_day = 1
	TimeComponentManager.current_hour = 14 if cross_shift else 7
	TimeComponentManager.current_minute = 55 if cross_shift else 0
	TimeComponentManager.emit_time_signal()
	var state: Node = other_plot.construction
	state.phase = "empty"
	state.changed.emit()
	Inventory.add_bulk_item(state.get_requirements())
	_expect(bool(state.start_build([worker.worker_id] as Array[String]).success), "Worker is assigned to the separate plot")
	if manual_kind == "house":
		manual_plot.construction.phase = "empty"
		manual_plot.construction.changed.emit()
		Inventory.add_bulk_item(manual_plot.construction.get_requirements())
	player.global_position = manual_plot.get_node("InteractableComponent").global_position + Vector2(0, 12 if manual_kind == "workshop" else 4)
	for frame: int in range(6):
		await get_tree().physics_frame
	_expect(manual_plot.has_player_access(), "The real manual plot is physically accessible")
	if not manual_plot.has_player_access():
		_finish()
		return
	if mode == "actual":
		manual_plot.on_player_interact(player)
		if is_instance_valid(manual_plot.get("keeper_dialogue")):
			manual_plot.keeper_dialogue.continued.emit()
		_expect(is_instance_valid(manual_plot.menu), "The actual manual-work menu opens")
		if not is_instance_valid(manual_plot.menu):
			_finish()
			return
	geometry = Node2D.new()
	add_child(geometry)
	var target: Vector2 = state.worker_entry_position
	var origin: Vector2 = target + Vector2(-96, 0)
	# Reachable detour plus harmless distant shapes exercise the real bounded
	# planner over multiple frame budgets, without changing the authored map.
	_box(target + Vector2(-48, 0), Vector2(8, 96))
	for index: int in range(1 if sealed else 100):
		_box(target + Vector2(300 + index * 12, 300), Vector2(4, 4))
	if sealed:
		_box(target + Vector2(-12, 0), Vector2(4, 24))
		_box(target + Vector2(12, 0), Vector2(4, 24))
		_box(target + Vector2(0, -12), Vector2(24, 4))
		_box(target + Vector2(0, 12), Vector2(24, 4))
	var fixture_navigation: FixtureNavigation = FixtureNavigation.new()
	fixture_navigation.fixture = geometry
	fixture_navigation.pending_steps = 12 if stop_kind == "close_pending" else 0
	fixture_navigation.configure(geometry)
	nav = fixture_navigation
	runtime.worksite_navigation = nav
	_expect(nav.is_clear(origin) and nav.is_clear(target), "Both route endpoints are physically clear")
	worker.begin_physical_approach("plot", state.order_id + ":building", state.order_id, origin, target)
	visuals.plot_presence.states.clear()
	start = _now()
	var work_before: int = state._remaining_work_units()
	var hunger_before: float = player.hunger
	var fatigue_before: float = player.fatigue
	start_hunger = hunger_before
	start_fatigue = fatigue_before
	TimeComponentManager.minute_changed.connect(_observe)
	if mode == "actual":
		manual_plot.menu.player_button.button_pressed = true
		_expect(not manual_plot.menu.build_button.disabled, "The actual Start button is enabled")
		manual_plot.menu.build_button.pressed.emit()
		var deadline: int = Time.get_ticks_msec() + 30000
		while (is_instance_valid(manual_plot.menu) or manual_plot._manual_clearing or TimeComponentManager.is_dispatching_time()) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		_expect(not is_instance_valid(manual_plot.menu) and not manual_plot._manual_clearing and not manual_plot.construction.is_player_work_active() and not TimeComponentManager.is_dispatching_time() and not TimeComponentManager.is_staged_advance_active(), "Manual action releases menu, work state and clock flags before the test finishes")
	elif mode == "normal":
		for minute: int in range(180):
			await get_tree().process_frame
			TimeComponentManager._process(TimeComponentManager.seconds_per_minute)
			visuals._process(TimeComponentManager.seconds_per_minute)
	elif mode == "staged":
		var result: Dictionary = await TimeComponentManager.advance_minutes_staged(180, self)
		_expect(result.completed, "Reference staged time completes")
	var earned: int = work_before - state._remaining_work_units()
	var elapsed: int = _now() - start
	if stop_kind not in ["close_pending", "critical_pending"]:
		_expect(elapsed == 180 and count == 180, "Exactly 180 minutes pass once")
	else:
		_expect(stop_applied and elapsed == 0 and count == 0 and earned == 0, "Stopping during pending planning commits no time or work")
	if stop_kind == "close_pending":
		_expect(stop_applied, "The close action was applied while the route planner was pending")
	if expect_repaired and stop_kind not in ["close_pending", "critical_pending"] and not cross_shift and not sealed:
		_expect(earned == 173 and first_arrival == start + 7, "The real manual action matches staged reference: seven travel minutes, 173 earned minutes")
	if stop_kind == "repeat_pending":
		_expect(stop_applied, "Repeated Start was attempted while planning was pending")
	if sealed:
		_expect(earned == 0 and not worker.physical_approach.arrived, "A sealed target never grants arrival or work")
	if expect_repaired and cross_shift:
		_expect(earned == 0, "A seven-minute route beginning at 14:55 cannot earn work after the 15:00 shift end")
	_expect(is_equal_approx(player.hunger, hunger_before + elapsed * player.hunger_increase_per_min), "Hunger is charged once")
	if stop_kind != "critical_pending":
		_expect(is_equal_approx(player.fatigue, fatigue_before + elapsed * player.fatigue_increase_per_min), "Fatigue is charged once")
	_expect(not get_tree().paused and player.can_move, "Controls and the modal pause are released")
	print("MANUAL_ROUTE_RESULT ", JSON.stringify({"mode":mode,"kind":manual_kind,"elapsed":_now()-start,"earned_work":earned,"arrived":worker.physical_approach.arrived,"arrival_after_minutes":first_arrival-start if first_arrival>=0 else -1,"dispatch_frame_span":last_frame-first_frame,"route_status":visuals.plot_presence.states.get(worker.worker_id,{}).get("status", "missing"),"stop_applied":stop_applied,"needs_active":not player.debug_disable_player_needs,"checks":failures}))
	_finish()
func _finish() -> void:
	print("ManualWorkRouteProbe: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
