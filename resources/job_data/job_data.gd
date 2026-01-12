class_name JobData extends Resource

var job_id: String = ""
var display_name: String = ""
var inputs: Dictionary[String, int] = {}
var outputs: Dictionary[String, int] = {}
var required_tool_id: String = "" # Kosong jika tidak ada standard

@export var base_duration_minutes: int = 0
@export var tool_durability_loss: int = 0
@export var waste_rate: float = 0.1
@export var min_trust: float = 0
@export var min_satisfaction: float = 0

var allowed_roles: Array[String] = []

# INI HINT, BARIS KE BERAPA AKU
