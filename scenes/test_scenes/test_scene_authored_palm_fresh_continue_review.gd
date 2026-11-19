extends Node

## Cloud-only process-boundary QA. The successful seven-source case injects the
## existing synthetic palm before opening the unchanged menu. It is not proof of
## a production binding hook, a current user scene, or graphical/input coverage.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const BINDING = preload("res://scenes/map_authoring/authored_date_palm_binding.gd")
const MIGRATION = preload("res://scenes/test_scenes/authored_palm_copy_migration.gd")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const SOURCES = preload("res://scenes/new_scenes/save_game/city_save_pickup_sources.gd")
const INPUT_PATH: String = "user://palm_fresh_continue_review/input_v17.json"

var checks: int = 0
var failures: int = 0
var mode: String = ""
var started_count: int = 0
var continued_count: int = 0
var input_bytes: PackedByteArray
var expected_raw: Dictionary = {}
var map: Node
var store: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	if not _isolated_profile():
		get_tree().quit(1)
		return
	mode = OS.get_environment("TIP_CONTINUE_REVIEW_MODE")
	_check(mode in ["prod_six_success", "prod_seven_reject", "bound_seven_success"], "An explicit supported review mode is selected.")
	_check_comparison_contract()
	input_bytes = FileAccess.get_file_as_bytes(INPUT_PATH)
	var document: Variant = JSON.parse_string(input_bytes.get_string_from_utf8())
	var codec = VALUES.new()
	var decoded: Variant = codec.decode(document.state) if document is Dictionary else null
	_check(not input_bytes.is_empty() and decoded is Dictionary and codec.error.is_empty(), "The synthetic checkpoint supplied by the separate writer process decodes.")
	if failures > 0:
		_finish()
		return
	expected_raw = decoded
	var expected_count: int = 6 if mode == "prod_six_success" else 7
	_check(expected_raw.pickup_sources.size() == expected_count, "The fixture contains the intended six- or seven-ledger catalog.")
	_check(WorkStateRuntime.get_node_or_null("CitySave") == null and SOURCES.new().nodes().is_empty(), "This new process starts with no CitySave or pickup-source ledgers.")
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	if mode == "bound_seven_success":
		await _create_bound_fixture()
		if failures > 0:
			_finish()
			return
	var menu: Node = MENU.instantiate()
	menu.checkpoint_file.path = INPUT_PATH
	if mode == "bound_seven_success":
		# Test-only setup: _open_city reuses this already-bound synthetic map.
		# The production _continue_game, disk loader and validators are unchanged.
		menu.set("_city", map)
	menu.session_started.connect(_on_session_started)
	get_tree().root.add_child(menu)
	if mode != "bound_seven_success":
		get_tree().current_scene = menu
	await _wait_frames(2)
	_check(not menu.continue_button.disabled, "The real menu enables Continue for the supplied checkpoint.")
	await menu._continue_game()
	await _wait_frames(5)
	store = WorkStateRuntime.get_node_or_null("CitySave")
	map = get_tree().current_scene
	_check(store != null and map != null, "The normal menu/store path provides a live city and CitySave.")
	if store == null or map == null:
		_finish()
		return
	if mode == "prod_seven_reject":
		_check(started_count == 0, "Production without the binding hook never claims the seven-source session started.")
		_check(is_instance_valid(menu) and not bool(menu.get("_busy")) and not menu.continue_button.disabled, "Rejected Continue returns to a retryable menu.")
		_check(get_tree().paused and store.last_error == "unsupported", "The incompatible catalog is rejected and simulation remains paused.")
		_check(SOURCES.new().nodes().size() == 6 and not SOURCES.new().nodes().has(MIGRATION._authored_id()), "Production still has only the six legacy ledgers, confirming the missing binding integration.")
		_check(Inventory.items.is_empty(), "Rejected Continue does not apply the saved harvested inventory.")
	else:
		_check(started_count == 1 and continued_count == 1 and store.status == "Loaded", "The unchanged Continue handler completes exactly one restored session.")
		_check(not get_tree().paused and not is_instance_valid(menu), "Successful Continue dismisses the menu and unpauses normally.")
		_check_loaded_state(expected_count)
		if mode == "bound_seven_success":
			await _repeat_bound_continue()
	_check(FileAccess.get_file_as_bytes(INPUT_PATH) == input_bytes, "Continue leaves every input checkpoint byte unchanged.")
	for suffix: String in [".bak", ".tmp", ".pending"]:
		_check(not FileAccess.file_exists(INPUT_PATH + suffix), "Read-only Continue creates no " + suffix + " checkpoint sidecar.")
	_finish()


func _create_bound_fixture() -> void:
	map = CITY.instantiate()
	var authored_map: Node = map.get_node("AuthoredMap")
	var world: Node = map.get_node("AuthoredMap/YSortWorld")
	_check(world.get_node_or_null("DatePalmTree") == null, "The isolated baseline has no authored palm before synthetic injection.")
	if failures > 0:
		map.free()
		return
	var palm := Sprite2D.new()
	palm.name = "DatePalmTree"
	palm.position = Vector2(83, -118)
	palm.texture = load("res://assets/objects/nature/trees/date_palm_tree.png")
	world.add_child(palm)
	palm.owner = authored_map
	var bound: Dictionary = BINDING.bind_before_tree(map)
	_check(bool(bound.get("ok", false)), "The existing helper binds only the synthetic palm before tree entry.")
	get_tree().root.add_child(map)
	get_tree().current_scene = map
	await _wait_frames(6)
	_check(SOURCES.new().nodes().size() == 7, "The injected map registers exactly seven sources before Continue.")


func _check_loaded_state(expected_count: int) -> void:
	var captured: Dictionary = store.snapshot.capture(map)
	var codec = VALUES.new()
	var loaded: Variant = codec.decode(captured.state) if not captured.is_empty() else null
	_check(loaded is Dictionary and codec.error.is_empty(), "The continued state can be captured normally.")
	if not loaded is Dictionary:
		return
	if _canonical(loaded) != _canonical(expected_raw):
		var expected_file = FileAccess.open("user://palm_fresh_continue_review/expected_state.json", FileAccess.WRITE)
		expected_file.store_string(_canonical(expected_raw))
		expected_file.close()
		var loaded_file = FileAccess.open("user://palm_fresh_continue_review/loaded_state.json", FileAccess.WRITE)
		loaded_file.store_string(_canonical(loaded))
		loaded_file.close()
		for key: String in expected_raw:
			if _canonical({key: expected_raw[key]}) != _canonical({key: loaded.get(key)}):
				print("DIAGNOSTIC changed saved group: ", key)
	_check(_canonical(loaded) == _canonical(expected_raw), "Every saved state field, including inventory, source depletion, timers and RNG, restores exactly across processes.")
	_check(SOURCES.new().nodes().size() == expected_count, "Continue creates exactly the saved source count with no duplicate ledgers.")
	if expected_count == 7:
		var authored: Dictionary = loaded.pickup_sources[MIGRATION._authored_id()]
		_check(authored.available == [false, false, false] and int(authored.remaining_minutes) > 0, "The authored palm remains harvested with its saved timer.")
		_check(int(Inventory.items.get("date_cluster", 0)) == 3, "Continue restores exactly the three harvested dates, without granting more.")
		var palm: Node = map.get_node("AuthoredMap/YSortWorld/DatePalmTree")
		_check((palm.get("_pickups") as Dictionary).is_empty(), "The depleted authored palm has no fruit views after Continue.")


func _repeat_bound_continue() -> void:
	var menu: Node = MENU.instantiate()
	menu.checkpoint_file.path = INPUT_PATH
	menu.set("_city", map)
	menu.session_started.connect(_on_session_started)
	get_tree().root.add_child(menu)
	await menu._continue_game()
	await _wait_frames(4)
	_check(started_count == 2 and continued_count == 2, "A repeated Continue reports exactly one additional successful load.")
	_check_loaded_state(7)


func _canonical(raw: Dictionary) -> String:
	var codec = VALUES.new()
	var encoded: Variant = codec.encode(raw)
	return JSON.stringify(_normalize_dictionary_order(encoded), "", true, true) if codec.error.is_empty() else "<encode-error>"


func _normalize_dictionary_order(value: Variant) -> Variant:
	# The codec stores dictionaries as ordered arrays of key/value entries. The
	# fresh map registers authored/legacy ledgers in a different order, which is
	# not a change to saved values. Only tagged dictionary entries are sorted;
	# ordinary arrays, types, keys, RNG integers and every field remain exact.
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_normalize_dictionary_order(item))
		return items
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = _normalize_dictionary_order(value[key])
		if result.get("$type") == "dictionary":
			result.entries.sort_custom(func(left: Array, right: Array) -> bool:
				return JSON.stringify(left[0], "", true, true) < JSON.stringify(right[0], "", true, true))
		return result
	return value


func _check_comparison_contract() -> void:
	_check(_canonical({"a": {"x": 1, "y": 2}}) == _canonical({"a": {"y": 2, "x": 1}}), "Comparison ignores only dictionary insertion order.")
	_check(_canonical({"slots": [true, false]}) != _canonical({"slots": [false, true]}), "Comparison still detects source-slot array ordering changes.")
	_check(_canonical({"timer": 300}) != _canonical({"timer": 301}), "Comparison still detects any timer/value change.")
	_check(_canonical({"rng": 9223372036854775806}) != _canonical({"rng": 9223372036854775805}), "Comparison preserves exact 64-bit RNG differences.")
	_check(_canonical({"quantity": 1}) != _canonical({"quantity": 1.0}), "Comparison still detects changed saved value types.")


func _on_session_started(continued: bool) -> void:
	started_count += 1
	if continued:
		continued_count += 1


func _isolated_profile() -> bool:
	var xdg: String = OS.get_environment("XDG_DATA_HOME").simplify_path().trim_suffix("/")
	var actual: String = ProjectSettings.globalize_path("user://").simplify_path()
	if not xdg.is_absolute_path() or not xdg.contains("palm_followup_cloud_20261109") or not actual.begins_with(xdg + "/"):
		push_error("Fresh Continue review requires an isolated follow-up cloud XDG_DATA_HOME.")
		return false
	print("FreshContinueReview isolated profile: ", actual)
	return true


func _wait_frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _finish() -> void:
	print("FreshContinueReview: mode=%s %s checks=%d failures=%d" % [mode, "PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
