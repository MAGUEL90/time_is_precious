extends Node
## Normal-start audit driver: live clock, movement input, production UI, no grants.
## The route knows authored interaction locations; this is not human discoverability QA.
const MENU = preload("res://scenes/ui/start_menu/start_menu.tscn")
const TREE = preload("res://scenes/pickup_item/date_palm_spawner.gd")
const ACTIONS = ["move_left", "move_right", "move_up", "move_down"]
const JOB = preload("res://resources/job_data/mudbrick_make.tres")
const DRYING = preload("res://resources/process_data/drying_mudbrick.tres")
var content: Node
var player: Player
var runtime: Node
var plot: Node
var workshop: Node
var worker: WorkerData
var failures := 0
var launched := false
var restored_snapshot: Dictionary = {}
var harvested := 0
var eaten := 0
var sold_wood := 0
var sold_bricks := 0
var earned := 0
var paid := 0
var shaped := 0
var dried := 0
var sleeps := 0
var visits: Array = []
var seen_visits: Dictionary = {}
var measurements: Array = []
var phase := "write"
var route: AStarGrid2D
var walked := 0.0
var stopped := false
var checkpoint_path := "user://mvp_first_playthrough/checkpoint.json"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
		stopped = true
		get_tree().quit(1)

func _frames(count: int = 3) -> void:
	for frame in range(count):
		await get_tree().physics_frame

func now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func bind_map() -> void:
	content = get_tree().current_scene
	player = content.get_node("YSortWorld/Player")
	runtime = content.get_node_or_null("YSortWorld/WorkerRuntime")
	plot = content.get_node_or_null("YSortWorld/WorkshopPlot")
	worker = WorkerDatabase.get_worker_data("initial_workshop_laborer")
	if plot != null:
		workshop = plot.get_node_or_null("BuiltWorkshop")
	route = null

func measure(stage: String) -> void:
	var row := {"stage": stage, "minute": now(), "inventory": Inventory.items.duplicate(),
		"hunger": player.hunger, "fatigue": player.fatigue, "focus": player.focus,
		"harvested": harvested, "eaten": eaten, "sold_wood": sold_wood, "sold_bricks": sold_bricks,
		"earned": earned, "paid": paid, "shaped": shaped, "dried": dried, "sleeps": sleeps,
		"walked_pixels": walked, "food": CitizenNeedsManager.get_food_supply_summary(),
		"clothing_missing": CitizenNeedsManager.last_clothing_unfulfilled_count,
		"workshop_stock": WorkShopStorage.items.duplicate(), "held": WorkShopStorage.get_storage_state().get("held_lots", [])}
	if worker != null:
		row["worker_satisfaction"] = worker.get_resolved_satisfaction()
		row["worker_reliability"] = worker.get_resolved_reliability()
	if plot != null:
		row["construction"] = plot.construction.phase
	measurements.append(row)
	print("MVP_MEASURE ", JSON.stringify(row))

func release_input() -> void:
	for action in ACTIONS:
		Input.action_release(action)

func build_route(door_target: bool) -> void:
	route = AStarGrid2D.new()
	route.region = Rect2i(-30, -50, 100, 100)
	route.cell_size = Vector2(8, 8)
	route.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	route.update()
	var door = content.get_node_or_null("YSortWorld/HomeDoor")
	for x in range(-30, 70):
		for y in range(-50, 50):
			var pos := Vector2(x * 8, y * 8)
			var solid: bool = player.test_move(Transform2D(0, pos), Vector2(0.01, 0))
			if door != null and not door_target and pos.distance_to(door.global_position) < 20:
				solid = true
			route.set_point_solid(Vector2i(x, y), solid)

func walk(target: Vector2, door_target: bool = false) -> void:
	if stopped:
		return
	# Construction changes collision geometry; plan against the current world.
	build_route(door_target)
	var start := Vector2i((player.global_position / 8).round())
	var end := Vector2i((target / 8).round())
	route.set_point_solid(start, false)
	route.set_point_solid(end, false)
	var points := route.get_point_path(start, end)
	_expect(not points.is_empty(), "Navigation route exists from %s to %s" % [player.global_position, target])
	points.append(target)
	for point in points:
		var frames := 0
		while player.global_position.distance_to(point) > 1.1 and not stopped:
			if SceneTransition.is_transitioning and door_target:
				release_input()
				return
			var delta := point - player.global_position
			release_input()
			if absf(delta.x) > 0.7:
				Input.action_press("move_right" if delta.x > 0 else "move_left")
			if absf(delta.y) > 0.7:
				Input.action_press("move_down" if delta.y > 0 else "move_up")
			var before: Vector2 = player.global_position
			await get_tree().physics_frame
			walked += before.distance_to(player.global_position)
			frames += 1
			if player.is_collapsing or frames > 240:
				_expect(false, "Route blocked/collapsed at %s toward %s" % [player.global_position, point])
		release_input()
	await _frames(5)

func interact(target: Node = null) -> void:
	if stopped:
		return
	if target != null:
		_expect(player.current_interactable == target, "Approach selects " + str(target.name))
	if stopped:
		return
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventAction.new()
	event.action = "interact"
	get_viewport().push_input(event)
	await _frames()

func eat() -> void:
	var amount: int = mini(int(Inventory.items.get("date_cluster", 0)), floori(player.hunger / 0.04))
	if amount <= 0 or stopped:
		return
	var ui = content.get_node("InventoryUI")
	ui.open_inventory()
	var before: int = Inventory.items.get("date_cluster", 0)
	await ui._execute_use_item("date_cluster", amount)
	eaten += before - int(Inventory.items.get("date_cluster", 0))
	ui.close_inventory()

func harvest() -> void:
	for tree in content.get_node("YSortWorld").get_children():
		if not is_instance_valid(tree) or tree.get_script() != TREE:
			continue
		for slot in tree._pickups.keys():
			var pickup = tree._pickups.get(slot)
			if not is_instance_valid(pickup) or pickup.is_collecting:
				continue
			await walk(pickup.global_position + Vector2(0, -6))
			if stopped:
				return
			var before: int = Inventory.items.get("date_cluster", 0)
			await interact(pickup)
			_expect(Inventory.items.get("date_cluster", 0) == before + 1, "Pickup earns one date")
			harvested += int(Inventory.items.get("date_cluster", 0)) - before
			await get_tree().create_timer(1.0).timeout
		await eat()

func supply_city() -> void:
	var storage = WorkStateRuntime.get_node("CityToolStorage")
	var need: int = maxi(CitizenNeedsManager.get_food_consumer_count() * 2 - storage.get_food_supply_points(), 0)
	var amount: int = mini(need, maxi(int(Inventory.items.get("date_cluster", 0)) - 8, 0))
	if amount > 0:
		var area = runtime.get_node("CityStorageArea")
		await walk(area.global_position + Vector2(0, 8))
		if stopped:
			return
		_expect(area.has_player_access(), "Physical city stock access")
		# Same atomic deposit API used by the inventory/warehouse UI, earned dates only.
		var result: Dictionary = storage.deposit_from_inventory("date_cluster", amount)
		_expect(bool(result.get("ok", false)), "Earned dates supply resident food")

func sleep_home() -> void:
	await eat()
	await walk(content.get_node("YSortWorld/HomeDoor").global_position, true)
	while SceneTransition.is_transitioning:
		await get_tree().process_frame
	bind_map()
	_expect(content.name == "PlayerHomeInterior", "Normal home door")
	if stopped:
		return
	var spot = content.get_node("YSortWorld/SleepSpot")
	await walk(spot.global_position + Vector2(0, 25))
	await interact(spot)
	while SceneTransition.is_transitioning or player.is_sleeping:
		await get_tree().process_frame
	sleeps += 1
	measure("sleep_checkpoint")

func leave_home() -> void:
	await walk(content.get_node("YSortWorld/ExitDoor").global_position, true)
	while SceneTransition.is_transitioning:
		await get_tree().process_frame
	bind_map()
	_expect(content.name == "ContentScene", "Normal exit door")

func upkeep() -> void:
	await eat()
	if Inventory.items.get("date_cluster", 0) < 12 or player.hunger > 0.35:
		await harvest()
	await supply_city()
	if player.fatigue > 0.45 and player.can_sleep():
		await sleep_home()
		if not stopped:
			await leave_home()
		await eat()
	_expect(not player.debug_disable_player_needs and not player.debug_disable_fatigue, "Player needs remain active")
	_expect(not player.is_collapsing, "No collapse bypass")
	_expect(not content.get_node("TimeDebugOverlay").worker_guard_enabled, "Worker guard remains off")
	_expect(is_equal_approx(Inventory.max_load, 100.0), "Normal personal capacity")
	_expect(is_equal_approx(TimeComponentManager.seconds_per_minute, 1.0) and is_equal_approx(player.speed, 50.0), "Normal clock and walking speed")

func wait_minutes(minutes: int) -> void:
	var end := now() + minutes
	while now() < end and not stopped:
		await get_tree().physics_frame
		if player.is_collapsing:
			_expect(false, "Player collapsed while waiting")

func gather(site_name: String) -> void:
	await upkeep()
	if stopped:
		return
	var marker = runtime.get_node("WorksiteMarkers/" + site_name)
	await walk(marker.global_position)
	await interact()
	_expect(runtime.inspector.visible, "E opens " + site_name)
	if stopped:
		return
	runtime.inspector.select_mode("Hourly")
	await runtime._start_work(180)
	_expect(runtime.last_work_result.minutes == 180 and not runtime.last_work_result.interrupted, "Normal three-hour gathering " + site_name)
	await eat()
	measure("gather_" + site_name)

func trade() -> void:
	var merchant = content.get_node("YSortWorld/TravelingMerchant")
	if not merchant.state.is_present() or stopped:
		return
	var visit_key: int = TimeComponentManager.current_day
	if not seen_visits.has(visit_key):
		seen_visits[visit_key] = true
		visits.append({"day": visit_key, "catalog": merchant.state.get_catalog()})
		print("MVP_VISIT ", JSON.stringify(visits.back()))
	var sellable := false
	for row: Dictionary in merchant.state.get_catalog():
		if row.demand > 0 and Inventory.items.get(row.item_id, 0) > 0:
			sellable = true
	if not sellable:
		return
	await walk(merchant.global_position + Vector2(0, 6))
	await interact(merchant)
	await accept_greeting(merchant)
	if stopped:
		return
	for id: String in ["wood_log", "sun_dried_mudbrick"]:
		merchant.menu._set_buying(false)
		merchant.menu._on_catalog_item_pressed(id)
		if not merchant.menu.max_button.disabled:
			merchant.menu.max_button.pressed.emit()
			if not merchant.menu.confirm_button.disabled:
				var before: int = Inventory.items.get("shekel", 0)
				var count: int = Inventory.items.get(id, 0)
				merchant.menu.confirm_button.pressed.emit()
				earned += int(Inventory.items.get("shekel", 0)) - before
				if id == "wood_log":
					sold_wood += count - int(Inventory.items.get(id, 0))
				else:
					sold_bricks += count - int(Inventory.items.get(id, 0))
	merchant.close_menu()
	await _frames()
	measure("sale")

func accept_greeting(merchant: Node) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while (not is_instance_valid(merchant.greeting_balloon) or not is_instance_valid(merchant.greeting_balloon.dialogue_line)) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var balloon = merchant.greeting_balloon
	_expect(is_instance_valid(balloon) and is_instance_valid(balloon.dialogue_line), "Merchant greeting")
	if stopped:
		return
	balloon.dialogue_label.skip_typing()
	balloon.show_responses()
	for item in balloon.responses_menu.get_menu_items():
		if item.get_meta("response").text.strip_edges() == "Trade":
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			item.gui_input.emit(click)
			break
	while not is_instance_valid(merchant.menu) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(is_instance_valid(merchant.menu), "Trade menu opened")

func hire() -> void:
	var board = content.get_node("YSortWorld/InitialWorksites/JobBoard")
	await walk(board.get_node("InteractableComponent").global_position + Vector2(0, 8))
	await interact(board)
	if stopped:
		return
	for index in range(board.job_board_ui.applicants.size()):
		if board.job_board_ui.applicants[index].profession == WorkerData.Profession.LABORER:
			board.job_board_ui.applicant_list.select(index)
			board.job_board_ui.hire_button.pressed.emit()
			break
	worker = WorkerDatabase.get_worker_data("initial_workshop_laborer")
	board.job_board_ui.close_button.pressed.emit()
	_expect(worker != null, "Normal Job Board hire")
	measure("hire")

func construct() -> void:
	await walk(plot.get_node("InteractableComponent").global_position + Vector2(0, 8))
	await interact(plot)
	if stopped:
		return
	plot.menu._on_worker_assignment_next_requested([worker.worker_id] as Array[String])
	plot.menu.build_button.pressed.emit()
	measure("construction_" + plot.construction.phase)

func deposit(targets: Dictionary = {}) -> void:
	if stopped:
		return
	if targets.is_empty():
		for id in JOB.inputs:
			targets[id] = JOB.inputs[id]
		if WorkshopFacilityManager.get_facility_level("drying_yard") == 0:
			for id in WorkshopFacilityManager.get_facility_upgrade_requirements("drying_yard", 1):
				targets[id] = targets.get(id, 0) + WorkshopFacilityManager.get_facility_upgrade_requirements("drying_yard", 1)[id]
		elif dried >= 1 and WorkshopFacilityManager.get_facility_level("drying_yard") == 1:
			for id in WorkshopFacilityManager.get_facility_upgrade_requirements("drying_yard", 2):
				if id != "sun_dried_mudbrick":
					targets[id] = targets.get(id, 0) + WorkshopFacilityManager.get_facility_upgrade_requirements("drying_yard", 2)[id]
	await open_workshop()
	if stopped:
		return
	await press(ui(WorkshopMenuUI).manage_button)
	await press(ui(WorkshopStorageMenuUI).deposit_button)
	var transfer = ui(ItemTransferUI)
	for slot in transfer.grid_container.get_children():
		if targets.has(slot._item_id):
			var amount: int = mini(slot._quantity, maxi(int(targets[slot._item_id]) - WorkShopStorage.get_free_item_quantity(slot._item_id), 0))
			for index in range(amount):
				slot.slot_clicked.emit(slot._item_id, slot._quantity, slot)
	if transfer.selected_items.is_empty():
		await press(transfer.close_button)
	else:
		await press(transfer.confirm_button)

func ui(script_type: Script) -> Node:
	for child in content.get_children():
		if child.get_script() == script_type and not child.is_queued_for_deletion():
			return child
	_expect(false, "Expected UI missing: " + script_type.resource_path)
	return null

func press(button: BaseButton) -> void:
	_expect(button != null and not button.disabled and button.is_visible_in_tree(), "Enabled visible UI action")
	if stopped:
		return
	button.pressed.emit()
	await _frames()

func open_workshop() -> void:
	if stopped:
		return
	workshop = plot.get_node("BuiltWorkshop")
	await walk(workshop.get_node("InteractableComponent").global_position + Vector2(0, 4))
	await interact(workshop)

func choose(production: WorkshopProductionUI, id: String) -> void:
	for card in production.work_order_grid.get_children():
		if card is WorkOrderCard and card.work_order_id == id:
			await press(card)
			await press(production.next_button)
			return
	_expect(false, "Missing recipe " + id)

func shape() -> void:
	if stopped:
		return
	await open_workshop()
	await press(ui(WorkshopMenuUI).assign_button)
	await choose(ui(WorkshopProductionUI), JOB.job_id)
	var assignment = ui(WorkshopWorkerAssignmentUI)
	if assignment._get_selected_worker_ids().is_empty():
		await press(assignment.slot_grid.get_child(0))
		await press(assignment.worker_list.get_child(0))
	await press(assignment.next_button)
	var job_ui = ui(WorkshopJobUI)
	await press(job_ui.start_button)
	_expect(job_ui.job_started, "Normal production starts: " + job_ui.requirement_label.text)
	if stopped:
		return
	await press(job_ui.close_button)
	while worker.is_working() and not stopped:
		await wait_minutes(10)
	shaped += 1
	measure("shaped")

func pay_output(id: String) -> void:
	if stopped:
		return
	await open_workshop()
	await press(ui(WorkshopMenuUI).manage_button)
	var storage_ui = ui(WorkshopStorageMenuUI)
	await press(storage_ui.held_grid.get_child(0))
	var popup = ui(WorkshopFeeConfirmUI)
	var before: int = Inventory.items.get("shekel", 0)
	await press(popup.fee_panel.primary_button)
	paid += before - int(Inventory.items.get("shekel", 0))
	_expect(WorkShopStorage.get_held_item_quantity(id) == 0, "Pay normal output fee")
	await press(storage_ui.back_button)
	await press(ui(WorkshopMenuUI).close_button)

func yard(level: int) -> void:
	if stopped:
		return
	await open_workshop()
	await press(ui(WorkshopMenuUI).build_button)
	var build = ui(WorkshopBuildUI)
	await press(build.facility_list.get_child(0))
	await press(build.build_button)
	await press(build.confirm_panel.primary_button)
	_expect(WorkshopFacilityManager.get_facility_level("drying_yard") == level, "Yard progression from earned materials")
	await press(build.close_button)
	measure("yard_" + str(level))

func dry() -> void:
	await open_workshop()
	await press(ui(WorkshopMenuUI).assign_button)
	await choose(ui(WorkshopProductionUI), DRYING.process_id)
	await press(ui(WorkshopProductionUI).process_confirm_panel.primary_button)
	while not ProcessManager.get_active_progress_entries().is_empty() and not stopped:
		await wait_minutes(10)
	dried += 1
	measure("dried")

func withdraw_bricks() -> void:
	await open_workshop()
	await press(ui(WorkshopMenuUI).manage_button)
	var storage_ui = ui(WorkshopStorageMenuUI)
	var slot = storage_ui.free_slots_by_item_id.get("sun_dried_mudbrick")
	if slot != null:
		# Leave room for normal food pickups and ten bricks for the yard upgrade.
		var available: int = maxi(WorkShopStorage.get_free_item_quantity("sun_dried_mudbrick") - 10, 0)
		var fits: int = maxi(floori((Inventory.get_remaining_capacity() - 8.0) / ItemDatabase.get_item_data("sun_dried_mudbrick").weight), 0)
		for i in range(mini(available, fits)):
			await press(slot)
		if mini(available, fits) > 0:
			await press(storage_ui.withdraw_button)
	await press(storage_ui.back_button)
	await press(ui(WorkshopMenuUI).close_button)

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--journey-phase="):
			phase = arg.trim_prefix("--journey-phase=")
	get_tree().current_scene = null
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = checkpoint_path
	menu.session_started.connect(func(continued: bool):
		if continued:
			restored_snapshot = WorkStateRuntime.get_node("CitySave").snapshot.capture(get_tree().current_scene)
		launched = true)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	if phase == "read":
		menu.continue_button.pressed.emit()
	else:
		_expect(menu.continue_button.disabled, "Use a fresh isolated data directory")
		menu.new_game_button.pressed.emit()
	while not launched and not stopped:
		await get_tree().process_frame
	bind_map()
	if phase == "read":
		await verify_continue()
		return
	_expect(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(), "New Game starts with zero personal resources/workers")
	_expect(preload("res://resources/traveling_merchant/common_merchant.tres").randomize_requests, "Merchant random requests stay enabled")
	measure("new_game")
	# First income is attempted against every naturally scheduled visit, never rerolled.
	while earned == 0 and TimeComponentManager.current_day < 16 and not stopped:
		await upkeep()
		await trade()
		if earned > 0 or stopped:
			break
		if Inventory.items.get("wood_log", 0) < 8 and player.fatigue < 0.55:
			await gather("WoodSite")
		else:
			await wait_minutes(60)
	if not stopped and earned > 0:
		await hire()
		await construct()
	# Gather construction materials; food/rest/merchant are serviced between work blocks.
	var needs := {"wood_log": 6, "clay_lump": 12, "reed_bundle": 8}
	var sites := {"wood_log": "WoodSite", "clay_lump": "ClaySiteA", "reed_bundle": "ReedSite", "straw_bundle": "StrawSite", "water_jar": "WaterSite"}
	while not stopped and plot.construction.phase != "built" and TimeComponentManager.current_day < 20:
		await upkeep()
		if plot.construction.phase == "empty":
			var missing := ""
			for id in needs:
				if Inventory.items.get(id, 0) < needs[id]:
					missing = id
					break
			if missing.is_empty():
				await construct()
			else:
				await gather(sites[missing])
		else:
			await trade()
			if Inventory.items.get("wood_log", 0) < 10 and player.fatigue < 0.5:
				await gather("WoodSite")
			else:
				await wait_minutes(60)
	if not stopped and plot.construction.phase == "built":
		measure("built")
		await deposit()
	# Gather inputs and yard materials in manageable loads; repeat real output batches.
	while not stopped and dried < 2 and TimeComponentManager.current_day < 28:
		await upkeep()
		await trade()
		if Inventory.items.get("shekel", 0) < 7:
			if Inventory.items.get("wood_log", 0) < 6:
				await gather("WoodSite")
			else:
				await wait_minutes(60)
			continue
		var required: Dictionary = JOB.inputs.duplicate()
		if WorkshopFacilityManager.get_facility_level("drying_yard") == 0:
			for id in WorkshopFacilityManager.get_facility_upgrade_requirements("drying_yard", 1):
				required[id] = required.get(id, 0) + WorkshopFacilityManager.get_facility_upgrade_requirements("drying_yard", 1)[id]
		elif dried >= 1 and WorkshopFacilityManager.get_facility_level("drying_yard") == 1:
			for id in WorkshopFacilityManager.get_facility_upgrade_requirements("drying_yard", 2):
				if id != "sun_dried_mudbrick":
					required[id] = required.get(id, 0) + WorkshopFacilityManager.get_facility_upgrade_requirements("drying_yard", 2)[id]
		var missing := ""
		for id in required:
			if WorkShopStorage.get_free_item_quantity(id) + Inventory.items.get(id, 0) < required[id]:
				missing = id
				break
		if not missing.is_empty():
			await gather(sites[missing])
			await deposit()
			continue
		await deposit()
		if WorkshopFacilityManager.get_facility_level("drying_yard") == 0:
			await yard(1)
		elif dried >= 1 and WorkshopFacilityManager.get_facility_level("drying_yard") == 1:
			await yard(2)
		await shape()
		await pay_output("wet_mudbrick")
		if WorkShopStorage.get_free_item_quantity("wet_mudbrick") >= 20:
			await dry()
			await pay_output("sun_dried_mudbrick")
			await withdraw_bricks()
			await trade()
	if not stopped and dried >= 2:
		while sold_bricks == 0 and TimeComponentManager.current_day < 31 and not stopped:
			await upkeep()
			await trade()
			await wait_minutes(60)
	# Save the actual earned journey, including a blocked/partial production state.
	if not stopped:
		while not player.can_sleep():
			await upkeep()
			await wait_minutes(60)
		await sleep_home()
		var store = WorkStateRuntime.get_node("CitySave")
		_expect(FileAccess.file_exists(checkpoint_path), "Sleep wrote real journey checkpoint")
		var file := FileAccess.open("user://mvp_first_playthrough/expected.json", FileAccess.WRITE)
		file.store_string(FileAccess.get_file_as_string(checkpoint_path))
		file.close()
	await finish()

func verify_continue() -> void:
	var expected = JSON.parse_string(FileAccess.get_file_as_string("user://mvp_first_playthrough/expected.json"))
	var store = WorkStateRuntime.get_node("CitySave")
	var actual: Dictionary = restored_snapshot
	_expect(same(expected, actual), "Separate-process Continue restores complete earned snapshot")
	measure("continued")
	await leave_home()
	await upkeep()
	measure("continued_city")
	await finish()

func same(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) < 0.000000001
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not same(a[key], b[key]):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not same(a[i], b[i]):
				return false
		return true
	return a == b

func finish() -> void:
	release_input()
	var complete: bool = phase == "read" or (earned > 0 and dried >= 2 and sold_bricks > 0
		and WorkshopFacilityManager.get_facility_level("drying_yard") == 2
		and FileAccess.file_exists(checkpoint_path))
	var status: String = "FAIL" if failures > 0 else ("PASS" if complete else "PARTIAL")
	var result := {"phase": phase, "status": status, "failures": failures, "two_drying_cycles": dried >= 2,
		"visits": visits, "measurements": measurements}
	print("MVP_RESULT ", JSON.stringify(result))
	print("MVPFirstPlaythrough ", phase, ": ", status)
	get_tree().paused = false
	var scene = get_tree().current_scene
	get_tree().current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
	await _frames()
	get_tree().quit(1 if failures > 0 else (0 if complete else 2))
