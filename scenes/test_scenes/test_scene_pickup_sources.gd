extends "res://scenes/test_scenes/test_scene_city_save.gd"

const SOURCE_SCENE = preload("res://scenes/test_scenes/pickup_source_fixture.tscn")
var sources: Array[Node] = []
var rename_source: bool = false

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	await load_content()
	await _add_sources()
	store = WorkStateRuntime.get_node("CitySave")
	store.disk.path = "user://pickup_sources/checkpoint.json"
	var phase: String = "roundtrip"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--sources-phase="):
			phase = argument.trim_prefix("--sources-phase=")
	if phase != "read":
		for suffix: String in ["", ".bak", ".tmp", ".pending"]:
			DirAccess.remove_absolute(store.disk.path + suffix)
		Inventory.items.clear()
		sources[0]._pickups[1].on_player_interact(player)
		sources[1]._pickups[0].on_player_interact(player)
		await get_tree().create_timer(0.5).timeout
		_expect(store.save_checkpoint(), "Generic sources save without a hardcoded identity list: " + store.last_error)
		if phase == "write":
			_finish()
			return
	_expect(store.load_checkpoint(), "Generic sources load, including in a fresh process: " + store.last_error)
	await _settle_source_views()
	_expect(sources[0].state.available == [true, false] and sources[0].state.remaining_minutes == 120, "Configured refill source restores its missing slot and interval.")
	_expect(sources[1].state.available == [false, true] and sources[1].state.remaining_minutes == 0, "One-shot source remains depleted without a timer.")
	_expect(Inventory.items.get("stone") == 2 and Inventory.items.get("clay_lump") == 3, "Shared pickups grant configured item and quantity exactly once.")
	_expect(store.snapshot._sources.nodes().size() == 8, "Both prefab instances register independently beside six palms.")
	_expect(store.snapshot._capture_city_drops(content).is_empty(), "Generic source views never become personal city drops.")
	var saved: Dictionary = store.snapshot.capture(content)
	_expect(store.load_checkpoint(), "Repeated generic load succeeds.")
	await _settle_source_views()
	_expect(saved == store.snapshot.capture(content), "Repeated load preserves all owners and RNG.")
	TimeComponentManager.advance_minutes(119)
	_expect(sources[0].state.available == [true, false] and sources[0].state.remaining_minutes == 1, "Refill waits until the exact due minute.")
	TimeComponentManager.advance_minutes(1)
	await _settle_source_views()
	_expect(sources[0].state.available == [true, true] and sources[1].state.available == [false, true], "Only the refill-enabled source replenishes.")
	_expect(store.load_checkpoint(), "Restore before map lifecycle test.")
	var prior_states: Array = [sources[0].state, sources[1].state]
	content.queue_free()
	await get_tree().process_frame
	await load_content()
	rename_source = true
	await _add_sources()
	_expect(store.load_checkpoint(), "Explicit source ID survives an authored node rename.")
	_expect(sources[0].state == prior_states[0] and sources[1].state == prior_states[1], "Two instances of one prefab keep independent stable identities across map recreation.")
	await _settle_source_views()
	var codec = VALUES.new()
	var raw: Dictionary = codec.decode(saved.state)
	var invalid: Dictionary = saved.duplicate(true)
	var id: String = str(sources[0].state.name)
	raw.pickup_sources[id].config.quantity += 1
	invalid.state = codec.encode(raw)
	var sentinel: Dictionary = store.snapshot.capture(content)
	_expect(not store.snapshot.prepare(invalid, content), "Changed authored configuration rejects a checkpoint.")
	_expect(sentinel == store.snapshot.capture(content), "Invalid source configuration cannot partially mutate the world.")
	raw = codec.decode(saved.state)
	raw.pickup_sources[str(sources[1].state.name)].remaining_minutes = 1
	invalid.state = codec.encode(raw)
	_expect(not store.snapshot.prepare(invalid, content), "A one-shot source cannot restore an active refill timer.")
	_expect(sentinel == store.snapshot.capture(content), "Invalid one-shot timer leaves every owner untouched.")
	# v3 only knew the six palms; newly introduced source histories are unavailable.
	raw = codec.decode(saved.state)
	var old_palms: Dictionary = {}
	for key: String in raw.pickup_sources:
		if key.begins_with("DatePalm_"):
			old_palms[key] = raw.pickup_sources[key].duplicate(true)
			old_palms[key].erase("config")
	raw.erase("pickup_sources")
	raw.date_palms = old_palms
	var legacy: Dictionary = saved.duplicate(true)
	legacy.schema_version = 3
	legacy.state = codec.encode(raw)
	_expect(store.snapshot.prepare(legacy, content), "v3 accepts new authored source types through explicit migration.")
	_expect(sentinel == store.snapshot.capture(content), "Migration preparation does not reset new sources.")
	store.snapshot.apply_prepared(content, false)
	await _settle_source_views()
	for source: Node in sources:
		_expect(source.state.available == [true, true] and source.state.remaining_minutes == 0, "v3 initializes only previously unrecorded sources with fresh full stock.")
	_finish()

func _add_sources() -> void:
	sources.clear()
	for index: int in range(2):
		var source: Node = SOURCE_SCENE.instantiate()
		source.name = "RefillSource" if index == 0 else "OneShotSource"
		source.position = Vector2(-300, -300 + index * 50)
		if index == 1:
			source.persistence_id = "one-shot-test-source"
			if rename_source:
				source.name = "RenamedOneShotSource"
			source.item_id = "clay_lump"
			source.quantity = 3
			source.refill_enabled = false
		content.get_node("YSortWorld").add_child(source)
		sources.append(source)
	await _settle_source_views()

func _settle_source_views() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	for source: Node in sources:
		for slot: int in range(source.state.available.size()):
			_expect(source._pickups.has(slot) == source.state.available[slot], "Source view matches its own available slots.")

func _finish() -> void:
	print("PickupSourcesTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
