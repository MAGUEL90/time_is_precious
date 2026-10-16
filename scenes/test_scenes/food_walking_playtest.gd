extends Node
## Offline fixed-frame playtest. Uses movement input, live clock, real work and doors.
## No teleport, food grants, needs guards, clock skips or debug refill in this driver.
const TREE_SCRIPT = preload("res://scenes/pickup_item/date_palm_spawner.gd")
const ACTIONS = ["move_left", "move_right", "move_up", "move_down"]
var content: Node
var player: Player
var failures := 0
var harvested := 0
var eaten := 0
var work_minutes := 0
var work_units := 0
var sleep_count := 0
var rounds := 0
var walk_seconds := 0.0
var distance := 0.0
var max_hunger := 0.0
var seed_value := 1
var worked_by_day: Dictionary = {}
var measurements: Array = []
var collected_by_tree: Dictionary = {}
var stopped := false

func _ready() -> void:
	call_deferred("run")

func now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		stopped = true
		push_error(message)

func _physics_process(_delta: float) -> void:
	sample_needs()

func sample_needs(_minute: int = 0) -> void:
	if is_instance_valid(player):
		max_hunger = maxf(max_hunger, player.hunger)
		if player.is_collapsing:
			stopped = true

func bind_map() -> void:
	content = get_tree().current_scene
	player = content.get_node("YSortWorld/Player")
	var index := 0
	for tree in trees():
		if not tree.state.has_meta("walking_seed"):
			tree.state._rng.seed = seed_value + 1009 * index
			tree.state.set_meta("walking_seed", true)
		index += 1

func trees() -> Array[Node]:
	var result: Array[Node] = []
	for child in content.get_node("YSortWorld").get_children():
		if child.get_script() == TREE_SCRIPT:
			result.append(child)
	return result

func release_input() -> void:
	for action in ACTIONS:
		Input.action_release(action)

func walk_axis(target: Vector2, axis: int) -> void:
	var frames := 0
	while not stopped and is_instance_valid(player) and absf(player.global_position[axis] - target[axis]) > 1.0:
		release_input()
		var positive: bool = target[axis] > player.global_position[axis]
		Input.action_press(ACTIONS[(1 if positive else 0) if axis == 0 else (3 if positive else 2)])
		var before := player.global_position
		await get_tree().physics_frame
		if not is_instance_valid(player):
			break
		distance += before.distance_to(player.global_position)
		walk_seconds += 1.0 / Engine.physics_ticks_per_second
		frames += 1
		if frames > 1800:
			check(false, "Walking blocked at %s toward %s" % [player.global_position, target])
			break
	release_input()

func walk(target: Vector2) -> void:
	await walk_axis(target, 0)
	await walk_axis(target, 1)
	for frame in range(3):
		await get_tree().physics_frame

func outdoor_walk(target: Vector2) -> void:
	# Authored open east-west corridor below the home, above the worksites.
	var corridor_y: float = content.get_node("YSortWorld").global_position.y - 402.0
	await walk_axis(Vector2(player.global_position.x, corridor_y), 1)
	await walk(target)

func interact() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventAction.new()
	event.action = "interact"
	get_viewport().push_input(event)
	await get_tree().physics_frame

func eat() -> void:
	var amount: int = mini(int(Inventory.items.get("date_cluster", 0)), floori(player.hunger / 0.04))
	if amount <= 0 or stopped:
		return
	var ui = content.get_node("InventoryUI")
	ui.open_inventory()
	var before: int = Inventory.items.get("date_cluster", 0)
	await ui._execute_use_item("date_cluster", amount)
	eaten += before - int(Inventory.items.get("date_cluster", 0))
	ui.close_inventory()

func measure(stage: String) -> void:
	var row := {"stage": stage, "minute": now(), "hunger": player.hunger, "energy": 1.0 - player.fatigue,
		"focus": player.focus, "harvested": harvested, "eaten": eaten, "dates": Inventory.items.get("date_cluster", 0),
		"work_minutes": work_minutes, "work_units": work_units, "walk_seconds": walk_seconds}
	measurements.append(row)
	print("WALK_MEASURE ", JSON.stringify(row))

func harvest_round() -> void:
	for tree in trees():
		# Visit even an empty tree; the route does not know hidden respawn countdowns.
		await outdoor_walk(tree.global_position + Vector2(0, 36))
		if stopped:
			return
		for slot in tree._pickups.keys():
			var pickup = tree._pickups.get(slot)
			if not is_instance_valid(pickup) or pickup.is_collecting:
				continue
			await walk(pickup.global_position + Vector2(0, -5))
			check(player.current_interactable == pickup, "Walking reaches date on " + str(tree.name))
			if stopped:
				return
			var before: int = Inventory.items.get("date_cluster", 0)
			await interact()
			var gained: int = int(Inventory.items.get("date_cluster", 0)) - before
			check(gained == 1, "E collects one date on " + str(tree.name))
			harvested += gained
			collected_by_tree[tree.name] = int(collected_by_tree.get(tree.name, 0)) + gained
			await get_tree().create_timer(1.0).timeout
			if stopped:
				return
		await eat()
	rounds += 1
	measure("round")

func work() -> void:
	var runtime = content.get_node("YSortWorld/WorkerRuntime")
	var marker = runtime.get_node("WorksiteMarkers/WoodSite")
	await outdoor_walk(marker.global_position)
	if stopped:
		return
	var site = runtime.sites[&"WoodSite"]
	if not site.participants.has("player"):
		site.toggle_participant("player")
	await interact()
	check(runtime.inspector.visible, "E opens worksite after walking")
	if stopped:
		return
	runtime.inspector.select_mode("Hourly")
	await runtime._start_work(180)
	check(runtime.last_work_result.minutes == 180 and not runtime.last_work_result.interrupted, "Three-hour work completes")
	work_minutes += int(runtime.last_work_result.minutes)
	work_units += int(runtime.last_work_result.units)
	var day: int = TimeComponentManager.current_day
	worked_by_day[day] = int(worked_by_day.get(day, 0)) + int(runtime.last_work_result.minutes)
	await eat()
	measure("work")

func enter_door(path: String, expected_scene: String, outside: bool) -> void:
	var door = content.get_node(path)
	# Stop walking when the overlap starts the real scene transition.
	var target: Vector2 = door.global_position
	if outside:
		var corridor_y: float = content.get_node("YSortWorld").global_position.y - 402.0
		await walk_axis(Vector2(player.global_position.x, corridor_y), 1)
		await walk_axis(target, 0)
	else:
		await walk_axis(target, 0)
	var action: String = "move_down" if target.y > player.global_position.y else "move_up"
	Input.action_press(action)
	var frames := 0
	while not SceneTransition.is_transitioning and frames < 1200 and not stopped:
		var before := player.global_position
		await get_tree().physics_frame
		distance += before.distance_to(player.global_position)
		walk_seconds += 1.0 / Engine.physics_ticks_per_second
		frames += 1
	release_input()
	check(SceneTransition.is_transitioning, "Walk activates door")
	while SceneTransition.is_transitioning:
		await get_tree().process_frame
	bind_map()
	check(content.name == expected_scene, "Door arrives at " + expected_scene)

func sleep_at_home() -> void:
	var ledger: Array = []
	for tree in trees():
		ledger.append(tree.state)
	await enter_door("YSortWorld/HomeDoor", "PlayerHomeInterior", true)
	if stopped:
		return
	var spot = content.get_node("YSortWorld/SleepSpot")
	await walk(spot.global_position + Vector2(0, 25))
	check(player.current_interactable == spot, "Walk reaches sleep interaction")
	if stopped:
		return
	var before := now()
	await interact()
	while SceneTransition.is_transitioning or player.is_sleeping:
		await get_tree().process_frame
	check(now() - before >= 420, "Sleep advances seven hours")
	sleep_count += 1
	measure("sleep")
	await enter_door("YSortWorld/ExitDoor", "ContentScene", false)
	await eat()
	for i in range(trees().size()):
		check(trees()[i].state == ledger[i], "Tree state survives walk home")

func run() -> void:
	seed_value = maxi(1, OS.get_environment("TIP_FOOD_SEED").to_int())
	get_tree().current_scene = null
	content = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	bind_map()
	TimeComponentManager.minute_changed.connect(sample_needs)
	await get_tree().physics_frame
	check(trees().size() == 6 and Inventory.items.is_empty(), "Six authored trees and fresh inventory")
	check(not player.debug_disable_player_needs and not player.debug_disable_fatigue, "Needs active")
	check(is_equal_approx(TimeComponentManager.seconds_per_minute, 1.0) and is_equal_approx(player.speed, 50.0), "Normal clock and movement speed")
	var start := now()
	measure("start")
	while now() - start < 4320 and not stopped:
		if start + 4320 - now() < 90:
			while now() < start + 4320 and not stopped:
				await get_tree().physics_frame
			await eat()
			break
		await harvest_round()
		if stopped:
			break
		var hour: int = TimeComponentManager.current_hour
		if (hour >= 19 or hour < 8) and player.can_sleep() and player.fatigue >= 0.3 and start + 4320 - now() >= 430:
			await sleep_at_home()
		elif hour >= 8 and hour < 17 and int(worked_by_day.get(TimeComponentManager.current_day, 0)) < 360 and start + 4320 - now() >= 190:
			await work()
		else:
			var until := mini(now() + 180, start + 4320)
			while now() < until and not stopped:
				await get_tree().physics_frame
			await eat()
	check(now() - start == 4320 and not player.is_collapsing, "Completes 72 hours without collapse")
	check(work_minutes == 1080 and sleep_count >= 2 and collected_by_tree.size() == 6, "Route covers work, sleep and all six trees")
	measure("end")
	print("WALK_RESULT ", JSON.stringify({"seed": seed_value, "elapsed_minutes": now() - start, "failures": failures,
		"collapsed": player.is_collapsing, "harvested": harvested, "eaten": eaten, "dates": Inventory.items.get("date_cluster", 0),
		"work_minutes": work_minutes, "work_units": work_units, "sleep_count": sleep_count, "rounds": rounds,
		"walk_seconds": walk_seconds, "distance_px": distance, "max_hunger": max_hunger, "trees": collected_by_tree,
		"measurements": measurements}))
	print("FoodWalkingPlaytest: ", "PASS" if failures == 0 else "FAIL")
	release_input()
	await get_tree().create_timer(6.0).timeout
	var final_scene = get_tree().current_scene
	get_tree().current_scene = null
	if is_instance_valid(final_scene):
		final_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)
