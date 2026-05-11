class_name JobData extends Resource

@export var job_id: String = ""
@export var display_name: String = ""
@export var inputs: Dictionary[String, int] = {}
@export var outputs: Dictionary[String, int] = {}
@export var required_tool_id: String = "" # Kosong jika tidak ada standard
@export var base_duration_minutes: int = 0
@export var tool_durability_loss: int = 0
@export var waste_rate: float = 0.1
@export var min_trust: float = 0
@export var min_satisfaction: float = 0
@export var requirement_profession: WorkerData.Profession = WorkerData.Profession.LABORER

var allowed_roles: Array[String] = []
