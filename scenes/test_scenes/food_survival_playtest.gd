extends Node
## Automated optimistic food route: hourly visits, teleported travel, real doors/sleep.
var content: Node
var player: Player
var tree: Node
var state: Node
var failures: int = 0
var harvested: int = 0
var eaten: int = 0
var first_cap: String = ""
var delays: Array[int] = []
var seed_value: int = 1

func _ready() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func stamp() -> String:
	return "D%d %02d:%02d" % [TimeComponentManager.current_day, TimeComponentManager.current_hour, TimeComponentManager.current_minute]

func measure(stage: String) -> void:
	print("FOOD_MEASURE ", JSON.stringify({"seed": seed_value, "stage": stage, "time": stamp(), "hunger": player.hunger, "energy": 1.0 - player.fatigue, "focus": player.focus, "harvested": harvested, "eaten": eaten, "inventory": Inventory.items.get("date_cluster", 0), "remaining": state.remaining_minutes}))

func bind_map() -> void:
	content = get_tree().current_scene
	player = content.get_node("YSortWorld/Player")
	tree = content.get_node_or_null("YSortWorld/DatePalmTree")

func settle() -> void:
	for frame in range(6):
		await get_tree().physics_frame

func door(path: String) -> void:
	player.global_position = content.get_node(path).global_position
	await get_tree().create_timer(1.0).timeout
	bind_map()
	await settle()

func harvest_and_eat() -> void:
	if is_instance_valid(tree):
		for pickup in tree._pickups.values():
			if not is_instance_valid(pickup) or pickup.is_collecting:
				continue
			player.global_position = pickup.global_position
			var before: int = Inventory.items.get("date_cluster", 0)
			var prior_timer: int = state.remaining_minutes
			pickup.on_player_interact(player)
			harvested += int(Inventory.items.get("date_cluster", 0)) - before
			if prior_timer == 0 and state.remaining_minutes > 0:
				delays.append(floori(float(state.remaining_minutes) / 60.0))
	var qty: int = mini(int(Inventory.items.get("date_cluster", 0)), floori(player.hunger / 0.04))
	if qty > 0:
		var ui = content.get_node("InventoryUI")
		ui.player_ref = player
		var before: int = Inventory.items.get("date_cluster", 0)
		await ui._execute_use_item("date_cluster", qty)
		eaten += before - int(Inventory.items.get("date_cluster", 0))
	await get_tree().create_timer(0.4).timeout

func run() -> void:
	var seed_text := OS.get_environment("TIP_FOOD_SEED")
	if not seed_text.is_empty():
		seed_value = seed_text.to_int()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().current_scene = null
	content = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	bind_map()
	await settle()
	state = tree.state
	state._rng.seed = seed_value
	expect(Inventory.items.is_empty() and not player.debug_disable_player_needs, "Fresh inventory and active needs")
	measure("start")
	var start_minutes: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	var stop_reason := "72h completed"
	while TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute - start_minutes < 4320:
		await harvest_and_eat()
		if TimeComponentManager.current_hour == 16 and player.can_sleep():
			measure("before_sleep")
			var saved_state = state
			var saved_stock: Array = state.available.duplicate()
			var saved_timer: int = state.remaining_minutes
			await door("YSortWorld/HomeDoor")
			expect(content.name == "PlayerHomeInterior", "Real home entry")
			expect(state.available == saved_stock and state.remaining_minutes == saved_timer, "Door does not refill or reset timer")
			var spot = content.get_node("YSortWorld/SleepSpot")
			player.global_position = spot.global_position
			await settle()
			await spot.on_player_interact(player)
			measure("after_sleep")
			expect(state.remaining_minutes == maxi(0, saved_timer - 420), "Seven-hour sleep advances refill timer")
			await door("YSortWorld/ExitDoor")
			expect(content.name == "ContentScene" and tree.state == saved_state, "Real return retains tree ledger")
			expect(tree._pickups.size() == state.available.count(true), "Return materializes exact stock")
			continue
		for minute in range(60):
			TimeComponentManager.advance_minutes(1)
			if player.hunger >= 1.0 and first_cap.is_empty():
				first_cap = stamp()
			if player.is_collapsing:
				stop_reason = "collapse"
				break
		if stop_reason == "collapse":
			break
		await settle()
		if TimeComponentManager.current_hour == 10:
			measure("daily")
	measure(stop_reason)
	print("FOOD_RESULT ", JSON.stringify({"seed": seed_value, "stop": stop_reason, "time": stamp(), "first_hunger_cap": first_cap, "harvested": harvested, "eaten": eaten, "delays_hours": delays, "failures": failures}))
	# Let any collapse transition/animation finish before teardown.
	await get_tree().create_timer(3.0).timeout
	get_tree().quit(0 if failures == 0 else 1)
