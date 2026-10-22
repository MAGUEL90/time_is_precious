extends Node

const WORKERS_PATH: String = "res://resources/worker_data"

var workers_by_id: Dictionary[String, WorkerData] = {}
var is_loaded: bool = false
var dismissed_workers: Dictionary[String, WorkerData] = {}
signal payroll_changed
# Temporary test rates approved by the Game Director on 2026-10-22.
# These are seven-day prices, not validated final balance or daily wages.
var onboarding_period_rates: Dictionary = {
	WorkerData.Profession.LABORER: 1,
	WorkerData.Profession.HAULER: 1,
	WorkerData.Profession.SCAVENGER: 1,
	WorkerData.Profession.CRAFTER: 2,
	WorkerData.Profession.FARMER: 2,
}
const PAYROLL_PERIOD_DAYS: int = 7

func _ready() -> void:
	# Gameplay starts without employees; Job Board hires populate this roster.
	# Isolated legacy fixtures may explicitly call reload_workers().
	is_loaded = true
	TimeComponentManager.hour_changed.connect(_on_payroll_hour)


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
	wage_shekel_per_day: int = 1
) -> WorkerData:
	if not is_job_board_open():
		return null
	var citizen_data: CitizenData = CitizenManager.get_citizen(citizen_id)
	if citizen_data == null:
		return null

	if not citizen_data.can_be_hired():
		return null

	if has_worker_data(citizen_data.citizen_id):
		return null
	if get_onboarding_rate(citizen_data.profession) <= 0:
		return null

	# Preserve earned profession progress if this citizen is hired again.
	var worker_data: WorkerData = dismissed_workers.get(citizen_data.citizen_id, WorkerData.new())
	dismissed_workers.erase(citizen_data.citizen_id)
	worker_data.worker_id = citizen_data.citizen_id
	worker_data.display_name = citizen_data.display_name
	worker_data.profession = citizen_data.profession
	worker_data.wage_shekel_per_day = maxi(0, wage_shekel_per_day)
	worker_data.payroll_start_day = TimeComponentManager.current_day + 1
	worker_data.payroll_paid_from_day = -1
	worker_data.payroll_paid_until_day = -1
	worker_data.payroll_period_rate = 0
	worker_data.payroll_last_attempt_day = -1
	workers_by_id[worker_data.worker_id] = worker_data
	citizen_data.employment_status = CitizenData.EmploymentStatus.HIRED
	payroll_changed.emit()

	return worker_data

func dismiss_worker(worker_id: String) -> bool:
	var worker: WorkerData = get_worker_data(worker_id)
	if worker == null or worker.is_reserved() or worker.current_work_status == WorkerData.WorkStatus.TRAVELLING:
		return false
	var citizen: CitizenData = worker.get_linked_citizen()
	if citizen != null and citizen.employment_status == CitizenData.EmploymentStatus.ASSIGNED:
		return false
	if citizen != null:
		citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	dismissed_workers[worker_id] = worker
	workers_by_id.erase(worker_id)
	return true

func assign_worker(worker_id: String) -> bool:
	var worker_data: WorkerData = get_worker_data(worker_id)
	if worker_data == null:
		return false
	if worker_data.is_waiting_for_first_payment():
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
	if worker_data == null:
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
	var total: int = 0
	var count: int = 0
	var unpriced: bool = false
	for worker: WorkerData in workers_by_id.values():
		if not worker.is_waiting_for_first_payment() or worker.payroll_start_day > day:
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
	# elapsed-hour only: restore/snapshot broadcasts must never charge the treasury.
	if hour != 8:
		return
	var day: int = TimeComponentManager.current_day
	var due: Array[WorkerData] = []
	for worker: WorkerData in workers_by_id.values():
		if worker.is_waiting_for_first_payment() and worker.payroll_start_day <= day:
			# A replay, including a retry after a midday deposit, is a no-op.
			if worker.payroll_last_attempt_day >= day:
				return
			due.append(worker)
	if due.is_empty():
		return
	var quote: Dictionary = get_first_payment_quote(day)
	for worker: WorkerData in due:
		worker.payroll_last_attempt_day = day
	if quote.unpriced or not CityStockManager.spend_shekel(quote.total):
		payroll_changed.emit()
		return
	for worker: WorkerData in due:
		worker.payroll_paid_from_day = day
		worker.payroll_paid_until_day = day + PAYROLL_PERIOD_DAYS - 1
		worker.payroll_period_rate = get_onboarding_rate(worker.profession)
	payroll_changed.emit()
