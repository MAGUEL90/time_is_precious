extends "res://scenes/test_scenes/test_scene_defense_dialogue.gd"

const CODEC = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const LEGACY_RELIABILITY = preload("res://scenes/test_scenes/legacy_reliability_fixture.gd")
const CHECKPOINT_PATH: String = "user://city_save_test/checkpoint.json"
var store: Node
var _payment_clock_before: int = -1
var _payment_clock_after: int = -1
var _payment_guard_seen: bool = false

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	await load_content()
	await get_tree().process_frame
	store = WorkStateRuntime.get_node("CitySave")
	store.disk.path = CHECKPOINT_PATH
	var mode: String = "roundtrip"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--city-save-phase="):
			mode = argument.trim_prefix("--city-save-phase=")
	if mode == "read":
		var original_bytes: String = FileAccess.get_file_as_string(CHECKPOINT_PATH)
		var read_document: Dictionary = JSON.parse_string(original_bytes)
		_expect(store.load_checkpoint(), "A fresh game process loads the disk checkpoint: " + store.last_error)
		var read_raw: Dictionary = store.snapshot.prepared.duplicate(true)
		await _assert_seed(read_raw.get("pickup_sources", {}))
		var expected: Dictionary = read_document.duplicate(true)
		if read_document.schema_version == 9:
			# The staged load already contains the current nested worksite shape.
			expected.schema_version = CODEC.VERSION
			expected.state = VALUES.new().encode(read_raw)
			for result: Dictionary in read_raw.needs.last_needs_results.values():
				_expect(not result.has("reliability") and not result.has("reliability_delta"), "A genuine v9 ledger loads without retired fields.")
			_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH) == original_bytes, "Loading a genuine v9 checkpoint preserves its exact bytes.")
		_expect(JSON.parse_string(JSON.stringify(store.snapshot.capture(content), "", true, true)) == JSON.parse_string(JSON.stringify(expected, "", true, true)), "Fresh-process restore matches every captured owner and RNG state after migration.")
		_finish()
		return
	_clean_files()
	await _seed()
	_expect(ui.find_child("SaveButton", true, false) == null and ui.find_child("LoadButton", true, false) == null, "City Hub does not expose manual checkpoint buttons.")
	var saved: bool = store.save_checkpoint()
	_expect(saved, "A checkpoint can be saved: " + store.last_error)
	if not saved:
		_finish()
		return
	await _assert_seed(VALUES.new().decode(store.snapshot.capture(content).state).pickup_sources)
	if mode == "write":
		_finish()
		return
	var before: Dictionary = store.snapshot.capture(content)
	var codec = VALUES.new()
	var saved_raw: Dictionary = codec.decode(before.state)
	_test_player_condition_migration(before, saved_raw)
	_test_reliability_migration(before, saved_raw)
	_test_wall_paid_source_migration(before, saved_raw)
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
	_expect(store.load_checkpoint(), "Manual Load restores the checkpoint: " + store.last_error)
	await _assert_seed(saved_raw.pickup_sources)
	var after: Dictionary = store.snapshot.capture(content)
	_expect(before == after, "Every captured owner round-trips exactly, without offline time or duplicated rewards.")
	_expect(store.load_checkpoint(), "A repeated Manual Load restores the same checkpoint: " + store.last_error)
	await _assert_seed(saved_raw.pickup_sources)
	_expect(before == store.snapshot.capture(content), "Repeated Load does not duplicate date inventory or pickup views.")
	await _assert_refill_boundaries(before, saved_raw)
	await _assert_future_palm_rng_sequence(saved_raw)
	_expect(store.load_checkpoint(), "Palm RNG sequence probing is rolled back by another Load: " + store.last_error)
	await _assert_seed(saved_raw.pickup_sources)
	_test_pending_wall_refund_roundtrip(before)
	await _assert_seed(saved_raw.pickup_sources)
	# Reject malformed palm ledgers through the disk boundary and prove each Load
	# leaves every live owner untouched.
	var valid_bytes: String = FileAccess.get_file_as_string(CHECKPOINT_PATH)
	for invalid_case: String in ["missing_collection", "missing_identity", "unknown_identity", "wrong_capacity", "non_bool_slot", "full_with_timer", "depleted_without_timer", "timer_too_large", "timer_float", "rng_bool", "rng_float", "rng_extra_field", "timer_negative", "missing_rng", "extra_field", "missing_config", "config_wrong_capacity", "config_extra_field"]:
		await _assert_invalid_palm_case(before, saved_raw, invalid_case)
	_write_text(CHECKPOINT_PATH, valid_bytes)
	_expect(store.load_checkpoint(), "Explicit Load accepts the restored valid checkpoint: " + store.last_error)
	await _assert_seed(saved_raw.pickup_sources)
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
	_assert_legacy_validation_only(legacy)
	var legacy_file := FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy, "", true, true))
	legacy_file.close()
	_expect(store.load_checkpoint(), "A version-1 manual city checkpoint still loads.")
	await _assert_legacy_palms_reset(legacy_rng)
	legacy = before.duplicate(true)
	legacy.schema_version = 2
	legacy_raw = saved_raw.duplicate(true)
	legacy_raw.erase("pickup_sources")
	_strip_post_v3_owner_fields(legacy_raw)
	legacy.state = LEGACY_RELIABILITY.encode_city(codec, legacy_raw)
	_strip_post_v3_worker_fields(legacy.state)
	legacy_file = FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy, "", true, true))
	legacy_file.close()
	legacy_rng = _set_palm_rng_sentinels()
	_assert_legacy_validation_only(legacy)
	_expect(store.load_checkpoint(), "A version-2 manual city checkpoint still loads.")
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
	_assert_legacy_validation_only(legacy)
	legacy_file = FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy, "", true, true))
	legacy_file.close()
	_expect(store.load_checkpoint(), "A version-3 palm checkpoint restores through the migration path.")
	await _assert_v3_palms_restored(legacy_palms, legacy_rng)
	_expect(store.save_checkpoint(), "The next explicit save writes the current location-aware version.")
	_expect(JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH)).schema_version == CODEC.VERSION, "A successful save explicitly upgrades the legacy header to the current version.")
	# A malformed document must fail before any live mutation, and block Save.
	valid_bytes = FileAccess.get_file_as_string(CHECKPOINT_PATH)
	var file := FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var sentinel: Dictionary = store.snapshot.capture(content)
	_expect(not store.load_checkpoint(), "Malformed JSON is rejected.")
	_expect(sentinel == store.snapshot.capture(content), "Invalid Load leaves the complete live world untouched.")
	_expect(not store.save_checkpoint() and FileAccess.get_file_as_string(CHECKPOINT_PATH) == "{broken", "Corrupt primary is preserved, never silently overwritten.")
	file = FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
	file.store_string(valid_bytes)
	file.close()
	_expect(store.load_checkpoint(), "Explicit Load accepts a repaired valid file.")
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
	_expect(store.save_checkpoint(), "An active raid can be checkpointed: " + store.last_error)
	var hp: int = state.wall_hp
	var elapsed: float = state._elapsed
	state.advance_attack(10.0)
	_expect(store.load_checkpoint(), "An active raid restores.")
	state.set_process(false)
	_expect(state.wall_hp == hp and state._elapsed == elapsed, "Attack HP and real-second hit cadence resume exactly.")
	state.wall_hp = 1
	state.advance_attack(3.0)
	_expect(state.phase == "looting", "The resumed raid reaches the real looting phase.")
	var satisfaction: float = CitizenNeedsManager.get_average_satisfaction()
	var city_progress: int = WorkStateRuntime.get_node("CityProgression").progress
	_expect(store.save_checkpoint(), "Looting state saves: " + store.last_error)
	var loot_before: Dictionary = state._stolen.duplicate()
	state.advance_attack(2.0)
	_expect(store.load_checkpoint(), "Looting state restores.")
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
	_clean_files()
	_finish()

func _seed() -> void:
	_set_clock_minute(7 * 1440 + 600)
	# This fixture jumps the clock directly; worksite time normally advances via
	# per-minute signals, so settle its idle ledger before capturing the world.
	content.get_node("YSortWorld/WorkerRuntime").daily.tick()
	Inventory.items.assign({"shekel": 17, "stone": 13, "wood_log": 5})
	storage.items = {"stone": 100, "wood_log": 100, "egg": 5}
	player.fatigue = 0.75
	var pickup: PickUpItem = preload("res://scenes/pickup_item/pickup_item.tscn").instantiate()
	pickup.item_id = "clay_lump"
	pickup.quantity = 4
	pickup.position = Vector2(-210, -260)
	content.get_node("YSortWorld").add_child(pickup)
	_payment_clock_before = _clock_minute()
	_payment_clock_after = -1
	_payment_guard_seen = false
	Inventory.items_changed.connect(_try_advance_clock_during_wall_payment)
	var wall_started: bool = state.request_wall_work(state.get_work_quote())
	Inventory.items_changed.disconnect(_try_advance_clock_during_wall_payment)
	_expect(wall_started, "The save fixture starts paid construction.")
	_expect(_payment_guard_seen and _payment_clock_after == _payment_clock_before,
		"A payment observer cannot advance city time while the wall ledger and Inventory debit are being published.")
	WorkStateRuntime.get_node("CityProgression").progress = 35
	await _seed_authored_palms()
	TimeComponentManager._timer = 0.375

func _assert_seed(expected_palms: Dictionary = {}) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(TimeComponentManager.current_day == 7, "A later-day checkpoint restores into a fresh day-zero session.")
	var palm_trees: Array = _authored_palm_trees()
	_expect(palm_trees.size() == 6, "The city fixture contains all six authored palm trees.")
	var palm_pickups: Array = get_tree().get_nodes_in_group("date_palm_pickups")
	_expect(palm_pickups.size() == 12, "Checkpoint restore preserves twelve palm-owned pickup views for six partially harvested trees.")
	for tree: Node in palm_trees:
		_expect(tree.state.available.count(true) == 2 and tree.state.remaining_minutes > 0,
			"Each independent palm restores two available slots and its pending refill timer: " + tree.name)
		for slot: int in range(tree.state.available.size()):
			_expect(tree._pickups.has(slot) == tree.state.available[slot], "Only available slot is projected: " + str(tree.name) + ":" + str(slot))
		_expect(tree._pickups.size() == 2, "Each palm view contains only its two available slots: " + tree.name)
		if expected_palms.has(tree.state.name):
			var expected: Dictionary = expected_palms[tree.state.name]
			_expect(tree.state.available == expected.available and tree.state.remaining_minutes == expected.remaining_minutes,
				"Each palm restores its exact slot ledger and remaining minutes: " + tree.name)
			_expect(tree.state._rng.seed == expected.rng.seed and tree.state._rng.state == expected.rng.state,
				"Each palm restores its exact RNG seed and state: " + tree.name)
	_expect(Inventory.items.get("date_cluster", 0) == 6, "Six collected date clusters remain in personal inventory across Load.")
	var drops: Array = store.snapshot._capture_city_drops(content)
	_expect(drops.size() == 1 and drops[0].quantity == 4 and drops[0].item_id == "clay_lump", "Dropped inventory items survive without duplication.")
	_expect(Inventory.items.get("shekel") == 17 and Inventory.items.get("stone") == 3 and Inventory.items.get("wood_log", 0) == 0, "Player inventory preserves the one-time wall payment across the checkpoint.")
	_expect(storage.items.get("stone") == 100 and storage.items.get("wood_log") == 100, "Wall materials are not taken from City Storage.")
	_expect(state._work_remaining == 120 and state._work_kind == "build" and state._work_paid_source == "inventory" and state.wall_hp == 0, "Unfinished wall work retains its timer, payment source, and ruined wall.")
	_expect(WorkStateRuntime.get_node("CityProgression").progress == 35 and is_equal_approx(player.fatigue, 0.75), "City progress and player conditions survive.")

func _clean_files() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		if FileAccess.file_exists(CHECKPOINT_PATH + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CHECKPOINT_PATH + suffix))

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
	_expect(store.save_checkpoint(), "A pending wall refund can be saved without losing its original payment: " + store.last_error)
	var pending_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	var pending_raw: Dictionary = VALUES.new().decode(pending_document.state)
	_expect(pending_document.schema_version == CODEC.VERSION and pending_raw.raid._refund_pending and pending_raw.raid._work_paid == {"stone": 2},
		"The current checkpoint records the pending refund and retained materials.")
	state._refund_pending = false
	state._work_kind = ""
	state._work_paid.clear()
	state._work_paid_source = ""
	_expect(store.load_checkpoint(), "A pending wall refund restores from its checkpoint: " + store.last_error)
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
	_write_text(CHECKPOINT_PATH, original_bytes)
	_expect(store.load_checkpoint(), "The original wall checkpoint restores after pending-refund coverage: " + store.last_error)

func _seed_authored_palms() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var palm_trees: Array = _authored_palm_trees()
	_expect(palm_trees.size() == 6, "The real city exposes six authored palm trees for the save fixture.")
	for index: int in range(palm_trees.size()):
		var tree: Node = palm_trees[index]
		_expect(tree._pickups.size() == 3, "Each authored palm begins with all three pickup views: " + tree.name)
		tree.state._rng.seed = 1000 + index
		var pickup: PickUpItem = tree._pickups[index % 3]
		pickup.on_player_interact(player)
	var deadline: int = Time.get_ticks_msec() + 2000
	while get_tree().get_nodes_in_group("date_palm_pickups").size() != 12 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(Inventory.items.get("date_cluster", 0) == 6, "One real pickup from each palm adds six date clusters to inventory.")
	_expect(get_tree().get_nodes_in_group("date_palm_pickups").size() == 12, "Collected palm views finish their pickup animation before the checkpoint.")

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
	_expect(store.load_checkpoint(), "Load restores palm RNG after sequence probing: " + store.last_error)
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
		"depleted_without_timer":
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
	_write_text(CHECKPOINT_PATH, JSON.stringify(invalid_document, "", true, true))
	_expect(not store.load_checkpoint(), "Load rejects invalid date palm data: " + case_name)
	_expect(baseline == store.snapshot.capture(content), "Invalid palm data leaves every live owner untouched: " + case_name)
	_write_text(CHECKPOINT_PATH, JSON.stringify(valid_document, "", true, true))

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
	_expect(get_tree().get_nodes_in_group("date_palm_pickups").size() == 18,
		"Legacy palm fallback recreates exactly eighteen pickup views.")
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
	_expect(get_tree().get_nodes_in_group("date_palm_pickups").size() == 12,
		"A v3 load preserves the six depleted palm views without duplication.")
	_expect(Inventory.items.get("date_cluster", 0) == 6, "A v3 load preserves collected dates without granting more.")

func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()

func _finish() -> void:
	print("CitySaveTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _assert_legacy_validation_only(document: Dictionary) -> void:
	var baseline: Dictionary = store.snapshot.capture(content)
	_expect(store.snapshot.prepare(document, content), "Legacy data validates before applying fallback.")
	_expect(store.snapshot.capture(content) == baseline, "Legacy validation alone leaves all owners, slots, timers and RNG untouched.")

func _test_wall_paid_source_migration(current: Dictionary, raw: Dictionary) -> void:
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
	_expect(store.snapshot.prepare(legacy, content), "A strict v15 save stages the legacy City Storage payment source.")
	_expect(store.snapshot.prepared.raid._work_paid_source == "city_storage" and store.snapshot.capture(content) == sentinel,
		"Legacy source migration is in-memory and does not change the live project.")
	var current_bytes: String = FileAccess.get_file_as_string(CHECKPOINT_PATH)
	var legacy_bytes: String = JSON.stringify(legacy, "", true, true)
	_write_text(CHECKPOINT_PATH, legacy_bytes)
	_expect(store.load_checkpoint(), "A v15 project loads with its original City Storage payment source: " + store.last_error)
	_expect(state._work_paid_source == "city_storage" and state._work_kind == "repair" and FileAccess.get_file_as_string(CHECKPOINT_PATH) == legacy_bytes,
		"Loading v15 stages City Storage as the refund source without rewriting saved bytes.")
	_expect(store.save_checkpoint(), "Saving the migrated legacy project writes the current schema: " + store.last_error)
	_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH + ".bak") == legacy_bytes,
		"The explicit save preserves the original v15 bytes in the normal backup.")
	var upgraded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	var upgraded_raw: Dictionary = values.decode(upgraded.state)
	_expect(upgraded.schema_version == CODEC.VERSION and upgraded_raw.raid._work_kind == "repair" and upgraded_raw.raid._work_paid_source == "city_storage",
		"The first explicit v16 save retains the legacy repair's City Storage refund source.")
	var inventory_before_legacy_refund: Dictionary = Inventory.items.duplicate(true)
	state._refund_interrupted_repair()
	_expect(storage.items.get("stone", 0) == 100 and Inventory.items == inventory_before_legacy_refund and state._work_kind.is_empty(),
		"The migrated repair returns its paid materials to City Storage without touching Inventory.")
	state._refund_interrupted_repair()
	_expect(storage.items.get("stone", 0) == 100, "A migrated City Storage refund cannot be duplicated.")
	_write_text(CHECKPOINT_PATH, current_bytes)
	_expect(store.load_checkpoint() and store.snapshot.capture(content) == sentinel,
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
	_write_text(CHECKPOINT_PATH, JSON.stringify(short_timers, "", true, true))
	_expect(store.load_checkpoint(), "A checkpoint with distinct near-due palm timers loads.")
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	TimeComponentManager.advance_minutes(3)
	for elapsed: int in range(3, 10):
		if elapsed > 3:
			TimeComponentManager.advance_minutes(1)
		await get_tree().process_frame
		await get_tree().process_frame
		var total_views: int = 0
		for tree: Node in _authored_palm_trees():
			var saved: Dictionary = staged.pickup_sources[str(tree.state.name)]
			var remaining: int = maxi(0, saved.remaining_minutes - elapsed)
			var slots: Array = [true, true, true] if remaining == 0 else saved.available
			_expect(tree.state.remaining_minutes == remaining and tree.state.available == slots, "Only the due palm refills at the exact restored minute: " + str(tree.name))
			for slot: int in range(slots.size()):
				_expect(tree._pickups.has(slot) == slots[slot], "Refill projects exactly the available slots.")
			total_views += slots.count(true)
			_expect(tree.state._rng.state == saved.rng.state, "Refill consumes no random draw.")
		_expect(get_tree().get_nodes_in_group("date_palm_pickups").size() == total_views, "Refill never duplicates pickup views.")
		_expect(Inventory.items == inventory_before, "Refill never grants Inventory goods.")
	var full_palms: Dictionary = store.snapshot._sources.capture()
	_expect(store.save_checkpoint() and store.load_checkpoint(), "Fully stocked palms also round-trip through disk.")
	_expect(store.snapshot._sources.capture() == full_palms, "Full palm stock preserves the next RNG draw across Load.")
	_write_text(CHECKPOINT_PATH, JSON.stringify(document, "", true, true))
	_expect(store.load_checkpoint(), "The original checkpoint restores after the countdown test.")
	await _assert_seed(raw.pickup_sources)

func _strip_post_v3_owner_fields(raw: Dictionary) -> void:
	# Pseudo-legacy documents omit owner fields absent in those schemas.
	LEGACY_RELIABILITY.strip_v16_owners(raw)
	raw.player["focus"] = 0.75
	raw.raid.erase("notification_seen_keys")
	for plot: Dictionary in raw.plots.values():
		plot.erase("payroll_work_remainder")

func _test_player_condition_migration(current: Dictionary, raw: Dictionary) -> void:
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
		_expect(store.snapshot.prepare(boundary, content), "Legacy Focus boundary remains valid: " + str(allowed_focus))
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
	_write_text(CHECKPOINT_PATH, invalid_bytes)
	_expect(not store.load_checkpoint() and not store.save_checkpoint(), "Invalid legacy saves cannot be loaded or overwritten.")
	_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH) == invalid_bytes and sentinel == store.snapshot.capture(content), "Invalid save bytes and the live world are preserved.")
	var legacy_bytes: String = JSON.stringify(legacy, "", true, true)
	_write_text(CHECKPOINT_PATH, legacy_bytes)
	_expect(store.load_checkpoint() and store.load_checkpoint(), "A valid v8 checkpoint loads repeatedly.")
	_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH) == legacy_bytes, "Loading a legacy checkpoint leaves its bytes untouched.")
	_expect(is_equal_approx(player.fatigue, raw.player.fatigue) and is_equal_approx(player.hunger, raw.player.hunger), "Migration preserves both player needs.")
	_expect(store.save_checkpoint(), "A later save writes the new checkpoint.")
	_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH + ".bak") == legacy_bytes, "The replaced legacy checkpoint remains in the normal backup.")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	var migrated: Dictionary = values.decode(saved.state)
	_expect(saved.schema_version == CODEC.VERSION and not migrated.player.has("focus"), "The new checkpoint omits the retired Focus field.")
	_expect(store.load_checkpoint() and store.load_checkpoint(), "The new checkpoint also loads repeatedly.")

func _test_reliability_migration(current: Dictionary, raw: Dictionary) -> void:
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
	_expect(store.snapshot.prepare(legacy, content), "A v9 checkpoint with retired Reliability validates: " + store.snapshot.error)
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
	_write_text(CHECKPOINT_PATH, bad_bytes)
	_expect(not store.load_checkpoint() and not store.save_checkpoint(), "A malformed legacy Reliability value blocks load and overwrite.")
	_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH) == bad_bytes and sentinel == store.snapshot.capture(content), "Rejected legacy bytes and live owners remain untouched.")
	var legacy_bytes: String = JSON.stringify(legacy, "", true, true)
	_write_text(CHECKPOINT_PATH, legacy_bytes)
	_expect(store.load_checkpoint() and store.load_checkpoint(), "A v9 Reliability checkpoint loads repeatedly through the disk boundary.")
	_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH) == legacy_bytes, "Loading v9 leaves its bytes untouched.")
	_expect(CitizenManager.citizens_by_id[id].display_name == "Saved resident" and WorkerDatabase.workers_by_id[id].profession_xp == 7 and not CitizenNeedsManager.last_needs_results[id].has("reliability"), "Applied v9 retains the person, worker and sanitized daily record.")
	_expect(store.save_checkpoint(), "The next explicit save upgrades v9.")
	_expect(FileAccess.get_file_as_string(CHECKPOINT_PATH + ".bak") == legacy_bytes, "The normal backup keeps the prior v9 bytes.")
	var upgraded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	var upgraded_raw: Dictionary = values.decode(upgraded.state)
	var objects: Array = LEGACY_RELIABILITY.city_objects(upgraded.state, "CitizenData") + LEGACY_RELIABILITY.city_objects(upgraded.state, "WorkerData")
	var fields_absent: bool = true
	for object: Dictionary in objects:
		fields_absent = fields_absent and not object.fields.has("reliability")
	_expect(upgraded.schema_version == CODEC.VERSION and fields_absent and not upgraded_raw.needs.last_needs_results[id].has("reliability_delta"), "The upgraded checkpoint omits every retired Reliability field.")
	_expect(store.load_checkpoint() and store.load_checkpoint(), "The upgraded checkpoint loads repeatedly.")
	_write_text(CHECKPOINT_PATH, JSON.stringify(current, "", true, true))
	_expect(store.load_checkpoint() and current == store.snapshot.capture(content), "The original checkpoint restores after the migration test.")
