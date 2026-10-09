extends Node

## Main-map entrypoint. State and presentation outlive maps in the existing host.
const STATE: Script = preload("res://scenes/raid/raid_state.gd")
const UI: PackedScene = preload("res://scenes/raid/raid_ui.tscn")
const WORLD_INDICATOR: PackedScene = preload("res://scenes/raid/wall_world_indicator.tscn")
const CONFIG_PATH: String = "res://scenes/raid/wall_playtest.tres"
const STATE_NAME: String = "CityRaid"
var state: Node
var raid_ui: RaidUI
var wall_indicator: WallWorldIndicator
var watchtower_visual: Node2D

func _ready() -> void:
	state = WorkStateRuntime.get_node_or_null(STATE_NAME)
	if state == null:
		state = STATE.new()
		state.name = STATE_NAME
		# Load after script initialization, then keep the template separate from runtime state.
		state.config = load(CONFIG_PATH).duplicate(true)
		state.storage = WorkStateRuntime.get_node_or_null("CityToolStorage")
		WorkStateRuntime.add_child(state)
		var ui: CanvasLayer = UI.instantiate()
		ui.name = "RaidUI"
		state.add_child(ui)
		ui.build_requested.connect(state.build_wall)
		ui.repair_requested.connect(state.repair_wall)
		ui.bind_state(state)

	raid_ui = state.get_node_or_null("RaidUI") as RaidUI
	if is_instance_valid(raid_ui):
		raid_ui.set_city_management_available(true)
	if not state.changed.is_connected(_refresh_wall_tiles):
		state.changed.connect(_refresh_wall_tiles)
	_setup_wall_indicator()
	_setup_watchtower_visual()
	_refresh_wall_tiles()

func _exit_tree() -> void:
	if is_instance_valid(state) and state.has_signal("changed") and state.changed.is_connected(_refresh_wall_tiles):
		state.changed.disconnect(_refresh_wall_tiles)
	if is_instance_valid(raid_ui):
		raid_ui.set_city_management_available(false)
	if is_instance_valid(wall_indicator):
		wall_indicator.bind_state(null)
		wall_indicator.queue_free()

func _setup_wall_indicator() -> void:
	var wall: TileMapLayer = get_parent().get_node_or_null("YSortWorld/WallStone") as TileMapLayer
	if wall == null:
		return
	wall_indicator = WORLD_INDICATOR.instantiate() as WallWorldIndicator
	if wall_indicator == null:
		return
	wall_indicator.name = "WallWorldIndicator"
	add_child(wall_indicator)
	wall_indicator.global_position = _get_south_wall_anchor(wall)
	wall_indicator.bind_state(state)

func _setup_watchtower_visual() -> void:
	var wall: TileMapLayer = get_parent().get_node_or_null("YSortWorld/WallStone") as TileMapLayer
	if wall == null or wall.get_used_cells().is_empty():
		return
	var corner: Vector2i = wall.get_used_cells()[0]
	for cell: Vector2i in wall.get_used_cells():
		if cell.y > corner.y or (cell.y == corner.y and cell.x > corner.x):
			corner = cell
	watchtower_visual = preload("res://scenes/raid/watchtower_visual.gd").new()
	watchtower_visual.name = "WatchtowerVisual"
	add_child(watchtower_visual)
	watchtower_visual.global_position = wall.to_global(wall.map_to_local(corner)) + Vector2(0, 7)

func _get_south_wall_anchor(wall: TileMapLayer) -> Vector2:
	var cells: Array[Vector2i] = wall.get_used_cells()
	if cells.is_empty():
		return wall.global_position
	var south_row: int = cells[0].y
	var x_total: float = 0.0
	var south_count: int = 0
	for cell: Vector2i in cells:
		if cell.y > south_row:
			south_row = cell.y
			x_total = float(cell.x)
			south_count = 1
		elif cell.y == south_row:
			x_total += float(cell.x)
			south_count += 1
	# Use the eastern half of the south wall, clear of Iddin-Sin in the center.
	var east_x: int = cells[0].x
	for cell: Vector2i in cells:
		if cell.y == south_row:
			east_x = maxi(east_x, cell.x)
	var center_x: float = x_total / float(maxi(south_count, 1))
	var anchor_cell := Vector2i(roundi((center_x + east_x) * 0.5), south_row)
	return wall.to_global(wall.map_to_local(anchor_cell))

func _refresh_wall_tiles() -> void:
	if is_instance_valid(watchtower_visual):
		watchtower_visual.visible = state.watchtower_built
	var wall: TileMapLayer = get_parent().get_node("YSortWorld/WallStone")
	var source_id: int = 1 if state.wall_hp > 0 else 0
	for cell: Vector2i in wall.get_used_cells():
		if wall.get_cell_source_id(cell) != source_id:
			wall.set_cell(cell, source_id, wall.get_cell_atlas_coords(cell), wall.get_cell_alternative_tile(cell))
