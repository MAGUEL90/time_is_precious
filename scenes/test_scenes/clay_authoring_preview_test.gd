extends SceneTree
var failures: int = 0
var checks: int = 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var qa: String = OS.get_environment("TIP_ISOLATED_DATA_ROOT").replace("\\", "/")
	var user: String = ProjectSettings.globalize_path("user://").replace("\\", "/")
	if qa.is_empty() or not user.begins_with(qa + "/"):
		quit(1)
		return
	print("QA_USER_DIR=", user)
	var city = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	# Shift only the isolated in-memory fixture, before binding at scene load.
	if "--shift" in OS.get_cmdline_user_args():
		city.get_node("AuthoredMap/YSortWorld/ClaySite").position += Vector2(13, -9)
		city.get_node("AuthoredMap/YSortWorld/ClaySite2").position += Vector2(21, 5)
	root.add_child(city)
	current_scene = city
	root.get_node("TimeComponentManager").set_process(false)
	for i in range(30): await physics_frame
	var works = city.get_node("YSortWorld/WorkerRuntime")
	for pair in [["ClaySite", "ClaySiteA"], ["ClaySite2", "ClaySiteB"]]:
		var source = city.get_node("AuthoredMap/YSortWorld/" + pair[0])
		var geometry: Dictionary = source.preview_geometry()
		check(not geometry.is_empty(), "Preview exists " + pair[0])
		if geometry.is_empty(): continue
		var collision = works.get_node("WorksiteMarkers/" + pair[1] + "/ResourceBase/CollisionPolygon2D")
		for i in range(4):
			check(geometry.collision[i].distance_to(collision.to_global(collision.polygon[i])) < 0.001, "Collision matches runtime " + pair[0])
		for i in range(2):
			var target: Vector2 = works.site_slot_destination(pair[1], i)
			check(geometry.slots[i].distance_to(target) < 0.001, "Slot matches runtime " + pair[0])
			print(pair[1], " slot=", i + 1, " preview=", geometry.slots[i], " runtime=", target)
		check(source.get_child_count() == 1 and not source.has_node("ClayEditorGuides") and not source.is_processing(), "No runtime preview nodes/polling")
		var old_position: Vector2 = source.position
		source.position += Vector2(7, -3)
		var moved: Dictionary = source.preview_geometry()
		check(moved.slots[0].is_equal_approx(geometry.slots[0] + Vector2(7, -3)), "Editor move follows immediately")
		source.position = old_position
	print("CLAY_PREVIEW checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
