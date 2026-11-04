extends "res://scenes/test_scenes/mvp_first_playthrough.gd"

## Accelerated integration journey: the real New Game, pickup, worksite,
## merchant, warehouse, house and sleep paths. The driver relocates the player
## to interaction range and advances otherwise idle minutes; it does not grant
## items, change needs/clock rules, or use debug protection. An optional test
## seed selects a reproducible merchant-request sequence. The driver is not
## evidence that a person can navigate or discover the route unaided.
const FIRST: String = "initial_workshop_laborer"
const SECOND: String = "initial_worksite_hauler"
const JOURNEY_DIR: String = "user://playable_needs_journey"
var bought_clothes: int = 0
var deposited_clothes: int = 0
var paid_wood: int = 0
var house_sessions: int = 0
var saw_empty_board: bool = false
var saw_house_work_without_applicants: bool = false
var minimum_satisfaction: float = 1.0
var require_city_worksite_output: bool = true


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
			if int(Inventory.items.get("date_cluster", 0)) >= 22 or not Inventory.has_capacity_for("date_cluster", 1):
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
			_expect(int(Inventory.items.get("date_cluster", 0)) == before + 1, "A date comes from its actual pickup.")
			harvested += 1
			while not player.can_move and not stopped:
				await get_tree().physics_frame


func supply_city() -> void:
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var available: int = int(Inventory.items.get("date_cluster", 0))
	var amount: int = mini(maxi(8 - storage.get_food_supply_points(), 0), maxi(available - 14, 0))
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
	if int(Inventory.items.get("date_cluster", 0)) < 18:
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


func gather(site_name: String) -> void:
	await upkeep()
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
	_expect(runtime.inspector.visible, "The real worksite inspector opens: " + site_name)
	if stopped:
		return
	runtime.inspector.select_mode("Hourly")
	var item_id: String = runtime.sites[site_name].item_id
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var city_before: int = int(storage.get_available_items().get(item_id, 0))
	var player_before: int = int(Inventory.items.get(item_id, 0))
	await runtime._start_work(180)
	_expect(runtime.last_work_result.minutes == 180 and not runtime.last_work_result.interrupted and runtime.last_work_result.units > 0, "A normal three-hour work session yields its output: " + site_name)
	if require_city_worksite_output:
		var city_after: int = int(storage.get_available_items().get(item_id, 0))
		_expect(city_after - city_before == int(runtime.last_work_result.units) and int(Inventory.items.get(item_id, 0)) == player_before, "Worksite output enters City Storage directly; the player's bag is unchanged.")
	await eat()


func _fetch_material(id: String, minimum: int) -> void:
	# If the integrated logistics route placed the output in City Storage, take
	# it back into the player's inventory before a player-funded house build.
	var missing: int = maxi(0, minimum - int(Inventory.items.get(id, 0)))
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var available: int = int(storage.get_available_items().get(id, 0))
	if missing <= 0 or available <= 0:
		return
	var area: Node2D = runtime.get_node("CityStorageArea")
	await walk(area.get_node("CollisionShape2D").global_position)
	_expect(area.has_player_access() and bool(storage.withdraw_items_to_inventory({id: mini(missing, available)}).ok), "Player withdraws construction materials from City Storage.")


func _market() -> void:
	var merchant: Node = content.get_node("YSortWorld/TravelingMerchant")
	if stopped or not merchant.state.is_present():
		return
	await _fetch_material("wood_log", 6)
	var catalog: Array = merchant.state.get_catalog()
	if not seen_visits.has(TimeComponentManager.current_day):
		seen_visits[TimeComponentManager.current_day] = true
		var requests: Dictionary = {}
		for row: Dictionary in catalog:
			if int(row.demand) > 0:
				requests[row.item_id] = row.demand
		print("NEEDS_JOURNEY_VISIT ", {"day": TimeComponentManager.current_day, "requests": requests})
	var demand: int = 0
	var stock: int = 0
	for row: Dictionary in catalog:
		if row.item_id == "wood_log":
			demand = int(row.demand)
		elif row.item_id == "simple_clothes":
			stock = int(row.stock)
	var house: Node = content.get_node("YSortWorld/CitizenHousePlot").construction
	var reserve: int = 4 if house.phase in ["uncleared", "clearing", "empty"] else 0
	var sell: int = mini(demand, maxi(0, int(Inventory.items.get("wood_log", 0)) - reserve))
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var want: int = mini(stock, maxi(0, 2 - storage.get_clothing_item_count() - int(Inventory.items.get("simple_clothes", 0))))
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
	var unstaffed: bool = CitizenManager.get_all_applicants().is_empty() and WorkerDatabase.get_all_workers().is_empty()
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
	if unstaffed and (construction.phase != phase_before or construction.clearing_remaining < clearing_before or construction._remaining_work_units() < work_before):
		saw_house_work_without_applicants = true
	if phase_before == "empty":
		for id: String in construction.get_requirements():
			_expect(int(inventory_before.get(id, 0)) - int(Inventory.items.get(id, 0)) == int(construction.get_requirements()[id]), "House construction consumes its materials from the player's Inventory: " + id)
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
	var expect_zero: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--journey-phase="):
			phase = arg.trim_prefix("--journey-phase=")
		elif arg.begins_with("--merchant-request-seed="):
			merchant_seed = int(arg.trim_prefix("--merchant-request-seed="))
		elif arg == "--expect-zero":
			expect_zero = true
		elif arg == "--expect-worksite-city":
			require_city_worksite_output = true
		elif arg == "--allow-legacy-player-worksite":
			require_city_worksite_output = false
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
	if merchant_seed >= 0:
		# Sampling a reproducible request sequence is a fixture, not an assertion
		# that the production merchant's natural RNG always follows it.
		content.get_node("YSortWorld/TravelingMerchant").state._request_rng.seed = merchant_seed
		print("NEEDS_JOURNEY_REQUEST_SEED ", merchant_seed)
	if not require_city_worksite_output:
		print("NEEDS_JOURNEY_LOGISTICS: legacy player output (pre-integration only)")
	_expect(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(), "New Game begins without personal resources or hired workers.")
	_expect(CitizenManager.get_all_residents().size() == 2 and CitizenManager.get_all_applicants().size() == 2, "The normal two residents are initially eligible.")
	await _check_board(2)
	var sites: Dictionary = {"wood_log": "WoodSite", "clay_lump": "ClaySiteA", "reed_bundle": "ReedSite"}
	while not stopped and TimeComponentManager.current_day < 35:
		await upkeep()
		if stopped:
			break
		var first: CitizenData = CitizenManager.get_citizen(FIRST)
		var second: CitizenData = CitizenManager.get_citizen(SECOND)
		minimum_satisfaction = minf(minimum_satisfaction, minf(first.satisfaction, second.satisfaction))
		var house: Node = content.get_node("YSortWorld/CitizenHousePlot").construction
		if not saw_empty_board and WorkerDatabase.is_job_board_open() and CitizenManager.get_all_applicants().is_empty() and first.satisfaction < 0.5 and second.satisfaction < 0.5:
			await _check_board(0)
			saw_empty_board = true
		if house.phase == "built" and first.satisfaction >= 0.5 and second.satisfaction >= 0.5 and first.are_basic_needs_fulfilled() and second.are_basic_needs_fulfilled():
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
				await _fetch_material(id, int(needed[id]))
				if int(Inventory.items.get(id, 0)) < int(needed[id]):
					missing = id
					break
			if missing.is_empty():
				await _house_session()
			else:
				await gather(sites[missing])
		else:
			await _fetch_material("wood_log", 8)
			if int(Inventory.items.get("shekel", 0)) < 4 and int(Inventory.items.get("wood_log", 0)) < 8:
				await gather("WoodSite")
			else:
				await wait_minutes(60)
	if stopped:
		return
	var house: Node = content.get_node("YSortWorld/CitizenHousePlot").construction
	var first: CitizenData = CitizenManager.get_citizen(FIRST)
	var second: CitizenData = CitizenManager.get_citizen(SECOND)
	_expect(saw_empty_board and saw_house_work_without_applicants and house.phase == "built" and CityStockManager.shelter_capacity == 3, "Manual construction makes progress with no applicants or workers, then grants shelter.")
	_expect(bought_clothes >= 2 and deposited_clothes >= 2 and paid_wood >= 4, "Wood income actually buys and deposits clothing.")
	_expect(first.are_basic_needs_fulfilled() and second.are_basic_needs_fulfilled() and first.satisfaction >= 0.5 and second.satisfaction >= 0.5 and CitizenManager.get_all_applicants().size() >= 2, "Food, clothing and shelter recover both residents and their Job Board eligibility.")
	if expect_zero:
		_expect(is_zero_approx(minimum_satisfaction), "The selected long-delay fixture actually reaches zero satisfaction before recovering.")
	if stopped:
		return
	while not WorkerDatabase.is_job_board_open() and not stopped:
		await upkeep()
		await wait_minutes(30)
	await _check_board(2)
	print("NEEDS_JOURNEY_RECOVERED ", JSON.stringify({"day": TimeComponentManager.current_day, "satisfaction": [first.satisfaction, second.satisfaction], "minimum_satisfaction": minimum_satisfaction, "house_sessions": house_sessions, "harvested": harvested, "bought_clothes": bought_clothes, "wood_income": paid_wood, "sleeps": sleeps}))
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
