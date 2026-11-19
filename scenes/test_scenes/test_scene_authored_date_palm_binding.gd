extends Node

## Synthetic integration fixture for the laptop-authored date-palm node.
## It does not modify the cloud authored scene or claim final-map render parity.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const BINDING = preload("res://scenes/map_authoring/authored_date_palm_binding.gd")
const PALM_SCRIPT: Script = preload("res://scenes/pickup_item/date_palm_spawner.gd")
const TREE_TEXTURE_PATH: String = "res://assets/objects/nature/trees/date_palm_tree.png"
const PICKUP_TEXTURE_PATH: String = "res://assets/objects/dates_pickup.png"
const PALM_NAMES: Array[String] = [
	"DatePalmTree", "DatePalmTree2", "DatePalmTree3",
	"DatePalmTree4", "DatePalmTree5", "DatePalmTree6",
]
const AUTHORED_POSITION: Vector2 = Vector2(83, -118)

var failures: int = 0
var checks: int = 0
var capture_root: String = ""
var xdg_data_root: String = ""
var store: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _has_isolated_user_data():
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false

	var profile_name: String = "authored_palm_binding_%d" % OS.get_process_id()
	var old_checkpoint: String = "user://%s/old_six/checkpoint.json" % profile_name
	var full_checkpoint: String = "user://%s/full_seven/checkpoint.json" % profile_name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(old_checkpoint.get_base_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(full_checkpoint.get_base_dir()))

	# Capture and write the six-ledger checkpoint before the synthetic palm exists.
	var baseline_map: Node = CITY.instantiate()
	get_tree().root.add_child(baseline_map)
	get_tree().current_scene = baseline_map
	await _wait_frames(6)
	store = WorkStateRuntime.get_node_or_null("CitySave")
	_check(store != null, "The city bootstrap creates the existing CitySave store.")
	if store == null:
		_finish()
		return
	store.disk.path = old_checkpoint
	store.bind_map(baseline_map)
	_check(store.snapshot._sources.nodes().size() == 6,
		"Before injection, the cloud map registers exactly six legacy palm ledgers.")
	var old_document: Dictionary = store.snapshot.capture(baseline_map)
	_check(not old_document.is_empty(), "The existing six-ledger CitySave snapshot captures before injection.")
	if not old_document.is_empty():
		var old_values = preload("res://scenes/new_scenes/save_game/city_save_values.gd").new()
		var old_raw: Dictionary = old_values.decode(old_document.state)
		_check(old_raw.get("pickup_sources", {}).size() == 6,
			"The baseline checkpoint contains only the six current palm ledgers.")
	_check(store.save_checkpoint(), "The isolated old six-ledger checkpoint is written before injection: " + store.last_error)
	var old_bytes_before: PackedByteArray = FileAccess.get_file_as_bytes(old_checkpoint)
	_check(not old_bytes_before.is_empty(), "The isolated old-checkpoint bytes are available for immutability checks.")

	baseline_map.queue_free()
	await _wait_frames(3)

	var map: Node = CITY.instantiate()
	var palm: Sprite2D = _make_synthetic_palm(map)
	if palm == null:
		_finish()
		return
	var before_transform: Transform2D = palm.transform
	var before_position: Vector2 = palm.position
	var before_scale: Vector2 = palm.scale
	var before_rotation: float = palm.rotation
	var before_visibility: bool = palm.visible
	var baseline_legacy: Dictionary = _legacy_view_snapshot(map)
	var bind_result: Dictionary = BINDING.bind_before_tree(map)
	_check(bool(bind_result.get("ok", false)), "The exact detached authored node binds: " + str(bind_result.get("error", "")))
	_check(not bool(bind_result.get("already_bound", true)), "The first bind reports a new binding.")
	_check(palm.get_script() == PALM_SCRIPT and palm.get("pickup_texture") is Texture2D
		and (palm.get("pickup_texture") as Texture2D).resource_path == PICKUP_TEXTURE_PATH,
		"Binding adds only the existing spawner and dates pickup texture.")
	_check(palm.texture != null and palm.texture.resource_path == TREE_TEXTURE_PATH
		and palm.transform == before_transform and palm.position == before_position
		and palm.scale == before_scale and is_equal_approx(palm.rotation, before_rotation)
		and palm.visible == before_visibility and palm.owner == map.get_node("AuthoredMap"),
		"Binding preserves authored tree art, transform, visibility, and ownership.")
	_check(_legacy_view_snapshot(map) == baseline_legacy,
		"The binding leaves all six legacy palm views unchanged.")

	# Repeated before-tree use is a strict no-op, including source configuration.
	palm.set("quantity", 2)
	var repeat_result: Dictionary = BINDING.bind_before_tree(map)
	_check(bool(repeat_result.get("ok", false)) and bool(repeat_result.get("already_bound", false)),
		"Repeated pre-tree binding with the same script is harmless.")
	_check(int(palm.get("quantity")) == 2, "Idempotent binding does not reset existing source configuration.")
	palm.set("quantity", 1)

	_check(_assert_rejections_without_mutation(), "Mismatch and late-bind rejection fixtures preserve their targets.")

	get_tree().root.add_child(map)
	get_tree().current_scene = map
	store.bind_map(map)
	await _wait_frames(6)
	var player: Player = map.get_node("YSortWorld/Player") as Player
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	var source_state: Node = palm.get("state") as Node
	var ledger_id: String = str(palm.get("tree_id"))
	var source_scene: String = str(source_state.get("source_scene")) if source_state != null else ""
	var expected_ledger_id: String = (CITY.resource_path + ":AuthoredMap/YSortWorld/DatePalmTree").sha256_text()
	_check(source_state != null and source_scene == CITY.resource_path and ledger_id == expected_ledger_id,
		"The authored palm registers the stable city-scene identity: source=%s ledger=%s" % [source_scene, ledger_id])
	_check(_legacy_views_are_disabled(map), "All six legacy palm views remain disabled after the authored source registers.")
	_check(_visible_palm_count(map) == 1 and palm.visible,
		"Exactly one date-palm tree view is visible in the city: the synthetic authored tree.")
	_check(palm.position == AUTHORED_POSITION and palm.scale == before_scale
		and is_equal_approx(palm.rotation, before_rotation) and palm.visible == before_visibility
		and palm.texture != null and palm.texture.resource_path == TREE_TEXTURE_PATH,
		"The active palm retains the authored date-palm artwork and exact position.")
	_check(_assert_default_config(palm), "The palm keeps the existing three-slot, quantity-one, 1–18 hour defaults.")
	_check(_fruit_count(map) == 3, "The active authored palm creates exactly three fruit pickups.")
	_check(store.snapshot._capture_city_drops(map).is_empty(),
		"Source fruit does not enter the personal ground-drop checkpoint collection.")
	var state_nodes: Dictionary = store.snapshot._sources.nodes()
	_check(state_nodes.size() == 7 and state_nodes.has(str(source_state.name)),
		"The full city source catalog includes the seventh authored palm ledger.")
	var late_result: Dictionary = BINDING.bind_before_tree(map)
	_check(not bool(late_result.get("ok", true)) and str(late_result.get("error", "")).contains("before"),
		"The helper explicitly refuses a late bind after scene-tree entry.")
	_check(palm.get_script() == PALM_SCRIPT and palm.get("state") == source_state,
		"Late-bind rejection leaves the running palm script and state untouched.")

	if not capture_root.is_empty():
		player.global_position = palm.global_position + Vector2(-40, 18)
		player.get_node("Camera2D").make_current()
		await _capture(map, "before-harvest.png")

	Inventory.items.clear()
	Inventory.max_load = 0.0
	var first_pickup: PickUpItem = palm.get("_pickups").get(0) as PickUpItem
	first_pickup.on_player_gather(player)
	await _wait_frames(2)
	_check(Inventory.items.is_empty() and source_state.get("available").count(true) == 3,
		"A full inventory rejects gathering and leaves all three fruit available.")
	_check(_fruit_count(map) == 3, "Rejected full-capacity gathering does not remove or duplicate fruit.")

	Inventory.max_load = 100.0
	first_pickup = palm.get("_pickups").get(0) as PickUpItem
	first_pickup.on_player_gather(player)
	await _wait_for_pickup_animation()
	_check(int(Inventory.items.get("date_cluster", 0)) == 3
		and source_state.get("available").count(true) == 0,
		"The existing gather handler collects exactly the three available dates once.")
	_check(palm.texture.resource_path == TREE_TEXTURE_PATH and palm.position == AUTHORED_POSITION
		and palm.scale == before_scale and is_equal_approx(palm.rotation, before_rotation)
		and palm.visible == before_visibility,
		"Harvesting leaves the date-palm art, position, scale, rotation, and visibility intact.")
	_check(_fruit_count(map) == 0, "Harvested fruit views disappear without creating duplicates.")
	_check(store.snapshot._capture_city_drops(map).is_empty(),
		"Harvested source pickups are not serialized as personal ground drops.")
	if not capture_root.is_empty():
		await _capture(map, "after-harvest.png")

	Inventory.max_load = Inventory.get_total_inventory_weight()
	var timer_minutes: int = int(source_state.get("remaining_minutes"))
	_check(timer_minutes >= 60 and timer_minutes <= 1080,
		"The source starts its normal 1–18 hour refill timer: %d minutes." % timer_minutes)
	store.disk.path = full_checkpoint
	var saved_before: Dictionary = store.snapshot.capture(map)
	var saved_values = preload("res://scenes/new_scenes/save_game/city_save_values.gd").new()
	var saved_raw: Dictionary = saved_values.decode(saved_before.state) if not saved_before.is_empty() else {}
	_check(saved_raw.get("pickup_sources", {}).size() == 7,
		"A fresh full CitySave snapshot captures all seven source ledgers.")
	_check(store.save_checkpoint(), "The fresh seven-ledger CitySave checkpoint writes: " + store.last_error)
	Inventory.items.clear()
	Inventory.max_load = 100.0
	source_state.get("available").fill(true)
	source_state.set("remaining_minutes", 0)
	source_state.emit_signal("changed")
	_check(store.load_checkpoint(), "The fresh seven-ledger CitySave checkpoint loads: " + store.last_error)
	await _wait_frames(4)
	_check(int(Inventory.items.get("date_cluster", 0)) == 3
		and source_state.get("available").count(true) == 0
		and int(source_state.get("remaining_minutes")) == timer_minutes,
		"Fresh Save/Load restores inventory, depletion, and the exact refill timer.")
	_check(saved_before == store.snapshot.capture(map),
		"Fresh Save/Load round-trips the complete state, including RNG and pickup-source identity.")
	_check(not FileAccess.get_file_as_bytes(full_checkpoint).is_empty(),
		"The fresh full checkpoint remains present after load.")

	# The six-source version-17 checkpoint predates this seventh source. Load is
	# expected to refuse it without migrating IDs or changing its file/live state.
	var live_before_old_load: Dictionary = store.snapshot.capture(map)
	var old_checkpoint_bytes_before: PackedByteArray = FileAccess.get_file_as_bytes(old_checkpoint)
	var old_validation_ok: bool = store.snapshot.prepare(old_document, map)
	_check(not old_validation_ok and store.snapshot.error == "Invalid pickup source state.",
		"Validation explicitly identifies the old six-ledger catalog as incompatible: " + store.snapshot.error)
	_check(store.snapshot.capture(map) == live_before_old_load,
		"Validation-only rejection does not mutate live state before the disk-load check.")
	store.disk.path = old_checkpoint
	var old_load_ok: bool = store.load_checkpoint()
	var old_checkpoint_bytes_after: PackedByteArray = FileAccess.get_file_as_bytes(old_checkpoint)
	var live_after_old_load: Dictionary = store.snapshot.capture(map)
	_check(not old_load_ok and store.last_error == "unsupported",
		"The disk load rejects the old checkpoint as unsupported by the seven-source catalog: " + store.last_error)
	_check(old_checkpoint_bytes_after == old_checkpoint_bytes_before and not old_checkpoint_bytes_after.is_empty(),
		"Rejected old-checkpoint load leaves its file bytes unchanged.")
	_check(live_after_old_load == live_before_old_load,
		"Rejected old-checkpoint load leaves all live state and the new palm ledger unchanged.")
	_check(not FileAccess.file_exists(old_checkpoint + ".bak")
		and not FileAccess.file_exists(old_checkpoint + ".tmp")
		and not FileAccess.file_exists(old_checkpoint + ".pending"),
		"The single old-save fixture has no backup fallback that could mask the rejection.")

	var saved_tree: Dictionary = _tree_appearance(palm)
	var saved_tree_id: String = ledger_id
	var saved_state_name: String = str(source_state.name)
	map.queue_free()
	await _wait_frames(4)
	map = CITY.instantiate()
	palm = _make_synthetic_palm(map)
	if palm == null:
		_finish()
		return
	var recreated_bind: Dictionary = BINDING.bind_before_tree(map)
	_check(bool(recreated_bind.get("ok", false)), "The same authored fixture rebinds before its recreated map enters the tree.")
	get_tree().root.add_child(map)
	get_tree().current_scene = map
	store.bind_map(map)
	await _wait_frames(6)
	player = map.get_node("YSortWorld/Player") as Player
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	if not capture_root.is_empty():
		player.global_position = palm.global_position + Vector2(-40, 18)
		player.get_node("Camera2D").make_current()
	source_state = palm.get("state") as Node
	_check(str(palm.get("tree_id")) == saved_tree_id and str(source_state.name) == saved_state_name
		and WorkStateRuntime.get_node_or_null(saved_state_name) == source_state,
		"Map teardown/recreate reuses the exact same source ledger identity and state node.")
	_check(_count_ledger_name(saved_state_name) == 1,
		"Map teardown/recreate does not add a duplicate ledger.")
	_check(source_state.get("available").count(true) == 0 and _fruit_count(map) == 0,
		"The recreated palm preserves depletion and does not mint fruit before its timer.")
	_check(_tree_appearance(palm) == saved_tree,
		"Recreating the synthetic palm preserves its authored tree art and transform.")

	_check(TimeComponentManager.advance_minutes(timer_minutes - 1), "The normal world clock advances to one minute before refill.")
	await _wait_frames(3)
	_check(int(source_state.get("remaining_minutes")) == 1 and source_state.get("available").count(true) == 0,
		"The palm remains empty until the exact refill minute.")
	_check(TimeComponentManager.advance_minutes(1), "The normal world clock advances through the refill deadline.")
	await _wait_frames(4)
	_check(int(source_state.get("remaining_minutes")) == 0 and source_state.get("available").count(true) == 3
		and _fruit_count(map) == 3,
		"The normal clock refills the same three fruit slots without duplicates.")
	_check(_legacy_views_are_disabled(map) and _visible_palm_count(map) == 1,
		"Refill keeps the six legacy views hidden and the single authored tree visible.")
	_check(_tree_appearance(palm) == saved_tree,
		"Refill leaves the date-palm art and authored transform unchanged.")
	if not capture_root.is_empty():
		await _capture(map, "after-refill.png")

	Inventory.max_load = Inventory.get_total_inventory_weight()
	var refilled_pickup: PickUpItem = palm.get("_pickups").get(0) as PickUpItem
	refilled_pickup.on_player_gather(player)
	await _wait_frames(2)
	_check(int(Inventory.items.get("date_cluster", 0)) == 3
		and source_state.get("available").count(true) == 3,
		"A full saved inventory cannot collect the refilled dates.")
	Inventory.max_load = 100.0
	refilled_pickup = palm.get("_pickups").get(0) as PickUpItem
	refilled_pickup.on_player_gather(player)
	await _wait_for_pickup_animation()
	_check(int(Inventory.items.get("date_cluster", 0)) == 6
		and source_state.get("available").count(true) == 0,
		"After capacity is restored, the existing gather handler collects exactly the refilled three.")
	_check(_fruit_count(map) == 0 and _tree_appearance(palm) == saved_tree,
		"The second harvest removes only fruit views and keeps the date tree intact.")
	_check(_legacy_views_are_disabled(map) and _visible_palm_count(map) == 1,
		"The six legacy palm views remain disabled through repeated harvest/refill.")
	if not capture_root.is_empty():
		await _capture(map, "after-refill-harvest.png")

	print("AuthoredDatePalmBindingTest: source_scene=%s ledger_id=%s" % [source_scene, saved_tree_id])
	print("AuthoredDatePalmBindingTest: " + ("PASS" if failures == 0 else "FAIL (%d)" % failures)
		+ " checks=%d failures=%d" % [checks, failures])
	_finish()


func _make_synthetic_palm(map: Node) -> Sprite2D:
	var authored_map: Node = map.get_node_or_null("AuthoredMap")
	var authored_world: Node = map.get_node_or_null("AuthoredMap/YSortWorld")
	if authored_map == null or authored_world == null or authored_world.get_node_or_null("DatePalmTree") != null:
		_check(false, "The synthetic fixture requires an empty DatePalmTree path inside AuthoredMap/YSortWorld.")
		return null
	var palm := Sprite2D.new()
	palm.name = "DatePalmTree"
	palm.position = AUTHORED_POSITION
	palm.texture = load(TREE_TEXTURE_PATH) as Texture2D
	if palm.texture == null:
		_check(false, "The observed date-palm texture loads in the cloud project.")
		return null
	authored_world.add_child(palm)
	palm.owner = authored_map
	return palm


func _assert_rejections_without_mutation() -> bool:
	var all_ok: bool = true
	var wrong_type_map: Node = CITY.instantiate()
	var wrong_type := Node2D.new()
	wrong_type.name = "DatePalmTree"
	wrong_type.position = AUTHORED_POSITION
	wrong_type_map.get_node("AuthoredMap/YSortWorld").add_child(wrong_type)
	wrong_type.owner = wrong_type_map.get_node("AuthoredMap")
	var wrong_type_before: Dictionary = {"script": wrong_type.get_script(), "position": wrong_type.position, "owner": wrong_type.owner}
	var result: Dictionary = BINDING.bind_before_tree(wrong_type_map)
	_check(not bool(result.get("ok", true)) and wrong_type.get_script() == wrong_type_before.script
		and wrong_type.position == wrong_type_before.position and wrong_type.owner == wrong_type_before.owner,
		"Wrong node type is rejected without mutation.")
	all_ok = all_ok and not bool(result.get("ok", true))
	wrong_type_map.free()

	var wrong_texture_map: Node = CITY.instantiate()
	var wrong_texture := Sprite2D.new()
	wrong_texture.name = "DatePalmTree"
	wrong_texture.position = AUTHORED_POSITION
	wrong_texture.texture = load(PICKUP_TEXTURE_PATH) as Texture2D
	wrong_texture_map.get_node("AuthoredMap/YSortWorld").add_child(wrong_texture)
	wrong_texture.owner = wrong_texture_map.get_node("AuthoredMap")
	var wrong_texture_before: Texture2D = wrong_texture.texture
	result = BINDING.bind_before_tree(wrong_texture_map)
	_check(not bool(result.get("ok", true)) and wrong_texture.get_script() == null
		and wrong_texture.texture == wrong_texture_before,
		"Unexpected tree art is rejected without mutation.")
	all_ok = all_ok and not bool(result.get("ok", true))
	wrong_texture_map.free()

	var foreign_script_map: Node = CITY.instantiate()
	var foreign_script := Sprite2D.new()
	foreign_script.name = "DatePalmTree"
	foreign_script.position = AUTHORED_POSITION
	foreign_script.texture = load(TREE_TEXTURE_PATH) as Texture2D
	foreign_script_map.get_node("AuthoredMap/YSortWorld").add_child(foreign_script)
	foreign_script.owner = foreign_script_map.get_node("AuthoredMap")
	foreign_script.set_script(preload("res://scenes/pickup_item/pickup_source.gd"))
	var foreign_script_before: Script = foreign_script.get_script()
	result = BINDING.bind_before_tree(foreign_script_map)
	_check(not bool(result.get("ok", true)) and foreign_script.get_script() == foreign_script_before,
		"A foreign script is rejected without replacement.")
	all_ok = all_ok and not bool(result.get("ok", true))
	foreign_script_map.free()

	var missing_path_map: Node = CITY.instantiate()
	result = BINDING.bind_before_tree(missing_path_map)
	_check(not bool(result.get("ok", true)) and str(result.get("error", "")).contains("path"),
		"A missing exact path is rejected explicitly.")
	all_ok = all_ok and not bool(result.get("ok", true))
	missing_path_map.free()
	return all_ok


func _legacy_view_snapshot(map: Node) -> Dictionary:
	var result: Dictionary = {}
	for palm_name: String in PALM_NAMES:
		var palm: Node = map.get_node_or_null("YSortWorld/" + palm_name)
		if palm == null:
			result[palm_name] = {"missing": true}
			continue
		result[palm_name] = {
			"script": palm.get_script(),
			"position": palm.position,
			"texture": (palm as Sprite2D).texture if palm is Sprite2D else null,
			"visible": (palm as CanvasItem).visible if palm is CanvasItem else false,
			"world_view_enabled": bool(palm.get("world_view_enabled")),
			"pickups": (palm.get("_pickups") as Dictionary).duplicate() if palm.get("_pickups") is Dictionary else {},
		}
	return result


func _legacy_views_are_disabled(map: Node) -> bool:
	for palm_name: String in PALM_NAMES:
		var palm: Node = map.get_node_or_null("YSortWorld/" + palm_name)
		if palm == null or palm.get_script() != PALM_SCRIPT or bool(palm.get("world_view_enabled")):
			return false
		if (palm as CanvasItem).visible or not (palm.get("_pickups") as Dictionary).is_empty():
			return false
	return true


func _visible_palm_count(map: Node) -> int:
	var count: int = 0
	for node: Node in map.find_children("*", "Sprite2D", true, false):
		if node.get_script() == PALM_SCRIPT and (node as CanvasItem).is_visible_in_tree():
			count += 1
	return count


func _fruit_count(map: Node) -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group("date_palm_pickups"):
		if map.is_ancestor_of(node) and not node.is_queued_for_deletion() \
				and not bool(node.get("is_collecting")):
			count += 1
	return count


func _assert_default_config(palm: Node) -> bool:
	return str(palm.get("item_id")) == "date_cluster" and int(palm.get("max_pickups")) == 3 \
		and int(palm.get("quantity")) == 1 and bool(palm.get("refill_enabled")) \
		and int(palm.get("refill_min_hours")) == 1 and int(palm.get("refill_max_hours")) == 18 \
		and (palm.get("pickup_texture") as Texture2D).resource_path == PICKUP_TEXTURE_PATH


func _tree_appearance(palm: Sprite2D) -> Dictionary:
	return {"texture": palm.texture.resource_path if palm.texture != null else "",
		"position": palm.position, "scale": palm.scale, "rotation": palm.rotation,
		"visible": palm.visible, "owner_name": str(palm.owner.name) if palm.owner != null else ""}


func _count_ledger_name(state_name: String) -> int:
	var count: int = 0
	for node: Node in WorkStateRuntime.get_children():
		if node.name == state_name:
			count += 1
	return count


func _capture(map: Node, filename: String) -> void:
	if capture_root.is_empty() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	_check(frame.get_size() == Vector2i(400, 225), filename + ": fixture uses the native 400x225 viewport")
	_check(frame.save_png(capture_root.path_join(filename)) == OK, filename + ": fixture capture saves")


func _has_isolated_user_data() -> bool:
	xdg_data_root = OS.get_environment("XDG_DATA_HOME").simplify_path().trim_suffix("/")
	var user_data_path: String = ProjectSettings.globalize_path("user://").simplify_path()
	var prefix: String = xdg_data_root + "/"
	if not xdg_data_root.is_absolute_path() or not user_data_path.begins_with(prefix):
		push_error("Authored palm test refuses to run outside an isolated absolute XDG_DATA_HOME. user://=%s XDG_DATA_HOME=%s" % [user_data_path, xdg_data_root])
		return false
	print("Authored palm test isolated user data: ", user_data_path)
	capture_root = OS.get_environment("TIP_PALM_CAPTURE_DIR").simplify_path()
	if not capture_root.is_empty():
		if not capture_root.is_absolute_path() or not capture_root.begins_with(prefix):
			push_error("TIP_PALM_CAPTURE_DIR must remain under the isolated XDG_DATA_HOME.")
			return false
		if DisplayServer.get_name() == "headless":
			print("Authored palm fixture capture skipped: the current display is headless.")
			capture_root = ""
		else:
			DirAccess.make_dir_recursive_absolute(capture_root)
	return true


func _wait_frames(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await get_tree().process_frame


func _wait_for_pickup_animation() -> void:
	await get_tree().create_timer(0.4).timeout
	await _wait_frames(2)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _finish() -> void:
	get_tree().quit(0 if failures == 0 else 1)
