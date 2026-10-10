extends Node

## One manual checkpoint. This lives in the existing WorkStateRuntime host.
signal changed
const SNAPSHOT = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const FILE = preload("res://scenes/new_scenes/save_game/city_save_file.gd")
var disk = FILE.new()
var snapshot = SNAPSHOT.new()
var map: Node
var status: String = ""
var last_error: String = ""
var _observed_path: String = ""
var _busy: bool = false

func bind_map(next_map: Node) -> void:
	map = next_map
	var ui := WorkStateRuntime.get_node_or_null("CityRaid/RaidUI") as RaidUI
	if ui != null:
		ui.bind_save_store(self)

func has_checkpoint() -> bool:
	return disk.exists()

func save_checkpoint() -> bool:
	if not _can_run():
		return false
	_busy = true
	# Observe an existing slot before the first replacement, without applying it.
	if _observed_path != disk.path:
		disk.read_snapshot(_validate)
		_observed_path = disk.path
		if not disk.error.is_empty() and disk.error != "missing":
			return _failed(disk.error)
	var document: Dictionary = snapshot.capture(map)
	if document.is_empty():
		return _failed(snapshot.error)
	if not disk.write_snapshot(document, _validate):
		return _failed(disk.error + ": " + snapshot.error)
	_busy = false
	status = "Saved"
	last_error = ""
	changed.emit()
	return true

func load_checkpoint() -> bool:
	if not _can_run():
		return false
	_busy = true
	var document: Dictionary = disk.read_snapshot(_validate)
	_observed_path = disk.path
	if document.is_empty():
		return _failed(disk.error)
	# The disk boundary may inspect several recovery candidates. Prepare the
	# selected document again so staged data always belongs to that document.
	if not snapshot.prepare(document, map):
		return _failed(snapshot.error)
	snapshot.apply_prepared(map)
	_busy = false
	status = "Loaded"
	last_error = ""
	changed.emit()
	return true

func _validate(document: Dictionary) -> bool:
	return snapshot.prepare(document, map)

func _can_run() -> bool:
	if _busy:
		return false
	var reason: String = snapshot.busy_reason(map)
	if not reason.is_empty():
		return _failed(reason)
	return true

func _failed(reason: String) -> bool:
	_busy = false
	last_error = reason
	if reason == "missing":
		status = "No save"
	elif reason.begins_with("changed"):
		status = "File changed"
	elif reason.begins_with("Finish") or reason.begins_with("Wait") or reason.begins_with("Return"):
		status = "Unavailable"
	else:
		status = "Invalid save"
	push_warning("City checkpoint: " + reason)
	changed.emit()
	return false
