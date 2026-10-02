extends Node
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	TimeComponentManager.seconds_per_minute = 100000.0
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 6
	TimeComponentManager.current_minute = 0
	var content = preload("res://scenes/test_scenes/fixtures/content_worksites_map.tscn").instantiate()
	var worksites = content.get_node("YSortWorld/Worksites")
	worksites.seed_playtest_hauler = false
	worksites.enable_worker_commute = false
	add_child(content)
	var destinations: Dictionary = {}
	for site_id: StringName in [&"WoodSite", &"ReedSite", &"StrawSite", &"WaterSite"]:
		var session = worksites.sites[site_id]
		var destination = worksites.get_node(str(site_id).replace("Site", "Storage"))
		_expect(worksites._hauler_storage_reason(destination, site_id).is_empty(), "Authored destination accepts its resource.")
		destinations[site_id] = destination
		for role: String in ["laborer", "hauler"]:
			var worker := WorkerData.new()
			worker.worker_id = str(site_id) + "_" + role
			worker.display_name = worker.worker_id
			worker.profession = WorkerData.Profession.LABORER if role == "laborer" else WorkerData.Profession.HAULER
			WorkerDatabase.workers_by_id[worker.worker_id] = worker
			if role == "hauler":
				worksites.city_tools.add_tool_unit(worker.worker_id + "_cart", "cart", "Test cart")
				worksites.worker_management.equip(worker.worker_id, worker.worker_id + "_cart")
				_expect(worksites.daily.select_hauler(site_id, worker.worker_id, worksites.get_path_to(destination), destination.name, 3), "Hauler selection retains the existing cart/destination rules.")
			else:
				_expect(worksites.daily.toggle(site_id, worker.worker_id), "Laborer can join the resource worksite.")
		_expect(worksites.daily.start(site_id, worksites._drop_daily_output.bind(worksites.get_node("WorksiteMarkers/" + str(site_id)))), "Daily team starts for " + str(site_id))
		_expect(worksites.hauling.routes[str(site_id) + "_hauler"].cargo.item_id == session.item_id, "Hauler route captures this site's item identity.")
		_expect(not worksites._hauler_storage_reason(worksites.get_node("CityStorageArea/DeliveryPoint"), site_id).is_empty(), "City Storage remains unavailable for raw resources.")
	var deadline: int = 1440 + 420 + 180
	TimeComponentManager.advance_minutes(deadline - worksites.daily.now())
	for site_id: StringName in destinations:
		var session = worksites.sites[site_id]
		var expected: int = floori(180.0 / session.minutes_per_unit)
		_expect(worksites.daily.jobs[site_id].stats[str(site_id) + "_laborer"].output == expected, "Daily output follows the site's rate including fractional minutes.")
		_expect(destinations[site_id].get_node("Storage").quantity == 3, "Matching storage received the three-item target.")
		_expect(worksites._daily_output_count(site_id) + 3 == expected, "Ground plus delivered output is conserved independently by site.")
		for stack in worksites.get_node("GroundOutput").get_children():
			if stack.get_meta("daily_site", "") == str(site_id):
				_expect(stack.item_id == session.item_id, "Daily ground output must not become clay.")
	var player: Player = content.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	Inventory.items.clear()
	for site_id: StringName in destinations:
		var destination = destinations[site_id]
		var storage = destination.get_node("Storage")
		var item: ItemData = ItemDatabase.get_item_data(storage.item_id)
		Inventory.max_load = Inventory.get_total_inventory_weight()
		await _take_with_e(player, destination)
		_expect(storage.quantity == 3, "Full bag leaves delivered stock untouched.")
		Inventory.max_load += item.weight
		await _take_with_e(player, destination)
		_expect(storage.quantity == 2 and Inventory.items.get(storage.item_id, 0) == 1, "E takes only what fits.")
		Inventory.max_load = 100.0
		await _take_with_e(player, destination)
		await _take_with_e(player, destination)
		_expect(storage.quantity == 0 and Inventory.items.get(storage.item_id, 0) == 3, "Repeated E cannot duplicate stock.")
	var workshop = preload("res://scenes/workshop/workshop.tscn").instantiate()
	add_child(workshop)
	var transferred: Dictionary = Inventory.items.duplicate()
	_expect(workshop.deposit_selected_items_from_player(transferred), "Collected hauler output can be deposited into the existing workshop.")
	for item_id: String in transferred:
		_expect(WorkShopStorage.get_free_item_quantity(item_id) == int(transferred[item_id]), "Workshop receives the exact collected resource.")
	var capture_dir: String = OS.get_environment("TIP_RESOURCE_CAPTURE_DIR")
	if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		player.global_position = worksites.global_position + Vector2(0, 10)
		await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture_dir.path_join("resource-storage-map.png"))
	get_tree().paused = false
	print("ResourceWorksitesTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _take_with_e(player: Player, destination: Node2D) -> void:
	player.global_position = destination.global_position + Vector2(0, 5)
	for _frame: int in range(5):
		await get_tree().physics_frame
	_expect(player.current_interactable == destination, "Storage is reachable through player interaction.")
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventAction.new()
	event.action = "interact"
	get_viewport().push_input(event)
	await get_tree().process_frame
