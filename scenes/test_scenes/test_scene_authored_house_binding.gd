extends Node

## The map stays an authored source; this fixture changes only its instance.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const AUTHORED: PackedScene = preload("res://scenes/map_authoring/new_map_authoring.tscn")
const BINDING: Script = preload("res://scenes/map_authoring/house_site_binding.gd")
const AUTHOR_PATH: String = "res://scenes/map_authoring/new_map_authoring.tscn"
const PLOT: Array[Vector2i] = [Vector2i(-5, -12), Vector2i(-4, -12), Vector2i(-3, -12),
	Vector2i(-5, -11), Vector2i(-4, -11), Vector2i(-3, -11),
	Vector2i(-5, -10), Vector2i(-4, -10), Vector2i(-3, -10)]

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
	var before_shelter := CityStockManager.shelter_capacity
	var before_inventory := Inventory.items.duplicate(true)
	_expect(original.size() == 13, "The source map has the original 13 authored tiles.")
	for cell in PLOT:
		_expect(original.has(cell), "The authored 3×3 footprint contains " + str(cell))
	_expect(house.global_position == marker.global_position, "The review house matches the authored first marker.")
	var binding := city.get_node("ReviewHouseBinding")
	await get_tree().process_frame
	var annex: Node2D = city.get_node("YSortWorld/WorkerRuntime/CityStorageAnnex")
	var annex_label: Label = annex.get_node("AnnexLabel")
	_expect(annex.position == Vector2(-40, 67) and annex_label.text == "ANNEX", "The readable Annex label changes no storage endpoint position.")
	for marker_name: String in ["ToBeClean1", "ToBeClean2", "ToBeClean3", "ToBeClean4"]:
		var authored_marker: Sprite2D = authored.get_node("YSortWorld/" + marker_name)
		var marker_bounds: Rect2 = authored_marker.global_transform * authored_marker.get_rect()
		_expect(not annex_label.get_global_rect().intersects(marker_bounds), "The Annex label does not cover authored plot " + marker_name)
	for phase in ["uncleared", "clearing", "empty", "building", "built", "empty", "uncleared"]:
		state.set("phase", phase)
		state.emit_signal("changed")
		state.emit_signal("changed")
		await get_tree().process_frame
		var showing: bool = phase in ["uncleared", "clearing", "empty", "building"]
		_expect(marker.visible == (phase in ["uncleared", "clearing"]), "The authored marker disappears when cleaning completes: " + phase)
		_expect(not house.get_node("ToBeClean").visible, "The duplicate house rubble remains hidden: " + phase)
		_expect(not house.get_node("SiteHouse").visible, "Legacy site art does not cover the authored footprint.")
		_expect(house.get_node("FinishedHouse").visible == (phase == "built"), "Finished house matches phase " + phase)
		for cell in PLOT:
			_expect((_cell(layer, cell) == original[cell]) if showing else layer.get_cell_source_id(cell) == -1,
				"The original footprint remains visible until the house is built: " + phase)
		for cell in original:
			if cell not in PLOT:
				_expect(_cell(layer, cell) == original[cell], "The separately painted path remains unchanged.")
		for marker_name in ["ToBeClean2", "ToBeClean3", "ToBeClean4"]:
			_expect(authored.get_node("YSortWorld/" + marker_name).visible, "Other authored markers remain visible.")
		_expect(CityStockManager.shelter_capacity == before_shelter and Inventory.items == before_inventory,
			"Presentation refresh does not grant shelter or consume items.")
	state.set("phase", "empty")
	state.emit_signal("changed")
	binding.queue_free()
	await get_tree().process_frame
	_expect(marker.visible and house.get_node("SiteHouse").visible and _snapshot(layer) == original,
		"Removing the binding restores the marker, old view, and complete authored tiles.")
	_expect(_snapshot(fresh.get_node("Ground/Setelah Cleaning")) == original
		and FileAccess.get_sha256(AUTHOR_PATH) == original_hash,
		"The source map remains byte-for-byte unchanged.")
	fresh.free()
	city.queue_free()
	await get_tree().process_frame
	print("AuthoredHouseBindingTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)


func _cell(layer: TileMapLayer, cell: Vector2i) -> Array:
	return [layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell), layer.get_cell_alternative_tile(cell)]


func _snapshot(layer: TileMapLayer) -> Dictionary:
	var result := {}
	for cell in layer.get_used_cells():
		result[cell] = _cell(layer, cell)
	return result
