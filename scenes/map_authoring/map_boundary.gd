extends StaticBody2D

## Exterior feet area only. Local walls never clamp the player in Nightmare.
@export var walkable_rect := Rect2(24, -232, 336, 208)
const WALL_THICKNESS: float = 16.0

var _camera: Camera2D
var _camera_defaults: Dictionary = {}
var _nightmare_active: bool = false

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	# Mask only the world outside the authored frame, below CanvasLayer HUDs.
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	var a: Vector2 = walkable_rect.position
	var b: Vector2 = walkable_rect.end
	var t: float = WALL_THICKNESS
	var walls: Array[Rect2] = [
		Rect2(a - Vector2(t, t), Vector2(t, walkable_rect.size.y + 2 * t)),
		Rect2(Vector2(b.x, a.y - t), Vector2(t, walkable_rect.size.y + 2 * t)),
		Rect2(Vector2(a.x, a.y - t), Vector2(walkable_rect.size.x, t)),
		Rect2(Vector2(a.x, b.y), Vector2(walkable_rect.size.x, t)),
	]
	for rect: Rect2 in walls:
		var collider := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		collider.shape = shape
		collider.position = rect.get_center()
		add_child(collider)
	_bind_camera.call_deferred()

func get_world_rect() -> Rect2:
	return global_transform * walkable_rect

func _bind_camera() -> void:
	_camera = get_node_or_null("../YSortWorld/Player/Camera2D") as Camera2D
	if _camera == null:
		return
	for property: StringName in [&"zoom", &"offset", &"limit_left", &"limit_top", &"limit_right", &"limit_bottom"]:
		_camera_defaults[property] = _camera.get(property)
	var nightmare: Node = get_node_or_null("../YSortWorld/NightmareWorld")
	if nightmare != null:
		nightmare.nightmare_active_changed.connect(_on_nightmare_active_changed)
		nightmare.nightmare_ui.visibility_changed.connect(_on_nightmare_visibility_changed.bind(nightmare.nightmare_ui))
		_nightmare_active = nightmare.is_active
	get_viewport().size_changed.connect(_update_camera_bounds)
	_update_camera_bounds()

func _on_nightmare_active_changed(active: bool) -> void:
	_nightmare_active = active
	_update_camera_bounds()

func _on_nightmare_visibility_changed(nightmare_ui: CanvasLayer) -> void:
	# The UI hides under black before returning; active_changed(false) comes
	# after fade-in, too late to prevent an unbounded glimpse of the city.
	if not nightmare_ui.visible:
		_on_nightmare_active_changed(false)

func _update_camera_bounds() -> void:
	if not is_instance_valid(_camera):
		return
	if _nightmare_active:
		for property: StringName in _camera_defaults:
			_camera.set(property, _camera_defaults[property])
	else:
		# Include the existing outer wall, not the large background tile layers.
		var bounds: Rect2 = global_transform * walkable_rect.grow(WALL_THICKNESS)
		var viewport_size: Vector2 = get_viewport_rect().size
		# Keep one source pixel per logical viewport pixel. A smaller map is
		# centered with blank margins instead of stretched by a fractional zoom.
		var frame_size: Vector2 = bounds.size.max(viewport_size).ceil()
		var frame_start: Vector2 = (bounds.get_center() - frame_size * 0.5).floor()
		_camera.zoom = Vector2.ONE
		# Camera2D offset can move the view beyond its limits; only the city uses zero.
		_camera.offset = Vector2.ZERO
		_camera.limit_left = int(frame_start.x)
		_camera.limit_top = int(frame_start.y)
		_camera.limit_right = int(frame_start.x + frame_size.x)
		_camera.limit_bottom = int(frame_start.y + frame_size.y)
	_camera.reset_smoothing()
	_camera.force_update_scroll()
	queue_redraw()

func _draw() -> void:
	if _nightmare_active:
		return
	var bounds: Rect2 = walkable_rect.grow(WALL_THICKNESS)
	var margin: Vector2 = get_viewport_rect().size.ceil()
	var left_top: Vector2 = bounds.position - margin
	draw_rect(Rect2(left_top, Vector2(margin.x, bounds.size.y + 2 * margin.y)), Color.BLACK)
	draw_rect(Rect2(Vector2(bounds.end.x, left_top.y), Vector2(margin.x, bounds.size.y + 2 * margin.y)), Color.BLACK)
	draw_rect(Rect2(Vector2(bounds.position.x, left_top.y), Vector2(bounds.size.x, margin.y)), Color.BLACK)
	draw_rect(Rect2(Vector2(bounds.position.x, bounds.end.y), Vector2(bounds.size.x, margin.y)), Color.BLACK)
