extends NodeState

@export var player_reff: Player
@onready var player_visual: PlayerVisual = $"../../PlayerVisual"

@export var speed: float = 50.0

func _on_physics_process(_delta: float) -> void:
	if not player_reff.can_move:
		player_reff.velocity = Vector2.ZERO
		player_reff.move_and_slide()
		return

	var direction = GameInputEvents.movement_input()

	if direction == Vector2.LEFT:
		player_visual.play_visual("walk", "left")
		player_reff.player_sprite_direction = direction
	elif direction == Vector2.RIGHT:
		player_visual.play_visual("walk", "right")
		player_reff.player_sprite_direction = direction
	elif direction == Vector2.UP:
		if player_reff.player_sprite_direction == Vector2.RIGHT:
			player_visual.play_visual("walk", "right")
		elif player_reff.player_sprite_direction == Vector2.LEFT:
			player_visual.play_visual("walk", "left")
	elif direction == Vector2.DOWN:
		if player_reff.player_sprite_direction == Vector2.RIGHT:
			player_visual.play_visual("walk", "right")
		elif player_reff.player_sprite_direction == Vector2.LEFT:
			player_visual.play_visual("walk", "left")

	player_reff.velocity = direction * player_reff.speed
	player_reff.move_and_slide()

func _on_next_transition() -> void:
	if not player_reff.can_move:
		transition.emit("playeridlestate")
		return

	GameInputEvents.movement_input()

	if not GameInputEvents.is_move():
		transition.emit("playeridlestate")
