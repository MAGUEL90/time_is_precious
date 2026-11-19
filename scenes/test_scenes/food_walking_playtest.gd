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
var navigator: Node

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
	if navigator == null:
		# Reuse the other walking fixture's collision-aware path calculations;
		# the detached driver never runs its own scene or moves the player.
		navigator = preload("res://scenes/test_scenes/mvp_first_playthrough.gd").new()
	navigator.content = content
	navigator.player = player
	navigator.runtime = content.get_node_or_null("YSortWorld/WorkerRuntime")
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

func walk(target: Vector2, door_target: bool = false) -> void:
	if stopped:
		return
	navigator.build_route(door_target)
	var route: AStarGrid2D = navigator.route
	var start := Vector2i((player.global_position / 8).round())
	var end := Vector2i((target / 8).round())
	route.set_point_solid(start, false)
	if door_target:
		route.set_point_solid(end, false)
	var points: PackedVector2Array = route.get_point_path(start, end)
	check(not points.is_empty(), "A physical walking route exists toward %s" % target)
	points.append(target)
	for point: Vector2 in points:
		var frames: int = 0
		while not stopped and player.global_position.distance_to(point) > 1.1:
			if door_target and SceneTransition.is_transitioning:
				release_input()
				return
			var delta: Vector2 = point - player.global_position
			release_input()
			if absf(delta.x) > 0.7:
				Input.action_press("move_right" if delta.x > 0 else "move_left")
			elif absf(delta.y) > 0.7:
				Input.action_press("move_down" if delta.y > 0 else "move_up")
			var before: Vector2 = player.global_position
			await get_tree().physics_frame
			distance += before.distance_to(player.global_position)
			walk_seconds += 1.0 / Engine.physics_ticks_per_second
			frames += 1
			if frames > 240:
				check(false, "Walking blocked at %s toward %s (route target %s)" % [player.global_position, point, target])
		release_input()
	for frame in range(3):
		await get_tree().physics_frame

func outdoor_walk(target: Vector2) -> void:
	# A tree's scenery can cover its visual center. Visit a nearby open point,
	# then use a separate in-range target for each actual fruit interaction.
	var candidates: Array[Vector2] = []
	for radius: float in [0.0, 8.0, 16.0, 24.0]:
		for angle: int in range(8):
			candidates.append(target + Vector2.from_angle(angle * TAU / 8.0) * radius)
	var approach: Vector2 = navigator._reachable_approach(candidates, target)
	check(approach != Vector2.INF, "The outdoor destination has a collision-clear approach")
	if not stopped:
		await walk(approach)

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
	var value: float = ItemDatabase.get_item_data("date_cluster").hunger_reduction
	var amount: int = mini(int(Inventory.items.get("date_cluster", 0)), floori(player.hunger / value))
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
		"harvested": harvested, "eaten": eaten, "dates": Inventory.items.get("date_cluster", 0),
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
			var approach: Vector2 = navigator._pickup_approach(pickup)
			check(approach != Vector2.INF, "A collision-clear pickup approach exists")
			if not stopped:
				await walk(approach)
			check(player.current_interactable == pickup, "Walking reaches date on " + str(tree.name))
			if stopped:
				return
			var before: int = Inventory.items.get("date_cluster", 0)
			var available_before: int = tree.state.available.count(true)
			await interact()
			var gained: int = int(Inventory.items.get("date_cluster", 0)) - before
			var consumed: int = available_before - tree.state.available.count(true)
			check(gained > 0 and gained == consumed, "E transfers the collected dates exactly once on " + str(tree.name))
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
	var avoided: Array[Vector2] = []
	for _attempt: int in range(12):
		var approach: Vector2 = navigator._site_approach(marker, avoided)
		check(approach != Vector2.INF, "A collision-clear worksite approach exists")
		if stopped:
			return
		await walk(approach)
		if not is_instance_valid(player.current_interactable) and not runtime._pickup_focused:
			break
		if player.current_interactable is Node2D:
			avoided.append((player.current_interactable as Node2D).global_position)
		else:
			await get_tree().physics_frame
	if stopped:
		return
	var site = runtime.sites[&"WoodSite"]
	if not site.participants.has("player"):
		site.toggle_participant("player")
	await interact()
	check(runtime.inspector.visible and runtime._selected_site == marker, "E opens the selected worksite after walking")
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

func enter_door(path: String, expected_scene: String, _outside: bool) -> void:
	var door = content.get_node(path)
	# Stop walking when the overlap starts the real scene transition.
	await walk(door.global_position, true)
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
	if navigator != null:
		navigator.free()
		navigator = null
	await get_tree().create_timer(6.0).timeout
	var final_scene = get_tree().current_scene
	get_tree().current_scene = null
	if is_instance_valid(final_scene):
		final_scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)
