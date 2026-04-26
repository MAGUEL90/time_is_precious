class_name WorkerData
extends Resource

enum Profession {LABORER, CRAFTER, HAULER, FARMER, SCAVENGER}

@export var worker_id: String = ""
@export var display_name: String = ""
@export var profession: Profession = Profession.LABORER
@export var profession_xp: int = 0
@export_range(1, 3) var profession_star: int = 1
@export_range(0.0, 2.0, 0.01) var efficiency: float = 1.0
@export_range(0.0, 2.0, 0.01) var reliability: float = 1.0
@export var wage_shekel_per_day: int = 0
@export var food_fulfilled: bool = false
@export var clothing_fulfilled: bool = false
@export var shelter_fulfilled: bool = false

func are_basic_needs_fulfilled() -> bool:
	return food_fulfilled and clothing_fulfilled and shelter_fulfilled
