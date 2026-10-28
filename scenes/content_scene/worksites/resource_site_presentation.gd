extends RefCounted

## Contact geometry follows the authored art, without changing its visible pixels.
static func configure(site: Node2D) -> void:
	var icon: Sprite2D = site.get_node_or_null("ResourceIcon")
	if icon == null or icon.texture == null or site.has_node("ResourceBase"):
		return
	var image: Image = icon.texture.get_image()
	var used: Rect2i = image.get_used_rect()
	if used.size == Vector2i.ZERO:
		return
	var offset: Vector2 = icon.offset - Vector2(image.get_size()) * 0.5 if icon.centered else icon.offset
	var bottom: float = used.end.y + offset.y
	# All layers stay at native Z; the opaque bottom owns front/back ordering.
	icon.position += icon.transform.basis_xform(Vector2(0, bottom))
	icon.offset.y -= bottom
	site.y_sort_enabled = true
	var left: int = image.get_width()
	var right: int = -1
	var top: int = maxi(used.position.y, used.end.y - 6)
	for y: int in range(top, used.end.y):
		for x: int in range(used.position.x, used.end.x):
			if image.get_pixel(x, y).a > 0.0:
				left = mini(left, x)
				right = maxi(right, x)
	if right < left:
		return
	offset = icon.offset - Vector2(image.get_size()) * 0.5 if icon.centered else icon.offset
	var points := PackedVector2Array()
	for point: Vector2 in [Vector2(left, top), Vector2(right + 1, top), Vector2(right + 1, used.end.y), Vector2(left, used.end.y)]:
		points.append(site.to_local(icon.to_global(point + offset)))
	var body := StaticBody2D.new()
	body.name = "ResourceBase"
	body.collision_layer = 1
	body.collision_mask = 2
	var collision := CollisionPolygon2D.new()
	collision.name = "CollisionPolygon2D"
	collision.polygon = points
	body.add_child(collision)
	site.add_child(body)
