extends Node

const SAVE_FILE = preload("res://scenes/new_scenes/save_game/city_save_file.gd")
const MAX_FILE_BYTES: int = 8 * 1024 * 1024
const MAX_JSON_NESTING: int = 128

class FailedRecoveryRead:
	extends "res://scenes/new_scenes/save_game/city_save_file.gd"
	func _read_candidate(source: String, validator: Callable) -> Dictionary:
		if source == path + ".tmp":
			return {"ok": false, "error": "read_failed"}
		return super._read_candidate(source, validator)

class ChangedRecoveryRead:
	extends "res://scenes/new_scenes/save_game/city_save_file.gd"
	func _read_candidate(source: String, validator: Callable) -> Dictionary:
		var result: Dictionary = super._read_candidate(source, validator)
		if source == path + ".tmp" and result.has("digest"):
			result.digest = "different bytes during read"
		return result

var failures: int = 0
var test_root: String = ""

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	test_root = "user://city_save_file_tests/%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_test_round_trip_and_backup()
	_test_missing_and_observation()
	_test_corrupt_primary_and_validation()
	_test_size_limit()
	_test_external_change()
	_test_recovery()
	_test_recovery_read_failure()
	_cleanup()
	print("CitySaveFileTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)

func _test_round_trip_and_backup() -> void:
	var helper = _helper("round_trip.json")
	_expect(not helper.exists(), "An unused isolated slot does not exist.")
	_expect(helper.read_snapshot(_validator).is_empty() and helper.error == "missing", "Missing slot is reported for first-write observation.")
	var first: Dictionary = {"schema_version": 1, "counter": 1, "items": ["wood", "stone"]}
	_expect(helper.write_snapshot(first, _validator), "A validated snapshot writes after observing a missing slot: " + helper.error)
	_expect(helper.exists(), "A primary snapshot counts as an existing slot.")
	var reader = _helper("round_trip.json")
	var loaded: Dictionary = reader.read_snapshot(_validator)
	_expect(_snapshot_matches(loaded, first), "A new helper reads the same JSON dictionary: " + reader.error)
	var second: Dictionary = {"schema_version": 1, "counter": 2, "items": ["wood"]}
	_expect(reader.write_snapshot(second, _validator), "A validated replacement writes after reading the existing primary: " + reader.error)
	_expect(FileAccess.file_exists(reader.path + ".bak"), "Replacing a primary retains the prior valid snapshot in .bak.")
	_expect(_snapshot_matches(_read_raw(reader.path + ".bak"), first), "The backup contains the previously validated primary.")

func _test_missing_and_observation() -> void:
	var path: String = _path("unobserved.json")
	var initial: Dictionary = {"schema_version": 1, "counter": 7, "items": []}
	_write_raw(path, JSON.stringify(initial))
	var helper = _helper("unobserved.json")
	var replacement: Dictionary = {"schema_version": 1, "counter": 8, "items": []}
	_expect(not helper.write_snapshot(replacement, _validator) and helper.error == "read_required", "An existing primary cannot be replaced before it is read.")
	_expect(_read_text(path) == JSON.stringify(initial), "The unobserved primary remains unchanged.")

func _test_corrupt_primary_and_validation() -> void:
	var helper = _helper("corrupt.json")
	var valid: Dictionary = {"schema_version": 1, "counter": 3, "items": []}
	_write_raw(helper.path + ".bak", JSON.stringify(valid))
	_write_raw(helper.path, "{corrupt")
	var before: String = _read_text(helper.path)
	_expect(helper.read_snapshot(_validator).is_empty() and helper.error == "invalid", "A corrupt primary is rejected without loading its backup.")
	_expect(not helper.write_snapshot(valid, _validator), "A corrupt primary cannot be overwritten.")
	_expect(_read_text(helper.path) == before, "Corrupt primary bytes are preserved.")

	var unsupported = _helper("unsupported.json")
	var unsupported_text: String = JSON.stringify({"schema_version": 2, "counter": 9, "items": []})
	_write_raw(unsupported.path + ".bak", JSON.stringify(valid))
	_write_raw(unsupported.path, unsupported_text)
	_expect(unsupported.read_snapshot(_validator).is_empty() and unsupported.error == "unsupported", "An unsupported primary is rejected without loading its backup.")
	_expect(not unsupported.write_snapshot(valid, _validator), "An unsupported primary cannot be overwritten.")
	_expect(_read_text(unsupported.path) == unsupported_text, "Unsupported primary bytes are preserved.")

	var rejected = _helper("rejected.json")
	_expect(rejected.read_snapshot(_validator).is_empty() and rejected.error == "missing", "Rejected-write slot starts empty.")
	var wrong_schema: Dictionary = {"schema_version": 2, "counter": 4, "items": []}
	_expect(not rejected.write_snapshot(wrong_schema, _validator) and rejected.error == "validator_rejected", "Caller validation rejects unsupported snapshots before publication.")
	_expect(not rejected.exists(), "Rejected data does not create a save file.")
	var object_snapshot: Dictionary = {"schema_version": 1, "counter": 1, "items": [], "node": Node.new()}
	_expect(not rejected.write_snapshot(object_snapshot, _validator), "Godot objects are rejected from JSON snapshots.")
	object_snapshot["node"].free()
	for non_finite: float in [NAN, INF, -INF]:
		var non_finite_snapshot: Dictionary = {"schema_version": 1, "counter": 1, "items": [], "unsafe": non_finite}
		_expect(not rejected.write_snapshot(non_finite_snapshot, _validator), "Non-finite numbers are rejected from JSON snapshots.")
	var deep_value: Variant = "leaf"
	for _index: int in range(MAX_JSON_NESTING + 1):
		deep_value = [deep_value]
	var deep_snapshot: Dictionary = {"schema_version": 1, "counter": 1, "items": [], "deep": deep_value}
	_expect(not rejected.write_snapshot(deep_snapshot, _validator), "JSON values deeper than the nesting limit are rejected.")

func _test_size_limit() -> void:
	var helper = _helper("oversized.json")
	var oversized := PackedByteArray()
	oversized.resize(MAX_FILE_BYTES + 1)
	var file := FileAccess.open(helper.path, FileAccess.WRITE)
	file.store_buffer(oversized)
	file.close()
	_expect(helper.read_snapshot(_validator).is_empty() and helper.error == "size_limit", "Files above 8 MiB are rejected.")
	_expect(FileAccess.get_file_as_bytes(helper.path).size() == MAX_FILE_BYTES + 1, "Oversized input remains untouched.")
	_expect(not helper.write_snapshot({"schema_version": 1, "counter": 1, "items": []}, _validator), "An oversized primary cannot be overwritten.")
	var oversized_write = _helper("oversized_write.json")
	_expect(oversized_write.read_snapshot(_validator).is_empty(), "Oversized-write slot starts missing.")
	var oversized_snapshot: Dictionary = {"schema_version": 1, "counter": 1, "items": ["x".repeat(MAX_FILE_BYTES)]}
	_expect(not oversized_write.write_snapshot(oversized_snapshot, _validator) and oversized_write.error == "size_limit", "Writes above 8 MiB are rejected before creating a save.")
	_expect(not oversized_write.exists(), "An oversized snapshot is not published.")
	var valid: Dictionary = {"schema_version": 1, "counter": 6, "items": []}
	var sidecar = _helper("oversized_sidecar.json")
	_write_raw(sidecar.path, JSON.stringify(valid))
	var sidecar_file := FileAccess.open(sidecar.path + ".tmp", FileAccess.WRITE)
	sidecar_file.store_buffer(oversized)
	sidecar_file.close()
	_expect(_snapshot_matches(sidecar.read_snapshot(_validator), valid), "A valid primary remains readable beside an oversized sidecar.")
	_expect(sidecar.inspect_recovery_candidates(_validator).is_empty() and sidecar.observation_is_current(),
		"A confirmed oversized sidecar is skipped after its streamed digest matches the observation.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sidecar.path))
	_write_raw(sidecar.path + ".bak", JSON.stringify(valid))
	sidecar = _helper("oversized_sidecar.json")
	_expect(_snapshot_matches(sidecar.read_snapshot(_validator), valid), "A confirmed oversized temporary file does not block a valid backup.")
	_expect(sidecar.inspect_recovery_candidates(_validator).is_empty(), "Recovery can inspect and skip the oversized candidate safely.")

func _test_external_change() -> void:
	var helper = _helper("external.json")
	var original: Dictionary = {"schema_version": 1, "counter": 1, "items": []}
	_expect(helper.read_snapshot(_validator).is_empty(), "External-change slot starts missing.")
	_expect(helper.write_snapshot(original, _validator), "Initial external-change snapshot writes: " + helper.error)
	var session = _helper("external.json")
	_expect(_snapshot_matches(session.read_snapshot(_validator), original), "Second session observes the primary: " + session.error)
	_expect(session.observation_is_current(), "An unchanged observation remains current.")
	var external: String = JSON.stringify({"schema_version": 1, "counter": 99, "items": []})
	_write_raw(session.path, external)
	_expect(not session.observation_is_current(), "An external change invalidates the observed slot before loading or writing.")
	var attempted: Dictionary = {"schema_version": 1, "counter": 2, "items": []}
	_expect(not session.write_snapshot(attempted, _validator) and session.error == "changed", "A changed primary blocks a stale session write.")
	_expect(_read_text(session.path) == external, "External primary contents are preserved byte for byte.")

func _test_recovery() -> void:
	var backup_helper = _helper("recover_backup.json")
	var backup_data: Dictionary = {"schema_version": 1, "counter": 11, "items": ["backup"]}
	_write_raw(backup_helper.path + ".bak", JSON.stringify(backup_data))
	_expect(_snapshot_matches(backup_helper.read_snapshot(_validator), backup_data), "A missing primary recovers from a valid backup.")
	var restored: Dictionary = {"schema_version": 1, "counter": 12, "items": ["restored"]}
	_expect(backup_helper.write_snapshot(restored, _validator), "A recovered backup can be written to a new primary: " + backup_helper.error)
	_expect(_snapshot_matches(_read_raw(backup_helper.path + ".bak"), backup_data), "Recovery preserves its valid backup.")

	var temp_helper = _helper("recover_temp.json")
	var temp_data: Dictionary = {"schema_version": 1, "counter": 21, "items": ["temporary"]}
	_write_raw(temp_helper.path + ".tmp", JSON.stringify(temp_data))
	_expect(_snapshot_matches(temp_helper.read_snapshot(_validator), temp_data), "A missing primary recovers from a valid temporary snapshot: " + temp_helper.error)
	_expect(temp_helper.error.is_empty(), "Successful temporary recovery clears the error string.")

func _test_recovery_read_failure() -> void:
	var helper = FailedRecoveryRead.new()
	helper.path = _path("read_failure.json")
	var valid: Dictionary = {"schema_version": 1, "counter": 33, "items": []}
	var text: String = JSON.stringify(valid)
	_write_raw(helper.path, text)
	_write_raw(helper.path + ".tmp", text)
	_write_raw(helper.path + ".bak", text)
	_expect(_snapshot_matches(helper.read_snapshot(_validator), valid), "A valid primary is selected before the simulated sidecar failure.")
	_expect(helper.inspect_recovery_candidates(_validator) == "read_failed" and helper.observation_is_current(),
		"A failed sidecar read is reported even if the observed file hashes have not changed.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(helper.path))
	helper = FailedRecoveryRead.new()
	helper.path = _path("read_failure.json")
	_expect(helper.read_snapshot(_validator).is_empty() and helper.error == "read_failed",
		"A transient recovery read failure does not fall through to an older backup.")
	_expect(not helper.write_snapshot(valid, _validator), "A failed recovery read cannot authorize a write.")
	_expect(_read_text(helper.path + ".tmp") == text and _read_text(helper.path + ".bak") == text,
		"The unread recovery candidate and backup are both preserved.")
	_write_raw(helper.path, text)
	var changed = ChangedRecoveryRead.new()
	changed.path = helper.path
	_expect(_snapshot_matches(changed.read_snapshot(_validator), valid), "The primary can be observed before a simulated sidecar race.")
	_expect(changed.inspect_recovery_candidates(_validator) == "changed" and changed.observation_is_current(),
		"The scanned bytes must match the observed hash even if the file is restored afterward.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(changed.path))
	changed = ChangedRecoveryRead.new()
	changed.path = helper.path
	_expect(changed.read_snapshot(_validator).is_empty() and changed.error == "changed",
		"A different recovery buffer is not silently skipped for the older backup.")
	_expect(not changed.write_snapshot(valid, _validator), "A recovery race cannot authorize a write.")

func _helper(filename: String):
	var helper = SAVE_FILE.new()
	helper.path = _path(filename)
	return helper

func _path(filename: String) -> String:
	return test_root.path_join(filename)

func _validator(snapshot: Dictionary) -> bool:
	var version: Variant = snapshot.get("schema_version")
	var counter: Variant = snapshot.get("counter")
	return version == 1 \
		and (typeof(counter) == TYPE_INT or (typeof(counter) == TYPE_FLOAT and is_equal_approx(counter, round(counter)))) \
		and counter >= 0 \
		and typeof(snapshot.get("items")) == TYPE_ARRAY

func _write_raw(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()

func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func _read_raw(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read_text(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _snapshot_matches(actual: Dictionary, expected: Dictionary) -> bool:
	return int(actual.get("schema_version", -1)) == int(expected.get("schema_version", -2)) \
		and int(actual.get("counter", -1)) == int(expected.get("counter", -2)) \
		and actual.get("items") == expected.get("items")

func _cleanup() -> void:
	for filename: String in [
		"round_trip.json", "round_trip.json.bak", "round_trip.json.tmp", "round_trip.json.pending",
		"unobserved.json", "unobserved.json.bak", "unobserved.json.tmp", "unobserved.json.pending",
		"corrupt.json", "corrupt.json.bak", "corrupt.json.tmp", "corrupt.json.pending",
		"unsupported.json", "unsupported.json.bak", "unsupported.json.tmp", "unsupported.json.pending",
		"rejected.json", "rejected.json.bak", "rejected.json.tmp", "rejected.json.pending",
		"oversized.json", "oversized.json.bak", "oversized.json.tmp", "oversized.json.pending",
		"oversized_write.json", "oversized_write.json.bak", "oversized_write.json.tmp", "oversized_write.json.pending",
		"oversized_sidecar.json", "oversized_sidecar.json.bak", "oversized_sidecar.json.tmp", "oversized_sidecar.json.pending",
		"external.json", "external.json.bak", "external.json.tmp", "external.json.pending",
		"recover_backup.json", "recover_backup.json.bak", "recover_backup.json.tmp", "recover_backup.json.pending",
		"recover_temp.json", "recover_temp.json.bak", "recover_temp.json.tmp", "recover_temp.json.pending",
		"read_failure.json", "read_failure.json.bak", "read_failure.json.tmp", "read_failure.json.pending"
	]:
		var absolute: String = ProjectSettings.globalize_path(_path(filename))
		if FileAccess.file_exists(_path(filename)):
			DirAccess.remove_absolute(absolute)
	var directory: String = ProjectSettings.globalize_path(test_root)
	DirAccess.remove_absolute(directory)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
