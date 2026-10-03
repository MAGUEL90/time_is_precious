extends Node2D

## Initial applicants and one city Cart, retained by the existing runtime stores.
@export var enable_initial_applicant: bool = true
@export var enable_initial_cart: bool = true
const APPLICANT_ID: String = "initial_workshop_laborer"
const HAULER_APPLICANT_ID: String = "initial_worksite_hauler"
const CART_UNIT_ID: String = "initial_worksite_cart"
const CART_SUPPLIED_META: StringName = &"initial_worksite_cart_supplied"

func _ready() -> void:
	if not enable_initial_applicant:
		return
	_register_applicant(APPLICANT_ID, "Workshop Laborer", WorkerData.Profession.LABORER)
	_register_applicant(HAULER_APPLICANT_ID, "Worksite Hauler", WorkerData.Profession.HAULER)
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
	CitizenManager.add_citizen(applicant)
	CitizenManager.register_applicant(citizen_id, profession)
