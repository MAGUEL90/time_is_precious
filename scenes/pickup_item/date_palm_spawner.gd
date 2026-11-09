extends "res://scenes/pickup_item/pickup_source.gd"
## Date-palm defaults and legacy identities. Each slot remains separately saved.

var _gathering: bool = false

func _init() -> void:
	item_id = "date_cluster"

func _ready() -> void:
	super._ready()
	if not world_view_enabled:
		visible = false
		return
	# The pickup source and its world positions stay fixed; only the art sways.
	var visual: Node = self
	if visual is Sprite2D and not has_node("PalmSway"):
		var sway := preload("res://scenes/pickup_item/palm_sway.gd").new()
		sway.name = "PalmSway"
		add_child(sway)

func _state_prefix() -> String:
	return "DatePalm_"

func _new_state() -> Node:
	return preload("res://scenes/pickup_item/date_palm_state.gd").new()

func _pickup_name() -> String:
	return "DatesPickup"

func _tag_pickup(pickup: Node) -> void:
	pickup.add_to_group("date_palm_pickups")
	pickup.gather_handler = _gather_from_palm


func _gather_from_palm(player: Player, chosen: PickUpItem) -> void:
	if _gathering or not is_instance_valid(state) or not is_instance_valid(player) or not is_instance_valid(chosen):
		return
	var chosen_slot: Variant = _pickups.find_key(chosen)
	if not chosen_slot is int or chosen_slot < 0 or chosen_slot >= state.available.size() or not state.available[chosen_slot]:
		return
	_gathering = true
	var gathered: int = 0
	# The selected fruit is attempted first, retaining its full-inventory shake.
	var candidates: Array = [chosen_slot]
	for slot: int in _pickups.keys():
		if slot != chosen_slot:
			candidates.append(slot)
	for slot: int in candidates:
		if slot < 0 or slot >= state.available.size() or not state.available[slot]:
			continue
		var pickup: PickUpItem = _pickups.get(slot)
		if not is_instance_valid(pickup) or pickup.is_queued_for_deletion() or pickup.is_collecting:
			continue
		if pickup != chosen and not Inventory.has_capacity_for(pickup.item_id, pickup.quantity):
			break
		pickup.suppress_pickup_popup = true
		pickup.on_player_interact(player)
		if not is_instance_valid(pickup):
			break
		pickup.suppress_pickup_popup = false
		if pickup.is_collecting:
			gathered += pickup.quantity
		elif pickup == chosen:
			break
	_gathering = false
	if gathered > 0 and is_instance_valid(chosen) and is_instance_valid(player):
		chosen._spawn_pickup_popup(player, gathered)
