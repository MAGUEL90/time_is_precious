extends NPCBase

func _ready() -> void:
	satisfaction_param = 0.3
	npc_name = get_tree().get_first_node_in_group("npcs").name
		
	print("satisfaction ", npc_name, " is ", self.satisfaction_param)
	super._ready()
