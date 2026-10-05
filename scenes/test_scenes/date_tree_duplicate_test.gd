extends Node
var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	TimeComponentManager.set_process(false)
	var packed = load("res://scenes/content_scene/content_scene.tscn")
	var map = packed.instantiate()
	add_child(map)
	await get_tree().process_frame
	var tree = map.get_node("YSortWorld/DatePalmTree")
	var copy = tree.duplicate(Node.DUPLICATE_SCRIPTS)
	copy.name = "DatePalmTreeTestCopy"
	copy.position += Vector2(60, 0)
	tree.get_parent().add_child(copy)
	await get_tree().process_frame
	var original_state = tree.state
	var copy_state = copy.state
	check(tree.tree_id != copy.tree_id and original_state != copy_state, "Duplicate automatically receives independent identity")
	var player = map.get_node("YSortWorld/Player")
	tree._pickups[0].on_player_interact(player)
	check(original_state.available.count(true) == 2 and copy_state.available.count(true) == 3, "Original collection leaves duplicate full")
	copy._pickups[1].on_player_interact(player)
	var original_timer: int = original_state.remaining_minutes
	var copy_timer: int = copy_state.remaining_minutes
	await get_tree().create_timer(0.5).timeout
	map.queue_free()
	await get_tree().process_frame
	map = packed.instantiate()
	add_child(map)
	await get_tree().process_frame
	tree = map.get_node("YSortWorld/DatePalmTree")
	copy = tree.duplicate(Node.DUPLICATE_SCRIPTS)
	copy.name = "DatePalmTreeTestCopy"
	tree.get_parent().add_child(copy)
	await get_tree().process_frame
	check(tree.state == original_state and copy.state == copy_state, "Both identities survive map recreation")
	check(tree._pickups.size() == 2 and copy._pickups.size() == 2, "Each tree restores its own missing slots")
	check(original_state.remaining_minutes == original_timer and copy_state.remaining_minutes == copy_timer, "Neither reload restarts timer")
	var sibling_pickups: Array = copy._pickups.values()
	copy.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for pickup in sibling_pickups:
		check(not is_instance_valid(pickup), "Deleting a tree cleans its pickup views")
	print("DateTreeDuplicateTest: ", "PASS" if failures == 0 else "FAIL")
	map.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
