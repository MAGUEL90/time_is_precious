extends RefCounted

## Isolated prototype for the one date palm observed in the laptop-authored map.
## This helper is deliberately not installed as a production scene hook.
const TARGET_PATH: NodePath = ^"AuthoredMap/YSortWorld/DatePalmTree"
const PALM_SCRIPT: Script = preload("res://scenes/pickup_item/date_palm_spawner.gd")
const TREE_TEXTURE_PATH: String = "res://assets/objects/nature/trees/date_palm_tree.png"
const PICKUP_TEXTURE: Texture2D = preload("res://assets/objects/dates_pickup.png")


static func bind_before_tree(map: Node) -> Dictionary:
	if not is_instance_valid(map):
		return _failure("The map instance is missing.")
	if map.is_inside_tree():
		return _failure("Date-palm binding must happen before the map enters the scene tree.")

	var authored_map: Node = map.get_node_or_null("AuthoredMap")
	var candidate: Node = map.get_node_or_null(TARGET_PATH)
	if candidate == null:
		return _failure("The exact authored date-palm path is missing: " + str(TARGET_PATH))
	if not candidate is Sprite2D:
		return _failure("The exact authored date-palm node must be a Sprite2D.")
	var palm: Sprite2D = candidate as Sprite2D
	if palm.is_inside_tree():
		return _failure("The authored date palm is already inside the scene tree.")
	if palm.owner != authored_map:
		return _failure("The authored date palm must be owned by the existing AuthoredMap instance.")
	if palm.texture == null or palm.texture.resource_path != TREE_TEXTURE_PATH:
		return _failure("The authored date palm uses unexpected tree art.")

	var current_script: Script = palm.get_script() as Script
	if current_script == PALM_SCRIPT:
		var current_pickup_texture: Texture2D = palm.get("pickup_texture") as Texture2D
		if current_pickup_texture == null or current_pickup_texture.resource_path != PICKUP_TEXTURE.resource_path:
			return _failure("The existing date-palm binding has an unexpected pickup texture.")
		return _success(true)
	if current_script != null:
		return _failure("The authored date-palm node already has a foreign script.")

	palm.set_script(PALM_SCRIPT)
	palm.set("pickup_texture", PICKUP_TEXTURE)
	if palm.get_script() != PALM_SCRIPT:
		return _failure("Godot did not accept the existing date-palm spawner script.")
	return _success(false)


static func _success(already_bound: bool) -> Dictionary:
	return {"ok": true, "error": "", "path": str(TARGET_PATH), "already_bound": already_bound}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "path": str(TARGET_PATH), "already_bound": false}
