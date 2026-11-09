extends Node

const MAP: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const PALM_SCRIPT: Script = preload("res://scenes/pickup_item/date_palm_spawner.gd")
const PALM_NAMES: Array[String] = [
	"DatePalmTree",
	"DatePalmTree2",
	"DatePalmTree3",
	"DatePalmTree4",
	"DatePalmTree5",
	"DatePalmTree6",
]

var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _has_isolated_user_data():
		return
	await get_tree().process_frame
	TimeComponentManager.set_process(false)
	var map: Node = MAP.instantiate()
	add_child(map)
	await _wait_frames(3)
	var world: Node = map.get_node("YSortWorld")
	var baseline_states: Dictionary = {}
	var expected_config: Dictionary = {
		"item_id": "date_cluster",
		"quantity": 1,
		"capacity": 3,
		"refill_enabled": true,
		"refill_min_hours": 1,
		"refill_max_hours": 18,
	}
	for palm_name: String in PALM_NAMES:
		var palm: Node = world.get_node(palm_name)
		var palm_state: Node = palm.get("state")
		check(palm_state != null, palm_name + " registers its existing ledger")
		if palm_state == null:
			continue
		var expected_tree_id: String = (MAP.resource_path + ":YSortWorld/" + palm_name).sha256_text()
		var config: Dictionary = palm_state.get("source_config")
		var view: CanvasItem = palm as CanvasItem
		var pickups: Dictionary = palm.get("_pickups")
		check(not bool(palm.get("world_view_enabled")), palm_name + " opts out of its world view")
		check(view != null and not view.visible, palm_name + " art is hidden")
		check(not palm.has_node("PalmSway"), palm_name + " does not create sway while hidden")
		check(pickups.is_empty(), palm_name + " creates no pickups on first refresh")
		check(str(palm.get("tree_id")) == expected_tree_id, palm_name + " keeps its path-derived ledger identity")
		check(str(palm_state.name) == "DatePalm_" + expected_tree_id, palm_name + " keeps its saved state node name")
		check(str(palm_state.get("source_scene")) == MAP.resource_path, palm_name + " keeps its source scene")
		check(config == expected_config and not config.has("world_view_enabled"), palm_name + " keeps its saved source configuration unchanged")
		baseline_states[palm_name] = {
			"state": palm_state,
			"tree_id": palm.get("tree_id"),
			"source_config": config.duplicate(true),
		}

	var depleted_state: Node = baseline_states["DatePalmTree"]["state"]
	depleted_state.call("collect", 0)
	await _wait_frames(2)
	var first_palm_pickups: Dictionary = world.get_node("DatePalmTree").get("_pickups")
	check(first_palm_pickups.is_empty(), "ledger changes do not spawn fruit while the palm view is disabled")
	var restored_remaining: int = int(depleted_state.get("remaining_minutes"))
	map.queue_free()
	await _wait_frames(2)
	map = MAP.instantiate()
	add_child(map)
	await _wait_frames(3)
	world = map.get_node("YSortWorld")
	for palm_name: String in PALM_NAMES:
		var palm: Node = world.get_node(palm_name)
		var palm_state: Node = palm.get("state")
		var baseline: Dictionary = baseline_states[palm_name]
		var pickups: Dictionary = palm.get("_pickups")
		check(palm_state == baseline["state"], palm_name + " reattaches to the same ledger after map return")
		check(palm.get("tree_id") == baseline["tree_id"], palm_name + " retains identity after map return")
		check(palm_state.get("source_config") == baseline["source_config"], palm_name + " retains source configuration after map return")
		check(pickups.is_empty(), palm_name + " restores with no world pickups")
	var restored_availability: Array = depleted_state.get("available")
	check(restored_availability.count(true) == 2, "restored ledger retains its depleted slot")
	check(int(depleted_state.get("remaining_minutes")) == restored_remaining, "restored ledger retains its refill deadline")
	depleted_state.emit_signal("changed")
	await _wait_frames(2)
	var restored_palm_pickups: Dictionary = world.get_node("DatePalmTree").get("_pickups")
	check(restored_palm_pickups.is_empty(), "explicit restored-state refresh still creates no fruit")

	var enabled_source = PALM_SCRIPT.new()
	enabled_source.name = "EnabledPalmControl"
	world.add_child(enabled_source)
	await _wait_frames(3)
	var enabled_pickups: Dictionary = enabled_source.get("_pickups")
	check(bool(enabled_source.get("world_view_enabled")), "ordinary pickup sources remain enabled by default")
	check(enabled_pickups.size() == 3, "enabled source still emits its three fruit pickups")
	print("LegacyDatePalmViewOptOutTest: " + ("PASS" if failures == 0 else "FAIL"))
	map.queue_free()
	await get_tree().process_frame
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)

func _has_isolated_user_data() -> bool:
	var xdg_data_home: String = OS.get_environment("XDG_DATA_HOME")
	if xdg_data_home.is_empty() or not xdg_data_home.is_absolute_path():
		push_error("Palm test requires an absolute XDG_DATA_HOME before creating any scene state.")
		get_tree().quit(1)
		return false
	var xdg_data_path: String = xdg_data_home.simplify_path()
	var user_data_path: String = ProjectSettings.globalize_path("user://").simplify_path()
	var xdg_data_prefix: String = xdg_data_path
	if not xdg_data_prefix.ends_with("/"):
		xdg_data_prefix += "/"
	if user_data_path != xdg_data_path and not user_data_path.begins_with(xdg_data_prefix):
		push_error("Palm test user:// data is outside XDG_DATA_HOME; refusing to start. user://=" + user_data_path + " XDG_DATA_HOME=" + xdg_data_path)
		get_tree().quit(1)
		return false
	print("Palm test isolated user data: ", user_data_path)
	return true

func _wait_frames(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await get_tree().process_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
