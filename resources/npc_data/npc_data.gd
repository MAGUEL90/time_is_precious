class_name NPCData extends Resource

@export_category("Attribute")
@export var npc_name: String
@export var npc_class: String
@export var unique_dialouge: DialogueResource

# ============= PARAM
@export var initial_satisfaction: float
@export var current_satisfaction: float

# ============= ROLE
@export var npc_role: String
@export var work_duration_day: int = 3
@export var contract_difficult: float


@export var timer: float = 0.0 

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
