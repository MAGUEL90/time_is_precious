extends Node

const PALM_SHADOW_COLOR: Color = Color8(147, 129, 98, 255)
const AUTHORED_DECOR_TEXTURES: Array[String] = [
	"res://assets/objects/nature/plant/small_green_plant.png",
	"res://assets/objects/nature/plant/red_plant_01.png",
	"res://assets/objects/nature/stone/small_stone.png",
	"res://assets/objects/nature/stone/blocked_stone_1.png",
	"res://assets/objects/nature/stone/blocked_stone_2.png",
]

## Render the authored palm in the same Y-sorted world as the player. The
## original node stays in place to preserve its pickup positions and identity.
func _ready() -> void:
	_setup.call_deferred()

func _setup() -> void:
	var city: Node = get_parent()
	var palm: Sprite2D = city.get_node_or_null("AuthoredMap/YSortWorld/DatePalmTree") as Sprite2D
	var world: Node2D = city.get_node_or_null("YSortWorld") as Node2D
	if palm == null or world == null or palm.texture == null:
		push_error("Could not locate the authored palm for Y-sorted presentation.")
		return
	var image: Image = palm.texture.get_image()
	if image == null or image.is_empty():
		push_error("Could not determine the authored palm's visual base.")
		return
	# The supplied texture contains an opaque ground shadow. Keep those pixels
	# below characters while the trunk and canopy participate in Y-sorting.
	var shadow_image: Image = Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).is_equal_approx(PALM_SHADOW_COLOR):
				shadow_image.set_pixel(x, y, PALM_SHADOW_COLOR)
				image.set_pixel(x, y, Color.TRANSPARENT)
	# Sort against the trunk's bottom, not the lower edge of its ground shadow.
	var base_y: float = palm.get_rect().position.y + image.get_used_rect().end.y
	var shadow := Sprite2D.new()
	shadow.name = "AuthoredPalmGroundShadow"
	shadow.texture = ImageTexture.create_from_image(shadow_image)
	shadow.centered = palm.centered
	shadow.offset = palm.offset
	shadow.z_index = -1
	shadow.texture_filter = palm.texture_filter
	world.add_child(shadow)
	shadow.global_transform = palm.global_transform
	shadow.visible = palm.is_visible_in_tree()
	var visual := Sprite2D.new()
	visual.name = "AuthoredPalmSortedVisual"
	visual.texture = ImageTexture.create_from_image(image)
	visual.centered = palm.centered
	visual.offset = palm.offset - Vector2(0, base_y)
	visual.material = palm.material
	visual.modulate = palm.modulate
	visual.self_modulate = palm.self_modulate
	visual.texture_filter = palm.texture_filter
	world.add_child(visual)
	visual.global_position = palm.to_global(Vector2(0, base_y))
	visual.global_rotation = palm.global_rotation
	visual.global_scale = palm.global_scale
	visual.visible = palm.is_visible_in_tree()
	palm.self_modulate.a = 0.0
	_sort_authored_decor(city, world)

func _sort_authored_decor(city: Node, world: Node2D) -> void:
	var authored_world: Node = city.get_node("AuthoredMap/YSortWorld")
	for node: Node in authored_world.get_children():
		var source: Sprite2D = node as Sprite2D
		if source == null or source.texture == null or not source.visible:
			continue
		if not AUTHORED_DECOR_TEXTURES.has(source.texture.resource_path):
			continue
		var image: Image = source.texture.get_image()
		if image == null or image.is_empty() or not image.get_used_rect().has_area():
			continue
		var base_y: float = source.get_rect().position.y + image.get_used_rect().end.y
		var visual := Sprite2D.new()
		visual.name = "SortedDecor_" + source.name
		visual.texture = source.texture
		visual.centered = source.centered
		visual.offset = source.offset - Vector2(0, base_y)
		visual.flip_h = source.flip_h
		visual.flip_v = source.flip_v
		visual.modulate = source.modulate
		visual.self_modulate = source.self_modulate
		visual.material = source.material
		visual.texture_filter = source.texture_filter
		world.add_child(visual)
		visual.global_position = source.to_global(Vector2(0, base_y))
		visual.global_rotation = source.global_rotation
		visual.global_scale = source.global_scale
		source.self_modulate.a = 0.0
