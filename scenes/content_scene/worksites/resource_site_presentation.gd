extends RefCounted

const VISIBLE_BOUNDS = preload("res://scenes/workshop_plot/keeper/workshop_visual_bounds.gd")
const PROMPT_GAP: float = 4.0

## Contact geometry follows the authored art, without changing its visible pixels.
static func configure(site: Node2D) -> void:
	var icon: Sprite2D = site.get_node_or_null("ResourceIcon")
	if site.name in [&"ClaySiteA", &"ReedSite"] and site.has_node("Label"):
		site.get_node("Label").hide()
	if icon != null and icon.texture != null:
		position_prompt(site, icon)
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

static func position_prompt(site: Node2D, icon: Sprite2D) -> void:
	var prompt: InteractableLabelComponent = site.get_node_or_null("InteractPrompt")
	if prompt == null:
		return
	var art: Rect2 = VISIBLE_BOUNDS.measure(icon)
	if not art.has_area():
		return
	var current: Rect2 = prompt.get_global_transform() * Rect2(Vector2.ZERO, prompt.size)
	var shift: Vector2
	if site.name in [&"ClaySiteA", &"WoodSite", &"ReedSite"]:
		shift = Vector2(art.end.x + PROMPT_GAP - current.position.x, art.position.y - PROMPT_GAP - current.end.y)
	elif site.name in [&"StrawSite", &"WaterSite"]:
		shift = Vector2(art.position.x - PROMPT_GAP - current.end.x, art.position.y - PROMPT_GAP - current.end.y)
	else:
		shift = Vector2(art.get_center().x - current.get_center().x, art.position.y - PROMPT_GAP - current.end.y)
	prompt.position += site.global_transform.affine_inverse().basis_xform(shift)
	prompt.position_offset = prompt.position
