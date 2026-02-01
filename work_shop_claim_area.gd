extends Area2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

func _on_body_entered(body: Node2D) -> void:
	# Cara paling aman: masukkan Player ke group "player"
	if body != null and body.is_in_group("player"):
		if has_node("/root/WorkShopStorage"):
			var workshop_storage: Node = get_node("/root/WorkShopStorage")
			if workshop_storage.has_method("set_player_in_claim_area"):
				workshop_storage.call("set_player_in_claim_area", true)


func _on_body_exited(body: Node2D) -> void:
	if body != null and body.is_in_group("player"):
		if has_node("/root/WorkShopStorage"):
			var workshop_storage: Node = get_node("/root/WorkShopStorage")
			if workshop_storage.has_method("set_player_in_claim_area"):
				workshop_storage.call("set_player_in_claim_area", false)
