extends RefCounted

## Small disk boundary for the city snapshot. Snapshot meaning and schema
## validation belong to the caller; this class only protects the JSON files.
const DEFAULT_PATH: String = "user://city_save/checkpoint_v1.json"
const MAX_FILE_BYTES: int = 8 * 1024 * 1024
const MAX_JSON_NESTING: int = 128
const HASH_CHUNK_BYTES: int = 64 * 1024

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
		var primary: Dictionary = _checked_candidate(path, validator)
		if not bool(primary.get("ok", false)):
			error = str(primary.get("error", "invalid"))
			return {}
		_write_permitted = true
		return primary["snapshot"]
	if bool(_observed_files[path].get("present", false)):
		error = "changed"
		return {}

	var found_candidate: bool = false
	for source: String in [path + ".tmp", path + ".pending", path + ".bak"]:
		if not FileAccess.file_exists(source):
			if bool(_observed_files[source].get("present", false)):
				error = "changed"
				return {}
			continue
		found_candidate = true
		var recovery: Dictionary = _checked_candidate(source, validator)
		if recovery.get("error") in ["read_failed", "changed"]:
			error = recovery.error
			return {}
		if bool(recovery.get("ok", false)):
			_write_permitted = true
			return recovery["snapshot"]
	if found_candidate:
		error = "invalid_recovery"
		return {}
	error = "missing"
	_write_permitted = true
	return {}

## Inspect every recovery candidate without changing the observed slot or the
## selected snapshot. The caller can record any validation-specific concern.
func inspect_recovery_candidates(validator: Callable) -> String:
	if not validator.is_valid():
		return "invalid_validator"
	if not _observation_ready or not _observation_hashes_valid:
		return "changed"
	for source: String in [path + ".tmp", path + ".pending", path + ".bak"]:
		var present: bool = FileAccess.file_exists(source)
		if present != bool(_observed_files[source].get("present", false)):
			return "changed"
		if present:
			var result: Dictionary = _checked_candidate(source, validator)
			if result.get("error") in ["read_failed", "changed"]:
				return result.error
	return ""

func observation_is_current() -> bool:
	return _observation_ready and _matches_observation()

func _checked_candidate(source: String, validator: Callable) -> Dictionary:
	var observed: Dictionary = _observed_files.get(source, {})
	if not _observation_hashes_valid or not bool(observed.get("present", false)):
		return {"ok": false, "error": "changed"}
	var result: Dictionary = _read_candidate(source, validator)
	if result.get("error") == "read_failed":
		return result
	if str(result.get("digest", "")) != str(observed.get("digest", "")):
		return {"ok": false, "error": "changed"}
	return result

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
		return {"ok": false, "error": "read_failed"}
	var length: int = file.get_length()
	if length > MAX_FILE_BYTES:
		# Confirm the rejected candidate is the observed file without loading an
		# oversized buffer; otherwise a replaced file could be silently skipped.
		var oversized_digest: String = _digest_open_file(file, length)
		file.close()
		if oversized_digest.is_empty():
			return {"ok": false, "error": "read_failed"}
		return {"ok": false, "error": "size_limit", "digest": oversized_digest}
	var bytes: PackedByteArray = file.get_buffer(length)
	var read_error: Error = file.get_error()
	file.close()
	if bytes.size() != length or read_error not in [OK, ERR_FILE_EOF]:
		return {"ok": false, "error": "read_failed"}
	var digest: String = _digest_bytes(bytes)
	if digest.is_empty():
		return {"ok": false, "error": "read_failed"}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "invalid", "digest": digest}
	if not _is_json_value(json.data):
		return {"ok": false, "error": "invalid", "digest": digest}
	var validation: Variant = validator.call(json.data)
	if typeof(validation) != TYPE_BOOL or not validation:
		return {"ok": false, "error": "unsupported", "digest": digest}
	return {
		"ok": true,
		"snapshot": json.data,
		"digest": digest
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
	if hashing.update(bytes) != OK:
		return ""
	return hashing.finish().hex_encode()

func _digest_open_file(file: FileAccess, length: int) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	var remaining: int = length
	while remaining > 0:
		var requested: int = mini(remaining, HASH_CHUNK_BYTES)
		var chunk: PackedByteArray = file.get_buffer(requested)
		if chunk.size() != requested or file.get_error() not in [OK, ERR_FILE_EOF] or hashing.update(chunk) != OK:
			return ""
		remaining -= chunk.size()
	if file.get_length() != length:
		return ""
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
