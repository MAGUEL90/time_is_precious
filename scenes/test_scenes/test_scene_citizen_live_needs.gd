extends Node

## Live panel coverage across real daily settlements and physical City Storage.
## The fixture is memory-only and never opens or writes a CitySave checkpoint.
const PANEL: PackedScene = preload("res://scenes/ui/citizen_inspection/citizen_inspection_panel.tscn")
const CITY_TOOL_STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const READY_BREAD: String = "barley_bread"
const SIMPLE_CLOTHES: String = "simple_clothes"
const DAILY_STEP: float = 0.05
const SHORTAGE_TARGET: float = 0.66
const FULL_NEEDS_TARGET: float = 0.99
const PANEL_REFRESH_WAIT: float = 0.25

var failures: int = 0
var fixture_day: int = 0
var person_id: String = ""
var person: CitizenData
var panel: CanvasLayer
var provider: Node
var runtime: Node
var created_provider: bool = false
var capture_directory: String = ""

var original_inventory: Dictionary = {}
var original_citizens: Dictionary = {}
var original_workers: Dictionary = {}
var original_dismissed_workers: Dictionary = {}
var original_onboarding_rates: Dictionary = {}
var original_clock: Dictionary = {}
var original_city_stock: Dictionary = {}
var original_needs_state: Dictionary = {}
var original_provider_state: Dictionary = {}
var city_progress_state: Node
var original_city_progress_state: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	capture_directory = OS.get_environment("TIP_CITIZEN_LIVE_CAPTURE_DIR")
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _frames(count: int = 1) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _wait_for_panel_refresh() -> void:
	await get_tree().create_timer(PANEL_REFRESH_WAIT, true, false, true).timeout


func _snapshot() -> void:
	original_inventory = Inventory.items.duplicate(true)
	original_citizens = CitizenManager.citizens_by_id.duplicate()
	original_workers = WorkerDatabase.workers_by_id.duplicate()
	original_dismissed_workers = WorkerDatabase.dismissed_workers.duplicate()
	original_onboarding_rates = WorkerDatabase.onboarding_period_rates.duplicate(true)
	original_clock = {
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"weather": TimeComponentManager.current_weather,
		"paused": TimeComponentManager.is_paused,
		"processing": TimeComponentManager.is_processing(),
		"tree_paused": get_tree().paused
	}
	original_city_stock = {
		"food_supply": CityStockManager.food_supply,
		"clothing_supply": CityStockManager.clothing_supply,
		"treasury": CityStockManager.treasury_shekel,
		"shelter": CityStockManager.shelter_capacity
	}
	for property_name: String in [
		"last_food_fulfilled_count", "last_food_unfulfilled_count",
		"last_clothing_fulfilled_count", "last_clothing_unfulfilled_count",
		"last_shelter_capacity_fulfilled_count", "last_shelter_capacity_unfulfilled_count",
		"last_processed_day", "last_food_processed_day", "last_clothing_processed_day",
		"_processing_daily_needs", "_processing_food", "_processing_clothing",
		"_daily_needs_retry_pending", "_daily_needs_retry_after_frame",
		"clothing_allocations", "last_needs_results"
	]:
		var value: Variant = CitizenNeedsManager.get(property_name)
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		original_needs_state[property_name] = value

	runtime = get_node_or_null("/root/WorkStateRuntime")
	_expect(is_instance_valid(runtime), "WorkStateRuntime is available for the real CityToolStorage provider.")
	if not is_instance_valid(runtime):
		return
	provider = runtime.get_node_or_null("CityToolStorage")
	if is_instance_valid(provider):
		original_provider_state = {
			"items": provider.get("items").duplicate(true),
			"food_portions": provider.get("food_portions").duplicate(true),
			"units": provider.get("units").duplicate(true),
			"unit_sequence": int(provider.get("_unit_sequence")),
			"transfer_in_progress": bool(provider.get("_transfer_in_progress"))
		}

	city_progress_state = runtime.get_node_or_null("CityProgression")
	if is_instance_valid(city_progress_state):
		for property_name: String in ["level", "progress", "last_daily", "last_event", "last_awarded_day", "_last_breach_id"]:
			var value: Variant = city_progress_state.get(property_name)
			if value is Dictionary or value is Array:
				value = value.duplicate(true)
			original_city_progress_state[property_name] = value


func _prepare_fixture() -> bool:
	if not is_instance_valid(runtime):
		return false
	if not is_instance_valid(provider):
		provider = CITY_TOOL_STORAGE_SCRIPT.new()
		provider.name = "CityToolStorage"
		runtime.add_child(provider)
		created_provider = true
	_expect(provider.get_script() == CITY_TOOL_STORAGE_SCRIPT
		and provider.has_method("get_food_supply_points") and provider.has_method("take_clothing_items"),
		"The fixture uses the actual CityToolStorage implementation.")
	if provider.get_script() != CITY_TOOL_STORAGE_SCRIPT:
		return false

	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	var latest_needs_day: int = maxi(CitizenNeedsManager.last_processed_day,
		maxi(CitizenNeedsManager.last_food_processed_day, CitizenNeedsManager.last_clothing_processed_day))
	fixture_day = maxi(TimeComponentManager.current_day, latest_needs_day) + 100
	TimeComponentManager.current_day = fixture_day
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_minute = 0

	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	Inventory.items.clear()
	Inventory.items_changed.emit()
	var storage_items: Dictionary = provider.get("items")
	var food_portions: Dictionary = provider.get("food_portions")
	storage_items.clear()
	food_portions.clear()
	provider.set("_transfer_in_progress", false)
	CityStockManager.shelter_capacity = 1

	for property_name: String in [
		"last_food_fulfilled_count", "last_food_unfulfilled_count",
		"last_clothing_fulfilled_count", "last_clothing_unfulfilled_count",
		"last_shelter_capacity_fulfilled_count", "last_shelter_capacity_unfulfilled_count"
	]:
		CitizenNeedsManager.set(property_name, 0)
	CitizenNeedsManager.last_processed_day = fixture_day - 1
	CitizenNeedsManager.last_food_processed_day = fixture_day - 1
	CitizenNeedsManager.last_clothing_processed_day = fixture_day - 1
	CitizenNeedsManager._processing_daily_needs = false
	CitizenNeedsManager._processing_food = false
	CitizenNeedsManager._processing_clothing = false
	CitizenNeedsManager._daily_needs_retry_pending = false
	CitizenNeedsManager._daily_needs_retry_after_frame = false
	CitizenNeedsManager.clothing_allocations.clear()
	CitizenNeedsManager.last_needs_results.clear()

	person_id = "citizen_live_needs_%d" % Time.get_ticks_usec()
	person = CitizenData.new()
	person.citizen_id = person_id
	person.display_name = "Live Needs Resident"
	person.population_status = CitizenData.PopulationStatus.RESIDENT
	person.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	person.satisfaction = 0.91
	CitizenManager.add_citizen(person)
	_expect(CitizenManager.get_citizen(person_id) == person and CitizenManager.get_all_residents().size() == 1,
		"The fixture adds one real resident through CitizenManager.")

	Inventory.items.assign({READY_BREAD: 5})
	Inventory.items_changed.emit()
	var initial_deposit: Dictionary = provider.call("deposit_items_from_inventory", {READY_BREAD: 5})
	_expect(bool(initial_deposit.get("ok", false)) and int(provider.call("get_food_supply_points")) == 5
		and int(provider.call("get_clothing_item_count")) == 0
		and int(provider.get("items").get(READY_BREAD, 0)) == 5
		and not provider.get("items").has(SIMPLE_CLOTHES),
		"Five real bread units enter CityToolStorage, with no clothing available for the shortage days.")
	return true


func _run() -> void:
	_snapshot()
	if not _prepare_fixture():
		await _finish()
		return

	panel = PANEL.instantiate() as CanvasLayer
	panel.summary_provider = Callable(CitizenNeedsManager, "get_person_needs_summary")
	add_child(panel)
	await _frames(2)
	panel.open_for(person_id)
	_expect(panel.visible and str(panel.get("selected_id")) == person_id,
		"The actual inspection panel opens for the real resident ID.")
	_expect(_label("NameRow/NameLabel").text == "Live Needs Resident"
		and _label("DailyCheckLabel").text == "LAST DAILY CHECK · NOT EVALUATED"
		and _label("ConditionLabel").text == "Condition (daily): Unknown"
		and _label("SatisfactionLabel").text == "Actual satisfaction: 91%"
		and _label("CityStockRow/FoodStock/Label").text == "5 pts"
		and _label("CityStockRow/ClothingStock/Label").text == "0 units"
		and _label("CityStockRow/ShelterStock/Label").text == "1 capacity",
		"The open panel begins from the actual provider summary without a fabricated daily result.")
	_expect(not panel.get_node("RefreshTimer").is_stopped(),
		"The actual panel refresh timer runs while inspection is open.")
	if not panel.visible:
		await _finish()
		return

	await _test_shortage_until_stable()
	await _test_same_day_restock_and_duplicate_settlement()
	await _test_clothing_issue_and_expiry()
	await _finish()


func _test_shortage_until_stable() -> void:
	var expected_satisfaction: float = person.satisfaction
	_expect(expected_satisfaction > SHORTAGE_TARGET,
		"The resident starts above the two-of-three-needs condition target.")
	for offset: int in range(5):
		var day: int = fixture_day + offset
		await _settle(day)
		expected_satisfaction = move_toward(expected_satisfaction, SHORTAGE_TARGET, DAILY_STEP)
		var trend: String = "stable" if offset == 4 else "down"
		_assert_panel_state(day, expected_satisfaction, SHORTAGE_TARGET, trend, true, false,
			0, 5 - offset - 1, 0, "Two needs met and clothing unavailable")
		if offset == 0:
			_expect(str(_label("ConditionLabel").text).ends_with("Down"),
				"The first actual settlement displays a downward direction.")
	_expect(is_equal_approx(person.satisfaction, SHORTAGE_TARGET)
		and str(CitizenNeedsManager.get_person_needs_summary(person_id).trend) == "stable",
		"Repeated real settlements move actual satisfaction down to 66% and then stabilize.")
	await _capture("shortage_stable")


func _test_same_day_restock_and_duplicate_settlement() -> void:
	var ledger_before: Dictionary = CitizenNeedsManager.last_needs_results[person_id].duplicate(true)
	var satisfaction_before: float = person.satisfaction
	_expect(not CitizenNeedsManager.clothing_allocations.has(person_id)
		and int(provider.call("get_food_supply_points")) == 0
		and int(provider.call("get_clothing_item_count")) == 0,
		"The shortage settlement leaves no physical food or garment allocation for this resident.")

	Inventory.items.assign({READY_BREAD: 8, SIMPLE_CLOTHES: 1})
	Inventory.items_changed.emit()
	var restock: Dictionary = provider.call("deposit_items_from_inventory", {READY_BREAD: 8, SIMPLE_CLOTHES: 1})
	_expect(bool(restock.get("ok", false))
		and int(provider.call("get_food_supply_points")) == 8
		and int(provider.call("get_clothing_item_count")) == 1
		and int(provider.get("items").get(READY_BREAD, 0)) == 8
		and int(provider.get("items").get(SIMPLE_CLOTHES, 0)) == 1,
		"The player physically restocks eight food points and one garment in CityToolStorage on the settled day.")
	await _wait_for_panel_refresh()
	_assert_panel_state(fixture_day + 4, satisfaction_before, SHORTAGE_TARGET, "stable", true, false,
		0, 8, 1, "Same-day restock before the next settlement")
	_expect(CitizenNeedsManager.last_needs_results[person_id] == ledger_before
		and is_equal_approx(person.satisfaction, satisfaction_before)
		and not CitizenNeedsManager.clothing_allocations.has(person_id),
		"Same-day physical restock changes current stock only; the last daily result and actual satisfaction remain unchanged.")
	await _capture("restocked_before_settlement")
	await _assert_duplicate_day_is_noop("restocked_before_settlement")


func _test_clothing_issue_and_expiry() -> void:
	var issue_day: int = fixture_day + 5
	await _settle(issue_day)
	var allocation: Dictionary = CitizenNeedsManager.clothing_allocations.get(person_id, {})
	_expect(allocation.get("item_id", "") == SIMPLE_CLOTHES
		and int(allocation.get("issued_day", -1)) == issue_day
		and int(allocation.get("expires_day", -1)) == issue_day + 6,
		"The next real settlement allocates the physical garment for seven inclusive days.")
	_assert_panel_state(issue_day, 0.71, FULL_NEEDS_TARGET, "up", true, true, 7,
		7, 0, "Garment allocated")
	_expect(is_equal_approx(person.satisfaction, 0.71)
		and bool(CitizenNeedsManager.last_needs_results[person_id].clothing)
		and CitizenNeedsManager.last_clothing_fulfilled_count == 1,
		"Actual satisfaction rises toward 99% after the real allocation, and the one resident is counted.")
	await _capture("garment_allocated")
	await _assert_duplicate_day_is_noop("after_garment_allocation")

	var expected_satisfaction: float = 0.71
	for offset: int in range(1, 8):
		var day: int = issue_day + offset
		await _settle(day)
		if offset < 7:
			expected_satisfaction = move_toward(expected_satisfaction, FULL_NEEDS_TARGET, DAILY_STEP)
			var trend: String = "stable" if is_equal_approx(expected_satisfaction, FULL_NEEDS_TARGET) else "up"
			_assert_panel_state(day, expected_satisfaction, FULL_NEEDS_TARGET, trend, true, true,
				7 - offset, 7 - offset, 0, "Garment remains valid without clothing restock")
		else:
			expected_satisfaction = move_toward(expected_satisfaction, SHORTAGE_TARGET, DAILY_STEP)
			_assert_panel_state(day, expected_satisfaction, SHORTAGE_TARGET, "down", true, false,
				0, 0, 0, "Garment expired without clothing restock")
			_expect(not CitizenNeedsManager.clothing_allocations.has(person_id)
				and CitizenNeedsManager.last_needs_results[person_id].missing.has("Clothing"),
				"At expiry, the real allocation is removed and Clothing is missing again.")
			await _capture("garment_expired")


func _settle(day: int) -> void:
	TimeComponentManager.current_day = day
	CitizenNeedsManager.process_daily_needs()
	_expect(CitizenNeedsManager.last_processed_day == day
		and CitizenNeedsManager.last_food_processed_day == day
		and CitizenNeedsManager.last_clothing_processed_day == day,
		"CitizenNeedsManager performs a real once-per-day settlement for day %d." % day)
	await _wait_for_panel_refresh()


func _assert_duplicate_day_is_noop(stage: String) -> void:
	var stock_items: Dictionary = provider.get("items").duplicate(true)
	var food_portions: Dictionary = provider.get("food_portions").duplicate(true)
	var ledger: Dictionary = CitizenNeedsManager.last_needs_results[person_id].duplicate(true)
	var allocation: Dictionary = CitizenNeedsManager.clothing_allocations.get(person_id, {}).duplicate(true)
	var satisfaction: float = person.satisfaction
	CitizenNeedsManager.process_daily_needs()
	CitizenNeedsManager.process_daily_food_needs()
	CitizenNeedsManager.process_daily_clothing_needs()
	await _wait_for_panel_refresh()
	_expect(provider.get("items") == stock_items and provider.get("food_portions") == food_portions
		and CitizenNeedsManager.last_needs_results[person_id] == ledger
		and CitizenNeedsManager.clothing_allocations.get(person_id, {}) == allocation
		and is_equal_approx(person.satisfaction, satisfaction),
		"Duplicate same-day settlement calls do not reconsume supplies or change state: " + stage)


func _assert_panel_state(
	day: int,
	satisfaction: float,
	condition_target: float,
	trend: String,
	food: bool,
	clothing: bool,
	clothing_days_left: int,
	food_stock: int,
	clothing_stock: int,
	stage: String
) -> void:
	var summary: Dictionary = CitizenNeedsManager.get_person_needs_summary(person_id)
	var ledger: Dictionary = CitizenNeedsManager.last_needs_results.get(person_id, {})
	var trend_text: String = trend.capitalize()
	var expected_condition_text: String = "Condition (daily): %d%% · %s" % [roundi(condition_target * 100.0), trend_text]
	var expected_satisfaction_text: String = "Actual satisfaction: %d%%" % roundi(satisfaction * 100.0)
	_expect(panel.visible and str(panel.get("selected_id")) == person_id
		and CitizenManager.get_citizen(person_id) == person,
		"The visible panel remains bound to the exact live resident ID: " + stage)
	_expect(bool(summary.get("evaluated", false)) and int(summary.get("day", -1)) == day
		and int(ledger.get("day", -1)) == day
		and is_equal_approx(float(summary.get("satisfaction", -1.0)), satisfaction)
		and is_equal_approx(float(summary.get("condition_target", -1.0)), condition_target)
		and str(summary.get("trend", "")) == trend,
		"The live manager summary exposes this settlement's day, actual satisfaction, target, and direction: " + stage)
	_expect(bool(summary.get("food", false)) == food and bool(summary.get("clothing", false)) == clothing
		and bool(summary.get("shelter", false))
		and bool(ledger.get("food", false)) == food and bool(ledger.get("clothing", false)) == clothing
		and bool(ledger.get("shelter", false))
		and int(summary.get("clothing_days_left", -1)) == clothing_days_left,
		"The last daily result contains the actual three-need and garment-duration outcomes: " + stage)
	_expect(int(summary.get("food_stock", -1)) == food_stock
		and int(summary.get("clothing_stock", -1)) == clothing_stock
		and int(summary.get("shelter_capacity", -1)) == 1
		and int(provider.call("get_food_supply_points")) == food_stock
		and int(provider.call("get_clothing_item_count")) == clothing_stock,
		"Current CityToolStorage stock is reported separately from the daily outcome: " + stage)
	_expect(_label("DailyCheckLabel").text == "LAST DAILY CHECK · DAY %d" % day
		and _label("DailyNeedsRow/FoodStatus/Label").text == ("Food: Met" if food else "Food: Missing")
		and _label("DailyNeedsRow/ClothingStatus/Label").text == ("Clothing: Met" if clothing else "Clothing: Missing")
		and _label("DailyNeedsRow/ShelterStatus/Label").text == "Shelter: Met"
		and _label("ClothingDaysLabel").text == "Clothing days left: %d" % clothing_days_left
		and _label("SatisfactionLabel").text == expected_satisfaction_text
		and _label("ConditionLabel").text == expected_condition_text,
		"The actual open panel refreshes every live value and label: " + stage)
	_expect(_label("CityStockLabel").text == "CITY SUPPLY NOW"
		and _label("CityStockRow/FoodStock/Label").text == "%d pts" % food_stock
		and _label("CityStockRow/ClothingStock/Label").text == "%d units" % clothing_stock
		and _label("CityStockRow/ShelterStock/Label").text == "1 capacity",
		"The panel's CITY SUPPLY NOW row matches physical storage and shelter capacity: " + stage)


func _label(path: String) -> Label:
	if not is_instance_valid(panel):
		return null
	return panel.get_node("Root/Frame/Margin/Contents/" + path) as Label


func _capture(stage: String) -> void:
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(capture_directory)
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_expect(image.save_png(capture_directory.path_join(stage + ".png")) == OK,
		"The actual panel capture is saved: " + stage)


func _finish() -> void:
	if is_instance_valid(panel):
		panel.call("close")
		panel.free()
	panel = null

	if is_instance_valid(provider) and created_provider:
		provider.free()
	elif is_instance_valid(provider):
		provider.set("items", original_provider_state.get("items", {}).duplicate(true))
		provider.set("food_portions", original_provider_state.get("food_portions", {}).duplicate(true))
		provider.set("units", original_provider_state.get("units", {}).duplicate(true))
		provider.set("_unit_sequence", int(original_provider_state.get("unit_sequence", 0)))
		provider.set("_transfer_in_progress", bool(original_provider_state.get("transfer_in_progress", false)))
		provider.emit_signal("changed")

	Inventory.items.assign(original_inventory)
	Inventory.items_changed.emit()
	CitizenManager.citizens_by_id.clear()
	CitizenManager.citizens_by_id.assign(original_citizens)
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.workers_by_id.assign(original_workers)
	WorkerDatabase.dismissed_workers.clear()
	WorkerDatabase.dismissed_workers.assign(original_dismissed_workers)
	WorkerDatabase.onboarding_period_rates.assign(original_onboarding_rates)
	for property_name: String in original_needs_state:
		var value: Variant = original_needs_state[property_name]
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		CitizenNeedsManager.set(property_name, value)
	CityStockManager.food_supply = int(original_city_stock.get("food_supply", 0))
	CityStockManager.clothing_supply = int(original_city_stock.get("clothing_supply", 0))
	CityStockManager.treasury_shekel = int(original_city_stock.get("treasury", 0))
	CityStockManager.shelter_capacity = int(original_city_stock.get("shelter", 0))
	if is_instance_valid(city_progress_state):
		for property_name: String in original_city_progress_state:
			var value: Variant = original_city_progress_state[property_name]
			if value is Dictionary or value is Array:
				value = value.duplicate(true)
			city_progress_state.set(property_name, value)
	TimeComponentManager.current_day = int(original_clock.get("day", 0))
	TimeComponentManager.current_hour = int(original_clock.get("hour", 0))
	TimeComponentManager.current_minute = int(original_clock.get("minute", 0))
	TimeComponentManager.current_weather = str(original_clock.get("weather", "clear"))
	TimeComponentManager.is_paused = bool(original_clock.get("paused", false))
	TimeComponentManager.set_process(bool(original_clock.get("processing", true)))
	get_tree().paused = bool(original_clock.get("tree_paused", false))

	if failures == 0:
		print("CitizenLiveNeedsTest PASSED")
	else:
		print("CitizenLiveNeedsTest FAILED: %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
