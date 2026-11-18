@tool
extends Sprite2D

## Editor-only guides for authored Clay controls (automatic fallback for legacy scenes).
## Mirrors resource_site_presentation._resource_contact geometry and the default
## content_worksites.site_slot_destination formula; the QA test compares both.
const RUNTIME_SCENE = "res://scenes/content_scene/worksites/main_map_worksites.tscn"
const NAVIGATION = preload("res://scenes/content_scene/worksites/worksite_navigation.gd")
var _runtime_icon: Dictionary = {}
var _guide: Node2D

func _ready() -> void:
	if Engine.is_editor_hint():
		_guide = Node2D.new()
		_guide.name = "ClayEditorGuides"
		_guide.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
		add_child(_guide, false, Node.INTERNAL_MODE_BACK)
		_guide.draw.connect(_draw_preview)
		item_rect_changed.connect(_guide.queue_redraw)
		set_notify_transform(true)
		_guide.queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint() and is_instance_valid(_guide):
		_guide.queue_redraw()

func _property(state: SceneState, index: int, key: String, fallback: Variant) -> Variant:
	for p: int in range(state.get_node_property_count(index)):
		if state.get_node_property_name(index, p) == key:
			return state.get_node_property_value(index, p)
	return fallback

func _icon_settings() -> Dictionary:
	if not _runtime_icon.is_empty():
		return _runtime_icon
	var packed: PackedScene = load(RUNTIME_SCENE)
	var state: SceneState = packed.get_state()
	var bindings: Dictionary = _property(state, 0, "authored_resource_paths", {})
	var site_id: String = ""
	for id: Variant in bindings:
		if str(bindings[id]).get_file() == str(name):
			site_id = str(id)
			break
	if site_id not in ["ClaySiteA", "ClaySiteB"]:
		return {}
	for i: int in range(state.get_node_count()):
		if str(state.get_node_path(i)).trim_prefix("./") == "WorksiteMarkers/" + site_id + "/ResourceIcon":
			_runtime_icon = {"position": _property(state, i, "position", Vector2.ZERO),
				"offset": _property(state, i, "offset", Vector2.ZERO),
				"centered": _property(state, i, "centered", true),
				"texture": _property(state, i, "texture", null)}
			return _runtime_icon
	return {}

## World-space results permit independent comparison with the live runtime.
func refresh_editor_preview() -> void:
	if Engine.is_editor_hint() and is_instance_valid(_guide):
		_guide.queue_redraw()

func preview_geometry() -> Dictionary:
	var authored: Dictionary = preload("res://scenes/map_authoring/clay_authoring_geometry.gd").read(self)
	if not authored.ok:
		return {}
	if authored.configured:
		return authored
	var settings: Dictionary = _icon_settings()
	if settings.is_empty() or texture == null or texture != settings.texture:
		return {}
	# Runtime authoring currently requires the same unrotated/unscaled basis.
	if not global_transform.x.is_equal_approx(Vector2.RIGHT) or not global_transform.y.is_equal_approx(Vector2.DOWN) or flip_h or flip_v or region_enabled or hframes != 1 or vframes != 1:
		return {}
	var image: Image = texture.get_image()
	var used: Rect2i = image.get_used_rect()
	if used.size == Vector2i.ZERO:
		return {}
	var art_offset: Vector2 = offset - Vector2(image.get_size()) * 0.5 if centered else offset
	var icon_offset: Vector2 = settings.offset - Vector2(image.get_size()) * 0.5 if settings.centered else settings.offset
	var center: Vector2 = Vector2(used.position) + Vector2(used.size) * 0.5
	var origin: Vector2 = to_global(center + art_offset) - (settings.position + center + icon_offset)
	var left: int = image.get_width()
	var right: int = -1
	var top: int = maxi(used.position.y, used.end.y - 6)
	for y: int in range(top, used.end.y):
		for x: int in range(used.position.x, used.end.x):
			if image.get_pixel(x, y).a > 0.0:
				left = mini(left, x)
				right = maxi(right, x)
	if right < left:
		return {}
	var polygon := PackedVector2Array()
	var bottom: float = -INF
	for pixel: Vector2 in [Vector2(left, top), Vector2(right + 1, top), Vector2(right + 1, used.end.y), Vector2(left, used.end.y)]:
		var point: Vector2 = to_global(pixel + art_offset)
		polygon.append(point)
		bottom = maxf(bottom, point.y)
	var y: float = maxf(origin.y + 8.0, bottom + NAVIGATION.CLEARANCE + 1.0)
	return {"collision": polygon, "slots": PackedVector2Array([Vector2(origin.x - 10.0, y), Vector2(origin.x + 10.0, y)])}

func _draw_preview() -> void:
	if not Engine.is_editor_hint():
		return
	var geometry: Dictionary = preview_geometry()
	if geometry.is_empty():
		_guide.draw_string(ThemeDB.fallback_font, Vector2(-20, 24), "Preview unavailable", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.ORANGE)
		return
	var outline := PackedVector2Array()
	for point: Vector2 in geometry.collision:
		outline.append(to_local(point))
	outline.append(outline[0])
	_guide.draw_polyline(outline, Color(1.0, 0.35, 0.2), 1.0)
	for i: int in range(2):
		var point: Vector2 = to_local(geometry.slots[i])
		_guide.draw_circle(point, NAVIGATION.CLEARANCE, Color(0.15, 0.9, 1.0), false, 0.8)
		_guide.draw_line(point - Vector2(2, 0), point + Vector2(2, 0), Color.WHITE)
		_guide.draw_line(point - Vector2(0, 2), point + Vector2(0, 2), Color.WHITE)
		_guide.draw_string(ThemeDB.fallback_font, point + Vector2(-2, 12), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.15, 0.9, 1.0))
