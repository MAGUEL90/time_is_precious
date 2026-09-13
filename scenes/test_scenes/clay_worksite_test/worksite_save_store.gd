extends Node

## Disk boundary for one explicitly enabled prototype scene. The save path is
## configured by local code only, never read from a snapshot.
signal status_changed(message: String)
const STATE = preload("res://scenes/test_scenes/clay_worksite_test/worksite_save_state.gd")
const DEFAULT_PATH: String = "user://worksite_mvp/save_v1.json"
const MAX_FILE_BYTES: int = 2 * 1024 * 1024
var path: String = DEFAULT_PATH
var fixture: Node
var destinations: Dictionary = {}
var codec = STATE.new()
var enabled: bool = false
var blocked: bool = false
var status: String = ""
var _last_written: String = ""
var _elapsed: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func start(target: Node, registry: Dictionary) -> String:
	fixture = target
	destinations = registry
	enabled = true
	var result: String = load_now()
	if result == "missing":
		save_now()
	return result

func _process(delta: float) -> void:
	if not enabled or blocked:
		return
	_elapsed += delta
	if _elapsed >= 0.5:
		_elapsed = 0.0
		save_now()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and enabled and not blocked:
		save_now()

func save_now() -> bool:
	if not enabled or blocked or not is_instance_valid(fixture) or fixture._working or fixture.is_queued_for_deletion():
		return false
	for worker: WorkerData in WorkerDatabase.get_all_workers():
		if not worker.current_order_id.is_empty():
			var site_id: StringName = fixture.worker_management.assigned_site(worker.worker_id)
			if site_id.is_empty() or fixture.daily.jobs[site_id].order != worker.current_order_id:
				return _block("A job outside this prototype cannot be saved in the worksite slot.")
	var snapshot: Dictionary = codec.capture(fixture, destinations)
	if not codec.validate(snapshot, fixture, destinations):
		return _block("Save stopped: " + codec.error)
	var serialized: String = JSON.stringify(snapshot, "\t", true, true)
	if serialized == _last_written:
		return true
	var absolute: String = ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		return _block("Cannot create the save folder.")
	# Protect a save changed externally since the last read, including a file
	# from a second game instance. Never silently replace another session.
	if FileAccess.file_exists(path):
		var current: Dictionary = _read(path)
		if current.is_empty() or FileAccess.get_file_as_string(path) != _last_written:
			return _block("Save changed outside this session; existing file preserved.")
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _block("Cannot write the save file.")
	file.store_string(serialized)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or _read(temporary).is_empty():
		return _block("Save verification failed; previous save preserved.")
	if FileAccess.file_exists(path):
		if DirAccess.rename_absolute(absolute, absolute + ".bak") != OK:
			return _block("Cannot retain the previous save backup.")
	if DirAccess.rename_absolute(absolute + ".tmp", absolute) != OK:
		return _block("Cannot finish saving; the previous snapshot remains in .bak.")
	_last_written = serialized
	_set_status("Saved")
	return true

func load_now() -> String:
	if not enabled or not is_instance_valid(fixture) or fixture._working:
		return "unavailable"
	var source: String = path
	if not FileAccess.file_exists(source):
		# An interrupted rotation can leave only a valid backup. Do not mistake
		# that for a fresh game and overwrite it with the seed fixture.
		if FileAccess.file_exists(path + ".bak"):
			source = path + ".bak"
		elif FileAccess.file_exists(path + ".tmp"):
			source = path + ".tmp"
		else:
			_set_status("New game")
			return "missing"
	var snapshot: Dictionary = _read(source)
	if snapshot.is_empty() or not codec.restore(snapshot, fixture, destinations):
		_block("Load stopped: " + codec.error + " Existing save preserved.")
		return "invalid"
	blocked = false
	_last_written = FileAccess.get_file_as_string(path) if source == path else ""
	_set_status("Loaded" if source == path else "Recovered backup")
	if source != path:
		# Do not copy over the recovery source: write a new verified primary.
		save_now()
	return "loaded"

func _read(source: String) -> Dictionary:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		codec.error = "Save is unreadable or too large."
		return {}
	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		codec.error = "Invalid JSON."
		return {}
	if not codec.validate(json.data, fixture, destinations):
		return {}
	return json.data

func _block(message: String) -> bool:
	blocked = true
	_set_status(message)
	push_warning(message + " " + ProjectSettings.globalize_path(path))
	return false

func _set_status(message: String) -> void:
	status = message
	status_changed.emit(message)
