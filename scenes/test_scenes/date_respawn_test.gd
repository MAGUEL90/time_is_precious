extends Node

const MAP: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const STATE: Script = preload("res://scenes/pickup_item/date_palm_state.gd")
var failures: int = 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	TimeComponentManager.set_process(false)
	var map = MAP.instantiate()
	add_child(map)
	await get_tree().process_frame
	await get_tree().process_frame
	var tree = map.get_node("YSortWorld/DatePalmTree")
	var state = tree.state
	var player: Player = map.get_node("YSortWorld/Player")
	Inventory.items.clear()
	check(state.available.count(true) == 3 and state.remaining_minutes == 0, "Starts full without timer")
	var retained = tree._pickups[2]
	tree._pickups[0].on_player_interact(player)
	var delay: int = state.remaining_minutes
	check(delay >= 60 and delay <= 1080 and delay % 60 == 0, "Random whole-hour delay within 1..18")
	tree._pickups[1].on_player_interact(player)
	check(state.remaining_minutes == delay, "Second collection preserves deadline")
	TimeComponentManager.emit_time_signal()
	check(state.remaining_minutes == delay, "Clock snapshots do not tick timer")
	TimeComponentManager.advance_minutes(delay - 1)
	check(state.available.count(true) == 1, "No early refill")
	TimeComponentManager.advance_minutes(1)
	await get_tree().process_frame
	check(state.available.count(true) == 3 and tree._pickups.size() == 3, "Refills only missing slots")
	check(tree._pickups[2] == retained, "Existing pickup preserved")
	TimeComponentManager.advance_minutes(1440)
	check(state.available.count(true) == 3 and state.remaining_minutes == 0, "Full tree does not accumulate")
	tree._pickups[0].on_player_interact(player)
	delay = state.remaining_minutes
	map.queue_free()
	await get_tree().process_frame
	TimeComponentManager.advance_minutes(1)
	map = MAP.instantiate()
	add_child(map)
	await get_tree().process_frame
	await get_tree().process_frame
	tree = map.get_node("YSortWorld/DatePalmTree")
	check(tree.state == state and state.remaining_minutes == delay - 1, "Map return preserves elapsed timer")
	check(tree._pickups.size() == 2, "Map return preserves missing slot")
	map.queue_free()
	await get_tree().process_frame
	TimeComponentManager.advance_minutes(state.remaining_minutes)
	map = MAP.instantiate()
	add_child(map)
	await get_tree().process_frame
	await get_tree().process_frame
	tree = map.get_node("YSortWorld/DatePalmTree")
	check(tree._pickups.size() == 3, "Refill completes while map absent")
	var other = STATE.new()
	WorkStateRuntime.add_child(other)
	other.configure(2)
	other.collect(0)
	check(state.remaining_minutes == 0 and other.remaining_minutes > 0, "Independent tree timers")
	var observed: Dictionary = {}
	for cycle in range(100):
		other.collect(0)
		var wait_minutes: int = other.remaining_minutes
		check(wait_minutes >= 60 and wait_minutes <= 1080, "Cycle delay bounds")
		observed[wait_minutes] = true
		for minute in range(wait_minutes):
			other._on_minute_changed(0)
	check(observed.size() > 1, "Repeated cycles vary")
	other.queue_free()
	print("DateRespawnTest: ", "PASS" if failures == 0 else "FAIL")
	map.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
