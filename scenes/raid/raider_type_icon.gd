extends Control
class_name RaiderTypeIcon

var type_id: String = ""
var source_texture: Texture2D

func set_icon(next_type_id: String, next_texture: Texture2D = null) -> void:
	type_id = next_type_id.to_lower()
	source_texture = next_texture
	queue_redraw()

func _draw() -> void:
	if source_texture != null:
		draw_texture_rect(source_texture, Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0)), false)
		return
	match type_id:
		"light":
			_draw_light_raider()
		"normal":
			_draw_normal_raider()
		"heavy":
			_draw_heavy_raider()
		_:
			_draw_unknown_raider()

func _pixel(x: float, y: float, width: float, height: float, color: Color) -> void:
	var origin: Vector2 = (size - Vector2(24.0, 24.0)) * 0.5
	draw_rect(Rect2(origin + Vector2(x, y), Vector2(width, height)), color)

func _draw_light_raider() -> void:
	var outline: Color = Color("#271d19")
	var skin: Color = Color("#d99a68")
	var cloth: Color = Color("#62915c")
	var shade: Color = Color("#3f6444")
	_pixel(8, 2, 8, 4, outline)
	_pixel(10, 4, 6, 6, skin)
	_pixel(8, 4, 2, 4, shade)
	_pixel(16, 6, 2, 2, outline)
	_pixel(10, 12, 6, 2, outline)
	_pixel(8, 14, 10, 6, outline)
	_pixel(10, 14, 6, 4, cloth)
	_pixel(10, 20, 4, 2, outline)
	_pixel(16, 20, 4, 2, outline)
	_pixel(20, 12, 2, 8, outline)
	_pixel(22, 10, 2, 4, Color("#d5d0bd"))

func _draw_normal_raider() -> void:
	var outline: Color = Color("#271d19")
	var skin: Color = Color("#d99a68")
	var cloth: Color = Color("#b58346")
	var shade: Color = Color("#765334")
	_pixel(8, 2, 8, 4, outline)
	_pixel(10, 4, 6, 6, skin)
	_pixel(8, 4, 2, 4, shade)
	_pixel(16, 6, 2, 2, outline)
	_pixel(6, 12, 12, 2, outline)
	_pixel(6, 14, 12, 6, outline)
	_pixel(8, 14, 8, 4, cloth)
	_pixel(8, 18, 4, 4, outline)
	_pixel(14, 18, 4, 4, outline)
	_pixel(20, 10, 2, 10, outline)
	_pixel(22, 8, 2, 4, Color("#d5d0bd"))

func _draw_heavy_raider() -> void:
	var outline: Color = Color("#241b1a")
	var skin: Color = Color("#c7845c")
	var armor: Color = Color("#657887")
	var highlight: Color = Color("#96a6ac")
	var shade: Color = Color("#414e5a")
	_pixel(6, 2, 12, 6, outline)
	_pixel(8, 4, 8, 4, highlight)
	_pixel(10, 6, 6, 6, skin)
	_pixel(8, 10, 2, 2, outline)
	_pixel(16, 10, 2, 2, outline)
	_pixel(4, 12, 16, 2, outline)
	_pixel(2, 14, 20, 6, outline)
	_pixel(4, 14, 16, 4, armor)
	_pixel(6, 18, 5, 4, outline)
	_pixel(13, 18, 5, 4, outline)
	_pixel(20, 12, 2, 8, shade)
	_pixel(22, 10, 2, 6, highlight)

func _draw_unknown_raider() -> void:
	var outline: Color = Color("#271d19")
	var fill: Color = Color("#77706a")
	_pixel(8, 3, 8, 6, outline)
	_pixel(10, 5, 4, 2, fill)
	_pixel(6, 11, 12, 9, outline)
	_pixel(8, 13, 8, 5, fill)
	_pixel(8, 20, 4, 2, outline)
	_pixel(14, 20, 4, 2, outline)
