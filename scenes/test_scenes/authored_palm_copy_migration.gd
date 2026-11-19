extends RefCounted

## Historical helper name retained for the existing research runner. This is a
## copy-only proof for an explicitly confirmed six-ledger schema-17 or schema-18 city checkpoint.
## It never applies staged state, writes files, or mutates live source ledgers.
const CITY_PATH: String = "res://scenes/content_scene/content_scene.tscn"
const SNAPSHOT = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const SOURCES = preload("res://scenes/new_scenes/save_game/city_save_pickup_sources.gd")
const SOURCE_STATE = preload("res://scenes/pickup_item/pickup_source_state.gd")
const LEGACY_SCHEMA_VERSION: int = 17
const CURRENT_SCHEMA_VERSION: int = 18
const LEGACY_NAMES: Array[String] = [
	"DatePalmTree", "DatePalmTree2", "DatePalmTree3",
	"DatePalmTree4", "DatePalmTree5", "DatePalmTree6",
]
const AUTHORED_NAME: String = "DatePalmTree"
const EXPECTED_CONFIG: Dictionary = {
	"item_id": "date_cluster",
	"quantity": 1,
	"capacity": 3,
	"refill_enabled": true,
	"refill_min_hours": 1,
	"refill_max_hours": 18,
}


## The caller must explicitly confirm a copy operation. A six-source document is
## never treated as proof of age or authorization; the bool is a task decision.
static func prepare_copy(
		document: Dictionary,
		map: Node,
		confirmed_legacy_catalog: bool = false) -> Dictionary:
	if not confirmed_legacy_catalog:
		return _failure("Explicit copy confirmation is required; catalog shape does not prove save age.")
	if not is_instance_valid(map) or not map.is_inside_tree() or map.scene_file_path != CITY_PATH:
		return _failure("A live city map is required for exact catalog validation.")
	if not _valid_header(document):
		return _failure("Only an exact schema-17 or schema-18 city_mvp city/home document is supported.")

	var legacy_ids: Array[String] = _legacy_ids()
	var authored_id: String = _authored_id()
	var source_ids: Array[String] = legacy_ids.duplicate()
	source_ids.append(authored_id)
	var source_nodes: Dictionary = SOURCES.new().nodes()
	if not _valid_current_catalog(source_nodes, source_ids):
		return _failure("The live city source catalog is not exactly the six known legacy ledgers plus the authored palm.")

	var input_copy: Dictionary = document.duplicate(true)
	var codec = VALUES.new()
	var raw: Variant = codec.decode(input_copy.state)
	if not codec.error.is_empty() or not raw is Dictionary:
		return _failure("The checkpoint state cannot be decoded with the current values codec.")
	if float(document.schema_version) == float(LEGACY_SCHEMA_VERSION) and _contains_float64_tag(input_copy.state):
		return _failure("Schema-17 documents cannot contain schema-18 float64 tags.")
	var pickup_sources: Variant = raw.get("pickup_sources")
	if not pickup_sources is Dictionary:
		return _failure("The checkpoint has no pickup-source ledger dictionary.")

	if _has_exact_ids(pickup_sources, source_ids):
		# A complete document is a strict no-op. It is validated, copied, and
		# returned unchanged, even when the authored record is depleted/timed.
		var noop_validator = SNAPSHOT.new()
		if not noop_validator.prepare(input_copy, map):
			return _failure("The complete seven-source checkpoint failed the full validator: " + noop_validator.error)
		return {
			"ok": true,
			"error": "",
			"mode": "noop_complete_seven",
			"candidate": input_copy,
			"report": "Already-complete seven-source document validated without resetting any source record.",
		}

	if not _has_exact_ids(pickup_sources, legacy_ids):
		return _failure("The input must contain exactly the six known legacy palm IDs, with no missing, extra, or foreign IDs.")

	# The schema cannot distinguish a genuine old checkpoint from a newer
	# checkpoint whose new-source entry was removed. This branch is gated by the
	# explicit task confirmation above, never inferred from document contents.
	# The existing full validator checks every legacy record after the new entry
	# is added to this decoded copy; no parallel save validator is maintained here.

	var authored_state: Node = source_nodes.get(authored_id)
	var current_records: Dictionary = SOURCES.new().capture()
	var authored_template: Variant = current_records.get(authored_id)
	if not _valid_source_record(authored_template, EXPECTED_CONFIG, true):
		return _failure("The current authored palm is not a pristine full-three, timer-zero template.")
	if authored_state == null or not is_instance_of(authored_state, SOURCE_STATE):
		return _failure("The current authored palm ledger is unavailable.")

	# Keep the decoded state for validation, but make the encoded edit as narrow as
	# possible: preserve every original encoded source record and append only the
	# new authored record. In particular, this does not normalize v17 numeric
	# satisfaction values or touch any v18 satisfaction accumulator bytes.
	var candidate_sources: Dictionary = pickup_sources.duplicate(true)
	candidate_sources[authored_id] = authored_template.duplicate(true)
	var encoded_template: Variant = codec.encode(authored_template)
	if not codec.error.is_empty():
		return _failure("The authored source cannot be encoded by the existing values codec: " + codec.error)
	var candidate_state: Variant = _append_encoded_authored_source(input_copy.state, legacy_ids, authored_id, encoded_template)
	if candidate_state == null:
		return _failure("The encoded pickup-source ledger is not the exact six-source legacy structure.")
	var decoded_candidate: Variant = codec.decode(candidate_state)
	if not codec.error.is_empty() or not decoded_candidate is Dictionary \
			or not decoded_candidate.get("pickup_sources") is Dictionary \
			or decoded_candidate.pickup_sources != candidate_sources:
		return _failure("The surgically edited candidate does not decode to the expected pickup-source ledger.")
	var candidate: Dictionary = input_copy.duplicate(true)
	candidate["state"] = candidate_state

	# Validate all fields through a fresh instance of the existing full validator.
	# Its staging lives only on that temporary RefCounted and is never applied.
	var validator = SNAPSHOT.new()
	if not validator.prepare(candidate, map):
		return _failure("The candidate failed the full current validator: " + validator.error)
	return {
		"ok": true,
		"error": "",
		"mode": "copy_added_authored_source",
		"candidate": candidate,
		"report": "One pristine authored-source record added to a separate candidate copy; no state applied or file written.",
	}


static func _valid_header(document: Dictionary) -> bool:
	if document.size() != 4:
		return false
	for key: Variant in document.keys():
		if typeof(key) != TYPE_STRING or key not in ["schema_version", "scenario", "location", "state"]:
			return false
	var version: Variant = document.get("schema_version")
	return typeof(version) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(version)) \
		and (float(version) == float(LEGACY_SCHEMA_VERSION) or float(version) == float(CURRENT_SCHEMA_VERSION)) \
		and typeof(document.get("scenario")) == TYPE_STRING \
		and document.scenario == "city_mvp" \
		and typeof(document.get("location")) == TYPE_STRING \
		and document.location in ["city", "home"] \
		and document.get("state") is Dictionary


static func _append_encoded_authored_source(
		encoded_state: Variant,
		legacy_ids: Array[String],
		authored_id: String,
		encoded_template: Variant) -> Variant:
	if not encoded_state is Dictionary or encoded_state.get("$type") != "dictionary":
		return null
	var candidate_state: Dictionary = encoded_state.duplicate(true)
	var state_entries: Variant = candidate_state.get("entries")
	if not state_entries is Array:
		return null
	var pickup_pair: Array = []
	var pickup_pair_index: int = -1
	for index: int in range(state_entries.size()):
		var pair: Variant = state_entries[index]
		if not pair is Array or pair.size() != 2:
			return null
		if typeof(pair[0]) == TYPE_STRING and pair[0] == "pickup_sources":
			if pickup_pair_index >= 0:
				return null
			pickup_pair_index = index
			pickup_pair = pair
	if pickup_pair_index < 0:
		return null
	var encoded_pickup_sources: Variant = pickup_pair[1]
	if not encoded_pickup_sources is Dictionary or encoded_pickup_sources.get("$type") != "dictionary":
		return null
	var source_entries: Variant = encoded_pickup_sources.get("entries")
	if not source_entries is Array or source_entries.size() != legacy_ids.size():
		return null
	var encoded_legacy_ids: Dictionary = {}
	for pair: Variant in source_entries:
		if not pair is Array or pair.size() != 2 or typeof(pair[0]) != TYPE_STRING:
			return null
		var source_id: String = pair[0]
		if encoded_legacy_ids.has(source_id) or source_id not in legacy_ids:
			return null
		encoded_legacy_ids[source_id] = true
	for source_id: String in legacy_ids:
		if not encoded_legacy_ids.has(source_id):
			return null
	if encoded_legacy_ids.has(authored_id) or not encoded_template is Dictionary:
		return null
	# encoded_state was deep-copied above, so this appends only to the candidate.
	encoded_pickup_sources.entries.append([authored_id, encoded_template])
	return candidate_state


static func _contains_float64_tag(value: Variant) -> bool:
	if value is Dictionary:
		if value.get("$type") == "float64":
			return true
		for child: Variant in value.values():
			if _contains_float64_tag(child):
				return true
	elif value is Array:
		for child: Variant in value:
			if _contains_float64_tag(child):
				return true
	return false


static func _legacy_ids() -> Array[String]:
	var result: Array[String] = []
	for palm_name: String in LEGACY_NAMES:
		result.append("DatePalm_" + (CITY_PATH + ":YSortWorld/" + palm_name).sha256_text())
	return result


static func _authored_id() -> String:
	return "DatePalm_" + (CITY_PATH + ":AuthoredMap/YSortWorld/" + AUTHORED_NAME).sha256_text()


static func _valid_current_catalog(nodes: Dictionary, expected_ids: Array[String]) -> bool:
	if nodes.size() != expected_ids.size():
		return false
	var current_records: Dictionary = SOURCES.new().capture()
	if not _has_exact_ids(current_records, expected_ids):
		return false
	for source_id: String in expected_ids:
		var state: Node = nodes.get(source_id)
		if state == null or not is_instance_of(state, SOURCE_STATE):
			return false
		if state.get_parent() != WorkStateRuntime or state.source_scene != CITY_PATH:
			return false
		if str(state.name) != source_id or not _valid_config(state.source_config):
			return false
		if not _valid_source_record(current_records[source_id], EXPECTED_CONFIG, false):
			return false
	return true


static func _valid_config(config: Variant) -> bool:
	if not config is Dictionary or config.size() != EXPECTED_CONFIG.size():
		return false
	for key: Variant in config.keys():
		if typeof(key) != TYPE_STRING or not EXPECTED_CONFIG.has(key):
			return false
	for key: String in EXPECTED_CONFIG:
		if typeof(config.get(key)) != typeof(EXPECTED_CONFIG[key]) or config[key] != EXPECTED_CONFIG[key]:
			return false
	return true


static func _has_exact_ids(records: Dictionary, expected_ids: Array[String]) -> bool:
	if records.size() != expected_ids.size():
		return false
	for source_id: String in expected_ids:
		if not records.has(source_id):
			return false
	return true


static func _valid_source_record(record: Variant, config: Dictionary, pristine: bool) -> bool:
	if not record is Dictionary or record.size() != 4:
		return false
	for key: Variant in record.keys():
		if typeof(key) != TYPE_STRING or key not in ["available", "remaining_minutes", "rng", "config"]:
			return false
	if not _valid_config(record.get("config")) or record.config != config or record.config.size() != config.size():
		return false
	for key: String in config:
		if typeof(record.config.get(key)) != typeof(config[key]):
			return false
	var available: Variant = record.get("available")
	if not available is Array or available.size() != int(config.capacity):
		return false
	var all_full: bool = true
	for slot: Variant in available:
		if typeof(slot) != TYPE_BOOL:
			return false
		all_full = all_full and slot
	var remaining: Variant = record.get("remaining_minutes")
	if typeof(remaining) != TYPE_INT or remaining < 0 or remaining > int(config.refill_max_hours) * 60:
		return false
	if bool(config.refill_enabled):
		if (remaining == 0) != all_full:
			return false
	elif remaining != 0:
		return false
	var rng: Variant = record.get("rng")
	if not rng is Dictionary or rng.size() != 2 or not rng.has("seed") or not rng.has("state"):
		return false
	if typeof(rng.seed) != TYPE_INT or typeof(rng.state) != TYPE_INT:
		return false
	if pristine and (not all_full or remaining != 0):
		return false
	return true


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "mode": "rejected"}
