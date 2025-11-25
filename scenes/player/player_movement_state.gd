extends NodeState

@export var player_reff: Player
@export var animated_sprite_2d: AnimatedSprite2D
@export var speed: float = 50.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _on_physics_process(_delta: float) -> void:
	
	var direction = GameInputEvents.movement_input()
	
	if direction == Vector2.LEFT:
		animated_sprite_2d.play("move_left")
		player_reff.player_sprite_direction = direction
	elif direction == Vector2.RIGHT:
		animated_sprite_2d.play("move_right")
		player_reff.player_sprite_direction = direction
	elif direction == Vector2.UP:
		if player_reff.player_sprite_direction == Vector2.RIGHT:
			animated_sprite_2d.play("move_right")
		elif player_reff.player_sprite_direction == Vector2.LEFT:
			animated_sprite_2d.play("move_left")
	elif direction == Vector2.DOWN:
		if player_reff.player_sprite_direction == Vector2.RIGHT:
			animated_sprite_2d.play("move_right")
		elif player_reff.player_sprite_direction == Vector2.LEFT:
			animated_sprite_2d.play("move_left")
	
	player_reff.velocity = direction * speed
	player_reff.move_and_slide()
	

func _on_next_transition() -> void:
	GameInputEvents.movement_input()
	
	if not GameInputEvents.is_move():
		transition.emit("playeridlestate")

func _on_enter() -> void:
	pass

func _on_exit() -> void:
	animated_sprite_2d.stop()
