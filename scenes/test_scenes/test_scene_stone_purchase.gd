extends "res://scenes/test_scenes/mvp_first_playthrough.gd"

## Explicit fixture currency and wood; stone must come from the real merchant UI.
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const LEGACY = preload("res://scenes/test_scenes/legacy_reliability_fixture.gd")
const MERCHANT = preload("res://scenes/traveling_merchant/merchant_state.gd")
const SAVE_PATH: String = "user://stone_purchase_test/checkpoint.json"
var store: Node

func _run() -> void:
	get_tree().current_scene = null
	TimeComponentManager.set_process(false)
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = SAVE_PATH
	menu.session_started.connect(func(_continued: bool): launched = true)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	await press(menu.new_game_button)
	for _frame: int in range(1200):
		if launched or stopped:
			break
		await get_tree().process_frame
	_expect(launched, "The real New Game opens.")
	if stopped:
		return
	bind_map()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	store = WorkStateRuntime.get_node("CitySave")
	var target: int = 1440 + 8 * 60
	if now() < target:
		_expect(TimeComponentManager.advance_minutes(target - now()), "Advance naturally to the first merchant visit.")
	var merchant: Node = content.get_node("YSortWorld/TravelingMerchant")
	_expect(merchant.state.is_present(), "The authored merchant is present on its normal schedule.")
	_test_legacy_offer_migration(merchant.state)
	Inventory.add_item("shekel", 20) # Explicit fixture money; normal price is charged.
	Inventory.add_item("wood_log", 6) # Fixture wood includes one extra for a guarded debit probe.
	var nested_trade: Dictionary = {}
	var observe_bulk := func():
		nested_trade.assign(merchant.state.trade("stone", 1, true))
	Inventory.items_changed.connect(observe_bulk)
	_expect(Inventory.consume_bulk_items({"wood_log": 1}), "Run one isolated bulk debit before the purchase.")
	Inventory.items_changed.disconnect(observe_bulk)
	_expect(not bool(nested_trade.get("ok", true)) and int(Inventory.items.get("shekel", 0)) == 20 and int(merchant.state._stock.get("stone", 0)) == 12, "A merchant trade cannot mutate Inventory during a bulk payment signal.")
	var city_before: Dictionary = WorkStateRuntime.get_node("CityToolStorage").items.duplicate(true)
	await walk(merchant.global_position + Vector2(0, 5))
	await interact(merchant)
	await _accept_merchant_greeting(merchant)
	if stopped:
		return
	var panel: Node = merchant.menu
	var found: bool = false
	for row: Node in panel.catalog_list.get_children():
		if str(row.get_meta("merchant_item_id", "")) == "stone":
			found = true
	_expect(found, "The merchant's real Buy panel lists stone.")
	panel._on_catalog_item_pressed("stone")
	panel.quantity_spin_box.value = 10
	_expect(not panel.confirm_button.disabled, "Ten stone can be bought with the quoted funds and capacity.")
	_expect(Inventory.try_add_bulk_items({"shekel": 1})
		and Inventory.consume_bulk_items({"shekel": 1})
		and not panel.confirm_button.disabled,
		"Read-only merchant quotes stay usable after a guarded Inventory transaction.")
	await press(panel.confirm_button)
	_expect(int(Inventory.items.get("stone", 0)) == 10 and int(Inventory.items.get("shekel", 0)) == 0 and int(merchant.state._stock.get("stone", 0)) == 2, "Purchase charges twenty Shekels and transfers exactly ten stones to Inventory.")
	merchant.close_menu()
	await _frames()
	var raid: Node = WorkStateRuntime.get_node("CityRaid")
	var quote: Dictionary = raid.get_work_quote("build")
	_expect(bool(quote.can_start) and raid.request_wall_work(quote), "Purchased personal stone and personal wood can start the wall.")
	_expect(not Inventory.items.has("stone") and not Inventory.items.has("wood_log") and WorkStateRuntime.get_node("CityToolStorage").items == city_before, "Wall work consumes the player materials once and never charges the city.")
	_expect(store.save_checkpoint(), "Save the player-funded wall after the normal purchase: " + store.last_error)
	var saved: Dictionary = store.snapshot.capture(content)
	var loaded: bool = store.load_checkpoint()
	var restored: Dictionary = store.snapshot.capture(content)
	_expect(loaded and same(restored, saved), "Continue does not repeat the stone purchase or construction charge: " + store.last_error)
	if stopped:
		return
	print("StonePurchaseTest: PASS")
	get_tree().quit(0)

func _test_legacy_offer_migration(merchant: Node) -> void:
	var original: Dictionary = store.snapshot.capture(content)
	var codec = VALUES.new()
	var raw: Dictionary = codec.decode(original.state)
	LEGACY.strip_v16_owners(raw)
	raw.merchant._offers.erase("stone")
	raw.merchant._stock.erase("stone")
	raw.merchant._demand.erase("stone")
	var old_stock: Dictionary = raw.merchant._stock.duplicate(true)
	var old_budget: int = raw.merchant._budget
	var legacy: Dictionary = original.duplicate(true)
	legacy.schema_version = 15
	legacy.state = codec.encode(raw)
	_expect(store.snapshot.prepare(legacy, content), "A genuine v15-shaped merchant ledger migrates: " + store.snapshot.error)
	if stopped:
		return
	var staged: Dictionary = store.snapshot.prepared.merchant
	_expect(staged._offers.has("stone") and int(staged._stock.stone) == 0 and staged._budget == old_budget, "The new stone offer is staged without restocking an in-progress legacy visit.")
	for id: String in old_stock:
		_expect(staged._stock[id] == old_stock[id], "Legacy merchant stock is retained for " + id)
	_expect(store.snapshot.capture(content) == original, "Preparing the merchant migration does not change any live owner.")
	var probe: Node = MERCHANT.new()
	probe._valid = true # Its already validated saved offer ledger is restored below.
	probe._offers = staged._offers.duplicate(true)
	probe._stock.assign(staged._stock)
	probe._demand.assign(staged._demand)
	probe._budget = staged._budget
	probe._visit_day = 1
	probe._latest_minute = 1440 + 8 * 60
	probe._on_time_changed(4, 8, 0, "clear")
	_expect(int(probe._stock.get("stone", 0)) == 12, "The next normal merchant visit refills the new offer once.")
	probe.free()

func _accept_merchant_greeting(merchant: Node) -> void:
	var balloon: BaseGameDialogueBalloon = merchant.greeting_balloon
	var deadline: int = Time.get_ticks_msec() + 5000
	while is_instance_valid(balloon) and not is_instance_valid(balloon.dialogue_line) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(is_instance_valid(balloon) and is_instance_valid(balloon.dialogue_line), "The merchant greeting loads.")
	if stopped:
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
	_expect(is_instance_valid(merchant.menu), "The real Trade choice opens the purchase panel.")
