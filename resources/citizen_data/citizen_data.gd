class_name CitizenData extends Resource

enum CitizenStatus {NONE, CITIZEN, APPLICANT, WORKER}

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

@export var status: CitizenStatus = CitizenStatus.CITIZEN
@export var profession: WorkerData.Profession = WorkerData.Profession.NONE

func are_basic_needs_fulfilled() -> bool:
	return food_fulfilled and clothing_fulfilled and shelter_fulfilled
