class_name GameInputEvents extends Node

static var direction: Vector2

static func movement_input() -> Vector2:
	
	if Input.is_action_pressed("move_left"):
		direction = Vector2.LEFT
	elif Input.is_action_pressed("move_right"):
		direction = Vector2.RIGHT
	elif Input.is_action_pressed("move_up"):
		direction = Vector2.UP
	elif Input.is_action_pressed("move_down"):
		direction = Vector2.DOWN
	else:
		direction = Vector2.ZERO
		
	return direction

static func is_move() -> bool:
	return true if direction != Vector2.ZERO else false
