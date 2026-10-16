extends Resource

## Recording preparation only. Rates, stock, wages and assignment rules stay authored.
@export var site_name: StringName = &"ClaySiteA"
@export var focus_site_only: bool = true
@export_range(0, 23) var start_hour: int = 14
@export_range(0.0, 1.0) var initial_fatigue: float = 0.1
@export var personal_shekel: int = 20
@export var personal_food: int = 4
@export var food_item: String = "roasted_drumstick"
@export var camera_offset: Vector2 = Vector2(24, -4)
@export var camera_zoom: float = 2.0
@export_range(1, 3) var preview_scale: int = 2
@export_enum("x1:1", "x10:10", "x60:60") var recording_speed: int = 10
@export var visual_seed: int = 117
