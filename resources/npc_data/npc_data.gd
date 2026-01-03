class_name NPCData extends Resource

# CHATGPT MENEMUKAN NPCDATA DALAM TEMPURUNG

@export var npc_name: String
@export var role: String
@export var id: String
@export var unique_dialogue : DialogueResource

# ============= PARAM
@export var min_limit_satisfaction: float = 0.0
@export var max_limit_satisfaction: float = 1.0
@export var initial_satisfaction: float

# ============= CONTRACT
@export var base_wage: float
@export var work_duration_day: int
@export var contract_difficult: float
@export var contract_list: Array[String] = ["collecting", "searching", "gardening"]
@export var allow_contract: bool = false

var needs: Dictionary = {
	"food": {"grade_A": 0.0, "grade_B": 0.0, "grade_C": 0.0, "grade_D": 0.0},
	"clothes": {"clothes": 0.0, "sandals": 0.0, "pants": 0.0, "accesories": 0.0},
	"house": {"hut": 0.0, "house": 0.0, "mansion": 0.0, "elite_mansion": 0.0},
	"shekel": {"bronze": 0.0, "silver": 0.0, "gold": 0.0},
}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.
