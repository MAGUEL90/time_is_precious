extends NPCBase

func _ready() -> void:
	npc_name = get_node(".").name.to_lower()
	super._ready()
	
