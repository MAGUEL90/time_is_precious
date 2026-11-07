extends Node

## Live panel coverage across elapsed game time and physical City Storage.
## The fixture is memory-only and never opens or writes a CitySave checkpoint.
const PANEL: PackedScene = preload("res://scenes/ui/citizen_inspection/citizen_inspection_panel.tscn")
const CITY_TOOL_STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const READY_BREAD: String = "barley_bread"
const SIMPLE_CLOTHES: String = "simple_clothes"
const DAILY_STEP: float = 0.05
const SHORTAGE_TARGET: float = 0.66
const FULL_NEEDS_TARGET: float = 0.99

var failures: int = 0
var fixture_day: int = 0
var person_id: String = ""
var person: CitizenData
var panel: CanvasLayer
var provider: Node
var runtime: Node
var created_provider: bool = false
var capture_directory: String = ""
var panel_refresh_generation: int = 0

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
	var generation_before: int = panel_refresh_generation
	var deadline: int = Time.get_ticks_msec() + 2000
	while panel_refresh_generation == generation_before and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(panel_refresh_generation > generation_before,
		"The open inspection panel completes a real RefreshTimer tick.")


func _on_panel_refresh_timeout() -> void:
	panel_refresh_generation += 1


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
		"clothing_allocations", "last_needs_results", "food_coverage_until",
		"satisfaction_last_minute"
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
	CitizenNeedsManager.food_coverage_until.clear()
	CitizenNeedsManager.satisfaction_last_minute.clear()

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

	Inventory.items.assign({READY_BREAD: 6})
	Inventory.items_changed.emit()
	var initial_deposit: Dictionary = provider.call("deposit_items_from_inventory", {READY_BREAD: 6})
	_expect(bool(initial_deposit.get("ok", false)) and int(provider.call("get_food_supply_points")) == 6
		and int(provider.call("get_clothing_item_count")) == 0
		and int(provider.get("items").get(READY_BREAD, 0)) == 6
		and not provider.get("items").has(SIMPLE_CLOTHES),
		"Six real bread units enter CityToolStorage, with no clothing available for the shortage days.")
	return true


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_window().size = Vector2i(1200, 675)
		await _frames(3)
	_expect(get_window().size == Vector2i(1200, 675)
		and get_viewport().get_visible_rect().size == Vector2(400, 225),
		"Live Needs are tested in the 1200x675 window at 400x225 logical size.")
	_snapshot()
	if not _prepare_fixture():
		await _finish()
		return

	panel = PANEL.instantiate() as CanvasLayer
	panel.summary_provider = Callable(CitizenNeedsManager, "get_person_needs_summary")
	add_child(panel)
	await _frames(2)
	var refresh_timer: Timer = panel.get_node("RefreshTimer") as Timer
	refresh_timer.timeout.connect(_on_panel_refresh_timeout)
	panel.open_for(person_id)
	await _wait_for_panel_refresh()
	_expect(panel.visible and str(panel.get("selected_id")) == person_id,
		"The actual inspection panel opens for the real resident ID.")
	_expect(_label("NameRow/NameLabel").text == "Live Needs Resident"
		and panel.find_child("DailyCheckLabel", true, false) == null
		and panel.find_child("ConditionLabel", true, false) == null
		and panel.find_child("ClothingDaysLabel", true, false) == null
		and panel.find_child("DailyChangeLabel", true, false) == null
		and _label("SatisfactionLabel").text == "Actual satisfaction: 91%",
		"The open panel shows current satisfaction and omits lower daily detail rows.")
	var initial_summary: Dictionary = CitizenNeedsManager.get_person_needs_summary(person_id)
	var initial_minute: int = fixture_day * 1440 + 8 * 60
	_expect(int(initial_summary.get("food_stock", -1)) == 5
		and int(initial_summary.get("clothing_stock", -1)) == 0
		and int(initial_summary.get("shelter_capacity", -1)) == 1
		and person.food_fulfilled
		and int(CitizenNeedsManager.food_coverage_until.get(person_id, -1)) == initial_minute + 1440,
		"The live allocator consumes one bread point and grants this resident 24 hours of coverage.")
	_expect(panel.find_child("CityStockLabel", true, false) == null
		and panel.find_child("CityStockRow", true, false) == null,
		"The individual card does not include City Supply.")
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
	for offset: int in range(6):
		var day: int = fixture_day + offset
		await _settle(day)
		if offset > 0:
			expected_satisfaction = move_toward(expected_satisfaction, SHORTAGE_TARGET, DAILY_STEP)
		var trend: String = "stable" if offset == 5 else "down"
		_assert_panel_state(day, expected_satisfaction, SHORTAGE_TARGET, trend, true, false,
			0, 5 - offset, 0, "Two needs met and clothing unavailable")
		if offset == 0:
			_expect(panel.find_child("ConditionLabel", true, false) == null,
				"The Needs card keeps condition feedback omitted after a real settlement.")
	_expect(is_equal_approx(person.satisfaction, SHORTAGE_TARGET)
		and str(CitizenNeedsManager.get_person_needs_summary(person_id).trend) == "stable",
		"Five elapsed days move actual satisfaction gradually to the 66% live target.")
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
	_assert_panel_state(fixture_day + 5, satisfaction_before, SHORTAGE_TARGET, "stable", true, false,
		0, 8, 1, "Same-day restock before the next settlement")
	_expect(CitizenNeedsManager.last_needs_results[person_id] == ledger_before
		and is_equal_approx(person.satisfaction, satisfaction_before)
		and not CitizenNeedsManager.clothing_allocations.has(person_id),
		"Same-day physical restock changes current stock only; the last daily result and actual satisfaction remain unchanged.")
	await _capture("restocked_before_settlement")
	await _assert_duplicate_day_is_noop("restocked_before_settlement")


func _test_clothing_issue_and_expiry() -> void:
	var issue_day: int = fixture_day + 6
	var issue_minute: int = issue_day * 1440
	var now_minute: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	_expect(issue_minute > now_minute and TimeComponentManager.advance_minutes(issue_minute - now_minute),
		"Advance real game minutes to the next day's clothing settlement.")
	await _wait_for_panel_refresh()
	await _settle(issue_day)
	var allocation: Dictionary = CitizenNeedsManager.clothing_allocations.get(person_id, {})
	_expect(allocation.get("item_id", "") == SIMPLE_CLOTHES
		and int(allocation.get("issued_day", -1)) == issue_day
		and int(allocation.get("expires_day", -1)) == issue_day + 6,
		"The next real settlement allocates the physical garment for seven inclusive days.")
	_assert_panel_state(issue_day, SHORTAGE_TARGET, FULL_NEEDS_TARGET, "up", true, true, 7,
		8, 0, "Garment allocated")
	_expect(is_equal_approx(person.satisfaction, SHORTAGE_TARGET)
		and bool(CitizenNeedsManager.last_needs_results[person_id].clothing)
		and CitizenNeedsManager.last_clothing_fulfilled_count == 1,
		"The physical garment is allocated at midnight; gradual recovery begins with elapsed time.")
	await _capture("garment_allocated")
	await _assert_duplicate_day_is_noop("after_garment_allocation")

	var expected_satisfaction: float = SHORTAGE_TARGET
	for offset: int in range(1, 8):
		var day: int = issue_day + offset
		await _settle(day)
		if offset < 7:
			expected_satisfaction = move_toward(expected_satisfaction, FULL_NEEDS_TARGET, DAILY_STEP)
			var trend: String = "stable" if is_equal_approx(expected_satisfaction, FULL_NEEDS_TARGET) else "up"
			_assert_panel_state(day, expected_satisfaction, FULL_NEEDS_TARGET, trend, true, true,
				7 - offset, 8 - offset, 0, "Garment remains valid without clothing restock")
		else:
			expected_satisfaction = move_toward(expected_satisfaction, FULL_NEEDS_TARGET, DAILY_STEP)
			_assert_panel_state(day, expected_satisfaction, SHORTAGE_TARGET, "down", true, false,
				0, 1, 0, "Garment expired without clothing restock")
			_expect(not CitizenNeedsManager.clothing_allocations.has(person_id)
				and CitizenNeedsManager.last_needs_results[person_id].missing.has("Clothing"),
				"At expiry, the real allocation is removed and Clothing is missing again.")
			await _capture("garment_expired")


func _settle(day: int) -> void:
	var target_minute: int = day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	var current_minute: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	if target_minute > current_minute:
		_expect(TimeComponentManager.advance_minutes(target_minute - current_minute),
			"The clock advances through real minutes to day %d." % day)
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
	var actual_food_display: String = _need_display("Food")
	var actual_clothing_display: String = _need_display("Clothing")
	var actual_shelter_display: String = _need_display("Shelter")
	var actual_satisfaction_text: String = _label("SatisfactionLabel").text
	_expect(_need_matches("Food", food)
		and _need_matches("Clothing", clothing)
		and _need_matches("Shelter", true)
		and actual_satisfaction_text == expected_satisfaction_text,
		"Panel live fields at %s: expected Food=%s, Clothing=%s, Shelter=true, Satisfaction='%s'; actual Food=%s, Clothing=%s, Shelter=%s, Satisfaction='%s'." % [
			stage, str(food), str(clothing), expected_satisfaction_text,			actual_food_display, actual_clothing_display, actual_shelter_display, actual_satisfaction_text,
		])
	_expect(panel.find_child("DailyCheckLabel", true, false) == null
		and panel.find_child("ClothingDaysLabel", true, false) == null
		and panel.find_child("DailyChangeLabel", true, false) == null
		and panel.find_child("ConditionLabel", true, false) == null,
		"The actual panel omits lower daily details: " + stage)
	_expect(panel.find_child("CityStockLabel", true, false) == null
		and panel.find_child("CityStockRow", true, false) == null,
		"The card stays free of City Supply while daily needs refresh: " + stage)



func _need_matches(need: String, value: Variant) -> bool:
	var card: Control = panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/DailyNeedsRow/" + need + "Status") as Control
	var label: Label = card.get_node("Status/Label") as Label
	var icon: TextureRect = card.get_node("Status/MetIcon") as TextureRect
	var met: bool = value != null and bool(value)
	var text: String = "Unknown" if value == null else ("Met" if met else "Missing")
	var texture: AtlasTexture = icon.texture as AtlasTexture
	return card.get_node("Label").text == need and icon.visible == met and label.visible == not met \
		and label.text == text and card.accessibility_name == need + ": " + text \
		and card.tooltip_text == need + ": " + text and card.get_node("Icon").tooltip_text == need + ": " + text \
		and card.get_node("Status").tooltip_text == need + ": " + text and icon.accessibility_name == need + ": " + text \
		and texture != null and texture.region == Rect2(84, 68, 8, 8) \
		and icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST


func _need_display(need: String) -> String:
	var card: Control = panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/DailyNeedsRow/" + need + "Status") as Control
	var label: Label = card.get_node("Status/Label") as Label
	var icon: TextureRect = card.get_node("Status/MetIcon") as TextureRect
	return "%s (icon=%s, accessible='%s')" % [label.text, str(icon.visible), card.accessibility_name]

func _label(path: String) -> Label:
	if not is_instance_valid(panel):
		return null
	var contents_path: String = "Root/Frame/Margin/Contents/"
	if not path.begins_with("NameRow/"):
		contents_path += "BodyScroll/Body/"
	return panel.get_node(contents_path + path) as Label


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
