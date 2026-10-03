extends Node

## One authored workshop plot. Hosted by WorkStateRuntime so scene changes do not reset it.
## Building is not a production order: it has no item output, escrow, or fee.
signal changed()

const REQUIREMENTS: Dictionary = {"wood_log": 6, "clay_lump": 12, "reed_bundle": 8}
const SOLO_MINUTES: int = 3 * 24 * 60
const ORDER_ID: String = "construction:main_workshop"

const CLEARING_MINUTES: int = 180

var order_id: String = ORDER_ID

var phase: String = "uncleared"
var clearing_remaining: int = CLEARING_MINUTES
var clearing_by_player: bool = false
var worker_ids: Array[String] = []
var started_at: int = 0
var completes_at: int = 0
var _latest_time: int = 0
var _starting: bool = false

func _ready() -> void:
	TimeComponentManager.time_changed.connect(_on_time_changed)
	_latest_time = _now()

func get_requirements() -> Dictionary:
	return REQUIREMENTS.duplicate()

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _worker_reason(id: String) -> String:
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if worker == null:
		return "Worker unavailable."
	if worker.is_reserved() or worker.current_work_status != WorkerData.WorkStatus.IDLE:
		return "Worker is busy."
	var citizen: CitizenData = worker.get_linked_citizen()
	if citizen != null and not citizen.can_be_assigned():
		return "Worker is already assigned or unavailable."
	return ""

func get_worker_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for worker: WorkerData in WorkerDatabase.get_all_workers():
		var reason: String = _worker_reason(worker.worker_id)
		options.append({"id": worker.worker_id, "name": worker.get_resolved_display_name(), "available": reason.is_empty(), "reason": reason})
	return options

func get_preview(selected_ids: Array[String]) -> Dictionary:
	var message: String = ""
	var unique: Array[String] = []
	for id: String in selected_ids:
		if unique.has(id):
			message = "Select each worker only once."
			break
		unique.append(id)
		var reason: String = _worker_reason(id)
		if not reason.is_empty():
			message = reason
			break
	if selected_ids.is_empty():
		message = "Select available workers."
	for id: String in REQUIREMENTS:
		if not Inventory.has_item(id, int(REQUIREMENTS[id])) and message.is_empty():
			message = "Missing materials in Inventory."
	if phase != "empty":
		message = "Clear the site first." if phase in ["uncleared", "clearing"] else ("Construction in progress." if phase == "building" else "Workshop ready.")
	elif _starting:
		message = "Starting construction."
	var duration: int = ceili(float(SOLO_MINUTES) / selected_ids.size()) if not selected_ids.is_empty() else 0
	var remaining: int = maxi(completes_at - _latest_time, 0) if phase == "building" else 0
	var progress: float = 0.0
	if phase == "building":
		progress = clampf(float(_latest_time - started_at) / maxi(completes_at - started_at, 1), 0.0, 1.0)
	elif phase == "built":
		progress = 1.0
	return {"phase": phase, "can_start": message.is_empty(), "message": message, "duration_minutes": duration, "remaining_minutes": remaining, "progress_ratio": progress, "worker_count": worker_ids.size() if phase != "empty" else selected_ids.size()}

func start_build(selected_ids: Array[String]) -> Dictionary:
	var preview: Dictionary = get_preview(selected_ids)
	if not bool(preview.can_start):
		return {"success": false, "message": preview.message}
	_starting = true
	var reserved: Array[String] = []
	for id: String in selected_ids:
		if not _worker_reason(id).is_empty() or not WorkerDatabase.assign_worker(id):
			_release_workers(reserved)
			_starting = false
			return {"success": false, "message": "Worker availability changed."}
		WorkerDatabase.get_worker_data(id).start_work(order_id, "Build Workshop")
		reserved.append(id)
	var consumed: Dictionary = {}
	for id: String in REQUIREMENTS:
		var quantity: int = int(REQUIREMENTS[id])
		if not Inventory.remove_item(id, quantity):
			for consumed_id: String in consumed:
				Inventory.add_item(consumed_id, int(consumed[consumed_id]))
			_release_workers(reserved)
			_starting = false
			return {"success": false, "message": "Materials changed; construction was not started."}
		consumed[id] = quantity
	worker_ids = reserved
	started_at = _now()
	_latest_time = started_at
	completes_at = started_at + int(preview.duration_minutes)
	phase = "building"
	_starting = false
	changed.emit()
	return {"success": true, "message": "Construction started."}

func _on_time_changed(day: int, hour: int, minute: int, _weather: String) -> void:
	if phase not in ["building", "clearing"]:
		return
	var next_time: int = day * 1440 + hour * 60 + minute
	if next_time <= _latest_time:
		return
	_latest_time = next_time
	if _latest_time >= completes_at:
		phase = "empty" if phase == "clearing" else "built"
		clearing_remaining = 0
		clearing_by_player = false
		_release_workers(worker_ids)
	changed.emit()

func _release_workers(ids: Array[String]) -> void:
	for id: String in ids:
		var worker: WorkerData = WorkerDatabase.get_worker_data(id)
		if worker != null and worker.current_order_id == order_id:
			worker.finish_work(order_id)
			WorkerDatabase.unassign_worker(id)

func _exit_tree() -> void:
	# Runtime host normally outlives all maps. Release reservations on shutdown/test teardown.
	if phase in ["building", "clearing"]:
		_release_workers(worker_ids)

func get_clearing_preview(ids: Array[String], use_player: bool) -> Dictionary:
	var message: String = ""
	if phase != "uncleared":
		message = "Clearing in progress." if phase == "clearing" else "Site is already clear."
	elif use_player and not ids.is_empty():
		message = "Choose player or one worker."
	elif not use_player:
		if ids.size() != 1:
			message = "Assign player or one worker."
		else:
			message = _worker_reason(ids[0])
	var remaining: int = maxi(completes_at - _latest_time, 0) if phase == "clearing" else clearing_remaining
	var progress: float = 1.0 - float(remaining) / CLEARING_MINUTES
	return {"can_start": message.is_empty(), "message": message, "duration_minutes": clearing_remaining,
		"remaining_minutes": remaining, "progress_ratio": progress, "worker_count": 1}

func start_clearing(ids: Array[String], use_player: bool) -> Dictionary:
	var preview: Dictionary = get_clearing_preview(ids, use_player)
	if not bool(preview.can_start):
		return {"success": false, "message": preview.message}
	if not use_player:
		if not WorkerDatabase.assign_worker(ids[0]):
			return {"success": false, "message": "Worker unavailable."}
		WorkerDatabase.get_worker_data(ids[0]).start_work(order_id, "Clear Workshop Site")
	worker_ids = ids.duplicate()
	clearing_by_player = use_player
	started_at = _now()
	_latest_time = started_at
	completes_at = started_at + clearing_remaining
	phase = "clearing"
	changed.emit()
	return {"success": true, "message": "Clearing started."}

func interrupt_player_clearing() -> void:
	if phase != "clearing" or not clearing_by_player:
		return
	clearing_remaining = maxi(completes_at - _latest_time, 0)
	phase = "uncleared"
	clearing_by_player = false
	changed.emit()
