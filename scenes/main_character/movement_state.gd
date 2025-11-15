extends NodeState

@export var player_reff: BaseCharacter
@export var animated_sprite_2d: AnimatedSprite2D
@export var speed: float = 50.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	GameInputEvents.movement_input()
	
	if player_reff.base_direction == Vector2.LEFT:
		animated_sprite_2d.play("move_left")
	elif player_reff.base_direction == Vector2.RIGHT:
		animated_sprite_2d.play("move_right")
	else:
		player_reff.base_direction = Vector2.ZERO
	
	player_reff.velocity = player_reff.base_direction * speed
	player_reff.move_and_slide()
	

func _on_next_transition() -> void:
	GameInputEvents.movement_input()
	
	if not GameInputEvents.is_move():
		transition.emit("idlestate")

func _on_enter() -> void:
	pass

func _on_exit() -> void:
	animated_sprite_2d.stop()
