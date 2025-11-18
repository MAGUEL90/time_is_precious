extends NodeState

@export var player_reff: BaseCharacter
@export var animated_sprite_2d: AnimatedSprite2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	GameInputEvents.movement_input()
	
	if not GameInputEvents.is_move():
		if player_reff.base_sprite_direction == Vector2.LEFT:
			animated_sprite_2d.play("idle_left")
		elif player_reff.base_sprite_direction == Vector2.RIGHT:
			animated_sprite_2d.play("idle_right")
	
func _on_next_transition() -> void:
	GameInputEvents.movement_input()
	
	if GameInputEvents.is_move():
		transition.emit("movementstate")

func _on_enter() -> void:
	pass

func _on_exit() -> void:
	animated_sprite_2d.stop()
