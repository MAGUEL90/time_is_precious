extends Node

const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
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
var city_ui: RaidUI
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
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	# Prevent unrelated random immigration from interrupting this UI fixture.
	ImmigrationManager.base_daily_chance = -1.0
	get_tree().paused = false
	await _load_content()
	if not is_instance_valid(storage) or not is_instance_valid(area) or not is_instance_valid(city_ui):
		_expect(false, "The actual map exposes City Storage and City Hub.")
		await _finish()
		return
	storage.items.clear()
	storage.units.clear()
	storage.food_portions.clear()
	storage._unit_sequence = 0
	CityStockManager.shelter_capacity = 0
	await _open_menu()
	if not is_instance_valid(menu):
		await _finish()
		return
	await _deposit_items({"barley_bread": 4, "roasted_drumstick": 1})
	_expect(_whole_item_count("barley_grain_sack") == 0 and _whole_item_count("barley_bread") == 4
		and Inventory.items == {"barley_grain_sack": 1},
		"The actual deposit UI keeps raw ingredients personal and displays deposited ready food.")
	_expect(not menu.get_node("Root/CitySupplyPanel").visible and menu.grid.get_child_count() >= 15,
		"Physical City Storage keeps its fifteen-slot grid and the retired supply panel hidden.")
	_expect(menu.feedback.get_visible_line_count() == menu.feedback.get_line_count(),
		"Physical storage feedback remains fully visible.")
	for slot: ItemSlot in menu.grid.get_children():
		if slot._item_id.is_empty():
			continue
		slot.mouse_entered.emit()
		await _frames(2)
		for control: Control in menu.find_children("*", "Control", true, false):
			_expect(not (control is ItemInfoPanel and control.is_visible_in_tree()), "Hovering city stock does not open item descriptions.")
			_expect(control.get_tooltip().is_empty(), "City stock controls have no native tooltip.")
		slot.mouse_exited.emit()
	area.close_menu()
	await _frames(3)
	var baseline_connections: int = TimeComponentManager.time_changed.get_connections().size()
	var baseline_needs_connections: int = CitizenNeedsManager.needs_changed.get_connections().size()
	for index: int in range(2):
		await _open_menu()
		if is_instance_valid(menu):
			area.close_menu()
		await _frames(3)
	_expect(TimeComponentManager.time_changed.get_connections().size() == baseline_connections,
		"Repeated physical storage use leaves no duplicate time listeners.")
	_expect(CitizenNeedsManager.needs_changed.get_connections().size() == baseline_needs_connections,
		"Repeated physical storage use leaves no duplicate needs listeners.")

	await _open_supply()
	var summary: Dictionary = CitizenNeedsManager.get_food_supply_summary()
	_expect(summary.points == 6 and summary.daily_need == 2 and summary.days_remaining == 3,
		"City Hub reads six ready-food points for two unique consumers; raw grain adds no meals.")
	_check_food_label(["6", "2", "3"])
	_check_clothing_label(["Clothing  0 / 2", "Reserve  0", "Short: 2"])
	_check_supply_label(city_ui.supply_shelter, ["Shelter  0 / 1", "Short 1"])
	await _capture("city-food-available.png")
	_expect(storage.items == {"barley_bread": 4, "roasted_drumstick": 1} and storage.food_portions.is_empty()
		and Inventory.items == {"barley_grain_sack": 1},
		"Opening and rendering City Hub does not consume, reserve or convert stock.")
	_expect(storage.try_add_item("barley_bread", 2), "A received food shipment updates the same provider.")
	await _frames(3)
	_expect(CitizenNeedsManager.get_food_supply_summary().points == 8,
		"A city receipt refreshes the shared food points.")
	_check_food_label(["8", "2", "4"])
	var received_items: Dictionary = storage.items.duplicate(true)
	storage.items = {"barley_bread": 999999999, "simple_clothes": 999999999}
	storage.changed.emit()
	await _frames(3)
	_check_food_label(["999999999", "499999999"])
	_check_clothing_label(["Reserve  999999999", "Clothing  0 / 2", "Ready tomorrow"])
	await _capture("city-food-long-value.png")
	storage.items = received_items
	storage.changed.emit()
	await _frames(3)
	city_ui.close_details()
	await _open_menu()
	_expect(is_instance_valid(menu) and _whole_item_count("barley_bread") == 6,
		"Reopening physical City Storage shows the received whole items.")
	if is_instance_valid(menu):
		area.close_menu()
	await _frames(3)

	# One two-point whole food feeds a single resident over two days, without inventing items.
	WorkerDatabase.workers_by_id.clear()
	storage.items = {"roasted_drumstick": 1, "simple_clothes": 1}
	storage.food_portions.clear()
	CitizenNeedsManager.last_processed_day = -1
	CitizenNeedsManager.last_food_processed_day = -1
	CitizenNeedsManager.last_clothing_processed_day = -1
	CitizenNeedsManager.clothing_allocations = {}
	var minutes_to_midnight: int = 1440 - TimeComponentManager.current_hour * 60 - TimeComponentManager.current_minute
	_expect(TimeComponentManager.advance_minutes(minutes_to_midnight), "Advance the actual clock to midnight.")
	_expect(storage.items.is_empty() and storage.get_food_portion_points() == 1 and resident.food_fulfilled,
		"At midnight one point is eaten and one city-owned portion remains.")
	await _open_menu()
	_expect(is_instance_valid(menu) and menu.feedback.text == "Prepared food remains.",
		"An empty whole-item grid must not hide the remaining prepared food portion.")
	if is_instance_valid(menu):
		area.close_menu()
	await _frames(3)
	await _open_supply()
	_check_food_label(["Food  1 pt"])
	_check_clothing_label(["Clothing  1 / 1", "Reserve  0"])
	await _capture("city-food-portions.png")
	city_ui.close_details()
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
	await _open_supply()
	_check_food_label(["Food  1 pt"])
	CitizenManager.citizens_by_id.clear()
	TimeComponentManager.time_changed.emit(TimeComponentManager.current_day,
		TimeComponentManager.current_hour, TimeComponentManager.current_minute, TimeComponentManager.current_weather)
	await _frames(3)
	var no_need: Dictionary = CitizenNeedsManager.get_food_supply_summary()
	_expect(no_need.points == 1 and no_need.daily_need == 0 and no_need.days_remaining == -1,
		"No residents or legacy workers means no daily need, without dividing by zero.")
	_check_food_label(["0 pt / day", "No daily demand"])
	_check_clothing_label(["Clothing  0 / 0"])
	await _capture("city-food-no-demand.png")
	CitizenManager.add_citizen(resident)
	_expect(storage.consume_food_points(1), "Use the final portion to exercise the visible shortage state.")
	await _frames(3)
	_check_food_label(["0 days", "Shortage"])
	await _capture("city-food-shortage.png")
	_expect(not bool(storage.withdraw_items_to_inventory({"roasted_drumstick": 1}).ok),
		"Prepared city food never provides a personal withdrawal path.")
	await _check_eight_person_clothing_summary()
	await _finish()


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
	_expect(TimeComponentManager.advance_minutes(1440), "Advance the actual clock to the clothing-shortage day.")
	await _frames(3)
	_check_clothing_label(["Clothing  7 / 8", "Reserve  0", "Short: 1"])
	_check_supply_label(city_ui.supply_shelter, ["Shelter  8 / 8", "Covered"])
	_expect(not residents[7].clothing_fulfilled and residents[7].food_fulfilled and residents[7].shelter_fulfilled,
		"The eighth person is missing only clothing in the rendered shortage case.")
	await _capture("city-supply-clothing-7-of-8.png")
	var before_items: Dictionary = storage.items.duplicate(true)
	var before_allocations: Dictionary = CitizenNeedsManager.clothing_allocations.duplicate(true)
	var before_day: int = CitizenNeedsManager.last_processed_day
	city_ui.refresh()
	CitizenNeedsManager.needs_changed.emit()
	await _frames(3)
	_expect(storage.items == before_items and CitizenNeedsManager.clothing_allocations == before_allocations
		and CitizenNeedsManager.last_processed_day == before_day,
		"Refreshing supply labels is read-only and cannot allocate clothing or evaluate another day.")
	city_ui.close_details()
	Inventory.add_item("simple_clothes", 1)
	await _open_menu()
	if is_instance_valid(menu):
		await _deposit_items({"simple_clothes": 1})
		area.close_menu()
	await _frames(3)
	await _open_supply()
	_check_clothing_label(["Clothing  7 / 8", "Reserve  1", "Ready tomorrow"])
	_expect(not residents[7].clothing_fulfilled,
		"Available replacement stock must not be presented as coverage before the daily distribution.")
	await _capture("city-supply-clothing-ready.png")
	_expect(TimeComponentManager.advance_minutes(1440), "Advance the actual clock to the clothing-recovery day.")
	await _frames(3)
	_check_clothing_label(["Clothing  8 / 8", "Reserve  0"])
	_expect(residents[7].clothing_fulfilled,
		"The next real daily evaluation fulfills the eighth person's clothing need.")
	await _capture("city-supply-clothing-covered.png")
	var newcomer := CitizenData.new()
	newcomer.citizen_id = "supply_ui_newcomer"
	newcomer.population_status = CitizenData.PopulationStatus.RESIDENT
	CitizenManager.add_citizen(newcomer)
	await _frames(3)
	_check_clothing_label(["Clothing  8 / 9", "Short: 1"])


func _load_content() -> void:
	content = CONTENT.instantiate()
	# Isolate the two explicit fixture consumers; normal startup applicants are
	# covered by the main-map hiring test and would also consume food here.
	content.get_node("YSortWorld/InitialWorksites").enable_initial_applicant = false
	add_child(content)
	await _frames(3)
	player = content.get_node("YSortWorld/Player") as Player
	player.debug_disable_player_needs = true
	area = content.get_node("YSortWorld/WorkerRuntime/CityStorageArea") as Area2D
	storage = area.storage
	city_ui = content.get_node("RaidBootstrap").raid_ui as RaidUI


func _open_menu() -> void:
	menu = null
	# The current warehouse access shape is offset from the area origin.
	player.global_position = area.get_node("CollisionShape2D").global_position
	for index: int in range(5):
		await get_tree().physics_frame
	_expect(area.has_player_access() and player.current_interactable == area,
		"The player is inside the actual City Storage interaction area.")
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventAction.new()
	event.action = "interact"
	get_viewport().push_input(event)
	await _frames(3)
	menu = area.menu
	_expect(is_instance_valid(menu), "Player E opens physical City Storage on the actual map.")


func _deposit_items(selection: Dictionary) -> void:
	menu.deposit_button.pressed.emit()
	await _frames(3)
	var transfer: ItemTransferUI = menu.transfer_ui
	_expect(is_instance_valid(transfer) and transfer.visible, "Physical City Storage opens the deposit dialog.")
	if not is_instance_valid(transfer):
		return
	for item_id: String in selection:
		var found: ItemSlot
		for child: Node in transfer.grid_container.get_children():
			if child is ItemSlot and child._item_id == item_id:
				found = child as ItemSlot
				break
		_expect(found != null, "The deposit dialog exposes " + item_id + ".")
		if found != null:
			for index: int in range(int(selection[item_id])):
				found.pressed.emit()
	_expect(transfer.selected_items == selection, "The deposit dialog stages the exact requested physical goods.")
	transfer.confirm_button.pressed.emit()
	await _frames(3)
	transfer.back_button.pressed.emit()
	await _frames(3)


func _open_supply() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_C
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventKey.new()
	event.keycode = KEY_C
	get_viewport().push_input(event)
	await _frames(3)
	_expect(city_ui.details_panel.visible, "C opens the actual City Hub.")
	var supply_button: Button = city_ui.hub_tabs.get_child(1) as Button
	supply_button.pressed.emit()
	await _frames(3)
	_expect(city_ui.supply_view.is_visible_in_tree(), "The Supply tab opens the actual City Hub summaries.")


func _check_food_label(expected: Array[String]) -> void:
	_check_supply_label(city_ui.supply_food, expected)


func _whole_item_count(item_id: String) -> int:
	for slot: ItemSlot in menu.grid.get_children():
		if slot._item_id == item_id:
			return slot._quantity
	return 0


func _check_clothing_label(expected: Array[String]) -> void:
	_check_supply_label(city_ui.supply_clothing, expected)


func _check_supply_label(label: Label, expected: Array[String]) -> void:
	_expect(is_instance_valid(label) and label.is_visible_in_tree(), "City Hub exposes the visible supply summary.")
	if not is_instance_valid(label):
		return
	for part: String in expected:
		_expect(label.text.to_lower().contains(part.to_lower()), "Supply summary includes: " + part)
	var panel: Control = city_ui.details_panel
	_expect(panel.get_global_rect().encloses(label.get_global_rect())
		and get_viewport().get_visible_rect().encloses(panel.get_global_rect()),
		"The supply summary and City Hub fit in the logical viewport.")
	var icon: TextureRect = label.get_parent().get_node("IconFrame/Icon") as TextureRect
	_expect(icon.size == Vector2(16, 16) and icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
		"City Hub supply icons retain their native pixel size and nearest filtering.")
	_expect(label.size.y >= label.get_minimum_size().y and label.get_visible_line_count() == label.get_line_count(),
		"Every supply line fits without vertical clipping.")
	var cards: Array[Control] = [city_ui.supply_food.get_parent(), city_ui.supply_clothing.get_parent(), city_ui.supply_shelter.get_parent()]
	for first: int in range(cards.size()):
		for second: int in range(first + 1, cards.size()):
			_expect(not cards[first].get_global_rect().intersects(cards[second].get_global_rect()),
				"Food, clothing and shelter supply cards remain separate.")
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	for line: String in label.text.split("\n"):
		for word: String in line.split(" "):
			_expect(font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= label.size.x,
				"City Hub supply keeps each value intact: " + word)


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
		"runtime_children": WorkStateRuntime.get_children(),
		"day": TimeComponentManager.current_day, "hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute, "weather": TimeComponentManager.current_weather,
		"paused": TimeComponentManager.is_paused, "clock_processing": TimeComponentManager.is_processing(),
		"immigration_chance": ImmigrationManager.base_daily_chance, "tree_paused": get_tree().paused,
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
	if is_instance_valid(city_ui):
		city_ui.close_details()
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
	var runtime_children: Array[Node] = WorkStateRuntime.get_children()
	runtime_children.reverse()
	for child: Node in runtime_children:
		if not saved.runtime_children.has(child):
			child.free()
	TimeComponentManager.current_day = saved.day
	TimeComponentManager.current_hour = saved.hour
	TimeComponentManager.current_minute = saved.minute
	TimeComponentManager.current_weather = saved.weather
	TimeComponentManager.is_paused = saved.paused
	TimeComponentManager.set_process(saved.clock_processing)
	ImmigrationManager.base_daily_chance = saved.immigration_chance
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
