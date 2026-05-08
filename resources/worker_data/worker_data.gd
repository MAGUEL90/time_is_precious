class_name WorkerData
extends Resource

enum Profession {LABORER, CRAFTER, HAULER, FARMER, SCAVENGER}

@export var worker_id: String = ""
@export var display_name: String = ""
@export var profession: Profession = Profession.LABORER
@export var profession_xp: int = 0
@export_range(1, 3) var profession_star: int = 1
@export_range(0.0, 2.0, 0.01) var efficiency: float = 1.0
@export_range(0.0, 1.0, 0.01) var reliability: float = 1.0
@export var wage_shekel_per_day: int = 0
@export var food_fulfilled: bool = false
@export var clothing_fulfilled: bool = false
@export var shelter_fulfilled: bool = false
@export_range(0.0, 1.0, 0.01) var satisfaction: float = 0.5

func are_basic_needs_fulfilled() -> bool:
	return food_fulfilled and clothing_fulfilled and shelter_fulfilled

func get_satisfaction_work_multiplier() -> float:
	if satisfaction >= 0.75:
		return 1.05
	elif satisfaction >= 0.4:
		return 1.0
	else:
		return 0.85

func get_reliability_success_chance() -> float:
	if reliability >= 0.75:
		return 0.95
	elif reliability >= 0.4:
		return 0.85
	else:
		return 0.65
