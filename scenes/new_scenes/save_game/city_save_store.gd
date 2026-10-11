extends Node

## One checkpoint, also written after successful sleep. This lives in the existing WorkStateRuntime host.
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
var parked_worksite: Node
var city_plots: Dictionary = {}
var city_drops: Array = []
var _departing_map: Node
var _pending_home_position: Variant = null
var _parked_layers: Dictionary = {}
var _resume_clock_after_load: bool = false

func _ready() -> void:
	get_tree().scene_changed.connect(_on_scene_changed)

func bind_map(next_map: Node) -> void:
	map = next_map
	if not snapshot.is_home(map):
		_restore_parked_worksite(map)
		city_plots = snapshot.plots(map)
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
	if snapshot.is_home(map):
		return _failed("Return to the city to load.")
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
	var return_home: bool = snapshot.prepared_location == "home"
	_pending_home_position = snapshot.prepared.player.global_position if return_home else null
	if return_home:
		_resume_clock_after_load = TimeComponentManager.is_processing()
		TimeComponentManager.set_process(false)
	snapshot.apply_prepared(map, not return_home)
	if return_home:
		WorkStateRuntime.get_node("CityRaid").set_process(false)
		status = "Loading"
		map.get_node("YSortWorld/Player").set_movement_locked(&"checkpoint", true)
		_return_home_after_load.call_deferred()
		changed.emit()
		return true
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

func save_after_sleep(player: Player) -> bool:
	var scene: Node = get_tree().current_scene
	if not is_instance_valid(scene) or not scene.is_ancestor_of(player):
		return _failed("Return to the city first.")
	if snapshot.is_home(scene):
		map = scene
	if not is_instance_valid(map) or map.get_node_or_null("YSortWorld/Player") != player:
		return _failed("Return to the city first.")
	return save_checkpoint()

func prepare_home_departure(scene: Node, target_path: String) -> bool:
	# Only the authored city/home pair needs this handoff. Resolve the editor's
	# UID reference without loading an arbitrary save-controlled path.
	var resolved: String = ResourceUID.get_id_path(ResourceUID.text_to_id(target_path)) if target_path.begins_with("uid://") else target_path
	if resolved != snapshot.HOME_PATH or scene != map or not is_instance_valid(map) or snapshot.is_home(map):
		return true
	var runtime: Node = map.get_node_or_null("YSortWorld/WorkerRuntime")
	if runtime == null or runtime._working:
		return _failed("Finish gathering first.")
	var check: Dictionary = snapshot._sites.capture(runtime)
	if check.is_empty():
		return _failed(snapshot._sites.error)
	city_plots = snapshot.plots(map)
	city_drops = snapshot._capture_city_drops(map)
	_departing_map = map
	parked_worksite = runtime
	# Retain the tested daily/hauling scheduler and its endpoints. Rendering,
	# input and physics stop; minute signals continue the same work rules.
	runtime.checkpoint_handoff = true
	runtime.reparent(self, true)
	runtime.process_mode = Node.PROCESS_MODE_DISABLED
	runtime.hide()
	for layer: Node in runtime.find_children("*", "CanvasLayer", true, false):
		_parked_layers[layer] = layer.visible
		layer.hide()
	return true

func cancel_home_departure() -> void:
	if not is_instance_valid(_departing_map) or not is_instance_valid(parked_worksite):
		return
	parked_worksite.reparent(_departing_map.get_node("YSortWorld"), true)
	parked_worksite.checkpoint_handoff = false
	parked_worksite.process_mode = Node.PROCESS_MODE_INHERIT
	parked_worksite.show()
	for layer: Node in _parked_layers:
		layer.visible = _parked_layers[layer]
	_parked_layers.clear()
	parked_worksite = null
	_departing_map = null
	city_drops.clear()

func _restore_parked_worksite(city_map: Node) -> void:
	if not is_instance_valid(parked_worksite):
		return
	var next_runtime: Node = city_map.get_node_or_null("YSortWorld/WorkerRuntime")
	if next_runtime == null or next_runtime == parked_worksite:
		return
	var data: Dictionary = snapshot._sites.capture(parked_worksite)
	if data.is_empty() or not snapshot._sites.validate(data, next_runtime, WorkerDatabase.workers_by_id, WorkerDatabase.dismissed_workers):
		_failed("Could not return city work state: " + snapshot._sites.error)
		return
	snapshot._sites.restore(data, next_runtime)
	# The fresh map now owns the jobs. Do not release its workers while disposing
	# the old hidden projection; normal teardown still disconnects callbacks.
	parked_worksite.daily.jobs.clear()
	parked_worksite.hauling.routes.clear()
	parked_worksite.retain_resource_stock = false
	parked_worksite.checkpoint_handoff = false
	parked_worksite.free()
	_parked_layers.clear()
	parked_worksite = null
	snapshot._restore_city_drops(city_drops, city_map)
	city_drops.clear()
	_departing_map = null

func _on_scene_changed() -> void:
	var scene: Node = get_tree().current_scene
	if snapshot.is_home(scene):
		map = scene
		if _pending_home_position is Vector2:
			scene.get_node("SpawnPoints/WakeUpPoint").global_position = _pending_home_position

func _return_home_after_load() -> void:
	# Validate in the city first, then use the normal home fade. Loading itself
	# must not advance another game minute or another raid hit.
	var raid: Node = WorkStateRuntime.get_node("CityRaid")
	TimeComponentManager.set_process(false)
	raid.set_process(false)
	var completed: bool = await SceneTransition.run_with_fade(_change_to_saved_home, 0.35, 0.15)
	TimeComponentManager.set_process(_resume_clock_after_load)
	raid.set_process(raid.is_raid_active())
	_busy = false
	_pending_home_position = null
	if completed:
		status = "Loaded"
		last_error = ""
	else:
		if is_instance_valid(map):
			map.get_node("YSortWorld/Player").set_movement_locked(&"checkpoint", false)
		_failed("Could not open the saved home.")
	changed.emit()

func _change_to_saved_home() -> bool:
	if not prepare_home_departure(map, snapshot.HOME_PATH):
		return false
	SceneTransition.queue_spawn_point(&"WakeUpPoint")
	var result: Error = get_tree().change_scene_to_file(snapshot.HOME_PATH)
	if result != OK:
		SceneTransition.clear_spawn_point()
		cancel_home_departure()
	return result == OK
