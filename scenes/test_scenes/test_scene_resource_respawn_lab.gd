extends Node

## Isolated, multi-process review of the debug lab. It never opens the real
## player's slot; the sentinel exists only inside the disposable XDG profile.
const LAB: PackedScene = preload("res://scenes/test_scenes/resource_respawn_lab.tscn")
const SENTINEL_PATH: String = "user://city_save/authored_map/checkpoint_v1.json"
const SENTINEL: String = "UNCHANGED PLAYER SAVE FIXTURE"
const EXPECTED_PATH: String = "user://debug_resource_respawn_lab/test_expected.json"
const WORKER_ID: String = "initial_workshop_laborer"
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _frames(count: int = 4) -> void:
	for i: int in range(count):
		await get_tree().process_frame

func _run() -> void:
	var root_path: String = OS.get_environment("XDG_DATA_HOME")
	_check(root_path.is_absolute_path() and ProjectSettings.globalize_path("user://").begins_with(root_path.trim_suffix("/") + "/"), "A disposable XDG_DATA_HOME is required.")
	var phase: String = "write"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--lab-phase="):
			phase = arg.trim_prefix("--lab-phase=")
	if failures > 0:
		_finish(phase)
		return
	if phase == "write":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SENTINEL_PATH).get_base_dir())
		var sentinel_file: FileAccess = FileAccess.open(SENTINEL_PATH, FileAccess.WRITE)
		sentinel_file.store_string(SENTINEL)
		sentinel_file.close()
	var lab: Node = LAB.instantiate()
	add_child(lab)
	for i: int in range(30):
		if lab.ready_for_test:
			break
		await get_tree().process_frame
	_check(lab.ready_for_test, "The isolated debug scene is ready.")
	if not lab.ready_for_test:
		_finish(phase)
		return
	TimeComponentManager.set_process(false)
	await _frames()
	if phase == "write":
		_check(lab._add_test_worker(), "A normally assigned, paid fixture worker can be added.")
		await _frames()
		_check(lab._deplete_selected(), "The selected deposit can be emptied in the lab.")
		var plan = lab.plans.ClaySiteA
		var due: int = plan.get_respawn_due_minute()
		var delay: int = due - plan.get_depleted_at_minute()
		_check(delay >= 2880 and delay <= 4320 and plan.is_respawn_pending(), "The pending timer is randomly chosen in the 2–3 game-day range.")
		_check(lab._save_debug(), "The pending timer and actual city state save to the debug slot.")
		var expected: FileAccess = FileAccess.open(EXPECTED_PATH, FileAccess.WRITE)
		expected.store_string(JSON.stringify({"due": due}))
		expected.close()
	elif phase == "read":
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED_PATH))
		_check(lab._continue_debug(), "A fresh process continues the saved debug timer.")
		await _frames()
		var due: int = int(expected.get("due", -1))
		_check(lab.plans.ClaySiteA.is_respawn_pending() and lab.plans.ClaySiteA.get_respawn_due_minute() == due, "Continue preserves the exact original deadline.")
		_check(lab._continue_debug() and lab.plans.ClaySiteA.get_respawn_due_minute() == due, "Repeated Continue does not reroll the timer.")
		await _frames()
		var worker: WorkerData = WorkerDatabase.get_worker_data(WORKER_ID)
		var old_target: Vector2 = worker.physical_approach.get("target", Vector2.INF) if worker != null else Vector2.INF
		var old_offset: Vector2 = lab.work.resource_site_offset(&"ClaySiteA")
		_check(lab._finish_selected(), "The debug button completes the timer at an explicitly checked test point.")
		var new_offset: Vector2 = lab.work.resource_site_offset(&"ClaySiteA")
		worker = WorkerDatabase.get_worker_data(WORKER_ID)
		_check(new_offset != old_offset and int(lab.work.sites[&"ClaySiteA"].stock) == lab.TEST_CAPACITY, "A fresh fixture deposit appears at the test point.")
		_check(worker != null and not worker.physical_approach.arrived and Vector2(worker.physical_approach.target) != old_target, "The assigned worker must travel to the new point.")
		if worker != null:
			var authored: Node2D = lab.city.get_node("AuthoredMap")
			var route: PackedVector2Array = lab.work.site_approach_route(worker.physical_approach.position, worker.physical_approach.target)
			_check(authored.to_global(Vector2(0, -75)) in route and authored.to_global(Vector2(0, -40)) in route, "The temporary worker route goes through both gate waypoints.")
		await _frames()
		_check(lab._save_debug(), "The moving worker and finished timer save in the debug slot.")
		var next_expected: FileAccess = FileAccess.open(EXPECTED_PATH, FileAccess.WRITE)
		next_expected.store_string(JSON.stringify({"offset_x": new_offset.x, "offset_y": new_offset.y,
			"target_x": worker.physical_approach.target.x, "target_y": worker.physical_approach.target.y}))
		next_expected.close()
	elif phase == "types":
		for site_id: String in ["ClaySiteA", "WoodSite", "ReedSite", "WaterSite"]:
			lab._on_site_selected(site_id)
			var original: Vector2 = lab.work.resource_site_offset(StringName(site_id))
			_check(lab._deplete_selected(), site_id + " can be selected and emptied.")
			await _frames()
			_check(lab._finish_selected(), site_id + " can use a checked temporary test point.")
			await _frames()
			_check(lab.work.resource_site_offset(StringName(site_id)) != original and int(lab.work.sites[StringName(site_id)].stock) == lab.TEST_CAPACITY, site_id + " respawns once with fixture stock.")
	elif phase == "arrive":
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED_PATH))
		_check(lab._continue_debug(), "A fresh process restores the worker en route to the test point.")
		await _frames()
		var worker: WorkerData = WorkerDatabase.get_worker_data(WORKER_ID)
		var target := Vector2(float(expected.get("target_x", INF)), float(expected.get("target_y", INF)))
		var offset := Vector2(float(expected.get("offset_x", INF)), float(expected.get("offset_y", INF)))
		_check(lab.work.resource_site_offset(&"ClaySiteA") == offset and int(lab.work.sites[&"ClaySiteA"].stock) == lab.TEST_CAPACITY, "Continue restores the test location and reserve.")
		_check(worker != null and Vector2(worker.physical_approach.target).is_equal_approx(target), "Continue restores the same worker destination.")
		_check(not lab.plans.ClaySiteA.is_respawn_pending(), "The completed timer remains completed after Continue.")
		if worker != null and not worker.physical_approach.is_empty():
			var visuals: Node = lab.work.get_node("WorkerVisuals")
			visuals.set_process(false)
			var actor: Node2D = visuals.ensure_actor(WORKER_ID, lab.work.worker_spawn(&"ClaySiteA", WORKER_ID))
			for step: int in range(500):
				if worker.physical_approach.get("arrived", false):
					break
				visuals._physical_site_step(&"ClaySiteA", WORKER_ID, actor, 0.15)
			_check(bool(worker.physical_approach.get("arrived", false)), "The real worker physically reaches the new test point.")
	else:
		_check(false, "Unknown lab phase.")
	_check(FileAccess.get_file_as_string(SENTINEL_PATH) == SENTINEL, "The normal player save sentinel remains untouched.")
	_finish(phase)

func _finish(phase: String) -> void:
	print("ResourceRespawnLabTest ", phase, ": ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
