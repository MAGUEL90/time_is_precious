class_name RaidTravelProgress extends Control

const TRACK_COLOR: Color = Color(0.32, 0.25, 0.20, 1.0)
const TRACK_FILL: Color = Color(0.72, 0.28, 0.20, 1.0)
const CASTLE_ICON: Texture2D = preload("res://assets/ui/ui_icon/castle_icon.png")
const RAIDER_ICON: Texture2D = preload("res://assets/ui/ui_icon/raider_icon.png")

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

var travel_total_minutes: int = 1
var arrival_minutes_remaining: int = 1
var progress_ratio: float = 0.0

func set_travel_progress(total_minutes: int, remaining_minutes: int) -> void:
	travel_total_minutes = maxi(total_minutes, 1)
	arrival_minutes_remaining = clampi(remaining_minutes, 0, travel_total_minutes)
	progress_ratio = 1.0 - float(arrival_minutes_remaining) / float(travel_total_minutes)
	queue_redraw()

func _draw() -> void:
	var center_y: float = floorf(size.y * 0.5)
	var castle_center_x: float = 10.0
	var raider_start_x: float = maxf(castle_center_x + 18.0, size.x - 10.0)
	var raider_x: float = lerpf(raider_start_x, castle_center_x + 17.0, progress_ratio)
	var track_start: float = castle_center_x + 10.0
	var track_end: float = raider_start_x - 9.0
	if track_end > track_start:
		draw_rect(Rect2(track_start, center_y - 1.0, track_end - track_start, 2.0), TRACK_COLOR)
		var traveled_width: float = (track_end - track_start) * progress_ratio
		if traveled_width > 0.0:
			draw_rect(Rect2(track_end - traveled_width, center_y - 1.0, traveled_width, 2.0), TRACK_FILL)
	_draw_castle(castle_center_x, center_y)
	_draw_raider(roundf(raider_x), center_y)

func _draw_castle(center_x: float, center_y: float) -> void:
	draw_texture(CASTLE_ICON, Vector2(center_x - 8, center_y - 8).floor())

func _draw_raider(center_x: float, center_y: float) -> void:
	draw_texture(RAIDER_ICON, Vector2(center_x - 8, center_y - 8).floor())
