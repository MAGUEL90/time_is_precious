extends "res://scenes/test_scenes/test_scene_playable_needs_journey.gd"

## End-to-end city journey from a fresh slot. The driver knows the map but
## walks with the normal actions, uses normal needs, and never grants resources,
## hires a worker by code, or teleports. Optional fast idle sends every real
## simulated-minute signal while the player waits; actions, work and sleep
## still use their normal mechanisms. Human discoverability review is needed.
const WALKED_DIR: String = "user://walked_city_journey"
const PROGRESS_PATH: String = WALKED_DIR + "/driver-progress.json"
var workshop_materials_phase: bool = false
var worker_hired: bool = false
var workshop_paid: bool = false
var renewed: int = 0
var resume_walked_write: bool = false
var fast_idle: bool = false
var fast_idle_minutes: int = 0

func _wait_for_player_control() -> void:
	for _frame: int in range(180):
		if player.can_move:
			return
		await get_tree().physics_frame
	print("WALKED_CONTROL_DIAGNOSTIC ", {"locks": player._movement_locks, "enabled": player._movement_enabled,
		"sleeping": player.is_sleeping, "collapsing": player.is_collapsing,
		"transition": SceneTransition.is_transitioning, "paused": get_tree().paused})
	_expect(false, "Normal player control returns before the next interaction.")

func sleep_home() -> void:
	await super.sleep_home()
	if stopped or phase != "write" or not FileAccess.file_exists(checkpoint_path):
		return
	# The game owns its ordinary sleep checkpoint. This sidecar retains only
	# test-driver counters so a real Continue can resume a long regression.
	var progress: Dictionary = {"save_sha256": FileAccess.get_file_as_string(checkpoint_path).sha256_text(),
		"saw_empty_board": saw_empty_board, "saw_house_work_without_applicants": saw_house_work_without_applicants,
		"saw_house_work_without_workers": saw_house_work_without_workers, "house_materials_paid": house_materials_paid,
		"bought_clothes": bought_clothes, "deposited_clothes": deposited_clothes, "paid_wood": paid_wood,
		"house_sessions": house_sessions, "minimum_satisfaction": minimum_satisfaction,
		"harvested": harvested, "eaten": eaten, "walked": walked, "harvest_interactions": harvest_interactions,
		"worker_hired": worker_hired, "workshop_paid": workshop_paid, "renewed": renewed,
		"fast_idle_minutes": fast_idle_minutes}
	var file: FileAccess = FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	_expect(file != null, "The test-driver progress sidecar can be written.")
	if file != null:
		file.store_string(JSON.stringify(progress))
		file.close()

func _restore_driver_progress() -> void:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROGRESS_PATH))
	_expect(value is Dictionary and value.get("save_sha256", "") == FileAccess.get_file_as_string(checkpoint_path).sha256_text(),
		"The test-driver sidecar matches the exact real sleep checkpoint.")
	if stopped:
		return
	saw_empty_board = bool(value.saw_empty_board)
	saw_house_work_without_applicants = bool(value.saw_house_work_without_applicants)
	saw_house_work_without_workers = bool(value.get("saw_house_work_without_workers", saw_house_work_without_applicants))
	house_materials_paid = bool(value.get("house_materials_paid", false))
	bought_clothes = int(value.bought_clothes)
	deposited_clothes = int(value.deposited_clothes)
	paid_wood = int(value.paid_wood)
	house_sessions = int(value.house_sessions)
	minimum_satisfaction = float(value.minimum_satisfaction)
	harvested = int(value.harvested)
	eaten = int(value.eaten)
	walked = float(value.walked)
	harvest_interactions = int(value.harvest_interactions)
	worker_hired = bool(value.worker_hired)
	workshop_paid = bool(value.workshop_paid)
	renewed = int(value.renewed)
	fast_idle_minutes = int(value.get("fast_idle_minutes", 0))

func _walk_out_of_overlap() -> void:
	if not player.test_move(player.global_transform, Vector2(0.01, 0)):
		return
	# Completing a house may enable its collision while the builder is still
	# inside it. Real movement resolves that overlap; issue normal input before
	# asking the grid planner for a route outside the new footprint.
	var origin: Vector2 = player.global_position
	for action: String in ["move_down", "move_left", "move_right", "move_up"]:
		for _frame: int in range(60):
			release_input()
			Input.action_press(action)
			var before: Vector2 = player.global_position
			await get_tree().physics_frame
			walked += before.distance_to(player.global_position)
			if not player.test_move(player.global_transform, Vector2(0.01, 0)):
				release_input()
				print("WALKED_OVERLAP_EXIT ", {"origin": origin, "end": player.global_position, "input": action})
				await _frames(3)
				return
	release_input()
	_expect(false, "Normal movement cannot leave the active collision overlap.")

func _walk_to_interactable(target: Node2D) -> void:
	await _wait_for_player_control()
	await _walk_out_of_overlap()
	if stopped:
		return
	var area_shape: CollisionShape2D = target.get_node("InteractableComponent/CollisionShape2D")
	var player_shape: CollisionShape2D = player.get_node("CollisionShape2D")
	var candidates: Array[Vector2] = []
	for x: int in range(-12, 13, 3):
		for y: int in range(-12, 13, 3):
			var candidate: Vector2 = area_shape.global_position + Vector2(x, y)
			var stable_overlap: bool = true
			for offset: Vector2 in [Vector2.ZERO, Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
				var projected: Transform2D = Transform2D(0, candidate + offset) * player_shape.transform
				if not area_shape.shape.collide(area_shape.global_transform, player_shape.shape, projected):
					stable_overlap = false
					break
			if stable_overlap:
				candidates.append(candidate)
	for _attempt: int in range(16):
		var approach: Vector2 = _reachable_approach(candidates, area_shape.global_position)
		_expect(approach != Vector2.INF, "A collision-clear interaction point exists for " + str(target.name))
		if stopped:
			return
		await walk(approach)
		if stopped:
			return
		var access: bool = not target.has_method("has_player_access") or bool(target.call("has_player_access"))
		if player.current_interactable == target and access:
			return
		print("WALKED_INTERACTION_APPROACH ", {"target": target.name, "position": player.global_position,
			"focused": player.current_interactable, "access": access})
		for index: int in range(candidates.size() - 1, -1, -1):
			if candidates[index].distance_to(approach) < 4.0:
				candidates.remove_at(index)
	_expect(false, "Normal walking selects the requested interactable: " + str(target.name))

func walk(target: Vector2, door_target: bool = false) -> void:
	if is_instance_valid(content) and content.has_node("AuthoredMap"):
		var authored: Node2D = content.get_node("AuthoredMap")
		var from_inside: bool = authored.to_local(player.global_position).y < -56.0
		var to_inside: bool = authored.to_local(target).y < -56.0
		if from_inside != to_inside:
			var gate_points: Array[Vector2] = []
			gate_points.assign([Vector2(0, -75), Vector2(0, -40)] if from_inside else [Vector2(0, -40), Vector2(0, -75)])
			for point: Vector2 in gate_points:
				await _walk_leg(authored.to_global(point))
				if stopped:
					return
	await _walk_leg(target, door_target)

func _walk_leg(target: Vector2, door_target: bool = false) -> void:
	if stopped:
		return
	await _walk_out_of_overlap()
	if stopped:
		return
	build_route(door_target)
	var start := Vector2i((player.global_position / 8).round())
	var end := Vector2i((target / 8).round())
	route.set_point_solid(start, false)
	if door_target:
		route.set_point_solid(end, false)
	var points: PackedVector2Array = route.get_point_path(start, end)
	_expect(not points.is_empty(), "A collision-aware walking route exists to %s" % target)
	points.append(target)
	for point: Vector2 in points:
		var frames: int = 0
		while not stopped and player.global_position.distance_to(point) > 1.1:
			if door_target and SceneTransition.is_transitioning:
				release_input()
				return
			var delta: Vector2 = point - player.global_position
			release_input()
			if absf(delta.x) > 0.7:
				Input.action_press("move_right" if delta.x > 0 else "move_left")
			elif absf(delta.y) > 0.7:
				Input.action_press("move_down" if delta.y > 0 else "move_up")
			var before: Vector2 = player.global_position
			await get_tree().physics_frame
			walked += before.distance_to(player.global_position)
			frames += 1
			if player.is_collapsing or frames > 240:
				_expect(false, "Walking blocked or collapsed at %s toward %s (goal %s)" % [player.global_position, point, target])
		release_input()
	await _frames(5)

func wait_minutes(minutes: int) -> void:
	var until: int = now() + minutes
	while now() < until and not stopped:
		if fast_idle and TimeComponentManager.can_advance_time():
			_expect(TimeComponentManager.advance_minutes(1), "Each compressed idle minute emits normal time and travel signals.")
			fast_idle_minutes += 1
		await get_tree().physics_frame
		_expect(not player.is_collapsing, "The player remains conscious while waiting naturally.")

func harvest() -> void:
	if stopped:
		return
	await _walk_out_of_overlap()
	if stopped:
		return
	for tree: Node in content.get_node("YSortWorld").get_children():
		if not is_instance_valid(tree) or tree.get_script() != TREE:
			continue
		for slot: Variant in tree._pickups.keys():
			if int(Inventory.items.get("date_cluster", 0)) >= 14 or not Inventory.has_capacity_for("date_cluster", 1):
				return
			var pickup: PickUpItem = tree._pickups.get(slot)
			if not is_instance_valid(pickup) or pickup.is_collecting:
				continue
			var approach: Vector2 = _pickup_approach(pickup)
			_expect(approach != Vector2.INF, "A palm pickup can be reached on foot.")
			if stopped:
				return
			await walk(approach)
			if stopped:
				return
			var before: int = int(Inventory.items.get("date_cluster", 0))
			var available_before: int = tree.state.available.count(true)
			await interact(pickup)
			var gained: int = int(Inventory.items.get("date_cluster", 0)) - before
			_expect(gained > 0 and gained == available_before - tree.state.available.count(true), "Walking to a palm transfers the exact collected dates.")
			harvested += gained
			harvest_interactions += 1
			while not player.can_move and not stopped:
				await get_tree().physics_frame

func gather(site_name: String) -> void:
	await upkeep()
	if stopped:
		return
	await _walk_out_of_overlap()
	site_name = await _available_site(site_name)
	if stopped:
		return
	var site: Marker2D = runtime.get_node("WorksiteMarkers/" + site_name)
	await walk_to_site(site)
	await interact()
	_expect(runtime.inspector.visible and runtime._selected_site == site, "The walked worksite opens: " + site_name)
	if stopped:
		return
	var item_id: String = runtime.sites[site_name].item_id
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var city_before: int = int(storage.get_available_items().get(item_id, 0))
	var bag_before: int = int(Inventory.items.get(item_id, 0))
	var ground_before: int = _personal_ground_quantity(item_id)
	await press(runtime.inspector.hourly_button)
	await press(runtime.inspector.next_button)
	await press(runtime.inspector.start_button)
	while runtime._working and not stopped:
		await get_tree().process_frame
	var result: Dictionary = runtime.last_work_result
	_expect(int(result.minutes) > 0 and int(result.minutes) <= 180 and not result.interrupted and int(result.units) > 0
		and (int(result.minutes) == 180 or int(runtime.sites[site_name].stock) == 0)
		and int(Inventory.items.get(item_id, 0)) - bag_before == int(result.to_bag)
		and _personal_ground_quantity(item_id) - ground_before == int(result.to_ground)
		and int(result.to_bag) + int(result.to_ground) == int(result.units)
		and int(storage.get_available_items().get(item_id, 0)) == city_before,
		"The actual Hourly UI conserves player-owned work output: " + site_name)
	await eat()

func supply_city() -> void:
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var dates: int = mini(maxi(8 - storage.get_food_supply_points(), 0), maxi(int(Inventory.items.get("date_cluster", 0)) - 6, 0))
	var clothes: int = int(Inventory.items.get("simple_clothes", 0))
	if dates <= 0 and clothes <= 0:
		return
	var area: Node = runtime.get_node("CityStorageArea")
	await walk(area.get_node("Board").global_position + Vector2(0, 13))
	await interact(area)
	if stopped:
		return
	var menu: Node = area.menu
	_expect(is_instance_valid(menu) and area.has_player_access(), "Walk to the actual City Storage board.")
	if stopped:
		return
	await press(menu.deposit_button)
	var transfer: ItemTransferUI = menu.transfer_ui
	var requested: Dictionary = {"date_cluster": dates, "simple_clothes": clothes}
	var before: Dictionary = Inventory.items.duplicate(true)
	for slot: ItemSlot in transfer.grid_container.get_children():
		for _index: int in range(int(requested.get(slot._item_id, 0))):
			slot.pressed.emit()
	for id: String in requested:
		if int(requested[id]) > 0:
			_expect(int(transfer.selected_items.get(id, 0)) == int(requested[id]), "Select earned supplies through the deposit UI: " + id)
	await press(transfer.confirm_button)
	for id: String in requested:
		_expect(int(before.get(id, 0)) - int(Inventory.items.get(id, 0)) == int(requested[id]), "The actual deposit consumes the selected personal supplies once: " + id)
	deposited_clothes += clothes
	await press(transfer.back_button)
	await press(menu.view.get_node("Margin/Content/Footer/Back"))
	_expect(not get_tree().paused and player.can_move, "Closing City Storage restores normal movement.")

func _market() -> void:
	var merchant: Node = content.get_node("YSortWorld/TravelingMerchant")
	if stopped or not merchant.state.is_present():
		return
	var demand: int = 0
	var clothes_stock: int = 0
	for row: Dictionary in merchant.state.get_catalog():
		if row.item_id == "wood_log":
			demand = int(row.demand)
		elif row.item_id == "simple_clothes":
			clothes_stock = int(row.stock)
	var house: Node = content.get_node("YSortWorld/CitizenHousePlot").construction
	var reserve: int = 4 if house.phase in ["uncleared", "clearing", "empty"] else (6 if workshop_materials_phase else 0)
	var sell: int = mini(demand, maxi(0, int(Inventory.items.get("wood_log", 0)) - reserve))
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var clothed: int = 0
	for resident: CitizenData in CitizenManager.get_all_residents():
		if resident.clothing_fulfilled:
			clothed += 1
	var want: int = mini(clothes_stock, maxi(0, CitizenManager.get_all_residents().size() - clothed - storage.get_clothing_item_count() - int(Inventory.items.get("simple_clothes", 0))))
	if sell == 0 and (want == 0 or int(Inventory.items.get("shekel", 0)) < 2):
		return
	await walk(merchant.global_position + Vector2(0, 6))
	await interact(merchant)
	await accept_greeting(merchant)
	if stopped:
		return
	if sell > 0:
		merchant.menu.sell_tab.pressed.emit()
		merchant.menu._on_catalog_item_pressed("wood_log")
		merchant.menu.quantity_spin_box.value = sell
		_expect(not merchant.menu.confirm_button.disabled, "The merchant accepts earned surplus wood.")
		var before: int = int(Inventory.items.get("shekel", 0))
		merchant.menu.confirm_button.pressed.emit()
		paid_wood += int(Inventory.items.get("shekel", 0)) - before
	if want > 0:
		want = mini(want, int(Inventory.items.get("shekel", 0)) / 2)
		if want > 0:
			merchant.menu.buy_tab.pressed.emit()
			merchant.menu._on_catalog_item_pressed("simple_clothes")
			merchant.menu.quantity_spin_box.value = want
			_expect(not merchant.menu.confirm_button.disabled, "The merchant offers affordable clothing.")
			var before: int = int(Inventory.items.get("simple_clothes", 0))
			merchant.menu.confirm_button.pressed.emit()
			bought_clothes += int(Inventory.items.get("simple_clothes", 0)) - before
	merchant.close_menu()
	await _frames(3)
	await supply_city()

func _hire_for_workshop() -> void:
	var price: int = WorkerDatabase.get_contract_price(WorkerData.Profession.LABORER, 9)
	var deadline_day: int = TimeComponentManager.current_day + 25
	while not stopped and TimeComponentManager.current_day < deadline_day and (int(Inventory.items.get("shekel", 0)) < price or not WorkerDatabase.is_job_board_open()):
		await upkeep()
		await _market()
		if int(Inventory.items.get("shekel", 0)) < price and int(Inventory.items.get("wood_log", 0)) < 8:
			await gather("WoodSite")
		else:
			await wait_minutes(30)
	_expect(int(Inventory.items.get("shekel", 0)) >= price and WorkerDatabase.is_job_board_open(), "Earned income funds a hire while the Job Board is open.")
	if stopped:
		return
	var board: JobBoard = content.get_node("YSortWorld/InitialWorksites/JobBoard")
	await walk(board.get_node("InteractableComponent").global_position + Vector2(0, 8))
	await interact(board)
	if stopped:
		return
	var panel: JobBoardUI = board.job_board_ui
	_expect(is_instance_valid(panel), "The actual Job Board opens for a funded hire.")
	if stopped:
		return
	var index: int = -1
	for i: int in range(panel.applicants.size()):
		if panel.applicants[i].citizen_id == FIRST:
			index = i
			break
	_expect(index >= 0, "The recovered resident is available on the Job Board.")
	if stopped:
		return
	var select_button: Button = panel.cards[index].selection_button
	_expect(select_button.is_visible_in_tree() and not select_button.disabled, "The recovered applicant's real selection control is available.")
	select_button.button_pressed = true
	await _frames(3)
	await press(panel.hire_button)
	var nine_days: Button
	for button: Button in panel.duration_buttons:
		if int(button.get_meta("contract_days", -1)) == 9:
			nine_days = button
	await press(nine_days)
	var wallet_before: int = int(Inventory.items.get("shekel", 0))
	await press(panel.confirm_hire_button)
	worker = WorkerDatabase.get_worker_data(FIRST)
	_expect(worker != null and not worker.is_payroll_blocked() and worker.payroll_contract_days == 9
		and wallet_before - int(Inventory.items.get("shekel", 0)) == price,
		"Hire the recovered worker using earned wallet funds and the actual nine-day UI.")
	worker_hired = worker != null
	await press(panel.close_button)
	measure("walked_hired")

func _assign_workshop() -> void:
	var old_phase: String = plot.construction.phase
	var before: Dictionary = Inventory.items.duplicate(true)
	await _walk_to_interactable(plot)
	await _wait_for_player_control()
	await interact(plot)
	if stopped:
		return
	if is_instance_valid(plot.get("keeper_dialogue")):
		# The authored main plot first greets the player; choose the real
		# Continue response before expecting the construction screen.
		var greeting: Node = plot.get("keeper_dialogue")
		var balloon: BaseGameDialogueBalloon = greeting.balloon
		var deadline: int = Time.get_ticks_msec() + 10000
		while is_instance_valid(balloon) and not is_instance_valid(balloon.dialogue_line) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		_expect(is_instance_valid(balloon) and is_instance_valid(balloon.dialogue_line), "The actual workshop keeper greeting opens.")
		if stopped:
			return
		balloon.dialogue_label.skip_typing()
		balloon.show_responses()
		var response: Control
		for item: Control in balloon.responses_menu.get_menu_items():
			if item.get_meta("response").text.strip_edges() == "Continue":
				response = item
				break
		_expect(is_instance_valid(response), "The keeper dialogue offers Continue.")
		if stopped:
			return
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		response.gui_input.emit(click)
		while not is_instance_valid(plot.menu) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
	var menu: WorkshopPlotUI = plot.menu
	if not is_instance_valid(menu):
		print("WALKED_PLOT_DIAGNOSTIC ", {"position": player.global_position, "focus": player.current_interactable,
			"access": plot.has_player_access(), "paused": get_tree().paused, "can_move": player.can_move,
			"locks": player._movement_locks, "enabled": player._movement_enabled})
	_expect(is_instance_valid(menu), "The actual workshop plot menu opens on foot.")
	if stopped:
		return
	await press(menu.assign_workers_button)
	var selection: WorkshopWorkerAssignmentUI = menu._worker_assignment_menu
	_expect(is_instance_valid(selection), "The real worker assignment screen opens.")
	if stopped:
		return
	await press(selection.slot_grid.get_child(0))
	var worker_button: Button
	for child: Node in selection.worker_list.get_children():
		if child is Button and str(child.get_meta("worker_id", "")) == worker.worker_id:
			worker_button = child
	await press(worker_button)
	await press(selection.next_button)
	await press(menu.build_button)
	_expect(plot.construction.worker_ids.has(worker.worker_id), "The selected worker receives the plot assignment.")
	if old_phase == "uncleared":
		_expect(plot.construction.phase == "clearing", "The paid worker starts physical clearing.")
	elif old_phase == "empty":
		_expect(plot.construction.phase == "building", "The worker starts the actual workshop build.")
		for id: String in plot.construction.get_requirements():
			_expect(int(before.get(id, 0)) - int(Inventory.items.get(id, 0)) == int(plot.construction.get_requirements()[id]), "Workshop construction deducts earned player material once: " + id)
		workshop_paid = true
	measure("walked_workshop_" + plot.construction.phase)

func _renew_worker() -> void:
	var action := InputEventAction.new()
	action.action = "open_worker_hub"
	action.pressed = true
	get_viewport().push_input(action)
	action.pressed = false
	get_viewport().push_input(action)
	await _frames(3)
	var hub: WorkerControlUI = runtime.worker_control
	_expect(hub.visible, "Open Worker Hub to renew the expired worker.")
	if stopped:
		return
	await press(hub._find_manage_button(worker.worker_id))
	await press(hub.manage_contract_button)
	var days_button: Button
	for button: Button in hub.contract_day_buttons:
		if int(button.get_meta("contract_days", -1)) == 9:
			days_button = button
	await press(days_button)
	var before: int = int(Inventory.items.get("shekel", 0))
	var price: int = WorkerDatabase.get_contract_price(worker.profession, 9)
	await press(hub.manage_renew_button)
	_expect(not worker.is_payroll_blocked() and before - int(Inventory.items.get("shekel", 0)) == price,
		"The actual contract UI renews the worker once using earned money.")
	renewed += 1
	action = InputEventAction.new()
	action.action = "open_worker_hub"
	action.pressed = true
	get_viewport().push_input(action)
	action.pressed = false
	get_viewport().push_input(action)
	await _frames(3)
	_expect(not hub.visible and not get_tree().paused, "Closing Worker Hub returns to live play.")

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--journey-phase="):
			phase = arg.trim_prefix("--journey-phase=")
		elif arg == "--resume-walked-write":
			resume_walked_write = true
		elif arg == "--fast-idle":
			fast_idle = true
	checkpoint_path = WALKED_DIR + "/checkpoint.json"
	var data_root: String = OS.get_environment("XDG_DATA_HOME")
	_expect(data_root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(data_root.simplify_path().trim_suffix("/") + "/"), "Use a disposable XDG data directory.")
	_expect(FileAccess.file_exists(checkpoint_path) == (phase == "read" or resume_walked_write), "Use a fresh slot for write and its real checkpoint for Continue.")
	if stopped:
		return
	get_tree().current_scene = null
	var start: Node = MENU.instantiate()
	start.checkpoint_file.path = checkpoint_path
	start.session_started.connect(func(continued: bool):
		if continued:
			restored_snapshot = WorkStateRuntime.get_node("CitySave").snapshot.capture(get_tree().current_scene)
		launched = continued == (phase == "read" or resume_walked_write))
	get_tree().root.add_child(start)
	get_tree().current_scene = start
	await _frames()
	await press(start.continue_button if phase == "read" or resume_walked_write else start.new_game_button)
	while not launched and not stopped:
		await get_tree().process_frame
	bind_map()
	_expect(is_equal_approx(TimeComponentManager.seconds_per_minute, 1.0) and is_equal_approx(player.speed, 50.0)
		and not player.debug_disable_player_needs and not player.debug_disable_fatigue,
		"Normal clock, walking speed and player needs remain active.")
	if phase == "read":
		await _verify_walked_continue()
		return
	if resume_walked_write:
		_restore_driver_progress()
		await leave_home()
		print("WALKED_CITY_RESUME ", JSON.stringify({"day": TimeComponentManager.current_day, "walked": walked, "house_sessions": house_sessions}))
	else:
		_expect(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(), "New Game starts without personal materials or workers.")
		await _check_board(3)
	var sites: Dictionary = {"wood_log": "WoodSite", "clay_lump": "ClaySiteA", "reed_bundle": "ReedSite"}
	while not stopped and TimeComponentManager.current_day < 35:
		await upkeep()
		var first: CitizenData = CitizenManager.get_citizen(FIRST)
		var second: CitizenData = CitizenManager.get_citizen(SECOND)
		var third: CitizenData = CitizenManager.get_citizen(THIRD)
		minimum_satisfaction = minf(minimum_satisfaction, minf(first.satisfaction, minf(second.satisfaction, third.satisfaction)))
		var house: Node = content.get_node("YSortWorld/CitizenHousePlot").construction
		if not saw_empty_board and WorkerDatabase.is_job_board_open() and CitizenManager.get_all_applicants().is_empty():
			_expect(first.satisfaction < 0.5 and second.satisfaction < 0.5 and third.satisfaction < 0.5,
				"An observed empty board has all three starter residents below the 50% applicant threshold.")
			if stopped:
				return
			await _check_board(0)
			saw_empty_board = true
		if house.phase == "built" and first.are_basic_needs_fulfilled() and second.are_basic_needs_fulfilled() and third.are_basic_needs_fulfilled() and first.satisfaction >= 0.5 and second.satisfaction >= 0.5 and third.satisfaction >= 0.5:
			break
		await _market()
		if house.phase in ["uncleared", "clearing", "building"]:
			await _house_session()
		elif house.phase == "empty":
			var missing: String = ""
			for id: String in house.get_requirements():
				if int(Inventory.items.get(id, 0)) < int(house.get_requirements()[id]):
					missing = id
					break
			if missing.is_empty():
				await _house_session()
			else:
				await gather(sites[missing])
		elif int(Inventory.items.get("shekel", 0)) < 4 and int(Inventory.items.get("wood_log", 0)) < 8:
			await gather("WoodSite")
		else:
			await wait_minutes(30)
	if stopped:
		return
	var first: CitizenData = CitizenManager.get_citizen(FIRST)
	var second: CitizenData = CitizenManager.get_citizen(SECOND)
	var third: CitizenData = CitizenManager.get_citizen(THIRD)
	print("WALKED_CITY_COVERAGE ", JSON.stringify({"saw_empty_board": saw_empty_board, "saw_house_work_without_applicants": saw_house_work_without_applicants, "saw_house_work_without_workers": saw_house_work_without_workers, "house_materials_paid": house_materials_paid, "house_built": content.get_node("YSortWorld/CitizenHousePlot").construction.phase == "built", "all_three_recovered": first.are_basic_needs_fulfilled() and second.are_basic_needs_fulfilled() and third.are_basic_needs_fulfilled()}))
	_expect(saw_house_work_without_workers and house_materials_paid and bought_clothes >= 3 and deposited_clothes >= 3
		and content.get_node("YSortWorld/CitizenHousePlot").construction.phase == "built"
		and first.are_basic_needs_fulfilled() and second.are_basic_needs_fulfilled() and third.are_basic_needs_fulfilled()
		and first.satisfaction >= 0.5 and second.satisfaction >= 0.5 and third.satisfaction >= 0.5,
		"Walking and earned supplies build the house with player materials and recover all three residents.")
	if stopped:
		return
	print("WALKED_CITY_RECOVERED ", JSON.stringify({"day": TimeComponentManager.current_day, "walked": walked, "satisfaction": [first.satisfaction, second.satisfaction], "house_sessions": house_sessions, "clothes": bought_clothes, "income": paid_wood}))
	if worker == null:
		await _hire_for_workshop()
	if stopped:
		return
	if plot.construction.phase == "uncleared" and player.can_sleep():
		await sleep_home()
		if not stopped:
			await leave_home()
	if plot.construction.phase == "uncleared":
		await _assign_workshop()
	if stopped:
		return
	while not stopped and plot.construction.phase == "clearing" and TimeComponentManager.current_day < 60:
		await upkeep()
		await _market()
		await wait_minutes(30)
	if stopped:
		return
	_expect(plot.construction.phase in ["empty", "building", "built"], "The paid worker finishes real workshop-site clearing.")
	workshop_materials_phase = true
	while not stopped and plot.construction.phase == "empty" and TimeComponentManager.current_day < 60:
		await upkeep()
		await _market()
		var missing: String = ""
		for id: String in plot.construction.get_requirements():
			if int(Inventory.items.get(id, 0)) < int(plot.construction.get_requirements()[id]):
				missing = id
				break
		if missing.is_empty():
			if worker.is_payroll_blocked():
				var price: int = WorkerDatabase.get_contract_price(worker.profession, 9)
				if int(Inventory.items.get("shekel", 0)) >= price:
					await _renew_worker()
				elif int(Inventory.items.get("wood_log", 0)) < 12:
					await gather("WoodSite")
				else:
					await wait_minutes(30)
			if not worker.is_payroll_blocked():
				await _assign_workshop()
		else:
			await gather(sites[missing])
	workshop_materials_phase = false
	if stopped:
		return
	while not stopped and plot.construction.phase == "building" and TimeComponentManager.current_day < 60:
		await upkeep()
		await _market()
		if worker.is_payroll_blocked():
			var price: int = WorkerDatabase.get_contract_price(worker.profession, 9)
			if int(Inventory.items.get("shekel", 0)) >= price:
				await _renew_worker()
			elif int(Inventory.items.get("wood_log", 0)) < 8:
				await gather("WoodSite")
			else:
				await wait_minutes(30)
		else:
			await wait_minutes(30)
	if stopped:
		return
	_expect(workshop_paid and worker_hired and plot.construction.phase == "built" and is_instance_valid(plot.get_node_or_null("BuiltWorkshop")), "The fully player-funded workshop is built after real shifts.")
	if stopped:
		return
	print("WALKED_CITY_BUILT ", JSON.stringify({"day": TimeComponentManager.current_day, "walked": walked, "renewals": renewed, "fast_idle_minutes": fast_idle_minutes, "inventory": Inventory.items, "food": CitizenNeedsManager.get_food_supply_summary()}))
	while not player.can_sleep() and not stopped:
		await upkeep()
		await _market()
		await wait_minutes(30)
	await sleep_home()
	_expect(FileAccess.file_exists(checkpoint_path), "A normal sleep writes the full walked journey.")
	var file: FileAccess = FileAccess.open(WALKED_DIR + "/expected.json", FileAccess.WRITE)
	_expect(file != null, "The checkpoint comparison can be written.")
	if file != null:
		file.store_string(JSON.stringify(WorkStateRuntime.get_node("CitySave").snapshot.capture(get_tree().current_scene)))
		file.close()
	print("WalkedCityJourney write: ", "PASS" if not stopped else "FAIL")
	if not stopped:
		get_tree().quit(0)

func _verify_walked_continue() -> void:
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(WALKED_DIR + "/expected.json"))
	_expect(expected is Dictionary and same(expected, restored_snapshot), "Continue restores the complete earned checkpoint on a new process.")
	await leave_home()
	_expect(content.get_node("YSortWorld/CitizenHousePlot").construction.phase == "built"
		and plot.construction.phase == "built" and is_instance_valid(plot.get_node_or_null("BuiltWorkshop")),
		"Both actual buildings and the city return after Continue.")
	workshop = plot.get_node("BuiltWorkshop")
	await _walk_to_interactable(workshop)
	await interact(workshop)
	var menu: WorkshopMenuUI = ui(WorkshopMenuUI)
	_expect(is_instance_valid(menu) and menu.visible, "The player can walk to and open the completed workshop after Continue.")
	if not stopped:
		await press(menu.close_button)
		# Continue beyond simply opening a menu: collect new ingredients through
		# normal work and deposit one complete recipe through the actual UI.
		await gather("StrawSite")
		await gather("WaterSite")
		_expect(int(Inventory.items.get("clay_lump", 0)) >= 3 and int(Inventory.items.get("straw_bundle", 0)) >= 3
			and int(Inventory.items.get("water_jar", 0)) >= 3, "After Continue, the player still has an earned recipe batch.")
		if stopped:
			return
		workshop = plot.get_node("BuiltWorkshop")
		await _walk_to_interactable(workshop)
		await interact(workshop)
		menu = ui(WorkshopMenuUI)
		await press(menu.manage_button)
		var storage_menu: WorkshopStorageMenuUI = ui(WorkshopStorageMenuUI)
		await press(storage_menu.deposit_button)
		var transfer: ItemTransferUI = ui(ItemTransferUI)
		var inventory_before: Dictionary = Inventory.items.duplicate(true)
		var storage_before: Dictionary = WorkShopStorage.items.duplicate(true)
		for slot: ItemSlot in transfer.grid_container.get_children():
			for _index: int in range(int(JOB.inputs.get(slot._item_id, 0))):
				slot.pressed.emit()
		for id: String in JOB.inputs:
			_expect(int(transfer.selected_items.get(id, 0)) == int(JOB.inputs[id]), "The workshop deposit UI selects the earned input: " + id)
		await press(transfer.confirm_button)
		for id: String in JOB.inputs:
			_expect(int(inventory_before.get(id, 0)) - int(Inventory.items.get(id, 0)) == int(JOB.inputs[id])
				and int(WorkShopStorage.items.get(id, 0)) - int(storage_before.get(id, 0)) == int(JOB.inputs[id]),
				"Continued play transfers each earned workshop ingredient exactly once: " + id)
		await press(transfer.back_button)
		storage_menu = ui(WorkshopStorageMenuUI)
		await press(storage_menu.back_button)
		menu = ui(WorkshopMenuUI)
		await press(menu.close_button)
	print("WalkedCityJourney read: ", "PASS" if not stopped else "FAIL")
	if not stopped:
		get_tree().quit(0)
