extends Node

# Uses real map/doors/sleep/work execution with no seeded money or materials.
# Travel is teleported and clock ticks are deterministic, so this is not a pacing test.
var failures: int = 0
var content: Node
var player: Player
var runtime: Node

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in range(6):
		await get_tree().physics_frame

func _bind_map() -> void:
	content = get_tree().current_scene
	player = content.get_node("YSortWorld/Player")
	runtime = content.get_node_or_null("YSortWorld/WorkerRuntime")

func _measure(stage: String) -> void:
	print("MAIN_LOOP ", JSON.stringify({"stage": stage, "day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour, "minute": TimeComponentManager.current_minute,
		"inventory": Inventory.items, "energy": 1.0 - player.fatigue, "hunger": player.hunger, "focus": player.focus}))

func _door(path: String) -> void:
	player.global_position = content.get_node(path).global_position
	await get_tree().create_timer(1.0).timeout
	_bind_map()
	await _settle()

func _capture(suffix: String = "main-map") -> void:
	var folder := OS.get_environment("TIP_MERCHANT_CAPTURE_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join("merchant-" + suffix + ".png"))

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	# Keep the driver outside current_scene so real doors can replace the map.
	get_tree().current_scene = null
	content = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	_bind_map()
	await _settle()
	_expect(Inventory.items.is_empty() and not player.debug_disable_player_needs and not player.debug_disable_fatigue, "Fresh map starts empty with needs active.")
	_measure("start")
	await _capture()
	var wood = runtime.sites[&"WoodSite"]
	wood.toggle_participant("player")
	for batch: int in range(2):
		var marker: Marker2D = runtime.get_node("WorksiteMarkers/WoodSite")
		player.global_position = marker.global_position
		runtime._open_site_panel(marker)
		runtime.inspector.select_mode("Hourly")
		await runtime._start_work(180)
		_expect(runtime.last_work_result.minutes == 180 and not runtime.last_work_result.interrupted, "Three-hour work session completes using active energy.")
		_measure("wood_batch_%d" % (batch + 1))
	_expect(Inventory.items.get("wood_log", 0) == 7 and wood.stock == 65, "Six hours at initial energy yields seven logs.")
	var fatigue_before: float = player.fatigue
	await _door("YSortWorld/HomeDoor")
	_expect(content.name == "PlayerHomeInterior", "Home door opens existing sleep scene.")
	_expect(not player.debug_disable_player_needs and is_equal_approx(player.fatigue, fatigue_before), "Entering home retains needs instead of resetting fatigue.")
	var spot: Node = content.get_node("YSortWorld/SleepSpot")
	player.global_position = spot.global_position
	await _settle()
	await spot.on_player_interact(player)
	_measure("after_sleep")
	_expect(player.fatigue < fatigue_before and TimeComponentManager.current_hour == 23, "Existing sleep consumes seven hours and restores energy.")
	await _door("YSortWorld/ExitDoor")
	_expect(content.name == "ContentScene" and runtime != null, "Exit returns to main map.")
	_expect(runtime.sites[&"WoodSite"].stock == 65 and Inventory.items.get("wood_log", 0) == 7, "Same-day return preserves gathered resources and depleted stock.")
	TimeComponentManager.advance_minutes(540)
	await _settle()
	_measure("first_arrival")
	var merchant: Node = content.get_node("YSortWorld/TravelingMerchant")
	_expect(merchant.state.is_present() and not player.is_collapsing, "Player reaches first arrival with normal needs.")
	await _open_merchant(merchant)
	merchant.menu.sell_tab.pressed.emit()
	merchant.menu._on_catalog_item_pressed("wood_log")
	merchant.menu.max_button.pressed.emit()
	_expect(merchant.menu.quantity_spin_box.value == 6, "Sell Max respects the six-log request.")
	merchant.menu.confirm_button.pressed.emit()
	_expect( Inventory.items.get("shekel", 0) == 12 and Inventory.items.get("wood_log", 0) == 1, "First wood request earns twelve coins and leaves one log.")
	_expect(not merchant.state.trade("wood_log", 1, false).ok, "Leftover wood cannot bypass the visit quota.")
	_measure("first_sale")
	await _capture("first_sale")
	_expect(merchant.state.get_budget() == 108 and merchant.menu.confirm_button.disabled, "Sale debits trader and disables further sales at exhausted demand.")
	merchant.menu.back_button.pressed.emit()
	await _settle()
	await _open_merchant(merchant)
	merchant.menu.buy_tab.pressed.emit()
	merchant.menu._on_catalog_item_pressed("clay_lump")
	merchant.menu.quantity_spin_box.value = 2
	merchant.menu.confirm_button.pressed.emit()
	_expect(Inventory.items.get("shekel", 0) == 8 and Inventory.items.get("clay_lump", 0) == 2 and merchant.state.get_budget() == 112, "Earned money buys two clay and credits trader correctly.")
	_measure("purchase_clay")
	await _capture("purchase_clay")
	merchant.menu._on_catalog_item_pressed("wood_log")
	merchant.menu.quantity_spin_box.value = 1
	merchant.menu.confirm_button.pressed.emit()
	_expect(Inventory.items.get("shekel", 0) == 4 and Inventory.items.get("wood_log", 0) == 2 and merchant.state.get_budget() == 116, "One previously sold log costs four coins to buy back.")
	merchant.menu.sell_tab.pressed.emit()
	_expect(merchant.menu.confirm_button.disabled and merchant.menu.max_button.disabled, "Buying back wood does not restore sale quota.")
	_measure("buyback_quota_exhausted")
	await _capture("buyback_quota_exhausted")
	for row: Dictionary in merchant.state.get_catalog():
		if row.item_id == "wood_log":
			_expect(row.stock == 13 and row.demand == 0, "Wood stock accounts for six sold and one bought back; demand remains zero.")
		if row.item_id == "clay_lump":
			_expect(row.stock == 10, "Two purchased clay are deducted from stock.")
	merchant.menu.back_button.pressed.emit()
	await _settle()
	# Verify held stock and uncollected output survive another real home trip.
	var storage: Node = runtime.get_node("WoodStorage").get_storage()
	Inventory.remove_item("wood_log", 1)
	storage.quantity = 1
	storage.changed.emit()
	var water = runtime.sites[&"WaterSite"]
	water.toggle_participant("player")
	water.execute(180, player, runtime)
	var water_count: int = Inventory.items.get("water_jar", 0)
	_expect(water_count > 0, "Player earns a water unit for the ground persistence check.")
	Inventory.remove_item("water_jar", water_count)
	runtime._drop_output_at(water_count, Vector2.ZERO, Callable(), "water_jar")
	var water_stock: int = water.stock
	await _door("YSortWorld/HomeDoor")
	await _door("YSortWorld/ExitDoor")
	_expect(runtime.get_node("WoodStorage").get_storage().quantity == 1, "Stockpile survives a scene round trip.")
	_expect(runtime.sites[&"WaterSite"].stock == water_stock, "Round trip does not refill natural stock.")
	_expect(runtime.get_node("GroundOutput").get_child_count() == 1 and runtime.get_node("GroundOutput").get_child(0).quantity == water_count, "Uncollected output survives without duplication.")
	merchant = content.get_node("YSortWorld/TravelingMerchant")
	_expect(not merchant.state.trade("wood_log", 1, false).ok and Inventory.items.get("shekel", 0) == 4 and merchant.state.get_budget() == 116, "Trip home does not reset merchant income quota or wallet.")
	content.free()
	print("MerchantMainMapLoopTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _open_merchant(merchant: Node) -> void:
	player.global_position = merchant.global_position + Vector2(0, 5)
	await _settle()
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = "interact"
	get_viewport().push_input(event)
	var deadline: int = Time.get_ticks_msec() + 5000
	while (not is_instance_valid(merchant.greeting_balloon) or not is_instance_valid(merchant.greeting_balloon.dialogue_line)) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var balloon: BaseGameDialogueBalloon = merchant.greeting_balloon
	_expect(is_instance_valid(balloon) and not is_instance_valid(merchant.menu), "E begins with dialogue on every interaction.")
	if not is_instance_valid(balloon):
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
	_expect(is_instance_valid(merchant.menu), "Trade opens the transaction panel.")
