extends Control
class_name DefenseWorkProgress

## Shared read-only construction marker for the city panel and the world.
@onready var progress_bar: TextureProgressBar = $ProgressBar
var work_kind: String = ""
var paused: bool = false

func show_work(status: Dictionary) -> void:
	work_kind = str(status.get("work_kind", ""))
	visible = not work_kind.is_empty()
	if not visible:
		return
	var total: int = maxi(int(status.get("work_total", 0)), 1)
	var remaining: int = clampi(int(status.get("work_remaining", 0)), 0, total)
	progress_bar.max_value = total
	progress_bar.value = total - remaining
	paused = str(status.get("phase", "")) in ["attacking", "looting"]
	progress_bar.tint_progress = Color("9a8b70") if paused else Color.WHITE
	queue_redraw()

func _draw() -> void:
	var outline := Color("69502f")
	var stone := Color("c4aa76")
	var light := Color("ddc493")
	if work_kind == "watchtower":
		draw_rect(Rect2(4, 5, 8, 10), outline)
		draw_rect(Rect2(5, 5, 6, 9), stone)
		draw_rect(Rect2(2, 2, 12, 5), outline)
		draw_rect(Rect2(3, 3, 10, 2), light)
		for x: int in [2, 7, 12]:
			draw_rect(Rect2(x, 0, 2, 4), stone)
		draw_rect(Rect2(7, 8, 2, 3), outline)
	else:
		draw_rect(Rect2(1, 5, 14, 9), outline)
		draw_rect(Rect2(2, 6, 12, 7), stone)
		for x: int in [1, 6, 11]:
			draw_rect(Rect2(x, 2, 4, 4), outline)
			draw_rect(Rect2(x + 1, 3, 2, 3), light)
		draw_line(Vector2(2, 9), Vector2(13, 9), outline)
		draw_line(Vector2(7, 6), Vector2(7, 12), outline)
	if paused:
		draw_rect(Rect2(1, 10, 2, 5), light)
		draw_rect(Rect2(5, 10, 2, 5), light)
