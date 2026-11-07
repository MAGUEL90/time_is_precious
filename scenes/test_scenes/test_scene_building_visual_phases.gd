extends Node

## Presentation-only fixture. Real work, rewards and save/Continue are covered
## by the existing construction, house and production integration tests.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const HOUSE_SITE_PATH: String = "res://assets/objects/buildings/house_construction_site.png"
const HOUSE_FINAL_PATH: String = "res://assets/objects/buildings/house_level_0.png"
const CLAY_FINAL_PATH: String = "res://assets/objects/buildings/clay_workshop_0.png"
const HOUSE_SITE_HASH: String = "6cf4a1fb554663faf8d3018907fb99f37a28dc4c7cbdf08db40fd08f2cfc925b"
const HOUSE_FINAL_HASH: String = "296a012f5ae691b96ce82c880adae4515446834375fae077fa19c9e4ae916a31"
const CLAY_FINAL_HASH: String = "a5e0871383698d9efd7e0d4aa451ca3584c38a1a79a6146e169aeec8a114c6b1"
const OPEN_PLOT_PATH: String = "res://assets/ui/building/plot_level_0.png"
const OPEN_BOARD_PATH: String = "res://assets/objects/object_board_0.png"
const BUILT_BOARD_PATH: String = "res://assets/objects/object_board_1.png"
const SEGMENTS: Array[String] = ["Plot", "LeftWall", "LeftWallTop", "RightWall", "RightWallTop", "Table", "TableLegs"]
const PHASES: Array[String] = ["uncleared", "clearing", "empty", "building", "built"]

var failures: int = 0
var content: Node2D
var house: Node2D
var keeper: Node2D
var secondary: Node2D
var player: Player
var capture_dir: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	TimeComponentManager.environment.color = Color.WHITE
	capture_dir = OS.get_environment("TIP_PLOT_CAPTURE_DIR")
	content = CONTENT.instantiate()
	add_child(content)
	for _frame: int in range(4):
		await get_tree().process_frame
	house = content.get_node_or_null("YSortWorld/CitizenHousePlot") as Node2D
	keeper = content.get_node_or_null("YSortWorld/WorkshopPlot") as Node2D
	secondary = content.get_node_or_null("YSortWorld/WorkshopPlot2") as Node2D
	player = content.get_node_or_null("YSortWorld/Player") as Player
	_expect(house != null and keeper != null and secondary != null and player != null,
		"The real map provides its house, both workshops and player.")
	if house == null or keeper == null or secondary == null or player == null:
		_finish()
		return
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	content.get_node("TimeDebugOverlay").set_process(false)
	_expect(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 400
		and int(ProjectSettings.get_setting("display/window/size/viewport_height")) == 225
		and str(ProjectSettings.get_setting("display/window/stretch/scale_mode")) == "integer",
		"The real map retains its 400x225 integer-scaled pixel presentation.")

	var house_site: Sprite2D = house.get_node("SiteHouse") as Sprite2D
	var house_final: Sprite2D = house.get_node("FinishedHouse") as Sprite2D
	var keeper_group: Node2D = keeper.get_node("FinishedBuilding") as Node2D
	var keeper_final: Sprite2D = keeper_group.get_node("Base") as Sprite2D
	var secondary_group: Node2D = secondary.get_node("FinishedClayWorkshop") as Node2D
	var secondary_final: Sprite2D = secondary_group.get_node("Sprite2D") as Sprite2D
	_assert_art(house_site, HOUSE_SITE_PATH, Vector2i(64, 64), HOUSE_SITE_HASH)
	_assert_art(house_final, HOUSE_FINAL_PATH, Vector2i(48, 64), HOUSE_FINAL_HASH)
	_assert_art(keeper_final, CLAY_FINAL_PATH, Vector2i(48, 64), CLAY_FINAL_HASH)
	_assert_art(secondary_final, CLAY_FINAL_PATH, Vector2i(48, 64), CLAY_FINAL_HASH)
	_expect(house_site.position == Vector2(0, -4) and house_site.scale == Vector2.ONE
		and house_final.position == Vector2(0, -8) and house_final.scale == Vector2.ONE,
		"The old site and new house remain native-sized with their specified ground anchors.")
	_expect(keeper_group.position == Vector2(11, 24) and keeper_final.position == Vector2(0, -32)
		and keeper_group.scale == Vector2.ONE and keeper_final.scale == Vector2.ONE,
		"The keeper workshop keeps its original native-sized ground anchor.")
	_expect(secondary_group.position == Vector2(0, 24) and secondary_final.position == Vector2(0, -32)
		and secondary_group.scale == Vector2.ONE and secondary_final.scale == Vector2.ONE,
		"The second workshop's native-sized artwork uses its authored ground anchor.")

	var entries: Dictionary = {}
	var static_counts: Dictionary = {}
	for plot: Node2D in [house, keeper, secondary]:
		entries[plot] = plot.get_worker_entry_position()
		static_counts[plot] = _count_static_bodies(plot)
		_expect(plot.construction.worker_entry_position == entries[plot], "The saved worker entrance is bound to its authored position.")
	var body: CollisionShape2D = house.get_node("HouseBody/CollisionShape2D") as CollisionShape2D
	var body_transform: Transform2D = body.transform
	var body_shape: Shape2D = body.shape
	var keeper_footprints: Array = keeper.get_built_footprints().duplicate(true)
	var generic_segments: Dictionary = _snapshot_segments(secondary)
	var keeper_segments: Dictionary = _snapshot_segments(keeper)
	var board: Sprite2D = secondary.get_node("Board") as Sprite2D
	var board_transform: Transform2D = board.transform
	var preview: Node2D = secondary.get_node("TableResources") as Node2D
	var preview_transforms: Array[Transform2D] = []
	for child: Node2D in preview.get_children():
		preview_transforms.append(child.transform)
	var shelter_before: int = CityStockManager.shelter_capacity
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var workshop_items_before: Dictionary = WorkShopStorage.items.duplicate(true)
	var order_count_before: int = WorkManager.active_orders.size()

	for phase: String in PHASES:
		for plot: Node2D in [house, keeper, secondary]:
			plot.construction.phase = phase
			plot.construction.changed.emit()
		await _settle()
		_assert_house_phase(phase, body, body_transform, body_shape)
		_assert_workshop_phase(keeper, phase, keeper_segments, true)
		_assert_workshop_phase(secondary, phase, generic_segments, false)
		_expect(board.visible and board.transform == board_transform
			and board.texture.resource_path == (BUILT_BOARD_PATH if phase == "built" else OPEN_BOARD_PATH),
			"The second workshop preserves its board placement and phase-specific texture in " + phase)
		_expect(preview.visible == (phase == "built") and preview.get_child_count() == preview_transforms.size(),
			"The second workshop's existing material previews appear only when complete in " + phase)
		for index: int in range(preview_transforms.size()):
			_expect((preview.get_child(index) as Node2D).transform == preview_transforms[index],
				"Material preview transforms remain unchanged in " + phase)
		for plot: Node2D in [house, keeper, secondary]:
			_expect(plot.get_worker_entry_position() == entries[plot]
				and plot.construction.worker_entry_position == entries[plot],
				"The authored and saved worker entry remains unchanged in " + phase)
		_expect(keeper.get_built_footprints() == keeper_footprints,
			"The keeper's collision footprint remains unchanged in " + phase)
		_expect(CityStockManager.shelter_capacity == shelter_before and Inventory.items == inventory_before
			and WorkShopStorage.items == workshop_items_before and WorkManager.active_orders.size() == order_count_before,
			"Presentation refresh in %s creates no shelter, payment or production." % phase)
		await _capture_phase(house, "house-" + phase)
		await _capture_phase(keeper, "keeper-" + phase)
		await _capture_phase(secondary, "secondary-" + phase)

	for plot: Node2D in [house, keeper, secondary]:
		for _repeat: int in range(3):
			plot.construction.changed.emit()
	await _settle()
	for plot: Node2D in [keeper, secondary]:
		_assert_one_backend(plot, "Repeated built signals")
	_expect(not house.has_node("BuiltWorkshop") and CityStockManager.shelter_capacity == shelter_before,
		"Repeated built signals do not create a house backend or grant shelter.")

	# Restore unfinished presentation as Continue does, then return to complete.
	for plot: Node2D in [house, keeper, secondary]:
		plot.construction.phase = "empty"
		plot.construction.changed.emit()
	await _settle()
	for plot: Node2D in [keeper, secondary]:
		_expect(not plot.has_node("BuiltWorkshop") and plot.interaction_area.monitoring
			and _count_static_bodies(plot) == static_counts[plot],
			"Unfinished restoration removes the old backend and restores its interaction and collision.")
	_expect(house.interaction_area.monitoring and body.disabled,
		"Unfinished house restoration re-enables interaction and removes its finished collider.")
	_assert_house_phase("empty", body, body_transform, body_shape)
	_assert_workshop_phase(keeper, "empty", keeper_segments, true)
	_assert_workshop_phase(secondary, "empty", generic_segments, false)
	for plot: Node2D in [house, keeper, secondary]:
		await _assert_unfinished_player_access(plot)
		plot.construction.phase = "built"
		plot.construction.changed.emit()
	await _settle()
	for plot: Node2D in [keeper, secondary]:
		_assert_one_backend(plot, "Restored built phase")
	_expect(CityStockManager.shelter_capacity == shelter_before, "Built restoration does not grant shelter again.")

	# Rebuild before the old backend's queued deletion completes. This exercises
	# the deferred recreation path instead of allowing a duplicate or missing view.
	for plot: Node2D in [keeper, secondary]:
		plot.construction.phase = "empty"
		plot.construction.changed.emit()
		plot.construction.phase = "built"
		plot.construction.changed.emit()
	await _settle(8)
	for plot: Node2D in [keeper, secondary]:
		_assert_one_backend(plot, "Immediate unfinished/built restoration")
	_expect(CityStockManager.shelter_capacity == shelter_before and Inventory.items == inventory_before
		and WorkShopStorage.items == workshop_items_before and WorkManager.active_orders.size() == order_count_before,
		"Repeated restoration never changes shelter, material or production owners.")
	content.queue_free()
	await get_tree().process_frame
	_finish()


func _snapshot_segments(plot: Node2D) -> Dictionary:
	var result: Dictionary = {}
	for path: String in SEGMENTS:
		var sprite: Sprite2D = plot.get_node(path) as Sprite2D
		result[path] = {"transform": sprite.transform, "offset": sprite.offset,
			"region_enabled": sprite.region_enabled, "region_rect": sprite.region_rect}
	return result


func _assert_house_phase(phase: String, body: CollisionShape2D, body_transform: Transform2D, body_shape: Shape2D) -> void:
	_expect(house.get_node("ToBeClean").visible == (phase in ["uncleared", "clearing"])
		and house.get_node("SiteHouse").visible == (phase in ["empty", "building"])
		and house.get_node("FinishedHouse").visible == (phase == "built"),
		"House rubble, old site and uploaded final art match phase " + phase)
	_expect(not house.get_node("FinishedClayWorkshop").visible and not house.has_node("BuiltWorkshop"),
		"The inherited workshop artwork/backend never appears in the house.")
	_expect(body.transform == body_transform and body.shape == body_shape and body.disabled == (phase != "built"),
		"The house collider shape and anchor are preserved in " + phase)


func _assert_workshop_phase(plot: Node2D, phase: String, segments: Dictionary, main: bool) -> void:
	var built: bool = phase == "built"
	_expect(plot.get_node("ToBeClean").visible == (phase in ["uncleared", "clearing"]),
		"Workshop rubble visibility matches phase " + phase)
	for path: String in SEGMENTS:
		var sprite: Sprite2D = plot.get_node(path) as Sprite2D
		var old: Dictionary = segments[path]
		_expect(sprite.visible == (not built) and sprite.transform == old.transform and sprite.offset == old.offset
			and sprite.region_enabled == old.region_enabled and sprite.region_rect == old.region_rect,
			"Workshop %s geometry and visibility match phase %s." % [path, phase])
		if not built:
			_expect(sprite.texture != null and sprite.texture.resource_path == OPEN_PLOT_PATH,
				"Unfinished workshop %s retains the original art." % path)
	if main:
		_expect(plot.get_node("FinishedBuilding").visible == built and not plot.get_node("FinishedClayWorkshop").visible,
			"Keeper workshop displays exactly its own finished artwork only in the built phase.")
		_expect(not plot.get_node("Board").visible and not plot.get_node("TableResources").visible,
			"The keeper variant retains its existing board and preview visibility.")
	else:
		_expect(plot.get_node("FinishedClayWorkshop").visible == built,
			"The second workshop displays new artwork only in the built phase.")
	_expect(plot.interaction_area.monitoring == (not built),
		"Workshop plot interaction is available only before completion.")
	if built:
		_assert_one_backend(plot, "Built workshop")
	else:
		_expect(not plot.has_node("BuiltWorkshop"), "Unfinished workshop has no built production backend.")


func _assert_one_backend(plot: Node2D, context: String) -> void:
	var count: int = 0
	for child: Node in plot.get_children():
		if child.name == &"BuiltWorkshop" and not child.is_queued_for_deletion():
			count += 1
			var backend: WorkShop = child as WorkShop
			_expect(backend != null and backend.get_job_data("mudbrick_make") != null,
				context + " preserves the original mudbrick production backend.")
	_expect(count == 1, context + " has exactly one live production backend.")


func _count_static_bodies(node: Node) -> int:
	var count: int = 1 if node is StaticBody2D else 0
	for child: Node in node.get_children():
		count += _count_static_bodies(child)
	return count


func _assert_unfinished_player_access(plot: Node2D) -> void:
	player.global_position = plot.interaction_area.global_position + Vector2(0, 4)
	await _settle()
	_expect(plot.has_player_access() and player.current_interactable == plot,
		"The restored unfinished plot remains physically selectable by the player.")


func _assert_art(sprite: Sprite2D, path: String, dimensions: Vector2i, source_hash: String) -> void:
	_expect(FileAccess.get_sha256(path) == source_hash, "The original PNG bytes are preserved: " + path)
	_expect(sprite != null and sprite.texture != null and sprite.texture.resource_path == path
		and sprite.texture.get_size() == Vector2(dimensions), "The expected native-sized texture is loaded: " + path)
	if sprite == null or sprite.texture == null:
		return
	var imported: Image = sprite.texture.get_image()
	var source := Image.new()
	var loaded: Error = source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	_expect(imported != null and loaded == OK, "Imported and supplied pixels are readable: " + path)
	if imported == null or loaded != OK or imported.get_size() != dimensions:
		return
	if imported.is_compressed():
		imported.decompress()
	imported.convert(Image.FORMAT_RGBA8)
	source.convert(Image.FORMAT_RGBA8)
	var mismatches: int = 0
	for y: int in range(dimensions.y):
		for x: int in range(dimensions.x):
			var expected: Color = source.get_pixel(x, y)
			var actual: Color = imported.get_pixel(x, y)
			if actual.a != expected.a or (expected.a > 0.0 and actual != expected):
				mismatches += 1
	_expect(mismatches == 0, "Every visible pixel and alpha value matches the original PNG: " + path)


func _settle(frames: int = 4) -> void:
	for _index: int in range(frames):
		await get_tree().physics_frame
		await get_tree().process_frame


func _capture_phase(plot: Node2D, label: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	player.global_position = plot.global_position + Vector2(0, 54)
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.force_update_scroll()
	await _settle(2)
	await RenderingServer.frame_post_draw
	var picture: Image = get_viewport().get_texture().get_image()
	_expect(picture != null and picture.get_size() == Vector2i(400, 225)
		and picture.save_png(capture_dir.path_join("building-" + label + ".png")) == OK,
		"The current map phase renders at native pixel size: " + label)


func _finish() -> void:
	get_tree().paused = false
	print("BuildingVisualPhasesTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
