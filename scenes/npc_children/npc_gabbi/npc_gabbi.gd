class_name Gabbi extends NPCBase

func _ready() -> void:
	satisfaction_param = 0.5
	
	print(get_parent().name)
	
	print("satisfaction ", npc_name, " is ", self.satisfaction_param)
	super._ready()
