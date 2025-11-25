extends NodeState

@export var npc_reff: NPCBase
@export var animated_sprite_2d: AnimatedSprite2D

var speed: float = 100.0

func _ready() -> void:
	pass

func _on_physics_process(_delta: float) -> void: 
	npc_reff.move_and_slide()

func _on_next_transition() -> void:
	pass

func _on_enter() -> void:
	pass

func _on_exit() -> void:
	animated_sprite_2d.stop()
