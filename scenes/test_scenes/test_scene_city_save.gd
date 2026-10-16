extends "res://scenes/test_scenes/test_scene_defense_dialogue.gd"

const CODEC = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const CHECKPOINT_PATH: String = "user://city_save_test/checkpoint.json"
var store: Node

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
		_expect(store.load_checkpoint(), "A fresh game process loads the disk checkpoint: " + store.last_error)
		var read_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
		var read_raw: Dictionary = VALUES.new().decode(read_document.state)
		await _assert_seed(read_raw.get("date_palms", {}))
		_expect(JSON.parse_string(JSON.stringify(store.snapshot.capture(content), "", true, true)) == JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH)), "Fresh-process restore matches every captured owner and RNG state.")
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
	await _assert_seed(VALUES.new().decode(store.snapshot.capture(content).state).date_palms)
	if mode == "write":
		_finish()
		return
	var before: Dictionary = store.snapshot.capture(content)
	var codec = VALUES.new()
	var saved_raw: Dictionary = codec.decode(before.state)
	_expect(saved_raw.date_palms is Dictionary and saved_raw.date_palms.size() == 6,
		"The version-3 snapshot records exactly the six authored palm identities.")
	_expect(is_equal_approx(saved_raw.clock._timer, 0.375), "The fractional clock tick is captured alongside pending palm timers.")
	_assert_saved_palm_shape(saved_raw.date_palms)
	Inventory.items.clear()
	storage.items.clear()
	state._work_remaining = 1
	state._work_paid.clear()
	WorkStateRuntime.get_node("CityProgression").progress = 0
	player.global_position += Vector2(30, 20)
	player.focus = 0.1
	_expect(store.load_checkpoint(), "Manual Load restores the checkpoint: " + store.last_error)
	await _assert_seed(saved_raw.date_palms)
	var after: Dictionary = store.snapshot.capture(content)
	_expect(before == after, "Every captured owner round-trips exactly, without offline time or duplicated rewards.")
	_expect(store.load_checkpoint(), "A repeated Manual Load restores the same checkpoint: " + store.last_error)
	await _assert_seed(saved_raw.date_palms)
	_expect(before == store.snapshot.capture(content), "Repeated Load does not duplicate date inventory or pickup views.")
	await _assert_refill_boundaries(before, saved_raw)
	await _assert_future_palm_rng_sequence(saved_raw)
	_expect(store.load_checkpoint(), "Palm RNG sequence probing is rolled back by another Load: " + store.last_error)
	await _assert_seed(saved_raw.date_palms)
	# Reject malformed palm ledgers through the disk boundary and prove each Load
	# leaves every live owner untouched.
	var valid_bytes: String = FileAccess.get_file_as_string(CHECKPOINT_PATH)
	for invalid_case: String in ["missing_collection", "missing_identity", "unknown_identity", "wrong_capacity", "non_bool_slot", "full_with_timer", "depleted_without_timer", "timer_too_large", "timer_float", "rng_bool", "rng_float", "rng_extra_field", "timer_negative", "missing_rng", "extra_field"]:
		await _assert_invalid_palm_case(before, saved_raw, invalid_case)
	_write_text(CHECKPOINT_PATH, valid_bytes)
	_expect(store.load_checkpoint(), "Explicit Load accepts the restored valid checkpoint: " + store.last_error)
	await _assert_seed(saved_raw.date_palms)
	# Legacy v1 and v2 files lack palm data. Applying either version restores
	# every authored tree to full stock, clears its timer and starts a fresh RNG.
	var legacy_rng: Dictionary = _set_palm_rng_sentinels()
	var legacy: Dictionary = before.duplicate(true)
	legacy.schema_version = 1
	legacy.erase("location")
	var legacy_raw: Dictionary = saved_raw.duplicate(true)
	legacy_raw.erase("date_palms")
	legacy.state = codec.encode(legacy_raw)
	_assert_legacy_validation_only(legacy)
	var legacy_file := FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy, "", true, true))
	legacy_file.close()
	_expect(store.load_checkpoint(), "A version-1 manual city checkpoint still loads.")
	await _assert_legacy_palms_reset(legacy_rng)
	legacy = before.duplicate(true)
	legacy.schema_version = 2
	legacy_raw = saved_raw.duplicate(true)
	legacy_raw.erase("date_palms")
	legacy.state = codec.encode(legacy_raw)
	legacy_file = FileAccess.open(CHECKPOINT_PATH, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy, "", true, true))
	legacy_file.close()
	legacy_rng = _set_palm_rng_sentinels()
	_assert_legacy_validation_only(legacy)
	_expect(store.load_checkpoint(), "A version-2 manual city checkpoint still loads.")
	await _assert_legacy_palms_reset(legacy_rng)
	_expect(store.save_checkpoint(), "The next explicit save writes the current location-aware version.")
	_expect(JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH)).schema_version == 3, "A successful save explicitly upgrades the legacy header.")
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
	_expect(state.wall_hp == 50 and state._attack_at > _clock_minute(), "Restored construction finishes once and starts a journey.")
	var arrival: int = state._attack_at
	_set_clock_minute(arrival)
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
	Inventory.items.assign({"shekel": 17, "stone": 3})
	storage.items = {"stone": 100, "wood_log": 100, "egg": 5}
	player.focus = 0.75
	var pickup: PickUpItem = preload("res://scenes/pickup_item/pickup_item.tscn").instantiate()
	pickup.item_id = "clay_lump"
	pickup.quantity = 4
	pickup.position = Vector2(-210, -260)
	content.get_node("YSortWorld").add_child(pickup)
	_expect(state.request_wall_work(state.get_work_quote()), "The save fixture starts paid construction.")
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
	_expect(Inventory.items.get("shekel") == 17 and Inventory.items.get("stone") == 3, "Player inventory survives the checkpoint.")
	_expect(storage.items.get("stone") == 90 and storage.items.get("wood_log") == 95, "Materials already paid for construction remain paid exactly once.")
	_expect(state._work_remaining == 120 and state._work_kind == "build" and state.wall_hp == 0, "Unfinished wall work retains its timer and ruined wall.")
	_expect(WorkStateRuntime.get_node("CityProgression").progress == 35 and player.focus == 0.75, "City progress and player conditions survive.")

func _clean_files() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		if FileAccess.file_exists(CHECKPOINT_PATH + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CHECKPOINT_PATH + suffix))

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

func _assert_saved_palm_shape(palms: Dictionary) -> void:
	var expected_ids: Dictionary = {}
	for tree: Node in _authored_palm_trees():
		expected_ids[tree.state.name] = true
	_expect(palms.size() == expected_ids.size(), "Palm save has the exact authored identity count.")
	for identity: String in expected_ids:
		_expect(palms.has(identity), "Palm save includes the authored runtime identity " + identity)
		if not palms.has(identity):
			continue
		var value: Dictionary = palms[identity]
		_expect(value.size() == 3 and value.available is Array and value.available.size() == 3,
			"Palm save uses the exact authored capacity for " + identity)
		_expect(value.available.count(false) == 1 and value.available.count(true) == 2,
			"Palm save records exactly one harvested slot for " + identity)
		_expect(typeof(value.remaining_minutes) == TYPE_INT and value.remaining_minutes >= 1 and value.remaining_minutes <= 18 * TimeComponentManager.minute_per_hour,
			"Palm save records a bounded integer refill timer for " + identity)
		_expect(value.rng is Dictionary and value.rng.size() == 2 and typeof(value.rng.get("seed")) == TYPE_INT and typeof(value.rng.get("state")) == TYPE_INT,
			"Palm save records exact integer RNG seed and state for " + identity)

func _assert_future_palm_rng_sequence(saved_raw: Dictionary) -> void:
	var expected_by_id: Dictionary = {}
	for identity: String in saved_raw.date_palms:
		var saved_rng: Dictionary = saved_raw.date_palms[identity].rng
		var expected_rng := RandomNumberGenerator.new()
		expected_rng.seed = saved_rng.seed
		expected_rng.state = saved_rng.state
		expected_by_id[identity] = [
			expected_rng.randi_range(1, 18) * TimeComponentManager.minute_per_hour,
			expected_rng.randi_range(1, 18) * TimeComponentManager.minute_per_hour
		]
	for tree: Node in _authored_palm_trees():
		var state_node: Node = tree.state
		var actual: Array = []
		for slot: int in range(2):
			state_node.available.fill(true)
			state_node.remaining_minutes = 0
			state_node.collect(slot)
			actual.append(state_node.remaining_minutes)
		_expect(actual == expected_by_id[state_node.name], "Palm RNG resumes its exact future refill sequence: " + tree.name)
	_expect(store.load_checkpoint(), "Load restores palm RNG after sequence probing: " + store.last_error)
	await _assert_seed(saved_raw.date_palms)

func _assert_invalid_palm_case(valid_document: Dictionary, valid_raw: Dictionary, case_name: String) -> void:
	var invalid_raw: Dictionary = valid_raw.duplicate(true)
	var identity: String = str(invalid_raw.date_palms.keys()[0])
	match case_name:
		"missing_collection":
			invalid_raw.erase("date_palms")
		"missing_identity":
			invalid_raw.date_palms.erase(identity)
		"unknown_identity":
			invalid_raw.date_palms["DatePalm_NotAnAuthoredTree"] = invalid_raw.date_palms[identity].duplicate(true)
			invalid_raw.date_palms.erase(identity)
		"wrong_capacity":
			invalid_raw.date_palms[identity].available.pop_back()
		"non_bool_slot":
			invalid_raw.date_palms[identity].available[0] = 1
		"full_with_timer":
			invalid_raw.date_palms[identity].available.fill(true)
		"depleted_without_timer":
			invalid_raw.date_palms[identity].remaining_minutes = 0
		"timer_too_large":
			invalid_raw.date_palms[identity].remaining_minutes = 18 * TimeComponentManager.minute_per_hour + 1
		"timer_negative":
			invalid_raw.date_palms[identity].remaining_minutes = -1
		"missing_rng":
			invalid_raw.date_palms[identity].erase("rng")
		"extra_field":
			invalid_raw.date_palms[identity]["extra"] = true
		"timer_float":
			invalid_raw.date_palms[identity].remaining_minutes = 60.0
		"rng_bool":
			invalid_raw.date_palms[identity].rng.seed = true
		"rng_float":
			invalid_raw.date_palms[identity].rng.state = 1.0
		"rng_extra_field":
			invalid_raw.date_palms[identity].rng["extra"] = 1
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
	for index: int in range(_authored_palm_trees().size()):
		var tree: Node = _authored_palm_trees()[index]
		tree.state._rng.seed = 900000 + index
		tree.state._rng.state = 800000 + index
		sentinel_by_id[tree.state.name] = {"seed": tree.state._rng.seed, "state": tree.state._rng.state}
	return sentinel_by_id

func _assert_legacy_palms_reset(sentinels: Dictionary) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	for tree: Node in _authored_palm_trees():
		_expect(tree.state.available.count(true) == 3 and tree.state.remaining_minutes == 0,
			"A legacy checkpoint explicitly restores full palm stock and clears its timer: " + tree.name)
		var sentinel: Dictionary = sentinels[tree.state.name]
		_expect(tree.state._rng.seed != sentinel.seed or tree.state._rng.state != sentinel.state,
			"A legacy checkpoint starts a fresh palm RNG: " + tree.name)
	_expect(get_tree().get_nodes_in_group("date_palm_pickups").size() == 18,
		"Legacy palm fallback recreates exactly eighteen pickup views.")
	_expect(Inventory.items.get("date_cluster", 0) == 6, "Legacy palm fallback preserves collected dates without granting more.")

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

func _assert_refill_boundaries(document: Dictionary, raw: Dictionary) -> void:
	var staged: Dictionary = raw.duplicate(true)
	var index: int = 0
	for id: String in staged.date_palms:
		staged.date_palms[id].remaining_minutes = 4 + index
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
			var saved: Dictionary = staged.date_palms[str(tree.state.name)]
			var remaining: int = maxi(0, saved.remaining_minutes - elapsed)
			var slots: Array = [true, true, true] if remaining == 0 else saved.available
			_expect(tree.state.remaining_minutes == remaining and tree.state.available == slots, "Only the due palm refills at the exact restored minute: " + str(tree.name))
			for slot: int in range(slots.size()):
				_expect(tree._pickups.has(slot) == slots[slot], "Refill projects exactly the available slots.")
			total_views += slots.count(true)
			_expect(tree.state._rng.state == saved.rng.state, "Refill consumes no random draw.")
		_expect(get_tree().get_nodes_in_group("date_palm_pickups").size() == total_views, "Refill never duplicates pickup views.")
		_expect(Inventory.items == inventory_before, "Refill never grants Inventory goods.")
	var full_palms: Dictionary = store.snapshot._palms.capture()
	_expect(store.save_checkpoint() and store.load_checkpoint(), "Fully stocked palms also round-trip through disk.")
	_expect(store.snapshot._palms.capture() == full_palms, "Full palm stock preserves the next RNG draw across Load.")
	_write_text(CHECKPOINT_PATH, JSON.stringify(document, "", true, true))
	_expect(store.load_checkpoint(), "The original checkpoint restores after the countdown test.")
	await _assert_seed(raw.date_palms)
