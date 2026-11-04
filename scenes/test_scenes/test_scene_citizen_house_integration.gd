extends Node

## Isolated main-map fixture: real prepaid hires and house/workshop owners.
## Player needs are disabled only to isolate the multi-day construction test.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const SHIFT_DRIVER = preload("res://scenes/test_scenes/workshop_shift_test_driver.gd")
const HOUSE_ID: String = "construction:citizen_house_1"
const FIRST_ID: String = "house_integration_first"
const REPLACEMENT_ID: String = "house_integration_replacement"
const HOUSE_REQUIREMENTS: Dictionary = {"wood_log": 4, "clay_lump": 8, "reed_bundle": 6}
const WORKSHOP_REQUIREMENTS: Dictionary = {"wood_log": 6, "clay_lump": 12, "reed_bundle": 8}
const HOUSE_WORK: int = 2880
const CLEARING_WORK: int = 180

var failures: int = 0
var completed: bool = false
var content: Node
var house: Node2D
var construction: Node
var workshop_construction: Node
var player: Player
var visuals: Node2D
var capture_dir: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 14
	TimeComponentManager.current_minute = 50
	TimeComponentManager.current_weather = "clear"
	TimeComponentManager.emit_time_signal()
	capture_dir = OS.get_environment("TIP_PLOT_CAPTURE_DIR")
	content = CONTENT.instantiate()
	add_child(content)
	for _frame: int in range(3):
		await get_tree().process_frame
	player = content.get_node_or_null("YSortWorld/Player") as Player
	house = content.get_node_or_null("YSortWorld/CitizenHousePlot") as Node2D
	var workshop: Node = content.get_node_or_null("YSortWorld/WorkshopPlot")
	visuals = content.get_node_or_null("YSortWorld/WorkerRuntime/WorkerVisuals") as Node2D
	_expect(player != null and house != null and workshop != null and visuals != null,
		"The authored main map provides the player, citizen house, workshop and worker visuals.")
	if player == null or house == null or workshop == null or visuals == null:
		await _finish()
		return
	construction = house.get("construction") as Node
	workshop_construction = workshop.get("construction") as Node
	_expect(construction != null and workshop_construction != null and construction != workshop_construction,
		"The house and workshop have distinct retained construction owners.")
	if construction == null or workshop_construction == null:
		await _finish()
		return
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	visuals.set_process(false)
	await _exercise_house()
	await _finish()


func _exercise_house() -> void:
	_expect(str(construction.order_id) == HOUSE_ID and construction.phase == "uncleared"
		and construction.get_requirements() == HOUSE_REQUIREMENTS,
		"The real house starts uncleared with its own identity and four/eight/six material costs.")
	_expect(workshop_construction.phase == "uncleared"
		and workshop_construction.get_requirements() == WORKSHOP_REQUIREMENTS,
		"The separate workshop retains its original starting phase and costs.")
	_expect(_count_npcs(house) == 0, "The house rubble has no keeper or other NPC child.")
	_expect(WorkerDatabase.get_all_workers().is_empty() and Inventory.items.is_empty(),
		"The isolated fixture starts without hired workers or granted items.")
	var initial_workshop_stock: Dictionary = WorkShopStorage.items.duplicate(true)
	var shelter_before: int = CityStockManager.shelter_capacity
	_expect(CityStockManager.add_shelter_capacity(4), "A separate existing shelter-capacity sentinel is installed.")
	var baseline_capacity: int = shelter_before + 4
	_expect(CityStockManager.shelter_capacity == baseline_capacity, "The pre-existing shelter sentinel is intact.")
	Inventory.add_item("shekel", 8)
	var first: WorkerData = _hire_fixture(FIRST_ID)
	var replacement: WorkerData = _hire_fixture(REPLACEMENT_ID)
	if first == null or replacement == null:
		return
	_expect(int(Inventory.items.get("shekel", 0)) == 2,
		"Both real nine-day contracts debit only their quoted three-shekel wallet prices.")

	var manual_preview: Dictionary = construction.get_clearing_preview([] as Array[String], true)
	var mixed_preview: Dictionary = construction.get_clearing_preview([FIRST_ID] as Array[String], true)
	_expect(bool(manual_preview.get("can_start", false)) and not bool(mixed_preview.get("can_start", true))
		and construction.phase == "uncleared" and not first.is_reserved(),
		"Player cleaning is available without assigning a worker, and mixed selection is rejected.")
	if not await _open_house_menu("house-rubble"):
		return
	var menu: WorkshopPlotUI = house.get("menu") as WorkshopPlotUI
	var title: Label = menu.get_node("Root/Center/Window/Margin/MainVBox/TitleHeader/TitleLabel") as Label
	_expect(title.text == "CLEAR HOUSE SITE" and menu.player_button.visible
		and menu.build_button.text == "Start Cleaning" and not player.can_move and get_tree().paused,
		"Physical E opens the house-cleaning menu with Assign Player available.")
	menu._on_player_selected(true)
	_expect(menu._use_player and menu.player_button.button_pressed,
		"Player selection is retained in the house cleaning menu.")
	menu._on_player_selected(false)
	await _capture("house-cleaning-menu")
	_prepare_departure_actor(FIRST_ID)
	menu._on_worker_assignment_next_requested([FIRST_ID] as Array[String])
	_expect(not menu.build_button.disabled, "The hired worker is selectable for house cleaning.")
	_expect(menu.duration_label.text == "3h 0m work, 1 worker", "The cleaning quote identifies working hours rather than elapsed days.")
	menu.build_button.pressed.emit()
	_expect(construction.phase == "clearing" and first.current_order_id == HOUSE_ID
		and first.get_linked_citizen().employment_status == CitizenData.EmploymentStatus.ASSIGNED
		and not get_tree().paused,
		"The menu starts the real paid worker assignment and releases the player's modal.")
	if construction.phase != "clearing":
		return
	_expect(_is_pending_approach(first, ":clearing"), "The cleaner starts on a physical route to this house.")
	if not _advance(3, "Clock advances while the cleaner is travelling."):
		return
	_expect(construction._remaining_work_units() == CLEARING_WORK,
		"Three prearrival minutes grant no cleaning progress.")
	if not _drive_arrival(first, ":clearing"):
		return
	if not _advance(7, "The arrived cleaner works until 15:00."):
		return
	var cleaning_at_close: int = construction._remaining_work_units()
	_expect(cleaning_at_close == CLEARING_WORK - 7
		and int(first.physical_approach.get("arrival_minute", -1)) == WorkerData.PLOT_DEPARTURE_PENDING,
		"Exactly seven arrived minutes count before the 15:00 departure.")
	if not _advance(16 * 60 - 1, "The clock advances to 06:59."):
		return
	_expect(construction._remaining_work_units() == cleaning_at_close
		and TimeComponentManager.current_hour == 6 and TimeComponentManager.current_minute == 59,
		"The overnight interval grants no house progress.")
	if not _advance(1, "The clock reaches the next 07:00 shift."):
		return
	_expect(construction._remaining_work_units() == cleaning_at_close
		and not first.physical_approach.get("arrived", false),
		"07:00 alone cannot bypass the cleaner's return journey.")
	if not _advance(1, "One morning minute elapses before physical return."):
		return
	_expect(construction._remaining_work_units() == cleaning_at_close,
		"The next shift grants no progress while the cleaner is still away.")
	if not _drive_arrival(first, ":clearing"):
		return
	if not _advance(cleaning_at_close, "The returned cleaner completes the remaining work."):
		return
	_expect(construction.phase == "empty" and not first.is_reserved()
		and first.get_linked_citizen().employment_status == CitizenData.EmploymentStatus.HIRED
		and CityStockManager.shelter_capacity == baseline_capacity
		and not house.get_node("SiteHouse").visible and not house.get_node("FinishedHouse").visible
		and not content.get_node("AuthoredMap/YSortWorld/ToBeClean1").visible
		and _authored_cleared_footprint_visible(),
		"All 180 cleaning minutes finish once, release the worker, preserve shelter and show the original authored footprint.")
	if construction.phase != "empty":
		return

	Inventory.add_bulk_item({"wood_log": 6, "clay_lump": 10, "reed_bundle": 8})
	var material_stock: Dictionary = Inventory.items.duplicate(true)
	var quote: Dictionary = construction.get_preview([FIRST_ID] as Array[String])
	_expect(bool(quote.get("can_start", false)) and int(quote.get("duration_minutes", 0)) == HOUSE_WORK,
		"One paid builder is quoted the full 2,880 worker-minute house build.")
	if not await _open_house_menu("house-cleared"):
		return
	menu = house.get("menu") as WorkshopPlotUI
	title = menu.get_node("Root/Center/Window/Margin/MainVBox/TitleHeader/TitleLabel") as Label
	_expect(title.text == "BUILD HOUSE" and menu.build_button.text == "Build House",
		"The cleared site opens the house construction menu through physical E.")
	await _capture("house-build-menu")
	_prepare_departure_actor(FIRST_ID)
	menu._on_worker_assignment_next_requested([FIRST_ID] as Array[String])
	_expect(not menu.build_button.disabled, "A paid builder and the listed materials enable construction.")
	_expect(menu.duration_label.text == "48h 0m work, 1 builder", "The house quote displays working hours without implying two calendar days.")
	await _capture("house-build-selected")
	menu.build_button.pressed.emit()
	_expect(construction.phase == "building" and construction.work_total_units == HOUSE_WORK
		and first.current_order_id == HOUSE_ID,
		"The real menu starts precisely 2,880 worker-minutes of house construction.")
	if construction.phase != "building":
		return
	for item_id: String in HOUSE_REQUIREMENTS:
		_expect(int(material_stock.get(item_id, 0)) - int(Inventory.items.get(item_id, 0)) == int(HOUSE_REQUIREMENTS[item_id]),
			"Construction consumes the %s requirement exactly once." % item_id)
	var paid_stock: Dictionary = Inventory.items.duplicate(true)
	_expect(not bool(construction.start_build([FIRST_ID] as Array[String]).get("success", true))
		and Inventory.items == paid_stock and CityStockManager.shelter_capacity == baseline_capacity,
		"A repeated build request charges nothing and adds no early shelter.")
	_expect(_is_pending_approach(first, ":building"), "The builder is routed to the house for its new task.")
	if not _advance(2, "The builder's prearrival time advances."):
		return
	_expect(construction._remaining_work_units() == HOUSE_WORK,
		"Construction remains frozen until the assigned builder physically arrives.")
	if not _drive_arrival(first, ":building") or not _advance(37, "The first builder contributes 37 minutes."):
		return
	var retained_work: int = construction._remaining_work_units()
	_expect(retained_work == HOUSE_WORK - 37, "The first builder's exact progress is retained.")
	first.get_linked_citizen().satisfaction = 0.0
	WorkerDatabase.resign_idle_workers_at_zero()
	_expect(not WorkerDatabase.has_worker_data(FIRST_ID) and WorkerDatabase.dismissed_workers.has(FIRST_ID)
		and CitizenManager.get_citizen(FIRST_ID).employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and construction.phase == "building" and construction.worker_ids.is_empty()
		and construction.get_replacement_slots() == 1 and construction._remaining_work_units() == retained_work,
		"Zero Satisfaction resigns the builder while preserving the same unfinished work and vacancy.")
	if not _advance(30, "Time advances while the house has no builder."):
		return
	_expect(construction._remaining_work_units() == retained_work and Inventory.items == paid_stock
		and CityStockManager.shelter_capacity == baseline_capacity,
		"Workerless construction is frozen and keeps all paid materials without adding shelter.")
	if not await _open_house_menu("house-paused"):
		return
	menu = house.get("menu") as WorkshopPlotUI
	_expect(menu.replacement_button.visible, "The real progress panel exposes the empty builder slot.")
	_prepare_departure_actor(REPLACEMENT_ID)
	menu._on_worker_assignment_next_requested([REPLACEMENT_ID] as Array[String])
	_expect(construction.worker_ids == [REPLACEMENT_ID] and replacement.current_order_id == HOUSE_ID
		and construction._remaining_work_units() == retained_work and Inventory.items == paid_stock,
		"The selected paid replacement inherits exact progress without another material charge.")
	if construction.worker_ids != [REPLACEMENT_ID]:
		return
	_expect(_is_pending_approach(replacement, ":building"), "The replacement receives its own house approach.")
	if not _advance(2, "The replacement travels before arriving."):
		return
	_expect(construction._remaining_work_units() == retained_work,
		"A replacement cannot advance the house while travelling.")
	if not _drive_arrival(replacement, ":building"):
		return
	var completed_to_final_minute: bool = SHIFT_DRIVER.work_minutes(retained_work - 1, visuals, [REPLACEMENT_ID] as Array[String])
	_expect(completed_to_final_minute and construction.phase == "building"
		and construction._remaining_work_units() == 1 and CityStockManager.shelter_capacity == baseline_capacity,
		"The replacement returns each shift and the house grants no shelter one minute early.")
	if not completed_to_final_minute or construction.phase != "building":
		return
	_expect(SHIFT_DRIVER.work_minutes(1, visuals, [REPLACEMENT_ID] as Array[String]),
		"The final paid worker-minute advances.")
	_expect(construction.phase == "built" and CityStockManager.shelter_capacity == baseline_capacity + 3
		and not replacement.is_reserved()
		and replacement.get_linked_citizen().employment_status == CitizenData.EmploymentStatus.HIRED
		and house.get_node("FinishedHouse").visible and not house.has_node("BuiltWorkshop"),
		"Completing the house adds exactly three shelter places and releases its builder.")
	if construction.phase != "built":
		return
	for _repeat: int in range(3):
		construction.changed.emit()
	_expect(_advance(60, "Time can continue after house completion."), "Post-completion clock advance succeeds.")
	TimeComponentManager.emit_time_signal()
	_expect(CityStockManager.shelter_capacity == baseline_capacity + 3 and Inventory.items == paid_stock,
		"Repeated state notifications and later time neither duplicate shelter nor charge materials again.")
	_expect(workshop_construction.phase == "uncleared" and workshop_construction.worker_ids.is_empty()
		and workshop_construction.get_requirements() == WORKSHOP_REQUIREMENTS
		and WorkShopStorage.items == initial_workshop_stock and WorkManager.active_orders.is_empty(),
		"House construction leaves the workshop's state, inputs and production orders untouched.")
	await _capture("house-finished")
	completed = true


func _hire_fixture(id: String) -> WorkerData:
	var citizen := CitizenData.new()
	citizen.citizen_id = id
	citizen.display_name = id
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	citizen.satisfaction = 0.95
	citizen.visual_profile = VisualProfile.new()
	CitizenManager.add_citizen(citizen)
	_expect(CitizenManager.register_applicant(id, WorkerData.Profession.LABORER),
		"The fixture resident applies through CitizenManager: " + id)
	var before: int = int(Inventory.items.get("shekel", 0))
	var price: int = WorkerDatabase.get_contract_price(WorkerData.Profession.LABORER, 9)
	var worker: WorkerData = WorkerDatabase.hire_applicant(id, 1, 9)
	_expect(price == 3 and worker != null and before - int(Inventory.items.get("shekel", 0)) == price
		and worker.payroll_contract_days == 9 and not worker.is_payroll_blocked(),
		"The applicant receives a real, immediately paid nine-day contract: " + id)
	return worker


func _open_house_menu(capture_name: String) -> bool:
	var access: Node2D = house.get_node_or_null("InteractableComponent") as Node2D
	if access == null:
		_expect(false, "The house has its authored physical interaction area.")
		return false
	player.global_position = access.global_position + Vector2(0, 4)
	for _frame: int in range(4):
		await get_tree().physics_frame
	await get_tree().process_frame
	await _capture(capture_name)
	_expect(house.has_player_access() and player.current_interactable == house,
		"Standing beside the house makes its real rubble interaction available.")
	if not house.has_player_access() or player.current_interactable != house:
		return false
	await _press_interact()
	var opened: bool = is_instance_valid(house.get("menu")) and house.get("menu") is WorkshopPlotUI
	_expect(opened, "Pressing E opens the house menu directly without NPC dialogue.")
	return opened


func _prepare_departure_actor(id: String) -> void:
	var marker: Node2D = visuals.get_parent().get_node("WorkerDeparture/NearSpawn") as Node2D
	var actor: Node2D = visuals.ensure_actor(id, marker.global_position - Vector2(0, 16))
	actor.global_position = marker.global_position - Vector2(0, 16)


func _is_pending_approach(worker: WorkerData, suffix: String) -> bool:
	return worker != null and worker.matches_physical_approach("plot", HOUSE_ID + suffix, HOUSE_ID) \
		and not worker.physical_approach.get("arrived", false) \
		and Vector2(worker.physical_approach.get("target", Vector2.ZERO)) == house.get_worker_entry_position()


func _drive_arrival(worker: WorkerData, suffix: String) -> bool:
	if worker == null or worker.physical_approach.is_empty():
		_expect(false, "An assigned house worker has a physical approach.")
		return false
	var start: Vector2 = worker.physical_approach.position
	var target: Vector2 = worker.physical_approach.target
	var was_departing: bool = int(worker.physical_approach.get("arrival_minute", -1)) == WorkerData.PLOT_DEPARTURE_PENDING
	var moved_from_start: bool = false
	for _frame: int in range(4000):
		if worker.physical_approach.get("arrived", false):
			break
		SHIFT_DRIVER.visual_frame(visuals, 0.1)
		if Vector2(worker.physical_approach.position).distance_to(start) > 0.1:
			moved_from_start = true
	var arrived: bool = worker.matches_physical_approach("plot", HOUSE_ID + suffix, HOUSE_ID) \
		and worker.physical_approach.get("arrived", false) \
		and Vector2(worker.physical_approach.position).distance_to(target) <= 0.1 \
		and int(worker.physical_approach.arrival_minute) == _now()
	_expect(arrived and (start.distance_to(target) <= 0.1 or start.distance_to(worker.physical_approach.position) > 0.1),
		"The worker actually follows the house route and records its arrival before work.")
	_expect(not was_departing or moved_from_start,
		"A worker returning after shift close physically departs the plot before arriving again.")
	return arrived and (not was_departing or moved_from_start)


func _advance(minutes: int, message: String) -> bool:
	var advanced: bool = TimeComponentManager.advance_minutes(minutes)
	_expect(advanced, message)
	return advanced


func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute


func _count_npcs(node: Node) -> int:
	var count: int = 1 if node is NPCBase else 0
	for child: Node in node.get_children():
		count += _count_npcs(child)
	return count


func _authored_cleared_footprint_visible() -> bool:
	var binding: Node = content.get_node("ReviewHouseBinding")
	var layer: TileMapLayer = content.get_node("AuthoredMap/Ground/Setelah Cleaning") as TileMapLayer
	var original_cells: Array = binding.get("_cells")
	if original_cells.size() != 9:
		return false
	for entry: Dictionary in original_cells:
		var cell: Vector2i = entry.cell
		if layer.get_cell_source_id(cell) != entry.source or layer.get_cell_atlas_coords(cell) != entry.atlas \
				or layer.get_cell_alternative_tile(cell) != entry.alternative:
			return false
	return true


func _press_interact() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = "interact"
	event.pressed = false
	get_viewport().push_input(event)
	await get_tree().process_frame


func _capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_dir.path_join(name + ".png"))


func _finish() -> void:
	get_tree().paused = false
	if is_instance_valid(content):
		content.queue_free()
		await get_tree().process_frame
	_expect(completed, "The complete house lifecycle must run before PASS.")
	print("CitizenHouseIntegrationTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
