extends Node

## Listen to the existing walk cycle; never drive the actor or its animation.
const DUST = preload("res://scenes/worker_visual/footstep_dust.gd")
const STEP_FRAME: int = 2
const MIN_STEP_DISTANCE: float = 3.0
const MAX_STEP_DISTANCE: float = 32.0
const FEET_OFFSET := Vector2(0, 16)

var actor: Node2D
var body: AnimatedSprite2D
var walking: bool = false
var direction: String = "right"
var last_step_position: Vector2

func _ready() -> void:
	actor = get_parent() as Node2D
	if actor == null:
		return
	body = actor.get("body_sprite") as AnimatedSprite2D
	if body != null:
		body.frame_changed.connect(_on_body_frame_changed)
	actor.visibility_changed.connect(_on_actor_visibility_changed)

func _on_actor_visibility_changed() -> void:
	# Hidden commutes or reappearing actors do not count as visible footsteps.
	if is_instance_valid(actor):
		last_step_position = actor.global_position

func set_walking(value: bool, facing: String) -> void:
	if value and not walking and is_instance_valid(actor):
		last_step_position = actor.global_position
	walking = value
	direction = facing

func _on_body_frame_changed() -> void:
	if not walking or not is_instance_valid(actor) or not actor.is_visible_in_tree():
		return
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return
	if body.frame != STEP_FRAME or not str(body.animation).contains("_walk_"):
		return
	var position: Vector2 = actor.global_position
	var distance: float = position.distance_to(last_step_position)
	if distance < MIN_STEP_DISTANCE:
		return
	# A scene handoff or time skip can move the actor without a visible step.
	if distance > MAX_STEP_DISTANCE:
		last_step_position = position
		return
	var world: Node2D = actor.get_parent() as Node2D
	if world == null:
		return
	var dust: Node2D = DUST.new()
	world.add_child(dust)
	dust.global_position = position + FEET_OFFSET + Vector2(4 if direction == "left" else -4, -1)
	dust.z_index = 0
	dust.scale = Vector2(0.6, 0.6)
	dust.modulate.a = 0.8
	last_step_position = position
