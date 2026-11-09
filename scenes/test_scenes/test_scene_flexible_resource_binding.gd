extends "res://scenes/test_scenes/test_scene_city_save.gd"

## Isolated fixtures only. Never edits the authored scene or a real save slot.
const LAYOUT = preload("res://scenes/content_scene/worksites/authored_resource_layout.gd")
const WORKSITES = preload("res://scenes/content_scene/worksites/main_map_worksites.tscn")
const WORKSITE_SCHEMA = preload("res://scenes/new_scenes/save_game/city_save_worksites.gd")
var checks: int = 0

func _expect(condition: bool, message: String) -> void:
	checks += 1
	super._expect(condition, message)

func _run() -> void:
	_expect(_validate_isolated_user_data(), "Use distinct absolute XDG profiles under this project's citysave_suite_qa directory.")
	if failures == 0:
		_expect(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://flexible_resource_binding")),
			"Use a fresh profile; never overwrite existing binding test files.")
	if failures > 0:
		_finish_binding()
		return
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	var extended: bool = OS.get_cmdline_user_args().has("--binding-catalog=extended")
	content = CONTENT_SCENE.instantiate()
	var runtime: Node2D = content.get_node("YSortWorld/WorkerRuntime")
	var world: Node2D = content.get_node("AuthoredMap/YSortWorld")
	if extended:
		var marker: Node = runtime.get_node("WorksiteMarkers/WoodSiteE").duplicate()
		marker.name = "WoodSiteExtension"
		runtime.get_node("WorksiteMarkers").add_child(marker)
		var source: Sprite2D = world.get_node("Poplar5").duplicate() as Sprite2D
		source.name = "ExtensionTree"
		source.position += Vector2(72, 72)
		world.add_child(source)
		runtime.authored_resource_paths["WoodSiteExtension"] = NodePath("../../AuthoredMap/YSortWorld/ExtensionTree")
	add_child(content)
	await _settle_physics()
	player = content.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	store = WorkStateRuntime.get_node("CitySave")
	store.disk.path = "user://flexible_resource_binding/current.json"
	_expect(bool(runtime.authored_resource_binding.get("ok", false)) and runtime._runtime_base_initialized,
		"The real map initializes with its configured resource catalog.")
	_expect(runtime.sites.size() == (11 if extended else 10), "The catalog keeps every stable runtime ID, including an explicitly added site.")
	if failures > 0:
		_finish_binding()
		return
	for session in runtime.sites.values():
		session.stock = maxi(1, int(session.stock) - 3)
	Inventory.items.assign({"date_cluster": 2})
	var original_document: Dictionary = store.snapshot.capture(content)
	_expect(not original_document.is_empty(), "The configured catalog captures without changing the save schema.")
	if original_document.is_empty():
		_finish_binding()
		return
	_expect(store.save_checkpoint(), "The configured catalog saves through CitySave: " + store.last_error)
	var saved_bytes: String = FileAccess.get_file_as_string(store.disk.path)
	var stock_before: Dictionary = {}
	for id: Variant in runtime.sites:
		stock_before[str(id)] = int(runtime.sites[id].stock)
	var origins: Dictionary = runtime._site_origins.duplicate(true)
	var paths: Dictionary = runtime.authored_resource_paths.duplicate(true)
	var group := Node2D.new()
	group.name = "ResourceArt"
	group.position = Vector2(131, -73)
	world.add_child(group)
	for pair: Array in [["WoodSite", "RenamedTree"], ["ClaySiteB", "RenamedClay"]]:
		var source: Sprite2D = runtime.get_node(paths[pair[0]]) as Sprite2D
		var old_global: Vector2 = source.global_position
		source.reparent(group, true)
		source.name = pair[1]
		paths[pair[0]] = runtime.get_path_to(source)
		_expect(source.global_position.is_equal_approx(old_global), "Regrouping preserves the authored sprite's global position.")
		_expect(str(source.name) == pair[1], "Authored display names can change independently of persistent site IDs.")
	runtime.authored_resource_paths = paths
	var rebound: Dictionary = LAYOUT.bind(runtime, paths)
	_expect(bool(rebound.get("ok", false)), "Updated explicit paths accept renamed sprites under a translated grouping node: " + str(rebound.get("error", "")))
	_expect(runtime._site_origins == origins, "Renaming/regrouping does not recapture or replace persistent site origins.")
	for repetition: int in range(2):
		_expect(store.load_checkpoint(), "Repeated load accepts the same-ID checkpoint after visual regrouping: " + store.last_error)
		_expect(FileAccess.get_file_as_string(store.disk.path) == saved_bytes, "Load never rewrites the input checkpoint.")
		for id: String in stock_before:
			_expect(int(runtime.sites[StringName(id)].stock) == int(stock_before[id]), "Stock stays attached to stable ID " + id)
		_expect(Inventory.items == {"date_cluster": 2}, "Repeated load does not duplicate inventory.")
	var values = VALUES.new()
	var raw: Dictionary = values.decode(original_document.state)
	_expect(values.error.is_empty(), "The original checkpoint decodes.")
	var missing: Dictionary = raw.duplicate(true)
	missing.worksites.sites.erase("WoodSiteE")
	_assert_save_rejected(original_document, missing, "A current checkpoint missing one configured ID remains rejected.")
	var foreign: Dictionary = raw.duplicate(true)
	foreign.worksites.sites["ForeignSite"] = {"stock": 24}
	_assert_save_rejected(original_document, foreign, "An unknown checkpoint ID remains rejected.")
	var legacy: Dictionary = raw.duplicate(true)
	legacy.worksites.schema_version = 5
	for id: Variant in legacy.worksites.sites.keys():
		if not WORKSITE_SCHEMA.LEGACY_SITE_IDS.has(str(id)):
			legacy.worksites.sites.erase(id)
	var legacy_document: Dictionary = original_document.duplicate(true)
	legacy_document.state = values.encode(legacy)
	var live_before: Dictionary = store.snapshot.capture(content)
	var input_before: String = JSON.stringify(legacy_document, "", true, true)
	var legacy_valid: bool = store.snapshot.prepare(legacy_document, content)
	_expect(legacy_valid != extended, "Known legacy catalog still migrates; a new, unmapped catalog extension requires an explicit save migration.")
	_expect(store.snapshot.capture(content) == live_before and JSON.stringify(legacy_document, "", true, true) == input_before,
		"Legacy validation/migration never mutates live state or the input document.")
	if extended:
		var old_current: Dictionary = raw.duplicate(true)
		old_current.worksites.sites.erase("WoodSiteExtension")
		_assert_save_rejected(original_document, old_current, "An older current-schema catalog is not silently filled with a newly added site.")
	_unit_bindings()
	print("FlexibleResourceBindingTest catalog=", "extended" if extended else "original", " checks=", checks)
	_finish_binding()

func _assert_save_rejected(document: Dictionary, raw: Dictionary, message: String) -> void:
	var values = VALUES.new()
	var bad: Dictionary = document.duplicate(true)
	bad.state = values.encode(raw)
	var live_before: Dictionary = store.snapshot.capture(content)
	var bytes_before: String = FileAccess.get_file_as_string(store.disk.path)
	_expect(not store.snapshot.prepare(bad, content), message)
	_expect(store.snapshot.capture(content) == live_before, "Rejected checkpoint leaves live state unchanged.")
	_expect(FileAccess.get_file_as_string(store.disk.path) == bytes_before, "Rejected checkpoint leaves disk bytes unchanged.")
	var original_path: String = store.disk.path
	var rejected_path: String = "user://flexible_resource_binding/rejected.json"
	var rejected_bytes: String = JSON.stringify(bad, "", true, true)
	var rejected_file: FileAccess = FileAccess.open(rejected_path, FileAccess.WRITE)
	rejected_file.store_string(rejected_bytes)
	rejected_file.close()
	store.disk.path = rejected_path
	_expect(not store.load_checkpoint(), "Disk Load rejects the same invalid catalog without applying it.")
	_expect(store.snapshot.capture(content) == live_before, "Rejected disk Load leaves every live owner unchanged.")
	_expect(FileAccess.get_file_as_string(rejected_path) == rejected_bytes and FileAccess.get_file_as_string(original_path) == bytes_before,
		"Neither rejected input nor the separate good checkpoint is rewritten.")
	store.disk.path = original_path

func _unit_bindings() -> void:
	var fixture := Node2D.new()
	fixture.name = "BindingFixture"
	var authored_map := Node2D.new()
	authored_map.name = "AuthoredMap"
	fixture.add_child(authored_map)
	var world := Node2D.new()
	world.name = "YSortWorld"
	authored_map.add_child(world)
	var runtime_world := Node2D.new()
	runtime_world.name = "RuntimeWorld"
	fixture.add_child(runtime_world)
	var runtime := Node2D.new()
	runtime_world.add_child(runtime)
	var packed: Node = WORKSITES.instantiate()
	var paths: Dictionary = packed.authored_resource_paths.duplicate(true)
	var markers: Node = packed.get_node("WorksiteMarkers")
	markers.owner = null
	packed.remove_child(markers)
	runtime.add_child(markers)
	packed.free()
	var source_map: Node = CONTENT_SCENE.instantiate()
	for id: String in paths:
		var source: Node = source_map.get_node("YSortWorld/WorkerRuntime").get_node(paths[id]).duplicate()
		world.add_child(source)
	source_map.free()
	add_child(fixture)
	var baseline: Dictionary = LAYOUT.bind(runtime, paths)
	_expect(bool(baseline.get("ok", false)) and baseline.bindings.size() == 8, "The unchanged authored map still binds exactly its existing eight sprites.")
	if not bool(baseline.get("ok", false)):
		fixture.free()
		return
	LAYOUT.restore(baseline)
	var reordered: Array = world.get_children()
	reordered.reverse()
	for node: Node in reordered:
		world.move_child(node, 0)
	var reorder_bind: Dictionary = LAYOUT.bind(runtime, paths)
	_expect(bool(reorder_bind.get("ok", false)), "Sibling ordering never determines resource identity.")
	LAYOUT.restore(reorder_bind)
	var tree: Sprite2D = world.get_node("Poplar")
	var origin: Vector2 = (markers.get_node("WoodSite") as Node2D).global_position
	var shift := Vector2(37, -19)
	tree.position += shift
	var moved: Dictionary = LAYOUT.bind(runtime, paths)
	_expect(bool(moved.get("ok", false)) and (markers.get_node("WoodSite") as Node2D).global_position.is_equal_approx(origin + shift),
		"Editing visual position translates the runtime site by the same amount, independent of hierarchy.")
	LAYOUT.restore(moved)
	var bad: Dictionary = paths.duplicate(true)
	bad.erase("ReedSite")
	_assert_binding_rejected(runtime, world, bad, "A missing configured binding is rejected atomically.")
	bad = paths.duplicate(true)
	bad["ReedSite"] = NodePath("../../AuthoredMap/YSortWorld/DoesNotExist")
	_assert_binding_rejected(runtime, world, bad, "A stale or missing node reference is rejected atomically.")
	bad = paths.duplicate(true)
	bad["WoodSiteE"] = paths.WoodSite
	_assert_binding_rejected(runtime, world, bad, "Duplicate literal references are rejected atomically.")
	bad["WoodSiteE"] = NodePath("../../AuthoredMap/YSortWorld/./Poplar")
	_assert_binding_rejected(runtime, world, bad, "Different path spellings cannot bind one Sprite2D twice.")
	bad = paths.duplicate(true)
	bad["WoodSite"] = tree.get_path()
	_assert_binding_rejected(runtime, world, bad, "Absolute paths are not accepted as scene-local references.")
	bad["WoodSite"] = NodePath(str(paths.WoodSite) + ":position")
	_assert_binding_rejected(runtime, world, bad, "Property paths cannot masquerade as resource nodes.")
	bad = paths.duplicate(true)
	bad["WoodSite"] = 7
	_assert_binding_rejected(runtime, world, bad, "Non-path values are rejected atomically.")
	var outside: Sprite2D = tree.duplicate() as Sprite2D
	outside.name = "OutsideTree"
	fixture.add_child(outside)
	bad = paths.duplicate(true)
	bad["WoodSite"] = runtime.get_path_to(outside)
	_assert_binding_rejected(runtime, world, bad, "A valid-looking sprite outside the authored world is rejected.")
	var layer := CanvasLayer.new()
	layer.name = "DifferentCanvas"
	world.add_child(layer)
	var layered: Sprite2D = tree.duplicate() as Sprite2D
	layer.add_child(layered)
	bad["WoodSite"] = runtime.get_path_to(layered)
	_assert_binding_rejected(runtime, world, bad, "A sprite on another canvas is rejected.")
	layer.free()
	var viewport := SubViewport.new()
	world.add_child(viewport)
	var isolated: Sprite2D = tree.duplicate() as Sprite2D
	viewport.add_child(isolated)
	bad["WoodSite"] = runtime.get_path_to(isolated)
	_assert_binding_rejected(runtime, world, bad, "A source rendered in another viewport is rejected.")
	viewport.free()
	var prior_texture: Texture2D = tree.texture
	tree.texture = load("res://assets/objects/worksites/clay_site.png")
	_assert_binding_rejected(runtime, world, paths, "Resource type and texture checks remain strict.")
	tree.texture = prior_texture
	tree.scale = Vector2(2, 1)
	_assert_binding_rejected(runtime, world, paths, "An incompatible visual basis is still rejected.")
	tree.scale = Vector2.ONE
	tree.flip_h = true
	_assert_binding_rejected(runtime, world, paths, "The existing tree flip restriction is retained.")
	tree.flip_h = false
	var known: Node = markers.get_node("WoodSite")
	known.item_id = "clay_lump"
	_assert_binding_rejected(runtime, world, paths, "A historical stable ID cannot be silently repurposed for another item.")
	known.item_id = "wood_log"
	var historical: Node = known.duplicate()
	historical.name = "ReedSiteB"
	markers.add_child(historical)
	var historical_source: Sprite2D = tree.duplicate() as Sprite2D
	historical_source.name = "HistoricalReedCandidate"
	world.add_child(historical_source)
	var historical_paths: Dictionary = paths.duplicate(true)
	historical_paths["ReedSiteB"] = runtime.get_path_to(historical_source)
	_assert_binding_rejected(runtime, world, historical_paths, "An inactive historical ReedSiteB ID cannot be repurposed as a wood site.", "wrong resource type: ReedSiteB")
	historical.free()
	historical_source.free()
	var source_visible: bool = tree.visible
	tree.visible = false
	var rebound: Dictionary = LAYOUT.bind(runtime, paths)
	_expect(bool(rebound.get("ok", false)), "Repeated binding after rejected edits succeeds.")
	LAYOUT.restore(rebound)
	_expect(not tree.visible, "Restoration preserves originally hidden art instead of showing everything.")
	tree.visible = source_visible
	var foreign_world := Node2D.new()
	_expect(not LAYOUT.hide_for_world(rebound, foreign_world), "A parked binding cannot hide an unrelated map instance.")
	foreign_world.free()
	_expect(LAYOUT.hide_for_world(rebound, world), "The original authored world can re-hide its own bound art.")
	LAYOUT.restore(rebound)
	fixture.free()

func _assert_binding_rejected(runtime: Node2D, world: Node2D, paths: Dictionary, message: String, error_fragment: String = "") -> void:
	var before: Dictionary = _binding_state(runtime, world)
	var result: Dictionary = LAYOUT.bind(runtime, paths)
	_expect(not bool(result.get("ok", false)), message)
	if not error_fragment.is_empty():
		_expect(error_fragment in str(result.get("error", "")), "The fixture reaches its intended validation guard: " + error_fragment)
	_expect(_binding_state(runtime, world) == before, "Rejected binding does not move any marker or hide any sprite.")

func _binding_state(runtime: Node2D, world: Node2D) -> Dictionary:
	var result: Dictionary = {}
	for node: Node2D in runtime.get_node("WorksiteMarkers").get_children():
		result[str(node.get_instance_id())] = node.global_position
	for node: Sprite2D in world.find_children("*", "Sprite2D", true, false):
		result[str(node.get_instance_id())] = node.visible
	return result

func _finish_binding() -> void:
	print("FlexibleResourceBindingTest: ", "PASS" if failures == 0 else "FAIL", " checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
