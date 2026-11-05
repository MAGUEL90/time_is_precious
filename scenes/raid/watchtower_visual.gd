extends Node2D

## Small world marker for the completed MVP addition; no collision or combat stats.
## Replace its drawing with dedicated tower art when that asset is available.
var constructing: bool = false

func set_construction(value: bool) -> void:
	if constructing != value:
		constructing = value
		queue_redraw()

func _draw() -> void:
	var outline := Color("69502f")
	var stone := Color("c4aa76")
	var light := Color("ddc493")
	var shadow := Color("9a7a49")
	if constructing:
		# A scaffold identifies the future structure without looking completed.
		draw_rect(Rect2(-9, -4, 18, 4), outline)
		draw_rect(Rect2(-7, -3, 14, 2), stone)
		draw_line(Vector2(-7, -4), Vector2(-7, -24), outline, 2.0)
		draw_line(Vector2(7, -4), Vector2(7, -24), outline, 2.0)
		draw_line(Vector2(-9, -22), Vector2(9, -22), outline, 2.0)
		draw_line(Vector2(-6, -5), Vector2(6, -21), shadow, 1.0)
		draw_line(Vector2(6, -5), Vector2(-6, -21), shadow, 1.0)
		return
	draw_rect(Rect2(-8, -25, 16, 25), outline)
	draw_rect(Rect2(-6, -21, 12, 20), stone)
	draw_rect(Rect2(3, -21, 3, 20), shadow)
	for y: int in [-18, -12, -6]:
		draw_line(Vector2(-6, y), Vector2(6, y), outline, 1.0)
		draw_line(Vector2(-1, y), Vector2(-1, y + 5), shadow, 1.0)
	draw_rect(Rect2(-10, -25, 20, 7), outline)
	draw_rect(Rect2(-9, -24, 18, 4), light)
	for x: int in [-10, -2, 6]:
		draw_rect(Rect2(x, -29, 4, 7), outline)
		draw_rect(Rect2(x + 1, -28, 2, 5), stone)
	draw_rect(Rect2(-2, -15, 4, 5), outline)
