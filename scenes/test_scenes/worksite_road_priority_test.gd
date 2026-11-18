extends SceneTree

## Real authored map, disposable profile, and no mutations to the player's save.
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var user_path: String = ProjectSettings.globalize_path("user://").replace("\\", "/")
	var qa_root: String = OS.get_environment("TIP_ISOLATED_DATA_ROOT").replace("\\", "/").trim_suffix("/")
	if qa_root.is_empty() or not qa_root.is_absolute_path() or not user_path.begins_with(qa_root + "/"):
		_check(false, "Road QA requires an isolated profile.")
		quit(1)
		return
	var city: Node2D = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	root.add_child(city)
	for frame: int in range(8):
		await physics_frame
	var work = city.get_node("YSortWorld/WorkerRuntime")
	var nav = work.worksite_navigation
	var reed_nav = work.site_navigation(&"ReedSite")
	var router = work.road_router
	_check(router.road_cells.size() > 0, "The authored brown road must be detected.")
	_check(reed_nav != nav and not nav.is_clear(Vector2(220, -168.5)) and reed_nav.is_clear(Vector2(220, -168.5)), "Pond exception must remain Reed-only.")
	var origin := Vector2(170, -145)
	var elapsed_max := 0
	for site_id: StringName in [&"WoodSitePoplar35", &"ClaySiteA", &"ReedSite"]:
		var destination: Vector2 = work.site_slot_destination(site_id, 0)
		var started: int = Time.get_ticks_msec()
		var path: PackedVector2Array = work.site_approach_route(origin, destination, site_id)
		elapsed_max = maxi(elapsed_max, Time.get_ticks_msec() - started)
		_check(path.size() >= 3 and path[0].distance_to(origin) < 0.1 and path[-1].distance_to(destination) < 0.1, str(site_id) + ": complete route")
		if path.size() < 3:
			continue
		var entry := Vector2i(roundi(path[1].x / router.STEP), roundi(path[1].y / router.STEP))
		_check(router.road_cells.has(entry) and path[1].distance_to(Vector2(entry * router.STEP)) < 0.01, str(site_id) + ": first waypoint is on the authored road")
		var site_nav = work.site_navigation(site_id)
		var last_road: Vector2 = path[1]
		for index: int in range(2, path.size() - 1):
			var cell := Vector2i(roundi(path[index].x / router.STEP), roundi(path[index].y / router.STEP))
			if not router.cell_ids.has(cell) or path[index].distance_to(Vector2(cell * router.STEP)) >= 0.01:
				break
			last_road = path[index]
		if site_id in [&"ClaySiteA", &"ReedSite"] and router.cell_ids.has(entry):
			var chosen_distance: float = last_road.distance_squared_to(destination)
			for cell: Vector2i in router.cell_ids:
				var road_point := Vector2(cell * router.STEP)
				if router.components[router.cell_ids[cell]] == router.components[router.cell_ids[entry]] and road_point.distance_squared_to(destination) + 0.01 < chosen_distance:
					_check(not site_nav.segment_clear(road_point, destination), str(site_id) + ": a nearer road exit has a clear final leg")
		for index: int in range(1, path.size()):
			_check(site_nav.segment_clear(path[index - 1], path[index]), str(site_id) + ": segment crosses a collision")
	print("ROAD_PRIORITY_SAMPLE_MAX_MS=", elapsed_max)
	# The optimized line check must agree with the authoritative collision check,
	# including a separate Reed geometry snapshot and boundary edges.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1172026
	for site_nav in [nav, reed_nav]:
		var bounds: Array[Rect2] = []
		for polygon: PackedVector2Array in site_nav.polygons:
			var box := Rect2(polygon[0], Vector2.ZERO)
			for point: Vector2 in polygon:
				box = box.expand(point)
			bounds.append(box.grow(site_nav.CLEARANCE + 0.001))
		for index: int in range(100):
			var from := Vector2(rng.randf_range(24, 360), rng.randf_range(-232, -24))
			var to := Vector2(rng.randf_range(24, 360), rng.randf_range(-232, -24))
			_check(router._segment_clear_fast(from, to, site_nav, bounds) == site_nav.segment_clear(from, to), "Road collision acceleration disagrees with navigation.")
	# A new obstacle must invalidate the graph and never be crossed.
	var clay_target: Vector2 = work.site_slot_destination(&"ClaySiteA", 0)
	var control: PackedVector2Array = work.site_approach_route(origin, clay_target, &"ClaySiteA")
	if control.size() > 8:
		var obstacle_center: Vector2 = control[control.size() / 2]
		var original: Array[PackedVector2Array] = nav.polygons.duplicate()
		var obstructed: Array[PackedVector2Array] = original.duplicate()
		obstructed.append(PackedVector2Array([obstacle_center + Vector2(-3, -3), obstacle_center + Vector2(3, -3), obstacle_center + Vector2(3, 3), obstacle_center + Vector2(-3, 3)]))
		nav.replace_polygons(obstructed)
		var rerouted: PackedVector2Array = work.site_approach_route(origin, clay_target, &"ClaySiteA")
		_check(not rerouted.is_empty() and router.graph_revision == nav.revision, "Obstacle change must rebuild the road graph and retain a valid route.")
		for index: int in range(1, rerouted.size()):
			_check(nav.segment_clear(rerouted[index - 1], rerouted[index]), "Rerouted path crosses a newly added obstacle.")
		nav.replace_polygons(original)
	else:
		_check(false, "Road control route is too short for the obstacle test.")
	var plain = load("res://scenes/content_scene/worksites/worksite_road_router.gd").new()
	var target := Vector2(180, -145)
	var fallback: PackedVector2Array = plain.route(origin, target, nav, nav)
	_check(not fallback.is_empty() and fallback[-1].distance_to(target) < 0.1, "A scene without road data must keep normal navigation.")
	var outside: PackedVector2Array = work.site_approach_route(origin, Vector2(-10000, -10000), &"ClaySiteA")
	_check(outside.is_empty(), "An unreachable target must not produce a route.")
	print("WORKSITE_ROAD_PRIORITY_TEST ", "PASS" if failures == 0 else "FAIL", " failures=", failures, " user=", user_path)
	quit(0 if failures == 0 else 1)
