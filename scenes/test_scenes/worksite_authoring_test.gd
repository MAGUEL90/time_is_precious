extends SceneTree

var layout: Script
const IDS: Array[String] = ["WoodSite", "ClaySiteA", "ReedSite"]
const SHIFT := Vector2(4, 0)
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok

func _run() -> void:
	var user_path: String = ProjectSettings.globalize_path("user://").replace("\\", "/")
	var qa_root: String = OS.get_environment("TIP_ISOLATED_DATA_ROOT").replace("\\", "/").trim_suffix("/")
	if not _check(not qa_root.is_empty() and qa_root.is_absolute_path() and user_path.begins_with(qa_root + "/"), "Refusing non-QA profile"):
		quit(1)
		return
	print("QA_USER_DIR=", user_path)
	layout = load("res://scenes/content_scene/worksites/authored_resource_layout.gd")
	var moved: bool = OS.get_cmdline_user_args().has("--moved")
	var blocked_start: bool = OS.get_cmdline_user_args().has("--blocked")
	if not moved and not blocked_start and FileAccess.file_exists("user://authoring/baseline.json"):
		_check(false, "Writer requires a fresh QA profile")
		quit(1)
		return
	var city = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	var works = city.get_node("YSortWorld/WorkerRuntime")
	# Edit only the unmounted test instance, as an editor position change would.
	# Never edit a .tscn or rebind/move a running worksite.
	if moved:
		for id: String in IDS:
			var source = works.get_node(works.authored_resource_paths[id])
			source.position += SHIFT
		# A fixture-only alternate path proves Reed uses the single binding.
		var reed = works.get_node(works.authored_resource_paths.ReedSite)
		reed.name = "ReedBindingFixture"
		works.authored_resource_paths["ReedSite"] = NodePath("../../AuthoredMap/YSortWorld/ReedBindingFixture")
	if blocked_start:
		works.get_node(works.authored_resource_paths.ClaySiteA).position = Vector2(1000, 1000)
	root.add_child(city)
	current_scene = city
	root.get_node("TimeComponentManager").set_process(false)
	for frame in range(30):
		await physics_frame
	var visuals = works.get_node("WorkerVisuals")
	visuals.set_process(false)
	var store = root.get_node("WorkStateRuntime/CitySave")
	var codec = load("res://scenes/new_scenes/save_game/city_save_values.gd").new()
	_check(works.authored_resource_binding.get("ok", false), "Full binding succeeds")
	if blocked_start:
		_check(works.authoring_slot_issues.any(func(issue: String) -> bool: return "ClaySiteA: work slot 1" in issue), "Startup publishes blocked authoring slot diagnostics")
		_check(works.get_node(works.authored_resource_paths.ClaySiteA).position == Vector2(1000, 1000), "Blocked placement is never auto-moved")
		print("WorksiteAuthoring: blocked_start=true checks=", checks, " failures=", failures)
		quit(0 if failures == 0 else 1)
		return
	_check(works.validate_authoring_slots().is_empty(), "Current automatic work slots are clear: " + str(works.validate_authoring_slots()))
	var positions: Dictionary = {}
	for id: String in IDS:
		positions[id] = works.get_node("WorksiteMarkers/" + id).global_position
	var reed_source = works.get_node(works.authored_resource_paths.ReedSite)
	_check(works.worksite_navigation._reed_marker_position == reed_source.global_position, "Reed navigation resolves the validated binding")
	_check(works.site_navigation(&"ReedSite") != works.worksite_navigation, "Reed retains its pond exception")
	_check(works.site_navigation(&"ClaySiteA") == works.worksite_navigation, "Reed exception does not leak to Clay")
	if moved:
		var baseline: Dictionary = codec.decode(JSON.parse_string(FileAccess.get_file_as_string("user://authoring/baseline.json")))
		for id: String in IDS:
			_check(positions[id].is_equal_approx(baseline[id] + SHIFT), "Scene position alone moves runtime marker: " + id)
		for phase: String in ["travelling", "working"]:
			store.disk.path = "user://authoring/old_%s.json" % phase
			var file_before: String = FileAccess.get_file_as_string(store.disk.path)
			var live_before: Dictionary = store.snapshot.capture(city)
			_check(not store.load_checkpoint(), "Old " + phase + " target is safely rejected")
			_check(store.snapshot.error == "Worker physical approach differs from its authored site.", "Explicit old-target rejection: " + store.snapshot.error)
			_check(FileAccess.get_file_as_string(store.disk.path) == file_before and store.snapshot.capture(city) == live_before, "Rejection preserves file and live state")
			_check(not store.save_checkpoint(), "Incompatible slot cannot be overwritten by saving")
			_check(FileAccess.get_file_as_string(store.disk.path) == file_before, "Rejected save leaves old bytes intact")
	else:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://authoring"))
		FileAccess.open("user://authoring/baseline.json", FileAccess.WRITE).store_string(JSON.stringify(codec.encode(positions)))
	# Independently generated QA state on each layout, never reset the old slot.
	var citizen = root.get_node("CitizenManager").get_citizen("initial_workshop_laborer")
	citizen.satisfaction = 0.99
	citizen.employment_status = citizen.EmploymentStatus.APPLICANT
	root.get_node("Inventory").add_item("shekel", 9)
	var worker = root.get_node("WorkerDatabase").hire_applicant("initial_workshop_laborer", 1, 9)
	if not _check(worker != null, "Paid worker fixture"):
		quit(1)
		return
	works.daily.tool_requirement = Callable()
	var marker = works.get_node("WorksiteMarkers/WoodSite")
	_check(works.daily.toggle(&"WoodSite", worker.worker_id) and works.daily.start(&"WoodSite", works._drop_daily_output.bind(marker)), "Wood assignment starts")
	visuals._process(0.05)
	_check(not worker.physical_approach.arrived, "Travelling checkpoint fixture")
	store.disk.path = "user://authoring/new_layout.json" if moved else "user://authoring/old_travelling.json"
	_check(store.save_checkpoint(), "QA transit save: " + store.last_error)
	var before: Dictionary = codec.decode(store.snapshot.capture(city).state)
	_check(store.load_checkpoint(), "Same-layout transit load: " + store.last_error)
	var after: Dictionary = codec.decode(store.snapshot.capture(city).state)
	for field: String in ["workers", "citizens", "worksites"]:
		_check(codec.encode(before[field]) == codec.encode(after[field]), "Identity, assignment and state conserved: " + field)
	worker = root.get_node("WorkerDatabase").get_worker_data(worker.worker_id)
	for frame in range(700):
		await process_frame
		visuals._process(0.05)
		if worker.physical_approach.arrived:
			break
	_check(worker.physical_approach.arrived, "Worker arrives at scene-derived work point")
	store.disk.path = "user://authoring/new_working.json" if moved else "user://authoring/old_working.json"
	_check(store.save_checkpoint() and store.load_checkpoint(), "Same-layout working roundtrip: " + store.last_error)
	# Negative binding checks are atomic: no partial movement/hiding on failure.
	var binding_before: Dictionary = _binding_state(works)
	var missing: Dictionary = works.authored_resource_paths.duplicate()
	missing.erase("WoodSite")
	var result: Dictionary = layout.bind(works, missing)
	_check(not result.ok and "WoodSite" in result.error and "Missing IDs" in result.error, "Missing binding identifies the ID")
	var stale: Dictionary = works.authored_resource_paths.duplicate()
	stale["WoodSite"] = NodePath("../../AuthoredMap/YSortWorld/AbsentTree")
	result = layout.bind(works, stale)
	_check(not result.ok and "WoodSite" in result.error and "AbsentTree" in result.error, "Stale binding identifies ID and path")
	var duplicate: Dictionary = works.authored_resource_paths.duplicate()
	duplicate["WoodSiteC"] = duplicate.WoodSite
	result = layout.bind(works, duplicate)
	_check(not result.ok and "duplicated" in result.error and "WoodSiteC" in result.error, "Duplicate resource binding rejected")
	_check(_binding_state(works) == binding_before, "Binding failures do not move or hide any object")
	# Simulate blocked geometry without modifying the authored layout.
	var nav = works.worksite_navigation
	var original: Array[PackedVector2Array] = nav.polygons.duplicate()
	var blocked: Array[PackedVector2Array] = original.duplicate()
	var point: Vector2 = works.site_slot_destination(&"ClaySiteA", 0)
	blocked.append(PackedVector2Array([point + Vector2(-8, -8), point + Vector2(8, -8), point + Vector2(8, 8), point + Vector2(-8, 8)]))
	nav.replace_polygons(blocked)
	var state_before: Dictionary = store.snapshot.capture(city)
	var issues: Array[String] = works.validate_authoring_slots()
	_check(issues.any(func(issue: String) -> bool: return "ClaySiteA: work slot 1" in issue), "Blocked point reports ID and slot")
	_check(store.snapshot.capture(city) == state_before and _binding_state(works) == binding_before, "Diagnostics never mutate saved state or scene positions")
	nav.replace_polygons(original)
	_check(works.validate_authoring_slots().is_empty(), "Clear geometry clears diagnostics")
	print("WorksiteAuthoring: moved=", moved, " checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

func _binding_state(works: Node) -> Dictionary:
	var result: Dictionary = {}
	for id: Variant in works.authored_resource_paths:
		var source = works.get_node(works.authored_resource_paths[id])
		var marker = works.get_node("WorksiteMarkers/" + str(id))
		result[str(id)] = [source.global_position, source.visible, marker.global_position, marker.visible]
	return result
