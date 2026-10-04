extends Node

var failures: int = 0
var content: Node
var merchant: Node
var player: Player

func _ready() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _clock(day: int, hour: int, minute: int = 0) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute
	TimeComponentManager.emit_time_signal()

func _settle() -> void:
	for i: int in range(6):
		await get_tree().physics_frame
	await get_tree().process_frame

func _load_map() -> void:
	content = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	merchant = content.get_node("YSortWorld/TravelingMerchant")
	player = content.get_node("YSortWorld/Player")

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	get_viewport().push_input(event)
	await get_tree().process_frame

func _run() -> void:
	TimeComponentManager.set_process(false)
	_clock(0, 10)
	_load_map()
	await _settle()
	_expect(not merchant.state.is_present(), "Day zero is before the first visit.")
	_expect(merchant.get_node("VisitNotice/Label").text.contains("Tomorrow"), "The upcoming visit is announced a day ahead.")
	_expect(not merchant.get_node("MerchantVisual").visible, "Absent merchant is hidden.")
	_expect(Inventory.items.is_empty(), "Adding merchant never grants starting money or goods.")
	_clock(1, 8)
	await _settle()
	_expect(merchant.get_node("MerchantVisual").visible, "Merchant arrives at scheduled time.")
	merchant.on_player_interact(player)
	_expect(not is_instance_valid(merchant.menu), "Remote access is rejected.")
	player.global_position = merchant.global_position + Vector2(0, 5)
	await _settle()
	_expect(player.current_interactable == merchant, "Approaching merchant selects E interaction.")
	await _capture("arrival")
	Inventory.add_item("shekel", 20)
	await _press("interact")
	_expect(is_instance_valid(merchant.menu) and not player.can_move, "E opens trading and locks player movement.")
	_expect(not get_tree().paused, "World time continues while browsing merchant.")
	if not is_instance_valid(merchant.menu):
		_finish()
		return
	var initial_budget: int = merchant.state.get_budget()
	merchant.menu.quantity_spin_box.value = 2
	_expect(not merchant.menu.confirm_button.disabled, "Valid purchase enables confirmation.")
	merchant.menu.confirm_button.pressed.emit()
	_expect(Inventory.items.get("clay_lump", 0) == 2 and Inventory.items.get("shekel", 0) == 16, "UI request buys materials through authoritative trade.")
	_expect(merchant.state.get_budget() == initial_budget + 4, "Payment funds merchant budget.")
	await _capture("buy")
	var selected: String = merchant.menu.selected_item_id
	var catalog_button: Node = merchant.menu.catalog_list.get_child(0)
	_clock(1, 8, 1)
	_expect(merchant.menu.selected_item_id == selected and merchant.menu.catalog_list.get_child(0) == catalog_button, "A clock tick preserves catalog controls and selection.")
	await _press("open_inventory")
	_expect(not content.get_node("InventoryUI").visible and is_instance_valid(merchant.menu), "Trading blocks inventory shortcut without closing the trade.")
	var window: Control = merchant.menu.get_node("Root/Center/TextureWindow")
	_expect(get_viewport().get_visible_rect().encloses(window.get_global_rect()), "Trading window fits the logical viewport.")
	await _press("ui_cancel")
	await _settle()
	_expect(not is_instance_valid(merchant.menu) and player.can_move, "Escape closes menu and releases only merchant movement lock.")
	var ledger: Node = merchant.state
	var stock_before: Array = ledger.get_catalog()
	content.free()
	_load_map()
	await _settle()
	_expect(merchant.state == ledger and ledger.get_catalog() == stock_before and ledger.get_budget() == initial_budget + 4, "Map reload retains same visit ledger and balance.")
	player.global_position = merchant.global_position + Vector2(0, 5)
	await _settle()
	var base_child_count: int = merchant.get_child_count()
	for i: int in range(3):
		await _press("interact")
		_expect(is_instance_valid(merchant.menu), "Repeated open succeeds.")
		await _press("ui_cancel")
		await _settle()
	_expect(merchant.get_child_count() == base_child_count, "Repeated open/close frees old menu nodes.")
	await _press("interact")
	player.set_movement_locked(&"test_other_action", true)
	_clock(1, 18)
	await _settle()
	_expect(not is_instance_valid(merchant.menu) and not merchant.get_node("MerchantVisual").visible, "Departure closes live UI and hides merchant.")
	_expect(not player.can_move, "Departure preserves another action's movement restriction.")
	player.set_movement_locked(&"test_other_action", false)
	_expect(player.can_move, "Merchant lock was released on departure.")
	_expect(player.current_interactable != merchant, "Departed merchant cannot remain selected.")
	var inv_before: Dictionary = Inventory.items.duplicate()
	merchant._on_trade_requested("clay_lump", 1, true)
	_expect(Inventory.items == inv_before, "Stale UI request after departure cannot trade.")
	_clock(4, 8)
	await _settle()
	_expect(ledger.get_budget() == 120, "New visit receives configured finite budget.")
	await _press("interact")
	_expect(is_instance_valid(merchant.menu), "Standing at the stop on arrival enables interaction.")
	Inventory.add_item("sun_dried_mudbrick", 2)
	merchant.menu.sell_tab.pressed.emit()
	merchant.menu._on_catalog_item_pressed("sun_dried_mudbrick")
	merchant.menu.quantity_spin_box.value = 2
	_expect(not merchant.menu.confirm_button.disabled, "Sell mode quotes owned workshop output.")
	merchant.menu.confirm_button.pressed.emit()
	_expect(Inventory.items.get("shekel", 0) == 22 and not Inventory.items.has("sun_dried_mudbrick"), "Finished workshop goods produce real Shekel.")
	await _capture("trade")
	_expect(merchant.menu.confirm_button.disabled, "Selling the last owned goods disables another sale.")
	Inventory.items["shekel"] = 9223372036854775807
	Inventory.items_changed.emit()
	await get_tree().process_frame
	window = merchant.menu.get_node("Root/Center/TextureWindow")
	_expect(get_viewport().get_visible_rect().encloses(window.get_global_rect()), "Long balances must remain inside the viewport.")
	await _capture("long-balance")
	player.global_position += Vector2(150, 0)
	await _settle()
	_expect(not is_instance_valid(merchant.menu) and player.can_move, "Leaving access range closes the menu.")
	player.global_position = merchant.global_position + Vector2(0, 5)
	await _settle()
	await _press("interact")
	SceneTransition.is_transitioning = true
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not is_instance_valid(merchant.menu), "Scene transition closes trading.")
	SceneTransition.is_transitioning = false
	await _press("interact")
	content.free()
	content = null
	_expect(not get_tree().paused, "Unloading an open merchant menu leaves no pause behind.")
	_finish()

func _capture(suffix: String) -> void:
	var folder: String = OS.get_environment("TIP_MERCHANT_CAPTURE_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join("merchant-" + suffix + ".png"))

func _finish() -> void:
	if is_instance_valid(content):
		content.free()
	print("TravelingMerchantAccessTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
