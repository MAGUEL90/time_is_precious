extends SceneTree
var failures: int = 0
var checks: int = 0
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; push_error(label)
func run():
	var qa: String = OS.get_environment("TIP_ISOLATED_DATA_ROOT").replace("\\", "/")
	if qa.is_empty() or not ProjectSettings.globalize_path("user://").replace("\\", "/").begins_with(qa + "/"): quit(1); return
	var city = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	root.add_child(city);current_scene=city
	root.get_node("TimeComponentManager").set_process(false)
	for i in range(30):await physics_frame
	var works=city.get_node("YSortWorld/WorkerRuntime")
	var source=city.get_node("AuthoredMap/YSortWorld/ClaySite")
	var layout=load("res://scenes/content_scene/worksites/authored_resource_layout.gd")
	var geometry=load("res://scenes/map_authoring/clay_authoring_geometry.gd")
	var shape=source.get_node("ClayControls/Collision/CollisionPolygon2D")
	var polygon:PackedVector2Array=shape.polygon
	var marker=works.get_node("WorksiteMarkers/ClaySiteA")
	var old_position:Vector2=marker.global_position
	var old_geometry:Dictionary=marker.get_meta("authored_clay_geometry").duplicate(true)
	shape.polygon=PackedVector2Array([Vector2.ZERO,Vector2.ONE])
	var result=layout.bind(works,works.authored_resource_paths)
	check(not result.ok and "ClaySiteA" in result.error,"Malformed polygon rejected with ID")
	check(marker.global_position==old_position and marker.get_meta("authored_clay_geometry")==old_geometry,"Invalid binding atomic")
	shape.polygon=polygon
	var point=source.get_node("ClayControls/WorkPoint2")
	point.name="MissingWorkPoint"
	check(not geometry.read(source).ok,"Partial controls rejected")
	point.name="WorkPoint2"
	var body=shape.get_parent()
	body.collision_layer=1
	check(not geometry.read(source).ok,"Duplicate active collision template rejected")
	body.collision_layer=0
	check(geometry.read(source).ok,"Valid controls accepted")
	check(not works.worksite_navigation.is_clear(shape.to_global(Vector2(0,10))),"Navigation blocks authored solid")
	var controls=source.get_node("ClayControls")
	source.remove_child(controls)
	check(geometry.read(source).ok and not geometry.read(source).configured,"Absent controls retain automatic fallback")
	source.add_child(controls)
	var center: Vector2 = shape.to_global(Vector2(0, 10))
	check(not works.authored_clay_pose_clear(center, {}), "Active Clay blocks saved pose")
	check(works.authored_clay_pose_clear(center, {"ClaySiteA": {"stock": 0}}), "Depleted Clay does not create phantom save collider")
	print("CLAY_INVALID checks=",checks," failures=",failures)
	quit(1 if failures else 0)
