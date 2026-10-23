extends Node

const WORKERS_PATH: String = "res://resources/worker_data"

var workers_by_id: Dictionary[String, WorkerData] = {}
var is_loaded: bool = false
var dismissed_workers: Dictionary[String, WorkerData] = {}
signal payroll_changed
# Flush elapsed work under the old entitlement before replacing paid-period dates.
signal payroll_settling
var _payroll_settling: bool = false
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
	if _payroll_settling or not is_job_board_open():
		return null
	var citizen_data: CitizenData = CitizenManager.get_citizen(citizen_id)
	if citizen_data == null:
		return null

	if not citizen_data.can_be_hired():
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
	worker_data.wage_shekel_per_day = maxi(0, wage_shekel_per_day)
	worker_data.payroll_start_day = TimeComponentManager.current_day
	_start_contract(worker_data, contract_days, price)
	workers_by_id[worker_data.worker_id] = worker_data
	citizen_data.employment_status = CitizenData.EmploymentStatus.HIRED
	_commit_wallet_payment(price)

	return worker_data

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

func assign_worker(worker_id: String) -> bool:
	var worker_data: WorkerData = get_worker_data(worker_id)
	if worker_data == null:
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
	if _payroll_settling or worker == null:
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
	if not Inventory.has_item("shekel", price) or get_worker_data(worker_id) != worker:
		_payroll_settling = false
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
