extends "res://scenes/test_scenes/mvp_first_playthrough.gd"

## Accelerated integration journey: the real New Game, pickup, worksite,
## merchant, warehouse, house and sleep paths. The driver relocates the player
## to interaction range and advances otherwise idle minutes; it does not grant
## items, change needs/clock rules, or use debug protection. An optional test
## seed selects a reproducible merchant-request sequence. The driver is not
## evidence that a person can navigate or discover the route unaided.
const FIRST: String = "initial_workshop_laborer"
const SECOND: String = "initial_worksite_hauler"
const THIRD: String = "initial_city_storage_hauler"
const JOURNEY_DIR: String = "user://playable_needs_journey"
var bought_clothes: int = 0
var deposited_clothes: int = 0
var paid_wood: int = 0
var house_sessions: int = 0
var saw_empty_board: bool = false
var saw_house_work_without_applicants: bool = false
var saw_house_work_without_workers: bool = false
var house_materials_paid: bool = false
var minimum_satisfaction: float = 1.0
var skip_merchant_visits: int = 0
var skipped_visit_days: Array[int] = []
var maximum_player_hunger: float = 0.0
var maximum_player_fatigue: float = 0.0
var harvest_interactions: int = 0
var audit_material_sources: bool = false


func walk(target: Vector2, _door_target: bool = false) -> void:
	if stopped:
		return
	# Navigation/discoverability is deliberately outside this accelerated test.
	player.global_position = target
	await _frames(8)


func harvest() -> void:
	if stopped:
		return
	await _frames(2) # Let source ledgers publish newly refilled pickup views.
	for tree: Node in content.get_node("YSortWorld").get_children():
		if not is_instance_valid(tree) or tree.get_script() != TREE:
			continue
		for slot: Variant in tree._pickups.keys():
			if int(Inventory.items.get("date_cluster", 0)) >= 14 or not Inventory.has_capacity_for("date_cluster", 1):
				return
			var pickup: Node2D = tree._pickups.get(slot)
			if not is_instance_valid(pickup) or pickup.is_collecting:
				continue
			await walk(pickup.global_position + Vector2(0, -6))
			if player.current_interactable != pickup:
				# Directly centering still exercises the real proximity selector.
				await walk(pickup.global_position)
			if player.current_interactable != pickup:
				print("PICKUP_DIAGNOSTIC ", {"target": pickup.name, "position": pickup.global_position, "player": player.global_position, "current": player.current_interactable, "nearby": player.nearby_interactables, "can_move": player.can_move, "paused": get_tree().paused})
			_expect(player.current_interactable == pickup, "A real date pickup is selected by proximity.")
			if stopped:
				return
			var before: int = Inventory.items.get("date_cluster", 0)
			await interact(pickup)
			var gained: int = int(Inventory.items.get("date_cluster", 0)) - before
			_expect(gained >= 1 and gained <= 3, "An interaction collects available dates from the selected palm.")
			harvested += gained
			harvest_interactions += 1
			while not player.can_move and not stopped:
				await get_tree().physics_frame


func supply_city() -> void:
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var available: int = int(Inventory.items.get("date_cluster", 0))
	var amount: int = mini(maxi(8 - storage.get_food_supply_points(), 0), maxi(available - 6, 0))
	var clothes: int = int(Inventory.items.get("simple_clothes", 0))
	if amount <= 0 and clothes <= 0:
		return
	var area: Node2D = runtime.get_node("CityStorageArea")
	await walk(area.get_node("CollisionShape2D").global_position)
	_expect(area.has_player_access(), "The actual warehouse is in interaction range.")
	if stopped:
		return
	if amount > 0:
		_expect(bool(storage.deposit_from_inventory("date_cluster", amount).ok), "Harvested dates enter City Storage.")
	if clothes > 0:
		_expect(bool(storage.deposit_from_inventory("simple_clothes", clothes).ok), "Purchased clothing enters City Storage.")
		deposited_clothes += clothes


func upkeep() -> void:
	if stopped:
		return
	_expect(not player.debug_disable_player_needs and not player.debug_disable_fatigue and not player.is_collapsing, "Player needs remain active and no collapse is bypassed.")
	await eat()
	if int(Inventory.items.get("date_cluster", 0)) < 10:
		await harvest()
	await eat()
	await supply_city()
	if player.fatigue >= 0.65 and player.can_sleep() and not stopped:
		await eat()
		await sleep_home()
		if not stopped:
			await leave_home()
		await eat()
	_expect(not player.has_critical_condition() and not player.is_collapsing, "Ordinary food and rest keep the player able to work.")


func wait_minutes(minutes: int) -> void:
	if stopped:
		return
	_expect(TimeComponentManager.advance_minutes(minutes), "Idle time advances through the real minute signals.")
	await _frames(3)


func _sample_player_conditions(_minute: int) -> void:
	if is_instance_valid(player):
		maximum_player_hunger = maxf(maximum_player_hunger, player.hunger)
		maximum_player_fatigue = maxf(maximum_player_fatigue, player.fatigue)


func _available_site(site_name: String) -> String:
	var item_id: String = runtime.sites[site_name].item_id
	var deadline: int = now() + 5 * 1440
	while not stopped and now() < deadline:
		if int(runtime.sites[site_name].stock) > 0:
			return site_name
		for key: Variant in runtime.sites:
			if runtime.sites[key].item_id == item_id and int(runtime.sites[key].stock) > 0:
				return str(key)
		await upkeep()
		await wait_minutes(60)
	_expect(false, "A resource site becomes available again within five game days: " + item_id)
	return ""

func gather(site_name: String) -> void:
	await upkeep()
	if stopped:
		return
	site_name = await _available_site(site_name)
	if stopped:
		return
	var site: Node2D = runtime.get_node("WorksiteMarkers/" + site_name)
	for offset: Vector2 in [Vector2.ZERO, Vector2(0, 24), Vector2(-20, 16), Vector2(20, 16), Vector2(-24, 0), Vector2(24, 0), Vector2(0, -24)]:
		await walk(site.global_position + offset)
		if not is_instance_valid(player.current_interactable) and not runtime._pickup_focused:
			break
	await interact()
	if not runtime.inspector.visible:
		print("GATHER_DIAGNOSTIC ", {"site": site_name, "current": player.current_interactable, "can_move": player.can_move, "pickup_focus": runtime._pickup_focused, "inventory_visible": runtime.inventory_ui.visible, "paused": get_tree().paused, "transition": SceneTransition.is_transitioning})
	_expect(runtime.inspector.visible and runtime._selected_site == site, "The real worksite inspector opens: " + site_name)
	if stopped:
		return
	runtime.inspector.select_mode("Hourly")
	var item_id: String = runtime.sites[site_name].item_id
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var city_before: int = int(storage.get_available_items().get(item_id, 0))
	var player_before: int = int(Inventory.items.get(item_id, 0))
	var ground_before: int = _personal_ground_quantity(item_id)
	var stock_before: int = int(runtime.sites[site_name].stock)
	var day_before: int = TimeComponentManager.current_day
	await runtime._start_work(180)
	var result: Dictionary = runtime.last_work_result
	_expect(int(result.minutes) > 0 and int(result.minutes) <= 180 and not result.interrupted and int(result.units) > 0
		and (int(result.minutes) == 180 or int(runtime.sites[site_name].stock) == 0), "Hourly work yields output and only ends early if the deposit is exhausted: " + site_name)
	_expect(int(Inventory.items.get(item_id, 0)) - player_before == int(result.to_bag)
		and _personal_ground_quantity(item_id) - ground_before == int(result.to_ground)
		and int(result.to_bag) + int(result.to_ground) == int(result.units)
		and int(storage.get_available_items().get(item_id, 0)) == city_before,
		"Hourly output belongs to the player and is conserved between the bag and personal pickup; city stock is unchanged.")
	if TimeComponentManager.current_day == day_before:
		_expect(int(runtime.sites[site_name].stock) == stock_before - int(result.units), "Hourly output consumes the same number of natural units.")
	await eat()


func _personal_ground_quantity(item_id: String) -> int:
	var quantity: int = 0
	for pickup: PickUpItem in runtime.get_node("GroundOutput").get_children():
		if is_instance_valid(pickup) and not pickup.is_queued_for_deletion() and not pickup.is_collecting \
			and pickup.item_id == item_id and str(pickup.get_meta("daily_site", "")).is_empty():
			quantity += pickup.quantity
	return quantity


func _buy_available_stone(goal: int) -> int:
	var merchant: Node = content.get_node("YSortWorld/TravelingMerchant")
	if stopped or not merchant.state.is_present():
		return 0
	var stock: int = 0
	var price: int = 0
	for row: Dictionary in merchant.state.get_catalog():
		if row.item_id == "stone":
			stock = int(row.stock)
			price = int(row.buy_price)
	if price <= 0:
		return 0
	var fits: int = floori(Inventory.get_remaining_capacity() / ItemDatabase.get_item_data("stone").weight)
	var quantity: int = mini(goal, mini(stock, mini(fits, int(Inventory.items.get("shekel", 0)) / price)))
	if quantity <= 0:
		return 0
	await walk(merchant.global_position + Vector2(0, 6))
	await interact(merchant)
	await accept_greeting(merchant)
	if stopped:
		return 0
	merchant.menu.buy_tab.pressed.emit()
	merchant.menu._on_catalog_item_pressed("stone")
	merchant.menu.quantity_spin_box.value = quantity
	_expect(not merchant.menu.confirm_button.disabled, "The actual merchant offers the affordable stone batch.")
	var before_stone: int = int(Inventory.items.get("stone", 0))
	var before_wallet: int = int(Inventory.items.get("shekel", 0))
	merchant.menu.confirm_button.pressed.emit()
	_expect(int(Inventory.items.get("stone", 0)) - before_stone == quantity
		and before_wallet - int(Inventory.items.get("shekel", 0)) == quantity * price,
		"Buying stone transfers the exact offered quantity and debits earned personal money.")
	merchant.close_menu()
	await _frames(3)
	print("MATERIAL_AUDIT_STONE ", JSON.stringify({"day": TimeComponentManager.current_day, "quantity": quantity, "price": price, "owned": Inventory.items.get("stone", 0)}))
	return quantity


func _drop_earned_surplus(item_id: String, keep: int) -> void:
	var quantity: int = maxi(0, int(Inventory.items.get(item_id, 0)) - keep)
	if quantity > 0:
		var parent: Node = player.get_parent()
		var children_before: Array[Node] = parent.get_children()
		var inventory_ui: InventoryUI = content.get_node("InventoryUI")
		inventory_ui.open_inventory()
		await inventory_ui._execute_drop_item(item_id, quantity)
		inventory_ui.close_inventory()
		var new_ground: int = 0
		for child: Node in parent.get_children():
			if child is PickUpItem and not children_before.has(child) and child.item_id == item_id:
				new_ground += child.quantity
		_expect(new_ground == quantity and int(Inventory.items.get(item_id, 0)) == keep,
			"The actual inventory drop action moves excess " + item_id + " into a recoverable pickup exactly once.")


func _audit_material_sources() -> void:
	# Leave working room with the ordinary inventory drop action and a one-way
	# city wood deposit. No goods or money are injected.
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	await _drop_earned_surplus("clay_lump", 4)
	var spare_wood: int = maxi(0, int(Inventory.items.get("wood_log", 0)) - 2)
	if spare_wood > 0:
		_expect(bool(storage.deposit_from_inventory("wood_log", spare_wood).ok), "Earned excess wood can be deposited to make carrying room.")
	if stopped:
		return
	for entry: Array in [["StrawSite", "straw_bundle"], ["WaterSite", "water_jar"]]:
		var before: int = int(Inventory.items.get(entry[1], 0))
		await gather(entry[0])
		_expect(int(Inventory.items.get(entry[1], 0)) - before >= 3, "The player's actual Hourly work supplies a full mudbrick input: " + str(entry[1]))
		if stopped:
			return
		await _drop_earned_surplus(str(entry[1]), 3)
	var purchased: int = 0
	var deadline_day: int = TimeComponentManager.current_day + 30
	while purchased < 20 and TimeComponentManager.current_day < deadline_day and not stopped:
		await upkeep()
		await _market()
		purchased += await _buy_available_stone(20 - purchased)
		if purchased >= 20 or stopped:
			break
		if int(Inventory.items.get("wood_log", 0)) < 3:
			await gather("WoodSite")
		else:
			await wait_minutes(60)
	_expect(purchased == 20 and int(Inventory.items.get("stone", 0)) >= 20,
		"Earned wood income and ordinary merchant visits supply twenty personal stone for the largest single wall requirement.")
	print("MATERIAL_AUDIT_RESULT ", JSON.stringify({"stone": Inventory.items.get("stone", 0), "purchased": purchased,
		"straw": Inventory.items.get("straw_bundle", 0), "water": Inventory.items.get("water_jar", 0),
		"clay": Inventory.items.get("clay_lump", 0), "reed": Inventory.items.get("reed_bundle", 0),
		"wood": Inventory.items.get("wood_log", 0), "day": TimeComponentManager.current_day,
		"income_from_wood": paid_wood, "clothes_purchased": bought_clothes}))


func _market() -> void:
	var merchant: Node = content.get_node("YSortWorld/TravelingMerchant")
	if stopped or not merchant.state.is_present():
		return
	var catalog: Array = merchant.state.get_catalog()
	if not seen_visits.has(TimeComponentManager.current_day):
		var skipped: bool = skipped_visit_days.size() < skip_merchant_visits
		seen_visits[TimeComponentManager.current_day] = skipped
		if skipped:
			skipped_visit_days.append(TimeComponentManager.current_day)
		var requests: Dictionary = {}
		for row: Dictionary in catalog:
			if int(row.demand) > 0:
				requests[row.item_id] = row.demand
		print("NEEDS_JOURNEY_VISIT ", {"day": TimeComponentManager.current_day, "requests": requests, "skipped": skipped})
	if bool(seen_visits[TimeComponentManager.current_day]):
		return
	var demand: int = 0
	var stock: int = 0
	for row: Dictionary in catalog:
		if row.item_id == "wood_log":
			demand = int(row.demand)
		elif row.item_id == "simple_clothes":
			stock = int(row.stock)
	var house: Node = content.get_node("YSortWorld/CitizenHousePlot").construction
	var reserve: int = 4 if house.phase in ["uncleared", "clearing", "empty"] else 0
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var clothed: int = 0
	for resident: CitizenData in CitizenManager.get_all_residents():
		if resident.clothing_fulfilled:
			clothed += 1
	var want: int = mini(stock, maxi(0, CitizenManager.get_all_residents().size() - clothed - storage.get_clothing_item_count() - int(Inventory.items.get("simple_clothes", 0))))
	var wallet: int = int(Inventory.items.get("shekel", 0))
	var wood_owned: int = int(Inventory.items.get("wood_log", 0))
	# Selling construction wood is an explicit trade-off if it is the only way
	# to afford clothing now; the player gathers the remainder for the house.
	var needed_for_clothes: int = ceili(float(maxi(0, want * 2 - wallet)) / 2.0)
	var sell: int = mini(demand, mini(wood_owned, maxi(maxi(0, wood_owned - reserve), needed_for_clothes)))
	if sell <= 0 and (want <= 0 or int(Inventory.items.get("shekel", 0)) < 2):
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
		_expect(not merchant.menu.confirm_button.disabled, "Owned wood can be sold against this visit's actual demand.")
		var before: int = Inventory.items.get("shekel", 0)
		merchant.menu.confirm_button.pressed.emit()
		paid_wood += int(Inventory.items.get("shekel", 0)) - before
	if want > 0:
		want = mini(want, int(Inventory.items.get("shekel", 0)) / 2)
		if want > 0:
			merchant.menu.buy_tab.pressed.emit()
			merchant.menu._on_catalog_item_pressed("simple_clothes")
			merchant.menu.quantity_spin_box.value = want
			_expect(not merchant.menu.confirm_button.disabled, "The ordinary Buy UI offers affordable Simple Clothes.")
			var before: int = Inventory.items.get("simple_clothes", 0)
			merchant.menu.confirm_button.pressed.emit()
			bought_clothes += int(Inventory.items.get("simple_clothes", 0)) - before
	merchant.close_menu()
	await _frames(3)
	await supply_city()


func _house_session() -> void:
	await upkeep()
	if stopped:
		return
	var house: Node = content.get_node("YSortWorld/CitizenHousePlot")
	var construction: Node = house.construction
	var phase_before: String = construction.phase
	var clearing_before: int = construction.clearing_remaining
	var work_before: int = construction._remaining_work_units()
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var without_workers: bool = WorkerDatabase.get_all_workers().is_empty()
	var without_applicants: bool = CitizenManager.get_all_applicants().is_empty()
	await walk(house.get_node("InteractableComponent").global_position + Vector2(0, 4))
	await interact(house)
	_expect(is_instance_valid(house.menu), "The actual house menu opens.")
	if stopped:
		return
	var menu: WorkshopPlotUI = house.menu
	if construction.phase == "building":
		_expect(menu.player_resume_button.visible and not menu.player_resume_button.disabled, "An unstaffed house can be resumed by the player.")
		menu.player_resume_button.pressed.emit()
	else:
		menu.player_button.button_pressed = true
		_expect(not menu.build_button.disabled, "The player can clear or build the house with their own materials.")
		menu.build_button.pressed.emit()
	var deadline: int = Time.get_ticks_msec() + 20000
	while is_instance_valid(house.menu) and Time.get_ticks_msec() < deadline and not stopped:
		await get_tree().process_frame
	_expect(not is_instance_valid(house.menu) and not house._manual_house_work, "The actual manual work session finishes and releases its menu.")
	var made_progress: bool = construction.phase != phase_before or construction.clearing_remaining < clearing_before or construction._remaining_work_units() < work_before
	if made_progress and without_workers:
		saw_house_work_without_workers = true
		if without_applicants:
			saw_house_work_without_applicants = true
	if without_workers and without_applicants:
		_expect(made_progress, "Manual house work during an actual no-applicant state advances construction.")
	if phase_before == "empty":
		var paid_all_materials: bool = true
		for id: String in construction.get_requirements():
			var paid: bool = int(inventory_before.get(id, 0)) - int(Inventory.items.get(id, 0)) == int(construction.get_requirements()[id])
			_expect(paid, "House construction consumes its materials from the player's Inventory: " + id)
			paid_all_materials = paid_all_materials and paid
		house_materials_paid = house_materials_paid or paid_all_materials
	house_sessions += 1


func _check_board(expected: int) -> void:
	var board: JobBoard = content.get_node("YSortWorld/InitialWorksites/JobBoard")
	await walk(board.get_node("InteractableComponent").global_position + Vector2(0, 8))
	await interact(board)
	_expect(is_instance_valid(board.job_board_ui), "The physical Job Board opens during its normal hours.")
	if stopped:
		return
	_expect(board.job_board_ui.applicants.size() == expected, "The actual Job Board displays the expected number of applicants.")
	if expected == 0:
		_expect(board.job_board_ui.empty_state_panel.visible, "The actual Job Board presents its empty state.")
	board.job_board_ui.close()
	await _frames(3)


func _run() -> void:
	var merchant_seed: int = -1
	var food_seed: int = -1
	var expect_zero: bool = false
	# Opt in only for a deliberate shortage fixture; ordinary journeys can recover before losing eligibility.
	var require_empty_board_recovery: bool = false
	var maximum_recovery_day: int = -1
	var maximum_harvest: int = -1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--journey-phase="):
			phase = arg.trim_prefix("--journey-phase=")
		elif arg.begins_with("--merchant-request-seed="):
			merchant_seed = int(arg.trim_prefix("--merchant-request-seed="))
		elif arg.begins_with("--food-seed="):
			food_seed = int(arg.trim_prefix("--food-seed="))
		elif arg == "--expect-zero":
			expect_zero = true
		elif arg == "--require-empty-board-recovery":
			require_empty_board_recovery = true
		elif arg == "--audit-material-sources":
			audit_material_sources = true
		elif arg in ["--expect-worksite-city", "--allow-legacy-player-worksite"]:
			_expect(false, "The temporary logistics flag is obsolete; Hourly output is checked as player-owned.")
		elif arg.begins_with("--skip-merchant-visits="):
			skip_merchant_visits = int(arg.trim_prefix("--skip-merchant-visits="))
		elif arg.begins_with("--max-recovery-day="):
			maximum_recovery_day = int(arg.trim_prefix("--max-recovery-day="))
		elif arg.begins_with("--max-harvest="):
			maximum_harvest = int(arg.trim_prefix("--max-harvest="))
	checkpoint_path = JOURNEY_DIR + "/checkpoint.json"
	var root: String = OS.get_environment("XDG_DATA_HOME")
	_expect(root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(root.simplify_path().trim_suffix("/") + "/"), "Use a disposable XDG_DATA_HOME.")
	_expect(FileAccess.file_exists(checkpoint_path) == (phase == "read"), "Use a fresh slot for write and its checkpoint for read.")
	if stopped:
		return
	get_tree().current_scene = null
	var menu: Node = MENU.instantiate()
	menu.checkpoint_file.path = checkpoint_path
	menu.session_started.connect(func(continued: bool): launched = continued == (phase == "read"))
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	if phase == "read":
		menu.continue_button.pressed.emit()
	else:
		menu.new_game_button.pressed.emit()
	for _frame: int in range(1200):
		if launched:
			break
		await get_tree().process_frame
	_expect(launched, "The actual Start Menu starts or continues the journey.")
	if stopped:
		return
	TimeComponentManager.set_process(false)
	bind_map()
	if phase == "read":
		await _verify_journey_continue()
		return
	TimeComponentManager.minute_changed.connect(_sample_player_conditions)
	if merchant_seed >= 0:
		# Sampling a reproducible request sequence is a fixture, not an assertion
		# that the production merchant's natural RNG always follows it.
		content.get_node("YSortWorld/TravelingMerchant").state._request_rng.seed = merchant_seed
		print("NEEDS_JOURNEY_REQUEST_SEED ", merchant_seed)
	if food_seed >= 0:
		var index: int = 0
		for tree: Node in content.get_node("YSortWorld").get_children():
			if is_instance_valid(tree) and tree.get_script() == TREE:
				tree.state._rng.seed = food_seed + 1009 * index
				index += 1
		print("NEEDS_JOURNEY_FOOD_SEED ", food_seed, " trees=", index)
	print("NEEDS_JOURNEY_LOGISTICS: player Hourly output remains personal; Daily worker output belongs to the city")
	_expect(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(), "New Game begins without personal resources or hired workers.")
	_expect(CitizenManager.get_all_residents().size() == 3 and CitizenManager.get_all_applicants().size() == 3, "The three residents, including the Hauler applicant, are initially eligible.")
	await _check_board(3)
	var sites: Dictionary = {"wood_log": "WoodSite", "clay_lump": "ClaySiteA", "reed_bundle": "ReedSite"}
	while not stopped and TimeComponentManager.current_day < 35:
		await upkeep()
		if stopped:
			break
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
		if house.phase == "built" and first.satisfaction >= 0.5 and second.satisfaction >= 0.5 and third.satisfaction >= 0.5 and first.are_basic_needs_fulfilled() and second.are_basic_needs_fulfilled() and third.are_basic_needs_fulfilled():
			break
		await _market()
		if stopped:
			break
		if house.phase in ["uncleared", "clearing", "building"]:
			await _house_session()
		elif house.phase == "empty":
			var needed: Dictionary = house.get_requirements()
			var missing: String = ""
			for id: String in needed:
				if int(Inventory.items.get(id, 0)) < int(needed[id]):
					missing = id
					break
			if missing.is_empty():
				await _house_session()
			else:
				await gather(sites[missing])
		else:
			if int(Inventory.items.get("shekel", 0)) < 4 and int(Inventory.items.get("wood_log", 0)) < 8:
				await gather("WoodSite")
			else:
				await wait_minutes(60)
	if stopped:
		return
	var house: Node = content.get_node("YSortWorld/CitizenHousePlot").construction
	var first: CitizenData = CitizenManager.get_citizen(FIRST)
	var second: CitizenData = CitizenManager.get_citizen(SECOND)
	var third: CitizenData = CitizenManager.get_citizen(THIRD)
	print("NEEDS_JOURNEY_COVERAGE ", JSON.stringify({"saw_empty_board": saw_empty_board, "saw_house_work_without_applicants": saw_house_work_without_applicants, "saw_house_work_without_workers": saw_house_work_without_workers, "house_materials_paid": house_materials_paid, "house_built": house.phase == "built", "all_three_recovered": first.are_basic_needs_fulfilled() and second.are_basic_needs_fulfilled() and third.are_basic_needs_fulfilled()}))
	_expect(saw_house_work_without_workers and house_materials_paid and house.phase == "built" and CityStockManager.shelter_capacity == 3, "Player materials fund manual house progress without hired workers, then grant shelter.")
	_expect(bought_clothes >= 3 and deposited_clothes >= 3 and paid_wood >= 4, "Wood income actually buys and deposits clothing for all three residents.")
	_expect(first.are_basic_needs_fulfilled() and second.are_basic_needs_fulfilled() and third.are_basic_needs_fulfilled() and first.satisfaction >= 0.5 and second.satisfaction >= 0.5 and third.satisfaction >= 0.5 and CitizenManager.get_all_applicants().size() >= 3, "Food, clothing and shelter recover all three residents and their Job Board eligibility.")
	if require_empty_board_recovery:
		_expect(saw_empty_board and saw_house_work_without_applicants,
			"The explicit shortage fixture observes an empty Job Board and manual house progress while applicants are ineligible.")
	if expect_zero:
		_expect(is_zero_approx(minimum_satisfaction), "The selected long-delay fixture actually reaches zero satisfaction before recovering.")
	if maximum_recovery_day >= 0:
		_expect(TimeComponentManager.current_day <= maximum_recovery_day, "The journey recovers by the requested latest game day.")
	if maximum_harvest >= 0:
		_expect(harvested <= maximum_harvest, "The journey stays within the requested date pickup budget.")
	if stopped:
		return
	while not WorkerDatabase.is_job_board_open() and not stopped:
		await upkeep()
		await wait_minutes(30)
	await _check_board(3)
	print("NEEDS_JOURNEY_RECOVERED ", JSON.stringify({"day": TimeComponentManager.current_day, "satisfaction": [first.satisfaction, second.satisfaction], "minimum_satisfaction": minimum_satisfaction, "house_sessions": house_sessions, "harvested": harvested, "harvest_interactions": harvest_interactions, "bought_clothes": bought_clothes, "wood_income": paid_wood, "sleeps": sleeps, "skipped_visit_days": skipped_visit_days, "max_hunger": maximum_player_hunger, "max_fatigue": maximum_player_fatigue}))
	if audit_material_sources:
		await _audit_material_sources()
		if stopped:
			return
	# Save an ordinary sleep checkpoint after recovery, then verify in a new process.
	while not player.can_sleep() and not stopped:
		await upkeep()
		await wait_minutes(30)
	await upkeep()
	if player.can_sleep():
		await sleep_home()
	_expect(FileAccess.file_exists(checkpoint_path) and WorkStateRuntime.get_node("CitySave").status == "Saved", "The recovered journey is written by normal sleep.")
	var expected: Dictionary = WorkStateRuntime.get_node("CitySave").snapshot.capture(get_tree().current_scene)
	var file: FileAccess = FileAccess.open(JOURNEY_DIR + "/expected.json", FileAccess.WRITE)
	_expect(file != null and not expected.is_empty(), "The checkpoint snapshot can be compared in a new process.")
	if file != null:
		file.store_string(JSON.stringify(expected))
		file.close()
	print("PlayableNeedsJourney write: ", "PASS" if not stopped else "FAIL")
	if not stopped:
		get_tree().quit(0)


func _verify_journey_continue() -> void:
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(JOURNEY_DIR + "/expected.json"))
	var store: Node = WorkStateRuntime.get_node("CitySave")
	var actual: Dictionary = store.snapshot.capture(get_tree().current_scene)
	_expect(expected is Dictionary and same(expected, actual), "Separate-process Continue restores the complete recovered sleep checkpoint.")
	_expect(not player.debug_disable_player_needs and not player.debug_disable_fatigue, "Continued play retains normal player needs.")
	await leave_home()
	var house: Node = content.get_node("YSortWorld/CitizenHousePlot").construction
	_expect(house.phase == "built" and CityStockManager.shelter_capacity == 3 and CitizenNeedsManager.clothing_allocations.size() >= 2, "Built house, shelter and issued clothing survive Continue.")
	_expect(CitizenManager.get_citizen(FIRST).satisfaction >= 0.5 and CitizenManager.get_citizen(SECOND).satisfaction >= 0.5, "Recovered satisfaction survives Continue.")
	print("PlayableNeedsJourney read: ", "PASS" if not stopped else "FAIL")
	if not stopped:
		get_tree().quit(0)
