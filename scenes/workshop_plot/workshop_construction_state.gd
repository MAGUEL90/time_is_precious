extends Node

## One authored workshop plot. Hosted by WorkStateRuntime so scene changes do not reset it.
## Building is not a production order: it has no item output, escrow, or fee.
signal changed()

const REQUIREMENTS: Dictionary = {"wood_log": 6, "clay_lump": 12, "reed_bundle": 8}
const SOLO_MINUTES: int = 3 * 24 * 60
const ORDER_ID: String = "construction:main_workshop"
const MAX_WORKER_CAPACITY: int = 10000
const CITIZEN_HOUSE_ORDER_ID: String = "construction:citizen_house_1"
const CITIZEN_HOUSE_REQUIREMENTS: Dictionary = {"wood_log": 4, "clay_lump": 8, "reed_bundle": 6}
const CITIZEN_HOUSE_SOLO_MINUTES: int = 2880
const CITIZEN_HOUSE_SHELTER_CAPACITY: int = 3

const CLEARING_MINUTES: int = 180
const SHIFT_START: int = 7 * 60
const SHIFT_END: int = 15 * 60

var order_id: String = ORDER_ID

var phase: String = "uncleared"
var clearing_remaining: int = CLEARING_MINUTES
var clearing_by_player: bool = false
# Manual house building is a transient session. A paused building keeps its
# ordinary workerless construction record, so no save schema change is needed.
var player_building: bool = false
var _player_interrupt_pending: bool = false
var worker_ids: Array[String] = []
# The original team size bounds replacements; total work stays fixed when the
# current team changes. Both values are persisted with the construction state.
var worker_capacity: int = 0
var work_total_units: int = 0
var started_at: int = 0
var completes_at: int = 0
var _latest_time: int = 0
var _starting: bool = false
# Fractional team progress, in worker-minutes modulo the assigned team size.
var payroll_work_remainder: int = 0
# Authored spatial binding survives the map being replaced by the home interior.
# Save data validates approach targets against this value; it never supplies it.
var worker_entry_position: Vector2 = Vector2.ZERO
# Plot kind is authored by the view, never read from a checkpoint. Keep the
# owner while the view is absent so offscreen construction retains its kind.
var _plot_kind_bound: bool = false
var _citizen_house_plot: bool = false
var _active_plot_view: WeakRef

func _ready() -> void:
	TimeComponentManager.time_changed.connect(_on_time_changed)
	WorkerDatabase.payroll_settling.connect(_flush_payroll_boundary)
	WorkerDatabase.payroll_changed.connect(_refresh_payroll_status)
	_latest_time = _now()

func is_citizen_house() -> bool:
	if _plot_kind_bound:
		return _citizen_house_plot
	# Legacy standalone state fixtures predate authored plot-kind binding.
	return order_id == CITIZEN_HOUSE_ORDER_ID


func bind_plot_view(view: Node, citizen_house: bool) -> bool:
	if not is_instance_valid(view) or not view.is_inside_tree():
		return false
	var current: Node = _active_plot_view.get_ref() as Node if _active_plot_view != null else null
	if is_instance_valid(current) and current != view and current.is_inside_tree():
		return false
	# A retained owner must not silently become a different building after a
	# scene handoff or when two authored plots use the same identity.
	if _plot_kind_bound and _citizen_house_plot != citizen_house:
		return false
	_plot_kind_bound = true
	_citizen_house_plot = citizen_house
	_active_plot_view = weakref(view)
	return true


func unbind_plot_view(view: Node) -> void:
	if _active_plot_view != null and _active_plot_view.get_ref() == view:
		_active_plot_view = null

func get_requirements() -> Dictionary:
	return (CITIZEN_HOUSE_REQUIREMENTS if is_citizen_house() else REQUIREMENTS).duplicate()

func get_solo_minutes() -> int:
	return CITIZEN_HOUSE_SOLO_MINUTES if is_citizen_house() else SOLO_MINUTES

func _worker_job_label(clearing: bool) -> String:
	if is_citizen_house():
		return "Clear House Site" if clearing else "Build House"
	return "Clear Workshop Site" if clearing else "Build Workshop"

func _has_shelter_room() -> bool:
	if not is_citizen_house():
		return true
	return CityStockManager.shelter_capacity >= 0 and CityStockManager.shelter_capacity <= CityStockManager.MAX_SHELTER_CAPACITY - CITIZEN_HOUSE_SHELTER_CAPACITY

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func is_transaction_busy() -> bool:
	return _starting

func is_player_work_active() -> bool:
	return clearing_by_player or player_building

func _finish_transaction() -> void:
	_starting = false
	if _player_interrupt_pending:
		_player_interrupt_pending = false
		if is_player_work_active():
			interrupt_player_work()
			return
	WorkerDatabase.on_work_owner_transaction_finished()

func _worker_reason(id: String) -> String:
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if worker == null:
		return "Worker unavailable."
	if worker.resignation_pending or worker.get_resolved_satisfaction() <= 0.0:
		return "Worker unavailable."
	if worker.is_payroll_blocked():
		return worker.get_onboarding_status()
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

func get_preview(selected_ids: Array[String], use_player: bool = false) -> Dictionary:
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
	if use_player and (not is_citizen_house() or not selected_ids.is_empty()):
		message = "Choose player or workers."
	elif selected_ids.is_empty() and not use_player:
		message = "Select available workers."
	elif selected_ids.size() > MAX_WORKER_CAPACITY:
		message = "Too many workers selected."
	var requirements: Dictionary = get_requirements()
	for id: String in requirements:
		if not Inventory.has_item(id, int(requirements[id])) and message.is_empty():
			message = "Missing materials in Inventory."
	if phase == "empty" and not _has_shelter_room() and message.is_empty():
		message = "Shelter capacity is full."
	if phase != "empty":
		message = "Clear the site first." if phase in ["uncleared", "clearing"] else ("Construction in progress." if phase == "building" else ("House ready." if is_citizen_house() else "Workshop ready."))
	var payroll_blocked: bool = phase == "building" and _all_workers_payroll_blocked()
	var shelter_blocked: bool = phase == "building" and is_citizen_house() and _remaining_work_units() <= 1 and not _has_shelter_room()
	if payroll_blocked:
		message = "Contract expired - renew in Worker Hub."
	elif shelter_blocked:
		message = "Shelter capacity is full; construction paused."
	elif _starting:
		message = "Starting construction."
	var duration: int = get_solo_minutes() if use_player and is_citizen_house() else (ceili(float(get_solo_minutes()) / selected_ids.size()) if not selected_ids.is_empty() else 0)
	var remaining: int = maxi(completes_at - _latest_time, 0) if phase == "building" else 0
	var progress: float = 0.0
	if phase == "building":
		var total_units: int = work_total_units if work_total_units > 0 else maxi(1, (completes_at - started_at) * maxi(1, worker_ids.size()))
		progress = clampf(1.0 - float(_remaining_work_units()) / float(total_units), 0.0, 1.0)
	elif phase == "built":
		progress = 1.0
	var preview: Dictionary = {"phase": phase, "can_start": message.is_empty(), "message": message, "duration_minutes": duration, "remaining_minutes": remaining, "progress_ratio": progress, "worker_count": (1 if player_building else worker_ids.size()) if phase != "empty" else (1 if use_player else selected_ids.size()), "payroll_blocked": payroll_blocked}
	if is_citizen_house():
		preview["shelter_blocked"] = shelter_blocked
	return preview

func start_build(selected_ids: Array[String], use_player: bool = false) -> Dictionary:
	if _starting:
		return {"success": false, "message": "Starting construction."}
	var preview: Dictionary = get_preview(selected_ids, use_player)
	if not bool(preview.can_start):
		return {"success": false, "message": preview.message}
	var requirements: Dictionary = get_requirements()
	if not Inventory.can_consume_bulk_items(requirements):
		return {"success": false, "message": "Materials changed; construction was not started."}
	if not _has_shelter_room():
		return {"success": false, "message": "Shelter capacity is full; construction was not started."}
	_starting = true
	var reserved: Array[String] = []
	for id: String in selected_ids:
		if not _worker_reason(id).is_empty() or not WorkerDatabase.assign_worker(id):
			_release_workers(reserved)
			_finish_transaction()
			return {"success": false, "message": "Worker availability changed."}
		WorkerDatabase.get_worker_data(id).start_work(order_id, _worker_job_label(false))
		reserved.append(id)
	var payment_available: bool = Inventory.can_consume_bulk_items(requirements)
	var shelter_available: bool = _has_shelter_room()
	var workers_reserved: bool = _start_workers_are_reserved(reserved)
	if not payment_available or not shelter_available or not workers_reserved:
		_release_workers(reserved)
		_finish_transaction()
		if not shelter_available:
			return {"success": false, "message": "Shelter capacity is full; construction was not started."}
		if not payment_available:
			return {"success": false, "message": "Materials changed; construction was not started."}
		return {"success": false, "message": "Worker availability changed."}
	# Keep a complete pre-payment snapshot so an unexpected bulk rejection can
	# restore the cleared plot without leaving a paid-looking or reserved job.
	var previous_phase: String = phase
	var previous_worker_ids: Array[String] = worker_ids.duplicate()
	var previous_worker_capacity: int = worker_capacity
	var previous_work_total_units: int = work_total_units
	var previous_started_at: int = started_at
	var previous_completes_at: int = completes_at
	var previous_latest_time: int = _latest_time
	var previous_payroll_work_remainder: int = payroll_work_remainder
	var previous_player_building: bool = player_building
	worker_ids = reserved
	worker_capacity = 1 if use_player else reserved.size()
	started_at = _now()
	_latest_time = started_at
	completes_at = started_at + int(preview.duration_minutes)
	work_total_units = CITIZEN_HOUSE_SOLO_MINUTES if is_citizen_house() else int(preview.duration_minutes) * worker_capacity
	# House work is exactly 2880 worker-minutes even if the team size does not
	# divide it evenly. Existing workshops keep their original rounded total.
	payroll_work_remainder = int(preview.duration_minutes) * worker_capacity - work_total_units
	player_building = use_player
	phase = "building"
	if not use_player:
		_initialize_approaches()
	# Route setup can call scene code, so validate every mutable precondition
	# again immediately before the one all-or-nothing debit.
	payment_available = Inventory.can_consume_bulk_items(requirements)
	shelter_available = _has_shelter_room()
	workers_reserved = _start_workers_are_reserved(reserved)
	if not payment_available or not shelter_available or not workers_reserved:
		_release_workers(reserved)
		phase = previous_phase
		worker_ids = previous_worker_ids
		worker_capacity = previous_worker_capacity
		work_total_units = previous_work_total_units
		started_at = previous_started_at
		completes_at = previous_completes_at
		_latest_time = previous_latest_time
		payroll_work_remainder = previous_payroll_work_remainder
		player_building = previous_player_building
		_finish_transaction()
		if not shelter_available:
			return {"success": false, "message": "Shelter capacity is full; construction was not started."}
		if not payment_available:
			return {"success": false, "message": "Materials changed; construction was not started."}
		return {"success": false, "message": "Worker availability changed."}
	# The state and reservations are already committed when Inventory emits its
	# single notification. Reentrant callbacks are blocked by _starting and the
	# Inventory bulk guard; later capacity changes affect progress, not payment.
	if not Inventory.consume_bulk_items(requirements):
		_release_workers(reserved)
		phase = previous_phase
		worker_ids = previous_worker_ids
		worker_capacity = previous_worker_capacity
		work_total_units = previous_work_total_units
		started_at = previous_started_at
		completes_at = previous_completes_at
		_latest_time = previous_latest_time
		payroll_work_remainder = previous_payroll_work_remainder
		player_building = previous_player_building
		_finish_transaction()
		return {"success": false, "message": "Materials changed; construction was not started."}
	changed.emit()
	_finish_transaction()
	return {"success": true, "message": "Construction started."}


func _start_workers_are_reserved(ids: Array[String]) -> bool:
	for id: String in ids:
		var worker: WorkerData = WorkerDatabase.get_worker_data(id)
		if worker == null or worker.current_order_id != order_id or worker.current_job_id != _worker_job_label(false) or not worker.is_reserved():
			return false
		var citizen: CitizenData = worker.get_linked_citizen()
		if citizen != null and citizen.employment_status != CitizenData.EmploymentStatus.ASSIGNED:
			return false
	return true

func _on_time_changed(day: int, hour: int, minute: int, _weather: String) -> void:
	if phase not in ["building", "clearing"]:
		return
	var next_time: int = day * 1440 + hour * 60 + minute
	if next_time <= _latest_time:
		return
	var elapsed: int = next_time - _latest_time
	if not is_player_work_active():
		var worked: int = 0
		var minute_of_day: int = _latest_time % 1440
		var on_shift: bool = minute_of_day >= SHIFT_START and minute_of_day < SHIFT_END
		# Once a shift ends, the worker must physically depart and return. A
		# coarse clock jump therefore cannot credit a later day's shift.
		var shift_end: int = _latest_time - minute_of_day + SHIFT_END
		var eligible_end: int = mini(next_time, shift_end) if on_shift else _latest_time
		if not worker_ids.is_empty():
			var contribution: int = payroll_work_remainder
			for id: String in worker_ids:
				var worker: WorkerData = WorkerDatabase.get_worker_data(id)
				if worker != null and not worker.resignation_pending and worker.get_resolved_satisfaction() > 0.0:
					contribution += worker.get_arrived_paid_minutes(_latest_time, eligible_end, "plot", order_id + ":" + phase, order_id)
			worked = contribution / worker_ids.size()
			payroll_work_remainder = contribution % worker_ids.size()
		if not on_shift or next_time >= shift_end:
			var presence: Script = null
			for id: String in worker_ids:
				var worker: WorkerData = WorkerDatabase.get_worker_data(id)
				if worker == null:
					continue
				if worker.physical_approach.get("arrival_minute", -1) == WorkerData.PLOT_DEPARTURE_PENDING and not worker.physical_approach.get("arrived", false) and worker.current_work_status == WorkerData.WorkStatus.RESTING:
					continue
				if presence == null:
					presence = load("res://scenes/workshop_plot/workshop_worker_presence.gd")
				presence.end_shift_for_worker(worker, "plot", order_id + ":" + phase, order_id)
		# If other activity fills shelter after the start, retain one uncompleted
		# worker-minute until all three places fit. This also keeps the existing
		# active-construction save invariant (positive remaining work).
		if phase == "building" and is_citizen_house() and not worker_ids.is_empty() and worked >= completes_at - _latest_time and not _has_shelter_room():
			worked = maxi(completes_at - _latest_time - 1, 0)
			payroll_work_remainder = worker_ids.size() - 1
		started_at += elapsed - worked
		completes_at += elapsed - worked
	_latest_time = next_time
	if _latest_time >= completes_at:
		var house_completed: bool = phase == "building" and is_citizen_house()
		if house_completed and not _has_shelter_room():
			# Defensive boundary guard: never publish a partial shelter bonus even
			# if an unusual caller presented an already-complete active state.
			var adjustment: int = _latest_time - completes_at + 1
			started_at += adjustment
			completes_at += adjustment
			payroll_work_remainder = maxi(0, worker_ids.size() - 1)
			changed.emit()
			return
		var owns_transaction: bool = house_completed and not _starting
		if owns_transaction:
			_starting = true
		phase = "empty" if phase == "clearing" else "built"
		if house_completed:
			# The room check above prevents CityStockManager's clamping from ever
			# applying a partial bonus. The phase changes before callbacks can see it.
			CityStockManager.add_shelter_capacity(CITIZEN_HOUSE_SHELTER_CAPACITY)
		payroll_work_remainder = 0
		clearing_remaining = 0
		clearing_by_player = false
		player_building = false
		_release_workers(worker_ids)
		changed.emit()
		if owns_transaction:
			_finish_transaction()
		return
	changed.emit()

func _all_workers_payroll_blocked() -> bool:
	if worker_ids.is_empty():
		return false
	for id: String in worker_ids:
		var worker: WorkerData = WorkerDatabase.get_worker_data(id)
		if worker != null and not worker.is_payroll_blocked():
			return false
	return true

func has_active_worker_at_plot() -> bool:
	if phase not in ["building", "clearing"]:
		return false
	if is_player_work_active():
		return true
	var minute_of_day: int = _now() % 1440
	if minute_of_day < SHIFT_START or minute_of_day >= SHIFT_END:
		return false
	var task_key: String = order_id + ":" + phase
	for id: String in worker_ids:
		var worker: WorkerData = WorkerDatabase.get_worker_data(id)
		if worker == null or worker.is_payroll_blocked():
			continue
		if worker.physical_approach.is_empty():
			return true # Legacy saves retain their established inside-plot state.
		if worker.matches_physical_approach("plot", task_key, order_id) and worker.physical_approach.arrived:
			return true
	return false

func _refresh_payroll_status() -> void:
	if not _starting and phase in ["building", "clearing"]:
		changed.emit()

func _flush_payroll_boundary() -> void:
	flush_elapsed_work()

## Settle the elapsed interval before Satisfaction changes or a team changes.
func flush_elapsed_work() -> void:
	_on_time_changed(TimeComponentManager.current_day, TimeComponentManager.current_hour, TimeComponentManager.current_minute, TimeComponentManager.current_weather)


func _remaining_work_units() -> int:
	var scale: int = maxi(1, worker_ids.size())
	return maxi(0, (completes_at - _latest_time) * scale - payroll_work_remainder)


func _ceil_units(units: int, scale: int) -> int:
	if units <= 0:
		return 0
	@warning_ignore("integer_division")
	return 1 + (units - 1) / scale


func _rebase_team(next_count: int) -> bool:
	var remaining: int = _remaining_work_units()
	if remaining <= 0 or work_total_units <= 0 or next_count < 0 or next_count > MAX_WORKER_CAPACITY:
		return false
	var scale: int = maxi(1, next_count)
	var remaining_minutes: int = _ceil_units(remaining, scale)
	var total_minutes: int = _ceil_units(work_total_units, scale)
	payroll_work_remainder = remaining_minutes * scale - remaining
	completes_at = _latest_time + remaining_minutes
	started_at = completes_at - total_minutes
	return true


## Atomically release a resigning builder with the existing worker transaction.
## A failed worker transaction restores the post-flush reservation and progress.
func resign_worker(worker_id: String) -> bool:
	if _starting or phase not in ["building", "clearing"] or is_player_work_active() or not worker_ids.has(worker_id):
		return false
	_starting = true
	flush_elapsed_work()
	# A job finishing at this boundary has already released its team.
	if phase not in ["building", "clearing"]:
		var completed_resignation: bool = WorkerDatabase.resign_idle_worker(worker_id)
		_finish_transaction()
		return completed_resignation
	var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
	if worker == null or worker.current_order_id != order_id:
		_finish_transaction()
		return false
	var citizen: CitizenData = worker.get_linked_citizen()
	var previous_status: int = citizen.employment_status if citizen != null else -1
	var previous_order: String = worker.current_order_id
	var previous_job: String = worker.current_job_id
	var previous_activity: int = worker.current_work_status
	var previous_approach: Dictionary = worker.physical_approach.duplicate(true)
	var previous_ids: Array[String] = worker_ids.duplicate()
	var previous_start: int = started_at
	var previous_end: int = completes_at
	var previous_remainder: int = payroll_work_remainder
	var next_ids: Array[String] = worker_ids.duplicate()
	next_ids.erase(worker_id)
	if not _rebase_team(next_ids.size()):
		_finish_transaction()
		return false
	worker_ids = next_ids
	worker.finish_work(order_id)
	if not WorkerDatabase.unassign_worker(worker_id) or not WorkerDatabase.resign_idle_worker(worker_id):
		worker_ids = previous_ids
		started_at = previous_start
		completes_at = previous_end
		payroll_work_remainder = previous_remainder
		worker.current_order_id = previous_order
		worker.current_job_id = previous_job
		worker.current_work_status = previous_activity
		worker.physical_approach = previous_approach
		if citizen != null:
			citizen.employment_status = previous_status
		_finish_transaction()
		return false
	changed.emit()
	_finish_transaction()
	return true


func get_replacement_slots() -> int:
	if phase not in ["building", "clearing"] or is_player_work_active():
		return 0
	return maxi(0, worker_capacity - worker_ids.size())


## Replacements occupy only vacancies from the original team; materials remain paid.
func add_replacement_workers(ids: Array[String]) -> Dictionary:
	if _starting or phase not in ["building", "clearing"] or is_player_work_active():
		return {"success": false, "message": "Workers cannot be assigned now."}
	_starting = true
	flush_elapsed_work()
	if phase not in ["building", "clearing"]:
		_finish_transaction()
		return {"success": false, "message": "The work is complete."}
	if ids.is_empty() or ids.size() > get_replacement_slots():
		_finish_transaction()
		return {"success": false, "message": "Choose available replacement workers."}
	var seen: Dictionary = {}
	for id: String in ids:
		if id.is_empty() or seen.has(id) or worker_ids.has(id) or not _worker_reason(id).is_empty():
			_finish_transaction()
			return {"success": false, "message": "Worker availability changed."}
		seen[id] = true
	var reserved: Array[String] = []
	for id: String in ids:
		if not WorkerDatabase.assign_worker(id):
			_release_workers(reserved)
			_finish_transaction()
			return {"success": false, "message": "Worker availability changed."}
		var worker: WorkerData = WorkerDatabase.get_worker_data(id)
		worker.start_work(order_id, _worker_job_label(phase == "clearing"))
		reserved.append(id)
	if not _rebase_team(worker_ids.size() + reserved.size()):
		_release_workers(reserved)
		_finish_transaction()
		return {"success": false, "message": "Work could not be resumed."}
	worker_ids.append_array(reserved)
	_initialize_approaches(reserved)
	changed.emit()
	_finish_transaction()
	return {"success": true, "message": "Replacement workers assigned."}

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
	var payroll_blocked: bool = phase == "clearing" and not clearing_by_player and _all_workers_payroll_blocked()
	if payroll_blocked:
		message = "Contract expired - renew in Worker Hub."
	var remaining: int = maxi(completes_at - _latest_time, 0) if phase == "clearing" else clearing_remaining
	var progress: float = 1.0 - float(remaining) / CLEARING_MINUTES
	var count: int = (1 if clearing_by_player else worker_ids.size()) if phase == "clearing" else (1 if use_player else ids.size())
	return {"can_start": message.is_empty(), "message": message, "duration_minutes": clearing_remaining,
		"remaining_minutes": remaining, "progress_ratio": progress, "worker_count": count, "payroll_blocked": payroll_blocked}

func start_clearing(ids: Array[String], use_player: bool) -> Dictionary:
	if _starting:
		return {"success": false, "message": "Starting construction."}
	var preview: Dictionary = get_clearing_preview(ids, use_player)
	if not bool(preview.can_start):
		return {"success": false, "message": preview.message}
	_starting = true
	if not use_player:
		if not WorkerDatabase.assign_worker(ids[0]):
			_finish_transaction()
			return {"success": false, "message": "Worker unavailable."}
		WorkerDatabase.get_worker_data(ids[0]).start_work(order_id, _worker_job_label(true))
	worker_ids = ids.duplicate()
	worker_capacity = 1
	work_total_units = CLEARING_MINUTES
	clearing_by_player = use_player
	payroll_work_remainder = 0
	started_at = _now()
	_latest_time = started_at
	completes_at = started_at + clearing_remaining
	phase = "clearing"
	if not use_player:
		_initialize_approaches()
	changed.emit()
	_finish_transaction()
	return {"success": true, "message": "Clearing started."}

func _initialize_approaches(ids: Array[String] = []) -> void:
	var approaching: Array[String] = worker_ids if ids.is_empty() else ids
	for plot: Node in get_tree().get_nodes_in_group("workshop_plots"):
		if plot.construction == self:
			for id: String in approaching:
				plot.begin_worker_approach(id, order_id + ":" + phase)
			return

## A player may take over an unstaffed house without repaying its materials.
func resume_player_work() -> Dictionary:
	if not is_citizen_house() or _starting or is_player_work_active() or phase not in ["building", "clearing"] or not worker_ids.is_empty():
		return {"success": false, "message": "Player cannot take over this work."}
	_starting = true
	flush_elapsed_work()
	if phase not in ["building", "clearing"] or not worker_ids.is_empty() or _remaining_work_units() <= 0:
		_finish_transaction()
		return {"success": false, "message": "The work is no longer available."}
	if phase == "building" and _remaining_work_units() <= 1 and not _has_shelter_room():
		_finish_transaction()
		return {"success": false, "message": "Shelter capacity is full; construction paused."}
	player_building = phase == "building"
	clearing_by_player = phase == "clearing"
	changed.emit()
	_finish_transaction()
	return {"success": true, "message": "Player work started."}


## Leave paid building work in its normal, saveable workerless state.
func interrupt_player_work() -> void:
	if _starting:
		if is_player_work_active():
			_player_interrupt_pending = true
		return
	if clearing_by_player:
		interrupt_player_clearing()
		return
	if not player_building:
		return
	_starting = true
	flush_elapsed_work()
	if player_building:
		player_building = false
		changed.emit()
	_finish_transaction()


func interrupt_player_clearing() -> void:
	if _starting or phase != "clearing" or not clearing_by_player:
		return
	_starting = true
	clearing_remaining = maxi(completes_at - _latest_time, 0)
	phase = "uncleared"
	clearing_by_player = false
	changed.emit()
	_finish_transaction()
