extends Node

## Reproducible visual comparison. Uses an isolated process and never writes to
## the authored map or changes the scene's permanent contents.
const MAP: PackedScene = preload("res://scenes/map_authoring/new_map_authoring.tscn")
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var directory: String = OS.get_environment("TIP_MAP_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Set TIP_MAP_CAPTURE_DIR and run with a graphics display.")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	get_window().content_scale_size = Vector2i(400, 225)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().size = Vector2i(1200, 675)
	TimeComponentManager.set_process(false)
	var map: Node2D = MAP.instantiate()
	get_tree().root.add_child(map)
	get_tree().current_scene = map
	var camera := Camera2D.new()
	map.add_child(camera)
	camera.position = Vector2(0, -145)
	camera.zoom = Vector2(0.8, 0.8)
	camera.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join("authored-only.png"))
	get_tree().current_scene = null
	map.free()
	var city: Node2D = CITY.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	for path: String in ["TopHUD", "BottomHUD", "TimeDebugOverlay"]:
		var node: Node = city.get_node_or_null(path)
		if node is CanvasItem or node is CanvasLayer:
			node.hide()
	camera = Camera2D.new()
	city.add_child(camera)
	camera.position = Vector2(0, -145)
	camera.zoom = Vector2(0.8, 0.8)
	camera.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join("city-with-gameplay.png"))
	# This third frame is a diagnostic only; no gameplay object is removed from
	# the saved scene. The real runtime picture above remains the authoritative one.
	for path: String in ["YSortWorld/WallStone", "YSortWorld/WallManagementSpot", "YSortWorld/WorkshopPlot", "YSortWorld/WorkshopPlot2", "YSortWorld/CitizenHousePlot", "YSortWorld/HomeDoor", "YSortWorld/WorkerRuntime/WorksiteMarkers", "YSortWorld/WorkerRuntime/WorkerVisuals", "YSortWorld/WorkerRuntime/CityStorageArea", "YSortWorld/WorkerRuntime/CityStorageAnnex", "YSortWorld/InitialWorksites", "YSortWorld/TravelingMerchant", "YSortWorld/Player", "YSortWorld/DatePalmTree", "YSortWorld/DatePalmTree2", "YSortWorld/DatePalmTree3", "YSortWorld/DatePalmTree4", "YSortWorld/DatePalmTree5", "YSortWorld/DatePalmTree6"]:
		var node: Node = city.get_node_or_null(path)
		if node is CanvasItem:
			node.hide()
	for pickup: Node in get_tree().get_nodes_in_group("date_palm_pickups"):
		if city.is_ancestor_of(pickup) and pickup is CanvasItem:
			pickup.hide()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join("city-gameplay-hidden.png"))
	print("AuthoredMapComparison: PASS; images in ", directory)
	get_tree().quit(0)
