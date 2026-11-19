extends Node

## Mirrors only the date's artwork into the player-sorted world. The actual
## pickup, collision, interaction and source identity stay at their old paths.
var pickup: Node2D
var source: Sprite2D
var proxy: Node2D
var artwork: Sprite2D
var source_color: Color

func _ready() -> void:
	_setup.call_deferred()

func _setup() -> void:
	pickup = get_parent() as Node2D
	if not is_instance_valid(pickup):
		return
	var ancestor: Node = pickup.get_parent()
	while ancestor != null and ancestor.scene_file_path != "res://scenes/content_scene/content_scene.tscn":
		ancestor = ancestor.get_parent()
	if ancestor == null:
		return
	var world: Node2D = ancestor.get_node_or_null("YSortWorld") as Node2D
	source = pickup.get_node_or_null("Icon") as Sprite2D
	if world == null or source == null or source.texture == null:
		return
	proxy = Node2D.new()
	proxy.name = "SortedDateVisual"
	artwork = Sprite2D.new()
	artwork.texture = source.texture
	artwork.centered = source.centered
	artwork.offset = source.offset
	artwork.flip_h = source.flip_h
	artwork.flip_v = source.flip_v
	artwork.material = source.material
	artwork.texture_filter = source.texture_filter
	source_color = source.self_modulate
	world.add_child(proxy)
	proxy.add_child(artwork)
	source.self_modulate.a = 0.0
	RenderingServer.frame_pre_draw.connect(_sync_visual)
	_sync_visual()

func _sync_visual() -> void:
	if not is_instance_valid(proxy) or not is_instance_valid(pickup) or not is_instance_valid(source):
		return
	proxy.visible = pickup.is_visible_in_tree() and source.visible
	proxy.global_position = pickup.global_position
	proxy.modulate = pickup.modulate
	artwork.global_transform = source.global_transform
	artwork.modulate = source.modulate
	artwork.self_modulate = source_color

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_visual):
		RenderingServer.frame_pre_draw.disconnect(_sync_visual)
	if is_instance_valid(proxy):
		proxy.queue_free()
