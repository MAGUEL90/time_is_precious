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
	if npc_reff.can_walk == true:
		transition.emit("npcwalkstate")
	#elif npc_reff.is_contract_activated == true:
		#transition.emit("npcworkingstate")

func _on_enter() -> void:
	animated_sprite_2d.play("idle")

func _on_exit() -> void:
	animated_sprite_2d.stop()
