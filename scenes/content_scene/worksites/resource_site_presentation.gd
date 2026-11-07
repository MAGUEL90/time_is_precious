extends RefCounted

const POPLAR: Texture2D = preload("res://assets/objects/nature/trees/poplar.png")
const STUMP: Texture2D = preload("res://assets/objects/nature/trees/cutted_poplar.png")
const WOOD_ROOTS: Array[Vector2] = [Vector2(-18, -4), Vector2(-6, -8), Vector2(6, -8), Vector2(18, -4)]

## Contact geometry follows the authored art, without changing its visible pixels.
static func configure(site: Node2D) -> void:
	var icon: Sprite2D = site.get_node_or_null("ResourceIcon")
	var is_wood: bool = site.get("item_id") == "wood_log"
	if is_wood:
		_configure_wood(site, icon)
	if site.name in [&"ClaySiteA", &"ClaySiteB", &"ReedSite", &"ReedSiteB"] and site.has_node("Label"):
		site.get_node("Label").hide()
	if not is_wood and icon != null and icon.texture != null:
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

## The original ResourceIcon and ResourceBase stay in place as navigation and
## worker-slot geometry. Grove art has no new solids: regrowth cannot trap an
## actor, and old routes and saved target coordinates remain valid.
static func _configure_wood(site: Node2D, icon: Sprite2D) -> void:
	if icon != null:
		icon.hide()
	for name: String in ["Footprint", "Label"]:
		var node: CanvasItem = site.get_node_or_null(name) as CanvasItem
		if node != null:
			node.hide()
	if not site.has_node("WoodGrove"):
		var grove := Node2D.new()
		grove.name = "WoodGrove"
		grove.y_sort_enabled = true
		site.add_child(grove)
		for index: int in range(WOOD_ROOTS.size()):
			var tree := Sprite2D.new()
			tree.name = "Tree%d" % index
			tree.texture = POPLAR
			tree.centered = false
			tree.offset = Vector2(-16, -64)
			tree.position = WOOD_ROOTS[index]
			tree.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tree.flip_h = index % 2 == 1
			grove.add_child(tree)
			var stump := Sprite2D.new()
			stump.name = "Stump%d" % index
			stump.texture = STUMP
			stump.centered = false
			stump.offset = Vector2(-8, -16)
			stump.position = WOOD_ROOTS[index]
			stump.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			stump.hide()
			grove.add_child(stump)
	if not site.has_node("WoodInteractionArea"):
		var area := Area2D.new()
		area.name = "WoodInteractionArea"
		area.collision_layer = 0
		area.collision_mask = 2 # player
		area.monitorable = false
		var shape := RectangleShape2D.new()
		shape.size = Vector2(64, 84)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = Vector2(0, -30)
		area.add_child(collision)
		site.add_child(area)
	# Place E outside the grove; the two close eastern sites use opposite sides.
	var prompt: InteractableLabelComponent = site.get_node_or_null("InteractPrompt")
	if prompt != null:
		var put_right: bool = false
		for sibling: Node in site.get_parent().get_children():
			if sibling != site and sibling is Node2D and sibling.get("item_id") == "wood_log":
				var delta: Vector2 = sibling.position - site.position
				if delta.length() < 70.0 and delta.x < 0.0:
					put_right = true
			prompt.position = Vector2(28 if put_right else -44, -20)
		prompt.position_offset = prompt.position

## Called after settled stock changes and after restoring the runtime state.
static func set_wood_depleted(site: Node2D, depleted: bool) -> void:
	if not is_instance_valid(site) or site.get("item_id") != "wood_log":
		return
	var grove: Node2D = site.get_node_or_null("WoodGrove") as Node2D
	if grove == null:
		return
	for index: int in range(WOOD_ROOTS.size()):
		grove.get_node("Tree%d" % index).visible = not depleted
		grove.get_node("Stump%d" % index).visible = depleted

static func position_prompt(site: Node2D, icon: Sprite2D) -> void:
	var prompt: InteractableLabelComponent = site.get_node_or_null("InteractPrompt")
	if prompt == null:
		return
	prompt.place_above_art(icon)
