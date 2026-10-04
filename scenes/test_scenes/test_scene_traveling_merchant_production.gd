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
	for cycle: int in range(1, 4):
		await _approach(merchant)
		merchant.on_player_interact(player)
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
		if cycle < 3:
			await _trade_ui("sun_dried_mudbrick", 20, false)
			_expect(Inventory.items.get("shekel", 0) == 100 + 35 * cycle, "Completed cycle earns 35 after material and service fees.")
			_expect(merchant.state.get_budget() == 120 - 42 * cycle, "Merchant wallet reconciles purchases and sales.")
		else:
			var before: Dictionary = Inventory.items.duplicate()
			var catalog_before: Array = merchant.state.get_catalog()
			var rejected: Dictionary = merchant.state.trade("sun_dried_mudbrick", 20, false)
			_expect(not rejected.ok and Inventory.items == before and merchant.state.get_catalog() == catalog_before and merchant.state.get_budget() == 54,
				"Oversized sale is rejected without partial mutation when merchant cannot pay.")
			await _trade_ui("sun_dried_mudbrick", 18, false)
			_expect(merchant.state.get_budget() == 0 and Inventory.items.get("sun_dried_mudbrick", 0) == 2,
				"Partial sale exhausts merchant money and leaves two player bricks.")
		_snapshot("cycle%d_sold" % cycle)
		await _close_merchant()
	_expect(completed_cycles == 3, "Three real production cycles complete.")
	_expect(TimeComponentManager.current_hour == 10 and TimeComponentManager.current_minute == 0, "Three batches advance 120 game minutes in this fixture.")
	await _approach(merchant)
	merchant.on_player_interact(player)
	await _trade_ui("sun_dried_mudbrick", 1, true)
	_expect(Inventory.items.get("shekel", 0) == 193 and merchant.state.get_budget() == 6, "Buying back a sold brick costs six.")
	await _trade_ui("sun_dried_mudbrick", 1, false)
	_expect(Inventory.items.get("shekel", 0) == 196 and merchant.state.get_budget() == 3, "Reselling the same brick returns only three.")
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
