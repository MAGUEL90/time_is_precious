extends Control
class_name DefenseWorkProgress

const WALL_ICON: Texture2D = preload("res://assets/ui/ui_icon/wall_icon.png")
const WATCHTOWER_ICON: Texture2D = preload("res://assets/ui/ui_icon/watchtower_icon.png")

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

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
	draw_texture(WATCHTOWER_ICON if work_kind == "watchtower" else WALL_ICON, Vector2.ZERO)
	if paused:
		draw_rect(Rect2(1, 10, 2, 5), Color("ddc493"))
		draw_rect(Rect2(5, 10, 2, 5), Color("ddc493"))
