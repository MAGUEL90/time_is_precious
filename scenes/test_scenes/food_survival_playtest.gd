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
var tree_count: int = 1
const TREE_SCRIPT: Script = preload("res://scenes/pickup_item/date_palm_spawner.gd")

func _ready() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func stamp() -> String:
	return "D%d %02d:%02d" % [TimeComponentManager.current_day, TimeComponentManager.current_hour, TimeComponentManager.current_minute]

func measure(stage: String) -> void:
	print("FOOD_MEASURE ", JSON.stringify({"seed": seed_value, "trees": tree_count, "stage": stage, "time": stamp(), "hunger": player.hunger, "energy": 1.0 - player.fatigue, "focus": player.focus, "harvested": harvested, "eaten": eaten, "inventory": Inventory.items.get("date_cluster", 0), "remaining": state.remaining_minutes}))

func bind_map() -> void:
	content = get_tree().current_scene
	player = content.get_node("YSortWorld/Player")
	tree = content.get_node_or_null("YSortWorld/DatePalmTree")
	if is_instance_valid(tree):
		# Keep this historical comparison fixture independent of authored tree count.
		for extra in get_trees().slice(tree_count):
			extra.free()
		for index in range(1, tree_count):
			var copy_name: String = "DatePalmTree%d" % (index + 1)
			if not tree.get_parent().has_node(copy_name):
				var copy = tree.duplicate(Node.DUPLICATE_SCRIPTS)
				copy.name = copy_name
				copy.position += Vector2(48 * (index % 3), 72 * (floori(float(index) / 3.0) + 1))
				tree.get_parent().add_child(copy)
		for candidate in get_trees():
			if not candidate.state.has_meta("test_seeded"):
				candidate.state._rng.seed = seed_value + 1009 * get_trees().find(candidate)
				candidate.state.set_meta("test_seeded", true)

func get_trees() -> Array[Node]:
	var trees: Array[Node] = []
	if not is_instance_valid(tree):
		return trees
	for candidate in tree.get_parent().get_children():
		if candidate.get_script() == TREE_SCRIPT:
			trees.append(candidate)
	return trees

func settle() -> void:
	for frame in range(6):
		await get_tree().physics_frame

func door(path: String) -> void:
	player.global_position = content.get_node(path).global_position
	await get_tree().create_timer(1.0).timeout
	bind_map()
	await settle()

func harvest_and_eat() -> void:
	for candidate in get_trees():
		for pickup in candidate._pickups.values():
			if not is_instance_valid(pickup) or pickup.is_collecting:
				continue
			player.global_position = pickup.global_position
			var before: int = Inventory.items.get("date_cluster", 0)
			var prior_timer: int = candidate.state.remaining_minutes
			pickup.on_player_interact(player)
			harvested += int(Inventory.items.get("date_cluster", 0)) - before
			if prior_timer == 0 and candidate.state.remaining_minutes > 0:
				delays.append(floori(float(candidate.state.remaining_minutes) / 60.0))
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
	tree_count = maxi(1, OS.get_environment("TIP_FOOD_TREES").to_int())
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().current_scene = null
	content = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	bind_map()
	await settle()
	state = tree.state
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
	print("FOOD_RESULT ", JSON.stringify({"seed": seed_value, "trees": tree_count, "stop": stop_reason, "time": stamp(), "first_hunger_cap": first_cap, "harvested": harvested, "eaten": eaten, "delays_hours": delays, "failures": failures}))
	# Let feedback, faint animation and the existing scene transition finish before shutdown.
	var teardown_seconds: float = 0.0
	while teardown_seconds < 6.0:
		await get_tree().process_frame
		teardown_seconds += get_process_delta_time()
	var final_scene: Node = get_tree().current_scene
	get_tree().current_scene = null
	if is_instance_valid(final_scene):
		final_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)
