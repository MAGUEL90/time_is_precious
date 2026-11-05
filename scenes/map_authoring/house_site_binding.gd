extends Node

## Binds the authored 3×3 cleared plot to the existing house state. All tile
## edits affect only the map instance, never the owner's authoring scene.
@export_node_path("TileMapLayer") var footprint_path: NodePath
@export_node_path("Node2D") var marker_path: NodePath
@export_node_path("Node2D") var house_path: NodePath

var _footprint: TileMapLayer
var _house: Node2D
var _marker: Node2D
var _construction: Node
var _cells: Array[Dictionary] = []
var _displayed: Variant = null
var _bound: bool = false
var _marker_was_visible: bool = true


func _ready() -> void:
	_footprint = get_node_or_null(footprint_path) as TileMapLayer
	_marker = get_node_or_null(marker_path) as Node2D
	_house = get_node_or_null(house_path) as Node2D
	if _footprint == null or _marker == null or _house == null or not _house.has_method("use_authored_site_footprint"):
		push_error("House site binding is missing an authored layer, marker, or house.")
		return
	_construction = _house.get("construction") as Node
	if _marker.global_position.distance_to(_house.global_position) > 0.1 or not is_instance_valid(_construction):
		push_error("House site binding requires the house at the authored marker.")
		return
	var center := _footprint.local_to_map(_footprint.to_local(_marker.global_position))
	for y in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2):
			var cell := Vector2i(x, y)
			var source_id := _footprint.get_cell_source_id(cell)
			if source_id < 0:
				push_error("House site binding requires the complete authored 3×3 footprint.")
				_cells.clear()
				return
			_cells.append({"cell": cell, "source": source_id,
				"atlas": _footprint.get_cell_atlas_coords(cell),
				"alternative": _footprint.get_cell_alternative_tile(cell)})
	_marker_was_visible = _marker.visible
	_house.call("use_authored_site_footprint", true)
	_construction.connect("changed", _sync_footprint)
	_bound = true
	_sync_footprint()


func _sync_footprint() -> void:
	var phase: String = str(_construction.get("phase"))
	_marker.visible = _marker_was_visible and phase in ["uncleared", "clearing"]
	# The artist's source already shows this footprint beneath the rubble. Keep
	# it visible until the finished house replaces the plot.
	var show_site: bool = phase in ["uncleared", "clearing", "empty", "building"]
	if _displayed == show_site:
		return
	for entry: Dictionary in _cells:
		if show_site:
			_footprint.set_cell(entry.cell, entry.source, entry.atlas, entry.alternative)
		else:
			_footprint.erase_cell(entry.cell)
	_displayed = show_site


func _exit_tree() -> void:
	if not _bound:
		return
	if is_instance_valid(_house):
		_house.call("use_authored_site_footprint", false)
	if is_instance_valid(_marker):
		_marker.visible = _marker_was_visible
	if is_instance_valid(_footprint):
		for entry: Dictionary in _cells:
			_footprint.set_cell(entry.cell, entry.source, entry.atlas, entry.alternative)
