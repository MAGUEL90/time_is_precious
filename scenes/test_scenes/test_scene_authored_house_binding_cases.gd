extends Node

const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const BINDING_SCRIPT: Script = preload("res://scenes/map_authoring/house_site_binding.gd")

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
	var case_ready: bool = await _run_binding_case("empty", 0)
	if not case_ready:
		_finish()
		return
	case_ready = await _run_binding_case("full", 9)
	if not case_ready:
		_finish()
		return
	case_ready = await _run_binding_case("partial", 3)
	if not case_ready:
		_finish()
		return
	_finish()


func _finish() -> void:
	print("AuthoredHouseBindingCasesTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)


func _run_binding_case(case_name: String, authored_cell_count: int) -> bool:
	var city: Node = CONTENT.instantiate()
	city.get_node("ReviewHouseBinding").free()
	var house := city.get_node("YSortWorld/CitizenHousePlot") as Node2D
	house.set("plot_id", "house_binding_case_" + case_name)
	add_child(city)
	await get_tree().process_frame
	var authored: Node = city.get_node("AuthoredMap")
	var layer := authored.get_node("Ground/Setelah Cleaning") as TileMapLayer
	var marker := authored.get_node("YSortWorld/ToBeClean1") as Node2D
	var cells := _cells_around_marker(layer, marker.global_position)
	var base_layer := authored.get_node("Ground/Base") as TileMapLayer
	var center_tile: Array = _first_tile(base_layer)
	if (center_tile.size() != 3 or int(center_tile[0]) < 0
			or base_layer.tile_set != layer.tile_set):
		_expect(false, "Ground/Base provides a valid tile in the same TileSet for the footprint fixture.")
		city.queue_free()
		await get_tree().process_frame
		return false
	for cell: Vector2i in cells:
		layer.erase_cell(cell)
	for index: int in range(authored_cell_count):
		var cell: Vector2i = cells[index]
		layer.set_cell(cell, int(center_tile[0]), Vector2i(center_tile[1]), int(center_tile[2]))
	var before_binding: Dictionary = _snapshot_cells(layer, cells)
	var state: Node = house.get("construction")
	state.set("phase", "uncleared" if authored_cell_count != 3 else "empty")
	state.emit_signal("changed")
	await get_tree().process_frame

	var binding := Node.new()
	binding.set_script(BINDING_SCRIPT)
	binding.set("footprint_path", NodePath("../AuthoredMap/Ground/Setelah Cleaning"))
	binding.set("marker_path", NodePath("../AuthoredMap/YSortWorld/ToBeClean1"))
	binding.set("house_path", NodePath("../YSortWorld/CitizenHousePlot"))
	city.add_child(binding)
	await get_tree().process_frame
	var expected_bound: bool = authored_cell_count == 0 or authored_cell_count == 9
	_expect(bool(binding.get("_bound")) == expected_bound,
		"Binding accepts an empty or complete footprint and rejects a partial one: " + case_name)
	_expect(house.global_position == marker.global_position,
		"The house remains aligned with its authored marker: " + case_name)
	if expected_bound:
		_expect(not house.get_node("ToBeClean").visible,
			"A successful binding uses the authored rubble marker: " + case_name)
		_expect(not house.get_node("SiteHouse").visible,
			"SiteHouse stays hidden before cleaning is complete: " + case_name)
	else:
		_expect(marker.visible and house.get_node("SiteHouse").visible,
			"A partial footprint is rejected without changing map or house presentation.")
	_expect(_snapshot_cells(layer, cells) == before_binding,
		"Binding preserves the authored cell values during its initial phase: " + case_name)

	if expected_bound:
		state.set("phase", "empty")
		state.emit_signal("changed")
		await get_tree().process_frame
		_expect(not marker.visible and house.get_node("SiteHouse").visible == (authored_cell_count == 0),
			"An empty phase hides the rubble marker and selects the correct site view: " + case_name)
		if authored_cell_count == 9:
			state.set("phase", "built")
			state.emit_signal("changed")
			await get_tree().process_frame
			for cell: Vector2i in cells:
				_expect(layer.get_cell_source_id(cell) == -1,
					"A built house clears its complete authored footprint.")
		state.set("phase", "empty")
		state.emit_signal("changed")
		await get_tree().process_frame
		city.remove_child(binding)
		await get_tree().process_frame
		_expect(not bool(binding.get("_bound")), "Removing the binding disconnects and restores its state: " + case_name)
		_expect(marker.visible and house.get_node("SiteHouse").visible,
			"Removing the binding restores the authored marker and local house view: " + case_name)
		_expect(_snapshot_cells(layer, cells) == before_binding,
			"Removing the binding restores the exact original authored cells: " + case_name)
		city.add_child(binding)
		await get_tree().process_frame
		await get_tree().process_frame
		_expect(bool(binding.get("_bound")), "The same binding reattaches successfully without another _ready call: " + case_name)
		_expect(not marker.visible and house.get_node("SiteHouse").visible == (authored_cell_count == 0),
			"Rebinding reapplies the current empty-phase presentation: " + case_name)
		city.remove_child(binding)
		await get_tree().process_frame
	binding.free()
	city.queue_free()
	await get_tree().process_frame
	return true


func _cells_around_marker(layer: TileMapLayer, marker_position: Vector2) -> Array[Vector2i]:
	var center: Vector2i = layer.local_to_map(layer.to_local(marker_position))
	var cells: Array[Vector2i] = []
	for y: int in range(center.y - 1, center.y + 2):
		for x: int in range(center.x - 1, center.x + 2):
			cells.append(Vector2i(x, y))
	return cells


func _first_tile(layer: TileMapLayer) -> Array:
	var used_cells: Array[Vector2i] = layer.get_used_cells()
	if used_cells.is_empty():
		return []
	var cell: Vector2i = used_cells[0]
	return [layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)]


func _snapshot_cells(layer: TileMapLayer, cells: Array[Vector2i]) -> Dictionary:
	var result := {}
	for cell: Vector2i in cells:
		result[cell] = [layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)]
	return result
