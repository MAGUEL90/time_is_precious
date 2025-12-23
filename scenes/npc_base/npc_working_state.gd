extends NodeState

@export var npc_reff: NPCBase
@export var animated_sprite_2d: AnimatedSprite2D
@export var current_time: int
@export var working_day: int


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func on_contract_activated() -> void:
	pass

func _on_next_transition() -> void:
	pass

func _on_enter() -> void:
	if npc_reff.is_contract_activated:
		print("on working state")

func _on_exit() -> void:
	pass
