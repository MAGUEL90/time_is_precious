extends RefCounted

## Bounds of authored object art only, excluding labels, prompts and menu layers.
static var _opaque_regions: Dictionary = {}

static func measure(root: Node, excluded: Array[Node] = []) -> Rect2:
	var parts: Array[Rect2] = []
	_collect(root, parts, excluded)
	if parts.is_empty():
		return Rect2()
	var bounds: Rect2 = parts[0]
	for part: Rect2 in parts:
		bounds = bounds.merge(part)
	return bounds

static func _collect(node: Node, parts: Array[Rect2], excluded: Array[Node]) -> void:
	if node in excluded or node is Control or node is CanvasLayer:
		return
	if node is CanvasItem and not node.is_visible_in_tree():
		return
	if node is Sprite2D and node.texture != null and node.modulate.a * node.self_modulate.a > 0.0:
		var bounds: Rect2 = _sprite_bounds(node)
		if bounds.has_area():
			parts.append(bounds)
	elif node is AnimatedSprite2D and node.sprite_frames != null and node.modulate.a * node.self_modulate.a > 0.0:
		var bounds: Rect2 = _animated_bounds(node)
		if bounds.has_area():
			parts.append(bounds)
	elif node is Polygon2D and node.color.a * node.modulate.a * node.self_modulate.a > 0.0:
		var points: PackedVector2Array = node.polygon
		if not points.is_empty():
			var bounds := Rect2(node.to_global(points[0] + node.offset), Vector2.ZERO)
			for point: Vector2 in points:
				bounds = bounds.expand(node.to_global(point + node.offset))
			if bounds.has_area():
				parts.append(bounds)
	for child: Node in node.get_children():
		_collect(child, parts, excluded)

static func _sprite_bounds(sprite: Sprite2D) -> Rect2:
	var source := Rect2(Vector2.ZERO, sprite.texture.get_size())
	if sprite.region_enabled:
		source = sprite.region_rect
	var frame_size: Vector2 = source.size / Vector2(sprite.hframes, sprite.vframes)
	var frame := Rect2i(source.position + Vector2(sprite.frame_coords) * frame_size, frame_size)
	var used: Rect2i = _opaque_region(sprite.texture, frame)
	if not used.has_area():
		return Rect2()
	if sprite.flip_h:
		used.position.x = frame.size.x - used.end.x
	if sprite.flip_v:
		used.position.y = frame.size.y - used.end.y
	var drawn: Rect2 = sprite.get_rect()
	var pixel_scale: Vector2 = drawn.size / Vector2(frame.size)
	var local_bounds := Rect2(drawn.position + Vector2(used.position) * pixel_scale, Vector2(used.size) * pixel_scale)
	return sprite.global_transform * local_bounds

static func _animated_bounds(sprite: AnimatedSprite2D) -> Rect2:
	if not sprite.sprite_frames.has_animation(sprite.animation):
		return Rect2()
	var texture: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return Rect2()
	var used: Rect2i = _opaque_region(texture, Rect2i(Vector2i.ZERO, texture.get_size()))
	if not used.has_area():
		return Rect2()
	if sprite.flip_h:
		used.position.x = texture.get_width() - used.end.x
	if sprite.flip_v:
		used.position.y = texture.get_height() - used.end.y
	var origin: Vector2 = sprite.offset - texture.get_size() * 0.5 if sprite.centered else sprite.offset
	return sprite.global_transform * Rect2(origin + Vector2(used.position), Vector2(used.size))

static func _opaque_region(texture: Texture2D, frame: Rect2i) -> Rect2i:
	var key: String = "%d:%s" % [texture.get_instance_id(), frame]
	if not _opaque_regions.has(key):
		var image: Image = _texture_image(texture)
		_opaque_regions[key] = image.get_region(frame).get_used_rect() if image != null else Rect2i()
	return _opaque_regions[key]

static func _texture_image(texture: Texture2D) -> Image:
	if texture is AtlasTexture:
		var atlas: AtlasTexture = texture as AtlasTexture
		var source: Image = _texture_image(atlas.atlas)
		var region := Rect2i(atlas.region)
		if region.size == Vector2i.ZERO:
			region = Rect2i(Vector2i.ZERO, source.get_size())
		var image := Image.create(atlas.get_width(), atlas.get_height(), false, Image.FORMAT_RGBA8)
		image.blit_rect(source, region, Vector2i(atlas.margin.position))
		return image
	var image: Image = texture.get_image()
	if image != null and image.is_compressed():
		image.decompress()
	return image
