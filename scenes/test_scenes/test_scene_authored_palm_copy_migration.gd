extends Node

## Historical test name retained for the existing runner. The fixture captures
## the current writer schema and exercises the same confirmed copy migration.
## Every save path is user:// under the isolated XDG profile supplied by the runner.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const BINDING = preload("res://scenes/map_authoring/authored_date_palm_binding.gd")
const MIGRATION = preload("res://scenes/test_scenes/authored_palm_copy_migration.gd")
const SNAPSHOT = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const SOURCES = preload("res://scenes/new_scenes/save_game/city_save_pickup_sources.gd")
const SAVE_FILE = preload("res://scenes/new_scenes/save_game/city_save_file.gd")
const SOURCE_STATE = preload("res://scenes/pickup_item/pickup_source_state.gd")
const PALM_SCRIPT: Script = preload("res://scenes/pickup_item/date_palm_spawner.gd")
const CITY_PATH: String = "res://scenes/content_scene/content_scene.tscn"
const TREE_TEXTURE_PATH: String = "res://assets/objects/nature/trees/date_palm_tree.png"
const AUTHORED_POSITION: Vector2 = Vector2(83, -118)
const HARVEST_WAIT_SECONDS: float = 0.4
const HAULER_APPLICANT_ID: String = "initial_city_storage_hauler"

var failures: int = 0
var checks: int = 0
var store: Node
var map: Node
var candidate_validator
var original_path: String = ""
var output_path: String = ""
var original_document: Dictionary = {}
var original_bytes: PackedByteArray = []
var authored_id: String = ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not _has_isolated_user_data():
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	Inventory.items.clear()
	Inventory.max_load = 100.0

	var run_id: String = "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	# These v17 filename labels are retained for runner compatibility; the
	# synthetic input is written by the actual current SNAPSHOT.VERSION writer.
	original_path = "user://authored_palm_copy_migration_%s/input/legacy_v17.json" % run_id
	output_path = "user://authored_palm_copy_migration_%s/output/converted_v17.json" % run_id
	authored_id = MIGRATION._authored_id()
	candidate_validator = SNAPSHOT.new()

	await _build_real_six_source_checkpoint()
	if failures > 0 or original_document.is_empty():
		_finish()
		return
	await _load_synthetic_authored_map()
	if failures > 0 or not is_instance_valid(map):
		_finish()
		return
	_run_copy_gate_and_full_validation()
	await _run_strict_rejection_fixtures()
	if failures > 0:
		_finish()
		return
	await _write_copy_and_load_normally()
	if failures > 0:
		_finish()
		return
	await _test_harvested_idempotent_round_trip()
	_check(_original_bytes_unchanged(), "The original six-source checkpoint bytes remain unchanged after conversion and reload.")
	print("AuthoredPalmCopyMigrationTest: source_scene=%s authored_id=%s" % [CITY_PATH, authored_id])
	print("AuthoredPalmCopyMigrationTest: %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	_finish()


func _build_real_six_source_checkpoint() -> void:
	# Capture a real current-schema checkpoint before the synthetic palm exists.
	var baseline_map: Node = CITY.instantiate()
	get_tree().root.add_child(baseline_map)
	get_tree().current_scene = baseline_map
	await _wait_frames(6)
	store = WorkStateRuntime.get_node_or_null("CitySave")
	_check(store != null, "The city bootstrap creates the existing deferred CitySave store.")
	if store == null:
		baseline_map.queue_free()
		return
	store.disk.path = original_path
	store.bind_map(baseline_map)
	var sources: Dictionary = SOURCES.new().nodes()
	var legacy_ids: Array[String] = MIGRATION._legacy_ids()
	_check(sources.size() == 6 and _has_exact_ids(sources, legacy_ids),
		"The pre-injection map registers exactly the six known legacy palm ledgers.")
	if not _has_exact_ids(sources, legacy_ids):
		baseline_map.queue_free()
		return
	_seed_legacy_sources(sources)
	_check(TimeComponentManager.advance_minutes(137),
		"The real city clock advances 137 elapsed minutes before capture.")
	original_document = store.snapshot.capture(baseline_map)
	_check(not original_document.is_empty(), "Existing CitySave captures a full six-ledger schema-%d document before injection: %s" % [SNAPSHOT.VERSION, store.snapshot.error])
	if original_document.is_empty():
		baseline_map.queue_free()
		return
	var legacy_values = VALUES.new()
	var legacy_raw: Variant = legacy_values.decode(original_document.state)
	_check(legacy_values.error.is_empty() and legacy_raw is Dictionary
		and legacy_raw.get("pickup_sources", {}).size() == 6,
		"The baseline document contains six source records and no authored-source record.")
	_check(original_document.schema_version == SNAPSHOT.VERSION,
		"The synthetic baseline keeps the actual current schema version (%d)." % SNAPSHOT.VERSION)
	if original_document.schema_version == SNAPSHOT.VERSION and legacy_raw is Dictionary:
		_check(_has_elapsed_satisfaction_accumulator(legacy_raw),
			"Elapsed game minutes create a genuine nonempty current-schema satisfaction accumulator before encoding.")
	var baseline_validator = SNAPSHOT.new()
	_check(baseline_validator.prepare(original_document, baseline_map),
		"The full existing validator accepts the exact original six-source schema-%d checkpoint: %s" % [SNAPSHOT.VERSION, baseline_validator.error])
	_check(store.save_checkpoint(), "The six-ledger checkpoint is written through existing CitySaveFile guards: " + store.last_error)
	original_bytes = FileAccess.get_file_as_bytes(original_path)
	_check(not original_bytes.is_empty(), "The isolated original checkpoint has saved bytes for byte-for-byte preservation checks.")
	var disk_readback: Dictionary = store.disk.read_snapshot(Callable(store, "_validate"))
	_check(not disk_readback.is_empty() and store.disk.error.is_empty(),
		"The original is read back through CitySaveFile and the existing snapshot validator: " + store.disk.error)
	if not disk_readback.is_empty():
		original_document = disk_readback
	_check(original_bytes == FileAccess.get_file_as_bytes(original_path), "The input bytes are stable immediately after guarded readback.")

	baseline_map.queue_free()
	await _wait_frames(4)


func _seed_legacy_sources(sources: Dictionary) -> void:
	var legacy_ids: Array[String] = MIGRATION._legacy_ids()
	var depletion_counts: Array[int] = [1, 2, 3, 1, 2, 3]
	for index: int in range(legacy_ids.size()):
		var state: Node = sources.get(legacy_ids[index])
		if state == null or not is_instance_of(state, SOURCE_STATE):
			_check(false, "Known legacy source exists before seeding: " + legacy_ids[index])
			continue
		state._rng.seed = 31001 + (index * 117)
		for slot: int in range(depletion_counts[index]):
			state.collect(slot)
		_check(state.available.count(false) == depletion_counts[index]
			and int(state.remaining_minutes) >= 60 and int(state.remaining_minutes) <= 1080,
			"Legacy state was varied via normal collect calls, with its timer and RNG retained: " + legacy_ids[index])


func _load_synthetic_authored_map() -> void:
	map = CITY.instantiate()
	var palm: Sprite2D = _make_synthetic_palm(map)
	if palm == null:
		return
	var bind_result: Dictionary = BINDING.bind_before_tree(map)
	_check(bool(bind_result.get("ok", false)), "Existing binding helper accepts the exact detached synthetic palm: " + str(bind_result.get("error", "")))
	if not bool(bind_result.get("ok", false)):
		map.free()
		map = null
		return
	get_tree().root.add_child(map)
	get_tree().current_scene = map
	store.bind_map(map)
	await _wait_frames(6)
	var sources: Dictionary = SOURCES.new().nodes()
	_check(sources.size() == 7 and sources.has(authored_id)
		and _has_exact_ids(sources, _all_ids()),
		"The synthetic authored map has exactly the known six legacy plus one authored ledger.")
	var authored_state: Node = palm.get("state") as Node
	_check(authored_state != null and authored_state.source_config == MIGRATION.EXPECTED_CONFIG,
		"The authored source uses the canonical date-palm configuration.")
	_check(_pristine_authored_record(SOURCES.new().capture().get(authored_id)),
		"The new authored source begins with three full slots and timer zero.")


func _run_copy_gate_and_full_validation() -> void:
	var live_before: Dictionary = store.snapshot.capture(map)
	var live_bytes_before: PackedByteArray = FileAccess.get_file_as_bytes(original_path)
	var source_before: Dictionary = original_document.duplicate(true)
	var denied: Dictionary = MIGRATION.prepare_copy(original_document, map)
	_check(not bool(denied.get("ok", true)) and str(denied.get("error", "")).contains("confirmation"),
		"A six-source document is refused by the default false confirmation gate.")
	_check(_live_document_equals(live_before), "Default-gate refusal leaves all live state unchanged.")
	_check(_original_bytes_unchanged() and original_document == source_before,
		"Default-gate refusal leaves the source dictionary and checkpoint bytes unchanged.")

	var result: Dictionary = MIGRATION.prepare_copy(original_document, map, true)
	_check(bool(result.get("ok", false)) and result.get("mode") == "copy_added_authored_source",
		"Explicit confirmation produces a candidate copy only: " + str(result.get("error", "")))
	if not bool(result.get("ok", false)):
		return
	var candidate: Dictionary = result.candidate
	var old_codec = VALUES.new()
	var old_raw: Variant = old_codec.decode(original_document.state)
	var candidate_codec = VALUES.new()
	var candidate_raw: Variant = candidate_codec.decode(candidate.state)
	_check(old_raw is Dictionary and candidate_raw is Dictionary,
		"The legacy input and candidate decode through the existing values codec.")
	if not old_raw is Dictionary or not candidate_raw is Dictionary:
		return
	_check(candidate.schema_version == original_document.schema_version
		and (candidate.schema_version == 17 or candidate.schema_version == SNAPSHOT.VERSION) and candidate.scenario == "city_mvp"
		and candidate.location == original_document.location,
		"The copy preserves its supported schema version and original city_mvp location.")
	_check(_encoded_state_without_pickup_sources(original_document) == _encoded_state_without_pickup_sources(candidate),
		"Every non-pickup encoded field is canonical-JSON exact, including numeric satisfaction and any v18 accumulator ledger.")
	_check(_encoded_legacy_source_records_match(original_document, candidate),
		"All six existing encoded source-record entries remain byte-equivalent and the authored entry is appended once.")
	_check(candidate_raw.pickup_sources.size() == 7
		and _has_exact_ids(candidate_raw.pickup_sources, _all_ids()),
		"The candidate contains exactly the six original IDs plus the one authored source ID.")
	_check(_legacy_sources_equal(old_raw.pickup_sources, candidate_raw.pickup_sources),
		"All six legacy source records, including depletion, timers, configs, and RNG, are unchanged.")
	var authored_record: Variant = candidate_raw.pickup_sources.get(authored_id)
	_check(_pristine_authored_record(authored_record)
		and authored_record == SOURCES.new().capture().get(authored_id),
		"Only the new record is added, copied from the pristine live authored ledger.")
	var full_validator = SNAPSHOT.new()
	_check(full_validator.prepare(candidate, map),
		"A fresh full city_save_state validator accepts the complete candidate: " + full_validator.error)
	_check(live_before == store.snapshot.capture(map),
		"Successful planning did not apply any staged fields or mutate the live map state.")
	_check(_original_bytes_unchanged() and original_document == source_before,
		"Successful planning leaves the original input document and original file bytes untouched.")

	var repeat: Dictionary = MIGRATION.prepare_copy(original_document, map, true)
	_check(bool(repeat.get("ok", false)) and repeat.candidate == candidate,
		"Repeated planning is deterministic while the fresh authored template is unchanged.")
	_check(_live_document_equals(live_before) and FileAccess.get_file_as_bytes(original_path) == live_bytes_before,
		"Repeated planning leaves live state and original checkpoint bytes unchanged.")


func _run_strict_rejection_fixtures() -> void:
	var live_before: Dictionary = store.snapshot.capture(map)
	var bytes_before: PackedByteArray = FileAccess.get_file_as_bytes(original_path)
	var raw_codec = VALUES.new()
	var base_raw: Dictionary = raw_codec.decode(original_document.state)
	if not raw_codec.error.is_empty():
		_check(false, "Malformed fixture setup decodes the old checkpoint.")
		return

	var missing_raw: Dictionary = base_raw.duplicate(true)
	missing_raw.pickup_sources.erase(MIGRATION._legacy_ids()[0])
	_expect_rejected(_document_with_raw(original_document, missing_raw), "Missing legacy ID is rejected.", live_before, bytes_before,
		"exactly the six known legacy palm IDs")

	var extra_raw: Dictionary = base_raw.duplicate(true)
	extra_raw.pickup_sources["foreign-source-id"] = extra_raw.pickup_sources.values()[0].duplicate(true)
	_expect_rejected(_document_with_raw(original_document, extra_raw), "Extra or foreign source ID is rejected.", live_before, bytes_before,
		"exactly the six known legacy palm IDs")

	var config_raw: Dictionary = base_raw.duplicate(true)
	config_raw.pickup_sources[MIGRATION._legacy_ids()[0]].config.quantity = 2
	_expect_rejected(_document_with_raw(original_document, config_raw), "Changed legacy source config is rejected.", live_before, bytes_before,
		"full current validator: Invalid pickup source state.")

	var timer_raw: Dictionary = base_raw.duplicate(true)
	timer_raw.pickup_sources[MIGRATION._legacy_ids()[0]].remaining_minutes = 0
	_expect_rejected(_document_with_raw(original_document, timer_raw), "Inconsistent or bad source timer is rejected.", live_before, bytes_before,
		"full current validator: Invalid pickup source state.")

	var rng_raw: Dictionary = base_raw.duplicate(true)
	rng_raw.pickup_sources[MIGRATION._legacy_ids()[0]].rng.state = "not-an-integer"
	_expect_rejected(_document_with_raw(original_document, rng_raw), "Wrong source RNG type is rejected.", live_before, bytes_before,
		"full current validator: Invalid pickup source state.")

	var slot_raw: Dictionary = base_raw.duplicate(true)
	slot_raw.pickup_sources[MIGRATION._legacy_ids()[0]].available[0] = 1
	_expect_rejected(_document_with_raw(original_document, slot_raw), "Wrong source slot type is rejected.", live_before, bytes_before,
		"full current validator: Invalid pickup source state.")

	var unrelated_raw: Dictionary = base_raw.duplicate(true)
	unrelated_raw.inventory.items["date_cluster"] = -1
	_expect_rejected(_document_with_raw(original_document, unrelated_raw),
		"Malformed unrelated Inventory state is rejected by the full existing validator.", live_before, bytes_before,
		"full current validator: Unknown item or invalid stock count.")

	if int(original_document.schema_version) == SNAPSHOT.VERSION:
		var accumulator_raw: Dictionary = base_raw.duplicate(true)
		var accumulators: Dictionary = accumulator_raw.needs.get("satisfaction_accumulators", {})
		if accumulators.is_empty():
			_check(false, "The current-schema malformed-accumulator control has a real saved accumulator to corrupt.")
		else:
			var accumulator_id: String = str(accumulators.keys()[0])
			accumulator_raw.needs.satisfaction_accumulators[accumulator_id].minutes = "not-an-integer"
			_expect_rejected(_document_with_raw(original_document, accumulator_raw),
				"Malformed current-schema satisfaction accumulator is rejected by the full validator.", live_before, bytes_before,
				"full current validator: Satisfaction accumulator differs from the saved person.")

	var bad_header: Dictionary = original_document.duplicate(true)
	bad_header.schema_version = "17"
	_expect_rejected(bad_header, "Wrong schema-version type is rejected.", live_before, bytes_before,
		"Only an exact schema-17 or schema-18")
	bad_header = original_document.duplicate(true)
	bad_header.schema_version = 19
	_expect_rejected(bad_header, "Unsupported schema version is rejected.", live_before, bytes_before,
		"Only an exact schema-17 or schema-18")
	var hybrid_v17: Dictionary = original_document.duplicate(true)
	hybrid_v17.schema_version = 17
	# Force a current-codec float64 tag even when this test is running against a
	# genuine schema-17 input. This fixture exists only to prove the hybrid guard.
	var hybrid_codec = VALUES.new()
	hybrid_v17.state = hybrid_codec.encode(base_raw)
	_expect_rejected(hybrid_v17, "A schema-17 header with schema-18 float64 tags is rejected.", live_before, bytes_before,
		"Schema-17 documents cannot contain schema-18 float64 tags.")

	# Add an extra synthetic state to the current global catalog, then remove it.
	# The helper must reject the altered catalog before it stages a candidate.
	var foreign_state: Node = SOURCE_STATE.new()
	foreign_state.name = "DatePalm_synthetic_foreign_catalog_entry"
	foreign_state.source_scene = CITY_PATH
	foreign_state.source_config = MIGRATION.EXPECTED_CONFIG.duplicate(true)
	foreign_state.add_to_group("pickup_source_states")
	WorkStateRuntime.add_child(foreign_state)
	var altered_catalog: Dictionary = MIGRATION.prepare_copy(original_document, map, true)
	_check(not bool(altered_catalog.get("ok", true))
		and str(altered_catalog.get("error", "")).contains("live city source catalog"),
		"An altered current source catalog is rejected by the catalog guard: " + str(altered_catalog.get("error", "")))
	foreign_state.queue_free()
	await _wait_frames(2)
	_check(_live_document_equals(live_before), "Malformed data and altered-catalog attempts leave live state unchanged.")
	_check(FileAccess.get_file_as_bytes(original_path) == bytes_before,
		"Malformed data and altered-catalog attempts leave the original checkpoint bytes unchanged.")


func _expect_rejected(
		document: Dictionary,
		message: String,
		live_before: Dictionary,
		bytes_before: PackedByteArray,
		expected_error_fragment: String) -> void:
	var document_before: Dictionary = document.duplicate(true)
	var result: Dictionary = MIGRATION.prepare_copy(document, map, true)
	var error: String = str(result.get("error", ""))
	_check(not bool(result.get("ok", true)) and error.contains(expected_error_fragment),
		message + " Expected rejection containing '%s', got: %s" % [expected_error_fragment, error])
	_check(_live_document_equals(live_before), message + " Live state remains unchanged.")
	_check(FileAccess.get_file_as_bytes(original_path) == bytes_before,
		message + " The original checkpoint bytes remain unchanged.")
	_check(document == document_before, message + " The supplied synthetic document remains unchanged.")


func _write_copy_and_load_normally() -> void:
	var result: Dictionary = MIGRATION.prepare_copy(original_document, map, true)
	if not bool(result.get("ok", false)):
		_check(false, "A fresh confirmed plan is available for guarded copy output: " + str(result.get("error", "")))
		return
	var candidate: Dictionary = result.candidate
	var copy_disk = SAVE_FILE.new()
	copy_disk.path = output_path
	var observed: Dictionary = copy_disk.read_snapshot(Callable(self, "_validate_candidate"))
	_check(observed.is_empty() and copy_disk.error == "missing",
		"The synthetic output path is observed as missing before first write.")
	_check(copy_disk.write_snapshot(candidate, Callable(self, "_validate_candidate")),
		"The converted candidate writes only to its separate path via guarded CitySaveFile: " + copy_disk.error)
	_check(FileAccess.file_exists(output_path) and not FileAccess.get_file_as_bytes(output_path).is_empty(),
		"The separate converted-copy output exists.")
	_check(_original_bytes_unchanged(), "Writing the copy did not overwrite the original input file.")

	store.disk.path = output_path
	store.refresh_checkpoint_slot()
	# Make the live destination visibly different so the ordinary store load must restore it.
	for state: Node in SOURCES.new().nodes().values():
		if state is Node and state.has_method("collect"):
			state.available.fill(true)
			state.remaining_minutes = 0
	Inventory.items.clear()
	_check(store.load_checkpoint(), "Normal CitySave store loads the converted copy: " + store.last_error)
	await _wait_frames(5)
	var loaded_document: Dictionary = store.snapshot.capture(map)
	var loaded_codec = VALUES.new()
	var loaded_raw: Variant = loaded_codec.decode(loaded_document.state) if not loaded_document.is_empty() else null
	var candidate_codec = VALUES.new()
	var candidate_raw: Variant = candidate_codec.decode(candidate.state)
	_check(loaded_raw is Dictionary and candidate_raw is Dictionary,
		"The normal store load produces a capturable seven-ledger city state.")
	if loaded_raw is Dictionary and candidate_raw is Dictionary:
		_check(_all_non_source_fields_match_after_load(candidate_raw, loaded_raw, int(candidate.schema_version)),
			"Normal load restores every non-source saved field exactly.")
		_check(_legacy_sources_equal(candidate_raw.pickup_sources, loaded_raw.pickup_sources),
			"Normal load restores each of the six legacy source ledgers exactly.")
		_check(loaded_raw.pickup_sources.get(authored_id) == candidate_raw.pickup_sources.get(authored_id)
			and _pristine_authored_record(loaded_raw.pickup_sources.get(authored_id)),
			"Normal load restores the added authored source as full-three and timer-zero.")
	_check(_original_bytes_unchanged(), "Normal loading the copy leaves the original six-source file untouched.")


func _test_harvested_idempotent_round_trip() -> void:
	var palm: Node = map.get_node_or_null("AuthoredMap/YSortWorld/DatePalmTree")
	var player: Node = map.get_node_or_null("YSortWorld/Player")
	_check(palm != null and player != null and palm.get_script() == PALM_SCRIPT,
		"The synthetic authored palm and player remain available for a real gather round trip.")
	if palm == null or player == null:
		return
	var state: Node = palm.get("state") as Node
	var before_dates: int = int(Inventory.items.get("date_cluster", 0))
	Inventory.max_load = 100.0
	player.global_position = palm.global_position + Vector2(-40, 18)
	var pickup: Node = (palm.get("_pickups") as Dictionary).get(0)
	_check(pickup != null, "The full authored palm presents a real fruit pickup before harvest.")
	if pickup == null:
		return
	pickup.on_player_gather(player)
	await get_tree().create_timer(HARVEST_WAIT_SECONDS).timeout
	_check(state.available.count(false) == 3 and int(state.remaining_minutes) >= 60
		and int(state.remaining_minutes) <= 1080,
		"The normal gather handler depletes all three authored slots and starts its normal timer.")
	_check(int(Inventory.items.get("date_cluster", 0)) == before_dates + 3,
		"The one real harvest grants exactly three dates once.")
	_check(_fruit_count(map) == 0, "Harvest removes the authored palm fruit views without duplicates.")
	var harvested_document: Dictionary = store.snapshot.capture(map)
	_check(not harvested_document.is_empty(), "The depleted authored source can be captured before its second save.")
	if harvested_document.is_empty():
		return
	var harvested_codec = VALUES.new()
	var harvested_raw: Dictionary = harvested_codec.decode(harvested_document.state)
	var authored_harvest_record: Dictionary = harvested_raw.pickup_sources[authored_id].duplicate(true)
	var live_before_noop: Dictionary = store.snapshot.capture(map)
	var no_op: Dictionary = MIGRATION.prepare_copy(harvested_document, map, true)
	_check(bool(no_op.get("ok", false)) and no_op.get("mode") == "noop_complete_seven"
		and no_op.candidate == harvested_document,
		"A complete seven-source document takes the no-op path, preserving depletion and its exact timer.")
	_check(authored_harvest_record.available.count(false) == 3
		and authored_harvest_record.remaining_minutes > 0,
		"The idempotent candidate does not replenish or reset the harvested authored record.")
	_check(live_before_noop == store.snapshot.capture(map),
		"Full-document no-op validation leaves the already-depleted live authored state unchanged.")
	_check(_original_bytes_unchanged(), "No-op validation does not touch the six-source original.")

	store.disk.path = output_path
	_check(store.save_checkpoint(), "Normal CitySave saves the harvested seven-source checkpoint: " + store.last_error)
	var saved_output_bytes: PackedByteArray = FileAccess.get_file_as_bytes(output_path)
	_check(not saved_output_bytes.is_empty(), "The harvested copy is persisted to the separate output slot.")
	# Simulate a fresh live view, then demand that the ordinary load restores the saved depletion.
	state.available.fill(true)
	state.remaining_minutes = 0
	state.changed.emit()
	Inventory.items["date_cluster"] = before_dates
	_check(store.load_checkpoint(), "Normal CitySave reloads the harvested copy: " + store.last_error)
	await _wait_frames(5)
	_check(state.available.count(false) == 3 and int(state.remaining_minutes) == int(authored_harvest_record.remaining_minutes),
		"Reload preserves the authored source depletion and exact refill timer.")
	_check(int(Inventory.items.get("date_cluster", 0)) == before_dates + 3,
		"Reload restores exactly the saved dates without regranting or duplicating them.")
	_check(_fruit_count(map) == 0 and SOURCES.new().nodes().size() == 7,
		"Reload keeps the depleted palm empty and exactly one ledger per seven source IDs.")
	_check(FileAccess.get_file_as_bytes(output_path) == saved_output_bytes,
		"Loading the harvested output does not rewrite its checkpoint bytes.")
	_check(_original_bytes_unchanged(), "Harvest save/load still leaves the original six-source file unchanged.")


func _make_synthetic_palm(city_map: Node) -> Sprite2D:
	var authored_map: Node = city_map.get_node_or_null("AuthoredMap")
	var authored_world: Node = city_map.get_node_or_null("AuthoredMap/YSortWorld")
	if authored_map == null or authored_world == null or authored_world.get_node_or_null("DatePalmTree") != null:
		_check(false, "The synthetic fixture requires the exact empty AuthoredMap/YSortWorld/DatePalmTree path.")
		return null
	var palm := Sprite2D.new()
	palm.name = "DatePalmTree"
	palm.position = AUTHORED_POSITION
	palm.texture = load(TREE_TEXTURE_PATH) as Texture2D
	if palm.texture == null:
		_check(false, "The known authored date-palm tree texture loads from the cloud project.")
		return null
	authored_world.add_child(palm)
	palm.owner = authored_map
	return palm


func _validate_candidate(document: Dictionary) -> bool:
	var validator = SNAPSHOT.new()
	return validator.prepare(document, map)


func _document_with_raw(base: Dictionary, raw: Dictionary) -> Dictionary:
	var codec = VALUES.new()
	var result: Dictionary = base.duplicate(true)
	var encoded: Variant = codec.encode(raw)
	if int(base.get("schema_version", -1)) == 17:
		# This is a synthetic malformed-input builder, not genuine writer
		# evidence. Recreate schema-17's ordinary numeric satisfaction values so
		# the intended malformed field reaches the validator instead of the
		# hybrid-v17 float64-tag guard.
		encoded = _replace_float64_tags_with_legacy_numbers(encoded)
	result["state"] = encoded
	return result


func _replace_float64_tags_with_legacy_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		if value.get("$type") == "float64":
			return VALUES.decode_float64_hex(str(value.get("value", "")))
		var replaced: Dictionary = {}
		for key: Variant in value:
			replaced[key] = _replace_float64_tags_with_legacy_numbers(value[key])
		return replaced
	if value is Array:
		var replaced: Array = []
		for child: Variant in value:
			replaced.append(_replace_float64_tags_with_legacy_numbers(child))
		return replaced
	return value


func _encoded_state_without_pickup_sources(document: Dictionary) -> String:
	var encoded_state: Variant = document.get("state")
	var entries: Variant = _encoded_dictionary_entries(encoded_state)
	if not entries is Array:
		return "<invalid-encoded-state>"
	var retained_entries: Array = entries.duplicate(true)
	var pickup_source_fields: int = 0
	for index: int in range(retained_entries.size() - 1, -1, -1):
		var pair: Variant = retained_entries[index]
		if not pair is Array or pair.size() != 2:
			return "<invalid-encoded-entry>"
		if typeof(pair[0]) == TYPE_STRING and pair[0] == "pickup_sources":
			pickup_source_fields += 1
			retained_entries.remove_at(index)
	if pickup_source_fields != 1:
		return "<missing-or-duplicate-pickup-sources>"
	var retained_state: Dictionary = encoded_state.duplicate(true)
	retained_state["entries"] = retained_entries
	return JSON.stringify(retained_state, "", true, true)


func _encoded_legacy_source_records_match(original_document_value: Dictionary, candidate: Dictionary) -> bool:
	var original_sources: Variant = _encoded_field_value(original_document_value.get("state"), "pickup_sources")
	var candidate_sources: Variant = _encoded_field_value(candidate.get("state"), "pickup_sources")
	var original_entries: Variant = _encoded_dictionary_entries(original_sources)
	var candidate_entries: Variant = _encoded_dictionary_entries(candidate_sources)
	if not original_entries is Array or not candidate_entries is Array \
			or original_entries.size() != 6 or candidate_entries.size() != 7:
		return false
	for index: int in range(original_entries.size()):
		if JSON.stringify(original_entries[index], "", true, true) != JSON.stringify(candidate_entries[index], "", true, true):
			return false
	var appended: Variant = candidate_entries[6]
	return appended is Array and appended.size() == 2 \
		and typeof(appended[0]) == TYPE_STRING and appended[0] == authored_id


func _encoded_field_value(encoded_dictionary: Variant, field_name: String) -> Variant:
	var entries: Variant = _encoded_dictionary_entries(encoded_dictionary)
	if not entries is Array:
		return null
	var found: bool = false
	var result: Variant = null
	for pair: Variant in entries:
		if not pair is Array or pair.size() != 2:
			return null
		if typeof(pair[0]) == TYPE_STRING and pair[0] == field_name:
			if found:
				return null
			found = true
			result = pair[1]
	return result if found else null


func _encoded_dictionary_entries(encoded_dictionary: Variant) -> Variant:
	if not encoded_dictionary is Dictionary or encoded_dictionary.get("$type") != "dictionary":
		return null
	var entries: Variant = encoded_dictionary.get("entries")
	return entries if entries is Array else null


func _all_non_source_fields_match_after_load(
		expected_raw: Dictionary,
		loaded_raw: Dictionary,
		schema_version: int) -> bool:
	var expected: Dictionary = expected_raw.duplicate(true)
	var loaded: Dictionary = loaded_raw.duplicate(true)
	if schema_version == 17:
		var expected_needs: Variant = expected.get("needs")
		var loaded_needs: Variant = loaded.get("needs")
		if not expected_needs is Dictionary or not loaded_needs is Dictionary \
				or expected_needs.has("satisfaction_accumulators") \
				or not loaded_needs.get("satisfaction_accumulators") is Dictionary \
				or not loaded_needs.satisfaction_accumulators.is_empty():
			return false
		# The only expected schema-17 migration is the validator's empty v18
		# accumulator ledger; no other absent group or field is ignored.
		expected_needs["satisfaction_accumulators"] = {}
	elif schema_version != SNAPSHOT.VERSION:
		return false
	expected.erase("pickup_sources")
	loaded.erase("pickup_sources")
	var expected_codec = VALUES.new()
	var loaded_codec = VALUES.new()
	var expected_encoded: Variant = expected_codec.encode(expected)
	var loaded_encoded: Variant = loaded_codec.encode(loaded)
	if expected_codec.error.is_empty() and loaded_codec.error.is_empty() \
			and JSON.stringify(expected_encoded, "", true, true) == JSON.stringify(loaded_encoded, "", true, true):
		return true

	# Keep failure evidence specific instead of normalizing away live changes.
	var keys: Dictionary = {}
	for key: Variant in expected:
		keys[key] = true
	for key: Variant in loaded:
		keys[key] = true
	var changed_fields: Array[String] = []
	for key: Variant in keys:
		var expected_field_codec = VALUES.new()
		var loaded_field_codec = VALUES.new()
		var expected_field: Variant = expected_field_codec.encode({"value": expected.get(key, null), "present": expected.has(key)})
		var loaded_field: Variant = loaded_field_codec.encode({"value": loaded.get(key, null), "present": loaded.has(key)})
		if JSON.stringify(expected_field, "", true, true) != JSON.stringify(loaded_field, "", true, true):
			changed_fields.append(str(key))
	push_error("Exact post-load field comparison failed. Changed non-source groups: " + ", ".join(changed_fields))
	return false


func _has_elapsed_satisfaction_accumulator(raw: Variant) -> bool:
	if not raw is Dictionary or not raw.get("needs") is Dictionary:
		return false
	var ledger: Variant = raw.needs.get("satisfaction_accumulators")
	if not ledger is Dictionary or ledger.is_empty():
		return false
	for record: Variant in ledger.values():
		if record is Dictionary and typeof(record.get("minutes")) == TYPE_INT and int(record.minutes) != 0:
			return true
	return false


func _legacy_sources_equal(old_sources: Dictionary, new_sources: Dictionary) -> bool:
	for source_id: String in MIGRATION._legacy_ids():
		if not old_sources.has(source_id) or not new_sources.has(source_id):
			return false
		if old_sources[source_id] != new_sources[source_id]:
			return false
	return true


func _has_exact_ids(actual: Dictionary, expected_ids: Array[String]) -> bool:
	if actual.size() != expected_ids.size():
		return false
	for source_id: String in expected_ids:
		if not actual.has(source_id):
			return false
	return true


func _all_ids() -> Array[String]:
	var ids: Array[String] = MIGRATION._legacy_ids()
	ids.append(authored_id)
	return ids


func _pristine_authored_record(record: Variant) -> bool:
	if not record is Dictionary or record.size() != 4:
		return false
	return record.get("available") is Array and record.available.size() == 3 \
		and record.available == [true, true, true] \
		and typeof(record.get("remaining_minutes")) == TYPE_INT and record.remaining_minutes == 0 \
		and record.get("config") == MIGRATION.EXPECTED_CONFIG \
		and record.get("rng") is Dictionary and typeof(record.rng.get("seed")) == TYPE_INT \
		and typeof(record.rng.get("state")) == TYPE_INT


func _live_document_equals(expected: Dictionary) -> bool:
	return expected == store.snapshot.capture(map)


func _original_bytes_unchanged() -> bool:
	return not original_bytes.is_empty() and FileAccess.get_file_as_bytes(original_path) == original_bytes


func _fruit_count(city_map: Node) -> int:
	var count: int = 0
	for pickup: Node in get_tree().get_nodes_in_group("date_palm_pickups"):
		if city_map.is_ancestor_of(pickup) and not pickup.is_queued_for_deletion() \
				and not bool(pickup.get("is_collecting")):
			count += 1
	return count


func _has_isolated_user_data() -> bool:
	var xdg: String = OS.get_environment("XDG_DATA_HOME").simplify_path().trim_suffix("/")
	var user_path: String = ProjectSettings.globalize_path("user://").simplify_path()
	if not xdg.is_absolute_path() or not xdg.to_lower().contains("authored_palm_copy_migration") \
			or not user_path.begins_with(xdg + "/"):
		push_error("Palm copy migration test refuses non-isolated user data. user://=%s XDG_DATA_HOME=%s" % [user_path, xdg])
		return false
	print("AuthoredPalmCopyMigrationTest isolated user data: ", user_path)
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
	print("AuthoredPalmCopyMigrationTest: %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
