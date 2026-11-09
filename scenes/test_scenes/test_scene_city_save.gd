extends "res://scenes/test_scenes/test_scene_defense_dialogue.gd"

const CODEC = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const LEGACY_RELIABILITY = preload("res://scenes/test_scenes/legacy_reliability_fixture.gd")
const CHECKPOINT_PATH: String = "user://city_save_test/checkpoint.json"
const CHECKPOINT_SUFFIXES: Array[String] = ["", ".bak", ".tmp", ".pending"]
var store: Node
var _payment_clock_before: int = -1
var _payment_clock_after: int = -1
var _payment_guard_seen: bool = false
var _aborted: bool = false
var _safe_xdg_data_home: String = ""
var _scenario_selection: String = "all"

func _run() -> void:
	if not _validate_isolated_user_data():
		_fail_fast("preflight_xdg", "XDG data/config/cache must be fresh absolute directories under citysave_suite_qa; no checkpoint files were touched.")
		return
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	if not ResourceLoader.exists("res://scenes/content_scene/content_scene.tscn"):
		_fail_fast("content", "Required content_scene resource is missing.")
		return
	if not await _load_content_checked():
		_fail_fast("content", "Required city scene, player, raid state, UI, or storage did not load.")
		return
	store = WorkStateRuntime.get_node_or_null("CitySave")
	if not is_instance_valid(store) or store.get("disk") == null or store.get("snapshot") == null:
		_fail_fast("store", "Required CitySave store, disk, or snapshot did not initialize.")
		return
	store.disk.path = CHECKPOINT_PATH
	if not _checkpoint_path_is_safe():
		_fail_fast("preflight_path", "Resolved checkpoint is outside the isolated XDG data directory.")
		return
	var mode: String = "roundtrip"
	var scenario: String = "all"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--city-save-phase="):
			mode = argument.trim_prefix("--city-save-phase=")
		elif argument.begins_with("--city-save-scenario="):
			scenario = argument.trim_prefix("--city-save-scenario=")
	if mode not in ["roundtrip", "read", "write"]:
		_fail_fast("selection", "Unknown --city-save-phase value: " + mode)
		return
	if scenario not in ["all", "fixture", "core", "raid", "legacy_focus", "legacy_v9", "legacy_v15", "inject_seed_failure", "inject_prepare_failure"]:
		_fail_fast("selection", "Unknown --city-save-scenario value: " + scenario)
		return
	if mode != "roundtrip" and scenario != "all":
		_fail_fast("selection", "--city-save-phase cannot be combined with a focused --city-save-scenario.")
		return
	_scenario_selection = scenario
	if mode == "read":
		if not FileAccess.file_exists(CHECKPOINT_PATH):
			_fail_fast("read_prerequisite", "Expected a checkpoint written by a separate isolated write phase.")
			return
		var original_bytes: String = FileAccess.get_file_as_string(CHECKPOINT_PATH)
		var parsed_document: Variant = JSON.parse_string(original_bytes)
		if original_bytes.is_empty() or not parsed_document is Dictionary:
			_fail_fast("read_decode", "Fresh-process checkpoint bytes are empty or do not decode to a document.")
			return
		var read_document: Dictionary = parsed_document
		if not _required_load("read_load"):
			return
		if not store.snapshot.prepared is Dictionary or store.snapshot.prepared.is_empty():
			_fail_fast("read_prepare", "Loaded checkpoint did not produce prepared dictionary state.")
			return
		var read_raw: Dictionary = store.snapshot.prepared.duplicate(true)
		if not read_raw.get("pickup_sources", {}) is Dictionary:
			_fail_fast("read_decode", "Prepared checkpoint is missing its pickup-source dictionary.")
			return
		await _assert_seed(read_raw.get("pickup_sources", {}))
		if _aborted:
			return
		_assert_comparator_controls()
		var expected: Dictionary = read_document.duplicate(true)
		if read_document.schema_version == 9:
			# The staged load already contains the current nested worksite shape.
			expected.schema_version = CODEC.VERSION
			expected.state = VALUES.new().encode(read_raw)
			for result: Dictionary in read_raw.needs.last_needs_results.values():
				_expect(not result.has("reliability") and not result.has("reliability_delta"), "A genuine v9 ledger loads without retired fields.")
			_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH) == original_bytes, "Loading a genuine v9 checkpoint preserves its exact bytes.")
		var actual_document: Dictionary = store.snapshot.capture(content)
		if actual_document.is_empty():
			_fail_fast("read_capture", "Fresh-process restore did not capture a complete current snapshot.")
			return
		_expect(_same_wire_snapshot(actual_document, expected), "Fresh-process restore matches every captured owner and RNG state after migration.")
		_finish()
		return
	if not _clean_files():
		_fail_fast("cleanup", "Could not safely remove the isolated checkpoint and recovery siblings.")
		return
	if not await _seed():
		if scenario == "inject_seed_failure":
			var checkpoint_files_absent: bool = true
			for suffix: String in CHECKPOINT_SUFFIXES:
				checkpoint_files_absent = checkpoint_files_absent and not FileAccess.file_exists(CHECKPOINT_PATH + suffix)
			print("CitySaveTest injection: seed prerequisite failed; checkpoint and recovery files remain absent: " + str(checkpoint_files_absent))
			_fail_fast("seed", "Injected seed prerequisite failure; no dependent assertions or checkpoint writes ran.")
		else:
			_fail_fast("seed", "Required CitySave fixture seed did not complete; dependent assertions and writes were stopped.")
		return
	_expect(ui.find_child("SaveButton", true, false) == null and ui.find_child("LoadButton", true, false) == null, "City Hub does not expose manual checkpoint buttons.")
	if not _required_save("seed_save"):
		return
	var capture_for_save: Dictionary = store.snapshot.capture(content)
	if capture_for_save.is_empty() or not capture_for_save.get("state") is Dictionary:
		_fail_fast("capture", "Required seed snapshot did not produce an encoded state dictionary.")
		return
	var save_codec: RefCounted = VALUES.new()
	var saved_raw_value: Variant = save_codec.decode(capture_for_save.state)
	if not saved_raw_value is Dictionary or not save_codec.error.is_empty():
		_fail_fast("decode", "Required seed snapshot did not decode to a state dictionary: " + save_codec.error)
		return
	var saved_raw: Dictionary = saved_raw_value
	if not saved_raw.get("pickup_sources") is Dictionary:
		_fail_fast("decode", "Decoded seed snapshot is missing pickup-source state.")
		return
	await _assert_seed(saved_raw.pickup_sources)
	if _aborted:
		return
	_assert_comparator_controls()
	if scenario == "fixture":
		print("CitySaveTest scenario: fixture only; hidden legacy palm ledger and save assertions completed.")
		_finish()
		return
	if scenario in ["legacy_focus", "legacy_v9", "legacy_v15"]:
		var migration_source: Dictionary = store.snapshot.capture(content)
		if migration_source.is_empty() or not migration_source.get("state") is Dictionary:
			_fail_fast("migration_capture", "The selected migration scenario requires a valid current snapshot.")
			return
		var migration_codec = VALUES.new()
		var migration_raw_value: Variant = migration_codec.decode(migration_source.state)
		if not migration_raw_value is Dictionary or not migration_codec.error.is_empty():
			_fail_fast("migration_decode", "The selected migration scenario could not decode current state: " + migration_codec.error)
			return
		match scenario:
			"legacy_focus": _test_player_condition_migration(migration_source, migration_raw_value)
			"legacy_v9": _test_reliability_migration(migration_source, migration_raw_value)
			"legacy_v15": _test_wall_paid_source_migration(migration_source, migration_raw_value)
		if _aborted: return
		_finish()
		return
	if scenario == "core":
		var core_before: Dictionary = store.snapshot.capture(content)
		if not _required_load("core_load"): return
		await _assert_seed(saved_raw.pickup_sources)
		if _aborted: return
		_expect(core_before == store.snapshot.capture(content), "Core CitySave owners round-trip exactly in an isolated run.")
		_finish()
		return
	if scenario == "raid":
		await _run_raid_scenario()
		if _aborted: return
		_finish()
		return
	if scenario == "inject_prepare_failure":
		var bytes_before_failed_prepare: String = FileAccess.get_file_as_string(CHECKPOINT_PATH)
		var live_before_failed_prepare: Dictionary = store.snapshot.capture(content)
		var invalid_prepare: Dictionary = capture_for_save.duplicate(true)
		invalid_prepare.schema_version = -1
		if _required_prepare(invalid_prepare, "prepare_injection"):
			_fail_fast("prepare_injection", "Injected unsupported checkpoint version unexpectedly prepared.")
			return
		var bytes_unchanged: bool = FileAccess.get_file_as_string(CHECKPOINT_PATH) == bytes_before_failed_prepare
		var live_unchanged: bool = store.snapshot.capture(content) == live_before_failed_prepare
		print("CitySaveTest injection: required prepare failure stopped this phase; checkpoint bytes unchanged=" + str(bytes_unchanged) + ", live state unchanged=" + str(live_unchanged) + ", dependent writes stopped.")
		return
	if mode == "write":
		_finish()
		return
	var before: Dictionary = store.snapshot.capture(content)
	if before.is_empty() or not before.get("state") is Dictionary:
		_fail_fast("capture", "Required pre-migration snapshot did not produce an encoded state dictionary.")
		return
	var codec = VALUES.new()
	var current_raw_value: Variant = codec.decode(before.state)
	if not current_raw_value is Dictionary or not codec.error.is_empty():
		_fail_fast("decode", "Required pre-migration snapshot did not decode: " + codec.error)
		return
	saved_raw = current_raw_value
	_test_player_condition_migration(before, saved_raw)
	if _aborted: return
	_test_reliability_migration(before, saved_raw)
	if _aborted: return
	_test_wall_paid_source_migration(before, saved_raw)
	if _aborted: return
	_expect(saved_raw.pickup_sources is Dictionary and saved_raw.pickup_sources.size() == 6,
		"The version-4 snapshot records exactly the six authored pickup-source identities.")
	_expect(is_equal_approx(saved_raw.clock._timer, 0.375), "The fractional clock tick is captured alongside pending palm timers.")
	_assert_saved_source_shape(saved_raw.pickup_sources)
	Inventory.items.clear()
	storage.items.clear()
	state._work_remaining = 1
	state._work_paid.clear()
	WorkStateRuntime.get_node("CityProgression").progress = 0
	player.global_position += Vector2(30, 20)
	player.fatigue = 0.1
	if not _required_load("roundtrip_load"):
		return
	await _assert_seed(saved_raw.pickup_sources)
	if _aborted: return
	var after: Dictionary = store.snapshot.capture(content)
	_expect(before == after, "Every captured owner round-trips exactly, without offline time or duplicated rewards.")
	if not _required_load("roundtrip_repeat_load"):
		return
	await _assert_seed(saved_raw.pickup_sources)
	if _aborted: return
	_expect(before == store.snapshot.capture(content), "Repeated Load does not duplicate date inventory or pickup views.")
	await _assert_refill_boundaries(before, saved_raw)
	if _aborted: return
	await _assert_future_palm_rng_sequence(saved_raw)
	if _aborted: return
	if not _required_load("post_rng_load"):
		return
	await _assert_seed(saved_raw.pickup_sources)
	if _aborted: return
	_test_pending_wall_refund_roundtrip(before)
	if _aborted: return
	await _assert_seed(saved_raw.pickup_sources)
	if _aborted: return
	# Reject malformed palm ledgers through the disk boundary and prove each Load
	# leaves every live owner untouched.
	var valid_bytes: String = FileAccess.get_file_as_string(CHECKPOINT_PATH)
	for invalid_case: String in ["missing_collection", "missing_identity", "unknown_identity", "wrong_capacity", "non_bool_slot", "full_with_timer", "depleted_without_timer", "timer_too_large", "timer_float", "rng_bool", "rng_float", "rng_extra_field", "timer_negative", "missing_rng", "extra_field", "missing_config", "config_wrong_capacity", "config_extra_field"]:
		await _assert_invalid_palm_case(before, saved_raw, invalid_case)
		if _aborted: return
	if not _write_text(CHECKPOINT_PATH, valid_bytes):
		_fail_fast("valid_checkpoint_rewrite", "Could not restore valid isolated checkpoint bytes after negative controls.")
		return
	if not _required_load("valid_checkpoint_restore"): return
	await _assert_seed(saved_raw.pickup_sources)
	if _aborted: return
	if _aborted: return
	# Legacy v1 and v2 files lack pickup-source data. Applying either version
	# restores every registered source to full stock and starts a fresh RNG.
	var legacy_rng: Dictionary = _set_palm_rng_sentinels()
	var legacy: Dictionary = before.duplicate(true)
	legacy.schema_version = 1
	legacy.erase("location")
	var legacy_raw: Dictionary = saved_raw.duplicate(true)
	legacy_raw.erase("pickup_sources")
	_strip_post_v3_owner_fields(legacy_raw)
	legacy.state = LEGACY_RELIABILITY.encode_city(codec, legacy_raw)
	_strip_post_v3_worker_fields(legacy.state)
	if not _assert_legacy_validation_only(legacy): return
	if not _write_text(CHECKPOINT_PATH, JSON.stringify(legacy, "", true, true)):
		_fail_fast("legacy_v1_write", "Could not write isolated v1 fixture.")
		return
	if not _required_load("legacy_v1_load"): return
	await _assert_legacy_palms_reset(legacy_rng)
	legacy = before.duplicate(true)
	legacy.schema_version = 2
	legacy_raw = saved_raw.duplicate(true)
	legacy_raw.erase("pickup_sources")
	_strip_post_v3_owner_fields(legacy_raw)
	legacy.state = LEGACY_RELIABILITY.encode_city(codec, legacy_raw)
	_strip_post_v3_worker_fields(legacy.state)
	if not _write_text(CHECKPOINT_PATH, JSON.stringify(legacy, "", true, true)):
		_fail_fast("legacy_v2_write", "Could not write isolated v2 fixture.")
		return
	legacy_rng = _set_palm_rng_sentinels()
	if not _assert_legacy_validation_only(legacy): return
	if not _required_load("legacy_v2_load"): return
	await _assert_legacy_palms_reset(legacy_rng)
	# Version 3 stored the old six palms without source configuration. Its load
	# path restores those six records exactly and initializes newer sources.
	var legacy_palms: Dictionary = {}
	for identity: String in saved_raw.pickup_sources:
		if not identity.begins_with("DatePalm_"):
			continue
		var palm_record: Dictionary = saved_raw.pickup_sources[identity].duplicate(true)
		palm_record.erase("config")
		legacy_palms[identity] = palm_record
	_expect(legacy_palms.size() == 6, "The v3 migration fixture contains the original six DatePalm identities.")
	legacy = before.duplicate(true)
	legacy.schema_version = 3
	legacy_raw = saved_raw.duplicate(true)
	legacy_raw.erase("pickup_sources")
	legacy_raw["date_palms"] = legacy_palms
	_strip_post_v3_owner_fields(legacy_raw)
	legacy.state = LEGACY_RELIABILITY.encode_city(codec, legacy_raw)
	_strip_post_v3_worker_fields(legacy.state)
	legacy_rng = _set_palm_rng_sentinels()
	if not _assert_legacy_validation_only(legacy): return
	if not _write_text(CHECKPOINT_PATH, JSON.stringify(legacy, "", true, true)):
		_fail_fast("legacy_v3_write", "Could not write isolated v3 fixture.")
		return
	if not _required_load("legacy_v3_load"): return
	await _assert_v3_palms_restored(legacy_palms, legacy_rng)
	if not _required_save("legacy_v3_upgrade_save"): return
	_expect(JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH)).schema_version == CODEC.VERSION, "A successful save explicitly upgrades the legacy header to the current version.")
	# A malformed document must fail before any live mutation, and block Save.
	valid_bytes = FileAccess.get_file_as_string(CHECKPOINT_PATH)
	if not _write_text(CHECKPOINT_PATH, "{broken"):
		_fail_fast("corrupt_fixture_write", "Could not write isolated malformed JSON fixture.")
		return
	var sentinel: Dictionary = store.snapshot.capture(content)
	_expect(not store.load_checkpoint(), "Malformed JSON is rejected.")
	_expect(sentinel == store.snapshot.capture(content), "Invalid Load leaves the complete live world untouched.")
	_expect(not store.save_checkpoint() and FileAccess.get_file_as_string(CHECKPOINT_PATH) == "{broken", "Corrupt primary is preserved, never silently overwritten.")
	if not _write_text(CHECKPOINT_PATH, valid_bytes):
		_fail_fast("repair_fixture_write", "Could not restore isolated valid checkpoint bytes.")
		return
	if not _required_load("repaired_valid_file_load"): return
	var values = VALUES.new()
	var raw: Dictionary = values.decode(before.state)
	raw.inventory.items["unknown_item"] = 3
	var invalid: Dictionary = before.duplicate(true)
	invalid.state = values.encode(raw)
	_expect(not store.snapshot.prepare(invalid, content), "Unknown items reject the entire checkpoint.")
	_expect(sentinel == store.snapshot.capture(content), "Schema rejection has no side effects.")
	# Continue the real build, then save during the real raid, after a breach.
	_set_clock_minute(_clock_minute() + state._work_remaining)
	content.get_node("YSortWorld/WorkerRuntime").daily.tick()
	_expect(state.wall_hp == 50 and state._attack_at > _clock_minute(), "Restored construction finishes once and starts a journey.")
	var arrival: int = state._attack_at
	_set_clock_minute(arrival)
	content.get_node("YSortWorld/WorkerRuntime").daily.tick()
	state.set_process(false)
	state.advance_attack(8.0)
	_expect(state.phase == "attacking", "The attack has started before the in-flight checkpoint.")
	if not _required_save("active_raid_save"): return
	var hp: int = state.wall_hp
	var elapsed: float = state._elapsed
	state.advance_attack(10.0)
	if not _required_load("active_raid_load"): return
	state.set_process(false)
	_expect(state.wall_hp == hp and state._elapsed == elapsed, "Attack HP and real-second hit cadence resume exactly.")
	state.wall_hp = 1
	state.advance_attack(3.0)
	_expect(state.phase == "looting", "The resumed raid reaches the real looting phase.")
	var satisfaction: float = CitizenNeedsManager.get_average_satisfaction()
	var city_progress: int = WorkStateRuntime.get_node("CityProgression").progress
	if not _required_save("looting_save"): return
	var loot_before: Dictionary = state._stolen.duplicate()
	state.advance_attack(2.0)
	if not _required_load("looting_load"): return
	state.set_process(false)
	_expect(state._stolen == loot_before and CitizenNeedsManager.get_average_satisfaction() == satisfaction and WorkStateRuntime.get_node("CityProgression").progress == city_progress,
		"Breach penalties and stolen items are not applied a second time by Load.")
	ui.open_details()
	ui._select_hub_tab(true)
	await capture_defense("city-save-supply.png")
	var frame: Rect2 = ui.details_panel.get_global_rect()
	ui._select_hub_tab(false)
	await capture_defense("city-save-management.png")
	_expect(ui.details_panel.get_global_rect() == frame and frame.size == Vector2(300, 196), "Save/Load footer preserves the fixed Hub frame in both tabs.")
	var footer: Control = ui.details_panel.get_node("Margin/Contents/FooterRow")
	_expect(footer.get_global_rect().end.y <= frame.end.y - 8, "Save/Load controls stay inside the panel.")
	if not _clean_files():
		_fail_fast("cleanup", "Could not safely clear isolated checkpoint files after the full scenario.")
		return
	_finish()

func _load_content_checked() -> bool:
	var content_resource: Resource = ResourceLoader.load("res://scenes/content_scene/content_scene.tscn")
	if not content_resource is PackedScene:
		return false
	content = content_resource.instantiate()
	if not is_instance_valid(content):
		return false
	add_child(content)
	await _settle_physics()
	var world: Node = content.get_node_or_null("YSortWorld")
	var player_node: Node = world.get_node_or_null("Player") if world != null else null
	var bootstrap: Node = content.get_node_or_null("RaidBootstrap")
	if player_node == null or bootstrap == null:
		return false
	var raid_state: Variant = bootstrap.get("state")
	if not raid_state is Node:
		return false
	var raid_ui: Node = raid_state.get_node_or_null("RaidUI")
	var city_storage: Node = WorkStateRuntime.get_node_or_null("CityToolStorage")
	if raid_ui == null or city_storage == null:
		return false
	player = player_node as Player
	state = raid_state
	ui = raid_ui as RaidUI
	storage = city_storage
	if player == null or ui == null or state.get("storage") != storage:
		return false
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	return true

func _validate_isolated_user_data() -> bool:
	return _validate_user_data_profile(true)

func _validate_inherited_test_user_data() -> bool:
	return _validate_user_data_profile(false)

func _validate_user_data_profile(require_suite_root: bool) -> bool:
	var qa_root: String = ProjectSettings.globalize_path("res://../citysave_suite_qa").simplify_path()
	var data_home: String = OS.get_environment("XDG_DATA_HOME").simplify_path()
	var config_home: String = OS.get_environment("XDG_CONFIG_HOME").simplify_path()
	var cache_home: String = OS.get_environment("XDG_CACHE_HOME").simplify_path()
	var homes: Array[String] = [data_home, config_home, cache_home]
	for home: String in homes:
		if home.is_empty() or not home.is_absolute_path() or not DirAccess.dir_exists_absolute(home):
			return false
		if require_suite_root and not home.begins_with(qa_root + "/"):
			return false
	if data_home == config_home or data_home == cache_home or config_home == cache_home:
		return false
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	if not user_root.begins_with(data_home + "/"):
		return false
	_safe_xdg_data_home = data_home
	return true

func _checkpoint_path_is_safe() -> bool:
	if _safe_xdg_data_home.is_empty() and not _validate_inherited_test_user_data():
		return false
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	var expected: String = user_root.path_join("city_save_test/checkpoint.json").simplify_path()
	var actual: String = ProjectSettings.globalize_path(CHECKPOINT_PATH).simplify_path()
	return user_root.begins_with(_safe_xdg_data_home + "/") and actual == expected

func _path_is_safe_for_test_file(path: String) -> bool:
	if _safe_xdg_data_home.is_empty() and not _validate_inherited_test_user_data():
		return false
	if not path.begins_with("user://"):
		return false
	var absolute: String = ProjectSettings.globalize_path(path).simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	return user_root.begins_with(_safe_xdg_data_home + "/") and absolute.begins_with(user_root + "/")

func _fail_fast(phase: String, message: String) -> void:
	if _aborted:
		return
	_aborted = true
	print("CitySaveTest: FAIL phase=" + phase + ": " + message)
	get_tree().quit(1)

func _required_load(phase: String) -> bool:
	if not _checkpoint_path_is_safe():
		_fail_fast(phase, "Checkpoint path is outside the isolated user-data profile.")
		return false
	if store.load_checkpoint():
		return true
	_fail_fast(phase, "Required checkpoint load failed: " + str(store.last_error))
	return false

func _required_prepare(document: Dictionary, phase: String) -> bool:
	var prepared_ok: bool = store.snapshot.prepare(document, content)
	if prepared_ok:
		return true
	_fail_fast(phase, "Required checkpoint preparation failed: " + str(store.snapshot.error))
	return false

func _required_save(phase: String) -> bool:
	if not _checkpoint_path_is_safe():
		_fail_fast(phase, "Checkpoint path is outside the isolated user-data profile.")
		return false
	if store.save_checkpoint():
		return true
	_fail_fast(phase, "Required checkpoint save failed: " + str(store.last_error))
	return false

func _capture_checkpoint_files(phase: String) -> Dictionary:
	if not _checkpoint_path_is_safe():
		_fail_fast(phase, "Checkpoint path is outside the isolated user-data profile.")
		return {}
	var captured: Dictionary = {}
	for suffix: String in CHECKPOINT_SUFFIXES:
		var path: String = CHECKPOINT_PATH + suffix
		var present: bool = FileAccess.file_exists(path)
		captured[suffix] = {"present": present, "bytes": FileAccess.get_file_as_string(path) if present else ""}
	return captured

func _restore_checkpoint_files(captured: Dictionary, phase: String) -> bool:
	if not _clean_files():
		_fail_fast(phase, "Could not safely clear the isolated checkpoint before restoring its original bytes.")
		return false
	for suffix: String in CHECKPOINT_SUFFIXES:
		var record: Dictionary = captured.get(suffix, {})
		if record.get("present", false) and not _write_text(CHECKPOINT_PATH + suffix, str(record.get("bytes", ""))):
			_fail_fast(phase, "Could not restore isolated checkpoint sibling " + suffix)
			return false
	return true

func _seed() -> bool:
	var failures_before_seed: int = failures
	if not is_instance_valid(content) or not is_instance_valid(player) or not is_instance_valid(state) or not is_instance_valid(storage):
		return false
	var world: Node = content.get_node_or_null("YSortWorld")
	var runtime: Node = content.get_node_or_null("YSortWorld/WorkerRuntime")
	if world == null or runtime == null or runtime.get("daily") == null:
		return false
	_set_clock_minute(7 * 1440 + 600)
	# This fixture jumps the clock directly; worksite time normally advances via
	# per-minute signals, so settle its idle ledger before capturing the world.
	runtime.daily.tick()
	Inventory.items.assign({"shekel": 17, "stone": 13, "wood_log": 5})
	storage.items = {"stone": 100, "wood_log": 100, "egg": 5}
	player.fatigue = 0.75
	var pickup: PickUpItem = preload("res://scenes/pickup_item/pickup_item.tscn").instantiate()
	if not is_instance_valid(pickup):
		return false
	pickup.item_id = "clay_lump"
	pickup.quantity = 4
	pickup.position = Vector2(-210, -260)
	world.add_child(pickup)
	_payment_clock_before = _clock_minute()
	_payment_clock_after = -1
	_payment_guard_seen = false
	Inventory.items_changed.connect(_try_advance_clock_during_wall_payment)
	var wall_started: bool = state.request_wall_work(state.get_work_quote())
	Inventory.items_changed.disconnect(_try_advance_clock_during_wall_payment)
	if not wall_started:
		return false
	if _scenario_selection == "inject_seed_failure":
		_payment_guard_seen = false
	_expect(_payment_guard_seen and _payment_clock_after == _payment_clock_before,
		"A payment observer cannot advance city time while the wall ledger and Inventory debit are being published.")
	if failures > failures_before_seed:
		return false
	WorkStateRuntime.get_node("CityProgression").progress = 35
	if not await _seed_authored_palms():
		return false
	TimeComponentManager._timer = 0.375
	return true

func _assert_seed(expected_palms: Dictionary = {}) -> void:
	var failures_before_seed_assertions: int = failures
	await get_tree().process_frame
	await get_tree().process_frame
	var palm_trees: Array = _authored_palm_trees()
	if palm_trees.size() != 6:
		_fail_fast("palm_fixture", "The legacy source fixture requires exactly six authored DatePalmTree ledgers.")
		return
	for tree: Node in palm_trees:
		if tree.get("state") == null:
			_fail_fast("palm_fixture", "An authored DatePalmTree is missing its source ledger: " + tree.name)
			return
	_expect(TimeComponentManager.current_day == 7, "A later-day checkpoint restores into a fresh day-zero session.")
	var palm_pickups: Array = get_tree().get_nodes_in_group("date_palm_pickups")
	_expect(palm_pickups.is_empty(), "Legacy source fixture keeps all six authored palm pickup views intentionally hidden.")
	for tree: Node in palm_trees:
		_expect(not tree.world_view_enabled and tree._pickups.is_empty(), "Legacy authored palm remains opted out of world pickup views: " + tree.name)
		_expect(tree.state.available.size() == 3 and tree.state.available.count(true) == 2 and tree.state.remaining_minutes > 0,
			"Legacy source fixture restores two available slots and a pending refill timer: " + tree.name)
		for slot: int in range(tree.state.available.size()):
			_expect(not tree._pickups.has(slot), "Legacy hidden view does not project slot " + str(slot) + ": " + str(tree.name))
		if expected_palms.has(tree.state.name):
			var expected: Dictionary = expected_palms[tree.state.name]
			_expect(tree.state.available == expected.available and tree.state.remaining_minutes == expected.remaining_minutes,
				"Each legacy source fixture restores its exact slot ledger and remaining minutes: " + tree.name)
			_expect(tree.state._rng.seed == expected.rng.seed and tree.state._rng.state == expected.rng.state,
				"Each legacy source fixture restores its exact RNG seed and state: " + tree.name)
	_expect(Inventory.items.get("date_cluster", 0) == 6, "Synthetic six-date inventory remains stable across the hidden legacy fixture checkpoint.")
	var drops: Array = store.snapshot._capture_city_drops(content)
	_expect(drops.size() == 1 and drops[0].quantity == 4 and drops[0].item_id == "clay_lump", "Dropped inventory items survive without duplication.")
	_expect(Inventory.items.get("shekel") == 17 and Inventory.items.get("stone") == 3 and Inventory.items.get("wood_log", 0) == 0, "Player inventory preserves the one-time wall payment across the checkpoint.")
	_expect(storage.items.get("stone") == 100 and storage.items.get("wood_log") == 100, "Wall materials are not taken from City Storage.")
	_expect(state._work_remaining == 120 and state._work_kind == "build" and state._work_paid_source == "inventory" and state.wall_hp == 0, "Unfinished wall work retains its timer, payment source, and ruined wall.")
	_expect(WorkStateRuntime.get_node("CityProgression").progress == 35 and is_equal_approx(player.fatigue, 0.75), "City progress and player conditions survive.")
	if failures > failures_before_seed_assertions:
		_fail_fast("seed_verify", "A CitySave seed/restore assertion failed; dependent scenarios were stopped.")

func _clean_files() -> bool:
	if not _checkpoint_path_is_safe():
		return false
	for suffix: String in CHECKPOINT_SUFFIXES:
		var path: String = CHECKPOINT_PATH + suffix
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
			return false
	return true

func _try_advance_clock_during_wall_payment() -> void:
	var raid: Node = WorkStateRuntime.get_node("CityRaid")
	_payment_guard_seen = raid.is_transaction_busy()
	TimeComponentManager.advance_one_minute()
	_payment_clock_after = _clock_minute()

func _test_pending_wall_refund_roundtrip(current: Dictionary) -> void:
	var original_bytes: String = JSON.stringify(current, "", true, true)
	var original_capacity: float = Inventory.max_load
	state.wall_level = 1
	state.wall_hp = 40
	state.phase = "safe"
	state._work_kind = "repair"
	state._work_remaining = 30
	state._work_total = 60
	state._work_restore_hp = 10
	state._work_base_max_hp = 50
	state._work_paid = {"stone": 2}
	state._work_paid_source = "inventory"
	state._refund_pending = false
	Inventory.items["stone"] = maxi(0, int(Inventory.items.get("stone", 0)) - 2)
	Inventory.max_load = Inventory.get_total_inventory_weight()
	state._refund_interrupted_repair()
	_expect(state._refund_pending and state._work_paid == {"stone": 2},
		"A full Inventory leaves an unfinished repair refund pending.")
	if not _required_save("pending_refund_save"): return
	var pending_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	if not pending_value is Dictionary or not pending_value.get("state") is Dictionary:
		_fail_fast("pending_refund_decode", "Pending refund checkpoint did not decode to a document.")
		return
	var pending_document: Dictionary = pending_value
	var pending_codec = VALUES.new()
	var pending_raw_value: Variant = pending_codec.decode(pending_document.state)
	if not pending_raw_value is Dictionary or not pending_codec.error.is_empty():
		_fail_fast("pending_refund_decode", "Pending refund state did not decode: " + pending_codec.error)
		return
	var pending_raw: Dictionary = pending_raw_value
	_expect(pending_document.schema_version == CODEC.VERSION and pending_raw.raid._refund_pending and pending_raw.raid._work_paid == {"stone": 2},
		"The current checkpoint records the pending refund and retained materials.")
	state._refund_pending = false
	state._work_kind = ""
	state._work_paid.clear()
	state._work_paid_source = ""
	if not _required_load("pending_refund_load"): return
	_expect(state._refund_pending and state._work_paid == {"stone": 2} and state._work_paid_source == "inventory",
		"Loading restores the pending repair and its Inventory refund provider.")
	Inventory.max_load = maxf(original_capacity, Inventory.get_total_inventory_weight() + 2.0)
	state._refund_interrupted_repair()
	_expect(not state._refund_pending and state._work_kind.is_empty() and Inventory.items.get("stone", 0) == 3,
		"A restored refund retries when Inventory capacity becomes available.")
	var after_refund: int = int(Inventory.items.get("stone", 0))
	state._refund_interrupted_repair()
	_expect(Inventory.items.get("stone", 0) == after_refund,
		"A restored pending refund cannot be applied twice.")
	Inventory.max_load = original_capacity
	if not _write_text(CHECKPOINT_PATH, original_bytes):
		_fail_fast("pending_refund_restore_write", "Could not restore the original isolated wall checkpoint bytes.")
		return
	if not _required_load("pending_refund_restore_load"): return

func _seed_authored_palms() -> bool:
	var failures_before_palm_fixture: int = failures
	await get_tree().process_frame
	await get_tree().process_frame
	var palm_trees: Array = _authored_palm_trees()
	if palm_trees.size() != 6:
		return false
	for index: int in range(palm_trees.size()):
		var tree: Node = palm_trees[index]
		if tree.state == null or tree.world_view_enabled or not tree._pickups.is_empty() or tree.state.available.size() != 3:
			return false
		tree.state._rng.seed = 1000 + index
		tree.state.collect(index % 3)
	Inventory.items["date_cluster"] = 6
	await get_tree().process_frame
	_expect(Inventory.items.get("date_cluster", 0) == 6, "Legacy source fixture seeds six synthetic date clusters in Inventory.")
	_expect(get_tree().get_nodes_in_group("date_palm_pickups").is_empty(), "Legacy source fixture keeps all intentionally hidden authored palm pickup views absent.")
	for tree: Node in palm_trees:
		_expect(tree.state.available.count(false) == 1 and tree.state.remaining_minutes > 0, "Legacy source fixture records one selected hidden slot and a pending timer: " + tree.name)
		_expect(tree._pickups.is_empty(), "Legacy source fixture exposes no visible pickup view: " + tree.name)
	return failures == failures_before_palm_fixture

func _authored_palm_trees() -> Array:
	var result: Array = []
	var world: Node = content.get_node_or_null("YSortWorld")
	if world == null:
		return result
	for child: Node in world.get_children():
		if child.get_script() == preload("res://scenes/pickup_item/date_palm_spawner.gd"):
			result.append(child)
	result.sort_custom(func(left: Node, right: Node) -> bool: return left.name < right.name)
	return result

func _assert_saved_source_shape(sources: Dictionary) -> void:
	var expected_ids: Dictionary = {}
	for tree: Node in _authored_palm_trees():
		expected_ids[tree.state.name] = true
	_expect(sources.size() == expected_ids.size(), "Pickup-source save has the exact authored identity count.")
	for identity: String in expected_ids:
		_expect(sources.has(identity), "Pickup-source save includes the authored runtime identity " + identity)
		if not sources.has(identity):
			continue
		var value: Dictionary = sources[identity]
		_expect(value.size() == 4 and value.available is Array and value.available.size() == 3,
			"Pickup-source save uses the exact authored capacity for " + identity)
		_expect(value.available.count(false) == 1 and value.available.count(true) == 2,
			"Palm save records exactly one harvested slot for " + identity)
		_expect(typeof(value.remaining_minutes) == TYPE_INT and value.remaining_minutes >= 1 and value.remaining_minutes <= 18 * TimeComponentManager.minute_per_hour,
			"Palm save records a bounded integer refill timer for " + identity)
		_expect(value.rng is Dictionary and value.rng.size() == 2 and typeof(value.rng.get("seed")) == TYPE_INT and typeof(value.rng.get("state")) == TYPE_INT,
			"Pickup-source save records exact integer RNG seed and state for " + identity)
		_expect(value.config is Dictionary and value.config.size() == 6,
			"Pickup-source save retains its complete authored configuration for " + identity)
		if value.config is Dictionary:
			_expect(typeof(value.config.get("item_id")) == TYPE_STRING and typeof(value.config.get("quantity")) == TYPE_INT
				and typeof(value.config.get("capacity")) == TYPE_INT and typeof(value.config.get("refill_enabled")) == TYPE_BOOL
				and typeof(value.config.get("refill_min_hours")) == TYPE_INT and typeof(value.config.get("refill_max_hours")) == TYPE_INT,
				"Pickup-source config values keep their exact declared types for " + identity)
		if identity.begins_with("DatePalm_") and value.config is Dictionary:
			_expect(value.config == {"item_id": "date_cluster", "quantity": 1, "capacity": 3,
				"refill_enabled": true, "refill_min_hours": 1, "refill_max_hours": 18},
				"Date palm source config preserves its authored item, capacity and refill range.")

func _assert_future_palm_rng_sequence(saved_raw: Dictionary) -> void:
	var expected_by_id: Dictionary = {}
	for identity: String in saved_raw.pickup_sources:
		var record: Dictionary = saved_raw.pickup_sources[identity]
		var saved_rng: Dictionary = record.rng
		var config: Dictionary = record.config
		var expected_rng := RandomNumberGenerator.new()
		expected_rng.seed = saved_rng.seed
		expected_rng.state = saved_rng.state
		var expected_delays: Array[int] = []
		for draw: int in range(mini(2, record.available.size())):
			var delay: int = 0
			if config.refill_enabled:
				delay = expected_rng.randi_range(config.refill_min_hours, config.refill_max_hours) * TimeComponentManager.minute_per_hour
			expected_delays.append(delay)
		expected_by_id[identity] = expected_delays
	for tree: Node in _authored_palm_trees():
		var state_node: Node = tree.state
		var actual: Array = []
		for slot: int in range(mini(2, state_node.available.size())):
			state_node.available.fill(true)
			state_node.remaining_minutes = 0
			state_node.collect(slot)
			actual.append(state_node.remaining_minutes)
		_expect(actual == expected_by_id[state_node.name], "Palm RNG resumes its exact future refill sequence: " + tree.name)
	if not _required_load("palm_rng_restore_load"): return
	await _assert_seed(saved_raw.pickup_sources)

func _assert_invalid_palm_case(valid_document: Dictionary, valid_raw: Dictionary, case_name: String) -> void:
	var invalid_raw: Dictionary = valid_raw.duplicate(true)
	var identity: String = str(invalid_raw.pickup_sources.keys()[0])
	match case_name:
		"missing_collection":
			invalid_raw.erase("pickup_sources")
		"missing_identity":
			invalid_raw.pickup_sources.erase(identity)
		"unknown_identity":
			invalid_raw.pickup_sources["DatePalm_NotAnAuthoredTree"] = invalid_raw.pickup_sources[identity].duplicate(true)
			invalid_raw.pickup_sources.erase(identity)
		"wrong_capacity":
			invalid_raw.pickup_sources[identity].available.pop_back()
		"non_bool_slot":
			invalid_raw.pickup_sources[identity].available[0] = 1
		"full_with_timer":
			invalid_raw.pickup_sources[identity].available.fill(true)
			invalid_raw.pickup_sources[identity].remaining_minutes = TimeComponentManager.minute_per_hour
		"depleted_without_timer":
			invalid_raw.pickup_sources[identity].available.fill(false)
			invalid_raw.pickup_sources[identity].remaining_minutes = 0
		"timer_too_large":
			invalid_raw.pickup_sources[identity].remaining_minutes = 18 * TimeComponentManager.minute_per_hour + 1
		"timer_negative":
			invalid_raw.pickup_sources[identity].remaining_minutes = -1
		"missing_rng":
			invalid_raw.pickup_sources[identity].erase("rng")
		"extra_field":
			invalid_raw.pickup_sources[identity]["extra"] = true
		"timer_float":
			invalid_raw.pickup_sources[identity].remaining_minutes = 60.0
		"rng_bool":
			invalid_raw.pickup_sources[identity].rng.seed = true
		"rng_float":
			invalid_raw.pickup_sources[identity].rng.state = 1.0
		"rng_extra_field":
			invalid_raw.pickup_sources[identity].rng["extra"] = 1
		"missing_config":
			invalid_raw.pickup_sources[identity].erase("config")
		"config_wrong_capacity":
			invalid_raw.pickup_sources[identity].config.capacity = true
		"config_extra_field":
			invalid_raw.pickup_sources[identity].config["extra"] = 1
	var codec = VALUES.new()
	var invalid_document: Dictionary = valid_document.duplicate(true)
	invalid_document.state = codec.encode(invalid_raw)
	var baseline: Dictionary = store.snapshot.capture(content)
	if not _write_text(CHECKPOINT_PATH, JSON.stringify(invalid_document, "", true, true)):
		_fail_fast("invalid_palm_write", "Could not write isolated invalid palm fixture: " + case_name)
		return
	_expect(not store.load_checkpoint(), "Load rejects invalid date palm data: " + case_name)
	_expect(baseline == store.snapshot.capture(content), "Invalid palm data leaves every live owner untouched: " + case_name)
	if not _write_text(CHECKPOINT_PATH, JSON.stringify(valid_document, "", true, true)):
		_fail_fast("invalid_palm_restore_write", "Could not restore valid isolated checkpoint bytes after negative control: " + case_name)

func _set_palm_rng_sentinels() -> Dictionary:
	var sentinel_by_id: Dictionary = {}
	var source_nodes: Dictionary = store.snapshot._sources.nodes()
	for index: int in range(source_nodes.size()):
		var source_id: String = str(source_nodes.keys()[index])
		var source: Node = source_nodes[source_id]
		source._rng.seed = 900000 + index
		source._rng.state = 800000 + index
		sentinel_by_id[source_id] = {"seed": source._rng.seed, "state": source._rng.state}
	return sentinel_by_id

func _assert_legacy_palms_reset(sentinels: Dictionary) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var source_nodes: Dictionary = store.snapshot._sources.nodes()
	for source_id: String in source_nodes:
		var source: Node = source_nodes[source_id]
		_expect(source.available.count(true) == source.available.size() and source.remaining_minutes == 0,
			"A legacy checkpoint explicitly restores full pickup stock and clears its timer: " + source_id)
		var sentinel: Dictionary = sentinels[source_id]
		_expect(source._rng.seed != sentinel.seed or source._rng.state != sentinel.state,
			"A legacy checkpoint starts a fresh pickup-source RNG: " + source_id)
	_expect(get_tree().get_nodes_in_group("date_palm_pickups").is_empty(),
		"Legacy palm fallback keeps the six authored hidden views absent.")
	_expect(Inventory.items.get("date_cluster", 0) == 6, "Legacy palm fallback preserves collected dates without granting more.")

func _assert_v3_palms_restored(legacy_palms: Dictionary, sentinels: Dictionary) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var captured: Dictionary = store.snapshot._sources.capture()
	for identity: String in legacy_palms:
		var expected: Dictionary = legacy_palms[identity]
		var actual: Dictionary = captured[identity]
		_expect(actual.available == expected.available and actual.remaining_minutes == expected.remaining_minutes
			and actual.rng == expected.rng,
			"A v3 checkpoint restores the legacy palm slots, timer and RNG exactly: " + identity)
	var source_nodes: Dictionary = store.snapshot._sources.nodes()
	for identity: String in source_nodes:
		if legacy_palms.has(identity):
			continue
		var source: Node = source_nodes[identity]
		_expect(source.available.count(true) == source.available.size() and source.remaining_minutes == 0,
			"A v3 checkpoint initializes sources absent from the v3 ledger: " + identity)
		var sentinel: Dictionary = sentinels[identity]
		_expect(source._rng.seed != sentinel.seed or source._rng.state != sentinel.state,
			"A v3 checkpoint starts a fresh RNG for sources absent from its ledger: " + identity)
	_expect(get_tree().get_nodes_in_group("date_palm_pickups").is_empty(),
		"A v3 load preserves six legacy ledgers without creating hidden pickup views.")
	_expect(Inventory.items.get("date_cluster", 0) == 6, "A v3 load preserves collected dates without granting more.")

func _write_text(path: String, value: String) -> bool:
	if not _path_is_safe_for_test_file(path):
		return false
	var absolute_path: String = ProjectSettings.globalize_path(path).simplify_path()
	var parent_path: String = absolute_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent_path) and DirAccess.make_dir_recursive_absolute(parent_path) != OK:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	var write_error: Error = file.get_error()
	file.close()
	return write_error == OK

func _same_snapshot(left: Variant, right: Variant) -> bool:
	# The save codec represents dictionary entries as ordered arrays; Godot may
	# decode the entries in a different insertion order after a fresh process.
	# Canonicalize only that representation while keeping ordinary arrays, exact
	# types, encoded int64 strings, timers, and RNG values strict.
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.get("$type") == "dictionary" or right.get("$type") == "dictionary":
			if left.get("$type") != "dictionary" or right.get("$type") != "dictionary":
				return false
			if left.size() != 2 or right.size() != 2:
				return false
			var left_entries: Variant = left.get("entries")
			var right_entries: Variant = right.get("entries")
			if not left_entries is Array or not right_entries is Array or left_entries.size() != right_entries.size():
				return false
			var matched_right: Dictionary = {}
			for left_index: int in range(left_entries.size()):
				var left_entry: Variant = left_entries[left_index]
				if not left_entry is Array or left_entry.size() != 2:
					return false
				var match_index: int = -1
				for right_index: int in range(right_entries.size()):
					if matched_right.has(right_index):
						continue
					var right_entry: Variant = right_entries[right_index]
					if right_entry is Array and right_entry.size() == 2 and _same_snapshot(left_entry[0], right_entry[0]):
						match_index = right_index
						break
				if match_index < 0:
					return false
				matched_right[match_index] = true
				if not _same_snapshot(left_entry[1], right_entries[match_index][1]):
					return false
			return true
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _same_snapshot(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not _same_snapshot(left[index], right[index]):
				return false
		return true
	return left == right

func _same_wire_snapshot(left: Variant, right: Variant) -> bool:
	# Normalize both full documents through the JSON wire format first. In-memory
	# integer headers become floats when parsed from disk, while tagged values
	# retain their explicit type and int64 strings for strict comparison below.
	var left_json: String = JSON.stringify(left, "", true, true)
	var right_json: String = JSON.stringify(right, "", true, true)
	if left_json.is_empty() or right_json.is_empty():
		return false
	var left_wire: Variant = JSON.parse_string(left_json)
	var right_wire: Variant = JSON.parse_string(right_json)
	if left_wire == null or right_wire == null:
		return false
	return _same_snapshot(left_wire, right_wire)

func _assert_comparator_controls() -> void:
	var memory_header: Dictionary = {"schema_version": CODEC.VERSION}
	var parsed_header: Variant = JSON.parse_string(JSON.stringify(memory_header, "", true, true))
	_expect(typeof(memory_header.schema_version) == TYPE_INT and parsed_header is Dictionary
		and typeof(parsed_header.schema_version) == TYPE_FLOAT
		and not _same_snapshot(memory_header, parsed_header)
		and _same_wire_snapshot(memory_header, parsed_header),
		"Wire-format comparison normalizes the JSON numeric representation of the schema header.")
	var entry_a: Array = [[{"$type": "string", "value": "a"}, {"$type": "int", "value": "9223372036854775807"}], [{"$type": "string", "value": "b"}, {"$type": "array", "items": [1, 2]}]]
	var entry_b: Array = [entry_a[1].duplicate(true), entry_a[0].duplicate(true)]
	var left: Dictionary = {"$type": "dictionary", "entries": entry_a}
	var right: Dictionary = {"$type": "dictionary", "entries": entry_b}
	_expect(_same_snapshot(left, right) and _same_wire_snapshot(left, right),
		"Fresh-process comparison ignores only tagged-dictionary insertion order.")
	var reordered_array: Dictionary = {"$type": "dictionary", "entries": [[{"$type": "string", "value": "b"}, {"$type": "array", "items": [2, 1]}], entry_a[0].duplicate(true)]}
	_expect(not _same_snapshot(left, reordered_array) and not _same_wire_snapshot(left, reordered_array),
		"Fresh-process comparison preserves ordinary array order.")
	var changed_int64: Dictionary = {"$type": "dictionary", "entries": [[{"$type": "string", "value": "b"}, {"$type": "array", "items": [1, 2]}], [{"$type": "string", "value": "a"}, {"$type": "int", "value": "9223372036854775806"}]]}
	_expect(not _same_snapshot(left, changed_int64) and not _same_wire_snapshot(left, changed_int64),
		"Fresh-process comparison preserves exact encoded integer values.")
	_expect(not _same_snapshot({"$type": "int", "value": "1"}, {"$type": "float", "value": 1.0})
		and not _same_snapshot({"$type": "int", "value": "1"}, {"$type": "bool", "value": true})
		and not _same_wire_snapshot({"$type": "int", "value": "1"}, {"$type": "float", "value": 1.0})
		and not _same_wire_snapshot({"$type": "int", "value": "1"}, {"$type": "bool", "value": true}),
		"Fresh-process comparison preserves exact tagged value types.")
	var extra_wrapper_field: Dictionary = left.duplicate(true)
	extra_wrapper_field["metadata"] = true
	_expect(not _same_snapshot(left, extra_wrapper_field) and not _same_wire_snapshot(left, extra_wrapper_field),
		"Fresh-process comparison rejects added tagged-dictionary wrapper fields.")
	var timer_before: Dictionary = {"$type": "dictionary", "entries": [[{"$type": "string", "value": "remaining_minutes"}, {"$type": "int", "value": "360"}], [{"$type": "string", "value": "rng_state"}, {"$type": "int", "value": "9007199254740993"}]]}
	var timer_after: Dictionary = {"$type": "dictionary", "entries": [[{"$type": "string", "value": "remaining_minutes"}, {"$type": "int", "value": "361"}], [{"$type": "string", "value": "rng_state"}, {"$type": "int", "value": "9007199254740993"}]]}
	var rng_after: Dictionary = {"$type": "dictionary", "entries": [[{"$type": "string", "value": "remaining_minutes"}, {"$type": "int", "value": "360"}], [{"$type": "string", "value": "rng_state"}, {"$type": "int", "value": "9007199254740994"}]]}
	_expect(not _same_snapshot(timer_before, timer_after) and not _same_snapshot(timer_before, rng_after)
		and not _same_wire_snapshot(timer_before, timer_after) and not _same_wire_snapshot(timer_before, rng_after),
		"Fresh-process comparison preserves exact refill timers and RNG state.")

func _run_raid_scenario() -> void:
	var runtime: Node = content.get_node_or_null("YSortWorld/WorkerRuntime")
	if runtime == null or state._work_kind != "build" or state._work_remaining != 120:
		_fail_fast("raid_prerequisite", "The isolated raid scenario requires the seeded paid wall build and worksite scheduler.")
		return
	_set_clock_minute(_clock_minute() + state._work_remaining)
	runtime.daily.tick()
	if state.wall_hp != 50 or state._attack_at <= _clock_minute():
		_fail_fast("raid_build", "Seeded paid construction did not complete into a scheduled raid journey.")
		return
	var arrival: int = state._attack_at
	_set_clock_minute(arrival)
	runtime.daily.tick()
	state.set_process(false)
	state.advance_attack(8.0)
	if state.phase != "attacking":
		_fail_fast("raid_phase", "The scheduled raid did not reach an active attack before checkpointing.")
		return
	if not _required_save("raid_active_save"):
		return
	var saved_hp: int = state.wall_hp
	var saved_elapsed: float = state._elapsed
	state.advance_attack(10.0)
	if not _required_load("raid_active_load"):
		return
	state.set_process(false)
	_expect(state.wall_hp == saved_hp and state._elapsed == saved_elapsed,
		"Active raid HP and hit cadence restore exactly from the isolated attack checkpoint.")
	state.wall_hp = 1
	state.advance_attack(3.0)
	if state.phase != "looting":
		_fail_fast("raid_looting", "The resumed attack did not reach looting after the breach.")
		return
	var satisfaction: float = CitizenNeedsManager.get_average_satisfaction()
	var city_progress: int = WorkStateRuntime.get_node("CityProgression").progress
	if not _required_save("raid_looting_save"):
		return
	var loot_before: Dictionary = state._stolen.duplicate(true)
	state.advance_attack(2.0)
	if not _required_load("raid_looting_load"):
		return
	state.set_process(false)
	_expect(state._stolen == loot_before
		and CitizenNeedsManager.get_average_satisfaction() == satisfaction
		and WorkStateRuntime.get_node("CityProgression").progress == city_progress,
		"Loading a looting checkpoint does not apply raid penalties or stolen items twice.")

func _finish() -> void:
	if _aborted:
		return
	print("CitySaveTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _assert_legacy_validation_only(document: Dictionary) -> bool:
	var baseline: Dictionary = store.snapshot.capture(content)
	if not _required_prepare(document, "legacy_prepare"):
		return false
	_expect(store.snapshot.capture(content) == baseline, "Legacy validation alone leaves all owners, slots, timers and RNG untouched.")
	return true

func _test_wall_paid_source_migration(current: Dictionary, raw: Dictionary) -> void:
	var original_files: Dictionary = _capture_checkpoint_files("legacy_v15_snapshot")
	if _aborted or not original_files.get("", {}).get("present", false):
		_fail_fast("legacy_v15_snapshot", "Current checkpoint is required before the v15 migration scenario.")
		return
	var values = VALUES.new()
	_expect(current.schema_version == CODEC.VERSION and raw.raid._work_paid_source == "inventory", "Current saves record the new wall project's Inventory payment source.")
	var sentinel: Dictionary = store.snapshot.capture(content)
	for invalid_source: Variant in ["", "workshop_storage", 7]:
		var bad_raw: Dictionary = raw.duplicate(true)
		bad_raw.raid._work_paid_source = invalid_source
		var bad: Dictionary = current.duplicate(true)
		bad.state = values.encode(bad_raw)
		_expect(not store.snapshot.prepare(bad, content), "Current saves reject invalid wall payment source: " + str(invalid_source))
		_expect(store.snapshot.capture(content) == sentinel, "Rejected wall payment source leaves live owners unchanged.")
	var missing_source_raw: Dictionary = raw.duplicate(true)
	missing_source_raw.raid.erase("_work_paid_source")
	var missing_source: Dictionary = current.duplicate(true)
	missing_source.state = values.encode(missing_source_raw)
	_expect(not store.snapshot.prepare(missing_source, content), "Current saves require the wall payment source field.")
	_expect(store.snapshot.capture(content) == sentinel, "A missing source field leaves the live project unchanged.")

	var legacy_raw: Dictionary = raw.duplicate(true)
	legacy_raw.raid.phase = "safe"
	legacy_raw.raid.wall_level = 1
	legacy_raw.raid.wall_hp = 40
	legacy_raw.raid._work_kind = "repair"
	legacy_raw.raid._work_remaining = 30
	legacy_raw.raid._work_total = 60
	legacy_raw.raid._work_restore_hp = 10
	legacy_raw.raid._work_base_max_hp = 50
	legacy_raw.raid._work_paid = {"stone": 2}
	legacy_raw.city_storage.items["stone"] = 98
	LEGACY_RELIABILITY.strip_v16_owners(legacy_raw)
	var legacy: Dictionary = current.duplicate(true)
	legacy.schema_version = 15
	legacy.state = values.encode(legacy_raw)
	if not _required_prepare(legacy, "legacy_v15_prepare"): return
	_expect(store.snapshot.prepared.raid._work_paid_source == "city_storage" and store.snapshot.capture(content) == sentinel,
		"Legacy source migration is in-memory and does not change the live project.")
	var legacy_bytes: String = JSON.stringify(legacy, "", true, true)
	if not _write_text(CHECKPOINT_PATH, legacy_bytes):
		_fail_fast("legacy_v15_write", "Could not write isolated v15 checkpoint bytes.")
		return
	if not _required_load("legacy_v15_load"): return
	_expect(state._work_paid_source == "city_storage" and state._work_kind == "repair" and FileAccess.get_file_as_string(CHECKPOINT_PATH) == legacy_bytes,
		"Loading v15 stages City Storage as the refund source without rewriting saved bytes.")
	if not _required_save("legacy_v15_upgrade_save"): return
	_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH + ".bak") == legacy_bytes,
		"The explicit save preserves the original v15 bytes in the normal backup.")
	var upgraded_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	if not upgraded_value is Dictionary or not upgraded_value.get("state") is Dictionary:
		_fail_fast("legacy_v15_decode", "Upgraded v15 file did not decode to a checkpoint document.")
		return
	var upgraded: Dictionary = upgraded_value
	var upgraded_raw_value: Variant = values.decode(upgraded.state)
	if not upgraded_raw_value is Dictionary or not values.error.is_empty():
		_fail_fast("legacy_v15_decode", "Upgraded v15 state did not decode: " + values.error)
		return
	var upgraded_raw: Dictionary = upgraded_raw_value
	_expect(upgraded.schema_version == CODEC.VERSION and upgraded_raw.raid._work_kind == "repair" and upgraded_raw.raid._work_paid_source == "city_storage",
		"The first explicit v16 save retains the legacy repair's City Storage refund source.")
	var inventory_before_legacy_refund: Dictionary = Inventory.items.duplicate(true)
	state._refund_interrupted_repair()
	_expect(storage.items.get("stone", 0) == 100 and Inventory.items == inventory_before_legacy_refund and state._work_kind.is_empty(),
		"The migrated repair returns its paid materials to City Storage without touching Inventory.")
	state._refund_interrupted_repair()
	_expect(storage.items.get("stone", 0) == 100, "A migrated City Storage refund cannot be duplicated.")
	if not _restore_checkpoint_files(original_files, "legacy_v15_restore"): return
	if not _required_load("legacy_v15_restore_load"): return
	_expect(store.snapshot.capture(content) == sentinel,
		"The original Inventory-funded project restores after the migration test.")

func _strip_post_v3_worker_fields(value: Variant) -> void:
	if value is Dictionary:
		if value.get("$type") == "object" and value.get("class") == "WorkerData":
			for field: String in VALUES.PAYROLL_FIELDS + VALUES.CONTRACT_FIELDS + ["physical_approach"]:
				value.fields.erase(field)
		for child: Variant in value.values():
			_strip_post_v3_worker_fields(child)
	elif value is Array:
		for child: Variant in value:
			_strip_post_v3_worker_fields(child)

func _assert_refill_boundaries(document: Dictionary, raw: Dictionary) -> void:
	var staged: Dictionary = raw.duplicate(true)
	var index: int = 0
	for id: String in staged.pickup_sources:
		if not id.begins_with("DatePalm_"):
			continue
		staged.pickup_sources[id].remaining_minutes = 4 + index
		index += 1
	var codec = VALUES.new()
	var short_timers: Dictionary = document.duplicate(true)
	short_timers.state = codec.encode(staged)
	if not _write_text(CHECKPOINT_PATH, JSON.stringify(short_timers, "", true, true)):
		_fail_fast("refill_fixture_write", "Could not write isolated countdown checkpoint.")
		return
	if not _required_load("refill_fixture_load"): return
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	TimeComponentManager.advance_minutes(3)
	for elapsed: int in range(3, 10):
		if elapsed > 3:
			TimeComponentManager.advance_minutes(1)
		await get_tree().process_frame
		await get_tree().process_frame
		for tree: Node in _authored_palm_trees():
			var saved: Dictionary = staged.pickup_sources[str(tree.state.name)]
			var remaining: int = maxi(0, saved.remaining_minutes - elapsed)
			var slots: Array = [true, true, true] if remaining == 0 else saved.available
			_expect(tree.state.remaining_minutes == remaining and tree.state.available == slots, "Only the due palm refills at the exact restored minute: " + str(tree.name))
			_expect(not tree.world_view_enabled and tree._pickups.is_empty(), "Hidden legacy palm view stays absent during refill: " + str(tree.name))
			_expect(tree.state._rng.state == saved.rng.state, "Refill consumes no random draw.")
		_expect(get_tree().get_nodes_in_group("date_palm_pickups").is_empty(), "Refill never creates hidden legacy pickup views.")
		_expect(Inventory.items == inventory_before, "Refill never grants Inventory goods.")
	var full_palms: Dictionary = store.snapshot._sources.capture()
	if not _required_save("refill_full_save"): return
	if not _required_load("refill_full_load"): return
	_expect(store.snapshot._sources.capture() == full_palms, "Full palm stock preserves the next RNG draw across Load.")
	if not _write_text(CHECKPOINT_PATH, JSON.stringify(document, "", true, true)):
		_fail_fast("refill_restore_write", "Could not restore original isolated checkpoint bytes after countdown test.")
		return
	if not _required_load("refill_restore_load"): return
	await _assert_seed(raw.pickup_sources)

func _strip_post_v3_owner_fields(raw: Dictionary) -> void:
	# Pseudo-legacy documents omit owner fields absent in those schemas.
	LEGACY_RELIABILITY.strip_v16_owners(raw)
	raw.player["focus"] = 0.75
	raw.raid.erase("notification_seen_keys")
	for plot: Dictionary in raw.plots.values():
		plot.erase("payroll_work_remainder")

func _test_player_condition_migration(current: Dictionary, raw: Dictionary) -> void:
	var original_files: Dictionary = _capture_checkpoint_files("legacy_v8_snapshot")
	if _aborted or not original_files.get("", {}).get("present", false):
		_fail_fast("legacy_v8_snapshot", "Current checkpoint is required before the v8 migration scenario.")
		return
	_expect(current.schema_version == CODEC.VERSION and not raw.player.has("focus"), "Current checkpoints contain only Hunger and Fatigue.")
	var values = VALUES.new()
	var legacy_raw: Dictionary = raw.duplicate(true)
	legacy_raw.player["focus"] = 0.63
	var legacy: Dictionary = current.duplicate(true)
	legacy.schema_version = 8
	legacy.state = LEGACY_RELIABILITY.encode_city(values, legacy_raw)
	var sentinel: Dictionary = store.snapshot.capture(content)
	for allowed_focus: float in [0.0, 1.0]:
		var boundary_raw: Dictionary = legacy_raw.duplicate(true)
		boundary_raw.player["focus"] = allowed_focus
		var boundary: Dictionary = legacy.duplicate(true)
		boundary.state = LEGACY_RELIABILITY.encode_city(values, boundary_raw)
		if not _required_prepare(boundary, "legacy_v8_boundary_prepare"): return
		_expect(sentinel == store.snapshot.capture(content), "Preparing a legacy checkpoint does not mutate live state.")
	for invalid_focus: Variant in ["missing", "wrong_type", -0.01, 1.01]:
		var bad_raw: Dictionary = legacy_raw.duplicate(true)
		if typeof(invalid_focus) == TYPE_STRING and invalid_focus == "missing":
			bad_raw.player.erase("focus")
		elif typeof(invalid_focus) == TYPE_STRING and invalid_focus == "wrong_type":
			bad_raw.player["focus"] = "0.63"
		else:
			bad_raw.player["focus"] = invalid_focus
		var invalid: Dictionary = legacy.duplicate(true)
		invalid.state = LEGACY_RELIABILITY.encode_city(values, bad_raw)
		_expect(not store.snapshot.prepare(invalid, content), "Invalid legacy Focus is rejected: " + str(invalid_focus))
		_expect(sentinel == store.snapshot.capture(content), "Rejected legacy data never mutates live state.")
	var invalid_current: Dictionary = current.duplicate(true)
	invalid_current.state = values.encode(legacy_raw)
	_expect(not store.snapshot.prepare(invalid_current, content), "Current checkpoints reject an unexpected Focus field.")
	var bad_raw: Dictionary = legacy_raw.duplicate(true)
	bad_raw.player["focus"] = 1.01
	var invalid_disk: Dictionary = legacy.duplicate(true)
	invalid_disk.state = LEGACY_RELIABILITY.encode_city(values, bad_raw)
	var invalid_bytes: String = JSON.stringify(invalid_disk, "", true, true)
	if not _write_text(CHECKPOINT_PATH, invalid_bytes):
		_fail_fast("legacy_v8_invalid_write", "Could not write isolated invalid v8 fixture.")
		return
	_expect(not store.load_checkpoint() and not store.save_checkpoint(), "Invalid legacy saves cannot be loaded or overwritten.")
	_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH) == invalid_bytes and sentinel == store.snapshot.capture(content), "Invalid save bytes and the live world are preserved.")
	var legacy_bytes: String = JSON.stringify(legacy, "", true, true)
	if not _write_text(CHECKPOINT_PATH, legacy_bytes):
		_fail_fast("legacy_v8_write", "Could not write isolated valid v8 fixture.")
		return
	if not _required_load("legacy_v8_load"): return
	if not _required_load("legacy_v8_repeat_load"): return
	_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH) == legacy_bytes, "Loading a legacy checkpoint leaves its bytes untouched.")
	_expect(is_equal_approx(player.fatigue, raw.player.fatigue) and is_equal_approx(player.hunger, raw.player.hunger), "Migration preserves both player needs.")
	if not _required_save("legacy_v8_upgrade_save"): return
	_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH + ".bak") == legacy_bytes, "The replaced legacy checkpoint remains in the normal backup.")
	var saved_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	if not saved_value is Dictionary or not saved_value.get("state") is Dictionary:
		_fail_fast("legacy_v8_decode", "Upgraded v8 file did not decode to a checkpoint document.")
		return
	var saved: Dictionary = saved_value
	var migrated_value: Variant = values.decode(saved.state)
	if not migrated_value is Dictionary or not values.error.is_empty():
		_fail_fast("legacy_v8_decode", "Upgraded v8 state did not decode: " + values.error)
		return
	var migrated: Dictionary = migrated_value
	_expect(saved.schema_version == CODEC.VERSION and not migrated.player.has("focus"), "The new checkpoint omits the retired Focus field.")
	if not _required_load("legacy_v8_upgraded_load"): return
	if not _required_load("legacy_v8_upgraded_repeat_load"): return
	if not _restore_checkpoint_files(original_files, "legacy_v8_restore"): return
	if not _required_load("legacy_v8_restore_load"): return
	_expect(store.snapshot.capture(content) == sentinel, "The original current disk and live state restore after the v8 migration scenario.")

func _test_reliability_migration(current: Dictionary, raw: Dictionary) -> void:
	var original_files: Dictionary = _capture_checkpoint_files("legacy_v9_snapshot")
	if _aborted or not original_files.get("", {}).get("present", false):
		_fail_fast("legacy_v9_snapshot", "Current checkpoint is required before the v9 migration scenario.")
		return
	var values = VALUES.new()
	var staged_raw: Dictionary = raw.duplicate(true)
	var id: String = "reliability_migration_person"
	var citizen := CitizenData.new()
	citizen.citizen_id = id
	citizen.display_name = "Saved resident"
	citizen.satisfaction = 0.43
	citizen.experience = 12.5
	staged_raw.citizens.citizens_by_id[id] = citizen
	var worker := WorkerData.new()
	worker.worker_id = id
	worker.display_name = "Saved worker"
	worker.profession_xp = 7
	worker.satisfaction = 0.61
	staged_raw.workers.workers_by_id[id] = worker
	staged_raw.needs.last_needs_results[id] = {
		"evaluated": true, "day": staged_raw.clock.current_day, "food": true,
		"clothing": false, "shelter": true, "clothing_days_left": 0,
		"satisfaction": 0.43, "satisfaction_delta": -0.05, "missing": ["Clothing"]
	}
	var legacy: Dictionary = current.duplicate(true)
	legacy.schema_version = 9
	legacy.state = LEGACY_RELIABILITY.encode_city(values, staged_raw)
	var sentinel: Dictionary = store.snapshot.capture(content)
	if not _required_prepare(legacy, "legacy_v9_prepare"): return
	var prepared: Dictionary = store.snapshot.prepared
	var result: Dictionary = prepared.needs.last_needs_results.get(id, {})
	_expect(not result.has("reliability") and not result.has("reliability_delta") and result.get("missing") == ["Clothing"], "Migration removes retired daily values and preserves the remaining record.")
	_expect(prepared.citizens.citizens_by_id[id].display_name == "Saved resident" and is_equal_approx(prepared.citizens.citizens_by_id[id].experience, 12.5) and prepared.workers.workers_by_id[id].profession_xp == 7, "Migration preserves citizen and worker fields.")
	_expect(sentinel == store.snapshot.capture(content), "Preparing v9 does not mutate live owners.")
	for invalid_kind: String in ["citizen_missing", "citizen_type", "citizen_low", "citizen_high", "worker_missing", "worker_type"]:
		var bad: Dictionary = legacy.duplicate(true)
		var target_class: String = "CitizenData" if invalid_kind.begins_with("citizen") else "WorkerData"
		var target: Dictionary = {}
		for object: Dictionary in LEGACY_RELIABILITY.city_objects(bad.state, target_class):
			if object.fields.get("citizen_id", object.fields.get("worker_id", "")) == id:
				target = object.fields
				break
		_expect(not target.is_empty(), "The invalid-object fixture finds " + target_class)
		if invalid_kind.ends_with("missing"):
			target.erase("reliability")
		elif invalid_kind.ends_with("type"):
			target.reliability = "0.5"
		elif invalid_kind.ends_with("low"):
			target.reliability = -0.01
		else:
			target.reliability = 1.01
		_expect(not store.snapshot.prepare(bad, content), "Invalid legacy object field is rejected: " + invalid_kind)
		_expect(sentinel == store.snapshot.capture(content), "Invalid legacy object leaves live owners intact: " + invalid_kind)
	for invalid_kind: String in ["reliability_missing", "reliability_type", "delta_missing", "delta_type"]:
		var bad_raw: Dictionary = staged_raw.duplicate(true)
		var ledger: Dictionary = bad_raw.needs.last_needs_results[id]
		ledger.reliability = 0.5
		ledger.reliability_delta = -0.05
		var key: String = "reliability_delta" if invalid_kind.begins_with("delta") else "reliability"
		if invalid_kind.ends_with("missing"):
			ledger.erase(key)
		else:
			ledger[key] = "invalid"
		var bad: Dictionary = legacy.duplicate(true)
		bad.state = LEGACY_RELIABILITY.encode_v10(values, bad_raw)
		LEGACY_RELIABILITY.add_city_object_fields(bad.state)
		_expect(not store.snapshot.prepare(bad, content), "Invalid legacy ledger is rejected: " + invalid_kind)
		_expect(sentinel == store.snapshot.capture(content), "Invalid legacy ledger leaves live owners intact: " + invalid_kind)
	var wrong_focus: Dictionary = staged_raw.duplicate(true)
	wrong_focus.player.focus = 0.5
	var v9_with_focus: Dictionary = legacy.duplicate(true)
	v9_with_focus.state = LEGACY_RELIABILITY.encode_city(values, wrong_focus)
	_expect(not store.snapshot.prepare(v9_with_focus, content), "Version 9 still rejects Focus, which was removed in that version.")
	var current_with_legacy_objects: Dictionary = current.duplicate(true)
	current_with_legacy_objects.state = values.encode(staged_raw)
	LEGACY_RELIABILITY.add_city_object_fields(current_with_legacy_objects.state)
	_expect(not store.snapshot.prepare(current_with_legacy_objects, content), "Current schema rejects retired object and ledger fields.")
	var legacy_ledger_raw: Dictionary = staged_raw.duplicate(true)
	legacy_ledger_raw.needs.last_needs_results[id].reliability = 0.5
	legacy_ledger_raw.needs.last_needs_results[id].reliability_delta = -0.05
	var current_with_legacy_ledger: Dictionary = current.duplicate(true)
	current_with_legacy_ledger.state = values.encode(legacy_ledger_raw)
	_expect(not store.snapshot.prepare(current_with_legacy_ledger, content), "Current schema separately rejects retired daily ledger fields.")
	var bad_disk: Dictionary = legacy.duplicate(true)
	var bad_objects: Array = LEGACY_RELIABILITY.city_objects(bad_disk.state, "WorkerData")
	for object: Dictionary in bad_objects:
		if object.fields.worker_id == id:
			object.fields.reliability = "invalid"
	var bad_bytes: String = JSON.stringify(bad_disk, "", true, true)
	if not _write_text(CHECKPOINT_PATH, bad_bytes):
		_fail_fast("legacy_v9_invalid_write", "Could not write isolated invalid v9 fixture.")
		return
	_expect(not store.load_checkpoint() and not store.save_checkpoint(), "A malformed legacy Reliability value blocks load and overwrite.")
	_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH) == bad_bytes and sentinel == store.snapshot.capture(content), "Rejected legacy bytes and live owners remain untouched.")
	var legacy_bytes: String = JSON.stringify(legacy, "", true, true)
	if not _write_text(CHECKPOINT_PATH, legacy_bytes):
		_fail_fast("legacy_v9_write", "Could not write isolated valid v9 fixture.")
		return
	if not _required_load("legacy_v9_load"): return
	if not _required_load("legacy_v9_repeat_load"): return
	_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH) == legacy_bytes, "Loading v9 leaves its bytes untouched.")
	_expect(CitizenManager.citizens_by_id[id].display_name == "Saved resident" and WorkerDatabase.workers_by_id[id].profession_xp == 7 and not CitizenNeedsManager.last_needs_results[id].has("reliability"), "Applied v9 retains the person, worker and sanitized daily record.")
	if not _required_save("legacy_v9_upgrade_save"): return
	_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH + ".bak") == legacy_bytes, "The normal backup keeps the prior v9 bytes.")
	var upgraded_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	if not upgraded_value is Dictionary or not upgraded_value.get("state") is Dictionary:
		_fail_fast("legacy_v9_decode", "Upgraded v9 file did not decode to a checkpoint document.")
		return
	var upgraded: Dictionary = upgraded_value
	var upgraded_raw_value: Variant = values.decode(upgraded.state)
	if not upgraded_raw_value is Dictionary or not values.error.is_empty():
		_fail_fast("legacy_v9_decode", "Upgraded v9 state did not decode: " + values.error)
		return
	var upgraded_raw: Dictionary = upgraded_raw_value
	var objects: Array = LEGACY_RELIABILITY.city_objects(upgraded.state, "CitizenData") + LEGACY_RELIABILITY.city_objects(upgraded.state, "WorkerData")
	var fields_absent: bool = true
	for object: Dictionary in objects:
		fields_absent = fields_absent and not object.fields.has("reliability")
	_expect(upgraded.schema_version == CODEC.VERSION and fields_absent and not upgraded_raw.needs.last_needs_results[id].has("reliability_delta"), "The upgraded checkpoint omits every retired Reliability field.")
	if not _required_load("legacy_v9_upgraded_load"): return
	if not _required_load("legacy_v9_upgraded_repeat_load"): return
	if not _restore_checkpoint_files(original_files, "legacy_v9_restore"): return
	if not _required_load("legacy_v9_restore_load"): return
	_expect(current == store.snapshot.capture(content), "The original current disk and live state restore after the v9 migration scenario.")
