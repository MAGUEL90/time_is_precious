extends Node

## Main-map entrypoint. State and presentation outlive maps in the existing host.
const STATE: Script = preload("res://scenes/raid/raid_state.gd")
const UI: PackedScene = preload("res://scenes/raid/raid_ui.tscn")
const CONFIG_PATH: String = "res://scenes/raid/wall_playtest.tres"
const STATE_NAME: String = "CityRaid"
var state: Node

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

	state.changed.connect(_refresh_wall_tiles)
	_refresh_wall_tiles()

func _refresh_wall_tiles() -> void:
	var wall: TileMapLayer = get_parent().get_node("YSortWorld/WallStone")
	var source_id: int = 1 if state.wall_hp > 0 else 0
	for cell: Vector2i in wall.get_used_cells():
		if wall.get_cell_source_id(cell) != source_id:
			wall.set_cell(cell, source_id, wall.get_cell_atlas_coords(cell), wall.get_cell_alternative_tile(cell))
