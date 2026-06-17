extends NodeState

@export var npc_reff: NPCBase
@export var character_visual: BaseCharacterVisual
@export var animated_sprite_2d: AnimatedSprite2D

func _ready() -> void:
	pass

func _on_process(_delta: float) -> void:
	_face_player()

func _on_physics_process(_delta: float) -> void:
	pass

func _on_next_transition() -> void:
	if npc_reff.allow_random_walk and npc_reff.can_walk:
		transition.emit("npcwalkstate")

func _on_enter() -> void:
	_play_idle(_get_facing_direction())

func _on_exit() -> void:
	if character_visual == null and animated_sprite_2d != null:
		animated_sprite_2d.stop()

func _face_player() -> void:
	if not npc_reff.player_reff:
		return

	_play_idle(_get_facing_direction())

func _get_facing_direction() -> String:
	if not npc_reff.player_reff:
		return "right"

	var x_distance: float = npc_reff.player_reff.global_position.x - npc_reff.global_position.x

	if abs(x_distance) < 1.0:
		return "right"

	var direction: String = "right"

	if x_distance < 0:
		direction = "left"

	return direction

func _play_idle(direction: String) -> void:
	if character_visual != null:
		character_visual.play_visual("idle", direction)
		return

	if animated_sprite_2d == null:
		return

	animated_sprite_2d.flip_h = direction == "left"
	if animated_sprite_2d.animation != &"idle" or not animated_sprite_2d.is_playing():
		animated_sprite_2d.play("idle")
