extends "res://scenes/test_scenes/test_scene_city_save_economy.gd"

## Reuse the established paid-worker fixture, without changing its rules.
const LAYOUT = preload("res://scenes/content_scene/worksites/authored_resource_layout.gd")

func _run() -> void:
	if not _isolated_profile_is_safe():
		_expect(false, "Use isolated test XDG directories.")
		get_tree().quit(1)
		return
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://binding_active_save")):
		_expect(false, "Use a fresh profile; never overwrite an existing active-binding checkpoint.")
		get_tree().quit(1)
		return
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_reset_singletons_before_load()
	await load_content()
	runtime = content.get_node("YSortWorld/WorkerRuntime")
	city_storage = WorkStateRuntime.get_node("CityToolStorage")
	wood_storage = runtime.get_node("CityStorageArea/DeliveryPoint")
	store = WorkStateRuntime.get_node("CitySave")
	store.disk.path = "user://binding_active_save/checkpoint.json"
	# Keep this non-shortage control explicit across the updated fixture ancestor.
	_prepare_city_state(RESIDENT_IDS.size())
	if failures > 0 or not _hire_and_assign_team():
		_finish_binding_active()
		return
	_settle_needs()
	var worker: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	_expect(not worker.physical_approach.is_empty(), "The worker owns an active world-space site journey.")
	var document: Dictionary = store.snapshot.capture(content)
	_expect(not document.is_empty() and store.snapshot.prepare(document, content), "The active assignment checkpoint is a valid control: " + store.snapshot.error)
	if failures > 0:
		_finish_binding_active()
		return
	_expect(store.save_checkpoint(), "The active assignment control saves.")
	var original_bytes: String = FileAccess.get_file_as_string(store.disk.path)
	var source: Sprite2D = runtime.get_node(runtime.authored_resource_paths.WoodSite)
	var group := Node2D.new()
	group.name = "ReorganizedArt"
	group.position = Vector2(-51, 92)
	source.get_parent().add_child(group)
	source.reparent(group, true)
	source.name = "TreeWithStableWorksite"
	runtime.authored_resource_paths.WoodSite = runtime.get_path_to(source)
	var bound: Dictionary = LAYOUT.bind(runtime, runtime.authored_resource_paths)
	_expect(bool(bound.get("ok", false)), "Regrouped/renamed active site binds through an updated explicit reference.")
	_expect(store.snapshot.prepare(document, content), "A same-position hierarchy/name edit preserves the active assignment checkpoint: " + store.snapshot.error)
	var marker: Node2D = runtime.get_node("WorksiteMarkers/WoodSite")
	var original_position: Vector2 = source.position
	var original_origin: Vector2 = runtime._site_origins[&"WoodSite"]
	source.position += Vector2(50, 0)
	bound = LAYOUT.bind(runtime, runtime.authored_resource_paths)
	_expect(bool(bound.get("ok", false)), "A translated visual site still binds.")
	# Simulate the new authored origin captured at the next startup, rather than
	# pretending arbitrary live rebinds are a supported gameplay operation.
	runtime._site_origins[&"WoodSite"] = marker.position
	var before_reject: Dictionary = store.snapshot.capture(content)
	_expect(not store.snapshot.prepare(document, content)
		and store.snapshot.error == "Worker physical approach differs from its authored site.",
		"Moving a site with a saved active journey remains rejected at the physical-target guard: " + store.snapshot.error)
	_expect(store.snapshot.capture(content) == before_reject and FileAccess.get_file_as_string(store.disk.path) == original_bytes,
		"A moved-site rejection does not mutate the input checkpoint or any live owner.")
	source.position = original_position
	LAYOUT.bind(runtime, runtime.authored_resource_paths)
	runtime._site_origins[&"WoodSite"] = original_origin
	for iteration: int in range(2):
		_expect(store.load_checkpoint(), "Restoring the authored position makes the exact active checkpoint loadable again: " + store.last_error)
		_expect(FileAccess.get_file_as_string(store.disk.path) == original_bytes, "Repeated active-site loads do not rewrite the checkpoint.")
	_finish_binding_active()

func _finish_binding_active() -> void:
	print("BindingActiveSaveTest: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
