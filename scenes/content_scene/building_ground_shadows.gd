extends Node

const SHADOW_COLOR: Color = Color8(147, 129, 98, 255)
var _silhouettes: Dictionary = {}

func _ready() -> void:
	_setup.call_deferred()

func _setup() -> void:
	var city: Node = get_parent()
	_add_shadow(city.get_node_or_null("YSortWorld/WorkerRuntime/CityStorageArea/Sprite2D") as Sprite2D)
	var world: Node = city.get_node("YSortWorld")
	for child: Node in world.get_children():
		if child is Node2D and child.has_node("FinishedClayWorkshop/Sprite2D"):
			_add_shadow(child.get_node("FinishedClayWorkshop/Sprite2D") as Sprite2D)

func _add_shadow(sprite: Sprite2D) -> void:
	if sprite == null or sprite.texture == null or sprite.has_node("GroundShadow"):
		return
	var image: Image = sprite.texture.get_image()
	if image == null or image.is_empty():
		return
	var used: Rect2i = image.get_used_rect()
	if not used.has_area():
		return
	var source: Rect2 = sprite.get_rect()
	var center: float = source.position.x + float(used.position.x) + float(used.size.x) * 0.5
	var bottom: float = source.position.y + float(used.end.y)
	var half_width: float = roundf(float(used.size.x) * 0.5) + 5.0
	var shadow := Polygon2D.new()
	shadow.name = "GroundShadow"
	shadow.color = SHADOW_COLOR
	shadow.z_index = -1
	shadow.polygon = PackedVector2Array([
		Vector2(center - half_width + 6, bottom - 10), Vector2(center + half_width - 6, bottom - 10),
		Vector2(center + half_width - 2, bottom - 8), Vector2(center + half_width, bottom - 5),
		Vector2(center + half_width, bottom + 1), Vector2(center + half_width - 5, bottom + 4),
		Vector2(center - half_width + 5, bottom + 4), Vector2(center - half_width, bottom + 1),
		Vector2(center - half_width, bottom - 5), Vector2(center - half_width + 2, bottom - 8),
	])
	sprite.add_child(shadow)
	# The silhouette follows the actual art so the shadow reaches the sides and
	# roof as well as the ground beneath the building.
	var key: int = sprite.texture.get_instance_id()
	if not _silhouettes.has(key):
		image.convert(Image.FORMAT_RGBA8)
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				var alpha: float = image.get_pixel(x, y).a
				image.set_pixel(x, y, Color(SHADOW_COLOR.r, SHADOW_COLOR.g, SHADOW_COLOR.b, alpha))
		_silhouettes[key] = ImageTexture.create_from_image(image)
	var silhouette := Sprite2D.new()
	silhouette.name = "BuildingShadowSilhouette"
	silhouette.texture = _silhouettes[key]
	silhouette.centered = sprite.centered
	silhouette.offset = sprite.offset
	silhouette.flip_h = sprite.flip_h
	silhouette.flip_v = sprite.flip_v
	silhouette.position = Vector2(2, 2)
	silhouette.z_index = -1
	silhouette.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.add_child(silhouette)
