extends Node2D
## Identity derives from the authored scene and node path, so duplicates are independent.
## Keep node names/paths or explicit persistence_id stable across saves.
const STATE: Script = preload("res://scenes/pickup_item/pickup_source_state.gd")
const PICKUP: PackedScene = preload("res://scenes/pickup_item/pickup_item.tscn")

@export var item_id: String = ""
@export_range(1, 100000, 1) var quantity: int = 1
@export var refill_enabled: bool = true
@export_range(1, 10000, 1) var refill_min_hours: int = 1
@export_range(1, 10000, 1) var refill_max_hours: int = 18
## Optional authored identity; unique within the owning scene. Never use a runtime instance ID.
@export var persistence_id: String = ""

var tree_id: String
@export_range(1, 100, 1) var max_pickups: int = 3
@export var pickup_positions: Array[Vector2] = [Vector2(-14, 36), Vector2(25, 21), Vector2(-23, 11)]
@export var pickup_texture: Texture2D
var state: Node
var _pickups: Dictionary = {}

func _ready() -> void:
	if max_pickups < 1 or max_pickups > 100 or pickup_positions.size() < max_pickups or quantity < 1 or ItemDatabase.get_item_data(item_id) == null or refill_min_hours < 1 or refill_max_hours < refill_min_hours:
		push_error("Invalid pickup source item, capacity, positions, quantity or refill configuration.")
		return
	var scene_root: Node = get_parent() if get_parent() != null else self
	while scene_root.scene_file_path.is_empty() and scene_root.get_parent() != null:
		scene_root = scene_root.get_parent()
	if scene_root.scene_file_path.is_empty():
		push_error("Pickup source must belong to an authored scene for stable identity.")
		return
	# An instanced source scene belongs to its authored owner, so two instances
	# get distinct paths in the enclosing map rather than sharing their own root path.
	while scene_root.owner != null:
		scene_root = scene_root.owner
	var relative_path: String = str(scene_root.get_path_to(self))
	tree_id = (scene_root.scene_file_path + ":" + (relative_path if persistence_id.is_empty() else "id:" + persistence_id)).sha256_text()
	var state_name: String = _state_prefix() + tree_id
	var config: Dictionary = {"item_id": item_id, "quantity": quantity, "capacity": max_pickups, "refill_enabled": refill_enabled, "refill_min_hours": refill_min_hours, "refill_max_hours": refill_max_hours}
	state = WorkStateRuntime.get_node_or_null(state_name)
	if state == null:
		state = _new_state()
		state.name = state_name
		WorkStateRuntime.add_child(state)
	if state.active_view != null and is_instance_valid(state.active_view.get_ref()):
		push_error("Duplicate pickup source identity: " + state_name)
		state = null
		return
	if not state.source_config.is_empty() and state.source_config != config:
		push_error("Pickup source configuration changed during the session: " + state_name)
		state = null
		return
	state.source_scene = scene_root.scene_file_path
	state.source_config = config
	state.active_view = weakref(self)
	state.add_to_group("pickup_source_states")
	state.configure(max_pickups)
	state.set_meta("display_name", relative_path)
	if state.available.size() > pickup_positions.size():
		push_error("Restart the session after changing pickup source capacity/positions.")
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
		elif not is_instance_valid(existing) or existing.is_collecting or existing.is_queued_for_deletion():
			var pickup = PICKUP.instantiate()
			pickup.name = _pickup_name() + ("" if slot == 0 else str(slot + 1))
			# This view belongs to the source ledger, not the city inventory-drop checkpoint.
			pickup.add_to_group("source_pickups")
			_tag_pickup(pickup)
			pickup.item_id = item_id
			pickup.quantity = quantity
			pickup.world_texture = pickup_texture
			pickup.position = get_parent().to_local(to_global(pickup_positions[slot]))
			pickup.collected.connect(state.collect.bind(slot))
			_pickups[slot] = pickup
			get_parent().add_child(pickup)

func _exit_tree() -> void:
	for pickup in _pickups.values():
		if is_instance_valid(pickup):
			pickup.queue_free()
	if is_instance_valid(state):
		state.active_view = null
		if state.changed.is_connected(_queue_refresh):
			state.changed.disconnect(_queue_refresh)

func _state_prefix() -> String:
	return "PickupSource_"

func _new_state() -> Node:
	return STATE.new()

func _pickup_name() -> String:
	return "SourcePickup"

func _tag_pickup(_pickup: Node) -> void:
	pass
