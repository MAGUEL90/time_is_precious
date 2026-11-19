extends "res://scenes/test_scenes/test_scene_city_transport_flow.gd"

## Isolated fixture: a paid courier encounters a temporary obstruction, then a
## second obstruction holds the cargo until the real contract expiry boundary.
## The clock is placed near expiry; stock and wallet are explicit fixture grants.
const INTERRUPTION_SAVE: String = "user://city_transport_interruption/checkpoint.json"

func _run() -> void:
	worker_id = "initial_city_storage_hauler" # Exercise the actual Hauler applicant.
	var data_root: String = OS.get_environment("XDG_DATA_HOME")
	_expect(data_root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(data_root.simplify_path().trim_suffix("/") + "/"), "Use a disposable XDG data directory.")
	_expect(not FileAccess.file_exists(INTERRUPTION_SAVE), "Use a fresh interruption checkpoint.")
	if stopped:
		return
	get_tree().current_scene = null
	TimeComponentManager.set_process(false)
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = INTERRUPTION_SAVE
	menu.session_started.connect(func(from_save: bool):
		continued = from_save
		launched = true)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	await press(menu.new_game_button)
	for _frame: int in range(1200):
		if launched or stopped:
			break
		await get_tree().process_frame
	_expect(launched and not continued, "New Game opens the authored city.")
	if stopped:
		return
	bind_map()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	transport = WorkStateRuntime.get_node("CityStorageTransport")
	central = transport.get_storage("city")
	annex = transport.get_storage("annex")
	store = WorkStateRuntime.get_node("CitySave")
	_place_fixture_clock(17, 8, 0)
	Inventory.add_item("shekel", 10)
	Inventory.add_item(ITEM_ID, 4)
	var courier: WorkerData = WorkerDatabase.hire_applicant(worker_id, 3)
	_expect(courier != null and not courier.is_payroll_blocked(), "A real three-day contract is purchased for the courier.")
	if stopped:
		return
	_expect(central.allocate("initial_worksite_cart", worker_id), "Equip the city's existing cart.")
	_expect(central.try_add_worksite_output(ITEM_ID, 6), "Seed six city-owned logs through the worksite receipt.")
	_place_fixture_clock(courier.payroll_paid_until_day, 14, 55)
	# This fixture isolates payroll expiry, not resignation. Its direct clock
	# jump predates gradual needs; seed a positive linked-citizen value and its
	# integration cursor so the overnight wait cannot trigger departure.
	var linked_citizen: CitizenData = courier.get_linked_citizen()
	_expect(linked_citizen != null and not courier.resignation_pending, "The courier has a present, non-resigning linked citizen.")
	if stopped:
		return
	linked_citizen.satisfaction = 1.0
	courier.satisfaction = 1.0
	CitizenNeedsManager.satisfaction_last_minute[worker_id] = now()
	var expiry: int = courier.get_paid_end_minute()
	_expect(expiry == (TimeComponentManager.current_day + 1) * 1440 + 7 * 60 and not courier.is_payroll_blocked(), "The normal contract expires at the next 07:00 boundary.")
	_expect(transport.start(worker_id, "city", ITEM_ID, 3), "A paid courier picks up a three-log shipment.")
	if stopped:
		return
	_expect(TimeComponentManager.advance_minutes(1), "The courier moves one minute before the obstruction.")
	var navigation = runtime.worksite_navigation
	var original: Array[PackedVector2Array] = navigation.polygons.duplicate()
	var position: Vector2 = Vector2(transport.get_visual(float(now())).position)
	var target: Vector2 = transport._leg_target(transport.route)
	_expect(position.distance_to(target) > 20.0, "The fixture has room to block the route ahead of the courier.")
	_block_ahead(original, position, target)
	_expect(navigation.is_clear(position + transport.FEET_OFFSET) and not navigation.segment_clear(position + transport.FEET_OFFSET, position.move_toward(target, 10.0) + transport.FEET_OFFSET), "The new obstacle blocks the next segment without covering the current feet.")
	_expect(TimeComponentManager.advance_minutes(3), "Advance while the new obstacle remains.")
	_expect(Vector2(transport.get_visual(float(now())).position).is_equal_approx(position) and _city_total() == 6 and int(transport.route.get("quantity", 0)) == 3, "The blocked courier stays at the last clear point and retains the cargo exactly once.")
	navigation.replace_polygons(original)
	_expect(TimeComponentManager.advance_minutes(1), "Advance after removing the obstacle.")
	var resumed: Vector2 = Vector2(transport.get_visual(float(now())).position)
	_expect(resumed.distance_to(position) > 0.1 and navigation.segment_clear(position + transport.FEET_OFFSET, resumed + transport.FEET_OFFSET) and _city_total() == 6, "The paid courier resumes only along a clear segment without changing total goods.")
	if stopped:
		return
	_block_ahead(original, resumed, target)
	_expect(TimeComponentManager.advance_minutes(expiry - now() + 3), "Hold the load through the real contract expiry.")
	_expect(courier.is_payroll_blocked() and not courier.resignation_pending and not bool(transport.route.get("resigning", false)) and courier.get_resolved_satisfaction() > 0.0 and not transport.route.is_empty() and int(transport.route.quantity) == 3 and _city_total() == 6, "Expiry without resignation keeps all cargo reserved and conserves the city stock.")
	var expired_position: Vector2 = Vector2(transport.get_visual(float(now())).position)
	navigation.replace_polygons(original)
	_expect(TimeComponentManager.advance_minutes(3), "Advance with a clear route but an expired contract.")
	_expect(Vector2(transport.get_visual(float(now())).position).is_equal_approx(expired_position) and _city_total() == 6, "An unpaid courier does not move or deliver after the obstruction is removed.")
	_expect(store.save_checkpoint(), "Save the expired courier and its cargo: " + store.last_error)
	_expect(store.load_checkpoint(), "Reload the expired courier and its cargo: " + store.last_error)
	transport = WorkStateRuntime.get_node("CityStorageTransport")
	central = transport.get_storage("city")
	annex = transport.get_storage("annex")
	courier = WorkerDatabase.get_worker_data(worker_id)
	_expect(courier != null and courier.is_payroll_blocked() and int(transport.route.get("quantity", 0)) == 3 and _city_total() == 6, "Continue preserves the unpaid courier, reservation and single cargo owner.")
	if stopped:
		return
	var price: int = WorkerDatabase.get_contract_price(courier.profession, 3)
	var wallet_before: int = int(Inventory.items.get("shekel", 0))
	_expect(WorkerDatabase.renew_contract(worker_id, 3), "Renew the expired contract through the normal paid backend.")
	_expect(not courier.is_payroll_blocked() and int(Inventory.items.get("shekel", 0)) == wallet_before - price and _city_total() == 6, "Renewal charges once and preserves the cargo.")
	await _finish_route()
	_expect(transport.route.is_empty() and int(central.items.get(ITEM_ID, 0)) == 3 and int(annex.items.get(ITEM_ID, 0)) == 3 and int(Inventory.items.get(ITEM_ID, 0)) == 4, "After renewal the shipment arrives once; city and personal stock remain separate.")
	if stopped:
		return
	_expect(transport.start(worker_id, "city", ITEM_ID, 1), "Start another shipment under the renewed, still-active contract.")
	var active_route: Dictionary = transport.route.duplicate(true)
	var previous_end: int = courier.payroll_paid_until_day
	wallet_before = int(Inventory.items.get("shekel", 0))
	_expect(WorkerDatabase.renew_contract(worker_id, 3), "Extend an active contract while the courier carries cargo.")
	_expect(courier.payroll_paid_until_day == previous_end + 3 and int(Inventory.items.get("shekel", 0)) == wallet_before - price and transport.route == active_route and _city_total() == 6, "An active extension charges once, extends the paid period and leaves the shipment intact.")
	await _finish_route()
	_expect(transport.route.is_empty() and int(central.items.get(ITEM_ID, 0)) == 2 and int(annex.items.get(ITEM_ID, 0)) == 4 and int(Inventory.items.get(ITEM_ID, 0)) == 4, "The actively extended courier delivers the second shipment exactly once.")
	if stopped:
		return
	_expect(transport.start(worker_id, "city", ITEM_ID, 1) and TimeComponentManager.advance_minutes(1), "A third courier load begins its outward route.")
	var visuals: Node = runtime.get_node("WorkerVisuals")
	visuals._process(0.01)
	var actor: Node = visuals.actors.get(worker_id)
	var cargo_label: Label = actor.get_node_or_null("CargoLabel") if is_instance_valid(actor) else null
	_expect(cargo_label != null and not cargo_label.text.is_empty(), "The moving courier visibly identifies its cargo.")
	_expect(transport.cancel(), "Cancel the loaded courier while it is travelling.")
	await _finish_route()
	visuals._process(0.01)
	_expect(transport.route.is_empty() and _city_total() == 6 and cargo_label != null and cargo_label.text.is_empty(), "A cancelled load returns once and leaves no stale cargo label on the idle worker.")
	if stopped:
		return
	print("CityStorageTransportInterruptionTest: PASS")
	get_tree().quit(0)

func _place_fixture_clock(day: int, hour: int, minute: int) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute
	TimeComponentManager.emit_time_signal()

func _block_ahead(original: Array[PackedVector2Array], position: Vector2, target: Vector2) -> void:
	var center: Vector2 = position.move_toward(target, 10.0) + transport.FEET_OFFSET
	var blocked: Array[PackedVector2Array] = original.duplicate()
	blocked.append(PackedVector2Array([center + Vector2(-1, -1), center + Vector2(1, -1), center + Vector2(1, 1), center + Vector2(-1, 1)]))
	runtime.worksite_navigation.replace_polygons(blocked)

func _city_total() -> int:
	return int(central.items.get(ITEM_ID, 0)) + int(annex.items.get(ITEM_ID, 0)) + int(transport.route.get("quantity", 0))
