extends Control

## A still copy of Gabbi's visible layers; owns no NPC or gameplay state.
func show_visual(source: Node2D) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var pose := Node2D.new()
	pose.name = "Pose"
	add_child(pose)
	var bounds := Rect2()
	var has_bounds := false
	for layer: Node in source.get_children():
		if not layer is AnimatedSprite2D or not layer.is_visible_in_tree():
			continue
		var texture: Texture2D = layer.sprite_frames.get_frame_texture(layer.animation, layer.frame)
		if texture == null:
			continue
		var used := Rect2(texture.get_image().get_used_rect())
		if not used.has_area():
			continue
		if layer.flip_h:
			used.position.x = texture.get_width() - used.end.x
		if layer.flip_v:
			used.position.y = texture.get_height() - used.end.y
		used.position += layer.offset
		if layer.centered:
			used.position -= texture.get_size() * 0.5
		used = layer.transform * used
		bounds = bounds.merge(used) if has_bounds else used
		has_bounds = true
		var sprite := Sprite2D.new()
		sprite.name = layer.name
		sprite.texture = texture
		sprite.transform = layer.transform
		sprite.centered = layer.centered
		sprite.offset = layer.offset
		sprite.flip_h = layer.flip_h
		sprite.flip_v = layer.flip_v
		sprite.modulate = layer.modulate
		sprite.self_modulate = layer.self_modulate
		sprite.z_index = layer.z_index
		pose.add_child(sprite)
	if has_bounds:
		# Whole-pixel scaling and a two-pixel inset preserve the existing frame.
		var available := size - Vector2(4, 4)
		var zoom := maxf(1.0, floorf(minf(available.x / bounds.size.x, available.y / bounds.size.y)))
		pose.scale = Vector2.ONE * zoom
		pose.position = (size * 0.5 - bounds.get_center() * zoom).round()
