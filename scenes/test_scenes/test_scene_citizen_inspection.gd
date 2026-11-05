extends Node

## Current-map integration coverage for citizen inspection. This fixture uses
## memory-only state and never opens a city save slot.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const FOOD_ITEM_ID: String = "date_cluster"
const CLOTHING_ITEM_ID: String = "simple_clothes"

var failures: int = 0
var content: Node
var controller: Node
var panel: CanvasLayer
var visuals: Node
var runtime: Node
var inventory_ui: InventoryUI
var primary_id: String = ""
var removal_id: String = ""
var primary_citizen: CitizenData
var removal_citizen: CitizenData
var primary_actor: Node2D
var removal_actor: Node2D
var capture_directory: String = ""
var saved_state: Dictionary = {}
var original_storage: Node
var original_storage_existed: bool = false
var original_transport: Node
var original_transport_existed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	capture_directory = OS.get_environment("TIP_CITIZEN_CAPTURE_DIR")
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _frames(count: int = 1) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _wait_for_panel_refresh() -> void:
	await get_tree().create_timer(0.25, true, false, true).timeout


func _snapshot() -> void:
	var storage: Node = WorkStateRuntime.get_node_or_null("CityToolStorage")
	original_storage_existed = is_instance_valid(storage)
	original_storage = storage
	var transport: Node = WorkStateRuntime.get_node_or_null("CityStorageTransport")
	original_transport_existed = is_instance_valid(transport)
	original_transport = transport
	saved_state = {
		"inventory": Inventory.items.duplicate(true),
		"workers": WorkerDatabase.workers_by_id.duplicate(),
		"dismissed": WorkerDatabase.dismissed_workers.duplicate(),
		"citizens": CitizenManager.citizens_by_id.duplicate(),
		"rates": WorkerDatabase.onboarding_period_rates.duplicate(true),
		"needs_results": CitizenNeedsManager.last_needs_results.duplicate(true),
		"clothing_allocations": CitizenNeedsManager.clothing_allocations.duplicate(true),
		"food_supply": CityStockManager.food_supply,
		"clothing_supply": CityStockManager.clothing_supply,
		"treasury": CityStockManager.treasury_shekel,
		"shelter": CityStockManager.shelter_capacity,
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"weather": TimeComponentManager.current_weather,
		"clock_paused": TimeComponentManager.is_paused,
		"clock_processing": TimeComponentManager.is_processing(),
		"tree_paused": get_tree().paused,
		"current_scene": get_tree().current_scene,
		"storage_units": storage.get("units").duplicate(true) if original_storage_existed else {},
		"storage_items": storage.get("items").duplicate(true) if original_storage_existed else {},
		"food_portions": storage.get("food_portions").duplicate(true) if original_storage_existed else {},
		"storage_sequence": int(storage.get("_unit_sequence")) if original_storage_existed else 0,
		"cart_meta_present": storage.has_meta(&"initial_worksite_cart_supplied") if original_storage_existed else false,
		"cart_meta": storage.get_meta(&"initial_worksite_cart_supplied", false) if original_storage_existed else false,
		"transport_route": transport.get("route").duplicate(true) if original_transport_existed else {},
		"transport_last_tick": int(transport.get("last_tick")) if original_transport_existed else -1,
		"transport_worker_ids": transport.get("worker_ids").duplicate() if original_transport_existed else [],
		"transport_storage": transport.get("_central_storage") if original_transport_existed else null,
		"transport_central_position": transport.get("_central_position") if original_transport_existed else Vector2.ZERO,
		"transport_annex_position": transport.get("_annex_position") if original_transport_existed else Vector2.ZERO,
	}


func _run() -> void:
	_snapshot()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	TimeComponentManager.current_hour = 10
	primary_id = "citizen_inspection_%d" % Time.get_ticks_usec()
	removal_id = primary_id + "_remove"

	content = CONTENT.instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	await _frames(6)
	runtime = content.get_node_or_null("YSortWorld/WorkerRuntime")
	visuals = runtime.get_node_or_null("WorkerVisuals") if is_instance_valid(runtime) else null
	controller = runtime.get_node_or_null("CitizenInspectionController") if is_instance_valid(runtime) else null
	panel = controller.get("panel") as CanvasLayer if is_instance_valid(controller) else null
	inventory_ui = content.get_node_or_null("InventoryUI") as InventoryUI
	_expect(is_instance_valid(runtime) and is_instance_valid(visuals), "The real ContentScene provides WorkerRuntime and WorkerVisuals.")
	_expect(is_instance_valid(controller) and is_instance_valid(panel), "The city runtime exposes its CitizenInspectionController and panel.")
	_expect(is_instance_valid(inventory_ui), "The real ContentScene provides its InventoryUI for the modal-input check.")
	if not is_instance_valid(controller) or not is_instance_valid(panel) or not is_instance_valid(visuals):
		await _finish()
		return

	await _test_added_residents_and_mouse_selection()
	if is_instance_valid(panel):
		await _test_needs_and_storage()
		await _test_hire_reuses_and_tracks_actor()
		await _test_modal_pause_and_close_button()
	await _finish()


func _new_citizen(id: String, display_name: String) -> CitizenData:
	var citizen := CitizenData.new()
	citizen.citizen_id = id
	citizen.display_name = display_name
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	citizen.satisfaction = 0.65
	return citizen


func _add_test_citizens() -> void:
	primary_citizen = _new_citizen(primary_id, "Inspection Resident")
	removal_citizen = _new_citizen(removal_id, "Resident To Remove")
	CitizenManager.add_citizen(primary_citizen)
	CitizenManager.add_citizen(removal_citizen)
	await _frames(2)
	primary_actor = visuals.actors.get(primary_id) as Node2D
	removal_actor = visuals.actors.get(removal_id) as Node2D
	_expect(is_instance_valid(primary_actor) and primary_actor.is_visible_in_tree(), "Adding an unemployed resident creates a visible city actor.")
	_expect(is_instance_valid(removal_actor) and removal_actor.is_visible_in_tree(), "A second added resident creates a separate visible actor.")
	if is_instance_valid(primary_actor):
		_position_actor_on_screen(primary_actor, Vector2(90, 80))
	if is_instance_valid(removal_actor):
		_position_actor_on_screen(removal_actor, Vector2(130, 80))


func _position_actor_on_screen(actor: Node2D, viewport_position: Vector2) -> void:
	actor.global_position = get_viewport().get_canvas_transform().affine_inverse() * viewport_position


func _mouse_click(viewport_position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = viewport_position
	press.global_position = viewport_position
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = viewport_position
	release.global_position = viewport_position
	get_viewport().push_input(release, true)
	await get_tree().process_frame


func _click_actor(actor: Node2D) -> void:
	var viewport_position: Vector2 = get_viewport().get_canvas_transform() * actor.global_position
	await _mouse_click(viewport_position)


func _name_label() -> Label:
	return panel.get_node("Root/Frame/Margin/Contents/NameRow/NameLabel") as Label


func _daily_label(path: String) -> Label:
	return panel.get_node("Root/Frame/Margin/Contents/" + path) as Label


func _test_added_residents_and_mouse_selection() -> void:
	await _add_test_citizens()
	_expect(not CitizenNeedsManager.last_needs_results.has(primary_id), "The newly added citizen has no daily needs ledger yet.")
	if not is_instance_valid(primary_actor) or not is_instance_valid(removal_actor):
		return

	var starting_satisfaction: float = primary_citizen.satisfaction
	var starting_inventory: Dictionary = Inventory.items.duplicate(true)
	var starting_ledger: Dictionary = CitizenNeedsManager.last_needs_results.duplicate(true)
	var starting_storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var starting_city_items: Dictionary = starting_storage.get("items").duplicate(true)
	var starting_food_portions: Dictionary = starting_storage.get("food_portions").duplicate(true)
	var starting_shelter_capacity: int = CityStockManager.shelter_capacity
	var starting_tree_pause: bool = get_tree().paused
	var starting_clock_pause: bool = TimeComponentManager.is_paused
	var starting_minute: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	await _click_actor(primary_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id, "A real viewport mouse click opens the panel for the hit unemployed resident ID.")
	_expect(_name_label().text == primary_citizen.display_name, "The panel shows the selected resident's real name.")
	_expect(_daily_label("DailyCheckLabel").text.contains("NOT EVALUATED"), "An unevaluated citizen is labeled as not evaluated.")
	_expect(_daily_label("DailyNeedsRow/FoodStatus/Label").text == "Food: Unknown"
		and _daily_label("DailyNeedsRow/ClothingStatus/Label").text == "Clothing: Unknown"
		and _daily_label("DailyNeedsRow/ShelterStatus/Label").text == "Shelter: Unknown",
		"Food, Clothing, and Shelter stay Unknown before the first daily evaluation.")
	_expect(_daily_label("ConditionLabel").text == "Condition (daily): Unknown", "Condition stays Unknown before a real or fixture daily ledger exists.")
	_expect(_daily_label("ClothingDaysLabel").text == "Clothing days left: Unknown", "Clothing lifespan remains Unknown before a daily ledger exists.")
	_expect(get_tree().paused == starting_tree_pause and TimeComponentManager.is_paused == starting_clock_pause
		and starting_minute == TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute,
		"Opening the inspection panel does not pause or advance the city clock.")
	_expect(primary_citizen.satisfaction == starting_satisfaction and Inventory.items == starting_inventory,
		"Opening the panel does not mutate citizen satisfaction or Inventory.")
	_expect(CitizenNeedsManager.last_needs_results == starting_ledger
		and starting_storage.get("items") == starting_city_items
		and starting_storage.get("food_portions") == starting_food_portions
		and CityStockManager.shelter_capacity == starting_shelter_capacity
		and CityStockManager.food_supply == int(saved_state.food_supply)
		and CityStockManager.clothing_supply == int(saved_state.clothing_supply),
		"Opening the panel does not settle needs or change any city supply stock.")
	await _capture("citizen-unevaluated")

	# Place a different real actor underneath the visible frame. If the frame
	# leaks the mouse event to _unhandled_input, the selected ID changes.
	var original_removal_position: Vector2 = removal_actor.global_position
	var frame: Control = panel.get_node("Root/Frame") as Control
	var frame_center: Vector2 = frame.get_global_rect().get_center()
	removal_actor.global_position = get_viewport().get_canvas_transform().affine_inverse() * frame_center
	await _mouse_click(frame_center)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id,
		"Clicking the panel frame cannot select the resident positioned behind it.")
	removal_actor.global_position = original_removal_position

	await _click_actor(removal_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == removal_id and _name_label().text == removal_citizen.display_name,
		"A real viewport click on the second actor selects that exact resident.")
	_expect(CitizenManager.leave_city(removal_id), "The fixture can remove its open, unemployed resident through the real CitizenManager API.")
	await _wait_for_panel_refresh()
	_expect(not panel.visible and str(panel.get("selected_id")).is_empty(),
		"Removing a resident while inspected closes the stale panel safely.")
	_expect(not visuals.actors.has(removal_id), "The removed resident is retired from the real city actor map.")

	await _click_actor(primary_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id,
		"The remaining resident can still be inspected after another resident leaves.")


func _test_needs_and_storage() -> void:
	if not panel.visible or not is_instance_valid(primary_citizen):
		return
	var initial_storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var initial_food: int = int(initial_storage.call("get_food_supply_points"))
	var initial_clothing: int = int(initial_storage.call("get_clothing_item_count"))
	var initial_shelter: int = CityStockManager.shelter_capacity
	Inventory.items.clear()
	Inventory.items.assign({FOOD_ITEM_ID: 1, CLOTHING_ITEM_ID: 1, "shekel": 100})
	Inventory.items_changed.emit()
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var deposit: Dictionary = storage.call("deposit_items_from_inventory", {FOOD_ITEM_ID: 1, CLOTHING_ITEM_ID: 1})
	_expect(bool(deposit.get("ok", false)), "The real City Storage accepts one valid food item and one valid clothing item.")
	if CityStockManager.shelter_capacity < CityStockManager.MAX_SHELTER_CAPACITY:
		CityStockManager.shelter_capacity += 1
	await _wait_for_panel_refresh()
	var current_food: int = int(storage.call("get_food_supply_points"))
	var current_clothing: int = int(storage.call("get_clothing_item_count"))
	_expect(_daily_label("CityStockRow/FoodStock/Label").text == "%d pts" % current_food
		and current_food >= initial_food + 1,
		"The panel reports the increased real City Storage food stock without a needs settlement.")
	_expect(_daily_label("CityStockRow/ClothingStock/Label").text == "%d units" % current_clothing
		and current_clothing >= initial_clothing + 1,
		"The panel reports the increased real City Storage clothing stock without a needs settlement.")
	_expect(_daily_label("CityStockRow/ShelterStock/Label").text == "%d capacity" % CityStockManager.shelter_capacity
		and (initial_shelter >= CityStockManager.MAX_SHELTER_CAPACITY or CityStockManager.shelter_capacity == initial_shelter + 1),
		"The panel reports current shelter capacity as stock without settling Shelter fulfillment.")
	_expect(_daily_label("DailyNeedsRow/FoodStatus/Label").text == "Food: Unknown"
		and _daily_label("DailyNeedsRow/ClothingStatus/Label").text == "Clothing: Unknown"
		and _daily_label("DailyNeedsRow/ShelterStatus/Label").text == "Shelter: Unknown"
		and _daily_label("ConditionLabel").text == "Condition (daily): Unknown",
		"Adding food, clothing, and shelter stock does not invent fulfilled needs or condition results.")

	primary_citizen.satisfaction = 0.24
	CitizenNeedsManager.last_needs_results[primary_id] = {
		"evaluated": true,
		"day": TimeComponentManager.current_day,
		"food": true,
		"clothing": false,
		"shelter": true,
		"clothing_days_left": 0,
		"satisfaction": 0.24,
		"satisfaction_delta": 0.05,
		"missing": ["clothing"],
	}
	await _wait_for_panel_refresh()
	_expect(_daily_label("DailyCheckLabel").text == "LAST DAILY CHECK · DAY %d" % TimeComponentManager.current_day,
		"The UI shows the day from its explicit fixture settlement ledger.")
	_expect(_daily_label("DailyNeedsRow/FoodStatus/Label").text == "Food: Met"
		and _daily_label("DailyNeedsRow/ClothingStatus/Label").text == "Clothing: Missing"
		and _daily_label("DailyNeedsRow/ShelterStatus/Label").text == "Shelter: Met",
		"The UI reports actual Food, Clothing, and Shelter outcomes from the fixture ledger.")
	_expect(_daily_label("ClothingDaysLabel").text == "Clothing days left: 0",
		"Clothing duration is presented separately from the fulfillment outcome.")
	_expect(_daily_label("SatisfactionLabel").text == "Actual satisfaction: 24%"
		and _daily_label("ConditionLabel").text.contains("Condition (daily): 66%")
		and _daily_label("ConditionLabel").text.contains("Up"),
		"The UI distinguishes current satisfaction from the 66% ledger-derived target and its upward direction.")
	await _capture("citizen-evaluated-ledger")
	# Simulate an outside change such as a raid without rewriting the daily
	# ledger: the open card must update the actual value and keep its target.
	var ledger_before: Dictionary = CitizenNeedsManager.last_needs_results[primary_id].duplicate(true)
	primary_citizen.satisfaction = 0.19
	await _wait_for_panel_refresh()
	_expect(_daily_label("SatisfactionLabel").text == "Actual satisfaction: 19%"
		and _daily_label("ConditionLabel").text.contains("Condition (daily): 66%")
		and CitizenNeedsManager.last_needs_results[primary_id] == ledger_before,
		"An open card reflects a live Satisfaction change without altering the last daily result.")


func _test_hire_reuses_and_tracks_actor() -> void:
	if not is_instance_valid(primary_actor):
		return
	primary_citizen.satisfaction = CitizenData.MIN_APPLICANT_SATISFACTION
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 1
	_expect(CitizenManager.register_applicant(primary_id, WorkerData.Profession.LABORER),
		"The unemployed resident can enter the normal applicant state before recruitment.")
	var original_actor_id: int = primary_actor.get_instance_id()
	var contract_price: int = WorkerDatabase.get_contract_price(WorkerData.Profession.LABORER, 3)
	Inventory.items["shekel"] = maxi(contract_price, 1)
	Inventory.items_changed.emit()
	var worker: WorkerData = WorkerDatabase.hire_applicant(primary_id, 1, 3)
	_expect(worker != null and CitizenManager.get_citizen(primary_id).employment_status == CitizenData.EmploymentStatus.HIRED,
		"The applicant is recruited through the real WorkerDatabase hiring API.")
	await _frames(2)
	var hired_actor: Node2D = visuals.actors.get(primary_id) as Node2D
	_expect(is_instance_valid(hired_actor) and hired_actor.get_instance_id() == original_actor_id
		and hired_actor.get_meta("worker_id", "") == primary_id,
		"Hiring keeps exactly the resident actor already registered for that same ID.")
	if not is_instance_valid(hired_actor):
		return
	primary_actor = hired_actor
	if panel.visible:
		panel.call("close")
	await _click_actor(primary_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id,
		"Clicking the hired worker's existing actor continues to inspect the same citizen ID.")

	# Drive the ordinary city roaming step along an open, short route so the
	# actor's real position changes while the non-modal card remains selected.
	var origin: Vector2 = primary_actor.global_position
	var target: Vector2 = origin
	var nav: Variant = runtime.get("worksite_navigation")
	# Renderer timing can leave the test actor in a different idle position.
	# Find a visible, collision-clear fixture segment before driving _roam.
	var found_segment: bool = false
	if nav != null:
		for y: int in range(70, 180, 8):
			for x: int in range(50, 145, 8):
				var point: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * Vector2(x, y)
				var endpoint: Vector2 = point + Vector2(8, 0)
				if not nav.segment_clear(point + Vector2(0, 16), endpoint + Vector2(0, 16)):
					continue
				var actor_clear: bool = true
				for other in visuals.actors.values():
					if is_instance_valid(other) and other != primary_actor and other.is_visible_in_tree() and other.global_position.distance_to(point) < 24:
						actor_clear = false
						break
				if actor_clear:
					origin = point
					target = endpoint
					primary_actor.global_position = origin
					found_segment = true
					break
			if found_segment:
				break
	_expect(found_segment, "The real city navigation fixture offers a clear short resident-roaming step.")
	if found_segment:
		visuals.roaming[primary_id] = {"target": target, "idle": 0.0, "direction": "right"}
		visuals.call("_roam", primary_id, primary_actor, 0.2)
		_expect(primary_actor.global_position != origin and panel.visible and str(panel.get("selected_id")) == primary_id,
			"A real city-roaming step moves the hired actor while the panel stays tied to its stable person ID.")


func _test_modal_pause_and_close_button() -> void:
	if not is_instance_valid(inventory_ui) or not is_instance_valid(primary_actor):
		return
	var close_button: Control = panel.get_node("Root/Frame/Margin/Contents/NameRow/CloseButton") as Control
	await _mouse_click(close_button.get_global_rect().get_center())
	_expect(not panel.visible and str(panel.get("selected_id")).is_empty(), "A real viewport click on the panel close button closes it.")
	_expect(not get_tree().paused and not TimeComponentManager.is_paused, "Closing the non-modal panel does not change either pause state.")

	await _click_actor(primary_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id, "The hired resident can be reopened before modal coverage.")
	inventory_ui.open_inventory()
	await _frames(2)
	_expect(inventory_ui.visible and get_tree().paused, "The real Inventory modal owns its pause while open.")
	await _click_actor(primary_actor)
	_expect(not panel.visible and str(panel.get("selected_id")).is_empty(), "An Inventory modal prevents actor click-through into inspection.")
	_expect(get_tree().paused, "A blocked actor click leaves Inventory's pause intact.")
	inventory_ui.close_inventory()
	_expect(not inventory_ui.visible and not get_tree().paused, "Inventory close restores the unpaused state it captured before opening.")

	get_tree().paused = true
	TimeComponentManager.is_paused = true
	inventory_ui.open_inventory()
	await _click_actor(primary_actor)
	_expect(not panel.visible and get_tree().paused and TimeComponentManager.is_paused,
		"Inspection stays blocked under Inventory when both pause flags were already true.")
	inventory_ui.close_inventory()
	_expect(not inventory_ui.visible and get_tree().paused and TimeComponentManager.is_paused,
		"Closing Inventory restores the previously paused state instead of resuming the city.")
	get_tree().paused = false
	TimeComponentManager.is_paused = false


func _capture(filename: String) -> void:
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(capture_directory)
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(capture_directory.path_join(filename + ".png"))
	_expect(error == OK, "Rendered citizen inspection evidence is saved: " + filename)


func _finish() -> void:
	if is_instance_valid(inventory_ui) and inventory_ui.visible:
		inventory_ui.close_inventory()
	get_tree().paused = false
	TimeComponentManager.is_paused = false
	if is_instance_valid(panel):
		panel.call("close")
	if is_instance_valid(content):
		content.free()
	content = null
	if original_transport_existed:
		if is_instance_valid(original_transport):
			original_transport.set("route", saved_state.transport_route)
			original_transport.set("last_tick", saved_state.transport_last_tick)
			original_transport.set("worker_ids", saved_state.transport_worker_ids)
			original_transport.set("_central_storage", saved_state.transport_storage)
			original_transport.set("_central_position", saved_state.transport_central_position)
			original_transport.set("_annex_position", saved_state.transport_annex_position)
	else:
		var new_transport: Node = WorkStateRuntime.get_node_or_null("CityStorageTransport")
		if is_instance_valid(new_transport):
			new_transport.free()
	if original_storage_existed and is_instance_valid(original_storage):
		var units: Dictionary = original_storage.get("units")
		var items: Dictionary = original_storage.get("items")
		var portions: Dictionary = original_storage.get("food_portions")
		units.assign(saved_state.storage_units)
		items.assign(saved_state.storage_items)
		portions.assign(saved_state.food_portions)
		original_storage.set("_unit_sequence", saved_state.storage_sequence)
		if bool(saved_state.cart_meta_present):
			original_storage.set_meta(&"initial_worksite_cart_supplied", saved_state.cart_meta)
		else:
			original_storage.remove_meta(&"initial_worksite_cart_supplied")
		original_storage.emit_signal("changed")
	else:
		var new_storage: Node = WorkStateRuntime.get_node_or_null("CityToolStorage")
		if is_instance_valid(new_storage):
			new_storage.free()
	Inventory.items.assign(saved_state.inventory)
	Inventory.items_changed.emit()
	WorkerDatabase.workers_by_id.assign(saved_state.workers)
	WorkerDatabase.dismissed_workers.assign(saved_state.dismissed)
	WorkerDatabase.onboarding_period_rates.assign(saved_state.rates)
	CitizenManager.citizens_by_id.assign(saved_state.citizens)
	CitizenNeedsManager.last_needs_results.assign(saved_state.needs_results)
	CitizenNeedsManager.clothing_allocations.assign(saved_state.clothing_allocations)
	CityStockManager.food_supply = int(saved_state.food_supply)
	CityStockManager.clothing_supply = int(saved_state.clothing_supply)
	CityStockManager.treasury_shekel = int(saved_state.treasury)
	CityStockManager.shelter_capacity = int(saved_state.shelter)
	TimeComponentManager.current_day = int(saved_state.day)
	TimeComponentManager.current_hour = int(saved_state.hour)
	TimeComponentManager.current_minute = int(saved_state.minute)
	TimeComponentManager.current_weather = str(saved_state.weather)
	TimeComponentManager.is_paused = bool(saved_state.clock_paused)
	TimeComponentManager.set_process(bool(saved_state.clock_processing))
	get_tree().paused = bool(saved_state.tree_paused)
	get_tree().current_scene = saved_state.current_scene if is_instance_valid(saved_state.current_scene) else self
	if failures == 0:
		print("CitizenInspectionTest PASSED")
	else:
		print("CitizenInspectionTest FAILED: %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
