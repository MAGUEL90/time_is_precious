extends Node

## The map stays an authored source; this fixture changes only its instance.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const AUTHORED: PackedScene = preload("res://scenes/map_authoring/new_map_authoring.tscn")
const AUTHOR_PATH: String = "res://scenes/map_authoring/new_map_authoring.tscn"

var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	var original_hash := FileAccess.get_sha256(AUTHOR_PATH)
	var city := CONTENT.instantiate()
	add_child(city)
	await get_tree().process_frame
	var authored := city.get_node("AuthoredMap")
	var layer := authored.get_node("Ground/Setelah Cleaning") as TileMapLayer
	var marker := authored.get_node("YSortWorld/ToBeClean1") as Node2D
	var house := city.get_node("YSortWorld/CitizenHousePlot") as Node2D
	var state: Node = house.get("construction")
	var fresh := AUTHORED.instantiate()
	var original := _snapshot(fresh.get_node("Ground/Setelah Cleaning"))
	var footprint_cells := _cells_around_marker(layer, marker.global_position)
	var original_footprint := _snapshot_cells(layer, footprint_cells)
	var authored_cell_count: int = 0
	for cell: Vector2i in footprint_cells:
		if int(original_footprint[cell][0]) >= 0:
			authored_cell_count += 1
	var has_authored_footprint: bool = authored_cell_count == 9
	var before_shelter := CityStockManager.shelter_capacity
	var before_inventory := Inventory.items.duplicate(true)
	_expect(footprint_cells.size() == 9, "The authored-site test derives all nine cells around the marker.")
	_expect(authored_cell_count == 0 or has_authored_footprint,
		"The real authored site has either no footprint cells or the complete 3x3, never a partial footprint.")
	_expect(house.global_position == marker.global_position, "The review house matches the authored first marker.")
	var binding := city.get_node("ReviewHouseBinding")
	await get_tree().process_frame
	var annex: Node2D = city.get_node("YSortWorld/WorkerRuntime/CityStorageAnnex")
	var annex_label: Label = annex.get_node("AnnexLabel")
	_expect(annex.position == Vector2(-40, 67) and annex_label.text == "ANNEX",
		"The readable Annex label changes no storage endpoint position.")
	for marker_name: String in ["ToBeClean1", "ToBeClean2", "ToBeClean3", "ToBeClean4"]:
		var authored_marker: Sprite2D = authored.get_node("YSortWorld/" + marker_name)
		var marker_bounds: Rect2 = authored_marker.global_transform * authored_marker.get_rect()
		_expect(not annex_label.get_global_rect().intersects(marker_bounds),
			"The Annex label does not cover authored plot " + marker_name)
	for phase: String in ["uncleared", "clearing", "empty", "building", "built", "empty", "uncleared"]:
		state.set("phase", phase)
		state.emit_signal("changed")
		state.emit_signal("changed")
		await get_tree().process_frame
		var showing: bool = phase in ["uncleared", "clearing", "empty", "building"]
		_expect(marker.visible == (phase in ["uncleared", "clearing"]),
			"The authored marker disappears when cleaning completes: " + phase)
		_expect(not house.get_node("ToBeClean").visible,
			"The authored marker replaces duplicate local rubble: " + phase)
		_expect(house.get_node("SiteHouse").visible == (not has_authored_footprint and phase in ["empty", "building"]),
			"The local house site is used only when the map has no complete footprint: " + phase)
		_expect(house.get_node("FinishedHouse").visible == (phase == "built"),
			"Finished house matches phase " + phase)
		for cell: Vector2i in footprint_cells:
			if has_authored_footprint:
				_expect((_cell(layer, cell) == original_footprint[cell]) if showing
					else layer.get_cell_source_id(cell) == -1,
					"The complete authored footprint is shown until the house is built: " + phase)
			else:
				_expect(_cell(layer, cell) == original_footprint[cell],
					"An empty authored footprint remains untouched: " + phase)
		for cell: Vector2i in original:
			if cell not in footprint_cells:
				_expect(_cell(layer, cell) == original[cell], "The separately painted map remains unchanged.")
		for marker_name: String in ["ToBeClean2", "ToBeClean3", "ToBeClean4"]:
			_expect(authored.get_node("YSortWorld/" + marker_name).visible,
				"Other authored markers remain visible.")
		_expect(CityStockManager.shelter_capacity == before_shelter and Inventory.items == before_inventory,
			"Presentation refresh does not grant shelter or consume items.")
	state.set("phase", "empty")
	state.emit_signal("changed")
	binding.queue_free()
	await get_tree().process_frame
	_expect(marker.visible and house.get_node("SiteHouse").visible and _snapshot(layer) == original,
		"Removing the binding restores the marker, local house view, and complete authored tile layer.")
	_expect(_snapshot(fresh.get_node("Ground/Setelah Cleaning")) == original
		and FileAccess.get_sha256(AUTHOR_PATH) == original_hash,
		"The source map remains byte-for-byte unchanged.")
	fresh.free()
	city.queue_free()
	await get_tree().process_frame
	print("AuthoredHouseBindingTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)


func _cells_around_marker(layer: TileMapLayer, marker_position: Vector2) -> Array[Vector2i]:
	var center: Vector2i = layer.local_to_map(layer.to_local(marker_position))
	var cells: Array[Vector2i] = []
	for y: int in range(center.y - 1, center.y + 2):
		for x: int in range(center.x - 1, center.x + 2):
			cells.append(Vector2i(x, y))
	return cells


func _cell(layer: TileMapLayer, cell: Vector2i) -> Array:
	return [layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)]


func _snapshot_cells(layer: TileMapLayer, cells: Array[Vector2i]) -> Dictionary:
	var result := {}
	for cell: Vector2i in cells:
		result[cell] = _cell(layer, cell)
	return result


func _snapshot(layer: TileMapLayer) -> Dictionary:
	var result := {}
	for cell: Vector2i in layer.get_used_cells():
		result[cell] = _cell(layer, cell)
	return result
