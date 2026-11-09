extends "res://scenes/test_scenes/test_scene_defense_dialogue.gd"

const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const WORKSITE_SCHEMA = preload("res://scenes/new_scenes/save_game/city_save_worksites.gd")
const LEGACY_FIXTURE = preload("res://scenes/test_scenes/legacy_reliability_fixture.gd")

var store: Node


func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	await load_content()
	await get_tree().process_frame
	store = WorkStateRuntime.get_node("CitySave")

	var source_document: Dictionary = store.snapshot.capture(content)
	var codec = VALUES.new()
	var source_raw: Variant = codec.decode(source_document.state)
	_expect(codec.error.is_empty() and source_raw is Dictionary, "The current control checkpoint decodes.")
	if not source_raw is Dictionary:
		await _finish_fixture_test()
		return
	var raw: Dictionary = source_raw
	var source_encoding: Variant = codec.encode(raw)
	var source_document_before: Dictionary = source_document.duplicate(true)
	var stripped: Dictionary = raw.duplicate(true)
	LEGACY_FIXTURE.strip_v16_owners(stripped)
	_expect(not stripped.needs.has("food_coverage_until") and not stripped.needs.has("satisfaction_last_minute"),
		"The legacy owner helper removes both timing ledgers introduced after outer schema v16.")
	_expect(raw.needs.has("food_coverage_until") and raw.needs.has("satisfaction_last_minute"),
		"Stripping a historical fixture leaves the current source raw state untouched.")

	var v10_state: Variant = LEGACY_FIXTURE.encode_v10(codec, raw)
	var v11_state: Variant = LEGACY_FIXTURE.encode_v11(codec, raw)
	_expect(codec.error.is_empty() and v10_state is Dictionary and v11_state is Dictionary,
		"The versioned historical payloads encode without modifying their caller input.")
	_expect(codec.encode(raw) == source_encoding and source_document == source_document_before,
		"Fixture construction preserves the caller raw state and checkpoint document.")
	if not v10_state is Dictionary or not v11_state is Dictionary:
		await _finish_fixture_test()
		return

	var v10_inspector = VALUES.new()
	v10_inspector.allow_legacy_resignation_field = true
	var v10_raw: Variant = v10_inspector.decode(v10_state)
	var v11_inspector = VALUES.new()
	var v11_raw: Variant = v11_inspector.decode(v11_state)
	_expect(v10_inspector.error.is_empty() and v10_raw is Dictionary, "The v10 payload retains a readable historical value shape.")
	_expect(v11_inspector.error.is_empty() and v11_raw is Dictionary, "The v11 payload retains a readable historical value shape.")
	if not v10_raw is Dictionary or not v11_raw is Dictionary:
		await _finish_fixture_test()
		return
	_assert_historical_shape(v10_raw, 1, "v10")
	_assert_historical_shape(v11_raw, 2, "v11")

	var sentinel: Dictionary = store.snapshot.capture(content)
	var v10_document: Dictionary = _legacy_document(source_document, 10, v10_state)
	var v11_document: Dictionary = _legacy_document(source_document, 11, v11_state)
	var v10_prepared: bool = store.snapshot.prepare(v10_document, content)
	_expect(v10_prepared, "A correctly shaped v10 fixture prepares: " + store.snapshot.error)
	_expect(store.snapshot.capture(content) == sentinel, "Preparing the v10 fixture leaves live owners unchanged.")
	var v11_prepared: bool = store.snapshot.prepare(v11_document, content)
	_expect(v11_prepared, "A correctly shaped v11 fixture prepares: " + store.snapshot.error)
	_expect(store.snapshot.capture(content) == sentinel, "Preparing the v11 fixture leaves live owners unchanged.")

	var malformed_timing: Dictionary = _legacy_document(source_document, 11, v11_state.duplicate(true))
	var needs_payload: Variant = _encoded_value_for_key(malformed_timing.state, "needs")
	var empty_dictionary: Variant = codec.encode({})
	_expect(_append_encoded_entry(needs_payload, "food_coverage_until", empty_dictionary),
		"The negative v11 file injects a well-formed post-v16 timing ledger after historical construction.")
	var timing_bytes: String = JSON.stringify(malformed_timing, "", true, true)
	_expect(not store.snapshot.prepare(malformed_timing, content),
		"A pre-v17 checkpoint with an injected timing ledger is rejected.")
	_expect(store.snapshot.error == "Invalid legacy needs timing ledger.", "The timing corruption reaches the strict legacy validator.")
	_expect(store.snapshot.capture(content) == sentinel, "Rejected timing corruption leaves live owners unchanged.")
	_expect(JSON.stringify(malformed_timing, "", true, true) == timing_bytes,
		"Preparing malformed timing data does not sanitize or mutate the input file payload.")

	var malformed_site: Dictionary = _legacy_document(source_document, 11, v11_state.duplicate(true))
	var worksites_payload: Variant = _encoded_value_for_key(malformed_site.state, "worksites")
	var sites_payload: Variant = _encoded_value_for_key(worksites_payload, "sites")
	var site_record: Variant = codec.encode({"stock": 1})
	_expect(_append_encoded_entry(sites_payload, "WoodSiteD", site_record),
		"The negative v11 file injects a new site outside the authoritative legacy registry.")
	var site_bytes: String = JSON.stringify(malformed_site, "", true, true)
	_expect(not store.snapshot.prepare(malformed_site, content), "A pre-v6 worksite payload with a foreign site is rejected.")
	_expect(store.snapshot.error == "Legacy worksite registry differs from the saved city.",
		"The foreign site is rejected by the strict historical registry check.")
	_expect(store.snapshot.capture(content) == sentinel, "Rejected foreign-site data leaves live owners unchanged.")
	_expect(JSON.stringify(malformed_site, "", true, true) == site_bytes,
		"Preparing foreign-site data does not sanitize or mutate the input file payload.")

	await _finish_fixture_test()


func _assert_historical_shape(raw: Dictionary, nested_version: int, label: String) -> void:
	var sites: Variant = raw.get("worksites", {}).get("sites")
	var shape_ok: bool = sites is Dictionary and sites.size() == WORKSITE_SCHEMA.LEGACY_SITE_IDS.size()
	if sites is Dictionary:
		for site_id: String in WORKSITE_SCHEMA.LEGACY_SITE_IDS:
			shape_ok = shape_ok and sites.has(site_id)
		for site_id_value: Variant in sites:
			shape_ok = shape_ok and WORKSITE_SCHEMA.LEGACY_SITE_IDS.has(str(site_id_value))
			var record: Variant = sites[site_id_value]
			shape_ok = shape_ok and record is Dictionary and record.size() == 1 and record.has("stock")
	var old_timing: bool = raw.needs is Dictionary \
		and not raw.needs.has("food_coverage_until") and not raw.needs.has("satisfaction_last_minute")
	_expect(int(raw.worksites.schema_version) == nested_version and shape_ok and old_timing,
		"The %s fixture has its versioned nested worksite, exact legacy site list and no v17 timing fields." % label)


func _legacy_document(current: Dictionary, outer_version: int, state_payload: Variant) -> Dictionary:
	var result: Dictionary = current.duplicate(true)
	result.schema_version = outer_version
	result.state = state_payload
	return result


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


func _finish_fixture_test() -> void:
	if is_instance_valid(content):
		content.queue_free()
	await get_tree().process_frame
	_restore_clock()
	print("LegacyFixtureRepairTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
