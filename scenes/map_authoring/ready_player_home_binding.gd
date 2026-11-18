extends Node

## Ready home presentation in the city instance; never edits the authored map.
@export_node_path("Node2D") var marker_path: NodePath
@export_node_path("TileMapLayer") var footprint_path: NodePath
@export_node_path("Node2D") var door_path: NodePath
@export_node_path("Node2D") var exit_spawn_path: NodePath
const VISUAL_BOUNDS = preload("res://scenes/workshop_plot/keeper/workshop_visual_bounds.gd")

func _ready() -> void:
	var marker := get_node(marker_path) as Node2D
	var footprint := get_node(footprint_path) as TileMapLayer
	var door := get_node(door_path) as Node2D
	var exit_spawn := get_node(exit_spawn_path) as Node2D
	var initial_player := door.get_parent().get_node_or_null("Player") as Node2D
	var player_at_initial_spawn: bool = initial_player != null and initial_player.global_position.is_equal_approx(exit_spawn.global_position)
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
	# Align visible ground edges, not the centers of differently sized PNGs.
	# Move the doorway assembly with its art so walls, Y-sort anchor and the
	# existing exit clearance stay coherent. The authored plot never moves.
	var house := door.get_node("House") as Sprite2D
	var plot_bounds: Rect2 = VISUAL_BOUNDS.measure(marker)
	var house_bounds: Rect2 = VISUAL_BOUNDS.measure(house)
	if plot_bounds.has_area() and house_bounds.has_area():
		door.global_position.y += plot_bounds.end.y - house_bounds.end.y
	exit_spawn.global_position = door.global_position + exit_offset
	# Keep the scene's fresh-start player outside the moved trigger. Checkpoint
	# restoration remains owned by CitySave and is never rewritten here.
	if player_at_initial_spawn:
		initial_player.global_position = exit_spawn.global_position
	marker.hide()
	for cell: Vector2i in cells:
		footprint.erase_cell(cell)
