extends NodeState

enum STATE {
	IDLE,
	WORKING,
	RETURN
}

func _ready() -> void:
	pass # Replace with function body.

func _on_process(_delta: float) -> void:
	pass

func _on_physics_process(_delta: float) -> void:
	pass

func _on_next_transition() -> void:
	pass

func _on_enter() -> void:
	pass

func _on_exit() -> void:
	pass

func do_quest() -> void:
	print("do something")
