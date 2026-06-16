extends NodeState

@export var npc_reff: NPCBase
@export var min_speed: float = 5
@export var max_speed: float = 15
@export var character_visual: BaseCharacterVisual
@export var animated_sprite_2d: AnimatedSprite2D

var speed: float

func _ready() -> void:
	call_deferred("character_setup")

func _on_physics_process(_delta: float) -> void:

	if npc_reff.navigation_agent_2d.is_navigation_finished():
		set_movement_target()
		npc_reff.can_walk = false
		npc_reff.walk_cycle_duration.start()
		return

	var next_position: Vector2 = npc_reff.navigation_agent_2d.get_next_path_position()
	var target_direction: Vector2 = npc_reff.global_position.direction_to(next_position)
	var visual_direction := "left" if target_direction.x < 0 else "right"
	_play_walk(visual_direction)

	if npc_reff.can_walk == true:
		npc_reff.walk_cycle_duration.stop()
		npc_reff.velocity = target_direction * speed
		npc_reff.move_and_slide()

func _on_next_transition() -> void:
	if npc_reff.can_walk == false:
		transition.emit("npcidlestate")

func _on_enter() -> void:
	_play_walk("right")

func _on_exit() -> void:
	if character_visual == null and animated_sprite_2d != null:
		animated_sprite_2d.stop()

func character_setup() -> void:
	await get_tree().physics_frame
	set_movement_target()

func set_movement_target() -> void:
	var target_position: Vector2 = NavigationServer2D.map_get_random_point(npc_reff.navigation_agent_2d.get_navigation_map(), npc_reff.navigation_agent_2d.navigation_layers, false)
	npc_reff.navigation_agent_2d.target_position = target_position
	speed = randf_range(min_speed, max_speed)

func _play_walk(direction: String) -> void:
	if character_visual != null:
		character_visual.play_visual("walk", direction)
		return

	if animated_sprite_2d == null:
		return

	animated_sprite_2d.flip_h = direction == "left"
	if animated_sprite_2d.animation != &"walk" or not animated_sprite_2d.is_playing():
		animated_sprite_2d.play("walk")
