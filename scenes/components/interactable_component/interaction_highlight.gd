extends RefCounted

## Visual-only emphasis for the selected interaction; preserves authored colors.
const TINT := Color(1.3, 1.2, 1.08, 1.0)
var _colors: Dictionary = {}

func clear() -> void:
	for visual in _colors:
		if is_instance_valid(visual):
			visual.self_modulate = _colors[visual]
	_colors.clear()

func select(target: Node) -> void:
	clear()
	if not is_instance_valid(target):
		return
	var visual_root: Node = target.get_meta("interaction_highlight_root", target)
	if is_instance_valid(visual_root):
		_collect(visual_root)

func _collect(node: Node) -> void:
	# Menus, prompts and HUD must retain their own palette.
	if node is Control or node is CanvasLayer:
		return
	if node is Sprite2D or node is AnimatedSprite2D or node is Polygon2D:
		_colors[node] = node.self_modulate
		node.self_modulate *= TINT
	for child in node.get_children():
		_collect(child)
