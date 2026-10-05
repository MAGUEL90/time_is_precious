extends Node
var failures: int = 0

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	TimeComponentManager.set_process(false)
	var map = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(map)
	for frame in range(6):
		await get_tree().physics_frame
	var player: Player = map.get_node("YSortWorld/Player")
	var tree = map.get_node("YSortWorld/DatePalmTree")
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	for slot in range(3):
		var pickup = tree._pickups[slot]
		player.global_position = pickup.global_position + Vector2(0, -6)
		for frame in range(6):
			await get_tree().physics_frame
		expect(player.current_interactable == pickup, "Physical approach selects date slot %d" % slot)
		var before: int = Inventory.items.get("date_cluster", 0)
		player._unhandled_input(event)
		expect(Inventory.items.get("date_cluster", 0) == before + 1, "E collects approached date")
		await get_tree().create_timer(1.0).timeout
		print("DATE_ACCESS ", slot, " can_move=", player.can_move)
		expect(player.can_move, "Movement restored after pickup animation")
	var remaining: int = tree.state.remaining_minutes
	TimeComponentManager.advance_minutes(remaining - 1)
	TimeComponentManager.current_weather = "storm"
	TimeComponentManager.advance_minutes(1)
	await get_tree().process_frame
	expect(tree.state.available.count(true) == 3, "Current policy refills in storm")
	print("DatePickupAccessTest: ", "PASS" if failures == 0 else "FAIL")
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if failures == 0 else 1)
