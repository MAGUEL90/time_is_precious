extends Node

## Ready home presentation in the city instance; never edits the authored map.
@export_node_path("Node2D") var marker_path: NodePath
@export_node_path("TileMapLayer") var footprint_path: NodePath
@export_node_path("Node2D") var door_path: NodePath
@export_node_path("Node2D") var exit_spawn_path: NodePath

func _ready() -> void:
	var marker := get_node(marker_path) as Node2D
	var footprint := get_node(footprint_path) as TileMapLayer
	var door := get_node(door_path) as Node2D
	var exit_spawn := get_node(exit_spawn_path) as Node2D
	# Preserve the established doorway-to-exit separation.
	var exit_offset: Vector2 = exit_spawn.global_position - door.global_position
	var center: Vector2i = footprint.local_to_map(footprint.to_local(marker.global_position))
	var cells: Array[Vector2i] = []
	for y in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2):
			var cell := Vector2i(x, y)
			if footprint.get_cell_source_id(cell) >= 0:
				cells.append(cell)
	if not cells.is_empty() and cells.size() != 9:
		push_error("Ready player home requires an empty or complete 3x3 authored footprint.")
		return
	door.global_position = marker.global_position
	exit_spawn.global_position = door.global_position + exit_offset
	marker.hide()
	for cell: Vector2i in cells:
		footprint.erase_cell(cell)
