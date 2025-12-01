class_name Gabbi extends NPCBase

func _ready() -> void:
	npc_name = get_node(".").name.to_lower()
	super._ready()
	
func _process(_delta: float) -> void:
	super._process(_delta)
	
