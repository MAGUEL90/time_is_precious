extends Node

## Adds small feet-level solids in the city instance, without editing the
## authored map or giving plants and pickups physical bodies.
const STONE_TEXTURES: Array[String] = [
	"res://assets/objects/nature/stone/small_stone.png",
	"res://assets/objects/nature/stone/blocked_stone_1.png",
	"res://assets/objects/nature/stone/blocked_stone_2.png",
]

func _ready() -> void:
	_setup.call_deferred()

func _setup() -> void:
	var city: Node = get_parent()
	var authored_world: Node = city.get_node("AuthoredMap/YSortWorld")
	_add_pond_collisions(city.get_node("AuthoredMap/Ground/Base") as TileMapLayer)
	for child: Node in authored_world.get_children():
		var sprite: Sprite2D = child as Sprite2D
		if sprite == null or sprite.texture == null or not sprite.visible:
			continue
		if STONE_TEXTURES.has(sprite.texture.resource_path):
			_add_stone(sprite)
	var palm: Sprite2D = authored_world.get_node_or_null("DatePalmTree") as Sprite2D
	var visual: Sprite2D = city.get_node_or_null("YSortWorld/AuthoredPalmSortedVisual") as Sprite2D
	if palm != null and visual != null and palm.visible:
		var base: Vector2 = palm.to_local(visual.global_position)
		_add_rect(palm, "TrunkBody", Rect2(base + Vector2(-4, -4), Vector2(8, 4)))
	var home: Node2D = city.get_node_or_null("YSortWorld/HomeDoor") as Node2D
	if home != null:
		# The middle remains open so the existing door trigger stays reachable.
		_add_rect(home, "HomeWallLeft", Rect2(-22, -9, 12, 17))
		_add_rect(home, "HomeWallRight", Rect2(10, -9, 12, 17))
		_add_rect(home, "HomeWallBack", Rect2(-22, -13, 44, 4))

# These authored 16px atlas tiles form the two ponds in the initial scene.
# Derive each width from the top edge and keep the border itself walkable.
func _add_pond_collisions(layer: TileMapLayer) -> void:
	if layer == null:
		return
	var tile_size: Vector2 = Vector2(layer.tile_set.tile_size)
	if tile_size != Vector2(16, 16):
		push_error("Cannot place pond collisions: unexpected tile size.")
		return
	for cell: Vector2i in layer.get_used_cells():
		if layer.get_cell_atlas_coords(cell) != Vector2i(14, 19):
			continue
		var width := 1
		while layer.get_cell_atlas_coords(cell + Vector2i(width, 0)) == Vector2i(15, 19):
			width += 1
		if layer.get_cell_atlas_coords(cell + Vector2i(width, 0)) != Vector2i(16, 19):
			continue
		width += 1
		var top_left: Vector2 = layer.map_to_local(cell) - tile_size * 0.5
		_add_rect(layer, "PondWaterBody_%d_%d" % [cell.x, cell.y], Rect2(top_left + Vector2(9, 14), Vector2(width * 16 - 18, 23)))
func _add_stone(sprite: Sprite2D) -> void:
	var image: Image = sprite.texture.get_image()
	if image == null or image.is_empty():
		return
	var used: Rect2i = image.get_used_rect()
	if not used.has_area():
		return
	var origin: Vector2 = sprite.get_rect().position
	var width: float = maxf(4.0, floorf(float(used.size.x) * 0.6))
	var center_x: float = origin.x + float(used.position.x) + float(used.size.x) * 0.5
	var bottom: float = origin.y + float(used.end.y)
	_add_rect(sprite, "StoneBody", Rect2(center_x - width * 0.5, bottom - 3.0, width, 3.0))

func _add_rect(parent: Node2D, node_name: String, rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 2
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.shape = shape
	collision.position = rect.get_center()
	body.add_child(collision)
	parent.add_child(body)
