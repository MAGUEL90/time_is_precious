extends Sprite2D
## Identity derives from the authored scene and node path, so duplicates are independent.
## Keep node names/paths stable during a session; each position is one pickup slot.
const STATE: Script = preload("res://scenes/pickup_item/date_palm_state.gd")
const PICKUP: PackedScene = preload("res://scenes/pickup_item/pickup_item.tscn")

var tree_id: String
@export_range(1, 100, 1) var max_pickups: int = 3
@export var pickup_positions: Array[Vector2] = [Vector2(-14, 36), Vector2(25, 21), Vector2(-23, 11)]
@export var pickup_texture: Texture2D
var state: Node
var _pickups: Dictionary = {}

func _ready() -> void:
	if max_pickups < 1 or pickup_positions.size() < max_pickups:
		push_error("Date palm needs at least max_pickups positions.")
		return
	var scene_root: Node = self
	while scene_root.scene_file_path.is_empty() and scene_root.get_parent() != null:
		scene_root = scene_root.get_parent()
	if scene_root.scene_file_path.is_empty():
		push_error("Date palm must belong to an authored scene for stable session identity.")
		return
	var relative_path: String = str(scene_root.get_path_to(self))
	tree_id = (scene_root.scene_file_path + ":" + relative_path).sha256_text()
	var state_name: String = "DatePalm_" + tree_id
	state = WorkStateRuntime.get_node_or_null(state_name)
	if state == null:
		state = STATE.new()
		state.name = state_name
		WorkStateRuntime.add_child(state)
	state.configure(max_pickups)
	state.set_meta("display_name", relative_path)
	if state.available.size() > pickup_positions.size():
		push_error("Restart the session after changing date pickup capacity/positions.")
		return
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
			pickup.position = get_parent().to_local(to_global(pickup_positions[slot]))
			pickup.collected.connect(state.collect.bind(slot))
			_pickups[slot] = pickup
			get_parent().add_child(pickup)

func _exit_tree() -> void:
	for pickup in _pickups.values():
		if is_instance_valid(pickup):
			pickup.queue_free()
	if is_instance_valid(state) and state.changed.is_connected(_queue_refresh):
		state.changed.disconnect(_queue_refresh)
