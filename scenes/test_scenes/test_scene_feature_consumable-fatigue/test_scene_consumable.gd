extends Node2D

# Test shortcuts

func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.is_pressed()
		and not event.is_echo()
		and event.keycode == KEY_T
	):
		var player: Player = get_tree().get_first_node_in_group("player")

		if player != null:
			print("Sleep success: ", player.sleep())
