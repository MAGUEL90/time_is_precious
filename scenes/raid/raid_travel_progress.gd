class_name RaidTravelProgress extends Control

const TRACK_COLOR: Color = Color(0.32, 0.25, 0.20, 1.0)
const TRACK_FILL: Color = Color(0.72, 0.28, 0.20, 1.0)
const STONE_DARK: Color = Color(0.23, 0.18, 0.14, 1.0)
const STONE_LIGHT: Color = Color(0.82, 0.72, 0.52, 1.0)
const STONE_HIGHLIGHT: Color = Color(0.95, 0.86, 0.64, 1.0)
const RAIDER_DARK: Color = Color(0.22, 0.13, 0.12, 1.0)
const RAIDER_CLOTH: Color = Color(0.68, 0.23, 0.16, 1.0)
const RAIDER_SKIN: Color = Color(0.86, 0.63, 0.43, 1.0)

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
	var x: float = center_x - 7.0
	var y: float = center_y - 5.0
	# Small pixel silhouette, drawn here to avoid adding another art dependency.
	draw_rect(Rect2(x, y + 3.0, 14.0, 9.0), STONE_DARK)
	draw_rect(Rect2(x + 1.0, y + 4.0, 12.0, 7.0), STONE_LIGHT)
	draw_rect(Rect2(x, y, 4.0, 6.0), STONE_DARK)
	draw_rect(Rect2(x + 1.0, y + 1.0, 2.0, 4.0), STONE_HIGHLIGHT)
	draw_rect(Rect2(x + 5.0, y + 2.0, 4.0, 3.0), STONE_DARK)
	draw_rect(Rect2(x + 6.0, y + 3.0, 2.0, 2.0), STONE_HIGHLIGHT)
	draw_rect(Rect2(x + 10.0, y, 4.0, 6.0), STONE_DARK)
	draw_rect(Rect2(x + 11.0, y + 1.0, 2.0, 4.0), STONE_HIGHLIGHT)
	draw_rect(Rect2(x + 6.0, y + 7.0, 2.0, 4.0), STONE_DARK)

func _draw_raider(center_x: float, center_y: float) -> void:
	draw_rect(Rect2(center_x - 3.0, center_y - 6.0, 6.0, 4.0), RAIDER_DARK)
	draw_rect(Rect2(center_x - 2.0, center_y - 5.0, 4.0, 2.0), RAIDER_CLOTH)
	draw_rect(Rect2(center_x - 2.0, center_y - 2.0, 4.0, 3.0), RAIDER_SKIN)
	draw_rect(Rect2(center_x - 4.0, center_y + 1.0, 8.0, 5.0), RAIDER_DARK)
	draw_rect(Rect2(center_x - 3.0, center_y + 2.0, 6.0, 3.0), RAIDER_CLOTH)
	draw_rect(Rect2(center_x - 3.0, center_y + 6.0, 2.0, 2.0), RAIDER_DARK)
	draw_rect(Rect2(center_x + 1.0, center_y + 6.0, 2.0, 2.0), RAIDER_DARK)
