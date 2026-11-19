extends "res://scenes/test_scenes/test_scene_citizen_house_navigation.gd"

## Review-only scene. One pickup per site is a fixture; production is tested
## separately by the real three-process laborer/Continue flow.
const AUTHORED_LAYOUT = preload("res://scenes/content_scene/worksites/authored_resource_layout.gd")
const CITY_VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const WORKSITES: PackedScene = preload("res://scenes/content_scene/worksites/main_map_worksites.tscn")

func _run() -> void:
	get_tree().current_scene = null
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = "user://review_resource_routes/checkpoint.json"
	menu.session_started.connect(_on_session_started)
	get_tree().root.add_child(menu)
	menu._request_new_game()
	for frame in range(600):
		if launched:
			break
		await get_tree().process_frame
	_expect(launched and not continued, "The real menu opens the review New Game.")
	if not launched or continued:
		_finish_review()
		return
	content = get_tree().current_scene as Node2D
	player = content.get_node("YSortWorld/Player") as Player
	var runtime: Node = content.get_node("YSortWorld/WorkerRuntime")
	TimeComponentManager.set_process(false)
	if not _assert_authored_binding(runtime) or not _assert_failed_binding_is_safe() or not _assert_current_catalog_save(runtime):
		_finish_review()
		return
	var origin: Vector2 = runtime.get_node("WorkerDeparture/NearSpawn").global_position
	for id: String in ["ClaySiteA", "WoodSite", "ReedSite", "StrawSite", "WaterSite", "ClaySiteB", "WoodSiteB", "WoodSiteC", "WoodSiteD", "WoodSiteE"]:
		var marker: Node2D = runtime.get_node("WorksiteMarkers/" + id)
		for slot: int in [0, 1]:
			var target: Vector2 = runtime.site_slot_destination(StringName(id), slot)
			_expect(not runtime.site_approach_route(origin, target).is_empty(),
				"A worker can reach %s slot %d from the real departure point." % [id, slot])
		if failures > 0:
			_finish_review()
			return
		var item_id: String = runtime.sites[StringName(id)].item_id
		var before: int = int(Inventory.items.get(item_id, 0))
		_expect(runtime._drop_daily_output(1, marker), "The %s fixture pickup appears on the ground." % id)
		var pile: PickUpItem
		for child in runtime.get_node("GroundOutput").get_children():
			if child is PickUpItem and child.get_meta("daily_site", "") == id and not child.is_collecting:
				pile = child
				break
		_expect(is_instance_valid(pile), "The %s ground pickup exists." % id)
		if not is_instance_valid(pile):
			_finish_review()
			return
		var destination: Vector2 = pile.global_position + Vector2(0, -5)
		if not await _walk_to(destination, "ground output at " + id):
			_finish_review()
			return
		_expect(player.current_interactable == pile, "The player can select the %s pickup." % id)
		if player.current_interactable != pile:
			_finish_review()
			return
		await _press_interact()
		for frame in range(240):
			if player.can_move and not is_instance_valid(pile):
				break
			await get_tree().physics_frame
		_expect(int(Inventory.items.get(item_id, 0)) == before + 1 and player.can_move and not is_instance_valid(pile),
			"The %s item is picked up once and movement resumes." % id)
		if failures > 0:
			_finish_review()
			return
	_finish_review()

func _assert_authored_binding(runtime: Node) -> bool:
	var authored_world: Node2D = content.get_node("AuthoredMap/YSortWorld") as Node2D
	var marker_root: Node = runtime.get_node("WorksiteMarkers")
	var expected_ids: Array[String] = ["ClaySiteA", "ClaySiteB", "ReedSite", "StrawSite", "WaterSite",
		"WoodSite", "WoodSiteB", "WoodSiteC", "WoodSiteD", "WoodSiteE"]
	var registered_ids: Array[String] = []
	for key: Variant in runtime.get("sites"):
		registered_ids.append(str(key))
	registered_ids.sort()
	expected_ids.sort()
	_expect(registered_ids == expected_ids and marker_root.get_child_count() == 10,
		"The live runtime exposes the current ten unique authored site identities.")
	if registered_ids != expected_ids:
		return false

	var paths: Dictionary = runtime.get("authored_resource_paths")
	var binding: Dictionary = runtime.get("authored_resource_binding")
	_expect(paths.size() == 8 and bool(binding.get("ok", false)) and binding.bindings.size() == 8,
		"All eight tree, clay, and reed placeholders bind before the worksite catalog initializes.")
	if not bool(binding.get("ok", false)):
		return false
	var source_names: Dictionary = {
		"ClaySiteA": "ClaySite", "ClaySiteB": "ClaySite2", "ReedSite": "ReedSite",
		"WoodSite": "Poplar", "WoodSiteB": "Poplar2", "WoodSiteC": "Poplar3",
		"WoodSiteD": "Poplar4", "WoodSiteE": "Poplar5",
	}
	var saved_origins: Dictionary = runtime.get("_site_origins").duplicate(true)
	var saved_positions: Dictionary = {}
	var total_trees: int = 0
	for site_id: String in source_names:
		var marker: Node2D = marker_root.get_node(site_id) as Node2D
		var source: Sprite2D = authored_world.get_node(source_names[site_id]) as Sprite2D
		_expect(source != null and not source.visible, "The bound authored placeholder stays hidden at runtime: " + site_id)
		if source == null:
			return false
		saved_positions[site_id] = marker.global_position
		if site_id.begins_with("WoodSite"):
			var grove: Node2D = marker.get_node_or_null("WoodGrove") as Node2D
			var visible_trees: int = 0
			var hidden_stumps: int = 0
			if grove != null:
				for child: Node in grove.get_children():
					if str(child.name).begins_with("Tree") and child is CanvasItem and (child as CanvasItem).visible:
						visible_trees += 1
					if str(child.name).begins_with("Stump") and child is CanvasItem and not (child as CanvasItem).visible:
						hidden_stumps += 1
			total_trees += visible_trees
			_expect(visible_trees == 4 and hidden_stumps == 4,
				"Each authored wood marker presents its existing four-tree grove: " + site_id)
			var source_image: Image = source.texture.get_image()
			var source_bounds: Rect2i = source_image.get_used_rect()
			var feet := Vector2((source_bounds.position.x + source_bounds.end.x) * 0.5, source_bounds.end.y)
			_expect(marker.global_position.distance_to(_sprite_pixel_global(source, feet)) < 0.01,
				"Wood origin matches the authored tree's opaque feet: " + site_id)
		else:
			var icon: Sprite2D = marker.get_node("ResourceIcon") as Sprite2D
			var source_bounds: Rect2i = source.texture.get_image().get_used_rect()
			var target_center := Vector2(source_bounds.position) + Vector2(source_bounds.size) * 0.5
			var icon_bounds: Rect2i = icon.texture.get_image().get_used_rect()
			var icon_center := Vector2(icon_bounds.position) + Vector2(icon_bounds.size) * 0.5
			_expect(_sprite_pixel_global(icon, icon_center).distance_to(_sprite_pixel_global(source, target_center)) < 0.01,
				"Resource icon pixel center matches its authored clay/reed marker: " + site_id)
	_expect(total_trees == 20, "The five authored wood sites present 20 visible runtime trees total.")

	# A malformed later entry must not partially move sites or reveal/hide any art.
	var before_bad_positions: Dictionary = {}
	for site_id: String in saved_positions:
		before_bad_positions[site_id] = (marker_root.get_node(site_id) as Node2D).global_position
	var before_bad_visibility: Dictionary = {}
	for source_name: String in source_names.values():
		before_bad_visibility[source_name] = (authored_world.get_node(source_name) as Sprite2D).visible
	var bad_paths: Dictionary = paths.duplicate(true)
	bad_paths["ReedSite"] = NodePath("../../AuthoredMap/YSortWorld/Poplar5")
	var rejected: Dictionary = AUTHORED_LAYOUT.bind(runtime, bad_paths)
	_expect(not bool(rejected.get("ok", false)), "A malformed authored path is rejected before runtime initialization.")
	var unchanged: bool = true
	for site_id: String in before_bad_positions:
		unchanged = unchanged and (marker_root.get_node(site_id) as Node2D).global_position == before_bad_positions[site_id]
	for source_name: String in before_bad_visibility:
		unchanged = unchanged and (authored_world.get_node(source_name) as Sprite2D).visible == before_bad_visibility[source_name]
	_expect(unchanged, "Rejected mapping validation leaves every site and placeholder unchanged.")
	var first_tree: Sprite2D = authored_world.get_node("Poplar") as Sprite2D
	var original_scale: Vector2 = first_tree.scale
	first_tree.scale = original_scale * Vector2(2.0, 1.0)
	var rejected_transform: Dictionary = AUTHORED_LAYOUT.bind(runtime, paths)
	first_tree.scale = original_scale
	_expect(not bool(rejected_transform.get("ok", false)), "A mismatched authored/runtime sprite basis is rejected.")
	var transform_unchanged: bool = true
	for site_id: String in saved_positions:
		transform_unchanged = transform_unchanged and (marker_root.get_node(site_id) as Node2D).global_position == saved_positions[site_id]
	for source_name: String in source_names.values():
		transform_unchanged = transform_unchanged and not (authored_world.get_node(source_name) as Sprite2D).visible
	_expect(transform_unchanged, "Rejected transform validation neither moves sites nor changes placeholder visibility.")

	# Restore/re-enter uses the captured visibility only; it never recaptures the
	# authored origin or moves a marker, and it refuses another map instance.
	AUTHORED_LAYOUT.restore(binding)
	var restored: bool = true
	for source_name: String in source_names.values():
		restored = restored and (authored_world.get_node(source_name) as Sprite2D).visible
	_expect(restored, "Exiting the authored city restores placeholder visibility.")
	var unrelated_world := Node2D.new()
	_expect(not AUTHORED_LAYOUT.hide_for_world(binding, unrelated_world),
		"A parked runtime cannot hide placeholders owned by a different city instance.")
	unrelated_world.free()
	_expect(AUTHORED_LAYOUT.hide_for_world(binding, authored_world),
		"Re-entering the original city re-hides only its bound placeholders.")
	var origins_unchanged: bool = runtime.get("_site_origins") == saved_origins
	for site_id: String in saved_positions:
		origins_unchanged = origins_unchanged and (marker_root.get_node(site_id) as Node2D).global_position == saved_positions[site_id]
	_expect(origins_unchanged, "Repeated hide/restore preserves site origins and saved offsets.")
	return failures == 0

func _assert_failed_binding_is_safe() -> bool:
	var world: Node2D = content.get_node("YSortWorld") as Node2D
	var authored_world: Node2D = content.get_node("AuthoredMap/YSortWorld") as Node2D
	var probe: Node = WORKSITES.instantiate()
	probe.name = "AuthoredBindingFailureProbe"
	var bad_paths: Dictionary = probe.get("authored_resource_paths").duplicate(true)
	bad_paths["ReedSite"] = NodePath("../../AuthoredMap/YSortWorld/Poplar5")
	probe.set("authored_resource_paths", bad_paths)
	var marker_root: Node = probe.get_node("WorksiteMarkers")
	var original_positions: Dictionary = {}
	for marker: Node2D in marker_root.get_children():
		original_positions[str(marker.name)] = marker.position
	var placeholder_visibility: Dictionary = {}
	for source_name: String in ["ClaySite", "ClaySite2", "Poplar", "Poplar2", "Poplar3", "Poplar4", "Poplar5", "ReedSite"]:
		placeholder_visibility[source_name] = (authored_world.get_node(source_name) as Sprite2D).visible
	world.add_child(probe)
	_expect(not probe.visible and probe.process_mode == Node.PROCESS_MODE_DISABLED,
		"A malformed live mapping hides and disables its entire runtime root.")
	_expect(not bool(probe.get("_runtime_base_initialized")) and (probe.get("sites") as Dictionary).is_empty(),
		"A failed bind returns before initializing or staging worksite participants.")
	var safe_physics: bool = true
	for node: Node in probe.find_children("*", "Node", true, false):
		if node is CollisionObject2D:
			safe_physics = safe_physics and (node as CollisionObject2D).collision_layer == 0 and (node as CollisionObject2D).collision_mask == 0
		if node is Area2D:
			safe_physics = safe_physics and not (node as Area2D).monitoring and not (node as Area2D).monitorable
		if node is CollisionShape2D:
			safe_physics = safe_physics and (node as CollisionShape2D).disabled
		if node is CollisionPolygon2D:
			safe_physics = safe_physics and (node as CollisionPolygon2D).disabled
		if node is CanvasLayer:
			safe_physics = safe_physics and not (node as CanvasLayer).visible
	_expect(safe_physics, "A failed bind disables child collision, area monitoring, and canvas interactions.")
	var unchanged: bool = true
	for marker: Node2D in marker_root.get_children():
		unchanged = unchanged and marker.position == original_positions[str(marker.name)]
	for source_name: String in placeholder_visibility:
		unchanged = unchanged and (authored_world.get_node(source_name) as Sprite2D).visible == placeholder_visibility[source_name]
	_expect(unchanged, "A failed full-scene bind leaves all marker positions and map visibility unchanged.")
	probe.free()
	return failures == 0

func _assert_current_catalog_save(runtime: Node) -> bool:
	var store: Node = WorkStateRuntime.get_node("CitySave")
	var original_path: String = store.disk.path
	var run_id: String = "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var save_path: String = "user://authored_resource_mapping_test/" + run_id + "/current.json"
	var old_path: String = "user://authored_resource_mapping_test/" + run_id + "/old_catalog.json"
	var before: Dictionary = store.snapshot.capture(content)
	_expect(not before.is_empty(), "The live ten-site city can capture a current-catalog snapshot: " + store.snapshot.error)
	if before.is_empty():
		return false
	var values = CITY_VALUES.new()
	var raw: Dictionary = values.decode(before.state)
	_expect(values.error.is_empty() and raw.worksites.sites.size() == 10,
		"The current checkpoint records all ten authored site IDs.")
	if not values.error.is_empty() or raw.worksites.sites.size() != 10:
		return false

	store.disk.path = save_path
	_expect(store.save_checkpoint(), "The current ten-site checkpoint saves through the real CitySave path: " + store.last_error)
	_expect(store.load_checkpoint(), "The current ten-site checkpoint loads through the real CitySave path: " + store.last_error)
	var round_trip: Dictionary = store.snapshot.capture(content)
	var round_trip_values = CITY_VALUES.new()
	var round_trip_raw: Dictionary = round_trip_values.decode(round_trip.get("state", {}))
	var before_clock: Dictionary = raw.get("clock", {})
	var round_trip_clock: Dictionary = round_trip_raw.get("clock", {})
	var has_clock_timers: bool = before_clock.has("_timer") and round_trip_clock.has("_timer")
	var clock_timer_within_json_tolerance: bool = false
	if has_clock_timers:
		clock_timer_within_json_tolerance = absf(
			float(round_trip_clock["_timer"]) - float(before_clock["_timer"])
		) <= 1.0e-12
	_expect(round_trip_values.error.is_empty() and has_clock_timers and clock_timer_within_json_tolerance,
		"Only the fractional clock timer may differ by JSON machine-precision round-trip noise.")
	if has_clock_timers and clock_timer_within_json_tolerance:
		round_trip_clock["_timer"] = before_clock["_timer"]
		round_trip_raw["clock"] = round_trip_clock
	var before_envelope: Dictionary = before.duplicate(true)
	var round_trip_envelope: Dictionary = round_trip.duplicate(true)
	before_envelope.erase("state")
	round_trip_envelope.erase("state")
	# Decoding creates fresh CitizenData/VisualProfile instances. Compare their
	# whitelisted saved fields, not RefCounted object identity.
	var before_comparison_values = CITY_VALUES.new()
	var round_trip_comparison_values = CITY_VALUES.new()
	var before_value_state: Variant = before_comparison_values.encode(raw)
	var round_trip_value_state: Variant = round_trip_comparison_values.encode(round_trip_raw)
	_expect(round_trip_values.error.is_empty() and before_comparison_values.error.is_empty()
		and round_trip_comparison_values.error.is_empty() and round_trip_value_state == before_value_state
		and round_trip_envelope == before_envelope,
		"Current ten-site snapshot values round-trip exactly after normalizing only JSON clock timer precision.")

	var old_sites: Dictionary = {}
	var old_ids: Array[String] = ["ClaySiteA", "ClaySiteB", "ReedSite", "ReedSiteB", "StrawSite", "WaterSite",
		"WoodSite", "WoodSiteB", "WoodSiteC"]
	for site_id: String in old_ids:
		if site_id == "ReedSiteB":
			old_sites[site_id] = {"stock": int(raw.worksites.sites["ReedSite"].stock)}
		else:
			old_sites[site_id] = raw.worksites.sites[site_id].duplicate(true)
	var old_raw: Dictionary = raw.duplicate(true)
	old_raw.worksites.sites = old_sites
	var old_values = CITY_VALUES.new()
	var old_state: Variant = old_values.encode(old_raw)
	var old_document: Dictionary = before.duplicate(true)
	old_document["state"] = old_state
	var old_bytes: String = JSON.stringify(old_document)
	_expect(old_values.error.is_empty() and old_sites.size() == 9,
		"The synthetic previous catalog contains exactly its old nine IDs.")
	if not old_values.error.is_empty():
		store.disk.path = original_path
		return false

	var live_before_rejection: String = JSON.stringify(store.snapshot.capture(content))
	_expect(not store.snapshot.prepare(old_document, content),
		"Preparing a synthetic old nine-site checkpoint is rejected: " + store.snapshot.error)
	_expect(JSON.stringify(store.snapshot.capture(content)) == live_before_rejection,
		"Failed old-catalog preparation leaves every live city owner unchanged.")
	_write_test_file(old_path, old_bytes)
	store.disk.path = old_path
	_expect(not store.load_checkpoint(), "Loading a synthetic old nine-site file is rejected: " + store.last_error)
	_expect(FileAccess.get_file_as_string(old_path) == old_bytes,
		"Rejected old-catalog load preserves the exact checkpoint bytes.")
	_expect(JSON.stringify(store.snapshot.capture(content)) == live_before_rejection,
		"Rejected old-catalog load leaves the live city unchanged.")
	_expect(not store.save_checkpoint(), "Saving over an unsupported old-catalog file is rejected: " + store.last_error)
	_expect(FileAccess.get_file_as_string(old_path) == old_bytes,
		"Rejected save preserves the exact old-catalog file bytes.")
	store.disk.path = original_path
	_remove_test_files(save_path)
	_remove_test_files(old_path)
	return failures == 0

func _sprite_pixel_global(sprite: Sprite2D, pixel: Vector2) -> Vector2:
	var point: Vector2 = pixel
	var size: Vector2 = sprite.texture.get_size()
	if sprite.flip_h:
		point.x = size.x - point.x
	if sprite.flip_v:
		point.y = size.y - point.y
	if sprite.centered:
		point -= size * 0.5
	point += sprite.offset
	return sprite.to_global(point)

func _write_test_file(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(contents)
		file.close()

func _remove_test_files(path: String) -> void:
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		var candidate: String = path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))

func _finish_review() -> void:
	_release_input()
	get_tree().paused = false
	print("ReviewResourcePathsTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures, "; walked=", walked)
	get_tree().quit(0 if failures == 0 else 1)
