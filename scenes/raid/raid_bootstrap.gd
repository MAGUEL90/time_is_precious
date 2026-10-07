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
