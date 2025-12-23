class_name NPCData extends Resource

@export var unique_dialogue : DialogueResource

@export var name: String #
var current_position: Vector2 # Simpan Posisi Terkini
var last_position: Vector2 # Simpan Posisi Terakhir

# ============= PARAM
var min_limit_satisfaction: float = 0.0
var max_limit_satisfaction: float = 1.0
var initial_satisfaction: float
@export var current_satisfaction: float

# ============= CONTRACT
var work_duration_day: int
var contract_difficult: float
var contract_list: Array[String] = ["collecting", "searching", "gardening"]
var allow_contract: bool = false

var needs: Dictionary = {
	"food": {"grade_A": 0.0, "grade_B": 0.0, "grade_C": 0.0, "grade_D": 0.0},
	"clothes": {"clothes": 0.0, "sandals": 0.0, "pants": 0.0, "accesories": 0.0},
	"house": {"hut": 0.0, "house": 0.0, "mansion": 0.0, "elite_mansion": 0.0},
	"shekel": {"bronze": 0.0, "silver": 0.0, "gold": 0.0},
}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.
