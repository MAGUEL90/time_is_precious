extends Node

## Isolated cloud-only HOME checkpoint research. Seven-source startup and the
## optional return-city palm view are injected only by this fixture. Production
## has no authored-palm startup hook; no scenes, validators or real user saves are edited.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const BINDING = preload("res://scenes/map_authoring/authored_date_palm_binding.gd")
const MIGRATION = preload("res://scenes/test_scenes/authored_palm_copy_migration.gd")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const SOURCES = preload("res://scenes/new_scenes/save_game/city_save_pickup_sources.gd")
const SAVE_FILE = preload("res://scenes/new_scenes/save_game/city_save_file.gd")
const CITY_PATH: String = "res://scenes/content_scene/content_scene.tscn"
const HOME_PATH: String = "res://scenes/player_home_interior/player_home_interior.tscn"
const DIR: String = "user://palm_home_continue"
const SOURCE: String = DIR + "/six_home.json"
const MIGRATED: String = DIR + "/migrated_home.json"
const HARVESTED: String = DIR + "/harvested_home.json"
const MALFORMED: String = DIR + "/malformed_home.json"

var phase: String = ""
var checks: int = 0
var failures: int = 0
var store: Node
var map: Node
var expected: Dictionary = {}
var started: int = 0
var continued: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	if not _isolated_profile():
		get_tree().quit(1)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--palm-home-phase="):
			phase = arg.trim_prefix("--palm-home-phase=")
	_check(phase in ["write_six", "migrate", "write_harvested", "read_pristine", "read_harvested", "reject_missing", "reject_malformed", "reject_unbound_seven"], "A supported explicit phase was selected.")
	if failures:
		_finish()
		return
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_check_comparison_contract()
	if failures:
		_finish()
		return
	match phase:
		"write_six":
			await _write_six_home()
		"migrate":
			await _migrate_home()
		"write_harvested":
			await _write_harvested_home()
		"read_pristine", "read_harvested":
			await _read_and_round_trip()
		"reject_missing", "reject_malformed", "reject_unbound_seven":
			await _reject_invalid()
	_finish()

func _write_six_home() -> void:
	_check(not FileAccess.file_exists(SOURCE), "The six-source writer requires a new checkpoint path.")
	if failures:
		return
	map = CITY.instantiate()
	get_tree().root.add_child(map)
	get_tree().current_scene = map
	await _frames(8)
	store = WorkStateRuntime.get_node_or_null("CitySave")
	_check(store != null and store.map == map, "Unchanged city startup binds the production CitySave store.")
	if failures:
		return
	var nodes: Dictionary = SOURCES.new().nodes()
	_check(_has_ids(nodes, MIGRATION._legacy_ids()), "The writer begins with exactly six legacy source ledgers.")
	_check(TimeComponentManager.advance_minutes(137), "The actual city clock advances 137 minutes before the checkpoint.")
	for i: int in range(MIGRATION._legacy_ids().size()):
		var state: Node = nodes.get(MIGRATION._legacy_ids()[i])
		if state == null:
			_check(false, "Legacy ledger exists for seeding.")
			continue
		state._rng.seed = 31001 + i * 117
		for slot: int in range(1 + i % 3):
			state.collect(slot)
		_check(state.available.count(false) == 1 + i % 3 and state.remaining_minutes > 0, "Real collection creates varied legacy depletion and timers: " + str(state.name))
	if failures:
		return
	await _city_to_home()
	if failures:
		return
	store.disk.path = SOURCE
	store.refresh_checkpoint_slot()
	_check(store.save_checkpoint(), "The production CitySave store writes the original HOME checkpoint: " + store.last_error)
	var document: Dictionary = _read_document(SOURCE)
	var raw: Dictionary = _decode(document)
	_check(document.get("schema_version") == 18 and document.get("location") == "home" and _has_ids(raw.get("pickup_sources", {}), MIGRATION._legacy_ids()), "The genuinely produced schema-18 checkpoint records HOME and exactly six sources.")
	_check(not FileAccess.get_file_as_bytes(SOURCE).is_empty(), "Original checkpoint bytes exist for later preservation checks.")

func _migrate_home() -> void:
	_check(FileAccess.file_exists(SOURCE) and not FileAccess.file_exists(MIGRATED) and not FileAccess.file_exists(MALFORMED), "The conversion reads an existing input and new output paths only.")
	if failures:
		return
	var source_bytes: PackedByteArray = FileAccess.get_file_as_bytes(SOURCE)
	var original: Dictionary = _read_document(SOURCE)
	await _create_bound_city()
	if failures:
		return
	var result: Dictionary = MIGRATION.prepare_copy(original, map, true)
	_check(bool(result.get("ok", false)) and result.get("mode") == "copy_added_authored_source", "Explicit copy-only migration accepts the actual six-source HOME checkpoint: " + str(result.get("error", "")))
	if failures:
		return
	var candidate: Dictionary = result.candidate
	var original_raw: Dictionary = _decode(original)
	var candidate_raw: Dictionary = _decode(candidate)
	_check(candidate.get("location") == "home" and candidate.get("schema_version") == original.get("schema_version") and candidate.get("scenario") == original.get("scenario"), "The candidate preserves every header field, including HOME.")
	_check(_encoded_preservation(original, candidate), "All original encoded non-source fields and six source entries are preserved exactly; only the seventh entry is appended.")
	_check(_legacy_equal(original_raw.get("pickup_sources", {}), candidate_raw.get("pickup_sources", {})), "All original source IDs, depletion, timers, config and 64-bit RNG state are exact.")
	_check(_has_ids(candidate_raw.get("pickup_sources", {}), _all_ids()) and _pristine(candidate_raw.pickup_sources.get(MIGRATION._authored_id())), "The seventh source is unique, full and timer-zero.")
	var validator = SAVE_FILE.new()
	validator.path = MIGRATED
	var absent: Dictionary = validator.read_snapshot(Callable(self, "_validate"))
	_check(absent.is_empty() and validator.error == "missing", "The converted output slot is independently observed as empty.")
	_check(validator.write_snapshot(candidate, Callable(self, "_validate")), "The existing guarded save-file writer writes the separate candidate: " + validator.error)
	_check(FileAccess.get_file_as_bytes(SOURCE) == source_bytes, "Conversion preserves every original checkpoint byte.")
	# A purpose-built, invalid copy checks the actual Continue validator in a
	# later fresh process. It never overwrites the input or converted checkpoint.
	var malformed: Dictionary = candidate.duplicate(true)
	var malformed_raw: Dictionary = candidate_raw.duplicate(true)
	malformed_raw.pickup_sources[MIGRATION._authored_id()].available[0] = 1
	var codec = VALUES.new()
	malformed.state = codec.encode(malformed_raw)
	_check(codec.error.is_empty(), "The isolated malformed-source control is encoded.")
	var file: FileAccess = FileAccess.open(MALFORMED, FileAccess.WRITE)
	_check(file != null, "The separate malformed control file opens.")
	if file != null:
		file.store_string(JSON.stringify(malformed, "\t", true, true))
		file.close()
	_check(FileAccess.get_file_as_bytes(SOURCE) == source_bytes, "Creating the negative control leaves the original bytes intact.")

func _write_harvested_home() -> void:
	_check(FileAccess.file_exists(MIGRATED) and not FileAccess.file_exists(HARVESTED), "The harvested writer requires the converted input and a new output slot.")
	if failures:
		return
	var source_bytes: PackedByteArray = FileAccess.get_file_as_bytes(SOURCE)
	var migrated_bytes: PackedByteArray = FileAccess.get_file_as_bytes(MIGRATED)
	await _continue_home(MIGRATED)
	if failures:
		return
	_check_current_home_matches(expected, "Migrated HOME Continue before harvest")
	var original_sources: Dictionary = SOURCES.new().capture().duplicate(true)
	await _home_to_city()
	if failures:
		return
	_check(_canonical(SOURCES.new().capture()) == _canonical(original_sources), "The actual unmodified HOME-to-city transition retains every source record.")
	var palm: Node = await _attach_test_view()
	if failures or palm == null:
		return
	_check(_fruit_count() == 3 and (palm.get("_pickups") as Dictionary).size() == 3, "The explicitly injected test view exposes exactly three pristine fruit.")
	var previous_dates: int = int(Inventory.items.get("date_cluster", 0))
	var pickup: Node = (palm.get("_pickups") as Dictionary).get(0)
	_check(pickup != null, "A genuine existing fruit pickup is available for the gather handler.")
	if failures:
		return
	pickup.on_player_gather(map.get_node("YSortWorld/Player"))
	await get_tree().create_timer(0.6).timeout
	await _frames(5)
	var authored: Dictionary = SOURCES.new().capture().get(MIGRATION._authored_id(), {})
	_check(int(Inventory.items.get("date_cluster", 0)) == previous_dates + 3 and authored.get("available") == [false, false, false] and int(authored.get("remaining_minutes", 0)) > 0, "The existing gather handler grants three dates once and depletes the authored ledger with its normal timer.")
	_check(_fruit_count() == 0 and _has_ids(SOURCES.new().nodes(), _all_ids()), "Harvest leaves no fruit and exactly seven unique ledgers.")
	await _city_to_home()
	if failures:
		return
	store.disk.path = HARVESTED
	store.refresh_checkpoint_slot()
	_check(store.save_checkpoint(), "The production store writes a separate genuinely harvested HOME checkpoint: " + store.last_error)
	var document: Dictionary = _read_document(HARVESTED)
	var raw: Dictionary = _decode(document)
	_check(document.get("location") == "home" and _canonical(raw.get("pickup_sources", {})) == _canonical(SOURCES.new().capture()), "The harvested HOME file contains the exact live seven-source ledger.")
	_check(FileAccess.get_file_as_bytes(SOURCE) == source_bytes and FileAccess.get_file_as_bytes(MIGRATED) == migrated_bytes, "The explicit harvest writer leaves both earlier source checkpoints unchanged.")

func _read_and_round_trip() -> void:
	var path: String = MIGRATED if phase == "read_pristine" else HARVESTED
	var artifact_before: Dictionary = _artifact_bytes()
	await _continue_home(path)
	if failures:
		return
	_check_current_home_matches(expected, "Fresh-process HOME Continue")
	var sources_before: Dictionary = SOURCES.new().capture().duplicate(true)
	var record: Dictionary = sources_before.get(MIGRATION._authored_id(), {})
	if phase == "read_pristine":
		_check(_pristine(record), "Fresh HOME Continue restores the pristine migrated source.")
	else:
		_check(record.get("available") == [false, false, false] and int(record.get("remaining_minutes", 0)) > 0 and int(Inventory.items.get("date_cluster", 0)) == 3, "Fresh HOME Continue preserves harvested slots, timer and exactly three dates.")
	_check(_fruit_count() == 0, "HOME contains no orphaned synthetic palm fruit views.")
	await _home_to_city()
	if failures:
		return
	_check(_canonical(SOURCES.new().capture()) == _canonical(sources_before), "HOME-to-city preserves the exact source IDs, slots, timers, config and RNG.")
	var palm: Node = await _attach_test_view()
	if failures or palm == null:
		return
	var expected_fruit: int = 3 if phase == "read_pristine" else 0
	_check(_fruit_count() == expected_fruit and (palm.get("_pickups") as Dictionary).size() == expected_fruit, "The explicit test-only view shows the exact saved fruit count without duplicates.")
	_check(_canonical(SOURCES.new().capture()) == _canonical(sources_before), "Attaching the test-only view neither refills nor duplicates any ledger.")
	await _city_to_home()
	if failures:
		return
	_check(_canonical(SOURCES.new().capture()) == _canonical(sources_before), "The city-to-HOME return preserves every source record exactly.")
	_check(_fruit_count() == 0 and _has_ids(SOURCES.new().nodes(), _all_ids()), "Returning HOME removes the view while retaining exactly seven unique ledgers.")
	_check_current_home_matches(expected, "HOME-to-city-to-HOME round trip")
	_check(_artifact_bytes() == artifact_before, "All actual checkpoint primaries and existing or absent recovery artifacts remain byte-identical during read-only Continue and travel.")

func _reject_invalid() -> void:
	var path: String = SOURCE if phase == "reject_missing" else (MALFORMED if phase == "reject_malformed" else MIGRATED)
	var artifact_before: Dictionary = _artifact_bytes()
	if phase == "reject_unbound_seven":
		await _create_unbound_city()
	else:
		await _create_bound_city()
	if failures:
		return
	var before: Dictionary = _decode(store.snapshot.capture(map))
	var before_sources: Dictionary = SOURCES.new().capture().duplicate(true)
	var menu: Node = MENU.instantiate()
	menu.checkpoint_file.path = path
	menu.set("_city", map)
	menu.session_started.connect(_on_session_started)
	get_tree().root.add_child(menu)
	await _frames(3)
	_check(not menu.continue_button.disabled, "The real menu offers Continue for the supplied negative control.")
	await menu._continue_game()
	await _frames(4)
	_check(started == 0 and continued == 0 and is_instance_valid(menu) and not bool(menu.get("_busy")), "The invalid HOME checkpoint is rejected without starting a session; the menu remains retryable.")
	_check(get_tree().paused and store.last_error == "unsupported", "The existing validator safely rejects the incompatible source catalog or malformed seventh source.")
	_check(_canonical(_decode(store.snapshot.capture(map))) == _canonical(before), "Rejected Continue leaves every live saved field unchanged.")
	var expected_ids: Array[String] = MIGRATION._legacy_ids() if phase == "reject_unbound_seven" else _all_ids()
	_check(_canonical(SOURCES.new().capture()) == _canonical(before_sources) and _has_ids(SOURCES.new().nodes(), expected_ids), "Rejected Continue leaves the exact live source catalog unchanged.")
	_check(_artifact_bytes() == artifact_before, "Rejection changes no checkpoint or recovery artifact bytes.")

func _continue_home(path: String) -> void:
	_check(FileAccess.file_exists(path), "The requested existing HOME checkpoint is present.")
	var document: Dictionary = _read_document(path)
	expected = _decode(document)
	_check(document.get("location") == "home" and _has_ids(expected.get("pickup_sources", {}), _all_ids()), "The input is a HOME document with exactly seven unique sources.")
	if failures:
		return
	await _create_bound_city()
	if failures:
		return
	var menu: Node = MENU.instantiate()
	menu.checkpoint_file.path = path
	menu.set("_city", map) # Test-only injection, not a production startup hook.
	menu.session_started.connect(_on_session_started)
	get_tree().root.add_child(menu)
	await _frames(3)
	_check(not menu.continue_button.disabled, "The unchanged real menu enables Continue.")
	await menu._continue_game()
	await _frames(5)
	_check(started == 1 and continued == 1 and store.status == "Loaded" and not is_instance_valid(menu), "The unchanged menu/store/transition path starts exactly one continued HOME session.")
	_check(store.snapshot.is_home(get_tree().current_scene) and store.map == get_tree().current_scene and is_instance_valid(store.parked_worksite), "The actual saved HOME opens with the city worksite parked.")
	_check(_has_ids(SOURCES.new().nodes(), _all_ids()), "The seventh ledger survives disposal of the injected city view.")

func _create_bound_city() -> void:
	map = CITY.instantiate()
	var result: Dictionary = _bind_detached_palm(map)
	_check(bool(result.get("ok", false)), "A synthetic palm is bound before this test city enters the tree: " + str(result.get("error", "")))
	if failures:
		map.free()
		return
	get_tree().root.add_child(map)
	get_tree().current_scene = map
	await _frames(8)
	store = WorkStateRuntime.get_node_or_null("CitySave")
	_check(store != null and store.map == map and _has_ids(SOURCES.new().nodes(), _all_ids()), "The test-injected city has one store and exactly seven ledger IDs.")

func _create_unbound_city() -> void:
	map = CITY.instantiate()
	get_tree().root.add_child(map)
	get_tree().current_scene = map
	await _frames(8)
	store = WorkStateRuntime.get_node_or_null("CitySave")
	_check(store != null and store.map == map and _has_ids(SOURCES.new().nodes(), MIGRATION._legacy_ids()), "The unmodified production city has only the six legacy ledgers and no palm hook.")

func _bind_detached_palm(city: Node) -> Dictionary:
	var authored: Node = city.get_node("AuthoredMap")
	var world: Node = city.get_node("AuthoredMap/YSortWorld")
	if world.get_node_or_null("DatePalmTree") != null:
		return {"ok": false, "error": "The synthetic target already exists."}
	var palm := Sprite2D.new()
	palm.name = "DatePalmTree"
	palm.position = Vector2(83, -118)
	palm.texture = load("res://assets/objects/nature/trees/date_palm_tree.png")
	world.add_child(palm)
	palm.owner = authored
	return BINDING.bind_before_tree(city)

func _attach_test_view() -> Node:
	# Real ExitDoor creates the unchanged city resource: it has no palm hook.
	# A separate detached city is used solely to bind the synthetic view before
	# this test attaches that view to the returned city; nothing is saved to disk.
	_check(map.get_node_or_null("AuthoredMap/YSortWorld/DatePalmTree") == null and _fruit_count() == 0, "Real city reload has no authored palm view because production has no startup hook.")
	var detached: Node = CITY.instantiate()
	var result: Dictionary = _bind_detached_palm(detached)
	_check(bool(result.get("ok", false)), "The return-city test view is separately bound before tree entry.")
	if failures:
		detached.free()
		return null
	var palm: Node = detached.get_node("AuthoredMap/YSortWorld/DatePalmTree")
	palm.get_parent().remove_child(palm)
	detached.free()
	map.get_node("AuthoredMap/YSortWorld").add_child(palm)
	palm.owner = map.get_node("AuthoredMap")
	await _frames(5)
	_check(is_instance_valid(palm.get("state")) and palm.get("state") == SOURCES.new().nodes().get(MIGRATION._authored_id()), "The test view reconnects to the existing authored ledger, not a duplicate.")
	return palm

func _home_to_city() -> void:
	var home: Node = get_tree().current_scene
	_check(store.snapshot.is_home(home), "The real ExitDoor starts from HOME.")
	if failures:
		return
	home.get_node("YSortWorld/ExitDoor")._on_body_entered(home.get_node("YSortWorld/Player"))
	await _wait_scene(CITY_PATH)
	map = get_tree().current_scene
	_check(map != null and map.scene_file_path == CITY_PATH and store.map == map and not is_instance_valid(store.parked_worksite), "The unchanged ExitDoor restores the actual city and its parked worksite.")

func _city_to_home() -> void:
	var city: Node = get_tree().current_scene
	_check(city != null and city.scene_file_path == CITY_PATH, "The real HomeDoor starts from the city.")
	if failures:
		return
	city.get_node("YSortWorld/HomeDoor")._on_body_entered(city.get_node("YSortWorld/Player"))
	await _wait_scene(HOME_PATH)
	map = get_tree().current_scene
	_check(store.snapshot.is_home(map) and store.map == map and is_instance_valid(store.parked_worksite), "The unchanged HomeDoor opens HOME and parks the actual city worksite.")

func _wait_scene(path: String) -> void:
	for frame: int in range(1800):
		var current: Node = get_tree().current_scene
		if current != null and current.scene_file_path == path and not SceneTransition.is_transitioning:
			await _frames(4)
			return
		await get_tree().process_frame
	_check(false, "The real scene transition completes to " + path)

func _check_current_home_matches(wanted: Dictionary, label: String) -> void:
	var capture: Dictionary = store.snapshot.capture(get_tree().current_scene)
	var actual: Dictionary = _decode(capture)
	if _canonical(actual) != _canonical(wanted):
		for key: Variant in wanted:
			if _canonical({key: wanted[key]}) != _canonical({key: actual.get(key)}):
				print("DIAGNOSTIC changed saved group: ", key)
	_check(capture.get("location") == "home" and _canonical(actual) == _canonical(wanted), label + " preserves every saved state field, with only dictionary insertion order ignored.")
	_check(_has_ids(SOURCES.new().nodes(), _all_ids()), label + " retains exactly seven unique source IDs.")

func _read_document(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "Checkpoint JSON decodes: " + path)
	return parsed if parsed is Dictionary else {}

func _decode(document: Dictionary) -> Dictionary:
	var codec = VALUES.new()
	var raw: Variant = codec.decode(document.get("state", {}))
	_check(codec.error.is_empty() and raw is Dictionary, "Checkpoint state decodes with the existing values codec.")
	return raw if raw is Dictionary else {}

func _validate(document: Dictionary) -> bool:
	return store.snapshot.prepare(document, map)

func _encoded_preservation(original: Dictionary, candidate: Dictionary) -> bool:
	var o: Dictionary = original.duplicate(true)
	var c: Dictionary = candidate.duplicate(true)
	var old_entries: Variant = _source_entries(o)
	var new_entries: Variant = _source_entries(c)
	if not old_entries is Array or not new_entries is Array or old_entries.size() != 6 or new_entries.size() != 7:
		return false
	if JSON.stringify(new_entries.slice(0, 6), "", true, true) != JSON.stringify(old_entries, "", true, true):
		return false
	if not new_entries[6] is Array or new_entries[6][0] != MIGRATION._authored_id():
		return false
	new_entries.remove_at(6)
	return JSON.stringify(o, "", true, true) == JSON.stringify(c, "", true, true)

func _source_entries(document: Dictionary) -> Variant:
	var state: Variant = document.get("state")
	if not state is Dictionary or state.get("$type") != "dictionary":
		return null
	for pair: Variant in state.get("entries", []):
		if pair is Array and pair.size() == 2 and pair[0] == "pickup_sources":
			var sources: Variant = pair[1]
			return sources.get("entries") if sources is Dictionary and sources.get("$type") == "dictionary" else null
	return null

func _legacy_equal(a: Dictionary, b: Dictionary) -> bool:
	for id: String in MIGRATION._legacy_ids():
		if not a.has(id) or not b.has(id) or _canonical(a[id]) != _canonical(b[id]):
			return false
	return true

func _all_ids() -> Array[String]:
	var ids: Array[String] = MIGRATION._legacy_ids()
	ids.append(MIGRATION._authored_id())
	return ids

func _has_ids(records: Variant, ids: Array[String]) -> bool:
	if not records is Dictionary or records.size() != ids.size():
		return false
	for id: String in ids:
		if not records.has(id):
			return false
	return true

func _pristine(record: Variant) -> bool:
	return record is Dictionary and record.get("available") == [true, true, true] and record.get("remaining_minutes") == 0 and record.get("config") == MIGRATION.EXPECTED_CONFIG and record.get("rng") is Dictionary and typeof(record.rng.get("seed")) == TYPE_INT and typeof(record.rng.get("state")) == TYPE_INT

func _canonical(raw: Dictionary) -> String:
	var codec = VALUES.new()
	var encoded: Variant = codec.encode(raw)
	return JSON.stringify(_normalize(encoded), "", true, true) if codec.error.is_empty() else "<encode-error>"

func _normalize(value: Variant) -> Variant:
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_normalize(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = _normalize(value[key])
		if result.get("$type") == "dictionary":
			result.entries.sort_custom(func(a: Array, b: Array) -> bool: return JSON.stringify(a[0], "", true, true) < JSON.stringify(b[0], "", true, true))
		return result
	return value

func _artifact_bytes() -> Dictionary:
	var result: Dictionary = {}
	for base: String in [SOURCE, MIGRATED, HARVESTED, MALFORMED]:
		for suffix: String in ["", ".bak", ".tmp", ".pending"]:
			var path: String = base + suffix
			result[path] = {"exists": FileAccess.file_exists(path), "bytes": FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()}
	return result

func _fruit_count() -> int:
	var result: int = 0
	for pickup: Node in get_tree().get_nodes_in_group("date_palm_pickups"):
		if not pickup.is_queued_for_deletion() and not bool(pickup.get("is_collecting")):
			result += 1
	return result

func _on_session_started(is_continue: bool) -> void:
	started += 1
	if is_continue:
		continued += 1

func _check_comparison_contract() -> void:
	_check(_canonical({"a": {"x": 1, "y": 2}}) == _canonical({"a": {"y": 2, "x": 1}}), "The comparison ignores dictionary insertion order only.")
	_check(_canonical({"slots": [true, false]}) != _canonical({"slots": [false, true]}), "The comparison detects changed source slot ordering.")
	_check(_canonical({"timer": 300}) != _canonical({"timer": 301}), "The comparison detects a changed timer.")
	_check(_canonical({"rng": 9223372036854775806}) != _canonical({"rng": 9223372036854775805}), "The comparison detects one-bit 64-bit RNG differences.")
	_check(_canonical({"quantity": 1}) != _canonical({"quantity": 1.0}), "The comparison distinguishes integer and float saved values.")

func _isolated_profile() -> bool:
	var qa_root: String = ProjectSettings.globalize_path("res://../qa").simplify_path()
	var homes: Array[String] = []
	for variable: String in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		var home: String = OS.get_environment(variable).simplify_path().trim_suffix("/")
		if not home.is_absolute_path() or not DirAccess.dir_exists_absolute(home) or not home.begins_with(qa_root + "/") or homes.has(home):
			push_error("HOME palm fixture requires three distinct existing XDG paths under its isolated cloud QA directory.")
			return false
		homes.append(home)
	var actual: String = ProjectSettings.globalize_path("user://").simplify_path()
	if not actual.begins_with(homes[0] + "/"):
		push_error("HOME palm fixture refuses user data outside its isolated XDG_DATA_HOME.")
		return false
	print("PalmHomeContinue isolated profile: ", actual)
	return true

func _frames(count: int) -> void:
	for i: int in range(count):
		await get_tree().process_frame

func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _finish() -> void:
	print("PalmHomeContinue phase=%s %s checks=%d failures=%d" % [phase, "PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
