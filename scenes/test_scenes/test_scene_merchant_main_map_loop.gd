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

func _capture() -> void:
	var folder := OS.get_environment("TIP_MERCHANT_CAPTURE_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join("merchant-main-map.png"))

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
	var sale: Dictionary = merchant.state.trade("wood_log", 6, false)
	_expect(sale.ok and Inventory.items.get("shekel", 0) == 12 and Inventory.items.get("wood_log", 0) == 1, "First wood request earns twelve coins and leaves one log.")
	_expect(not merchant.state.trade("wood_log", 1, false).ok, "Leftover wood cannot bypass the visit quota.")
	_measure("first_sale")
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
	_expect(not merchant.state.trade("wood_log", 1, false).ok and Inventory.items.get("shekel", 0) == 12, "Trip home does not reset merchant income quota or wallet.")
	content.free()
	print("MerchantMainMapLoopTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
