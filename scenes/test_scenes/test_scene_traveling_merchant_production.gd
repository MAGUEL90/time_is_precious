extends "res://scenes/test_scenes/mudbrick_player_flow_test.gd"

## Operating-loop fixture: infrastructure and capital are supplied, production inputs are not.
var merchant: Node2D

func _run() -> void:
	_prepare_fixture()
	TimeComponentManager.set_process(false)
	Inventory.items.clear()
	Inventory.add_item("shekel", 100)
	initial_materials.assign(JOB.inputs)
	_expect(WorkshopFacilityManager.set_facility_level("drying_yard", 1), "Fixture has a level-one yard.")
	TimeComponentManager.current_day = 1
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_minute = 0
	TimeComponentManager.emit_time_signal()
	worker.satisfaction = 0.5
	worker.reliability = 0.9
	merchant = preload("res://scenes/traveling_merchant/traveling_merchant.tscn").instantiate()
	merchant.position = Vector2(310, 127)
	add_child(merchant)
	await _frames(3)
	_expect(WorkShopStorage.items.is_empty(), "No raw materials or output are seeded into storage.")
	_snapshot("start")
	for cycle: int in range(1, 2):
		await _approach(merchant)
		merchant.on_player_interact(player)
		await _accept_greeting()
		for item_id: String in JOB.inputs:
			await _trade_ui(item_id, 3, true)
		_snapshot("cycle%d_bought" % cycle)
		await _close_merchant()
		await _approach(workshop)
		await _open_workshop()
		await _deposit_materials(_ui(WorkshopMenuUI) as WorkshopMenuUI)
		await _shape_wet_bricks()
		await _pay_output("wet_mudbrick", "Assign Work")
		_snapshot("cycle%d_shaping_paid" % cycle)
		await _dry_wet_bricks()
		await _pay_output("sun_dried_mudbrick", "sun-dried")
		await _withdraw_batch()
		_snapshot("cycle%d_ready_to_sell" % cycle)
		await _approach(merchant)
		merchant.on_player_interact(player)
		await _accept_greeting()
		await _trade_ui("sun_dried_mudbrick", 20, false)
		_expect(Inventory.items.get("shekel", 0) == 135 and merchant.state.get_budget() == 78, "One batch earns 35 after materials and fees.")
		_snapshot("cycle%d_sold" % cycle)
		await _close_merchant()
	_expect(completed_cycles == 1, "One real production cycle fills the visit's brick request.")
	_expect(TimeComponentManager.current_hour == 8 and TimeComponentManager.current_minute == 40, "Batch advances 40 game minutes.")
	await _approach(merchant)
	merchant.on_player_interact(player)
	await _accept_greeting()
	await _trade_ui("sun_dried_mudbrick", 1, true)
	_expect(Inventory.items.get("shekel", 0) == 129 and merchant.state.get_budget() == 84, "Buying back a sold brick costs six.")
	merchant.menu._set_buying(false)
	merchant.menu._on_catalog_item_pressed("sun_dried_mudbrick")
	_expect(merchant.menu.confirm_button.disabled and merchant.menu.max_button.disabled, "Exhausted request disables Sell and Max even after buying back stock.")
	var rejected: Dictionary = merchant.state.trade("sun_dried_mudbrick", 1, false)
	_expect(not rejected.ok and Inventory.items.get("sun_dried_mudbrick", 0) == 1 and Inventory.items.get("shekel", 0) == 129, "Exhausted quota rejects buyback resale without changing balances.")
	_snapshot("buyback_and_resale")
	await _close_merchant()
	print("TravelingMerchantProductionTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _approach(target: Node2D) -> void:
	player.global_position = target.global_position + Vector2(0, 8)
	for index: int in range(6):
		await get_tree().physics_frame
	await _frames(2)
	_expect(player.current_interactable == target, "Approached target is selected for interaction.")

func _trade_ui(item_id: String, quantity: int, buying: bool) -> void:
	_expect(is_instance_valid(merchant.menu), "Merchant UI is open.")
	if not is_instance_valid(merchant.menu):
		return
	merchant.menu._set_buying(buying)
	merchant.menu._on_catalog_item_pressed(item_id)
	merchant.menu.quantity_spin_box.value = quantity
	_expect(int(merchant.menu.quantity_spin_box.value) == quantity, "UI preserves requested quantity.")
	await _press(merchant.menu.confirm_button)

func _close_merchant() -> void:
	merchant.close_menu()
	await _frames(3)

func _withdraw_batch() -> void:
	await _open_workshop()
	await _press((_ui(WorkshopMenuUI) as WorkshopMenuUI).manage_button)
	var storage_ui: WorkshopStorageMenuUI = _ui(WorkshopStorageMenuUI) as WorkshopStorageMenuUI
	var slot: ItemSlot = storage_ui.free_slots_by_item_id["sun_dried_mudbrick"]
	for index: int in range(20):
		await _press(slot)
	await _press(storage_ui.withdraw_button)
	_expect(Inventory.items.get("sun_dried_mudbrick", 0) == 20 and WorkShopStorage.get_free_item_quantity("sun_dried_mudbrick") == 0,
		"All twenty produced bricks are withdrawn through storage UI.")
	await _press(storage_ui.back_button)
	await _press((_ui(WorkshopMenuUI) as WorkshopMenuUI).close_button)

func _snapshot(stage: String) -> void:
	print("ECONOMY ", JSON.stringify({"stage": stage, "player": Inventory.items, "merchant_shekel": merchant.state.get_budget(),
		"hour": TimeComponentManager.current_hour, "minute": TimeComponentManager.current_minute, "catalog": merchant.state.get_catalog()}))

func _accept_greeting() -> void:
	var balloon: BaseGameDialogueBalloon = merchant.greeting_balloon
	var deadline: int = Time.get_ticks_msec() + 5000
	while is_instance_valid(balloon) and not is_instance_valid(balloon.dialogue_line) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not is_instance_valid(balloon) or not is_instance_valid(balloon.dialogue_line):
		_expect(false, "Merchant greeting loaded before Trade.")
		return
	balloon.dialogue_label.skip_typing()
	balloon.show_responses()
	for item: Control in balloon.responses_menu.get_menu_items():
		var response: DialogueResponse = item.get_meta("response")
		if response.text.strip_edges() == "Trade":
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			item.gui_input.emit(click)
			break
	while not is_instance_valid(merchant.menu) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(is_instance_valid(merchant.menu), "Trade choice opens the transaction panel.")
