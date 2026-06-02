extends NodeState

@export var player_reff: Player
@onready var player_visual: PlayerVisual = $"../../PlayerVisual"
	
func _on_next_transition() -> void:
	GameInputEvents.movement_input()
	
	if GameInputEvents.is_move():
		transition.emit("playermovementstate")

func _on_enter() -> void:
	if player_reff.player_sprite_direction == Vector2.LEFT:
		player_visual.play_visual("idle", "left")
	elif player_reff.player_sprite_direction == Vector2.RIGHT:
		player_visual.play_visual("idle", "right")
