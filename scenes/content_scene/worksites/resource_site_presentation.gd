extends RefCounted

const POPLAR: Texture2D = preload("res://assets/objects/nature/trees/poplar.png")
const STUMP: Texture2D = preload("res://assets/objects/nature/trees/cutted_poplar.png")
const CUTTED_REED: Texture2D = preload("res://assets/objects/worksites/cutted_reed_site.png")
const VISIBLE_BOUNDS = preload("res://scenes/workshop_plot/keeper/workshop_visual_bounds.gd")
const TREE_SWAY = preload("res://scenes/pickup_item/palm_sway.gd")
const WOOD_ROOTS: Array[Vector2] = [Vector2.ZERO]
const WOOD_SHADOW_COLOR: Color = Color8(147, 129, 98, 255)
static var _wood_tree_texture: Texture2D
static var _wood_shadow_texture: Texture2D
static var _wood_trunk_bottom: float

static func _prepare_wood_layers() -> void:
	if _wood_tree_texture != null:
		return
	var image: Image = POPLAR.get_image()
	image.convert(Image.FORMAT_RGBA8)
	var shadow: Image = Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).is_equal_approx(WOOD_SHADOW_COLOR):
				shadow.set_pixel(x, y, WOOD_SHADOW_COLOR)
				image.set_pixel(x, y, Color.TRANSPARENT)
	_wood_trunk_bottom = float(image.get_used_rect().end.y) - 64.0
	_wood_tree_texture = ImageTexture.create_from_image(image)
	_wood_shadow_texture = ImageTexture.create_from_image(shadow)

## Contact geometry follows the authored art, without changing its visible pixels.
static func configure(site: Node2D, finite_resource: bool = false) -> void:
	var icon: Sprite2D = site.get_node_or_null("ResourceIcon")
	var is_wood: bool = site.get("item_id") == "wood_log"
	if is_wood:
		_configure_wood(site, icon)
	if finite_resource:
		_configure_ready_particles(site)
	if site.name in [&"ClaySiteA", &"ClaySiteB", &"ReedSite", &"ReedSiteB"] and site.has_node("Label"):
		site.get_node("Label").hide()
	if not is_wood and icon != null and icon.texture != null:
		position_prompt(site, icon)
	if icon == null or icon.texture == null:
		return
	if not site.has_node("ResourceBase"):
		var image: Image = icon.texture.get_image()
		var used: Rect2i = image.get_used_rect()
		if used.size != Vector2i.ZERO:
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
			if right >= left:
				offset = icon.offset - Vector2(image.get_size()) * 0.5 if icon.centered else icon.offset
				var points := PackedVector2Array()
				for point: Vector2 in [Vector2(left, top), Vector2(right + 1, top), Vector2(right + 1, used.end.y), Vector2(left, used.end.y)]:
					points.append(site.to_local(icon.to_global(point + offset)))
				if is_wood:
					# The hidden log icon is offset from the visible tree. Its old
					# collider blocked empty ground to the right of the trunk.
					var tree: Sprite2D = site.get_node("WoodGrove/Tree0") as Sprite2D
					var base: Vector2 = site.to_local(tree.global_position)
					points = PackedVector2Array([base + Vector2(-4, -4), base + Vector2(4, -4), base + Vector2(4, 0), base + Vector2(-4, 0)])
				var body := StaticBody2D.new()
				body.name = "ResourceBase"
				body.collision_layer = 1
				body.collision_mask = 2
				var collision := CollisionPolygon2D.new()
				collision.name = "CollisionPolygon2D"
				collision.polygon = points
				body.add_child(collision)
				site.add_child(body)
	if site.has_meta("authored_clay_geometry"):
		var clay_shape: CollisionPolygon2D = site.get_node("ResourceBase/CollisionPolygon2D")
		clay_shape.polygon = site.get_meta("authored_clay_geometry").collision
	if finite_resource and site.get("item_id") == "reed_bundle":
		_configure_cutted_reed(site, icon)

## The original ResourceIcon and ResourceBase stay in place as navigation and
## worker-slot geometry. The resource base is fitted to the visible trunk;
## old routes and saved target coordinates remain unchanged.
static func _configure_wood(site: Node2D, icon: Sprite2D) -> void:
	if icon != null:
		icon.hide()
	for name: String in ["Footprint", "Label"]:
		var node: CanvasItem = site.get_node_or_null(name) as CanvasItem
		if node != null:
			node.hide()
	if not site.has_node("WoodGrove"):
		_prepare_wood_layers()
		var grove := Node2D.new()
		grove.name = "WoodGrove"
		grove.y_sort_enabled = true
		site.add_child(grove)
		for index: int in range(WOOD_ROOTS.size()):
			var border_suffix: String = str(site.name).trim_prefix("WoodSiteBorder")
			var flipped: bool = str(site.name).begins_with("WoodSiteBorder") and border_suffix.is_valid_int() and int(border_suffix) % 2 == 1
			var shadow := Sprite2D.new()
			shadow.name = "Shadow%d" % index
			shadow.texture = _wood_shadow_texture
			shadow.centered = false
			shadow.offset = Vector2(-16, -64)
			shadow.position = WOOD_ROOTS[index]
			shadow.z_index = -1
			shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			shadow.flip_h = flipped or index % 2 == 1
			grove.add_child(shadow)
			var tree := Sprite2D.new()
			tree.name = "Tree%d" % index
			tree.texture = _wood_tree_texture
			tree.centered = false
			tree.offset = Vector2(-16, -64 - _wood_trunk_bottom)
			tree.position = WOOD_ROOTS[index] + Vector2(0, _wood_trunk_bottom)
			tree.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tree.flip_h = flipped or index % 2 == 1
			grove.add_child(tree)
			var sway: Node = TREE_SWAY.new()
			sway.name = "TreeSway"
			tree.add_child(sway)
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
		# The former grove-sized area reached the top of a single tree. Keep
		# interaction around the trunk and ground instead of the canopy.
		shape.size = Vector2(32, 32)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = Vector2(0, -4)
		area.add_child(collision)
		site.add_child(area)
	var prompt: InteractableLabelComponent = site.get_node_or_null("InteractPrompt")
	if prompt != null:
		prompt.place_above_art(site.get_node("WoodGrove/Tree0"))

## Called after settled stock changes and after restoring the runtime state.
static func set_wood_depleted(site: Node2D, depleted: bool) -> void:
	if not is_instance_valid(site) or site.get("item_id") != "wood_log":
		return
	var grove: Node2D = site.get_node_or_null("WoodGrove") as Node2D
	if grove == null:
		return
	for index: int in range(WOOD_ROOTS.size()):
		grove.get_node("Tree%d" % index).visible = not depleted
		grove.get_node("Shadow%d" % index).visible = not depleted
		grove.get_node("Stump%d" % index).visible = depleted
	var prompt: InteractableLabelComponent = site.get_node_or_null("InteractPrompt")
	if prompt != null:
		prompt.place_above_art(grove.get_node("Stump0" if depleted else "Tree0"))

static func set_reed_depleted(site: Node2D, depleted: bool) -> void:
	if not is_instance_valid(site) or site.get("item_id") != "reed_bundle":
		return
	var cut: CanvasItem = site.get_node_or_null("CuttedReed") as CanvasItem
	if cut != null:
		cut.visible = depleted
		var prompt: InteractableLabelComponent = site.get_node_or_null("InteractPrompt")
		if prompt != null:
			prompt.place_above_art(cut if depleted else site.get_node("ResourceIcon"))

static func _configure_cutted_reed(site: Node2D, icon: Sprite2D) -> void:
	if site.has_node("CuttedReed"):
		return
	var cut := Sprite2D.new()
	cut.name = "CuttedReed"
	cut.texture = CUTTED_REED
	cut.texture_filter = icon.texture_filter
	cut.centered = icon.centered
	cut.offset = icon.offset
	cut.position = icon.position
	cut.rotation = icon.rotation
	cut.scale = icon.scale
	cut.flip_h = icon.flip_h
	cut.flip_v = icon.flip_v
	cut.z_index = icon.z_index
	cut.region_enabled = icon.region_enabled
	cut.region_rect = icon.region_rect
	# The replacement art can have a different transparent margin than its
	# ready art. Keep their opaque bottoms on the exact same feet anchor.
	cut.position += _sprite_bottom_in_parent(icon) - _sprite_bottom_in_parent(cut)
	cut.hide()
	site.add_child(cut)

static func _sprite_bottom_in_parent(sprite: Sprite2D) -> Vector2:
	if sprite.texture == null:
		return sprite.position
	var image: Image = sprite.texture.get_image()
	var used: Rect2i = image.get_used_rect()
	var offset: Vector2 = sprite.offset - Vector2(image.get_size()) * 0.5 if sprite.centered else sprite.offset
	return sprite.position + sprite.transform.basis_xform(Vector2(0, used.end.y + offset.y))

static func _configure_ready_particles(site: Node2D) -> void:
	if site.has_node("ReadyParticles"):
		return
	var particles := CPUParticles2D.new()
	particles.name = "ReadyParticles"
	var art: CanvasItem = site.get_node_or_null("WoodGrove/Tree0") if site.get("item_id") == "wood_log" else site.get_node_or_null("ResourceIcon")
	var art_bounds: Rect2 = VISIBLE_BOUNDS.measure(art) if art != null else Rect2()
	if site.get("item_id") == "wood_log" and site.has_node("WoodGrove/Shadow0"):
		art_bounds = art_bounds.merge(VISIBLE_BOUNDS.measure(site.get_node("WoodGrove/Shadow0")))
	particles.position = site.to_local(art_bounds.get_center()).round() if art_bounds.has_area() else Vector2(0, -18)
	particles.z_index = 2
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particles.amount = 6
	particles.lifetime = 1.5
	particles.explosiveness = 0.0
	particles.randomness = 0.65
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 5.0
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.gravity = Vector2(0, -3)
	particles.initial_velocity_min = 5.0
	particles.initial_velocity_max = 10.0
	particles.scale_amount_min = 0.75
	particles.scale_amount_max = 1.2
	particles.color = Color(1.0, 0.86, 0.38, 0.9)
	particles.emitting = true
	site.add_child(particles)

static func position_prompt(site: Node2D, icon: Sprite2D) -> void:
	var prompt: InteractableLabelComponent = site.get_node_or_null("InteractPrompt")
	if prompt == null:
		return
	prompt.place_above_art(icon)
