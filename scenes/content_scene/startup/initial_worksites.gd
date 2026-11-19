extends Node2D

## Initial applicants and one city Cart, retained by the existing runtime stores.
@export var enable_initial_applicant: bool = true
@export var enable_initial_cart: bool = true
@export_group("New Citizen Defaults")
@export var laborer_seed: InitialCitizenSeed = preload("res://scenes/content_scene/startup/initial_laborer_seed.tres")
@export var worksite_laborer_seed: InitialCitizenSeed = preload("res://scenes/content_scene/startup/initial_worksite_laborer_seed.tres")
@export var city_hauler_seed: InitialCitizenSeed = preload("res://scenes/content_scene/startup/initial_city_hauler_seed.tres")
# Compatibility constants are intentionally independent of editable New Game
# data. Existing saves, including legacy missing-profile repair, keep this baseline.
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
	# Validate the full setup before publishing any citizen or supplying the cart.
	for seed: InitialCitizenSeed in [laborer_seed, worksite_laborer_seed, city_hauler_seed]:
		var error: String = _seed_validation_error(seed)
		if not error.is_empty():
			push_error("InitialWorksites: " + error)
			return
	_register_applicant(APPLICANT_ID, LABORER_NAME, WorkerData.Profession.LABORER, laborer_seed)
	_register_applicant(HAULER_APPLICANT_ID, HAULER_NAME, WorkerData.Profession.LABORER, worksite_laborer_seed)
	# Continuing an old checkpoint stages its candidate through the bounded
	# save codec. Only fresh startup seeds directly before CitySave exists.
	if WorkStateRuntime.get_node_or_null("CitySave") == null:
		ensure_city_hauler_applicant(city_hauler_seed)
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

func _register_applicant(citizen_id: String, display_name: String, profession: WorkerData.Profession, seed: InitialCitizenSeed = null) -> void:
	if CitizenManager.get_citizen(citizen_id) != null or WorkerDatabase.has_worker_data(citizen_id) or WorkerDatabase.dismissed_workers.has(citizen_id):
		return
	if seed != null and not seed.validation_error().is_empty():
		push_error("InitialWorksites: " + seed.validation_error())
		return
	var applicant := CitizenData.new()
	applicant.citizen_id = citizen_id
	applicant.display_name = seed.display_name if seed != null else display_name
	applicant.visual_profile = seed.create_visual_profile() if seed != null else create_initial_visual_profile()
	applicant.population_status = CitizenData.PopulationStatus.RESIDENT
	applicant.satisfaction = seed.satisfaction if seed != null else INITIAL_APPLICANT_SATISFACTION
	CitizenManager.add_citizen(applicant)
	CitizenManager.register_applicant(citizen_id, profession)


static func create_initial_visual_profile() -> VisualProfile:
	# These are the starters' existing visible defaults, now recorded explicitly.
	# Keep this compatibility baseline stable if future generic defaults change.
	# A legacy null profile contains no recoverable historical appearance.
	var profile := VisualProfile.new()
	profile.skin_tone = "light"
	profile.expression = "base"
	profile.hair_style = "grey_male_01"
	profile.clothes_id = "clay_worn_wrap"
	profile.accessory = "default"
	return profile


static func normalize_legacy_applicant_name(applicant: CitizenData) -> void:
	# Old checkpoints used role labels for these two authored applicant IDs.
	if applicant == null:
		return
	if applicant.citizen_id == APPLICANT_ID and applicant.display_name == "Workshop Laborer":
		applicant.display_name = LABORER_NAME
	elif applicant.citizen_id == HAULER_APPLICANT_ID and applicant.display_name == "Worksite Hauler":
		applicant.display_name = HAULER_NAME


static func ensure_city_hauler_applicant(seed: InitialCitizenSeed = null) -> void:
	# Preserve existing citizens and their professions in older checkpoints.
	# A legacy resident Hauler is sufficient; do not create a second one.
	if CitizenManager.get_citizen(CITY_HAULER_APPLICANT_ID) != null or WorkerDatabase.has_worker_data(CITY_HAULER_APPLICANT_ID) or WorkerDatabase.dismissed_workers.has(CITY_HAULER_APPLICANT_ID):
		return
	if CitizenManager.citizens_by_id.size() >= CitySaveValues.MAX_COLLECTION_SIZE:
		return
	for person: CitizenData in CitizenManager.get_all_residents():
		if person.profession == WorkerData.Profession.HAULER:
			return
	if seed != null and not seed.validation_error().is_empty():
		push_error("InitialWorksites: " + seed.validation_error())
		return
	var applicant := CitizenData.new()
	applicant.citizen_id = CITY_HAULER_APPLICANT_ID
	applicant.display_name = seed.display_name if seed != null else CITY_HAULER_NAME
	applicant.visual_profile = seed.create_visual_profile() if seed != null else create_initial_visual_profile()
	applicant.population_status = CitizenData.PopulationStatus.RESIDENT
	applicant.profession = WorkerData.Profession.HAULER
	applicant.satisfaction = seed.satisfaction if seed != null else INITIAL_APPLICANT_SATISFACTION
	CitizenManager.add_citizen(applicant)
	CitizenManager.register_applicant(CITY_HAULER_APPLICANT_ID, WorkerData.Profession.HAULER)


static func _seed_validation_error(seed: InitialCitizenSeed) -> String:
	return "Starter seed resource is missing." if seed == null else seed.validation_error()
