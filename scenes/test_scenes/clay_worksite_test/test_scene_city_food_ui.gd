extends Node

const CONTENT: PackedScene = preload("res://scenes/test_scenes/fixtures/content_worksites_map.tscn")
const HOME: PackedScene = preload("res://scenes/player_home_interior/player_home_interior.tscn")
const NEED_FIELDS: Array[String] = [
	"last_processed_day", "last_food_processed_day", "last_food_fulfilled_count",
	"last_food_unfulfilled_count", "last_clothing_fulfilled_count", "last_clothing_unfulfilled_count",
	"last_shelter_capacity_fulfilled_count", "last_shelter_capacity_unfulfilled_count",
	"last_clothing_processed_day", "_processing_clothing", "clothing_allocations", "last_needs_results"
]

var failures: int = 0
var content: Node
var storage: Node
var player: Player
var area: Area2D
var menu: CanvasLayer
var saved: Dictionary = {}
var restored: bool = false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_snapshot()
	Inventory.items = {"barley_bread": 4, "roasted_drumstick": 1, "barley_grain_sack": 1}
	WorkerDatabase.workers_by_id.clear()
	CitizenManager.citizens_by_id.clear()
	var resident := CitizenData.new()
	resident.citizen_id = "food_ui_resident"
	resident.population_status = CitizenData.PopulationStatus.RESIDENT
	CitizenManager.add_citizen(resident)
	var linked := WorkerData.new()
	linked.worker_id = resident.citizen_id
	WorkerDatabase.workers_by_id[linked.worker_id] = linked
	var legacy := WorkerData.new()
	legacy.worker_id = "food_ui_legacy"
	WorkerDatabase.workers_by_id[legacy.worker_id] = legacy
	TimeComponentManager.is_paused = true
	get_tree().paused = false
	await _load_content()
	storage.items.clear()
	storage.units.clear()
	storage.food_portions.clear()
	storage._unit_sequence = 0
	var deposit: Dictionary = storage.deposit_items_from_inventory({"barley_bread": 4, "roasted_drumstick": 1})
	_expect(bool(deposit.ok), "The physical-food UI fixture deposits its whole items into the shared city provider.")
	await _open_menu()
	if not is_instance_valid(menu):
		_finish()
		return
	var summary: Dictionary = CitizenNeedsManager.get_food_supply_summary()
	_expect(summary.points == 6 and summary.daily_need == 2 and summary.days_remaining == 3,
		"The menu uses six ready-food points for two unique consumers; raw grain adds no meals.")
	_check_food_label(["6", "2", "3"])
	_check_clothing_label(["Clothing  0/2", "Reserve: 0", "Short: 2"])
	_expect(_whole_item_count("barley_grain_sack") == 0 and _whole_item_count("barley_bread") == 4
		and Inventory.items == {"barley_grain_sack": 1},
		"Raw ingredients stay personal while eligible food becomes visible city stock.")
	await _capture("city-food-available.png")
	for item_id: String in ["simple_clothes", "barley_bread"]:
		menu._show_item_info(item_id)
		await _frames(2)
		var info_rect: Rect2 = menu.item_info.get_global_rect()
		var footer: Control = menu.view.get_node("Margin/Content/Footer")
		_expect(absf(info_rect.get_center().x - get_viewport().get_visible_rect().get_center().x) <= 1,
			"Item info is horizontally centered.")
		_expect(info_rect.position.y > menu.view.get_global_rect().get_center().y
			and info_rect.end.y < footer.global_position.y
			and get_viewport().get_visible_rect().encloses(info_rect),
			"Item info stays in the lower center above the action buttons and inside the viewport.")
		await _capture("city-info-%s.png" % item_id)
	menu.item_info.clear_item()
	_expect(storage.items == {"barley_bread": 4, "roasted_drumstick": 1} and storage.food_portions.is_empty()
		and Inventory.items == {"barley_grain_sack": 1},
		"Opening and rendering the food summary does not consume, reserve or convert stock.")
	_expect(storage.try_add_item("barley_bread", 2), "A received food shipment updates the same provider.")
	await _frames(3)
	_expect(CitizenNeedsManager.get_food_supply_summary().points == 8 and _whole_item_count("barley_bread") == 6,
		"A city receipt refreshes food points and the visible whole-item grid together.")
	_check_food_label(["8", "2", "4"])
	var received_items: Dictionary = storage.items.duplicate(true)
	storage.items = {"barley_bread": 999999999, "simple_clothes": 999999999}
	storage.changed.emit()
	await _frames(3)
	_check_food_label(["999999999", "499999999"])
	_check_clothing_label(["Reserve: 999999999", "Clothing  0/2", "Ready tomorrow"])
	await _capture("city-food-long-value.png")
	storage.items = received_items
	storage.changed.emit()
	await _frames(3)
	area.close_menu()
	await _frames(3)
	var baseline_connections: int = TimeComponentManager.time_changed.get_connections().size()
	var baseline_needs_connections: int = CitizenNeedsManager.needs_changed.get_connections().size()
	for index: int in range(2):
		await _open_menu()
		area.close_menu()
		await _frames(3)
	_expect(TimeComponentManager.time_changed.get_connections().size() == baseline_connections,
		"Repeated menu use leaves no duplicate food-status time listeners.")
	_expect(CitizenNeedsManager.needs_changed.get_connections().size() == baseline_needs_connections,
		"Repeated menu use disconnects the clothing needs listener.")

	# One two-point whole food feeds a single resident over two days, without inventing items.
	WorkerDatabase.workers_by_id.clear()
	storage.items = {"roasted_drumstick": 1, "simple_clothes": 1}
	storage.food_portions.clear()
	CitizenNeedsManager.last_processed_day = -1
	CitizenNeedsManager.last_food_processed_day = -1
	CitizenNeedsManager.last_clothing_processed_day = -1
	CitizenNeedsManager.clothing_allocations = {}
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 23
	TimeComponentManager.current_minute = 59
	TimeComponentManager.advance_minutes(1)
	_expect(storage.items.is_empty() and storage.get_food_portion_points() == 1 and resident.food_fulfilled,
		"At midnight one point is eaten and one city-owned portion remains.")
	await _open_menu()
	_check_food_label(["Food  1 pt"])
	_check_clothing_label(["Clothing  1/1", "Reserve: 0"])
	_expect(menu.feedback.text != "No available items.",
		"An empty whole-item grid must not hide the remaining prepared food portion.")
	await _capture("city-food-portions.png")
	area.close_menu()
	await _frames(3)
	var retained: Node = storage
	var clothing_before_home: Dictionary = CitizenNeedsManager.clothing_allocations.duplicate(true)
	_expect(resident.clothing_fulfilled and clothing_before_home.size() == 1,
		"The same midnight issues one physical garment to the food recipient.")
	content.free()
	var home: Node = HOME.instantiate()
	add_child(home)
	await _frames(3)
	_expect(CitizenNeedsManager.get_food_supply_summary().points == 1,
		"Food portions remain available to daily needs while the player is at home.")
	home.free()
	await _load_content()
	_expect(storage == retained and storage.get_food_portion_points() == 1,
		"Returning to the city reuses the same prepared food portion without duplication.")
	_expect(CitizenNeedsManager.clothing_allocations == clothing_before_home
		and CitizenNeedsManager.get_clothing_supply_summary().covered_count == 1,
		"Clothing validity survives home and city transitions without issuing a second garment.")
	await _open_menu()
	_check_food_label(["Food  1 pt"])
	CitizenManager.citizens_by_id.clear()
	TimeComponentManager.time_changed.emit(TimeComponentManager.current_day,
		TimeComponentManager.current_hour, TimeComponentManager.current_minute, TimeComponentManager.current_weather)
	await _frames(3)
	var no_need: Dictionary = CitizenNeedsManager.get_food_supply_summary()
	_expect(no_need.points == 1 and no_need.daily_need == 0 and no_need.days_remaining == -1,
		"No residents or legacy workers means no daily need, without dividing by zero.")
	_check_food_label(["0 pt / day", "-"])
	_check_clothing_label(["Clothing  0/0"])
	await _capture("city-food-no-demand.png")
	CitizenManager.add_citizen(resident)
	_expect(storage.consume_food_points(1), "Use the final portion to exercise the visible shortage state.")
	await _frames(3)
	_check_food_label(["0 days", "Shortage"])
	await _capture("city-food-shortage.png")
	_expect(not bool(storage.withdraw_items_to_inventory({"roasted_drumstick": 1}).ok),
		"Prepared city food never provides a personal withdrawal path.")
	await _check_eight_person_clothing_summary()
	_finish()


func _check_eight_person_clothing_summary() -> void:
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	CitizenNeedsManager.clothing_allocations.clear()
	CityStockManager.shelter_capacity = 8
	storage.items = {"barley_bread": 32, "simple_clothes": 7}
	storage.food_portions.clear()
	var residents: Array[CitizenData] = []
	for index: int in range(8):
		var resident := CitizenData.new()
		resident.citizen_id = "supply_ui_person_%d" % index
		resident.population_status = CitizenData.PopulationStatus.RESIDENT
		resident.employment_status = CitizenData.EmploymentStatus.HIRED
		CitizenManager.add_citizen(resident)
		residents.append(resident)
	var linked := WorkerData.new()
	linked.worker_id = residents[7].citizen_id
	WorkerDatabase.workers_by_id[linked.worker_id] = linked
	TimeComponentManager.current_day += 1
	CitizenNeedsManager.process_daily_needs()
	await _frames(3)
	_check_clothing_label(["Clothing  7/8", "Reserve: 0", "Short: 1"])
	_expect(not residents[7].clothing_fulfilled and residents[7].food_fulfilled and residents[7].shelter_fulfilled,
		"The eighth person is missing only clothing in the rendered shortage case.")
	await _capture("city-supply-clothing-7-of-8.png")
	var before_items: Dictionary = storage.items.duplicate(true)
	var before_allocations: Dictionary = CitizenNeedsManager.clothing_allocations.duplicate(true)
	var before_day: int = CitizenNeedsManager.last_processed_day
	menu._refresh_view()
	CitizenNeedsManager.needs_changed.emit()
	await _frames(3)
	_expect(storage.items == before_items and CitizenNeedsManager.clothing_allocations == before_allocations
		and CitizenNeedsManager.last_processed_day == before_day,
		"Refreshing supply labels is read-only and cannot allocate clothing or evaluate another day.")
	Inventory.add_item("simple_clothes", 1)
	_expect(bool(storage.deposit_items_from_inventory({"simple_clothes": 1}).ok),
		"One physical garment can replenish the missing person's city supply.")
	await _frames(3)
	_check_clothing_label(["Clothing  7/8", "Reserve: 1", "Ready tomorrow"])
	_expect(not residents[7].clothing_fulfilled,
		"Available replacement stock must not be presented as coverage before the daily distribution.")
	await _capture("city-supply-clothing-ready.png")
	TimeComponentManager.current_day += 1
	CitizenNeedsManager.process_daily_needs()
	await _frames(3)
	_check_clothing_label(["Clothing  8/8", "Reserve: 0"])
	_expect(residents[7].clothing_fulfilled,
		"The next real daily evaluation fulfills the eighth person's clothing need.")
	await _capture("city-supply-clothing-covered.png")
	var newcomer := CitizenData.new()
	newcomer.citizen_id = "supply_ui_newcomer"
	newcomer.population_status = CitizenData.PopulationStatus.RESIDENT
	CitizenManager.add_citizen(newcomer)
	await _frames(3)
	_check_clothing_label(["Clothing  8/9", "Short: 1"])


func _load_content() -> void:
	content = CONTENT.instantiate()
	content.get_node("YSortWorld/Worksites").seed_playtest_hauler = false
	add_child(content)
	await _frames(3)
	player = content.get_node("YSortWorld/Player") as Player
	player.debug_disable_player_needs = true
	area = content.get_node("YSortWorld/Worksites/CityStorageArea") as Area2D
	storage = area.storage


func _open_menu() -> void:
	player.global_position = area.global_position + Vector2(0, 12)
	for index: int in range(3):
		await get_tree().physics_frame
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	await _frames(3)
	menu = area.menu
	_expect(is_instance_valid(menu), "Player E must open the physical City Storage food display.")


func _check_food_label(expected: Array[String]) -> void:
	var label: Label = menu.find_child("FoodSummary", true, false) as Label
	_expect(label != null and label.is_visible_in_tree(), "Physical City Storage exposes the visible FoodSummary.")
	if label == null:
		return
	for part: String in expected:
		_expect(label.text.to_lower().contains(part.to_lower()), "Food summary includes: " + part)
	var bounds: Rect2 = menu.view.get_global_rect()
	for control: Control in menu.find_children("*", "Control", true, false):
		_expect(control.tooltip_text.is_empty(), "City Storage has no native tooltip: " + str(control.name))
	for summary_label: Label in [menu.food_summary, menu.clothing_summary]:
		var icon_panel: Control = summary_label.get_parent().get_node("IconPanel")
		_expect(icon_panel.size == Vector2(24, 24)
			and absf(icon_panel.get_global_rect().get_center().y - summary_label.get_global_rect().get_center().y) <= 1.0,
			"Supply icon frames retain native size and align with their text block.")
	var food_panel: Control = menu.get_node("Root/CitySupplyPanel") as Control
	var viewport_bounds: Rect2 = get_viewport().get_visible_rect()
	_expect(food_panel.get_global_rect().encloses(label.get_global_rect())
		and viewport_bounds.encloses(food_panel.get_global_rect()) and viewport_bounds.encloses(bounds)
		and not food_panel.get_global_rect().intersects(bounds),
		"Food information and storage remain readable in separate panels inside the logical viewport.")
	_expect(label.size.y >= label.get_minimum_size().y and label.size.x >= label.get_minimum_size().x,
		"The current food status is not clipped by the label bounds.")
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	for line: String in label.text.split("\n"):
		for word: String in line.split(" "):
			_expect(font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= label.size.x,
				"Food status keeps each value intact when wrapping: " + word)
	_expect(label.get_visible_line_count() == label.get_line_count(),
		"All wrapped food status lines remain visible inside the panel.")
	_expect(menu.grid.get_child_count() >= 15, "Food status preserves the existing fifteen-slot storage grid.")
	_expect(menu.feedback.get_visible_line_count() == menu.feedback.get_line_count(),
		"The intake guidance and feedback remain fully visible.")


func _whole_item_count(item_id: String) -> int:
	for slot: ItemSlot in menu.grid.get_children():
		if slot._item_id == item_id:
			return slot._quantity
	return 0


func _check_clothing_label(expected: Array[String]) -> void:
	var label: Label = menu.find_child("ClothingSummary", true, false) as Label
	_expect(label != null and label.is_visible_in_tree(), "Physical City Storage exposes a visible clothing supply summary.")
	if label == null:
		return
	for part: String in expected:
		_expect(label.text.contains(part), "Clothing summary includes: " + part)
	var panel: Control = menu.get_node("Root/CitySupplyPanel") as Control
	var food_label: Label = menu.food_summary
	_expect(panel.get_global_rect().encloses(label.get_global_rect())
		and get_viewport().get_visible_rect().encloses(panel.get_global_rect())
		and not panel.get_global_rect().intersects(menu.view.get_global_rect())
		and not label.get_global_rect().intersects(food_label.get_global_rect())
		and panel.get_global_rect().position.x > menu.view.get_global_rect().end.x,
		"Food and clothing share City Supply to the right of storage, without overlap or overflow.")
	_expect(label.size.y >= label.get_minimum_size().y and label.get_visible_line_count() == label.get_line_count(),
		"Every clothing supply line fits without vertical clipping.")
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	for line: String in label.text.split("\n"):
		for word: String in line.split(" "):
			_expect(font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= label.size.x,
				"Clothing supply keeps each value intact when wrapping: " + word)


func _capture(filename: String) -> void:
	await _frames(2)
	var directory: String = OS.get_environment("TIP_CITY_FOOD_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_expect(get_viewport().get_texture().get_image().save_png(directory.path_join(filename)) == OK,
		"Saved rendered evidence: " + filename)


func _frames(count: int) -> void:
	for index: int in range(count):
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _snapshot() -> void:
	var previous: Node = WorkStateRuntime.get_node_or_null("CityToolStorage")
	saved = {"inventory": Inventory.items.duplicate(true), "citizens": CitizenManager.citizens_by_id.duplicate(),
		"workers": WorkerDatabase.workers_by_id.duplicate(), "provider": previous,
		"day": TimeComponentManager.current_day, "hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute, "weather": TimeComponentManager.current_weather,
		"paused": TimeComponentManager.is_paused, "tree_paused": get_tree().paused,
		"clothing": CityStockManager.clothing_supply, "shelter": CityStockManager.shelter_capacity}
	if is_instance_valid(previous):
		saved.items = previous.items.duplicate(true)
		saved.units = previous.units.duplicate(true)
		saved.portions = previous.food_portions.duplicate(true)
		saved.sequence = previous._unit_sequence
	for field: String in NEED_FIELDS:
		var value: Variant = CitizenNeedsManager.get(field)
		saved[field] = value.duplicate(true) if value is Dictionary else value


func _restore() -> void:
	if restored or saved.is_empty():
		return
	restored = true
	if is_instance_valid(area):
		area.close_menu()
	if is_instance_valid(content):
		content.free()
	Inventory.items = saved.inventory
	CitizenManager.citizens_by_id = saved.citizens
	WorkerDatabase.workers_by_id = saved.workers
	CityStockManager.clothing_supply = saved.clothing
	CityStockManager.shelter_capacity = saved.shelter
	if is_instance_valid(saved.provider):
		saved.provider.items = saved.items
		saved.provider.units = saved.units
		saved.provider.food_portions = saved.portions
		saved.provider._unit_sequence = saved.sequence
	elif is_instance_valid(storage):
		storage.free()
	TimeComponentManager.current_day = saved.day
	TimeComponentManager.current_hour = saved.hour
	TimeComponentManager.current_minute = saved.minute
	TimeComponentManager.current_weather = saved.weather
	TimeComponentManager.is_paused = saved.paused
	get_tree().paused = saved.tree_paused
	for field: String in NEED_FIELDS:
		CitizenNeedsManager.set(field, saved[field])


func _finish() -> void:
	_restore()
	# Let queued UI and renderer cleanup settle after freeing the content scenes.
	await _frames(2)
	print("CityFoodUITest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)


func _exit_tree() -> void:
	_restore()
