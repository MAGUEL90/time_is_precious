class_name WorkerData
extends Resource

enum PopulationStatus {MIGRANT, RESIDENT, REJECTED, LEFT_CITY}
enum EmploymentStatus {UNEMPLOYED, APPLICANT, HIRED, ASSIGNED}
enum Profession {LABORER, CRAFTER, HAULER, FARMER, SCAVENGER}
enum WorkStatus {IDLE, WORKING}

@export var worker_id: String = ""
@export var display_name: String = ""
@export var profession: Profession = Profession.LABORER
@export var profession_xp: int = 0
@export var current_order_id: String = ""
@export var current_job_id: String = ""
@export var current_work_status: WorkStatus = WorkStatus.IDLE
@export var population_status: PopulationStatus = PopulationStatus.MIGRANT
@export var employment_status: EmploymentStatus = EmploymentStatus.UNEMPLOYED
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

func can_be_hired() -> bool:
	if population_status == PopulationStatus.RESIDENT and employment_status == EmploymentStatus.APPLICANT:
		return true

	return false

func hire_applicant() -> bool:
	if not can_be_hired():
		return false

	employment_status = EmploymentStatus.HIRED
	return true
