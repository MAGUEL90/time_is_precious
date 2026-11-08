extends "res://scenes/test_scenes/test_scene_citizen_house_integration.gd"

## Real plot/menu, clock and Player; all supplies and citizens are fixtures.
## Run in an isolated XDG_DATA_HOME. The critical case is last because it starts
## the normal asynchronous faint/Nightmare transition.
var player_worker: WorkerData
var store: Node
var block_after_minutes: int = -1


func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	TimeComponentManager.current_day = 0
	# Hire through the real board rules while it is open; then stage the actual
	# manual work at night without claiming the player needs a worker shift.
	TimeComponentManager.current_hour = 14
	TimeComponentManager.current_minute = 0
	TimeComponentManager.current_weather = "clear"
	TimeComponentManager.emit_time_signal()
	capture_dir = OS.get_environment("TIP_PLOT_CAPTURE_DIR")
	content = CONTENT.instantiate()
	add_child(content)
	for _frame: int in range(3):
		await get_tree().process_frame
	player = content.get_node_or_null("YSortWorld/Player") as Player
	house = content.get_node_or_null("YSortWorld/CitizenHousePlot") as Node2D
	visuals = content.get_node_or_null("YSortWorld/WorkerRuntime/WorkerVisuals") as Node2D
	store = WorkStateRuntime.get_node_or_null("CitySave")
	_expect(player != null and house != null and visuals != null and store != null,
		"The real map supplies player, house, worker visuals and save owner.")
	if player == null or house == null or visuals == null or store == null:
		await _finish()
		return
	construction = house.get("construction") as Node
	player.debug_disable_player_needs = false
	player.debug_disable_fatigue = false
	player.hunger = 0.10
	player.fatigue = 0.10
	visuals.set_process(false)
	Inventory.add_item("shekel", 4)
	player_worker = _hire_fixture(FIRST_ID)
	if player_worker == null:
		await _finish()
		return
	TimeComponentManager.current_hour = 20
	TimeComponentManager.emit_time_signal()
	await _test_player_and_worker_routes()
	if failures == 0:
		await _test_critical_interruption()
	completed = failures == 0
	await _finish()


func _test_player_and_worker_routes() -> void:
	var shelter_before: int = CityStockManager.shelter_capacity
	var initial_inventory: Dictionary = Inventory.items.duplicate(true)
	var marker: Node2D = content.get_node("AuthoredMap/YSortWorld/ToBeClean1")
	var footprint: TileMapLayer = content.get_node("AuthoredMap/Ground/Setelah Cleaning")
	var authored_footprint_cells: int = _authored_footprint_cell_count(footprint, marker.global_position)
	var has_authored_footprint: bool = authored_footprint_cells == 9
	_expect(authored_footprint_cells == 0 or has_authored_footprint,
		"The authored map uses either an empty fallback or a complete 3x3 house footprint.")
	_expect(marker.visible and not house.get_node("ToBeClean").visible
		and not house.get_node("SiteHouse").visible,
		"Before cleaning, only the authored rubble marker is shown for the house site.")
	_expect(not construction.get_clearing_preview([FIRST_ID] as Array[String], true).can_start,
		"Player and worker cannot both be selected for the same manual cleaning.")
	if not await _open_house_menu("house-player-rubble"):
		return
	var menu: WorkshopPlotUI = house.get("menu") as WorkshopPlotUI
	_expect(menu.player_button.visible and not menu.player_button.button_pressed,
		"Physical E opens cleaning with Assign Player visible and initially unselected.")
	menu.player_button.button_pressed = true
	_expect(menu._use_player and menu._selected_worker_ids.is_empty() and not menu.build_button.disabled,
		"Selecting the player enables cleaning without also selecting a worker.")
	await _capture("house-player-cleaning-selected")
	menu.assign_workers_button.pressed.emit()
	await get_tree().process_frame
	var assignment: Node = menu.get("_worker_assignment_menu") as Node
	_expect(assignment != null, "The normal worker selector opens from the house menu.")
	if assignment == null:
		return
	assignment.get_node("Root/Center/TextureWindow/Margin/MainVBox/OverviewPage/Footer/BackButton").pressed.emit()
	await get_tree().process_frame
	_expect(is_instance_valid(house.menu) and get_tree().paused and menu._use_player,
		"Back from an unchanged worker selector returns to the selected player.")
	menu.assign_workers_button.pressed.emit()
	await get_tree().process_frame
	assignment = menu.get("_worker_assignment_menu") as Node
	if assignment == null or not await _select_worker_in_menu(assignment, FIRST_ID):
		return
	_expect(not menu._use_player and menu._selected_worker_ids == [FIRST_ID],
		"Choosing a worker clears the player selection rather than mixing assignments.")
	assignment.get_node("Root/Center/TextureWindow/Margin/MainVBox/OverviewPage/Footer/BackButton").pressed.emit()
	await get_tree().process_frame
	menu.player_button.button_pressed = true
	_expect(menu._use_player and menu._selected_worker_ids.is_empty(),
		"Switching back to the player clears the previously selected worker.")
	menu.close_menu()
	await get_tree().process_frame
	_expect(not get_tree().paused and player.can_move and construction.phase == "uncleared"
		and Inventory.items == initial_inventory and not player_worker.is_reserved(),
		"Closing the draft leaves work, stock, reservation and movement unchanged.")
	if not await _open_house_menu("house-player-cleaning"):
		return
	menu = house.get("menu") as WorkshopPlotUI
	_expect(not menu.player_button.button_pressed and not menu._use_player,
		"Reopening does not retain a stale player draft.")
	player.fatigue = player.fatigue_critical_threshold
	menu.player_button.button_pressed = true
	var refused_at: int = _now()
	menu.build_button.pressed.emit()
	_expect(_now() == refused_at and construction.phase == "uncleared" and is_instance_valid(house.menu),
		"A critically tired player cannot start cleaning or advance time.")
	player.fatigue = 0.10
	menu.player_button.button_pressed = false
	menu.player_button.button_pressed = true
	var reentrant_start: int = _now()
	construction.changed.connect(_close_while_cleaning_starts, CONNECT_ONE_SHOT)
	menu.build_button.pressed.emit()
	await house.clearing_finished
	_expect(_now() == reentrant_start and construction.phase == "uncleared"
		and not construction.is_player_work_active() and not is_instance_valid(house.menu)
		and not get_tree().paused and player.can_move and Inventory.items == initial_inventory,
		"A close callback during cleaning startup safely cancels without advancing time or stranding the modal.")
	if not await _open_house_menu("house-player-menu-queued-during-start"):
		return
	menu = house.get("menu") as WorkshopPlotUI
	menu.player_button.button_pressed = true
	var queued_menu_start: int = _now()
	construction.changed.connect(_queue_free_menu_while_cleaning_starts, CONNECT_ONE_SHOT)
	menu.build_button.pressed.emit()
	await house.clearing_finished
	_expect(_now() == queued_menu_start and construction.phase == "uncleared"
		and not construction.is_player_work_active() and not is_instance_valid(house.menu)
		and not get_tree().paused and player.can_move and Inventory.items == initial_inventory,
		"A menu queued for deletion by a startup callback cancels cleaning without advancing time or stranding the modal.")
	if not await _open_house_menu("house-player-after-start-cancel"):
		return
	menu = house.get("menu") as WorkshopPlotUI
	menu.player_button.button_pressed = true
	var start: int = _now()
	var start_hunger: float = player.hunger
	var start_fatigue: float = player.fatigue
	menu.build_button.pressed.emit()
	await house.clearing_finished
	_expect(_now() - start == CLEARING_WORK and construction.phase == "empty",
		"Player cleans for exactly 180 minutes at night without a worker shift.")
	_expect(not marker.visible and not house.get_node("ToBeClean").visible
		and house.get_node("SiteHouse").visible == (not has_authored_footprint)
		and _authored_footprint_cell_count(footprint, marker.global_position) == authored_footprint_cells,
		"After cleaning, the house shows its complete authored footprint or the local SiteHouse fallback.")
	await _capture("house-player-cleaning-complete")
	_expect(_needs_drained_once(start_hunger, start_fatigue, CLEARING_WORK)
		and Inventory.items == initial_inventory and not player_worker.is_reserved(),
		"Manual cleaning advances the existing Belly/Energy clock once without using material or worker.")
	if construction.phase != "empty":
		return
	_expect(not construction.start_build([FIRST_ID] as Array[String], true).success,
		"Player plus worker is rejected for house construction without charging stock.")
	Inventory.add_bulk_item({"wood_log": 6, "clay_lump": 10, "reed_bundle": 8})
	var material_stock: Dictionary = Inventory.items.duplicate(true)
	if not await _open_house_menu("house-player-build"):
		return
	menu = house.get("menu") as WorkshopPlotUI
	_expect(menu.player_button.visible and not menu.player_button.button_pressed,
		"The cleared house exposes an unselected Assign Player action.")
	menu.player_button.button_pressed = true
	_expect(menu._use_player and not menu.build_button.disabled,
		"Selecting player with the materials enables house construction.")
	await _capture("house-player-build-selected")
	start = _now()
	start_hunger = player.hunger
	start_fatigue = player.fatigue
	menu.build_button.pressed.emit()
	if not await _wait_manual_session("Starting the player's build"):
		return
	var remaining: int = construction._remaining_work_units()
	var paid_stock: Dictionary = Inventory.items.duplicate(true)
	var paid_once: bool = true
	for item_id: String in HOUSE_REQUIREMENTS:
		paid_once = paid_once and int(material_stock.get(item_id, 0)) - int(paid_stock.get(item_id, 0)) == int(HOUSE_REQUIREMENTS[item_id])
	_expect(_now() - start == 180 and construction.phase == "building" and remaining == HOUSE_WORK - 180
		and construction.worker_ids.is_empty() and not construction.is_player_work_active(),
		"One player build session performs exactly three hours of work across midnight and then pauses.")
	_expect(not marker.visible and house.get_node("SiteHouse").visible == (not has_authored_footprint)
		and _authored_footprint_cell_count(footprint, marker.global_position) == authored_footprint_cells,
		"While the paid house is built, it uses a complete authored footprint or local site art.")
	_expect(_needs_drained_once(start_hunger, start_fatigue, 180) and paid_once
		and CityStockManager.shelter_capacity == shelter_before,
		"The session charges normal time-based needs and each material once, without premature shelter.")
	if construction.phase != "building":
		return
	if not await _open_house_menu("house-player-paused"):
		return
	menu = house.get("menu") as WorkshopPlotUI
	_expect(menu.player_resume_button.visible and menu.replacement_button.visible,
		"A paused house offers both player continuation and worker replacement.")
	menu.close_menu()
	await get_tree().process_frame
	_expect(construction._remaining_work_units() == remaining and Inventory.items == paid_stock,
		"Closing the progress page does not lose work or charge materials again.")
	if not await _open_house_menu("house-player-resume"):
		return
	menu = house.get("menu") as WorkshopPlotUI
	start = _now()
	start_hunger = player.hunger
	start_fatigue = player.fatigue
	block_after_minutes = 5
	TimeComponentManager.time_changed.connect(_block_clock_after_minutes)
	menu.player_resume_button.pressed.emit()
	var stopped: bool = await _wait_manual_session("Resuming and interrupting player work")
	TimeComponentManager.time_changed.disconnect(_block_clock_after_minutes)
	store._busy = false
	if not stopped:
		return
	_expect(_now() - start == 5 and construction._remaining_work_units() == remaining - 5
		and _needs_drained_once(start_hunger, start_fatigue, 5) and Inventory.items == paid_stock,
		"A clock interruption preserves the five completed minutes and never repeats the payment.")
	remaining = construction._remaining_work_units()
	if not await _open_house_menu("house-player-close-during-work"):
		return
	menu = house.get("menu") as WorkshopPlotUI
	start = _now()
	start_hunger = player.hunger
	start_fatigue = player.fatigue
	block_after_minutes = 5
	TimeComponentManager.time_changed.connect(_close_house_after_minutes)
	menu.player_resume_button.pressed.emit()
	stopped = await _wait_manual_session("Closing player work from a time callback")
	TimeComponentManager.time_changed.disconnect(_close_house_after_minutes)
	if not stopped:
		return
	_expect(_now() - start == 5 and construction._remaining_work_units() == remaining - 5
		and _needs_drained_once(start_hunger, start_fatigue, 5) and Inventory.items == paid_stock
		and player.can_move and not get_tree().paused and not is_instance_valid(house.menu),
		"Closing during work preserves five minutes, paid materials and normal needs, then unlocks controls.")
	remaining = construction._remaining_work_units()
	if not await _open_house_menu("house-player-replace"):
		return
	menu = house.get("menu") as WorkshopPlotUI
	menu.replacement_button.pressed.emit()
	await get_tree().process_frame
	assignment = menu.get("_worker_assignment_menu") as Node
	if assignment == null or not await _select_worker_in_menu(assignment, FIRST_ID):
		return
	_prepare_departure_actor(FIRST_ID)
	assignment.get_node("Root/Center/TextureWindow/Margin/MainVBox/OverviewPage/Footer/NextButton").pressed.emit()
	await get_tree().process_frame
	_expect(construction.worker_ids == [FIRST_ID] and player_worker.current_order_id == HOUSE_ID
		and construction._remaining_work_units() == remaining and Inventory.items == paid_stock,
		"A paid worker takes over the player's exact partial build without another material charge.")
	if construction.worker_ids != [FIRST_ID]:
		return
	if is_instance_valid(house.menu):
		house.menu.close_menu()
	await get_tree().process_frame
	# Only the worker is on duty over these days; avoid an unrelated player faint
	# while driving the long shift regression. Manual sessions above use real needs.
	player.debug_disable_player_needs = true
	var worked: bool = SHIFT_DRIVER.work_minutes(remaining - 1, visuals, [FIRST_ID] as Array[String])
	_expect(worked and construction.phase == "building" and construction._remaining_work_units() == 1
		and CityStockManager.shelter_capacity == shelter_before,
		"The replacement observes worker shifts and shelter is absent one work-minute before completion.")
	if not worked or construction.phase != "building":
		return
	_expect(SHIFT_DRIVER.work_minutes(1, visuals, [FIRST_ID] as Array[String])
		and construction.phase == "built" and CityStockManager.shelter_capacity == shelter_before + 3,
		"A worker can complete the player's paid construction and grant three places once.")
	for _index: int in range(3):
		construction.changed.emit()
	TimeComponentManager.emit_time_signal()
	_expect(CityStockManager.shelter_capacity == shelter_before + 3 and Inventory.items == paid_stock,
		"Repeated completion notifications do not duplicate shelter or charge materials.")
	player.debug_disable_player_needs = false


func _authored_footprint_cell_count(footprint: TileMapLayer, marker_global_position: Vector2) -> int:
	var center: Vector2i = footprint.local_to_map(footprint.to_local(marker_global_position))
	var count: int = 0
	for y: int in range(center.y - 1, center.y + 2):
		for x: int in range(center.x - 1, center.x + 2):
			if footprint.get_cell_source_id(Vector2i(x, y)) >= 0:
				count += 1
	return count


func _close_while_cleaning_starts() -> void:
	if construction.phase == "clearing" and construction.is_player_work_active():
		house.close_menu()


func _queue_free_menu_while_cleaning_starts() -> void:
	if construction.phase == "clearing" and construction.is_player_work_active() and is_instance_valid(house.menu):
		house.menu.queue_free()


func _test_critical_interruption() -> void:
	# Start an independent cleared-house case after the complete takeover journey.
	# Reset this authored fixture's state directly; this is not a gameplay action.
	construction.phase = "empty"
	construction.worker_ids.clear()
	construction.worker_capacity = 0
	construction.work_total_units = 0
	construction.started_at = 0
	construction.completes_at = 0
	construction._latest_time = _now()
	construction.payroll_work_remainder = 0
	construction.changed.emit()
	for _frame: int in range(3):
		await get_tree().physics_frame
	Inventory.add_bulk_item({"wood_log": 4, "clay_lump": 8, "reed_bundle": 6})
	var shelter_before: int = CityStockManager.shelter_capacity
	var nightmare: NightmareWorld = content.get_node("YSortWorld/NightmareWorld") as NightmareWorld
	_expect(nightmare != null, "The real map provides the Nightmare flow for a critical player.")
	var time_debug: Node = content.get_node_or_null("TimeDebugOverlay")
	if time_debug != null:
		time_debug.set_player_guard(false)
		time_debug.set_process(false)
	player.hunger = 0.20
	player.fatigue = player.fatigue_critical_threshold - 0.0025
	if not await _open_house_menu("house-player-critical"):
		return
	var menu: WorkshopPlotUI = house.get("menu") as WorkshopPlotUI
	menu.player_button.button_pressed = true
	var start: int = _now()
	menu.build_button.pressed.emit()
	var deadline: int = Time.get_ticks_msec() + 15000
	while is_instance_valid(construction) and construction.is_player_work_active() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var elapsed: int = _now() - start
	var remaining: int = construction._remaining_work_units()
	var paid_stock: Dictionary = Inventory.items.duplicate(true)
	_expect(is_instance_valid(construction) and not construction.is_player_work_active() and player.is_collapsing
		and elapsed > 0 and elapsed < 180 and construction.phase == "building"
		and remaining > 0 and remaining < HOUSE_WORK
		and CityStockManager.shelter_capacity == shelter_before,
		"Genuine critical Energy interrupts a partly completed session while preserving paid work and no shelter.")
	var manual_released: Callable = func() -> bool:
		return player.is_collapsing and not house._manual_clearing and not is_instance_valid(house.menu)
	if nightmare == null or not await _wait_house_condition(manual_released,
		"Critical work releases its completed manual fade and closes the plot menu."):
		return
	_expect(not get_tree().paused and not player.can_move,
		"The plot releases its modal while the ongoing collapse still owns movement.")
	var nightmare_entered: Callable = func() -> bool:
		return nightmare.is_active and not player.is_collapsing and not SceneTransition.is_transitioning
	if not await _wait_house_condition(nightmare_entered,
		"Nightmare entry completes after player construction stops."):
		return
	_expect(player.can_move, "The interrupted house interaction does not strand the player in Nightmare.")
	nightmare.exit_npc.body_entered.emit(player)
	if not await _wait_house_condition(func() -> bool: return SceneTransition.continue_button.visible,
		"The Nightmare exit presents its normal Continue action."):
		return
	SceneTransition.continue_button.pressed.emit()
	if not await _wait_house_condition(func() -> bool: return not SceneTransition.is_transitioning,
		"Nightmare return completes."):
		return
	_expect(player.can_move and not TimeComponentManager.is_paused and not get_tree().paused
		and construction.phase == "building" and construction._remaining_work_units() == remaining
		and Inventory.items == paid_stock and CityStockManager.shelter_capacity == shelter_before,
		"Returning restores movement/time and keeps the interrupted construction, paid materials and shelter unchanged.")


func _select_worker_in_menu(assignment: Node, worker_id: String) -> bool:
	var slots: GridContainer = assignment.get_node("Root/Center/TextureWindow/Margin/MainVBox/OverviewPage/SlotCenter/SlotGrid")
	if slots.get_child_count() == 0:
		_expect(false, "The worker selector has an available slot.")
		return false
	(slots.get_child(0) as Button).pressed.emit()
	await get_tree().process_frame
	var workers: GridContainer = assignment.get_node("Root/Center/TextureWindow/Margin/MainVBox/WorkerSelectionPage/WorkerScroll/WorkerList")
	for child: Node in workers.get_children():
		if child is Button and str(child.get_meta("worker_id", "")) == worker_id and not child.disabled:
			(child as Button).pressed.emit()
			await get_tree().process_frame
			return true
	_expect(false, "The paid worker is selectable in the actual assignment screen.")
	return false


func _block_clock_after_minutes(_day: int, _hour: int, _minute: int, _weather: String) -> void:
	if block_after_minutes <= 0:
		return
	block_after_minutes -= 1
	if block_after_minutes == 0:
		store._busy = true


func _close_house_after_minutes(_day: int, _hour: int, _minute: int, _weather: String) -> void:
	if block_after_minutes <= 0:
		return
	block_after_minutes -= 1
	if block_after_minutes == 0:
		house.close_menu()


func _needs_drained_once(before_hunger: float, before_fatigue: float, minutes: int) -> bool:
	return is_equal_approx(player.hunger, minf(player.max_hunger, before_hunger + minutes * player.hunger_increase_per_min)) \
		and is_equal_approx(player.fatigue, minf(player.max_fatigue, before_fatigue + minutes * player.fatigue_increase_per_min))


func _wait_manual_session(label: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if not is_instance_valid(house) or not is_instance_valid(construction):
			break
		if not construction.is_player_work_active() and not house._manual_clearing and not is_instance_valid(house.menu):
			return true
		await get_tree().process_frame
	_expect(false, label + " should finish and release the manual session.")
	return false


func _wait_house_condition(predicate: Callable, label: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 15000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var ok: bool = bool(predicate.call())
	_expect(ok, label)
	return ok


func _finish() -> void:
	if is_instance_valid(store):
		store._busy = false
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	if is_instance_valid(content):
		content.queue_free()
		await get_tree().process_frame
	_expect(completed, "The player house lifecycle must reach its final critical case.")
	print("CitizenHousePlayerTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
