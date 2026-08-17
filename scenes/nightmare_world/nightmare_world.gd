class_name NightmareWorld extends Node2D

const TIMER_NORMAL_COLOR: Color = Color(0.3686, 0.2745, 0.1882, 1.0)
const TIMER_CRITICAL_COLOR: Color = Color(0.8, 0.15, 0.1, 1.0)
const MAX_NIGHTMARE_LEVEL: int = 5
const NIGHTMARE_TIME_MULTIPLIER: Array[float] = [
	1.0,
	1.2,
	1.6,
	1.8,
	2.0
]

signal timeout_reached
signal nightmare_active_changed(active: bool)
signal nightmare_completed(
	base_minutes: int,
	extra_minutes: int,
	total_minutes: int
)

@export var base_duration_seconds: float = 60.0
@export var world_minutes_per_second: float = 1.0
@export var scoreboard_duration: float = 4.0
@export var base_vision_radius: float = 96.0
@export var minimum_vision_radius: float = 48.0
@export var vision_shrink_start_seconds: float = 20.0
@export var minimum_vision_at_seconds: float = 10.0
@export_range(0.0, 2.0, 0.05) var timeout_penalty_rate: float = 0.50
@export_range(1, 60, 1) var timer_warning_seconds: int = 10

@export_group("Larva Animation")
@export_range(0.1, 10.0, 0.1) var larva_min_delay: float
@export_range(0.1, 10.0, 0.1) var larva_max_delay: float

@onready var spawn_point: Marker2D = $WorldObjects/SpawnPoint
@onready var exit_npc: Area2D = $WorldObjects/ExitNPC
@onready var timer_label: Label = $NightmareUI/TimerLabel
@onready var nightmare_ui: CanvasLayer = $NightmareUI
@onready var vision_overlay: ColorRect = $NightmareUI/VisionOverlay
@onready var larva_timer: Timer = $LarvaTimer
@onready var larvae: Array[AnimatedSprite2D] = [
	$Larva,
	$Larva2,
	$Larva3,
	$Larva4
]

var player_ref: Player = null
var return_position: Vector2
var collapse_tier: int = 1
var elapsed_seconds: float = 0.0
var max_duration_seconds: float = 60.0
var is_active: bool = false
var previous_time_paused: bool = false
var last_larva_index: int = -1

# Lifecycle and timer

func _ready() -> void:
	nightmare_ui.visible = false
	set_process(false)
	exit_npc.body_entered.connect(_on_exit_npc_body_entered)
	larva_timer.timeout.connect(_on_larva_timer_timeout)

	for larva in larvae:
		larva.stop()
		larva.hide()
		larva.animation_finished.connect(
			_on_larva_animation_finished.bind(larva)
		)

func _process(delta: float) -> void:
	if not is_active:
		return

	elapsed_seconds = minf(
		elapsed_seconds + delta,
		max_duration_seconds
	)

	_update_vision_radius()
	_update_timer_label()

	if elapsed_seconds >= max_duration_seconds:
		timeout_reached.emit()
		finish_nightmare(true)

# Nightmare entry

func start_nightmare(player: Player, tier: int) -> bool:
	if is_active or not is_instance_valid(player):
		return false

	player_ref = player
	return_position = player.global_position
	collapse_tier = clampi(
		tier,
		1,
		MAX_NIGHTMARE_LEVEL
	)
	elapsed_seconds = 0.0
	max_duration_seconds = base_duration_seconds
	_update_vision_radius()

	previous_time_paused = TimeComponentManager.is_paused
	TimeComponentManager.is_paused = true

	player.global_position = spawn_point.global_position

	is_active = true
	_schedule_next_larva()
	nightmare_active_changed.emit(true)
	nightmare_ui.show()
	_update_timer_label()
	set_process(true)
	return true

func _update_timer_label() -> void:
	var remaining: int = ceili(
		max_duration_seconds - elapsed_seconds
	)
	var minutes: int = int(float(remaining) / 60.0)
	var seconds: int = remaining % 60

	timer_label.text = "NIGHTMARE %d\n%02d:%02d" % [
		collapse_tier,
		minutes,
		seconds
	]

	if remaining <= timer_warning_seconds:
		timer_label.add_theme_color_override(
			"font_color",
			TIMER_CRITICAL_COLOR
		)
	else:
		timer_label.add_theme_color_override(
			"font_color",
			TIMER_NORMAL_COLOR
		)

# Nightmare completion and consequences

func _on_exit_npc_body_entered(body: Node2D) -> void:
	if is_active and body == player_ref:
		finish_nightmare(false)

func finish_nightmare(time_out: bool) -> void:
	if not is_active:
		return

	is_active = false
	_stop_larva_cycle()
	set_process(false)

	var base_minutes: int = maxi(
		ceili(elapsed_seconds * world_minutes_per_second),
		1
	)

	var level_multiplier: float = NIGHTMARE_TIME_MULTIPLIER[
		collapse_tier - 1
	]

	var multiplied_minutes: int = ceili(
		float(base_minutes) * level_multiplier
	)

	var tier_penalty: int = maxi(
		multiplied_minutes - base_minutes,
		0
	)

	var timeout_penalty: int = 0

	if time_out:
		timeout_penalty = ceili(
			float(base_minutes) * timeout_penalty_rate
		)

	var extra_minutes: int = tier_penalty + timeout_penalty
	var total_minutes: int = multiplied_minutes + timeout_penalty
	var result: String = "TIME EXPIRED" if time_out else "ESCAPED"

	var scoreboard: String = (
		"NIGHTMARE ENDED\n"
		+ "Result: %s\n" % result
		+ "Time spent: %.1f sec\n" % elapsed_seconds
		+ "Base time: %d min\n" % base_minutes
		+ "Level penalty (x%.1f): +%d min\n" % [
			level_multiplier,
			tier_penalty
		]
		+ "Timeout penalty: +%d min\n" % timeout_penalty
		+ "Total world time: %d min" % total_minutes
	)

	var previous_can_move: bool = player_ref.can_move
	player_ref.can_move = false

	await SceneTransition.run_with_fade(
		Callable(self, "_return_to_world").bind(total_minutes),
		0.35,
		scoreboard_duration,
		scoreboard,
		true
	)

	TimeComponentManager.is_paused = previous_time_paused
	nightmare_active_changed.emit(false)

	player_ref.can_move = previous_can_move
	nightmare_completed.emit(
		base_minutes,
		extra_minutes,
		total_minutes
	)

func _return_to_world(total_minutes: int) -> bool:
	nightmare_ui.hide()
	player_ref.global_position = return_position
	player_ref.apply_nightmare_consequences(total_minutes)

	return true

# Vision presentation

func _update_vision_radius() -> void:
	var remaining_seconds: float = maxf(
		max_duration_seconds - elapsed_seconds,
		0.0
	)
	var shrink_duration: float = maxf(
		vision_shrink_start_seconds - minimum_vision_at_seconds,
		1.0
	)

	var shrink_progress: float = clampf(
		(
			vision_shrink_start_seconds
			- remaining_seconds
		) / shrink_duration,
		0.0,
		1.0
	)

	var radius: float = lerpf(
		base_vision_radius,
		minimum_vision_radius,
		shrink_progress
	)

	var shader_material := vision_overlay.material as ShaderMaterial

	if shader_material != null:
		shader_material.set_shader_parameter(
			"radius_pixels",
			radius
		)


func _schedule_next_larva() -> void:
	if not is_active:
		return

	var minimum_delay: float = minf(larva_min_delay, larva_max_delay)
	var maximum_delay: float = maxf(larva_min_delay, larva_max_delay)

	larva_timer.start(randf_range(minimum_delay, maximum_delay))

func _on_larva_timer_timeout() -> void:
	if not is_active:
		return

	var choices: Array[int] = []

	for index in range(larvae.size()):
		if larvae.size() == 1 or index != last_larva_index:
			choices.append(index)

	var selected_index: int = choices.pick_random()
	var selected_larva: AnimatedSprite2D = larvae[selected_index]

	last_larva_index = selected_index
	selected_larva.frame = 0
	selected_larva.show()
	selected_larva.play(&"default")

func _on_larva_animation_finished(
	larva: AnimatedSprite2D
) -> void:
	larva.stop()
	larva.hide()

	if is_active:
		_schedule_next_larva()

func _stop_larva_cycle() -> void:
	larva_timer.stop()

	for larva in larvae:
		larva.stop()
		larva.hide()
