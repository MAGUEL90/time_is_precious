extends Node

## Isolated city fixture. Use a disposable XDG_DATA_HOME for every run.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const DUST: Script = preload("res://scenes/worker_visual/clay_work_dust.gd")
const WORKER_ID: String = "world_life_animation_fixture"
var failures: int = 0
var city: Node2D
var visuals: Node2D
var runtime: Node
var worker: WorkerData
var actor: Node2D
var camera: Camera2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var data_root: String = OS.get_environment("XDG_DATA_HOME")
	_check(data_root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(data_root.simplify_path().trim_suffix("/") + "/"), "Use a disposable XDG_DATA_HOME.")
	if failures > 0:
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 20
	TimeComponentManager.current_hour = 11
	TimeComponentManager.current_minute = 0
	city = CITY.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	runtime = city.get_node("YSortWorld/WorkerRuntime")
	visuals = runtime.get_node("WorkerVisuals")
	visuals.set_process(false)
	if DisplayServer.get_name() != "headless":
		get_window().content_scale_size = Vector2i(400, 225)
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().size = Vector2i(1200, 675)
		camera = Camera2D.new()
		city.add_child(camera)
		camera.make_current()
	await get_tree().physics_frame
	await get_tree().process_frame
	await _test_palms()
	await _test_work_dust()
	if failures == 0:
		print("WorldLifeAnimationTest PASSED")
	else:
		print("WorldLifeAnimationTest FAILED: %d" % failures)
	get_tree().paused = false
	SceneTransition.is_transitioning = false
	TimeComponentManager.is_paused = false
	get_tree().quit(0 if failures == 0 else 1)

func _test_palms() -> void:
	var palm: Sprite2D = city.get_node("YSortWorld/DatePalmTree")
	var sway: Node = palm.get_node_or_null("PalmSway")
	_check(sway != null and palm.material is ShaderMaterial, "The real city palm has its visual sway.")
	if sway == null:
		return
	var state: Node = palm.state
	var source_position: Vector2 = palm.global_position
	var available: Array = state.available.duplicate()
	var pickup_positions: Array[Vector2] = []
	for pickup: Node2D in palm._pickups.values():
		pickup_positions.append(pickup.global_position)
	sway.set_process(false)
	var offsets: Dictionary = {}
	for _step: int in range(60):
		sway._process(0.1)
		offsets[sway.last_offset] = true
	_check(offsets.size() >= 3, "Palm canopy moves through multiple whole-pixel positions.")
	_check(palm.global_position == source_position and state.available == available, "Sway does not alter the source or its availability.")
	var index: int = 0
	for pickup: Node2D in palm._pickups.values():
		_check(pickup.global_position == pickup_positions[index], "Sway leaves each pickup at its original world position.")
		index += 1
	var frozen: float = sway.elapsed
	TimeComponentManager.is_paused = true
	sway._process(1.0)
	_check(sway.elapsed == frozen, "Palm freezes when game time is paused.")
	TimeComponentManager.is_paused = false
	SceneTransition.is_transitioning = true
	sway._process(1.0)
	_check(sway.elapsed == frozen, "Palm freezes during a scene transition.")
	SceneTransition.is_transitioning = false
	sway.set_process(true)
	get_tree().paused = true
	await get_tree().create_timer(0.2).timeout
	_check(sway.elapsed == frozen, "Palm freezes while the scene tree is paused.")
	get_tree().paused = false
	var copy: Sprite2D = palm.duplicate(Node.DUPLICATE_SCRIPTS)
	copy.name = "AnimationTestPalmCopy"
	palm.get_parent().add_child(copy)
	await get_tree().process_frame
	_check(copy.get_node_or_null("PalmSway") != null and copy.material != palm.material, "Duplicated palms use independent sway materials.")
	var sway_count: int = 0
	for child: Node in copy.get_children():
		if child.name == "PalmSway":
			sway_count += 1
	_check(sway_count == 1 and copy.tree_id != palm.tree_id and copy.state != state, "A copied palm has one animation and its own pickup identity.")
	copy.queue_free()
	await get_tree().process_frame
	_check(palm.material == sway.sway_material and palm.state == state, "Removing a copy preserves the original palm.")
	await _capture_frames("palm", palm.global_position + Vector2(32, 10), 50)

func _dust_count() -> int:
	var count: int = 0
	for child: Node in actor.get_children():
		if child.get_script() == DUST and not child.is_queued_for_deletion():
			count += 1
	return count

func _dust() -> Node:
	for child: Node in actor.get_children():
		if child.get_script() == DUST and not child.is_queued_for_deletion():
			return child
	return null

func _assign_and_arrive(site_id: StringName) -> bool:
	var assigned: bool = runtime.daily.toggle(site_id, WORKER_ID) and runtime.daily.start(site_id, func(_quantity: int) -> bool: return true)
	_check(assigned, "Native assignment starts for " + str(site_id))
	if not assigned:
		return false
	for _frame: int in range(4000):
		if worker.physical_approach.get("arrived", false):
			break
		visuals._process(0.05)
	_check(worker.physical_approach.get("arrived", false), "Worker physically arrives at " + str(site_id))
	TimeComponentManager.advance_minutes(1)
	visuals._process(0.05)
	return worker.physical_approach.get("arrived", false)

func _test_work_dust() -> void:
	runtime.daily.tool_requirement = Callable()
	worker = WorkerData.new()
	worker.worker_id = WORKER_ID
	worker.display_name = "Animation fixture"
	worker.payroll_start_day = 20
	worker.payroll_paid_from_day = 20
	worker.payroll_paid_until_day = 23
	worker.payroll_last_attempt_day = 20
	worker.payroll_period_rate = 1
	worker.payroll_contract_days = 3
	worker.payroll_paid_start_minute = 20 * 1440 + 660
	WorkerDatabase.workers_by_id[WORKER_ID] = worker
	if not _assign_and_arrive(&"ClaySiteA"):
		return
	actor = visuals.actors[WORKER_ID]
	var initial_stock: int = runtime.daily.sites[&"ClaySiteA"].stock
	var initial_units: int = int(runtime.daily.jobs[&"ClaySiteA"].units)
	var initial_inventory: Dictionary = Inventory.items.duplicate(true)
	visuals.work_cycles.erase(WORKER_ID)
	visuals._process(0.05)
	_check(visuals.work_cycles[WORKER_ID].phase == 0 and _dust_count() == 0, "Arrival idle has no work dust.")
	for _step: int in range(60):
		if _dust_count() > 0:
			break
		visuals._process(0.1)
	_check(_dust_count() == 1 and visuals.work_cycles[WORKER_ID].phase == 1, "The first clay work stroke emits one bounded puff.")
	for _step: int in range(3):
		visuals._process(0.1)
	_check(_dust_count() == 1, "Repeated updates in the same stroke do not duplicate the puff.")
	_check(runtime.daily.sites[&"ClaySiteA"].stock == initial_stock and int(runtime.daily.jobs[&"ClaySiteA"].units) == initial_units and Inventory.items == initial_inventory, "The animation does not change stock, output, or inventory.")
	var puff: Node = _dust()
	if puff != null:
		var before: float = puff.elapsed
		var cycle_before: float = visuals.work_cycles[WORKER_ID].elapsed
		TimeComponentManager.is_paused = true
		visuals._process(1.0)
		await get_tree().create_timer(0.2).timeout
		_check(puff.elapsed == before and visuals.work_cycles[WORKER_ID].elapsed == cycle_before and _dust_count() == 1, "Clay dust and work visuals freeze with game time.")
		TimeComponentManager.is_paused = false
		SceneTransition.is_transitioning = true
		visuals._process(1.0)
		await get_tree().create_timer(0.2).timeout
		_check(puff.elapsed == before and visuals.work_cycles[WORKER_ID].elapsed == cycle_before and _dust_count() == 1, "Clay dust and work visuals freeze during a scene transition.")
		SceneTransition.is_transitioning = false
		get_tree().paused = true
		await get_tree().create_timer(0.2).timeout
		_check(puff.elapsed == before, "Clay dust freezes when the tree pauses.")
		get_tree().paused = false
	# Capture the native clay assignment while it is still active.
	visuals.work_cycles.erase(WORKER_ID)
	visuals.set_process(true)
	await _capture_frames("clay", actor.global_position, 85)
	visuals.set_process(false)
	_check(runtime.daily.withdraw(&"ClaySiteA", WORKER_ID), "The native clay assignment can stop.")
	visuals._process(0.1)
	await get_tree().create_timer(0.8).timeout
	_check(_dust_count() == 0, "The last puff clears after work stops.")
	for _step: int in range(20):
		visuals._process(0.1)
	_check(_dust_count() == 0, "Idle or roaming does not emit work dust.")
	# Exercise the same visual phase with the water site's real session data;
	# this does not create a second long-distance navigation journey.
	visuals.work_cycles[WORKER_ID] = {"phase": 1, "elapsed": 0.0, "direction": "right", "dust_emitted": false,
		"origin": actor.global_position, "target": actor.global_position, "idle": 1.0}
	actor.show()
	visuals._update_work_cycle(&"WaterSite", WORKER_ID, actor, actor.global_position, "right", 1.1)
	_check(_dust_count() == 0, "The water work pose does not produce clay dust.")
	visuals.work_cycles.erase(WORKER_ID)
	visuals._play(actor, "idle", "right")

func _capture_frames(name: String, center: Vector2, count: int) -> void:
	var directory: String = OS.get_environment("TIP_ANIMATION_CAPTURE_DIR")
	if directory.is_empty() or camera == null:
		return
	DirAccess.make_dir_recursive_absolute(directory.path_join(name))
	camera.global_position = center
	camera.zoom = Vector2(2, 2)
	camera.reset_smoothing()
	camera.force_update_scroll()
	for index: int in range(count):
		await get_tree().create_timer(0.1).timeout
		await RenderingServer.frame_post_draw
		var frame: Image = get_viewport().get_texture().get_image()
		_check(frame.save_png(directory.path_join(name).path_join("%04d.png" % index)) == OK, "Save animation frame.")
