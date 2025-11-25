extends NodeState

@export var npc_reff: NPCBase
@export var animated_sprite_2d: AnimatedSprite2D

func _ready() -> void:
	pass

func _on_process(_delta: float) -> void:
	pass

func _on_physics_process(_delta: float) -> void:
	pass

func _on_next_transition() -> void:
	pass

func _on_enter() -> void:
	animated_sprite_2d.play("idle_right")

func _on_exit() -> void:
	animated_sprite_2d.stop()
