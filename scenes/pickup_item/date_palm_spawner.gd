extends "res://scenes/pickup_item/pickup_source.gd"
## Date-palm defaults and legacy identities; all behavior lives in PickupSource.

func _init() -> void:
	item_id = "date_cluster"

func _state_prefix() -> String:
	return "DatePalm_"

func _new_state() -> Node:
	return preload("res://scenes/pickup_item/date_palm_state.gd").new()

func _pickup_name() -> String:
	return "DatesPickup"

func _tag_pickup(pickup: Node) -> void:
	pickup.add_to_group("date_palm_pickups")
