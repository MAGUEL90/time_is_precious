extends Node

## Real New Game, visible Debug control, midnight settlement and isolated saves.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const CLEAN_SAVE: String = "user://debug_resident_needs/clean.json"
const SUPPLIED_SAVE: String = "user://debug_resident_needs/supplied.json"
const FIRST_ID: String = "initial_workshop_laborer"
const SECOND_ID: String = "initial_worksite_hauler"
const THIRD_ID: String = "initial_city_storage_hauler"
var launched: bool = false
var failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _frames(count: int = 3) -> void:
	for _frame: int in range(count):
		await get_tree().process_frame

func _capture(stage: String) -> void:
	var directory: String = OS.get_environment("TIP_RESIDENT_NEEDS_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_expect(get_viewport().get_texture().get_image().save_png(directory.path_join(stage + ".png")) == OK, "Capture " + stage)

func _click(button: Button) -> void:
	var scale_to_window: Vector2 = Vector2(get_window().size) / get_viewport().get_visible_rect().size
	var point: Vector2 = button.get_global_rect().get_center() * scale_to_window
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = true
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(event)
	await _frames(2)
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = false
	get_viewport().push_input(event)
	await _frames(3)

func _run() -> void:
	if OS.get_name() == "Linux":
		var root: String = OS.get_environment("XDG_DATA_HOME")
		var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
		_expect(root.is_absolute_path() and user_root.begins_with(root.simplify_path().trim_suffix("/") + "/"), "Use a disposable XDG_DATA_HOME.")
	for path: String in [CLEAN_SAVE, SUPPLIED_SAVE]:
		for suffix: String in ["", ".bak", ".tmp", ".pending"]:
			_expect(not FileAccess.file_exists(path + suffix), "Do not overwrite any existing checkpoint: " + path + suffix)
	if failures > 0:
		get_tree().quit(1)
		return
	get_tree().current_scene = null
	var menu: Node = MENU.instantiate()
	menu.checkpoint_file.path = CLEAN_SAVE
	menu.session_started.connect(func(continued: bool): launched = not continued)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	menu.new_game_button.pressed.emit()
	for _frame: int in range(1200):
		if launched:
			break
		await get_tree().process_frame
	_expect(launched, "The actual Start Menu launches New Game.")
	if not launched:
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	var city: Node = get_tree().current_scene
	var player: Player = city.get_node("YSortWorld/Player")
	var debug: Node = city.get_node("TimeDebugOverlay")
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var store: Node = WorkStateRuntime.get_node("CitySave")
	var house: Node = city.get_node("YSortWorld/CitizenHousePlot").construction
	var original_house_phase: String = house.phase
	_expect(CitizenManager.get_all_residents().size() == 3 and CitizenManager.get_all_applicants().size() == 3, "The genuine new game starts with three eligible residents.")
	_expect(storage.get_food_supply_points() == 0 and storage.get_clothing_item_count() == 0 and CityStockManager.shelter_capacity == 0, "Food, clothing and shelter do not appear automatically.")
	# This fixture exercises recovery from the prior 50% edge explicitly;
	# the new-game starter buffer is tested separately without this adjustment.
	for id: String in [FIRST_ID, SECOND_ID, THIRD_ID]:
		CitizenManager.get_citizen(id).satisfaction = 0.5
	debug.panel.show()
	await _frames()
	_expect(storage.get_food_supply_points() == 0 and storage.get_clothing_item_count() == 0 and CityStockManager.shelter_capacity == 0, "Opening Debug does not grant resident needs.")
	debug.panel.hide()
	_expect(store.save_checkpoint(), "A clean checkpoint saves before using debug: " + store.last_error)

	# Test-only player protection prevents a collapse while preserving resident needs.
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	var now: int = TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	_expect(TimeComponentManager.advance_minutes(1440 - now + 8 * 60), "The real clock reaches day one at 08:00.")
	var first: CitizenData = CitizenManager.get_citizen(FIRST_ID)
	var second: CitizenData = CitizenManager.get_citizen(SECOND_ID)
	var third: CitizenData = CitizenManager.get_citizen(THIRD_ID)
	_expect(is_equal_approx(first.satisfaction, 0.45) and is_equal_approx(second.satisfaction, 0.45) and is_equal_approx(third.satisfaction, 0.45) and CitizenManager.get_all_applicants().is_empty(), "Without the debug supply, ordinary unmet needs produce the original 45% empty-board state.")
	var before_inventory: Dictionary = Inventory.items.duplicate(true)
	var before_day: int = TimeComponentManager.current_day
	var observed: Dictionary = {"count": 0, "complete": false, "nested": true, "save_blocked": false}
	var on_supply: Callable = func() -> void:
		observed.count += 1
		observed.complete = storage.get_food_supply_points() == 21 and storage.get_clothing_item_count() == 3 and CityStockManager.shelter_capacity == 3
		observed.nested = debug.give_resident_needs()
		observed.save_blocked = store.snapshot.busy_reason(city) == "Wait for the current transaction."
	storage.changed.connect(on_supply)
	debug.panel.show()
	var button: Button = debug.resident_needs_button
	var scroll: ScrollContainer = button.get_parent().get_parent() as ScrollContainer
	scroll.ensure_control_visible(button)
	await _frames(4)
	debug._refresh_controls()
	_expect(button.is_visible_in_tree() and not button.disabled and get_viewport().get_visible_rect().encloses(button.get_global_rect()), "The labeled resident-needs Debug button is visible and clickable.")
	await _capture("needs-before")
	if DisplayServer.get_name() == "headless":
		button.pressed.emit()
	else:
		await _click(button)
	await _capture("needs-after")
	storage.changed.disconnect(on_supply)
	_expect(observed.count == 1 and observed.complete and not observed.nested and observed.save_blocked, "One atomic storage notification sees all needs; reentry and save are guarded.")
	_expect(storage.get_food_supply_points() == 21 and storage.get_clothing_item_count() == 3 and CityStockManager.shelter_capacity == 3, "The actual button supplies seven days of food, spare clothes and shelter.")
	_expect(first.satisfaction == 0.45 and second.satisfaction == 0.45 and third.satisfaction == 0.45 and TimeComponentManager.current_day == before_day and CitizenManager.get_all_applicants().is_empty(), "Supply does not change satisfaction, time or applicant eligibility before midnight.")
	_expect(Inventory.items == before_inventory and CitizenManager.get_all_residents().size() == 3 and house.phase == original_house_phase, "The debug action creates no personal stock, residents or houses.")
	_expect(debug.resident_needs_status.text.to_lower().contains("sleep") and debug.resident_needs_status.text.contains("midnight"), "The UI explains settlement timing and sleep-save persistence.")
	_expect(scroll.get_global_rect().encloses(debug.resident_needs_status.get_global_rect()), "The confirmation and save information remain visible beside the button.")
	_expect(scroll.get_global_rect().encloses(button.get_global_rect()), "The button remains visible after its confirmation changes size.")
	var supplied_items: Dictionary = storage.items.duplicate(true)
	_expect(not debug.give_resident_needs() and storage.items == supplied_items and CityStockManager.shelter_capacity == 3, "Repeating the button without consumption adds nothing.")
	_expect(storage.try_add_item("date_cluster", 1) and storage.try_add_item("simple_clothes", 1) and CityStockManager.add_shelter_capacity(1), "The fixture can create surplus using the normal stock APIs.")
	var surplus_items: Dictionary = storage.items.duplicate(true)
	_expect(not debug.give_resident_needs() and storage.items == surplus_items and CityStockManager.shelter_capacity == 4, "Existing food, clothes and shelter surplus are never reduced.")
	storage.items = supplied_items.duplicate(true)
	CityStockManager.shelter_capacity = 1
	storage._transfer_in_progress = true
	_expect(not debug.give_resident_needs() and storage.items == supplied_items and CityStockManager.shelter_capacity == 1, "A busy City Storage transaction rejects an otherwise needed top-up.")
	storage._transfer_in_progress = false
	storage.items["simple_clothes"] = -1 # Test-only invalid state for all-or-nothing validation.
	var invalid_items: Dictionary = storage.items.duplicate(true)
	CityStockManager.shelter_capacity = 1
	_expect(not debug.give_resident_needs() and storage.items == invalid_items and CityStockManager.shelter_capacity == 1, "Invalid stock cannot partially top up food, clothing or shelter.")
	storage.items = supplied_items.duplicate(true)
	CityStockManager.shelter_capacity = 3
	debug.panel.hide()
	store.disk.path = SUPPLIED_SAVE
	_expect(store.save_checkpoint(), "Explicit debug supplies save in the ordinary checkpoint: " + store.last_error)
	store.disk.path = CLEAN_SAVE
	_expect(store.load_checkpoint(), "The earlier clean checkpoint loads: " + store.last_error)
	await _frames(4)
	_expect(storage.get_food_supply_points() == 0 and storage.get_clothing_item_count() == 0 and CityStockManager.shelter_capacity == 0 and CitizenManager.get_citizen(FIRST_ID).satisfaction == 0.5, "Loading the clean save restores its original state without debug supplies.")
	store.disk.path = SUPPLIED_SAVE
	_expect(store.load_checkpoint(), "The supplied checkpoint loads: " + store.last_error)
	await _frames(4)
	_expect(TimeComponentManager.current_day == 1 and storage.get_food_supply_points() == 21 and storage.get_clothing_item_count() == 3 and CityStockManager.shelter_capacity == 3 and CitizenManager.get_citizen(FIRST_ID).satisfaction == 0.45, "Loading the supplied save retains actual stock and shelter without settling needs early.")
	debug.set_player_guard(true) # Optional existing Debug control; resident needs remain active.
	debug._refresh_controls()
	_expect(not debug.step_buttons[1].disabled, "The actual Debug +1d control is available.")
	debug.step_buttons[1].pressed.emit()
	_expect(TimeComponentManager.current_day == 2 and TimeComponentManager.current_hour == 8, "The actual +1d control crosses the next midnight.")
	first = CitizenManager.get_citizen(FIRST_ID)
	second = CitizenManager.get_citizen(SECOND_ID)
	third = CitizenManager.get_citizen(THIRD_ID)
	_expect(first.are_basic_needs_fulfilled() and second.are_basic_needs_fulfilled() and third.are_basic_needs_fulfilled() and is_equal_approx(first.satisfaction, 0.5) and is_equal_approx(second.satisfaction, 0.5) and is_equal_approx(third.satisfaction, 0.5), "Normal daily settlement fulfills all three needs and restores 45% to 50%.")
	_expect(CitizenManager.get_all_applicants().size() == 3 and storage.get_food_supply_points() == 18 and CitizenNeedsManager.clothing_allocations.size() == 3, "The Job Board becomes eligible again while real food is consumed and clothes are allocated.")
	_expect(storage.get_clothing_item_count() == 0 and CityStockManager.shelter_capacity == 3 and house.phase == original_house_phase, "No housing or extra clothing is invented by settlement.")
	_expect(debug.give_resident_needs() and storage.get_food_supply_points() == 21 and storage.get_clothing_item_count() == 3, "A later click tops up consumed food and keeps one spare outfit per consumer.")
	_expect(store.save_checkpoint() and store.load_checkpoint(), "Post-settlement debug stock and normal needs can save and reload.")
	await _frames(4)
	_expect(storage.get_food_supply_points() == 21 and storage.get_clothing_item_count() == 3 and CitizenNeedsManager.clothing_allocations.size() == 3 and is_equal_approx(CitizenManager.get_citizen(FIRST_ID).satisfaction, 0.5), "Reload preserves stock, allocations and satisfaction exactly.")
	store.disk.path = CLEAN_SAVE
	_expect(store.load_checkpoint(), "The original clean checkpoint remains loadable.")
	await _frames(3)
	_expect(CitizenManager.leave_city(FIRST_ID) and CitizenManager.leave_city(SECOND_ID) and CitizenManager.leave_city(THIRD_ID), "The test can remove all three nonworkers.")
	var empty_before: Dictionary = storage.items.duplicate(true)
	_expect(not debug.give_resident_needs() and storage.items == empty_before and CityStockManager.shelter_capacity == 0, "No residents or workers means no debug grant.")
	var linked_person := CitizenData.new()
	linked_person.citizen_id = "debug_linked_fixture"
	linked_person.population_status = CitizenData.PopulationStatus.RESIDENT
	linked_person.employment_status = CitizenData.EmploymentStatus.HIRED
	CitizenManager.add_citizen(linked_person)
	var linked_worker := WorkerData.new()
	linked_worker.worker_id = linked_person.citizen_id
	WorkerDatabase.workers_by_id[linked_worker.worker_id] = linked_worker
	var legacy_worker := WorkerData.new()
	legacy_worker.worker_id = "debug_unlinked_fixture"
	WorkerDatabase.workers_by_id[legacy_worker.worker_id] = legacy_worker
	_expect(debug.give_resident_needs() and storage.get_food_supply_points() == 14 and storage.get_clothing_item_count() == 2 and CityStockManager.shelter_capacity == 2, "One linked resident plus one legacy worker receive two shares, never three.")
	var unemployed := CitizenData.new()
	unemployed.citizen_id = "debug_unemployed_fixture"
	unemployed.population_status = CitizenData.PopulationStatus.RESIDENT
	unemployed.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	unemployed.satisfaction = 0.45
	CitizenManager.add_citizen(unemployed)
	_expect(debug.give_resident_needs() and storage.get_food_supply_points() == 21 and storage.get_clothing_item_count() == 3 and CityStockManager.shelter_capacity == 3, "A later resident increases only the missing debug supplies.")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	now = TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	_expect(TimeComponentManager.advance_minutes(1440 - now), "The mixed recipient fixture reaches midnight.")
	_expect(linked_person.are_basic_needs_fulfilled() and legacy_worker.are_basic_needs_fulfilled() and is_equal_approx(linked_person.satisfaction, 0.55) and is_equal_approx(legacy_worker.satisfaction, 0.55), "Normal settlement fulfills linked and unlinked workers once each.")
	_expect(unemployed.are_basic_needs_fulfilled() and is_equal_approx(unemployed.satisfaction, 0.5) and CitizenManager.get_all_applicants().has(unemployed), "A previously unemployed resident applies through normal midnight evaluation after needs recover.")
	print("DebugResidentNeedsTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
