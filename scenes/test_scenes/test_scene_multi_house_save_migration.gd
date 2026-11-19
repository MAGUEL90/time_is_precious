extends "res://scenes/test_scenes/test_scene_house_save_migration.gd"

## Each case uses a synthetic checkpoint produced by the prior map. The new
## map must reject old in-flight positions safely; compatible data can migrate.
## Additional house nodes exist only in this test scene, not in the authored map.
const EXTRA_HOUSE: PackedScene = preload("res://scenes/citizen_house_plot/citizen_house_plot.tscn")
const OLD_FIXTURES: String = "res://scenes/test_scenes/fixtures/legacy_houses_v13/"
const OLD_HASHES := {
	"clearing": "ba2a8c842ad1ff0986ac73890f623e31f7e3ee538265dfa97304fa8c3c947a7b",
	"building": "6dc1f60bc66e9fabf2a5a371006f62271c2283928879a23d68678765a47d4bd2",
	"built": "3d2e005c4fb3b04c5ee9d0724967a4198f935c6e39b6d418e76641d3079dbb3f",
	"pre_house_v11": "e7041b9425be06be8f891c667f44941c6e8978775ec0bfae790ca8c6a9e04739",
	"stocked_v12": "61493082ed3e6af4f9c3a01185ed8681bccfbcb0ea199ff77dcc3b3346460ce2",
	"outbound_v12": "cc28baaf8f48441e82d49426c1d6bd0da213683d5bbc20af7d755766ad84fd11",
}
var extra_states: Array[Node] = []
var extra_keys: Array[String] = []
const OLD_TARGET_CASES: Array[String] = ["clearing", "building", "built", "pre_house_v11", "outbound_v12"]

func _run() -> void:
	var fixture_case: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--legacy-house-case="):
			fixture_case = argument.trim_prefix("--legacy-house-case=")
	if not OLD_HASHES.has(fixture_case):
		_abort_multi("Choose a supported --legacy-house-case.")
		return
	if OS.get_name() == "Linux":
		var root: String = OS.get_environment("XDG_DATA_HOME")
		var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
		if root.is_empty() or not root.is_absolute_path() or not user_root.begins_with(root.simplify_path().trim_suffix("/") + "/"):
			_abort_multi("Use an isolated absolute XDG_DATA_HOME.")
			return
	var source_path: String = OLD_FIXTURES + fixture_case + ".json.gz"
	if fixture_case.ends_with("_v12"):
		source_path = "res://scenes/test_scenes/fixtures/legacy_stockpile_v12/" + fixture_case.trim_suffix("_v12") + ".json.gz"
	var source: PackedByteArray = FileAccess.get_file_as_bytes(source_path).decompress_dynamic(1000000, FileAccess.COMPRESSION_GZIP)
	if source.is_empty() or _hash_bytes(source) != OLD_HASHES[fixture_case]:
		_abort_multi("The synthetic old checkpoint is missing or has an unexpected hash.")
		return
	var document: Variant = JSON.parse_string(source.get_string_from_utf8())
	if not document is Dictionary:
		_abort_multi("The synthetic old checkpoint is not a document.")
		return
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_reset_singletons_before_load()
	await _load_root_city()
	var world: Node = content.get_node("YSortWorld")
	for number: int in [2, 3]:
		var plot = EXTRA_HOUSE.instantiate()
		plot.name = "FixtureHouse%d" % number
		plot.plot_id = "citizen_house_%d" % number
		plot.position = Vector2(-900 + number * 100, -900)
		world.add_child(plot)
		extra_states.append(plot.construction)
		extra_keys.append("WorkshopConstruction_" + plot.plot_id.sha256_text())
	_expect(store.snapshot.plots(content).size() == 5 and extra_states[0] != extra_states[1]
		and extra_states[0].is_citizen_house() and extra_states[1].is_citizen_house(),
		"Distinct test houses have independent, house-typed retained states.")
	house_state = content.get_node("YSortWorld/CitizenHousePlot").construction
	var codec = MIGRATION_VALUES.new()
	var original: Dictionary = codec.decode(document.state)
	var old_capacity: int = original.stock.shelter_capacity
	var old_inventory: Dictionary = original.inventory.items.duplicate(true)
	var old_city_storage: Dictionary = original.city_storage.items.duplicate(true)
	var old_plot: Dictionary = original.plots.get(house_key, {}).duplicate(true)
	var test_path: String = test_root.path_join("multi_" + fixture_case + ".json")
	_select_house_path(test_path)
	_expect(not FileAccess.file_exists(test_path), "The test checkpoint is a new isolated file.")
	_write_house_bytes(test_path, source)
	if fixture_case in OLD_TARGET_CASES:
		_test_incompatible_legacy(document, codec, test_path, source, fixture_case)
		_finish_multi(fixture_case)
		return
	for attempt: int in range(2):
		var ok: bool = store.load_checkpoint()
		_expect(ok, "Old Continue succeeds (%d): %s / %s" % [attempt, store.last_error, store.snapshot.error])
		if not ok:
			_finish_multi(fixture_case)
			return
		_expect(FileAccess.get_file_as_bytes(test_path) == source and not FileAccess.file_exists(test_path + ".bak"), "Continue leaves original checkpoint and backups untouched.")
		_expect(CityStockManager.shelter_capacity == old_capacity and _same_snapshot(Inventory.items, old_inventory)
			and _same_snapshot(city_storage.items, old_city_storage), "Migration preserves shelter, player inventory and city stock.")
		if fixture_case != "pre_house_v11":
			_expect(_same_snapshot(store.snapshot.fields(house_state, store.snapshot.PLOT_FIELDS), old_plot), "The original house phase, work and worker reservation are exact.")
		else:
			_expect(house_state.phase == "uncleared", "Pre-house v11 starts the original house uncleared.")
		for state: Node in extra_states:
			_expect(state.phase == "uncleared" and state.clearing_remaining == state.CLEARING_MINUTES and state.worker_ids.is_empty(), "A new house is initialized once, without granting shelter.")
		if fixture_case.ends_with("_v12"):
			_expect_legacy_ground(fixture_case)
		var after: Dictionary = codec.decode(store.snapshot.capture(content).state)
		for id: String in original.workers.workers_by_id:
			var before_worker: Variant = codec.encode(original.workers.workers_by_id[id])
			var after_worker: Variant = codec.encode(after.workers.workers_by_id[id])
			_expect(_same_snapshot(before_worker, after_worker), "Worker, contract and physical approach survive old Continue: " + id)
	if fixture_case != "pre_house_v11":
		var forged: Dictionary = document.duplicate(true)
		var forged_raw: Dictionary = codec.decode(forged.state)
		forged_raw.plots[extra_keys[0]] = old_plot.duplicate(true)
		forged_raw.plots[extra_keys[0]].order_id = extra_states[0].order_id
		forged.state = codec.encode(forged_raw)
		var live_before: Dictionary = store.snapshot.capture(content)
		_expect(not store.snapshot.prepare(forged, content)
			and _same_snapshot(store.snapshot.capture(content), live_before)
			and FileAccess.get_file_as_bytes(test_path) == source,
			"A forged pre-v14 checkpoint with an extra plot is rejected without live or file mutation.")
	_expect(store.save_checkpoint(), "The migrated checkpoint can be explicitly saved: " + store.last_error)
	_expect(FileAccess.get_file_as_bytes(test_path + ".bak") == source, "The old checkpoint is retained byte-for-byte as the backup.")
	var upgraded: Variant = JSON.parse_string(FileAccess.get_file_as_string(test_path))
	_expect(upgraded is Dictionary and int(upgraded.get("schema_version", 0)) == store.snapshot.VERSION, "The explicit save writes the current schema.")
	if upgraded is Dictionary:
		var incomplete: Dictionary = upgraded.duplicate(true)
		var incomplete_raw: Dictionary = codec.decode(incomplete.state)
		incomplete_raw.plots.erase(extra_keys[0])
		incomplete.state = codec.encode(incomplete_raw)
		var live_before: Dictionary = store.snapshot.capture(content)
		_expect(not store.snapshot.prepare(incomplete, content) and _same_snapshot(store.snapshot.capture(content), live_before),
			"A current checkpoint missing an authored house is rejected without live mutation.")
	for attempt: int in range(2):
		_expect(store.load_checkpoint() and CityStockManager.shelter_capacity == old_capacity, "Repeated current Continue does not duplicate shelter.")
		for state: Node in extra_states:
			_expect(state.phase == "uncleared", "Repeated current Continue retains each new house.")
		if fixture_case.ends_with("_v12"):
			_expect_legacy_ground(fixture_case)
	# Test separate progress through real player-work state transitions. Materials
	# and stamina controls below are fixture-only and do not affect the old save.
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	Inventory.max_load = 1000.0
	for item_id: String in extra_states[1].get_requirements():
		Inventory.add_item(item_id, int(extra_states[1].get_requirements()[item_id]))
	var first: Node = extra_states[0]
	var second: Node = extra_states[1]
	_expect(bool(first.start_clearing([] as Array[String], true).get("success", false)), "Player starts clearing the first extra house.")
	_expect(TimeComponentManager.advance_minutes(40), "Partial clearing advances naturally.")
	first.interrupt_player_work()
	_expect(bool(second.start_clearing([] as Array[String], true).get("success", false)), "Player starts clearing the second extra house.")
	_expect(TimeComponentManager.advance_minutes(second.CLEARING_MINUTES), "The second clearing completes naturally.")
	_expect(second.phase == "empty" and bool(second.start_build([] as Array[String], true).get("success", false)), "Only the second extra house begins building.")
	_expect(TimeComponentManager.advance_minutes(17), "The second house gains partial building progress.")
	second.interrupt_player_work()
	var remaining: int = second._remaining_work_units()
	var capacity_after_work: int = CityStockManager.shelter_capacity
	var inventory_after_work: Dictionary = Inventory.items.duplicate(true)
	_expect(first.phase == "uncleared" and first.clearing_remaining == first.CLEARING_MINUTES - 40
		and second.phase == "building" and remaining == second.CITIZEN_HOUSE_SOLO_MINUTES - 17,
		"Partial cleaning and building belong to different houses.")
	_expect(store.save_checkpoint(), "Both independent partial houses save: " + store.last_error)
	for attempt: int in range(2):
		_expect(store.load_checkpoint() and first.phase == "uncleared" and first.clearing_remaining == first.CLEARING_MINUTES - 40
			and second.phase == "building" and second._remaining_work_units() == remaining
			and CityStockManager.shelter_capacity == capacity_after_work and _same_snapshot(Inventory.items, inventory_after_work),
			"Repeated Continue preserves each house's partial work, inventory and shelter.")
	if fixture_case == "stocked_v12":
		await _test_partial_houses_from_home(first, second, remaining, capacity_after_work, inventory_after_work)
	_finish_multi(fixture_case)

func _hash_bytes(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

func _test_incompatible_legacy(document: Dictionary, codec: RefCounted, path: String, source: PackedByteArray, fixture_case: String) -> void:
	# The historical target belongs to the old city. Loading or saving this
	# fixture directly must not silently move workers or overwrite the files.
	var live_before: Dictionary = store.snapshot.capture(content)
	var files_before: Dictionary = _house_files(path)
	for attempt: int in range(2):
		var loaded: bool = store.load_checkpoint()
		var validation_error: String = store.snapshot.error
		var saved: bool = store.save_checkpoint()
		_expect(not loaded and not saved and validation_error == "Worker physical approach differs from its authored site.",
			"An old worker destination is rejected without inferred relocation: " + fixture_case)
		_expect(_house_files(path) == files_before and FileAccess.get_file_as_bytes(path) == source
			and _same_snapshot(store.snapshot.capture(content), live_before),
			"The rejected old checkpoint and live state remain unchanged: " + fixture_case)
	if fixture_case == "clearing":
		# Probe the independent house-target guard using an in-memory test copy.
		# This is not a migration and never changes the original checkpoint.
		var candidate: Dictionary = document.duplicate(true)
		var raw: Dictionary = codec.decode(candidate.state)
		var worker: WorkerData = raw.workers.workers_by_id.get("initial_workshop_laborer")
		_expect(worker != null and worker.physical_approach.get("owner") == "WoodSite", "The fixture includes its historical site worker.")
		if worker != null and worker.physical_approach.get("owner") == "WoodSite":
			worker.physical_approach.target = runtime.site_slot_destination(&"WoodSite", 0)
			candidate.state = codec.encode(raw)
			_expect(not store.snapshot.prepare(candidate, content)
				and store.snapshot.error == "Worker physical approach differs from its authored plot.",
				"A separately displaced house-worker target is also rejected.")
			_expect(_house_files(path) == files_before and _same_snapshot(store.snapshot.capture(content), live_before),
				"The in-memory diagnostic preserves the original checkpoint and live state.")

func _test_partial_houses_from_home(first: Node, second: Node, remaining: int, capacity: int, inventory: Dictionary) -> void:
	content.get_node("YSortWorld/HomeDoor")._on_body_entered(player)
	if not await _wait_scene(store.snapshot.HOME_PATH):
		return
	_expect(store.city_plots.size() == 5 and first.is_citizen_house() and second.is_citizen_house(),
		"Both partially worked houses remain registered as houses while the player is home.")
	_expect(store.save_checkpoint(), "Partially worked houses save at home: " + store.last_error)
	var files_before: Dictionary = _house_files(store.disk.path)
	for attempt: int in range(2):
		if not await _return_house_to_city():
			return
		# The additional views are test fixtures, so recreate them just as a
		# future authored city scene would; their owner states must be retained.
		for index: int in range(extra_states.size()):
			var number: int = index + 2
			var plot = EXTRA_HOUSE.instantiate()
			plot.name = "FixtureHouse%d" % number
			plot.plot_id = "citizen_house_%d" % number
			plot.position = Vector2(-900 + number * 100, -900)
			content.get_node("YSortWorld").add_child(plot)
			_expect(plot.construction == extra_states[index], "A returning view rebinds its original house state.")
		if not store.load_checkpoint():
			_expect(false, "Partially worked houses load from home: " + store.last_error)
			return
		if not await _wait_house_load():
			return
		_expect(first.phase == "uncleared" and first.clearing_remaining == first.CLEARING_MINUTES - 40
			and second.phase == "building" and second._remaining_work_units() == remaining
			and CityStockManager.shelter_capacity == capacity and _same_snapshot(Inventory.items, inventory)
			and _house_files(store.disk.path) == files_before,
			"Home Continue preserves both partial jobs, materials and shelter without rewriting the files.")

func _expect_legacy_ground(fixture_case: String) -> void:
	var expected: Dictionary = {"clay_lump": 6, "wood_log": 10 if fixture_case == "stocked_v12" else 7,
		"reed_bundle": 6, "straw_bundle": 7, "water_jar": 8}
	var ground: Dictionary = {}
	for node: Node in runtime.get_node("GroundOutput").get_children():
		if node is PickUpItem and not node.is_queued_for_deletion() and not node.is_collecting:
			ground[node.item_id] = int(ground.get(node.item_id, 0)) + int(node.quantity)
	_expect(_same_snapshot(ground, expected), "Old stockpiles migrate to the exact ground quantities once alongside the additional houses.")
	if fixture_case == "outbound_v12":
		var route: Dictionary = runtime.hauling.routes.get("initial_worksite_hauler", {})
		_expect(not route.is_empty() and int(route.get("cargo", {}).get("quantity", 0)) == 3
			and str(route.get("phase", "")) == "outbound" and bool(route.get("legacy_final", false)),
			"The old in-flight delivery retains its three carried items and final-route state.")

func _abort_multi(message: String) -> void:
	push_error(message)
	get_tree().quit(1)

func _finish_multi(fixture_case: String) -> void:
	print("MultiHouseSaveMigrationTest ", fixture_case, ": ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
