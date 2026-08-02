class_name WorkerData
extends Resource

enum Profession {NONE, LABORER, CRAFTER, HAULER, FARMER, SCAVENGER}
enum WorkStatus {IDLE, WORKING}

@export var worker_id: String = ""
@export var display_name: String = ""
@export var profession: Profession = Profession.LABORER
@export var profession_xp: int = 0
@export var current_order_id: String = ""
@export var current_job_id: String = ""
@export var current_work_status: WorkStatus = WorkStatus.IDLE
@export_range(1, 3) var profession_star: int = 1
@export_range(0.0, 2.0, 0.01) var efficiency: float = 1.0
@export_range(0.0, 1.0, 0.01) var reliability: float = 1.0
@export var wage_shekel_per_day: int = 0
@export var food_fulfilled: bool = false
@export var clothing_fulfilled: bool = false
@export var shelter_fulfilled: bool = false
@export_range(0.0, 1.0, 0.01) var satisfaction: float = 0.5

# Citizen linking and shared-state resolution

func get_linked_citizen() -> CitizenData:
	var clean_worker_id: String = worker_id.strip_edges()

	if clean_worker_id.is_empty():
		return null

	return CitizenManager.get_citizen(clean_worker_id)

func has_linked_citizen() -> bool:
	return get_linked_citizen() != null

func get_resolved_display_name() -> String:
	var citizen_data: CitizenData = get_linked_citizen()

	if citizen_data != null:
		return citizen_data.display_name

	return display_name

# Needs and performance

func are_basic_needs_fulfilled() -> bool:
	var citizen_data: CitizenData = get_linked_citizen()

	if citizen_data != null:
		return citizen_data.are_basic_needs_fulfilled()

	return food_fulfilled and clothing_fulfilled and shelter_fulfilled

func get_resolved_satisfaction() -> float:
	var citizen_data: CitizenData = get_linked_citizen()

	if citizen_data != null:
		return citizen_data.satisfaction

	return satisfaction

func get_resolved_reliability() -> float:
	var citizen_data: CitizenData = get_linked_citizen()

	if citizen_data != null:
		return citizen_data.reliability

	return reliability

func get_satisfaction_work_multiplier() -> float:
	var resolved_satisfaction: float = get_resolved_satisfaction()

	if resolved_satisfaction >= 0.75:
		return 1.05
	elif resolved_satisfaction >= 0.4:
		return 1.0
	else:
		return 0.85

func get_reliability_success_chance() -> float:
	var resolved_reliability: float = get_resolved_reliability()

	if resolved_reliability >= 0.75:
		return 0.95
	elif resolved_reliability >= 0.4:
		return 0.85
	else:
		return 0.65

# Work lifecycle

func is_working() -> bool:
	return current_work_status == WorkStatus.WORKING

func start_work(order_id: String, job_id: String) -> void:
	current_order_id = order_id
	current_job_id = job_id
	current_work_status = WorkStatus.WORKING

func finish_work(order_id: String) -> void:
	if order_id != current_order_id:
		return

	current_job_id = ""
	current_order_id = ""
	current_work_status = WorkStatus.IDLE
