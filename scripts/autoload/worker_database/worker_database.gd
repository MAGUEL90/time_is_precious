extends Node

const WORKERS_PATH: String = "res://resources/worker_data"
const CITY_TOOL_STORAGE: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")

var workers_by_id: Dictionary[String, WorkerData] = {}
var is_loaded: bool = false
var dismissed_workers: Dictionary[String, WorkerData] = {}
signal payroll_changed
# Flush elapsed work under the old entitlement before replacing paid-period dates.
signal payroll_settling
var _payroll_settling: bool = false
var _idle_resignation_sweep_active: bool = false
var _idle_resignation_retry_queued: bool = false
var _idle_resignation_retry_after_frame: bool = false
var _worksite_schedules: Array[WeakRef] = []
# Temporary test rates approved by the Game Director on 2026-10-22.
# These are three-day package prices, not validated final balance or daily wages.
var onboarding_period_rates: Dictionary = {
	WorkerData.Profession.LABORER: 1,
	WorkerData.Profession.HAULER: 1,
	WorkerData.Profession.SCAVENGER: 1,
	WorkerData.Profession.CRAFTER: 2,
	WorkerData.Profession.FARMER: 2,
}
const PAYROLL_PERIOD_DAYS: int = 7 # Legacy save/fixture period only.
const CONTRACT_DAYS: Array[int] = [3, 6, 9]
const MAX_CONTRACT_DAY: int = 100000000

func _ready() -> void:
	# Gameplay starts without employees; Job Board hires populate this roster.
	# Isolated legacy fixtures may explicitly call reload_workers().
	is_loaded = true
	TimeComponentManager.hour_changed.connect(_on_payroll_hour)
	if WorkManager.has_signal("transaction_finished") and not WorkManager.is_connected("transaction_finished", _on_work_manager_transaction_finished):
		WorkManager.connect("transaction_finished", _on_work_manager_transaction_finished)


func _load_all_workers(path: String) -> void:
	workers_by_id.clear()
	is_loaded = false

	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		push_error("WorkerDatabase: failed to open workers path: %s" % path)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			file_name = dir.get_next()
			continue

		if not file_name.ends_with(".tres"):
			file_name = dir.get_next()
			continue

		var worker_path: String = path.path_join(file_name)
		var worker_res: Resource = load(worker_path)
		if not worker_res is WorkerData:
			push_warning("WorkerDatabase: %s is not a WorkerData resource." % worker_path)
			file_name = dir.get_next()
			continue

		var worker_data: WorkerData = worker_res as WorkerData
		var resolved_id: String = worker_data.worker_id.strip_edges()
		if resolved_id == "":
			resolved_id = file_name.trim_suffix(".tres")
			worker_data.worker_id = resolved_id

		if workers_by_id.has(resolved_id):
			var existing_worker: WorkerData = workers_by_id[resolved_id]
			push_error(
				"WorkerDatabase: duplicate worker id '%s' between %s and %s." % [
					resolved_id,
					existing_worker.resource_path,
					worker_path
				]
			)
			file_name = dir.get_next()
			continue

		workers_by_id[resolved_id] = worker_data
		file_name = dir.get_next()

	dir.list_dir_end()
	is_loaded = true

func get_worker_data(worker_id: String) -> WorkerData:
	return workers_by_id.get(worker_id, null)

func get_all_workers() -> Array:
	return workers_by_id.values()

func reload_workers() -> void:
	_load_all_workers(WORKERS_PATH)

func has_worker_data(worker_id: String) -> bool:
	return workers_by_id.has(worker_id)

# Hiring lifecycle

func hire_applicant(
	citizen_id: String,
	wage_shekel_per_day: int = 1,
	contract_days: int = 3
) -> WorkerData:
	if _payroll_settling or Inventory._bulk_transaction_in_progress or not is_job_board_open():
		return null
	var citizen_data: CitizenData = CitizenManager.get_citizen(citizen_id)
	if citizen_data == null:
		return null

	if not citizen_data.can_be_hired() or not CitizenManager.is_profession_recruitable(citizen_data.profession):
		return null

	if has_worker_data(citizen_data.citizen_id):
		return null
	var price: int = get_contract_price(citizen_data.profession, contract_days)
	if price <= 0 or not Inventory.has_item("shekel", price) or TimeComponentManager.current_day > MAX_CONTRACT_DAY - contract_days:
		return null
	_payroll_settling = true

	# Preserve earned profession progress if this citizen is hired again.
	var worker_data: WorkerData = dismissed_workers.get(citizen_data.citizen_id, WorkerData.new())
	dismissed_workers.erase(citizen_data.citizen_id)
	worker_data.worker_id = citizen_data.citizen_id
	worker_data.display_name = citizen_data.display_name
	worker_data.profession = citizen_data.profession
	worker_data.resignation_pending = false
	worker_data.wage_shekel_per_day = maxi(0, wage_shekel_per_day)
	worker_data.payroll_start_day = TimeComponentManager.current_day
	_start_contract(worker_data, contract_days, price)
	workers_by_id[worker_data.worker_id] = worker_data
	citizen_data.employment_status = CitizenData.EmploymentStatus.HIRED
	_commit_wallet_payment(price)

	return worker_data

func hire_applicants(
	citizen_ids: PackedStringArray,
	wage_shekel_per_day: int = 1,
	contract_days: int = 3
) -> Array[WorkerData]:
	var hired: Array[WorkerData] = []
	if _payroll_settling or Inventory._bulk_transaction_in_progress or not is_job_board_open() or citizen_ids.is_empty():
		return hired
	if contract_days not in CONTRACT_DAYS or TimeComponentManager.current_day > MAX_CONTRACT_DAY - contract_days:
		return hired
	var citizens: Array[CitizenData] = []
	var prices: Array[int] = []
	var seen: Dictionary = {}
	var total: int = 0
	# Validate the complete batch before changing workers, citizens or funds.
	for citizen_id: String in citizen_ids:
		var clean_id: String = citizen_id.strip_edges()
		if clean_id.is_empty() or seen.has(clean_id):
			return hired
		seen[clean_id] = true
		var citizen: CitizenData = CitizenManager.get_citizen(clean_id)
		if citizen == null or not citizen.can_be_hired() or not CitizenManager.is_profession_recruitable(citizen.profession) or has_worker_data(clean_id):
			return hired
		var price: int = get_contract_price(citizen.profession, contract_days)
		if price <= 0 or total > 9223372036854775807 - price:
			return hired
		total += price
		citizens.append(citizen)
		prices.append(price)
	if not Inventory.has_item("shekel", total):
		return hired
	_payroll_settling = true
	for index: int in range(citizens.size()):
		var citizen: CitizenData = citizens[index]
		# Rehire uses the same retained worker resource as the single-hire path.
		var worker: WorkerData = dismissed_workers.get(citizen.citizen_id, WorkerData.new())
		dismissed_workers.erase(citizen.citizen_id)
		worker.worker_id = citizen.citizen_id
		worker.display_name = citizen.display_name
		worker.profession = citizen.profession
		worker.resignation_pending = false
		worker.wage_shekel_per_day = maxi(0, wage_shekel_per_day)
		worker.payroll_start_day = TimeComponentManager.current_day
		_start_contract(worker, contract_days, prices[index])
		workers_by_id[worker.worker_id] = worker
		citizen.employment_status = CitizenData.EmploymentStatus.HIRED
		hired.append(worker)
	# One debit and one pair of notifications after every membership is published.
	# The existing guard stays raised through both callbacks, including reentry.
	_commit_wallet_payment(total)
	return hired

func dismiss_worker(worker_id: String) -> bool:
	var worker: WorkerData = get_worker_data(worker_id)
	if _payroll_settling or worker == null or worker.is_reserved() or worker.current_work_status == WorkerData.WorkStatus.TRAVELLING:
		return false
	var citizen: CitizenData = worker.get_linked_citizen()
	if citizen != null and citizen.employment_status == CitizenData.EmploymentStatus.ASSIGNED:
		return false
	if citizen != null:
		citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	dismissed_workers[worker_id] = worker
	workers_by_id.erase(worker_id)
	# Prepaid time is forfeited; removal only refreshes the next payroll quote.
	payroll_changed.emit()
	return true


## Schedules register their live owner, including one parked during a home visit.
## Merely registering never mutates the world: save owners may still be loading.
func register_worksite_schedule(schedule: RefCounted) -> void:
	if schedule == null or _live_worksite_schedules().has(schedule):
		return
	_worksite_schedules.append(weakref(schedule))
	if schedule.has_signal("resignation_ready") and not schedule.is_connected("resignation_ready", _on_worksite_resignation_ready):
		schedule.connect("resignation_ready", _on_worksite_resignation_ready)
	if schedule.has_signal("settlement_finished") and not schedule.is_connected("settlement_finished", _on_worksite_settlement_finished):
		schedule.connect("settlement_finished", _on_worksite_settlement_finished)


func unregister_worksite_schedule(schedule: RefCounted) -> void:
	if schedule == null:
		return
	if schedule.has_signal("resignation_ready") and schedule.is_connected("resignation_ready", _on_worksite_resignation_ready):
		schedule.disconnect("resignation_ready", _on_worksite_resignation_ready)
	if schedule.has_signal("settlement_finished") and schedule.is_connected("settlement_finished", _on_worksite_settlement_finished):
		schedule.disconnect("settlement_finished", _on_worksite_settlement_finished)
	for reference: WeakRef in _worksite_schedules.duplicate():
		if reference.get_ref() == null or reference.get_ref() == schedule:
			_worksite_schedules.erase(reference)


func _live_worksite_schedules() -> Array:
	var result: Array = []
	for reference: WeakRef in _worksite_schedules.duplicate():
		var schedule: Object = reference.get_ref()
		if schedule == null:
			_worksite_schedules.erase(reference)
		else:
			result.append(schedule)
	return result


## Clock requests from callbacks must not advance into the next minute while a
## worksite, equipment transfer or resignation owns a partial transaction.
func is_world_time_transition_busy() -> bool:
	if _payroll_settling or _idle_resignation_sweep_active:
		return true
	if Inventory._bulk_transaction_in_progress or (WorkshopFacilityManager.has_method("is_transaction_busy") and WorkshopFacilityManager.is_transaction_busy()):
		return true
	if StorageDestination.is_any_delivery_busy():
		return true
	if WorkManager.has_method("is_transaction_busy") and bool(WorkManager.call("is_transaction_busy")):
		return true
	var runtime: Node = get_node_or_null("/root/WorkStateRuntime")
	if runtime != null:
		for owner: Node in runtime.get_children():
			if owner.has_method("is_transaction_busy") and bool(owner.call("is_transaction_busy")):
				return true
	for schedule: RefCounted in _live_worksite_schedules():
		if schedule.has_method("is_settlement_busy") and bool(schedule.call("is_settlement_busy")):
			return true
	for storage: Node in _resignation_tool_storages():
		if bool(storage.get("_transfer_in_progress")):
			return true
	return false


func _on_work_manager_transaction_finished() -> void:
	on_work_owner_transaction_finished()


## Work owners call this after publishing all changes and releasing their
## transaction guard. A zero worker must not perform another clock tick merely
## because the request arrived from a synchronous change observer.
func on_work_owner_transaction_finished() -> void:
	var needs_resignation: bool = false
	for worker: WorkerData in workers_by_id.values():
		if worker.resignation_pending or worker.get_resolved_satisfaction() <= 0.0:
			needs_resignation = true
			break
	if needs_resignation:
		if is_world_time_transition_busy():
			_queue_idle_resignation_retry()
		else:
			resign_idle_workers_at_zero()
	if CitizenNeedsManager._daily_needs_retry_pending:
		CitizenNeedsManager.process_daily_needs.call_deferred()


func _on_worksite_resignation_ready(worker_id: String) -> void:
	# The scheduler emits only after cargo has one owner and the assignment is
	# released. Finish synchronously, including inside an uninterrupted time skip.
	var worker: WorkerData = get_worker_data(worker_id)
	if worker == null or not worker.resignation_pending:
		return
	if not _idle_resignation_sweep_active and not _payroll_settling and not worker.is_reserved() and worker.current_work_status == WorkerData.WorkStatus.IDLE:
		unassign_worker(worker_id)
		if resign_idle_worker(worker_id):
			return
	_queue_idle_resignation_retry()


func _on_worksite_settlement_finished() -> void:
	_queue_idle_resignation_retry()
	if CitizenNeedsManager._daily_needs_retry_pending:
		CitizenNeedsManager.process_daily_needs.call_deferred()


## Day-change is emitted before normal time_changed/minute_changed. Flush each
## old-Satisfaction interval before the daily needs calculation changes it.
func flush_before_daily_needs() -> bool:
	if _payroll_settling or StorageDestination.is_any_delivery_busy():
		return false
	if WorkManager.has_method("is_transaction_busy") and bool(WorkManager.call("is_transaction_busy")):
		return false
	for schedule: RefCounted in _live_worksite_schedules():
		if schedule.has_method("flush_before_needs") and not bool(schedule.call("flush_before_needs")):
			return false
	_payroll_settling = true
	payroll_settling.emit()
	_payroll_settling = false
	return true


## Mark every worker who reaches zero and interrupt their owner safely. A
## loaded delivery remains pending until its one final receipt has committed.
func resign_idle_workers_at_zero() -> void:
	if _idle_resignation_sweep_active:
		_queue_idle_resignation_retry()
		return
	var transaction_busy: bool = _payroll_settling
	if StorageDestination.is_any_delivery_busy():
		transaction_busy = true
	if WorkManager.has_method("is_transaction_busy") and bool(WorkManager.call("is_transaction_busy")):
		transaction_busy = true
	for storage: Node in _resignation_tool_storages():
		if bool(storage.get("_transfer_in_progress")):
			transaction_busy = true
	if transaction_busy:
		# Both locks are synchronous; retry after the current owner transaction.
		_queue_idle_resignation_retry()
		return
	_idle_resignation_sweep_active = true
	for worker_id: String in workers_by_id.keys():
		var worker: WorkerData = get_worker_data(worker_id)
		if worker != null and (worker.resignation_pending or worker.get_resolved_satisfaction() <= 0.0):
			worker.resignation_pending = true
			_interrupt_resigning_worker(worker_id)
	_idle_resignation_sweep_active = false


func _interrupt_resigning_worker(worker_id: String) -> void:
	var worker: WorkerData = get_worker_data(worker_id)
	if worker == null or not worker.resignation_pending:
		return
	for schedule: RefCounted in _live_worksite_schedules():
		if schedule.has_method("request_resignation") and not bool(schedule.call("request_resignation", worker_id)):
			return
	# Draft workshop selection is not a persisted work order. Release only this
	# worker; the other selected workers and any finished output remain intact.
	_release_workshop_selection(worker_id)
	WorkManager.pause_orders_for_worker(worker_id)
	var runtime: Node = get_node_or_null("/root/WorkStateRuntime")
	if runtime != null:
		for state: Node in runtime.get_children():
			if state.has_method("resign_worker"):
				var ids: Variant = state.get("worker_ids")
				if ids is Array and ids.has(worker_id):
					if not bool(state.call("resign_worker", worker_id)) and state.has_method("is_transaction_busy") and bool(state.call("is_transaction_busy")):
						_queue_idle_resignation_retry()
					return
	# The owners above must have released the reservation before a roster change.
	if not worker.is_reserved() and worker.current_work_status == WorkerData.WorkStatus.IDLE:
		unassign_worker(worker_id)
		resign_idle_worker(worker_id)


func _release_workshop_selection(worker_id: String) -> void:
	var pending_nodes: Array[Node] = [get_tree().root]
	while not pending_nodes.is_empty():
		var node: Node = pending_nodes.pop_back()
		if node is WorkShop:
			(node as WorkShop).assigned_worker_ids.erase(worker_id)
		pending_nodes.append_array(node.get_children())


func _queue_idle_resignation_retry() -> void:
	if not _idle_resignation_retry_queued:
		_idle_resignation_retry_queued = true
		_retry_idle_resignations.call_deferred()


func _retry_idle_resignations() -> void:
	_idle_resignation_retry_queued = false
	if is_world_time_transition_busy():
		# A test or asynchronous owner can retain a lock across frames. A
		# deferred call that requeues itself in the same idle flush would spin.
		if not _idle_resignation_retry_after_frame:
			_idle_resignation_retry_after_frame = true
			get_tree().process_frame.connect(_retry_idle_resignations_after_frame, CONNECT_ONE_SHOT)
		return
	resign_idle_workers_at_zero()


func _retry_idle_resignations_after_frame() -> void:
	_idle_resignation_retry_after_frame = false
	_queue_idle_resignation_retry()


func _resignation_tool_storages() -> Array[Node]:
	var result: Array[Node] = []
	var shared: Node = get_node_or_null("/root/WorkStateRuntime/CityToolStorage")
	if shared != null:
		result.append(shared)
	# The isolated worksite uses its own real equipment owner; the main map uses
	# the shared store above. Deduplicate the owner before staging any release.
	for schedule: RefCounted in _live_worksite_schedules():
		if not schedule.has_method("get_equipment_storage"):
			continue
		var storage: Variant = schedule.call("get_equipment_storage")
		if storage is Node and is_instance_valid(storage) and not result.has(storage):
			result.append(storage)
	return result


func resign_idle_worker(worker_id: String) -> bool:
	if _payroll_settling or worker_id.is_empty() or worker_id != worker_id.strip_edges():
		return false
	if StorageDestination.is_any_delivery_busy():
		return false
	if WorkManager.has_method("is_transaction_busy") and bool(WorkManager.call("is_transaction_busy")):
		return false
	var worker: WorkerData = get_worker_data(worker_id)
	if worker == null or worker.worker_id != worker_id or dismissed_workers.has(worker_id):
		return false
	if (not worker.resignation_pending and worker.get_resolved_satisfaction() != 0.0) or worker.current_work_status != WorkerData.WorkStatus.IDLE:
		return false
	# Pending resignation is latched at zero, so later needs recovery cannot turn
	# a departing worker back into a resident. A direct zero-boundary resignation
	# uses the same final departure path.
	var should_leave_city: bool = worker.resignation_pending or worker.get_resolved_satisfaction() == 0.0
	if worker.is_reserved() or not worker.current_job_id.is_empty() or not worker.physical_approach.is_empty():
		return false
	var citizen: CitizenData = worker.get_linked_citizen()
	if citizen != null and (citizen.population_status != CitizenData.PopulationStatus.RESIDENT or citizen.employment_status != CitizenData.EmploymentStatus.HIRED):
		return false
	for order: WorkOrder in WorkManager.active_orders.values():
		if order != null and order.worker_id == worker_id:
			return false
	if _has_workshop_assignment(worker_id):
		return false

	var storages: Array[Node] = _resignation_tool_storages()
	if storages.is_empty():
		return false
	var staged_units: Array[Dictionary] = []
	var released_storages: Array[Node] = []
	for storage: Node in storages:
		if storage.get_script() != CITY_TOOL_STORAGE or bool(storage.get("_transfer_in_progress")):
			return false
		var current_units: Variant = storage.get("units")
		if not current_units is Dictionary:
			return false
		var next_units: Dictionary = current_units.duplicate(true)
		for unit_id: Variant in next_units:
			var unit: Variant = next_units[unit_id]
			if not unit_id is String or not unit is Dictionary or not unit.get("worker_id") is String:
				return false
			if unit.worker_id == worker_id:
				unit.worker_id = ""
				if not released_storages.has(storage):
					released_storages.append(storage)
		staged_units.append(next_units)

	var added_citizen: bool = citizen == null
	var generator_counter: int = CitizenGenerator.counter_id
	if added_citizen:
		# An unlinked legacy worker has no other identity that can receive needs or
		# reapply. Keep the existing ID and needs values; never generate a new one.
		for pending: CitizenData in ImmigrationManager.pending_immigrants:
			if pending != null and pending.citizen_id.strip_edges() == worker_id:
				return false
		# A canonical generated ID must not be issued again after promotion.
		if worker_id.begins_with("citizen_"):
			var suffix: String = worker_id.trim_prefix("citizen_")
			if suffix.is_valid_int():
				var number: int = int(suffix)
				if number > generator_counter and worker_id == "citizen_%03d" % number:
					if number == 9223372036854775807:
						return false
					generator_counter = number
		citizen = CitizenData.new()
		citizen.citizen_id = worker_id
		citizen.display_name = worker.display_name
		citizen.profession = worker.profession
		citizen.satisfaction = worker.satisfaction
		citizen.food_fulfilled = worker.food_fulfilled
		citizen.clothing_fulfilled = worker.clothing_fulfilled
		citizen.shelter_fulfilled = worker.shelter_fulfilled
		citizen.population_status = CitizenData.PopulationStatus.RESIDENT

	# No signals between these writes. Both guards remain raised through all
	# notifications so observers see one coherent roster and equipment state.
	_payroll_settling = true
	for storage: Node in storages:
		storage.set("_transfer_in_progress", true)
	for index: int in range(storages.size()):
		storages[index].set("units", staged_units[index])
	if added_citizen:
		CitizenManager.citizens_by_id[worker_id] = citizen
		CitizenGenerator.counter_id = generator_counter
	citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	worker.payroll_start_day = -1
	worker.payroll_paid_from_day = -1
	worker.payroll_paid_until_day = -1
	worker.payroll_period_rate = 0
	worker.payroll_last_attempt_day = -1
	worker.payroll_contract_days = 0
	worker.payroll_paid_start_minute = -1
	worker.resignation_pending = false
	dismissed_workers[worker_id] = worker
	workers_by_id.erase(worker_id)
	# leave_city rejects active workers, so only invoke it after the complete
	# roster/equipment commit. The guards remain raised while its signal observers
	# see the departed citizen and any legacy identity promotion.
	var departed: bool = should_leave_city and CitizenManager.leave_city(worker_id)
	if added_citizen and not departed:
		CitizenManager.citizen_added.emit(citizen)
	for storage: Node in released_storages:
		storage.emit_signal("changed")
	payroll_changed.emit()
	for storage: Node in storages:
		storage.set("_transfer_in_progress", false)
	_payroll_settling = false
	return true


func _has_workshop_assignment(worker_id: String) -> bool:
	# Legacy unlinked workers have no CitizenData ASSIGNED state. A live workshop
	# can still own their idle selection, so inspect its existing assignment list.
	var pending_nodes: Array[Node] = [get_tree().root]
	while not pending_nodes.is_empty():
		var node: Node = pending_nodes.pop_back()
		if node is WorkShop and (node as WorkShop).assigned_worker_ids.has(worker_id):
			return true
		pending_nodes.append_array(node.get_children())
	return false

func assign_worker(worker_id: String) -> bool:
	var worker_data: WorkerData = get_worker_data(worker_id)
	if worker_data == null:
		return false
	if worker_data.resignation_pending or worker_data.get_resolved_satisfaction() <= 0.0:
		return false
	if worker_data.is_payroll_blocked():
		return false

	var citizen_data: CitizenData = worker_data.get_linked_citizen()
	# Preserve compatibility with legacy workers that have no CitizenData.
	if citizen_data == null:
		return true

	if citizen_data.employment_status == CitizenData.EmploymentStatus.ASSIGNED:
		return true

	if not citizen_data.can_be_assigned():
		return false

	citizen_data.employment_status = CitizenData.EmploymentStatus.ASSIGNED
	return true

func unassign_worker(worker_id: String) -> bool:
	var worker_data: WorkerData = get_worker_data(worker_id)
	# A live work owner must finish its reservation before releasing the
	# citizen's assignment. This also prevents a payment observer from silently
	# unassigning a builder while construction is being committed.
	if worker_data == null or worker_data.is_reserved():
		return false

	var citizen_data: CitizenData = worker_data.get_linked_citizen()
	# Preserve compatibility with legacy workers that have no CitizenData.
	if citizen_data == null:
		return true

	if citizen_data.employment_status == CitizenData.EmploymentStatus.HIRED:
		return true

	if citizen_data.employment_status != CitizenData.EmploymentStatus.ASSIGNED:
		return false

	citizen_data.employment_status = CitizenData.EmploymentStatus.HIRED
	return true

func is_job_board_open() -> bool:
	return TimeComponentManager.current_hour >= 8 and TimeComponentManager.current_hour < 17

func get_onboarding_rate(profession: WorkerData.Profession) -> int:
	return int(onboarding_period_rates.get(profession, -1))

func get_first_payment_quote(day: int) -> Dictionary:
	# Legacy quote API only; contracts are purchased individually from the wallet.
	return get_payroll_quote(day)

func get_payroll_quote(day: int) -> Dictionary:
	var total: int = 0
	var count: int = 0
	var unpriced: bool = false
	for worker: WorkerData in workers_by_id.values():
		if not worker.is_payroll_due(day):
			continue
		count += 1
		var rate: int = get_onboarding_rate(worker.profession)
		if rate <= 0:
			unpriced = true
		else:
			total += rate
	return {"count": count, "total": total, "unpriced": unpriced,
		"shortfall": maxi(0, total - CityStockManager.treasury_shekel)}

func _on_payroll_hour(hour: int) -> void:
	# Expiry is per worker. There is no automatic charge or group settlement.
	if hour in [7, 8] and not _payroll_settling:
		payroll_changed.emit()

func get_contract_price(profession: WorkerData.Profession, days: int) -> int:
	var base: int = get_onboarding_rate(profession)
	if days not in CONTRACT_DAYS or base <= 0 or base > 9223372036854775807 / 3:
		return -1
	return base * (days / 3)

func renew_contract(worker_id: String, days: int) -> bool:
	var worker: WorkerData = get_worker_data(worker_id)
	if _payroll_settling or Inventory._bulk_transaction_in_progress or worker == null:
		return false
	if worker.resignation_pending or worker.get_resolved_satisfaction() <= 0.0:
		return false
	var price: int = get_contract_price(worker.profession, days)
	var day: int = TimeComponentManager.current_day
	var active: bool = worker.payroll_start_day >= 0 and not worker.is_payroll_blocked()
	var end_day: int = worker.payroll_paid_until_day if active else day
	if price <= 0 or not Inventory.has_item("shekel", price) or end_day > MAX_CONTRACT_DAY - days:
		return false
	_payroll_settling = true
	# Account for all elapsed work BEFORE changing entitlement, including gaps.
	payroll_settling.emit()
	# Flush listeners may complete work; never assume the original wallet balance.
	if not Inventory.has_item("shekel", price) or get_worker_data(worker_id) != worker or worker.resignation_pending or worker.get_resolved_satisfaction() <= 0.0:
		_payroll_settling = false
		on_work_owner_transaction_finished()
		return false
	if active:
		worker.payroll_paid_until_day += days
		worker.payroll_contract_days = days
		worker.payroll_period_rate = price
		worker.payroll_last_attempt_day = day
		if worker.payroll_paid_start_minute < 0:
			worker.payroll_paid_start_minute = worker.payroll_paid_from_day * 1440 + 480
	else:
		worker.payroll_start_day = day
		_start_contract(worker, days, price)
	_commit_wallet_payment(price)
	return true

func _start_contract(worker: WorkerData, days: int, price: int) -> void:
	var day: int = TimeComponentManager.current_day
	worker.payroll_paid_from_day = day
	worker.payroll_paid_start_minute = day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	worker.payroll_paid_until_day = day + days
	worker.payroll_contract_days = days
	worker.payroll_period_rate = price
	worker.payroll_last_attempt_day = day

func _commit_wallet_payment(price: int) -> void:
	# Publish contract and wallet together before observers can react/reenter.
	Inventory.items["shekel"] -= price
	if Inventory.items["shekel"] == 0:
		Inventory.items.erase("shekel")
	Inventory.items_changed.emit()
	payroll_changed.emit()
	_payroll_settling = false
	on_work_owner_transaction_finished()
