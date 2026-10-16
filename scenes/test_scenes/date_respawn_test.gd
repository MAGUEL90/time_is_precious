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

func disable_player_needs(map_instance: Node) -> void:
	var fixture_player: Player = map_instance.get_node("YSortWorld/Player")
	fixture_player.debug_disable_player_needs = true

func run() -> void:
	TimeComponentManager.set_process(false)
	var map = MAP.instantiate()
	add_child(map)
	await get_tree().process_frame
	await get_tree().process_frame
	disable_player_needs(map)
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
	disable_player_needs(map)
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
	disable_player_needs(map)
	tree = map.get_node("YSortWorld/DatePalmTree")
	check(tree._pickups.size() == 3, "Refill completes while map absent")
	var overlay = map.get_node("TimeDebugOverlay")
	player = map.get_node("YSortWorld/Player")
	tree._pickups[0].on_player_interact(player)
	delay = state.remaining_minutes
	overlay.panel.show()
	overlay._refresh_date_controls()
	check(state.remaining_minutes == delay and state.available.count(true) == 2, "Viewing debug does not mutate stock or timer")
	check(overlay.date_status.text.contains("2/3"), "Debug displays stock")
	check(not overlay.date_refill_button.disabled, "Debug refill available for missing stock")
	var inventory_before: int = Inventory.items.get("date_cluster", 0)
	overlay.date_refill_button.pressed.emit()
	await get_tree().process_frame
	check(state.available.count(true) == 3 and state.remaining_minutes == 0, "Debug refill clears timer and fills stock")
	check(Inventory.items.get("date_cluster", 0) == inventory_before, "Debug spawn does not grant inventory")
	overlay.refill_dates()
	await get_tree().process_frame
	check(tree._pickups.size() == 3 and overlay.date_refill_button.disabled, "Repeated debug refill remains capped")
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
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)
