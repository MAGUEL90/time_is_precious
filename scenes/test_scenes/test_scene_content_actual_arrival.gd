extends Node

## Isolated fixture: no checkpoint files, grants are explicit test setup only.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const NAVIGATION = preload("res://scenes/content_scene/worksites/worksite_navigation.gd")
const SNAPSHOT = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const WORKER_ID: String = "arrival_fixture_worker"
var failures: int = 0
var city: Node
var runtime: Node
var visuals: Node
var worker: WorkerData

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	_set_clock(20, 11, 0)
	city = CONTENT.instantiate()
	add_child(city)
	runtime = city.get_node("YSortWorld/WorkerRuntime")
	visuals = runtime.get_node("WorkerVisuals")
	visuals.set_process(false)
	worker = WorkerData.new()
	worker.worker_id = WORKER_ID
	worker.display_name = "Arrival fixture"
	worker.payroll_start_day = 20
	worker.payroll_paid_from_day = 20
	worker.payroll_paid_until_day = 23
	worker.payroll_last_attempt_day = 20
	worker.payroll_period_rate = 1
	worker.payroll_contract_days = 3
	worker.payroll_paid_start_minute = 20 * 1440 + 11 * 60
	WorkerDatabase.workers_by_id[WORKER_ID] = worker
	runtime.daily.tool_requirement = Callable()
	_test_obstacle_route()
	_assign(&"ClaySiteA")
	_check(not worker.physical_approach.is_empty() and not worker.physical_approach.arrived,
		"New assignment synchronously records pending physical arrival")
	var origin: Vector2 = worker.physical_approach.position
	SceneTransition.is_transitioning = true
	visuals._process(0.5)
	_check(worker.physical_approach.position == origin, "Scene fade holds the saved physical pose")
	SceneTransition.is_transitioning = false
	TimeComponentManager.advance_minutes(30)
	_check(worker.physical_approach.position == origin and not worker.physical_approach.arrived,
		"Instant time jump cannot create physical movement or arrival")
	_check(int(runtime.daily.minutes_by_worker.get(WORKER_ID, 0)) == 0,
		"Travel produces no paid production minutes")
	visuals._process(0.1)
	_check(worker.physical_approach.position.distance_to(origin) <= visuals.APPROACH_SPEED * 0.1 + 0.001,
		"First physical frame obeys its movement budget without clock catch-up")
	var actor: Node = visuals.actors[WORKER_ID]
	var frame_samples: Array[Dictionary] = []
	var observe_frame: Callable = func() -> void:
		frame_samples.append({"animation": str(actor.body_sprite.animation), "frame": actor.body_sprite.frame})
	actor.body_sprite.frame_changed.connect(observe_frame)
	observe_frame.call()
	var visible_start: Vector2 = worker.physical_approach.position
	visuals.set_process(true)
	await get_tree().create_timer(0.45).timeout
	visuals.set_process(false)
	actor.body_sprite.frame_changed.disconnect(observe_frame)
	var observed_walk_frames: Dictionary = {}
	for sample: Dictionary in frame_samples:
		if str(sample.animation).contains("_walk_"):
			observed_walk_frames[int(sample.frame)] = true
	_check(str(actor.body_sprite.animation).contains("_walk_") and observed_walk_frames.size() >= 2
		and worker.physical_approach.position.distance_to(visible_start) > 0.0,
		"Actual rendered sprite frames continue WALK during the physical approach")
	print("Arrival WALK frames: ", frame_samples, " feet distance=", worker.physical_approach.position.distance_to(visible_start))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(get_viewport().get_texture().get_image().save_png("user://content_actual_arrival_walk.png") == OK,
			"Save visible native WALK frame in the isolated fixture profile")
	var saved: Dictionary = worker.physical_approach.duplicate(true)
	var saved_pose: Vector2 = saved.position
	visuals.actors[WORKER_ID].free()
	visuals.actors.erase(WORKER_ID)
	visuals.site_paths.clear()
	worker.physical_approach = saved
	visuals._process(0.0)
	_check(visuals.actors[WORKER_ID].global_position + Vector2(0, 16) == saved_pose and not worker.physical_approach.arrived,
		"Recreated actor restores saved pending feet without arrival or teleport")
	_walk_until_arrived()
	_check(worker.physical_approach.arrived, "Real physical route reaches the authored work entry")
	TimeComponentManager.advance_minutes(1)
	_check(int(runtime.daily.minutes_by_worker.get(WORKER_ID, 0)) == 1, "Only post-arrival paid time produces work")
	var paid_pose: Dictionary = worker.physical_approach.duplicate(true)
	_check(WorkerData.physical_approach_valid(paid_pose), "Arrived physical snapshot passes schema type validation")
	var current_pose: Vector2 = visuals.actors[WORKER_ID].global_position + Vector2(0, 16)
	runtime.daily.withdraw(&"ClaySiteA", WORKER_ID)
	_check(worker.physical_approach.is_empty(), "Withdraw removes active approach identity")
	_assign(&"WoodSite")
	_check(worker.physical_approach.position == current_pose and not worker.physical_approach.arrived,
		"Immediate reassignment preserves actual feet and starts a new pending task")
	worker.payroll_paid_until_day = 19
	var blocked_pose: Vector2 = worker.physical_approach.position
	visuals._process(0.2)
	TimeComponentManager.advance_minutes(5)
	_check(worker.physical_approach.position == blocked_pose and not worker.physical_approach.arrived,
		"Expired contract pauses physical approach and grants no false arrival")
	worker.payroll_paid_until_day = 23
	var host := Node2D.new()
	add_child(host)
	runtime.checkpoint_handoff = true
	runtime.reparent(host, true)
	runtime.process_mode = Node.PROCESS_MODE_DISABLED
	visuals.set_process(true)
	var before_hidden: Vector2 = worker.physical_approach.position
	await get_tree().create_timer(0.15).timeout
	_check(worker.physical_approach.position.distance_to(before_hidden) > 0.0,
		"Retained visual owner physically moves under a disabled parked parent")
	visuals.set_process(false)
	_walk_until_arrived()
	_check(worker.physical_approach.arrived, "Hidden real movement reaches entry after renewal")
	runtime.process_mode = Node.PROCESS_MODE_INHERIT
	runtime.reparent(city.get_node("YSortWorld"), true)
	runtime.checkpoint_handoff = false
	runtime.daily.withdraw(&"WoodSite", WORKER_ID)
	_set_clock(21, 6, 0)
	_reset_ledger()
	_assign(&"ClaySiteA")
	_check(int(runtime.daily.jobs[&"ClaySiteA"].starts[WORKER_ID]) == 21 * 1440 + 420,
		"Before-opening assignment retains the 07:00 start anchor")
	TimeComponentManager.advance_minutes(60)
	_check(int(runtime.daily.minutes_by_worker.get(WORKER_ID, 0)) == 0,
		"Opening/time jump alone cannot produce before actual arrival")
	_walk_until_arrived()
	TimeComponentManager.advance_minutes(1)
	_check(int(runtime.daily.minutes_by_worker.get(WORKER_ID, 0)) == 1,
		"07:00 physical arrival grants only the next paid work minute")
	TimeComponentManager.advance_minutes(8 * 60 - 1)
	var at_close: int = int(runtime.daily.minutes_by_worker.get(WORKER_ID, 0))
	TimeComponentManager.advance_minutes(1)
	_check(int(runtime.daily.minutes_by_worker.get(WORKER_ID, 0)) == at_close,
		"Physical arrival does not permit production after 15:00")
	runtime.daily.withdraw(&"ClaySiteA", WORKER_ID)
	_set_clock(22, 7, 0)
	_reset_ledger()
	_assign(&"WoodSite")
	_check(int(runtime.daily.jobs[&"WoodSite"].starts[WORKER_ID]) == 22 * 1440 + 420 and not worker.physical_approach.arrived,
		"Exact-opening assignment remains pending until its new target is physically reached")
	TimeComponentManager.advance_minutes(1)
	_check(int(runtime.daily.minutes_by_worker.get(WORKER_ID, 0)) == 0,
		"Assigning exactly at opening does not bypass physical travel")
	runtime.daily.withdraw(&"WoodSite", WORKER_ID)
	_set_clock(22, 15, 0)
	_reset_ledger()
	_assign(&"ClaySiteA")
	_check(int(runtime.daily.jobs[&"ClaySiteA"].starts[WORKER_ID]) == 23 * 1440 + 420,
		"15:00 assignment schedules the next opening unchanged")
	var snapshot = SNAPSHOT.new()
	var evening_document: Dictionary = snapshot.capture(city)
	_check(not evening_document.is_empty(), "Capture evening next-day pending assignment: " + snapshot.error)
	_check(snapshot.prepare(evening_document, city), "Validate evening next-day pending assignment: " + snapshot.error)
	city.free()
	WorkerDatabase.workers_by_id.erase(WORKER_ID)
	print("ContentActualArrival: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _assign(site_id: StringName) -> void:
	_check(runtime.daily.toggle(site_id, WORKER_ID), "Fixture worker selected at " + str(site_id))
	_check(runtime.daily.start(site_id, func(_quantity: int) -> bool: return true), "Fixture assignment starts at " + str(site_id))

func _walk_until_arrived() -> void:
	for _frame: int in range(2000):
		if worker.physical_approach.arrived:
			return
		visuals._process(0.05)

func _reset_ledger() -> void:
	runtime.daily.last_tick = runtime.daily.now()
	runtime.daily.last_stock_day = TimeComponentManager.current_day
	runtime.daily.minutes_by_worker.clear()
	runtime.daily.ledger_day = TimeComponentManager.current_day

func _set_clock(day: int, hour: int, minute: int) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute

func _test_obstacle_route() -> void:
	var navigation = NAVIGATION.new()
	var geometry := Node2D.new()
	var body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 24)
	collision.shape = shape
	body.add_child(collision)
	geometry.add_child(body)
	add_child(geometry)
	navigation.configure(geometry)
	var from := Vector2(-40, 0)
	var to := Vector2(40, 0)
	_check(not navigation.segment_clear(from, to), "Authored solid blocks a direct approach")
	var points: PackedVector2Array = navigation.route(from, to)
	_check(points.size() > 2, "Finite native route finds a detour around the solid")
	for index: int in range(1, points.size()):
		_check(navigation.segment_clear(points[index - 1], points[index]), "Every route segment respects the unchanged collider")
	_check(navigation.route(Vector2.ZERO, to).is_empty(), "Blocked spawn is rejected without teleport")
	geometry.free()
