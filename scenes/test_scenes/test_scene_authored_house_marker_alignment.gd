extends Node

const HOUSE: PackedScene = preload("res://scenes/citizen_house_plot/citizen_house_plot.tscn")

var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	var fixture := Node2D.new()
	add_child(fixture)
	var authored_map := Node2D.new()
	authored_map.name = "AuthoredMap"
	authored_map.position = Vector2(19, -37)
	fixture.add_child(authored_map)
	var authored_world := Node2D.new()
	authored_world.name = "YSortWorld"
	authored_world.position = Vector2(73, 42)
	authored_map.add_child(authored_world)
	var marker := Node2D.new()
	marker.name = "ToBeClean1"
	marker.position = Vector2(66, -205)
	authored_world.add_child(marker)
	var house_parent := Node2D.new()
	house_parent.name = "YSortWorld"
	house_parent.position = Vector2(-152, 81)
	fixture.add_child(house_parent)

	var house := HOUSE.instantiate() as Node2D
	house.set("plot_id", "authored_alignment_reentry_test")
	house.set("authored_marker_path", NodePath("../../AuthoredMap/YSortWorld/ToBeClean1"))
	house.position = Vector2(-600, 400)
	house_parent.add_child(house)
	_expect(marker.is_inside_tree(), "The authored marker is already in the tree before the detached house enters.")
	_expect(house.global_position == marker.global_position,
		"A detached configured instance aligns to the exact authored marker in _enter_tree.")
	await get_tree().process_frame
	var construction: Node = house.get("construction")
	_expect(construction.get("worker_entry_position") == house.call("get_worker_entry_position"),
		"The construction state caches the worker entrance at the aligned house position.")

	house_parent.remove_child(house)
	marker.global_position = Vector2(348, -126)
	house.position = Vector2(800, 900)
	house_parent.add_child(house)
	_expect(house.global_position == marker.global_position,
		"A re-entered house realigns to the marker's latest authored position.")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(construction.get("worker_entry_position") == house.call("get_worker_entry_position"),
		"A re-entered house refreshes the cached worker entrance after its children enter.")

	var plain_parent := Node2D.new()
	plain_parent.position = Vector2(31, -52)
	fixture.add_child(plain_parent)
	var plain_house := HOUSE.instantiate() as Node2D
	plain_house.set("plot_id", "unconfigured_house_fixture_test")
	plain_house.position = Vector2(47, 29)
	plain_parent.add_child(plain_house)
	_expect(plain_house.position == Vector2(47, 29),
		"A fixture with no authored marker path keeps its configured local position.")
	await get_tree().process_frame
	var plain_construction: Node = plain_house.get("construction")
	_expect(plain_construction.get("worker_entry_position") == plain_house.call("get_worker_entry_position"),
		"The unconfigured fixture still initializes its normal worker entrance.")

	fixture.queue_free()
	await get_tree().process_frame
	print("AuthoredHouseMarkerAlignmentTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
