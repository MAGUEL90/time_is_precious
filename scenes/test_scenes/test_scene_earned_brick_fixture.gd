extends "res://scenes/test_scenes/test_scene_playable_needs_journey.gd"

## Continue the no-grant material audit, then isolate the production chain by
## placing the workshop in its built phase. Every ingredient, fee and the hired
## worker still come from the actual continued player journey. Construction of
## the workshop itself is covered separately; this fixture does not prove that
## its full construction was played through in this run.

func _run() -> void:
	checkpoint_path = JOURNEY_DIR + "/checkpoint.json"
	_expect(FileAccess.file_exists(checkpoint_path), "A completed earned-material checkpoint is required.")
	if stopped:
		return
	get_tree().current_scene = null
	var menu: Node = MENU.instantiate()
	menu.checkpoint_file.path = checkpoint_path
	menu.session_started.connect(func(continued: bool): launched = continued)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	menu.continue_button.pressed.emit()
	for _frame: int in range(1200):
		if launched:
			break
		await get_tree().process_frame
	_expect(launched, "Continue loads the player-earned material checkpoint.")
	if stopped:
		return
	TimeComponentManager.set_process(false)
	bind_map()
	await leave_home()
	_expect(int(Inventory.items.get("stone", 0)) >= 20 and int(Inventory.items.get("straw_bundle", 0)) >= 3
		and int(Inventory.items.get("water_jar", 0)) >= 3, "The continued bag retains bought stone and gathered recipe inputs.")
	var city: Node = WorkStateRuntime.get_node("CityToolStorage")
	var city_before: int = int(city.get_available_items().get("stone", 0))
	_expect(bool(city.deposit_from_inventory("stone", 20).ok)
		and int(city.get_available_items().get("stone", 0)) == city_before + 20,
		"Twenty purchased stones can be moved to city stock once to free carrying room.")
	var deadline: int = TimeComponentManager.current_day + 20
	while (int(Inventory.items.get("shekel", 0)) < 8 or not WorkerDatabase.is_job_board_open()) \
		and TimeComponentManager.current_day < deadline and not stopped:
		await upkeep()
		await _market()
		if int(Inventory.items.get("shekel", 0)) < 8 and int(Inventory.items.get("wood_log", 0)) < 3:
			await gather("WoodSite")
		else:
			await wait_minutes(60)
	_expect(int(Inventory.items.get("shekel", 0)) >= 8 and WorkerDatabase.is_job_board_open(), "Earned wood sales fund a real hire and both production fees.")
	if stopped:
		return
	await hire()
	if stopped:
		return
	while int(Inventory.items.get("wood_log", 0)) < 2 and not stopped:
		await gather("WoodSite")
	while int(Inventory.items.get("clay_lump", 0)) < 7 and not stopped:
		await gather("ClaySiteA")
	_expect(int(Inventory.items.get("reed_bundle", 0)) >= 4 and int(Inventory.items.get("straw_bundle", 0)) >= 3
		and int(Inventory.items.get("water_jar", 0)) >= 3, "All yard and recipe ingredients remain in the earned bag.")
	if stopped:
		return
	# Explicit fixture shortcut: the existing workshop appears already built.
	plot.construction.phase = "built"
	plot._sync_construction()
	await _frames(8)
	workshop = plot.get_node_or_null("BuiltWorkshop")
	_expect(is_instance_valid(workshop), "The isolated prebuilt workshop fixture is present.")
	await walk(workshop.get_node("InteractableComponent").global_position + Vector2(0, 4))
	_expect(player.current_interactable == workshop, "The production fixture is within the actual workshop interaction area.")
	var yard_before: Dictionary = Inventory.items.duplicate(true)
	var yard: Dictionary = WorkshopFacilityManager.upgrade_facility("drying_yard")
	_expect(bool(yard.get("success", false)) and WorkshopFacilityManager.get_facility_level("drying_yard") == 1, "The actual level-one yard is built from personal materials.")
	for id: String in WorkshopFacilityManager.get_facility_upgrade_requirements("drying_yard", 1):
		_expect(int(yard_before.get(id, 0)) - int(Inventory.items.get(id, 0)) == int(WorkshopFacilityManager.get_facility_upgrade_requirements("drying_yard", 1)[id]), "Yard consumes earned personal " + id + " exactly once.")
	var before_inputs: Dictionary = Inventory.items.duplicate(true)
	_expect(workshop.deposit_selected_items_from_player(JOB.inputs), "The actual workshop accepts the three earned recipe inputs.")
	for id: String in JOB.inputs:
		_expect(int(before_inputs.get(id, 0)) - int(Inventory.items.get(id, 0)) == int(JOB.inputs[id]) and WorkShopStorage.get_free_item_quantity(id) == int(JOB.inputs[id]), "Recipe transfer conserves earned " + id + ".")
	_expect(workshop.start_job_from_storage(JOB, [worker.worker_id] as Array[String]), "The hired worker starts the real shaping job.")
	var production_deadline: int = now() + 2 * 1440
	while WorkShopStorage.get_held_item_quantity("wet_mudbrick") < 20 and now() < production_deadline and not stopped:
		await wait_minutes(10)
		if player.fatigue >= 0.65 or player.hunger >= 0.7:
			await upkeep()
	_expect(WorkShopStorage.get_held_item_quantity("wet_mudbrick") >= 20, "The earned inputs produce at least one full held wet-brick batch, including any legitimate worker bonus.")
	if stopped:
		return
	workshop = plot.get_node("BuiltWorkshop")
	await walk(workshop.get_node("InteractableComponent").global_position + Vector2(0, 4))
	_pay_earned_lot("wet_mudbrick")
	_expect(ProcessManager.start_registered_process(DRYING.process_id, 20), "The real drying process accepts the paid wet batch.")
	await wait_minutes(DRYING.base_duration_minutes + 5)
	_expect(WorkShopStorage.get_held_item_quantity("sun_dried_mudbrick") == 20, "Drying creates twenty held construction bricks.")
	if stopped:
		return
	workshop = plot.get_node("BuiltWorkshop")
	await walk(workshop.get_node("InteractableComponent").global_position + Vector2(0, 4))
	_pay_earned_lot("sun_dried_mudbrick")
	var before_bricks: int = int(Inventory.items.get("sun_dried_mudbrick", 0))
	_expect(workshop.withdraw_selected_items_to_player({"sun_dried_mudbrick": 10})
		and int(Inventory.items.get("sun_dried_mudbrick", 0)) == before_bricks + 10
		and WorkShopStorage.get_free_item_quantity("sun_dried_mudbrick") == 10,
		"Ten finished bricks reach personal Inventory for the level-two yard without duplication.")
	print("EARNED_BRICK_FIXTURE ", JSON.stringify({"status": "PASS" if not stopped else "FAIL", "fixture": "prebuilt workshop only", "personal_bricks": Inventory.items.get("sun_dried_mudbrick", 0), "free_bricks": WorkShopStorage.get_free_item_quantity("sun_dried_mudbrick"), "wallet": Inventory.items.get("shekel", 0)}))
	if not stopped:
		get_tree().quit(0)


func _pay_earned_lot(item_id: String) -> void:
	var lot_id: String = ""
	for lot: Dictionary in WorkShopStorage.output_lots:
		if int(lot.get("items", {}).get(item_id, 0)) >= 20:
			lot_id = str(lot.lot_id)
			break
	_expect(not lot_id.is_empty(), "The produced batch has an actual fee-bearing lot: " + item_id)
	if not stopped:
		var result: Dictionary = WorkShopStorage.pay_output_lot(lot_id, Inventory)
		_expect(bool(result.get("success", false)) and WorkShopStorage.get_held_item_quantity(item_id) == 0,
			"Earned money pays the actual fee and releases " + item_id + ".")
