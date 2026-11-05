extends Node2D

## Initial applicants and one city Cart, retained by the existing runtime stores.
@export var enable_initial_applicant: bool = true
@export var enable_initial_cart: bool = true
const APPLICANT_ID: String = "initial_workshop_laborer"
const HAULER_APPLICANT_ID: String = "initial_worksite_hauler"
const LABORER_NAME: String = "Naram"
const HAULER_NAME: String = "Lugal"
const CITY_HAULER_APPLICANT_ID: String = "initial_city_storage_hauler"
const CITY_HAULER_NAME: String = "Belum"
const CART_UNIT_ID: String = "initial_worksite_cart"
const CART_SUPPLIED_META: StringName = &"initial_worksite_cart_supplied"
# Temporary starter balance: the first missed day leaves the two authored
# residents at the existing 0.50 hiring threshold, through the first merchant
# visit. Further unmet days still make them ineligible and reduce satisfaction.
const INITIAL_APPLICANT_SATISFACTION: float = 0.55

func _ready() -> void:
	if not enable_initial_applicant:
		return
	_register_applicant(APPLICANT_ID, LABORER_NAME, WorkerData.Profession.LABORER)
	_register_applicant(HAULER_APPLICANT_ID, HAULER_NAME, WorkerData.Profession.LABORER)
	# Continuing an old checkpoint stages its candidate through the bounded
	# save codec. Only fresh startup seeds directly before CitySave exists.
	if WorkStateRuntime.get_node_or_null("CitySave") == null:
		ensure_city_hauler_applicant()
	if enable_initial_cart:
		_supply_initial_cart.call_deferred()

func _supply_initial_cart() -> void:
	# Worksites creates the shared provider after this sibling's _ready.
	var storage: Node = WorkStateRuntime.get_node_or_null("CityToolStorage")
	if storage == null or bool(storage.get_meta(CART_SUPPLIED_META, false)):
		return
	# The marker follows city stock across map visits, even if the cart is removed.
	if storage.units.has(CART_UNIT_ID) or storage.add_tool_unit(CART_UNIT_ID, "cart", "Cart"):
		storage.set_meta(CART_SUPPLIED_META, true)

func _register_applicant(citizen_id: String, display_name: String, profession: WorkerData.Profession) -> void:
	if CitizenManager.get_citizen(citizen_id) != null or WorkerDatabase.has_worker_data(citizen_id) or WorkerDatabase.dismissed_workers.has(citizen_id):
		return
	var applicant := CitizenData.new()
	applicant.citizen_id = citizen_id
	applicant.display_name = display_name
	applicant.population_status = CitizenData.PopulationStatus.RESIDENT
	applicant.satisfaction = INITIAL_APPLICANT_SATISFACTION
	CitizenManager.add_citizen(applicant)
	CitizenManager.register_applicant(citizen_id, profession)


static func normalize_legacy_applicant_name(applicant: CitizenData) -> void:
	# Old checkpoints used role labels for these two authored applicant IDs.
	if applicant == null:
		return
	if applicant.citizen_id == APPLICANT_ID and applicant.display_name == "Workshop Laborer":
		applicant.display_name = LABORER_NAME
	elif applicant.citizen_id == HAULER_APPLICANT_ID and applicant.display_name == "Worksite Hauler":
		applicant.display_name = HAULER_NAME


static func ensure_city_hauler_applicant() -> void:
	# Preserve existing citizens and their professions in older checkpoints.
	# A legacy resident Hauler is sufficient; do not create a second one.
	if CitizenManager.get_citizen(CITY_HAULER_APPLICANT_ID) != null or WorkerDatabase.has_worker_data(CITY_HAULER_APPLICANT_ID) or WorkerDatabase.dismissed_workers.has(CITY_HAULER_APPLICANT_ID):
		return
	if CitizenManager.citizens_by_id.size() >= CitySaveValues.MAX_COLLECTION_SIZE:
		return
	for person: CitizenData in CitizenManager.get_all_residents():
		if person.profession == WorkerData.Profession.HAULER:
			return
	var applicant := CitizenData.new()
	applicant.citizen_id = CITY_HAULER_APPLICANT_ID
	applicant.display_name = CITY_HAULER_NAME
	applicant.population_status = CitizenData.PopulationStatus.RESIDENT
	applicant.profession = WorkerData.Profession.HAULER
	applicant.satisfaction = INITIAL_APPLICANT_SATISFACTION
	CitizenManager.add_citizen(applicant)
	CitizenManager.register_applicant(CITY_HAULER_APPLICANT_ID, WorkerData.Profession.HAULER)
