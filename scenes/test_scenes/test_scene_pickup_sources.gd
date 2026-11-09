extends "res://scenes/test_scenes/test_scene_city_save.gd"

const SOURCE_SCENE = preload("res://scenes/test_scenes/pickup_source_fixture.tscn")
const WORKSITE_SCHEMA = preload("res://scenes/new_scenes/save_game/city_save_worksites.gd")
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
	var current_schema_input: Dictionary = saved.duplicate(true)
	var raw: Dictionary = codec.decode(saved.state)
	var current_source_dictionary: Dictionary = raw.pickup_sources.duplicate(true)
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
	_strip_post_v3_owner_fields(raw)
	# The pre-v17 v3 schema predates these per-person timing ledgers. Keep this
	# historical fixture accurate instead of weakening the production validator.
	raw.needs.erase("food_coverage_until")
	raw.needs.erase("satisfaction_last_minute")
	# Keep only the registry that the existing v3 adapter recognizes. The
	# current map contains newer resource sites that were absent from v3.
	for site_id_value: Variant in raw.worksites.sites.keys():
		if not WORKSITE_SCHEMA.LEGACY_SITE_IDS.has(str(site_id_value)):
			raw.worksites.sites.erase(site_id_value)
	_expect(old_palms.size() == 6 and current_source_dictionary.size() == 8,
		"The v3 fixture keeps the original six palm records while current input retains every source record.")
	_expect(not raw.needs.has("food_coverage_until") and not raw.needs.has("satisfaction_last_minute"),
		"The v3 fixture omits both timing ledgers introduced after its schema.")
	_expect(raw.worksites.sites.size() == WORKSITE_SCHEMA.LEGACY_SITE_IDS.size(),
		"The v3 fixture omits worksite sites added after its supported legacy registry.")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.schema_version = 3
	# v3 predates the retired Reliability fields as well as newer pickup
	# sources. Use the same genuine legacy encoding as CitySaveTest.
	legacy.state = LEGACY_RELIABILITY.encode_city(codec, raw)
	_strip_post_v3_worker_fields(legacy.state)
	_expect(current_schema_input == saved and codec.decode(saved.state).pickup_sources == current_source_dictionary,
		"Building the v3 fixture leaves the current schema input and source dictionary intact.")
	var legacy_values = VALUES.new()
	legacy_values.allow_legacy_worker_fields = true
	legacy_values.allow_legacy_contract_fields = true
	legacy_values.allow_legacy_approach_field = true
	legacy_values.allow_legacy_reliability_field = true
	legacy_values.allow_legacy_resignation_field = true
	var encoded_legacy_raw: Variant = legacy_values.decode(legacy.state)
	_expect(legacy_values.error.is_empty() and encoded_legacy_raw is Dictionary
		and not encoded_legacy_raw.needs.has("food_coverage_until")
		and not encoded_legacy_raw.needs.has("satisfaction_last_minute"),
		"The encoded v3 fixture contains no post-v3 timing ledgers.")
	var legacy_input_bytes: String = JSON.stringify(legacy, "", true, true)
	for timing_field: String in ["food_coverage_until", "satisfaction_last_minute"]:
		var malformed: Dictionary = legacy.duplicate(true)
		var malformed_raw: Dictionary = raw.duplicate(true)
		malformed.state = LEGACY_RELIABILITY.encode_city(codec, malformed_raw)
		_strip_post_v3_worker_fields(malformed.state)
		var malformed_needs: Variant = _encoded_value_for_key(malformed.state, "needs")
		_expect(_append_encoded_entry(malformed_needs, timing_field, codec.encode({})),
			"The %s corruption is injected after constructing the historical v3 payload." % timing_field)
		var decoded_malformed: Variant = legacy_values.decode(malformed.state)
		_expect(legacy_values.error.is_empty() and decoded_malformed is Dictionary
			and decoded_malformed.needs.get(timing_field) == {},
			"The malformed v3 payload actually retains %s after historical construction." % timing_field)
		var malformed_input_bytes: String = JSON.stringify(malformed, "", true, true)
		_expect(not store.snapshot.prepare(malformed, content), "v3 rejects a legacy fixture containing " + timing_field + ".")
		_expect(store.snapshot.error == "Invalid legacy needs timing ledger.", "Malformed v3 timing field reports the strict ledger rejection.")
		_expect(sentinel == store.snapshot.capture(content), "Malformed v3 timing field cannot mutate current owners.")
		_expect(JSON.stringify(malformed, "", true, true) == malformed_input_bytes,
			"Preparing malformed %s leaves the original input unchanged." % timing_field)
	_expect(JSON.stringify(legacy, "", true, true) == legacy_input_bytes,
		"The timing corruption probes leave the pristine historical v3 fixture unchanged.")
	var prepared: bool = store.snapshot.prepare(legacy, content)
	_expect(prepared, "v3 accepts new authored source types through explicit migration: " + store.snapshot.error)
	_expect(sentinel == store.snapshot.capture(content), "Migration preparation does not reset new sources.")
	_expect(JSON.stringify(legacy, "", true, true) == legacy_input_bytes,
		"Preparing the v3 checkpoint leaves its original input document unchanged.")
	if not prepared:
		_finish()
		return
	var staged: Dictionary = store.snapshot.prepared.duplicate(true)
	var runtime_worksite: Node = content.get_node("YSortWorld/WorkerRuntime")
	for site_id: String in WORKSITE_SCHEMA.LEGACY_SITE_IDS:
		_expect(int(staged.worksites.sites[site_id].stock) == int(encoded_legacy_raw.worksites.sites[site_id].stock),
			"v3 migration preserves old worksite stock for " + site_id + ".")
	for owner_field: String in ["clock", "inventory", "city_storage", "rng", "city_drops"]:
		_expect(staged[owner_field] == encoded_legacy_raw[owner_field],
			"v3 worksite migration preserves unrelated owner " + owner_field + ".")
	for site_id: String in WORKSITE_SCHEMA.NEW_SITE_IDS:
		if runtime_worksite.sites.has(StringName(site_id)):
			var capacity: int = int(runtime_worksite.sites[StringName(site_id)].get("deposit_capacity"))
			var initialized: Dictionary = staged.worksites.sites[site_id]
			_expect(capacity > 0 and int(initialized.stock) == capacity,
				"v3 initializes authored site " + site_id + " from its configured capacity.")
			_expect(initialized.size() == 1 and not initialized.has("deposit_capacity") and not initialized.has("offset"),
				"v3 initializes only stock for newly authored site " + site_id + ".")
		else:
			_expect(not staged.worksites.sites.has(site_id), "v3 does not invent absent site " + site_id + ".")
	store.snapshot.apply_prepared(content, false)
	await _settle_source_views()
	for site_id: String in WORKSITE_SCHEMA.LEGACY_SITE_IDS:
		_expect(int(runtime_worksite.sites[StringName(site_id)].stock) == int(encoded_legacy_raw.worksites.sites[site_id].stock),
			"Applying v3 preserves old runtime stock for " + site_id + ".")
	for site_id: String in ["WoodSiteD", "WoodSiteE"]:
		_expect(int(runtime_worksite.sites[StringName(site_id)].stock) == int(runtime_worksite.sites[StringName(site_id)].get("deposit_capacity")),
			"Applying v3 initializes " + site_id + " from its configured capacity.")
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

func _encoded_value_for_key(payload: Variant, key: String) -> Variant:
	if not payload is Dictionary or payload.get("$type") != "dictionary" or not payload.get("entries") is Array:
		return null
	for entry: Variant in payload.entries:
		if entry is Array and entry.size() == 2 and entry[0] == key:
			return entry[1]
	return null

func _append_encoded_entry(payload: Variant, key: String, encoded_value: Variant) -> bool:
	if not payload is Dictionary or payload.get("$type") != "dictionary" or not payload.get("entries") is Array:
		return false
	payload.entries.append([key, encoded_value])
	return true
