class_name CitizenActor extends Node2D

enum MovementMode {
	STATIC,
	WANDER,
	COMMANDED
}

@onready var base_worker_visual: Node2D = $BaseWorkerVisual
@onready var navigation_agent_2d: NavigationAgent2D = $NavigationAgent2D

@export_category("Citizen Visual")

@export_enum("dark", "light", "tan", "warm")
var skin_tone: String = "light"
@export var expression: String = "base"
@export_enum("default", "clay_worn_wrap", "plain_worn_wrap")
var clothes_id: String = "clay_worn_wrap"
@export_enum(
	"default",
	"grey_female_01", "grey_female_02", "grey_female_03",
	"grey_male_01", "grey_male_02", "grey_male_03",
	"red_female_01", "red_female_02", "red_female_03",
	"red_male_01", "red_male_02", "red_male_03",
	"black_female_01", "black_female_02", "black_female_03",
	"black_male_01", "black_male_02", "black_male_03",
	"brown_female_01", "brown_female_02", "brown_female_03",
	"brown_male_01", "brown_male_02", "brown_male_03"
)
var hair_style: String = "grey_male_01"
@export_enum("default", "farmer_hat")
var accessory: String = "default"
@export_enum("left", "right")
var initial_direction: String = "right"

@export_category("Movement")
@export var movement_mode: MovementMode = MovementMode.WANDER

@export_category("Movement Settings")
@export_range(1.0, 40.0, 0.5)
var move_speed: float = 10.0

@export_range(0.2, 10.0, 0.1)
var min_idle_duration: float = 0.7

@export_range(0.2, 10.0, 0.1)
var max_idle_duration: float = 1.8

var citizen_data: CitizenData

var _precise_position: Vector2
var _idle_time_left: float = 0.0
var _is_walking: bool = false
var _last_visual_direction: String = "right"
var _initialized: bool = false
var _navigation_ready: bool = false

# Lifecycle

func _ready() -> void:
	call_deferred("_initialize_actor")


func _initialize_actor() -> void:
	if _initialized:
		return

	_initialized = true
	_last_visual_direction = initial_direction
	_precise_position = global_position
	_play_visual("idle")

	if movement_mode == MovementMode.STATIC:
		return

	# Menunggu NavigationServer menyinkronkan region.
	await get_tree().physics_frame
	_navigation_ready = true

	if movement_mode == MovementMode.WANDER:
		_start_idle_phase()


func _physics_process(delta: float) -> void:
	if not _initialized or not _navigation_ready:
		return

	if movement_mode != MovementMode.WANDER:
		return

	_process_wander(delta)


# Citizen Setup

func setup(data: CitizenData) -> void:
	if data == null:
		return

	citizen_data = data
	var citizen_profile: VisualProfile = citizen_data.visual_profile

	if citizen_profile == null:
		return

	skin_tone = citizen_profile.skin_tone
	expression = citizen_profile.expression
	accessory = citizen_profile.accessory
	clothes_id = citizen_profile.clothes_id
	hair_style = citizen_profile.hair_style

	if _initialized:
		_play_visual("idle")


func _setup_manual_citizen() -> void:
	if citizen_data != null:
		return

	_last_visual_direction = initial_direction

	base_worker_visual.apply_profile(
		skin_tone,
		expression,
		accessory,
		clothes_id,
		hair_style
	)


# Wander Movement

func _process_wander(delta: float) -> void:
	if not _is_walking:
		_idle_time_left -= delta

		if _idle_time_left <= 0.0:
			_start_walk_phase()

		return

	if navigation_agent_2d.is_navigation_finished():
		_start_idle_phase()
		return

	_move_along_navigation_path(delta)


func _start_walk_phase() -> void:
	var navigation_map: RID = navigation_agent_2d.get_navigation_map()

	if not navigation_map.is_valid():
		_idle_time_left = 0.5
		return

	var target_position: Vector2 = NavigationServer2D.map_get_random_point(
		navigation_map,
		navigation_agent_2d.navigation_layers,
		false
	)

	navigation_agent_2d.target_position = target_position
	_is_walking = true
	_play_visual("walk")


func _start_idle_phase() -> void:
	_is_walking = false
	_idle_time_left = randf_range(
		min_idle_duration,
		max_idle_duration
	)

	_precise_position = global_position
	_play_visual("idle")


func _move_along_navigation_path(delta: float) -> void:
	var next_path_position: Vector2 = (
		navigation_agent_2d.get_next_path_position()
	)

	var movement_direction: Vector2 = (
		global_position.direction_to(next_path_position)
	)

	if movement_direction.is_zero_approx():
		return

	if _update_visual_direction(movement_direction):
		_play_visual("walk")

	_precise_position += movement_direction * move_speed * delta
	global_position = _precise_position


func _update_visual_direction(movement_direction: Vector2) -> bool:
	# Gerakan yang hampir vertikal mempertahankan arah visual terakhir.
	if absf(movement_direction.x) < 0.05:
		return false

	var new_direction: String = (
		"right" if movement_direction.x > 0.0 else "left"
	)

	if new_direction == _last_visual_direction:
		return false

	_last_visual_direction = new_direction
	return true


# Visual Playback

func _play_visual(action: String) -> void:
	base_worker_visual.play_visual(
		skin_tone,
		expression,
		action,
		_last_visual_direction,
		accessory,
		clothes_id,
		hair_style
	)
