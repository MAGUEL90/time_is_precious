extends SceneTree
var checks: int = 0
var failures: int = 0
func _initialize(): run.call_deferred()
func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok
func run():
	var qa: String = OS.get_environment("TIP_ISOLATED_DATA_ROOT").replace("\\", "/")
	var user: String = ProjectSettings.globalize_path("user://").replace("\\", "/")
	if not check(not qa.is_empty() and user.begins_with(qa + "/"), "QA isolation"):
		quit(1); return
	print("QA_USER_DIR=", user)
	var mode: String = OS.get_cmdline_user_args()[0]
	var city = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	var source = city.get_node("AuthoredMap/YSortWorld/ClaySite")
	if mode == "moved":
		source.get_node("ClayControls/WorkPoint1").position += Vector2(8, 0)
		source.get_node("ClayControls/WorkPoint2").position += Vector2(8, 0)
	if mode == "collision":
		# Cover the authored first work point in this fixture, even after editor changes.
		var old_point: Vector2 = source.get_node("ClayControls/WorkPoint1").position
		source.get_node("ClayControls/Collision/CollisionPolygon2D").polygon = PackedVector2Array([old_point + Vector2(-6, -6), old_point + Vector2(6, -6), old_point + Vector2(6, 6), old_point + Vector2(-6, 6)])
	if mode == "edited":
		source.get_node("ClayControls/WorkPoint1").position += Vector2(0, 6)
		source.get_node("ClayControls/WorkPoint2").position += Vector2(0, 6)
		source.get_node("ClayControls/Collision/CollisionPolygon2D").position += Vector2(2, -2)
	root.add_child(city); current_scene = city
	root.get_node("TimeComponentManager").set_process(false)
	for i in range(30): await physics_frame
	var works = city.get_node("YSortWorld/WorkerRuntime")
	var visuals = works.get_node("WorkerVisuals")
	visuals.set_process(false)
	var store = root.get_node("WorkStateRuntime/CitySave")
	var codec = load("res://scenes/new_scenes/save_game/city_save_values.gd").new()
	if mode in ["new", "moved", "collision"]:
		for phase in (["working"] if mode == "collision" else ["travelling", "working"]):
			store.disk.path = "user://clay_controls/old_" + phase + ".json"
			var bytes: String = FileAccess.get_file_as_string(store.disk.path)
			var before: Dictionary = store.snapshot.capture(city)
			var loaded: bool = store.load_checkpoint()
			if mode == "new":
				check(loaded, "Old default-layout save accepted: " + store.last_error)
				var old = codec.decode(JSON.parse_string(bytes).state)
				var fresh = codec.decode(store.snapshot.capture(city).state)
				for field in ["workers", "citizens", "worksites"]:
					check(codec.encode(old[field]) == codec.encode(fresh[field]), "Old data preserved: " + field)
			else:
				check(not loaded, "Incompatible old save rejected")
				check("authored" in store.last_error, "Clear rejection reason: " + store.last_error)
				check(store.snapshot.capture(city) == before, "Rejected load leaves live state intact")
				check(not store.save_checkpoint(), "Cannot overwrite rejected save")
			check(FileAccess.get_file_as_string(store.disk.path) == bytes, "Old file untouched")
	else:
		if mode == "edited":
			var preview = source.preview_geometry()
			for i in range(2):check(preview.slots[i].is_equal_approx(works.site_slot_destination(&"ClaySiteA", i)), "Edited marker read exactly")
			var shape = works.get_node("WorksiteMarkers/ClaySiteA/ResourceBase/CollisionPolygon2D")
			for i in range(4):check(preview.collision[i].is_equal_approx(shape.to_global(shape.polygon[i])), "Edited collision read exactly")
		var citizen = root.get_node("CitizenManager").get_citizen("initial_workshop_laborer")
		citizen.satisfaction = 0.99
		root.get_node("Inventory").add_item("shekel", 9)
		var worker = root.get_node("WorkerDatabase").hire_applicant(citizen.citizen_id, 1, 9)
		if not check(worker != null, "Paid QA hire"): quit(1); return
		var marker = works.get_node("WorksiteMarkers/ClaySiteA")
		check(works.daily.toggle(&"ClaySiteA", worker.worker_id) and works.daily.start(&"ClaySiteA", works._drop_daily_output.bind(marker)), "Clay assignment starts")
		visuals._process(0.05)
		check(not worker.physical_approach.arrived, "Travelling state")
		store.disk.path = "user://clay_controls/" + ("old" if mode == "baseline" else "edited") + "_travelling.json"
		check(store.save_checkpoint(), "Travel save: " + store.last_error)
		check(store.load_checkpoint(), "Travel load: " + store.last_error)
		worker = root.get_node("WorkerDatabase").get_worker_data(citizen.citizen_id)
		for i in range(1200):
			await process_frame
			visuals._process(0.05)
			if worker.physical_approach.arrived: break
		check(worker.physical_approach.arrived, "Worker reaches Clay without teleport")
		store.disk.path = "user://clay_controls/" + ("old" if mode == "baseline" else "edited") + "_working.json"
		check(store.save_checkpoint() and store.load_checkpoint(), "Working roundtrip: " + store.last_error)
		root.get_node("TimeComponentManager").advance_minutes(30)
		visuals._process(0.05)
		check(int(works.daily.jobs[&"ClaySiteA"].stats[citizen.citizen_id].output) > 0, "Clay production")
	print("CLAY_CONTROLS mode=", mode, " checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
