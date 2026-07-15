class_name NightmareWorld extends Node2D

signal timeout_reached
signal nightmare_active_changed(active: bool)
signal nightmare_completed(
	base_minutes: int,
	extra_minutes: int,
	total_minutes: int
)

@export var base_duration_seconds: float = 60.0
@export var duration_increase_per_tier: float = 30.0
@export var world_minutes_per_second: float = 1.0
@export var scoreboard_duration: float = 4.0
@export var extra_penalty_per_tier: float = 0.25
@export var base_vision_radius: float = 96.0
@export var vision_reduction_per_tier: float = 12.0
@export var minimum_vision_radius: float = 48.0
@export_range(0.0, 2.0, 0.05) var timeout_penalty_rate: float = 0.50

@onready var spawn_point: Marker2D = $WorldObjects/SpawnPoint
@onready var exit_npc: Area2D = $WorldObjects/ExitNPC
@onready var timer_label: Label = $NightmareUI/TimerLabel
@onready var nightmare_ui: CanvasLayer = $NightmareUI
@onready var vision_overlay: ColorRect = $NightmareUI/VisionOverlay

var player_ref: Player = null
var return_position: Vector2
var collapse_tier: int = 1
var elapsed_seconds: float = 0.0
var max_duration_seconds: float = 60.0
var is_active: bool = false
var previous_time_paused: bool = false

# Lifecycle and timer

func _ready() -> void:
	nightmare_ui.visible = false
	set_process(false)
	exit_npc.body_entered.connect(_on_exit_npc_body_entered)

func _process(delta: float) -> void:
	if not is_active:
		return

	elapsed_seconds = minf(
		elapsed_seconds + delta,
		max_duration_seconds
	)

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
	collapse_tier = maxi(tier, 1)
	_update_vision_radius()
	elapsed_seconds = 0.0
	max_duration_seconds = (
		base_duration_seconds
		+ duration_increase_per_tier * float(collapse_tier - 1)
	)

	previous_time_paused = TimeComponentManager.is_paused
	TimeComponentManager.is_paused = true

	player.global_position = spawn_point.global_position

	is_active = true
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

# Nightmare completion and consequences

func _on_exit_npc_body_entered(body: Node2D) -> void:
	if is_active and body == player_ref:
		finish_nightmare(false)

func finish_nightmare(time_out: bool) -> void:
	if not is_active:
		return

	is_active = false
	set_process(false)

	var base_minutes: int = maxi(
		ceili(elapsed_seconds * world_minutes_per_second),
		1
	)
	var tier_penalty: int = ceili(
		float(base_minutes)
		* extra_penalty_per_tier
		* float(collapse_tier - 1)
	)
	var timeout_penalty: int = 0

	if time_out:
		timeout_penalty = ceili(
			float(base_minutes) * timeout_penalty_rate
		)

	var extra_minutes: int = tier_penalty + timeout_penalty
	var total_minutes: int = base_minutes + extra_minutes
	var result: String = "TIME EXPIRED" if time_out else "ESCAPED"

	var scoreboard: String = (
		"NIGHTMARE ENDED\n\n"
		+ "Result: %s\n" % result
		+ "Time spent: %.1f seconds\n" % elapsed_seconds
		+ "Base time: %d minutes\n" % base_minutes
		+ "Tier penalty: +%d minutes\n" % tier_penalty
		+ "Additional penalty: +%d minutes\n" % extra_minutes
		+ "Total world time: %d minutes" % total_minutes
	)

	var previous_can_move: bool = player_ref.can_move
	player_ref.can_move = false

	await SceneTransition.run_with_fade(
		Callable(self, "_return_to_world").bind(total_minutes),
		0.35,
		scoreboard_duration,
		scoreboard
	)

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
	TimeComponentManager.is_paused = previous_time_paused
	nightmare_active_changed.emit(false)
	return true

# Vision presentation

func _update_vision_radius() -> void:
	var radius: float = maxf(
		base_vision_radius
		- vision_reduction_per_tier * float(collapse_tier - 1),
		minimum_vision_radius
	)

	var shader_material := vision_overlay.material as ShaderMaterial

	if shader_material != null:
		shader_material.set_shader_parameter(
			"radius_pixels",
			radius
		)
