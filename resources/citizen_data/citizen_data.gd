class_name CitizenData extends Resource

enum PopulationStatus {
	MIGRANT,
	RESIDENT,
	REJECTED,
	LEFT_CITY
}

enum EmploymentStatus {
	UNEMPLOYED,
	APPLICANT,
	HIRED,
	ASSIGNED
}

const MIN_APPLICANT_SATISFACTION: float = 0.5

@export var citizen_id: String = ""
@export var display_name: String = ""
@export var satisfaction: float = 0.5
@export var reliability: float = 1.0
@export var food_fulfilled: bool = false
@export var clothing_fulfilled: bool = false
@export var shelter_fulfilled: bool = false
@export var experience: float = 0.0
@export var visual_profile: VisualProfile
@export var population_status: PopulationStatus = PopulationStatus.MIGRANT
@export var employment_status: EmploymentStatus = EmploymentStatus.UNEMPLOYED
@export var profession: WorkerData.Profession = WorkerData.Profession.NONE

func are_basic_needs_fulfilled() -> bool:
	return food_fulfilled and clothing_fulfilled and shelter_fulfilled

func can_apply_for_work() -> bool:
	return (
		population_status == PopulationStatus.RESIDENT
		and employment_status == EmploymentStatus.UNEMPLOYED
		and satisfaction >= MIN_APPLICANT_SATISFACTION
	)

func can_be_hired() -> bool:
	return (
		population_status == PopulationStatus.RESIDENT
		and employment_status == EmploymentStatus.APPLICANT
		and profession != WorkerData.Profession.NONE
	)
