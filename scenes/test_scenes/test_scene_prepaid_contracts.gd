extends Node

## Explicit wallet/time fixtures for prepaid hiring and per-worker renewal.
## These prices and grants isolate contract behavior; they are not balance claims.
const FIXTURE_RATES: Dictionary = {
	WorkerData.Profession.LABORER: 2,
	WorkerData.Profession.HAULER: 3,
	WorkerData.Profession.CRAFTER: 4,
}
const FIXTURE_WORK_ORDER_ID: String = "prepaid_contract_fixture_long_order"

var failures: int = 0

var _hire_watch_id: String = ""
var _hire_watch_reentry_id: String = ""
var _hire_watch_wallet: int = 0
var _hire_watch_start_minute: int = -1
var _hire_inventory_callbacks: int = 0
var _hire_payroll_callbacks: int = 0
var _hire_reentry_results: Array[bool] = []
var _hire_renewal_reentry_results: Array[bool] = []
var _hire_reentry_active: bool = false

var _renew_watch_id: String = ""
var _renew_watch_other_applicant_id: String = ""
var _renew_watch_wallet_before: int = 0
var _renew_watch_wallet_after: int = 0
var _renew_watch_old_paid_until: int = -1
var _renew_watch_new_paid_until: int = -1
var _renew_watch_new_rate: int = -1
var _renew_settling_callbacks: int = 0
var _renew_inventory_callbacks: int = 0
var _renew_payroll_callbacks: int = 0
var _renew_settling_reentry_results: Array[bool] = []
var _renew_hire_reentry_results: Array[bool] = []
var _renew_commit_reentry_results: Array[bool] = []
var _renew_reentry_active: bool = false

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	_test_package_hiring_and_wallet_atomicity()
	_test_open_hours_and_rejections()
	_test_contract_day_limit()
	_test_active_renewal_and_current_pricing()
	_test_expired_renewal_and_work_accounting()
	_test_legacy_seven_day_expiry_boundary()
	_test_dismissal_forfeits_prepaid_time()
	_finish()

func _reset_fixture(day: int, hour: int, minute: int, wallet: int) -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	_set_clock(day, hour, minute)
	WorkerDatabase.onboarding_period_rates = FIXTURE_RATES.duplicate(true)
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	WorkerDatabase._payroll_settling = false
	CitizenManager.citizens_by_id.clear()
	Inventory.items.clear()
	if wallet > 0:
		Inventory.items["shekel"] = wallet
	CityStockManager.treasury_shekel = 0
	WorkManager.active_orders.clear()
	WorkManager.source_item_store_by_order_id.clear()
	WorkManager.output_item_store_by_order_id.clear()
	WorkManager.service_fee_by_order.clear()
	WorkManager.service_fee_currency_by_order.clear()
	WorkManager._last_total_minutes = _now_total_minutes()

func _seed_applicant(citizen_id: String, profession: WorkerData.Profession) -> CitizenData:
	var citizen: CitizenData = CitizenData.new()
	citizen.citizen_id = citizen_id
	citizen.display_name = "Fixture " + citizen_id
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.APPLICANT
	citizen.profession = profession
	citizen.satisfaction = 0.8
	CitizenManager.add_citizen(citizen)
	return citizen

func _test_package_hiring_and_wallet_atomicity() -> void:
	_reset_fixture(100, 8, 1, 25)
	var laborer: CitizenData = _seed_applicant("prepaid_fixture_laborer", WorkerData.Profession.LABORER)
	var hauler: CitizenData = _seed_applicant("prepaid_fixture_hauler", WorkerData.Profession.HAULER)
	var crafter: CitizenData = _seed_applicant("prepaid_fixture_crafter", WorkerData.Profession.CRAFTER)
	_expect(WorkerDatabase.get_contract_price(WorkerData.Profession.LABORER, 3) == 2
		and WorkerDatabase.get_contract_price(WorkerData.Profession.LABORER, 6) == 4
		and WorkerDatabase.get_contract_price(WorkerData.Profession.LABORER, 9) == 6,
		"Three-, six-, and nine-day package prices scale from the explicit Laborer fixture rate.")
	_expect(WorkerDatabase.get_contract_price(WorkerData.Profession.HAULER, 6) == 6
		and WorkerDatabase.get_contract_price(WorkerData.Profession.CRAFTER, 9) == 12,
		"Package prices use the applicant's profession rate.")

	_hire_watch_id = laborer.citizen_id
	_hire_watch_reentry_id = hauler.citizen_id
	_hire_watch_wallet = 23
	_hire_watch_start_minute = _now_total_minutes()
	_hire_inventory_callbacks = 0
	_hire_payroll_callbacks = 0
	_hire_reentry_results.clear()
	_hire_renewal_reentry_results.clear()
	_hire_reentry_active = false
	Inventory.items_changed.connect(_observe_hire_commit)
	WorkerDatabase.payroll_changed.connect(_observe_hire_commit)
	var first_worker: WorkerData = WorkerDatabase.hire_applicant(laborer.citizen_id, 17, 3)
	Inventory.items_changed.disconnect(_observe_hire_commit)
	WorkerDatabase.payroll_changed.disconnect(_observe_hire_commit)
	_expect(first_worker != null, "An applicant can buy a three-day contract with personal wallet Shekels.")
	_expect(_hire_inventory_callbacks == 1 and _hire_payroll_callbacks == 1
		and _hire_reentry_results == [true, true]
		and _hire_renewal_reentry_results == [true, true],
		"Both hire callbacks observe one complete transaction, and reentrant hire or renewal is rejected.")
	_expect(first_worker != null and first_worker.payroll_start_day == 100
		and first_worker.payroll_paid_from_day == 100
		and first_worker.payroll_paid_until_day == 103
		and first_worker.payroll_contract_days == 3
		and first_worker.payroll_period_rate == 2
		and first_worker.payroll_paid_start_minute == 100 * 1440 + 8 * 60 + 1
		and not first_worker.is_payroll_blocked()
		and laborer.employment_status == CitizenData.EmploymentStatus.HIRED,
		"A successful hire starts a paid contract at the exact purchase minute and ends on today plus D, inclusive.")
	_expect(Inventory.items.get("shekel", 0) == 23,
		"Hiring deducts exactly the three-day package price from the wallet.")
	_expect(hauler.employment_status == CitizenData.EmploymentStatus.APPLICANT
		and not WorkerDatabase.has_worker_data(hauler.citizen_id),
		"Commit callbacks cannot use the same wallet transaction to hire another eligible applicant.")

	_set_clock(100, 12, 34)
	var second_worker: WorkerData = WorkerDatabase.hire_applicant(hauler.citizen_id, 29, 6)
	_expect(second_worker != null and second_worker.payroll_contract_days == 6
		and second_worker.payroll_paid_until_day == 106
		and second_worker.payroll_period_rate == 6
		and second_worker.payroll_paid_start_minute == 100 * 1440 + 12 * 60 + 34,
		"A six-day hire records its own exact purchase time and paid-through day.")
	_set_clock(100, 16, 59)
	var third_worker: WorkerData = WorkerDatabase.hire_applicant(crafter.citizen_id, 31, 9)
	_expect(third_worker != null and third_worker.payroll_contract_days == 9
		and third_worker.payroll_paid_until_day == 109
		and third_worker.payroll_period_rate == 12
		and third_worker.payroll_paid_start_minute == 100 * 1440 + 16 * 60 + 59,
		"A nine-day hire is available at 16:59 and records its own exact contract.")
	_expect(Inventory.items.get("shekel", 0) == 5
		and WorkerDatabase.get_all_workers().size() == 3,
		"Three successful hires debit only their individual package prices.")

	var wallet_before_duplicate: int = Inventory.items.get("shekel", 0)
	_expect(WorkerDatabase.hire_applicant(laborer.citizen_id, 1, 3) == null
		and WorkerDatabase.get_worker_data(laborer.citizen_id) == first_worker
		and Inventory.items.get("shekel", 0) == wallet_before_duplicate,
		"A duplicate hire creates no second worker and charges no second package.")

func _observe_hire_commit() -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(_hire_watch_id)
	var citizen: CitizenData = CitizenManager.get_citizen(_hire_watch_id)
	var wallet_is_committed: bool = Inventory.items.get("shekel", 0) == _hire_watch_wallet
	var contract_is_committed: bool = (
		worker != null and citizen != null
		and citizen.employment_status == CitizenData.EmploymentStatus.HIRED
		and worker.payroll_paid_start_minute == _hire_watch_start_minute
		and not worker.is_payroll_blocked()
	)
	_expect(wallet_is_committed and contract_is_committed,
		"Hire observers see the wallet, roster, citizen status, and paid entitlement committed together.")
	if _hire_inventory_callbacks + _hire_payroll_callbacks == 0:
		_hire_inventory_callbacks += 1
	else:
		_hire_payroll_callbacks += 1
	if _hire_reentry_active:
		_hire_reentry_results.append(false)
		_hire_renewal_reentry_results.append(false)
		return
	_hire_reentry_active = true
	_hire_reentry_results.append(WorkerDatabase.hire_applicant(_hire_watch_reentry_id) == null)
	_hire_renewal_reentry_results.append(not WorkerDatabase.renew_contract(_hire_watch_id, 3))
	_hire_reentry_active = false

func _test_open_hours_and_rejections() -> void:
	_reset_fixture(110, 7, 59, 20)
	var early: CitizenData = _seed_applicant("prepaid_fixture_early", WorkerData.Profession.LABORER)
	_expect(WorkerDatabase.hire_applicant(early.citizen_id) == null
		and early.employment_status == CitizenData.EmploymentStatus.APPLICANT
		and WorkerDatabase.get_all_workers().is_empty()
		and Inventory.items.get("shekel", 0) == 20,
		"A 07:59 hire is rejected without changing the applicant, roster, or wallet.")
	_set_clock(110, 8, 1)
	var hired: WorkerData = WorkerDatabase.hire_applicant(early.citizen_id)
	_expect(hired != null and hired.payroll_paid_start_minute == 110 * 1440 + 8 * 60 + 1
		and Inventory.items.get("shekel", 0) == 18,
		"The same applicant can be hired at 08:01 today with an immediate wallet charge.")
	var late: CitizenData = _seed_applicant("prepaid_fixture_late", WorkerData.Profession.LABORER)
	_set_clock(110, 17, 0)
	_expect(WorkerDatabase.hire_applicant(late.citizen_id) == null
		and late.employment_status == CitizenData.EmploymentStatus.APPLICANT
		and Inventory.items.get("shekel", 0) == 18,
		"A 17:00 hire is rejected without changing the applicant or wallet.")

	_reset_fixture(111, 8, 1, 1)
	var poor: CitizenData = _seed_applicant("prepaid_fixture_poor_wallet", WorkerData.Profession.LABORER)
	CityStockManager.treasury_shekel = CityStockManager.MAX_SHEKEL
	var rich_city_wallet_before: int = Inventory.items.get("shekel", 0)
	var rich_city_worker_count: int = WorkerDatabase.get_all_workers().size()
	_expect(WorkerDatabase.hire_applicant(poor.citizen_id) == null
		and poor.employment_status == CitizenData.EmploymentStatus.APPLICANT
		and WorkerDatabase.get_all_workers().size() == rich_city_worker_count
		and Inventory.items.get("shekel", 0) == rich_city_wallet_before
		and CityStockManager.treasury_shekel == CityStockManager.MAX_SHEKEL,
		"An empty personal wallet rejects hiring even with a full city treasury, without mutations.")

	_reset_fixture(112, 10, 0, 30)
	var invalid: CitizenData = _seed_applicant("prepaid_fixture_invalid_package", WorkerData.Profession.LABORER)
	for invalid_days: int in [0, 2, 4, -3, 10]:
		_expect(WorkerDatabase.get_contract_price(WorkerData.Profession.LABORER, invalid_days) == -1,
			"Unsupported package duration %d has no price." % invalid_days)
		var wallet_before_invalid: int = Inventory.items.get("shekel", 0)
		_expect(WorkerDatabase.hire_applicant(invalid.citizen_id, 1, invalid_days) == null
			and invalid.employment_status == CitizenData.EmploymentStatus.APPLICANT
			and not WorkerDatabase.has_worker_data(invalid.citizen_id)
			and Inventory.items.get("shekel", 0) == wallet_before_invalid,
			"Invalid package duration %d is rejected atomically." % invalid_days)

func _test_contract_day_limit() -> void:
	_expect(WorkerDatabase.CONTRACT_DAYS == [3, 6, 9],
		"The public contract package choices are the supported three, six, and nine days.")
	_reset_fixture(WorkerDatabase.MAX_CONTRACT_DAY - 3, 10, 0, 20)
	var boundary_citizen: CitizenData = _seed_applicant("prepaid_fixture_max_day_boundary", WorkerData.Profession.LABORER)
	var boundary_worker: WorkerData = WorkerDatabase.hire_applicant(boundary_citizen.citizen_id, 1, 3)
	_expect(boundary_worker != null
		and boundary_worker.payroll_paid_until_day == WorkerDatabase.MAX_CONTRACT_DAY,
		"A package ending exactly at MAX_CONTRACT_DAY is allowed.")
	if boundary_worker != null:
		var boundary_wallet: int = Inventory.items.get("shekel", 0)
		_expect(not WorkerDatabase.renew_contract(boundary_worker.worker_id, 3)
			and boundary_worker.payroll_paid_until_day == WorkerDatabase.MAX_CONTRACT_DAY
			and Inventory.items.get("shekel", 0) == boundary_wallet,
			"Renewal beyond MAX_CONTRACT_DAY is rejected without changing the contract or wallet.")

	_reset_fixture(WorkerDatabase.MAX_CONTRACT_DAY - 2, 10, 0, 20)
	var overflow_citizen: CitizenData = _seed_applicant("prepaid_fixture_max_day_overflow", WorkerData.Profession.LABORER)
	_expect(WorkerDatabase.hire_applicant(overflow_citizen.citizen_id, 1, 3) == null
		and not WorkerDatabase.has_worker_data(overflow_citizen.citizen_id)
		and overflow_citizen.employment_status == CitizenData.EmploymentStatus.APPLICANT
		and Inventory.items.get("shekel", 0) == 20,
		"A hire whose end date would exceed MAX_CONTRACT_DAY is rejected atomically.")

func _test_active_renewal_and_current_pricing() -> void:
	_reset_fixture(120, 8, 1, 100)
	var renewing_citizen: CitizenData = _seed_applicant("prepaid_fixture_renewing", WorkerData.Profession.LABORER)
	var other_citizen: CitizenData = _seed_applicant("prepaid_fixture_other_paid", WorkerData.Profession.HAULER)
	var second_purchase_citizen: CitizenData = _seed_applicant("prepaid_fixture_new_price", WorkerData.Profession.LABORER)
	var blocked_reentry_citizen: CitizenData = _seed_applicant("prepaid_fixture_reentry_applicant", WorkerData.Profession.LABORER)
	var renewing_worker: WorkerData = WorkerDatabase.hire_applicant(renewing_citizen.citizen_id, 3, 3)
	_set_clock(120, 8, 15)
	var other_worker: WorkerData = WorkerDatabase.hire_applicant(other_citizen.citizen_id, 4, 3)
	_expect(renewing_worker != null and other_worker != null,
		"The renewal fixture starts with two independently prepaid workers.")
	if renewing_worker == null or other_worker == null:
		return
	var original_start_day: int = renewing_worker.payroll_start_day
	var original_paid_from_day: int = renewing_worker.payroll_paid_from_day
	var original_paid_start_minute: int = renewing_worker.payroll_paid_start_minute
	var original_paid_until_day: int = renewing_worker.payroll_paid_until_day
	var original_contract_rate: int = renewing_worker.payroll_period_rate
	var other_snapshot: Array[int] = [other_worker.payroll_start_day, other_worker.payroll_paid_from_day,
		other_worker.payroll_paid_until_day, other_worker.payroll_period_rate,
		other_worker.payroll_last_attempt_day, other_worker.payroll_paid_start_minute]
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 5
	_expect(renewing_worker.payroll_period_rate == original_contract_rate
		and WorkerDatabase.get_contract_price(WorkerData.Profession.LABORER, 6) == 10,
		"Changing a profession's quote leaves the existing purchase locked while the next quote uses the new rate.")

	_set_clock(121, 10, 10)
	_renew_watch_id = renewing_citizen.citizen_id
	_renew_watch_other_applicant_id = blocked_reentry_citizen.citizen_id
	_renew_watch_wallet_before = Inventory.items.get("shekel", 0)
	_renew_watch_wallet_after = _renew_watch_wallet_before - 10
	_renew_watch_old_paid_until = original_paid_until_day
	_renew_watch_new_paid_until = original_paid_until_day + 6
	_renew_watch_new_rate = 10
	_renew_settling_callbacks = 0
	_renew_inventory_callbacks = 0
	_renew_payroll_callbacks = 0
	_renew_settling_reentry_results.clear()
	_renew_hire_reentry_results.clear()
	_renew_commit_reentry_results.clear()
	_renew_reentry_active = false
	WorkerDatabase.payroll_settling.connect(_observe_renew_settling)
	Inventory.items_changed.connect(_observe_renew_commit)
	WorkerDatabase.payroll_changed.connect(_observe_renew_commit)
	var renewed: bool = WorkerDatabase.renew_contract(renewing_worker.worker_id, 6)
	WorkerDatabase.payroll_settling.disconnect(_observe_renew_settling)
	Inventory.items_changed.disconnect(_observe_renew_commit)
	WorkerDatabase.payroll_changed.disconnect(_observe_renew_commit)
	_expect(renewed, "An active contract can be renewed early by purchasing another six-day package.")
	_expect(_renew_settling_callbacks == 1 and _renew_inventory_callbacks == 1
		and _renew_payroll_callbacks == 1 and _renew_settling_reentry_results == [true]
		and _renew_hire_reentry_results == [true, true, true]
		and _renew_commit_reentry_results == [true, true],
		"Renewal settlement and commit callbacks are atomic and reject nested wallet transactions.")
	_expect(renewing_worker.payroll_start_day == original_start_day
		and renewing_worker.payroll_paid_from_day == original_paid_from_day
		and renewing_worker.payroll_paid_start_minute == original_paid_start_minute
		and renewing_worker.payroll_paid_until_day == original_paid_until_day + 6
		and renewing_worker.payroll_contract_days == 6
		and renewing_worker.payroll_period_rate == 10
		and renewing_worker.payroll_last_attempt_day == 121
		and not renewing_worker.is_payroll_blocked(),
		"Early renewal appends six days to the old end date and retains the original paid start.")
	_expect(other_snapshot == [other_worker.payroll_start_day, other_worker.payroll_paid_from_day,
		other_worker.payroll_paid_until_day, other_worker.payroll_period_rate,
		other_worker.payroll_last_attempt_day, other_worker.payroll_paid_start_minute]
		and not other_worker.is_payroll_blocked(),
		"Renewing one worker does not alter another worker's paid contract.")
	_expect(Inventory.items.get("shekel", 0) == _renew_watch_wallet_after
		and blocked_reentry_citizen.employment_status == CitizenData.EmploymentStatus.APPLICANT
		and not WorkerDatabase.has_worker_data(blocked_reentry_citizen.citizen_id),
		"The renewal spends only its own current-price quote; attempted cross-worker reentry changes nothing.")
	_expect(not WorkerDatabase.renew_contract(renewing_worker.worker_id, 2)
		and not WorkerDatabase.renew_contract("missing_prepaid_fixture_worker", 3)
		and renewing_worker.payroll_paid_until_day == original_paid_until_day + 6
		and Inventory.items.get("shekel", 0) == _renew_watch_wallet_after,
		"Invalid or missing-worker renewals do not mutate the paid contract or wallet.")

	var new_price_worker: WorkerData = WorkerDatabase.hire_applicant(second_purchase_citizen.citizen_id, 2, 3)
	_expect(new_price_worker != null and new_price_worker.payroll_period_rate == 5
		and new_price_worker.payroll_paid_until_day == 124
		and Inventory.items.get("shekel", 0) == _renew_watch_wallet_after - 5,
		"The next Laborer purchase uses the changed profession price.")
	var wallet_before_refresh: int = Inventory.items.get("shekel", 0)
	var paid_until_before_eight: int = renewing_worker.payroll_paid_until_day
	_set_clock(122, 7, 0)
	TimeComponentManager.hour_changed.emit(7)
	_set_clock(122, 8, 0)
	TimeComponentManager.hour_changed.emit(8)
	_expect(Inventory.items.get("shekel", 0) == wallet_before_refresh
		and CityStockManager.treasury_shekel == 0
		and renewing_worker.payroll_paid_until_day == paid_until_before_eight
		and not renewing_worker.is_payroll_blocked()
		and other_worker.payroll_paid_until_day == other_snapshot[2],
		"The 07:00 and 08:00 refresh notifications perform no group charge or mutation.")

func _observe_renew_settling() -> void:
	_renew_settling_callbacks += 1
	var worker: WorkerData = WorkerDatabase.get_worker_data(_renew_watch_id)
	_expect(worker != null and worker.payroll_paid_until_day == _renew_watch_old_paid_until
		and worker.payroll_period_rate == 2
		and Inventory.items.get("shekel", 0) == _renew_watch_wallet_before,
		"The settlement callback sees the old entitlement and unchanged wallet before renewal commits.")
	if _renew_reentry_active:
		_renew_settling_reentry_results.append(false)
		_renew_hire_reentry_results.append(false)
		return
	_renew_reentry_active = true
	_renew_settling_reentry_results.append(not WorkerDatabase.renew_contract(_renew_watch_id, 3))
	_renew_hire_reentry_results.append(WorkerDatabase.hire_applicant(_renew_watch_other_applicant_id) == null)
	_renew_reentry_active = false

func _observe_renew_commit() -> void:
	if _renew_inventory_callbacks + _renew_payroll_callbacks == 0:
		_renew_inventory_callbacks += 1
	else:
		_renew_payroll_callbacks += 1
	var worker: WorkerData = WorkerDatabase.get_worker_data(_renew_watch_id)
	_expect(worker != null and worker.payroll_paid_until_day == _renew_watch_new_paid_until
		and worker.payroll_period_rate == _renew_watch_new_rate
		and Inventory.items.get("shekel", 0) == _renew_watch_wallet_after,
		"Renewal commit observers see the appended entitlement and matching wallet debit together.")
	if _renew_reentry_active:
		_renew_commit_reentry_results.append(false)
		_renew_hire_reentry_results.append(false)
		return
	_renew_reentry_active = true
	_renew_commit_reentry_results.append(not WorkerDatabase.renew_contract(_renew_watch_id, 3))
	_renew_hire_reentry_results.append(WorkerDatabase.hire_applicant(_renew_watch_other_applicant_id) == null)
	_renew_reentry_active = false

func _test_expired_renewal_and_work_accounting() -> void:
	_reset_fixture(60, 9, 0, 20)
	var citizen: CitizenData = _seed_applicant("prepaid_fixture_expired_worker", WorkerData.Profession.LABORER)
	var worker: WorkerData = WorkerDatabase.hire_applicant(citizen.citizen_id, 1, 3)
	_expect(worker != null, "The work-accounting fixture purchases a three-day contract.")
	if worker == null:
		return
	var job: JobData = JobData.new()
	job.job_id = FIXTURE_WORK_ORDER_ID
	job.display_name = "Prepaid contract fixture order"
	job.requirement_profession = WorkerData.Profession.LABORER
	job.base_duration_minutes = 20000
	var initial_order_start: int = _now_total_minutes()
	var order_id: String = WorkManager.start_job(
		job,
		WorkOrder.Worker_Type.NPC,
		worker.worker_id,
		null,
		Inventory,
		Inventory
	)
	var order: WorkOrder = WorkManager.active_orders.get(order_id, null)
	_expect(not order_id.is_empty() and order != null,
		"An actively paid worker can start a real WorkManager order for accounting coverage.")
	if order == null:
		return
	var original_duration: int = order.end_time_total_minutes - order.start_time_total_minutes
	_expect(order.start_time_total_minutes == initial_order_start and original_duration == 20000,
		"The fixture order starts at the exact worker purchase clock with its requested duration.")

	_set_clock(60, 9, 10)
	WorkManager.on_time_changed(60, 9, 10)
	_expect(order.start_time_total_minutes == initial_order_start
		and order.end_time_total_minutes - order.start_time_total_minutes == original_duration,
		"WorkManager does not pause or lengthen the order during paid minutes.")
	_set_clock(63, 23, 59)
	WorkManager.on_time_changed(63, 23, 59)
	_expect(not worker.is_payroll_blocked()
		and order.start_time_total_minutes == initial_order_start,
		"The paid-through day remains inclusive through 23:59.")
	_set_clock(64, 6, 59)
	WorkManager.on_time_changed(64, 6, 59)
	_expect(not worker.is_payroll_blocked()
		and order.start_time_total_minutes == initial_order_start,
		"The contract remains active through 06:59 on the following day.")
	_set_clock(64, 7, 0)
	WorkManager.on_time_changed(64, 7, 0)
	var paid_end_minute: int = worker.get_paid_end_minute()
	_expect(worker.is_payroll_blocked()
		and worker.get_payroll_unpaid_minutes(paid_end_minute, paid_end_minute) == 0
		and order.start_time_total_minutes == initial_order_start,
		"The prepaid contract expires exactly at 07:00, with no unpaid minute before that boundary.")
	_set_clock(64, 8, 30)
	WorkManager.on_time_changed(64, 8, 30)
	var renewal_minute: int = _now_total_minutes()
	_expect(worker.get_payroll_unpaid_minutes(paid_end_minute, renewal_minute) == 90
		and order.start_time_total_minutes == initial_order_start + 90
		and order.end_time_total_minutes == initial_order_start + original_duration + 90
		and order.end_time_total_minutes - order.start_time_total_minutes == original_duration,
		"An existing WorkManager order shifts by each unpaid minute across the expired coverage gap.")
	var renewed: bool = WorkerDatabase.renew_contract(worker.worker_id, 6)
	_expect(renewed and worker.payroll_paid_from_day == 64
		and worker.payroll_paid_start_minute == renewal_minute
		and worker.payroll_paid_until_day == 70
		and not worker.is_payroll_blocked(),
		"Expired renewal at 08:30 starts at that exact minute and buys today plus six inclusive days.")
	_expect(worker.get_payroll_unpaid_minutes(paid_end_minute, renewal_minute) == 90
		and order.start_time_total_minutes == initial_order_start + 90
		and order.end_time_total_minutes == initial_order_start + original_duration + 90,
		"Expired renewal leaves the elapsed gap unpaid and does not backdate the new contract.")
	_cleanup_work_order(order_id, worker)

func _cleanup_work_order(order_id: String, worker: WorkerData) -> void:
	worker.finish_work(order_id)
	WorkManager.active_orders.erase(order_id)
	WorkManager.source_item_store_by_order_id.erase(order_id)
	WorkManager.output_item_store_by_order_id.erase(order_id)
	WorkManager.service_fee_by_order.erase(order_id)
	WorkManager.service_fee_currency_by_order.erase(order_id)

func _test_legacy_seven_day_expiry_boundary() -> void:
	_reset_fixture(151, 7, 59, 0)
	var legacy_worker: WorkerData = WorkerData.new()
	legacy_worker.worker_id = "prepaid_fixture_untouched_legacy_worker"
	legacy_worker.payroll_start_day = 140
	legacy_worker.payroll_paid_from_day = 140
	legacy_worker.payroll_paid_until_day = 150
	legacy_worker.payroll_contract_days = 0
	legacy_worker.payroll_paid_start_minute = -1
	_expect(legacy_worker.get_paid_end_minute() == 151 * 1440 + 480
		and not legacy_worker.is_payroll_blocked(),
		"An untouched legacy seven-day record retains its 08:00 expiry boundary.")
	_set_clock(151, 8, 0)
	_expect(legacy_worker.is_payroll_blocked(),
		"The untouched legacy record expires at 08:00 after its inclusive paid-through day.")

func _test_dismissal_forfeits_prepaid_time() -> void:
	_reset_fixture(80, 10, 0, 10)
	var citizen: CitizenData = _seed_applicant("prepaid_fixture_dismissed", WorkerData.Profession.LABORER)
	var worker: WorkerData = WorkerDatabase.hire_applicant(citizen.citizen_id, 9, 3)
	_expect(worker != null and Inventory.items.get("shekel", 0) == 8,
		"The dismissal fixture pays the package from the wallet before dismissal.")
	if worker == null:
		return
	var contract_end_day: int = worker.payroll_paid_until_day
	_expect(WorkerDatabase.dismiss_worker(worker.worker_id), "An idle prepaid worker can be dismissed.")
	_expect(Inventory.items.get("shekel", 0) == 8
		and not WorkerDatabase.has_worker_data(worker.worker_id)
		and WorkerDatabase.dismissed_workers.get(worker.worker_id) == worker
		and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED,
		"Dismissal forfeits remaining paid time without refunding wallet Shekels.")
	_set_clock(contract_end_day + 1, 7, 0)
	TimeComponentManager.hour_changed.emit(7)
	_set_clock(contract_end_day + 1, 8, 0)
	TimeComponentManager.hour_changed.emit(8)
	_expect(Inventory.items.get("shekel", 0) == 8
		and CityStockManager.treasury_shekel == 0
		and not WorkerDatabase.has_worker_data(worker.worker_id),
		"A dismissed worker receives no later automatic renewal charge or refund.")

func _set_clock(day: int, hour: int, minute: int) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute

func _now_total_minutes() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _finish() -> void:
	var status: String = "PASS" if failures == 0 else "FAIL"
	print("PrepaidContractsFixtureTest: %s (%d checks failed)" % [status, failures])
	get_tree().quit(0 if failures == 0 else 1)
