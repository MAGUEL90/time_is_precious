extends Sprite2D
## Stable tree_id must be unique across maps. Each position is one pickup slot.
const STATE: Script = preload("res://scenes/pickup_item/date_palm_state.gd")
const PICKUP: PackedScene = preload("res://scenes/pickup_item/pickup_item.tscn")

@export var tree_id: String = "starting_date_palm"
@export_range(1, 100, 1) var max_pickups: int = 3
@export var pickup_positions: Array[Vector2] = [Vector2(-14, 36), Vector2(25, 21), Vector2(-23, 11)]
@export var pickup_texture: Texture2D
var state: Node
var _pickups: Dictionary = {}

func _ready() -> void:
	if tree_id.is_empty() or not tree_id.is_valid_identifier() or pickup_positions.size() < max_pickups:
		push_error("Date palm needs a unique identifier and at least max_pickups positions.")
		return
	var state_name: String = "DatePalm_" + tree_id
	state = WorkStateRuntime.get_node_or_null(state_name)
	if state == null:
		state = STATE.new()
		state.name = state_name
		WorkStateRuntime.add_child(state)
	state.configure(max_pickups)
	state.changed.connect(_queue_refresh)
	call_deferred("_refresh")

func _queue_refresh() -> void:
	call_deferred("_refresh")

func _refresh() -> void:
	if not is_inside_tree() or not is_instance_valid(state):
		return
	for slot: int in range(state.available.size()):
		var existing = _pickups.get(slot)
		if not state.available[slot]:
			if is_instance_valid(existing) and not existing.is_collecting:
				existing.queue_free()
			_pickups.erase(slot)
		elif not is_instance_valid(existing) or existing.is_collecting:
			var pickup = PICKUP.instantiate()
			pickup.name = "DatesPickup" + ("" if slot == 0 else str(slot + 1))
			pickup.item_id = "date_cluster"
			pickup.quantity = 1
			pickup.world_texture = pickup_texture
			pickup.position = position + pickup_positions[slot]
			pickup.collected.connect(state.collect.bind(slot))
			_pickups[slot] = pickup
			get_parent().add_child(pickup)

func _exit_tree() -> void:
	if is_instance_valid(state) and state.changed.is_connected(_queue_refresh):
		state.changed.disconnect(_queue_refresh)
