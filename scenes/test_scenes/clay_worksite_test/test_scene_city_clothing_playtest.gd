extends Node2D

## F6 manual clothing lifecycle fixture.
##
## This scene is deliberately test-only: it uses the real content map, Player,
## City Storage and Worker Hub while restoring every shared runtime registry on
## exit. It never writes a save and does not auto-quit.

const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const TEST_ID: String = "city_clothing_manual_test"
const SIMPLE_CLOTHES: String = "simple_clothes"
const BARLEY_BREAD: String = "barley_bread"
const NEED_FIELDS: Array[String] = [
	"last_food_fulfilled_count", "last_food_unfulfilled_count",
	"last_clothing_fulfilled_count", "last_clothing_unfulfilled_count",
	"last_shelter_capacity_fulfilled_count", "last_shelter_capacity_unfulfilled_count",
	"last_processed_day", "last_food_processed_day", "last_clothing_processed_day",
	"_processing_daily_needs", "_processing_food", "_processing_clothing",
	"clothing_allocations", "last_needs_results"
]

var content: Node
var provider: Node
var player: Player
var storage_area: Area2D
var worker_control: WorkerControlUI
var personal_garment_granted: bool = false
var provider_existed_before_fixture: bool = false

var original_citizens: Dictionary = {}
var original_workers: Dictionary = {}
var original_dismissed_workers: Dictionary = {}
var original_inventory: Dictionary = {}
var original_city_stock: Dictionary = {}
var original_clock: Dictionary = {}
var original_needs_state: Dictionary = {}
var original_provider_state: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_snapshot_shared_state()
	_setup_fixture.call_deferred()


func _setup_fixture() -> void:
	_clear_fixture_registries()
	_create_fixture_people()
	CityStockManager.food_supply = 0
	CityStockManager.clothing_supply = 0
	CityStockManager.shelter_capacity = 1

	content = CONTENT.instantiate()
	content.process_mode = Node.PROCESS_MODE_PAUSABLE
	var worksites = content.get_node("YSortWorld/Worksites")
	worksites.set("seed_playtest_hauler", false)
	add_child(content)
	await get_tree().process_frame
	await get_tree().process_frame

	player = content.get_node("YSortWorld/Player") as Player
	player.debug_disable_player_needs = true
	storage_area = content.get_node("YSortWorld/Worksites/CityStorageArea") as Area2D
	var worksite = content.get_node("YSortWorld/Worksites")
	provider = worksite.get("city_tools") as Node
	worker_control = worksite.get_node("WorkerControlUI") as WorkerControlUI
	if is_instance_valid(provider):
		provider.set("items", {BARLEY_BREAD: 32, SIMPLE_CLOTHES: 2})
		provider.set("food_portions", {})
		provider.set("units", {})
		provider.set("_unit_sequence", 0)
		provider.set("_transfer_in_progress", false)
	if is_instance_valid(player) and is_instance_valid(storage_area):
		player.global_position = storage_area.global_position + Vector2(0, 12)
		await get_tree().physics_frame
		await get_tree().physics_frame

	# The automatic clock remains paused; N calls the real minute advancement API.
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 0
	TimeComponentManager.current_minute = 0
	TimeComponentManager.current_weather = "clear"
	TimeComponentManager.is_paused = true
	get_tree().paused = false
	_reset_need_tracking()
	_refresh_instructions("Fixture ready")
	_capture_initial_view.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_N:
			# A test day skips 1,440 minute ticks. Keep the real clock/needs path,
			# but render the open Hub only once after the test-only time jump.
			var hub_was_visible: bool = is_instance_valid(worker_control) and worker_control.visible
			if hub_was_visible:
				worker_control.hide()
			TimeComponentManager.advance_minutes(1440)
			if hub_was_visible:
				worker_control.show()
				worker_control.refresh()
			_refresh_instructions("Advanced one day")
			get_viewport().set_input_as_handled()
		KEY_R:
			_grant_personal_garment()
			get_viewport().set_input_as_handled()
		KEY_T:
			if worker_control.visible:
				worker_control.close()
			else:
				worker_control.open()
			get_viewport().set_input_as_handled()


func _grant_personal_garment() -> void:
	if personal_garment_granted:
		_refresh_instructions("R already granted one; use E Deposit")
		return
	Inventory.add_item(SIMPLE_CLOTHES, 1)
	personal_garment_granted = true
	_refresh_instructions("R gave one garment; press E at City Storage and use Deposit")


func _open_worker_details() -> void:
	if not is_instance_valid(worker_control):
		_refresh_instructions("Worker Hub is not ready")
		return
	if not worker_control.visible and not worker_control._can_open_now():
		_refresh_instructions("Close the other menu, then press T again")
		return
	worker_control.open()
	# Let the newly opened status rows lay out before anchoring their popup.
	await get_tree().process_frame
	await get_tree().process_frame
	worker_control._show_manage(TEST_ID)
	worker_control.manage_details_button.pressed.emit()
	_refresh_instructions("Worker Hub Details: Clothing Test")


func _refresh_instructions(action: String) -> void:
	var day: int = TimeComponentManager.current_day
	var stock: int = int(provider.call("get_clothing_item_count")) if is_instance_valid(provider) else 0
	var citizen: CitizenData = CitizenManager.get_citizen(TEST_ID)
	var clothing_ok: bool = citizen != null and citizen.clothing_fulfilled
	var allocation: Dictionary = {}
	if _has_property(CitizenNeedsManager, "clothing_allocations"):
		var allocations: Variant = CitizenNeedsManager.get("clothing_allocations")
		if allocations is Dictionary:
			allocation = allocations.get(TEST_ID, {})
	var days_left: int = 0
	if not allocation.is_empty():
		days_left = int(allocation.get("expires_day", day - 1)) - day + 1
	$InstructionLayer/InstructionPanel/InstructionLabel.text = (
		"CLOTHING TEST | Day %d | Stock %d | Covered %s | Left %d\n"
		% [day, stock, "yes" if clothing_ok else "no", days_left]
		+ "N +1 day (clock paused) | R Inventory +1 garment\n"
		+ "E City Storage: Deposit | T Worker Hub\n"
		+ action
	)


func _capture_initial_view() -> void:
	var directory: String = OS.get_environment("TIP_CITY_CLOTHING_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(directory.path_join("city-clothing-playtest.png"))


func _snapshot_shared_state() -> void:
	original_citizens = CitizenManager.citizens_by_id.duplicate(true)
	original_workers = WorkerDatabase.workers_by_id.duplicate(true)
	original_dismissed_workers = WorkerDatabase.dismissed_workers.duplicate(true)
	original_inventory = Inventory.items.duplicate(true)
	original_city_stock = {
		"food_supply": CityStockManager.food_supply,
		"clothing_supply": CityStockManager.clothing_supply,
		"treasury_shekel": CityStockManager.treasury_shekel,
		"shelter_capacity": CityStockManager.shelter_capacity
	}
	original_clock = {
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"weather": TimeComponentManager.current_weather,
		"paused": TimeComponentManager.is_paused,
		"tree_paused": get_tree().paused
	}
	for property_name: String in NEED_FIELDS:
		if _has_property(CitizenNeedsManager, property_name):
			var value: Variant = CitizenNeedsManager.get(property_name)
			if value is Dictionary or value is Array:
				value = value.duplicate(true)
			original_needs_state[property_name] = value

	var existing_provider: Node = get_node_or_null("/root/WorkStateRuntime/CityToolStorage")
	provider_existed_before_fixture = is_instance_valid(existing_provider)
	if provider_existed_before_fixture:
		provider = existing_provider
		original_provider_state = _snapshot_provider(provider)


func _snapshot_provider(target: Node) -> Dictionary:
	var snapshot: Dictionary = {}
	for property_name: String in ["food_portions", "items", "units"]:
		var value: Variant = target.get(property_name)
		if value is Dictionary:
			snapshot[property_name] = value.duplicate(true)
	for property_name: String in ["_unit_sequence", "_transfer_in_progress"]:
		if _has_property(target, property_name):
			snapshot[property_name] = target.get(property_name)
	return snapshot


func _clear_fixture_registries() -> void:
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()


func _create_fixture_people() -> void:
	var resident: CitizenData = CitizenData.new()
	resident.citizen_id = TEST_ID
	resident.display_name = "Clothing Test"
	resident.population_status = CitizenData.PopulationStatus.RESIDENT
	resident.employment_status = CitizenData.EmploymentStatus.HIRED
	resident.profession = WorkerData.Profession.LABORER
	resident.satisfaction = 0.5
	resident.reliability = 0.5
	CitizenManager.add_citizen(resident)

	var worker: WorkerData = WorkerData.new()
	worker.worker_id = TEST_ID
	worker.display_name = "Clothing Test"
	worker.profession = WorkerData.Profession.LABORER
	worker.satisfaction = 0.5
	worker.reliability = 0.5
	WorkerDatabase.workers_by_id[TEST_ID] = worker


func _reset_need_tracking() -> void:
	_set_if_property(CitizenNeedsManager, "last_processed_day", 0)
	_set_if_property(CitizenNeedsManager, "last_food_processed_day", 0)
	_set_if_property(CitizenNeedsManager, "last_clothing_processed_day", 0)
	_set_if_property(CitizenNeedsManager, "_processing_daily_needs", false)
	_set_if_property(CitizenNeedsManager, "_processing_food", false)
	_set_if_property(CitizenNeedsManager, "_processing_clothing", false)
	_set_if_property(CitizenNeedsManager, "clothing_allocations", {})
	_set_if_property(CitizenNeedsManager, "last_needs_results", {})


func _exit_tree() -> void:
	if is_instance_valid(worker_control) and worker_control.visible:
		worker_control.close()
	CitizenManager.citizens_by_id = original_citizens.duplicate(true)
	WorkerDatabase.workers_by_id = original_workers.duplicate(true)
	WorkerDatabase.dismissed_workers = original_dismissed_workers.duplicate(true)
	Inventory.items = original_inventory.duplicate(true)
	CityStockManager.food_supply = int(original_city_stock.get("food_supply", 0))
	CityStockManager.clothing_supply = int(original_city_stock.get("clothing_supply", 0))
	CityStockManager.treasury_shekel = int(original_city_stock.get("treasury_shekel", 0))
	CityStockManager.shelter_capacity = int(original_city_stock.get("shelter_capacity", 0))
	TimeComponentManager.current_day = int(original_clock.get("day", 0))
	TimeComponentManager.current_hour = int(original_clock.get("hour", 0))
	TimeComponentManager.current_minute = int(original_clock.get("minute", 0))
	TimeComponentManager.current_weather = str(original_clock.get("weather", "clear"))
	TimeComponentManager.is_paused = bool(original_clock.get("paused", false))
	get_tree().paused = bool(original_clock.get("tree_paused", false))
	for property_name: String in original_needs_state.keys():
		if _has_property(CitizenNeedsManager, property_name):
			var value: Variant = original_needs_state[property_name]
			if value is Dictionary or value is Array:
				value = value.duplicate(true)
			CitizenNeedsManager.set(property_name, value)

	if provider_existed_before_fixture:
		_restore_provider(provider, original_provider_state)
	else:
		var created_provider: Node = get_node_or_null("/root/WorkStateRuntime/CityToolStorage")
		if is_instance_valid(created_provider):
			created_provider.queue_free()


func _restore_provider(target: Node, snapshot: Dictionary) -> void:
	if not is_instance_valid(target):
		return
	for property_name: String in ["food_portions", "items", "units"]:
		if snapshot.has(property_name):
			target.set(property_name, snapshot[property_name].duplicate(true))
	for property_name: String in ["_unit_sequence", "_transfer_in_progress"]:
		if snapshot.has(property_name) and _has_property(target, property_name):
			target.set(property_name, snapshot[property_name])


func _set_if_property(target: Object, property_name: String, value: Variant) -> void:
	if _has_property(target, property_name):
		target.set(property_name, value)


func _has_property(target: Object, property_name: String) -> bool:
	for property_info: Dictionary in target.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false
