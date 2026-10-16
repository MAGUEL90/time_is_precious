extends RefCounted

## Small disk boundary for the city snapshot. Snapshot meaning and schema
## validation belong to the caller; this class only protects the JSON files.
const DEFAULT_PATH: String = "user://city_save/checkpoint_v1.json"
const MAX_FILE_BYTES: int = 8 * 1024 * 1024
const MAX_JSON_NESTING: int = 128

var path: String = DEFAULT_PATH
var error: String = ""

var _observation_ready: bool = false
var _write_permitted: bool = false
var _observation_hashes_valid: bool = true
var _observed_files: Dictionary = {}

func exists() -> bool:
	return FileAccess.file_exists(path) \
		or FileAccess.file_exists(path + ".bak") \
		or FileAccess.file_exists(path + ".tmp") \
		or FileAccess.file_exists(path + ".pending")

## A valid primary always wins. Recovery files are considered only when the
## primary is absent, and each candidate must pass the caller's validator.
func read_snapshot(validator: Callable) -> Dictionary:
	error = ""
	_observation_ready = true
	_write_permitted = false
	_capture_observation()
	if not validator.is_valid():
		error = "invalid_validator"
		return {}
	if FileAccess.file_exists(path):
		var primary: Dictionary = _read_candidate(path, validator)
		if not bool(primary.get("ok", false)):
			error = str(primary.get("error", "invalid"))
			return {}
		_write_permitted = true
		return primary["snapshot"]

	var found_candidate: bool = false
	for source: String in [path + ".tmp", path + ".pending", path + ".bak"]:
		if not FileAccess.file_exists(source):
			continue
		found_candidate = true
		var recovery: Dictionary = _read_candidate(source, validator)
		if bool(recovery.get("ok", false)):
			_write_permitted = true
			return recovery["snapshot"]
	if found_candidate:
		error = "invalid_recovery"
		return {}
	error = "missing"
	_write_permitted = true
	return {}

## Existing files may only be replaced after a successful read in this helper
## instance. The read records hashes for all managed files so external edits
## cannot be silently overwritten.
func write_snapshot(data: Dictionary, validator: Callable) -> bool:
	error = ""
	if not _observation_ready:
		error = "read_required"
		return false
	if not _write_permitted:
		if error.is_empty():
			error = "read_required"
		return false
	if not validator.is_valid() or not _is_json_value(data):
		error = "invalid_snapshot"
		return false
	var input_result: Variant = validator.call(data)
	if typeof(input_result) != TYPE_BOOL or not input_result:
		error = "validator_rejected"
		return false
	if not _matches_observation():
		error = "changed"
		return false

	var serialized: String = JSON.stringify(data, "\t", true, true)
	var serialized_bytes: PackedByteArray = serialized.to_utf8_buffer()
	if serialized_bytes.size() > MAX_FILE_BYTES:
		error = "size_limit"
		return false
	var absolute_path: String = ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir()) != OK:
		error = "path_error"
		return false

	var pending_path: String = path + ".pending"
	if not _write_text(pending_path, serialized):
		error = "write_failed"
		return false
	var pending: Dictionary = _read_candidate(pending_path, validator)
	if not bool(pending.get("ok", false)):
		error = str(pending.get("error", "write_failed"))
		return false
	var expected_digest: String = str(pending.get("digest", ""))
	if expected_digest.is_empty() or not _matches_observation([pending_path]):
		error = "changed"
		return false

	# Keep a recognized temporary snapshot available if the process stops during
	# primary/backup rotation. The pending copy remains verified if writing the
	# recognized temporary file is interrupted.
	var temporary_path: String = path + ".tmp"
	if not _write_text(temporary_path, serialized):
		error = "write_failed"
		return false
	var temporary: Dictionary = _read_candidate(temporary_path, validator)
	if not bool(temporary.get("ok", false)) or str(temporary.get("digest", "")) != expected_digest:
		error = "write_failed"
		return false
	if not _matches_primary_and_backup():
		error = "changed"
		return false

	if FileAccess.file_exists(path):
		var backup_path: String = path + ".bak"
		if FileAccess.file_exists(backup_path):
			if DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path)) != OK:
				error = "write_failed"
				return false
		if DirAccess.rename_absolute(absolute_path, ProjectSettings.globalize_path(backup_path)) != OK:
			error = "write_failed"
			return false
	if FileAccess.file_exists(path):
		# A file appeared after the observation/rotation checks. Preserve it.
		error = "changed"
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), absolute_path) != OK:
		error = "write_failed"
		return false

	if FileAccess.file_exists(pending_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending_path))
	_capture_observation()
	_write_permitted = true
	error = ""
	return true

func _capture_observation() -> void:
	_observed_files.clear()
	_observation_hashes_valid = true
	for candidate: String in [path, path + ".bak", path + ".tmp", path + ".pending"]:
		var present: bool = FileAccess.file_exists(candidate)
		var digest: String = _digest_file(candidate) if present else ""
		if present and digest.is_empty():
			_observation_hashes_valid = false
		_observed_files[candidate] = {
			"present": present,
			"digest": digest
		}

func _matches_observation(excluded_paths: Array = []) -> bool:
	if not _observation_hashes_valid:
		return false
	for candidate: String in _observed_files:
		if excluded_paths.has(candidate):
			continue
		var expected: Dictionary = _observed_files[candidate]
		var present: bool = FileAccess.file_exists(candidate)
		if present != bool(expected.get("present", false)):
			return false
		if present and _digest_file(candidate) != str(expected.get("digest", "")):
			return false
	return true

func _matches_primary_and_backup() -> bool:
	for candidate: String in [path, path + ".bak"]:
		var expected: Dictionary = _observed_files.get(candidate, {})
		var present: bool = FileAccess.file_exists(candidate)
		if present != bool(expected.get("present", false)):
			return false
		if present and _digest_file(candidate) != str(expected.get("digest", "")):
			return false
	return true

func _read_candidate(source: String, validator: Callable) -> Dictionary:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "invalid"}
	var length: int = file.get_length()
	if length > MAX_FILE_BYTES:
		file.close()
		return {"ok": false, "error": "size_limit"}
	var bytes: PackedByteArray = file.get_buffer(length)
	file.close()
	if bytes.size() != length:
		return {"ok": false, "error": "invalid"}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "invalid"}
	if not _is_json_value(json.data):
		return {"ok": false, "error": "invalid"}
	var validation: Variant = validator.call(json.data)
	if typeof(validation) != TYPE_BOOL or not validation:
		return {"ok": false, "error": "unsupported"}
	return {
		"ok": true,
		"snapshot": json.data,
		"digest": _digest_bytes(bytes)
	}

func _write_text(destination: String, contents: String) -> bool:
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(contents)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	return write_error == OK

func _digest_file(source: String) -> String:
	return FileAccess.get_sha256(source)

func _digest_bytes(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(bytes)
	return hashing.finish().hex_encode()

func _is_json_value(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_JSON_NESTING:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item: Variant in value:
				if not _is_json_value(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) != TYPE_STRING or not _is_json_value(value[key], depth + 1):
					return false
			return true
		_:
			return false
