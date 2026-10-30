extends Node

const TEST_WORKER_IDS: Array[String] = [
	"payroll_fixture_early_laborer",
	"payroll_fixture_early_hauler",
	"payroll_fixture_early_crafter",
	"payroll_fixture_late_laborer",
	"payroll_fixture_after_hours",
	"payroll_fixture_later_unpaid"
]
const FIXTURE_RATES: Dictionary = {
	WorkerData.Profession.LABORER: 1,
	WorkerData.Profession.HAULER: 2,
	WorkerData.Profession.CRAFTER: 2
}

var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 10
	TimeComponentManager.current_hour = 16
	TimeComponentManager.current_minute = 59

	# These prices and wallet funds belong to this isolated fixture. Production rates
	# remain unset until the Game Director provides them.
	WorkerDatabase.onboarding_period_rates = {}
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	CitizenManager.citizens_by_id.clear()
	Inventory.items.clear()
	CityStockManager.treasury_shekel = 0
	for citizen_id: String in TEST_WORKER_IDS:
		CitizenManager.add_citizen(_make_applicant(citizen_id))

	_expect(WorkerDatabase.hire_applicant(TEST_WORKER_IDS[0]) == null, "Unpriced profession cannot silently use a guessed balance value.")
	_expect(WorkerDatabase.get_all_workers().is_empty(), "Rejected unpriced hire preserves roster.")
	WorkerDatabase.onboarding_period_rates = FIXTURE_RATES.duplicate()
	_test_wallet_deposit_guards()
	_test_first_payroll_flow()
	_finish()

func _make_applicant(citizen_id: String) -> CitizenData:
	var citizen: CitizenData = CitizenData.new()
	citizen.citizen_id = citizen_id
	citizen.display_name = citizen_id
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.APPLICANT
	citizen.satisfaction = 0.8
	match citizen_id:
		"payroll_fixture_early_hauler":
			citizen.profession = WorkerData.Profession.HAULER
		"payroll_fixture_early_crafter":
			citizen.profession = WorkerData.Profession.CRAFTER
		_:
			citizen.profession = WorkerData.Profession.LABORER
	return citizen

func _test_wallet_deposit_guards() -> void:
	Inventory.add_item("shekel", 10)
	_expect(not CityStockManager.deposit_wallet_shekel(0),
		"A zero wallet deposit is rejected.")
	_expect(not CityStockManager.deposit_wallet_shekel(-1),
		"A negative wallet deposit is rejected.")
	_expect(not CityStockManager.deposit_wallet_shekel(11),
		"A deposit larger than the personal wallet is rejected.")
	_expect(CityStockManager.treasury_shekel == 0
		and Inventory.items.get("shekel", 0) == 10,
		"Invalid deposits preserve both city and personal balances.")

	CityStockManager.treasury_shekel = CityStockManager.MAX_SHEKEL - 1
	_expect(not CityStockManager.deposit_wallet_shekel(2),
		"A deposit that would overflow city treasury capacity is rejected.")
	_expect(CityStockManager.treasury_shekel == CityStockManager.MAX_SHEKEL - 1
		and Inventory.items.get("shekel", 0) == 10,
		"An overflow rejection transfers no shekels from the wallet.")
	CityStockManager.treasury_shekel = 0

func _test_first_payroll_flow() -> void:
	var laborer: WorkerData = _hire(TEST_WORKER_IDS[0])
	var hauler: WorkerData = _hire(TEST_WORKER_IDS[1])
	var crafter: WorkerData = _hire(TEST_WORKER_IDS[2])
	_expect(laborer != null and hauler != null and crafter != null,
		"Applicants can be hired at 16:59 with explicitly injected fixture rates.")
	if laborer == null or hauler == null or crafter == null:
		return
	_expect(laborer.payroll_start_day == 11
		and hauler.payroll_start_day == 11
		and crafter.payroll_start_day == 11,
		"Hires made on day 10 start payroll on day 11.")
	_expect(laborer.is_waiting_for_first_payment()
		and hauler.is_waiting_for_first_payment()
		and crafter.is_waiting_for_first_payment(),
		"New hires remain unpaid until their first city payment.")
	_set_clock(10, 17, 0)
	_expect(WorkerDatabase.hire_applicant(TEST_WORKER_IDS[4]) == null,
		"Hiring is closed at exactly 17:00.")

	var no_input_job: JobData = JobData.new()
	no_input_job.job_id = "payroll_fixture_no_input_job"
	no_input_job.display_name = "Payroll fixture job"
	no_input_job.requirement_profession = WorkerData.Profession.LABORER
	no_input_job.base_duration_minutes = 30
	var blocked_order_id: String = WorkManager.start_job(
		no_input_job,
		WorkOrder.Worker_Type.NPC,
		laborer.worker_id
	)
	_expect(blocked_order_id.is_empty()
		and WorkManager.get_last_start_job_error().contains("payment"),
		"An unpaid new worker cannot start a work order.")
	_expect(laborer.current_order_id.is_empty(),
		"Rejected unpaid work does not reserve the worker.")

	# Personal shekels do not fund payroll automatically. At 08:00 the entire
	# three-worker quote (1 + 2 + 2) is short, so nobody receives partial cover.
	_set_clock(11, 7, 59)
	TimeComponentManager.advance_minutes(1)
	_expect(CityStockManager.treasury_shekel == 0
		and Inventory.items.get("shekel", 0) == 10,
		"Zero city funds leave personal wallet funds untouched and pay nobody.")
	_expect(laborer.payroll_last_attempt_day == 11
		and hauler.payroll_last_attempt_day == 11
		and crafter.payroll_last_attempt_day == 11
		and laborer.is_waiting_for_first_payment()
		and hauler.is_waiting_for_first_payment()
		and crafter.is_waiting_for_first_payment(),
		"The zero-funds attempt marks each due worker and leaves the group unpaid.")
	TimeComponentManager.hour_changed.emit(8)
	TimeComponentManager.emit_time_signal()
	_expect(CityStockManager.treasury_shekel == 0
		and laborer.is_waiting_for_first_payment()
		and hauler.is_waiting_for_first_payment()
		and crafter.is_waiting_for_first_payment(),
		"Duplicate 08:00 callbacks and a time snapshot do not retry or charge payroll.")

	_expect(CityStockManager.deposit_wallet_shekel(4),
		"An explicit wallet deposit within treasury capacity succeeds.")
	_expect(CityStockManager.treasury_shekel == 4
		and Inventory.items.get("shekel", 0) == 6,
		"A valid deposit transfers exactly the requested amount.")
	var first_quote: Dictionary = WorkerDatabase.get_first_payment_quote(11)
	_expect(int(first_quote.get("total", -1)) == 5
		and int(first_quote.get("shortfall", -1)) == 1,
		"The first-payment quote includes the explicit injected rates and shortfall.")
	_expect(laborer.is_waiting_for_first_payment()
		and hauler.is_waiting_for_first_payment()
		and crafter.is_waiting_for_first_payment()
		and CityStockManager.treasury_shekel == 4,
		"A midday deposit does not trigger an immediate or repeated attempt.")

	_set_clock(11, 16, 59)
	var later_laborer: WorkerData = _hire(TEST_WORKER_IDS[3])
	_expect(later_laborer != null and later_laborer.payroll_start_day == 12,
		"A worker hired at 16:59 on day 11 joins the next day's payroll group.")
	_set_clock(11, 17, 0)
	_expect(WorkerDatabase.hire_applicant(TEST_WORKER_IDS[4]) == null,
		"A second 17:00 check also rejects a new hire.")
	if later_laborer == null:
		return

	_set_clock(12, 7, 59)
	TimeComponentManager.advance_minutes(1)
	var second_quote: Dictionary = WorkerDatabase.get_first_payment_quote(12)
	_expect(int(second_quote.get("count", -1)) == 4
		and int(second_quote.get("total", -1)) == 6
		and int(second_quote.get("shortfall", -1)) == 2,
		"The later hire joins the earlier still-pending workers in one due quote.")
	_expect(CityStockManager.treasury_shekel == 4
		and laborer.is_waiting_for_first_payment()
		and hauler.is_waiting_for_first_payment()
		and crafter.is_waiting_for_first_payment()
		and later_laborer.is_waiting_for_first_payment(),
		"Insufficient funds pay none of the four due workers.")
	_expect(laborer.payroll_last_attempt_day == 12
		and hauler.payroll_last_attempt_day == 12
		and crafter.payroll_last_attempt_day == 12
		and later_laborer.payroll_last_attempt_day == 12,
		"Each worker in the short-funds attempt records day 12.")

	_expect(CityStockManager.deposit_wallet_shekel(2),
		"The wallet can provide the exact remaining payroll shortfall.")
	TimeComponentManager.hour_changed.emit(8)
	TimeComponentManager.emit_time_signal()
	_expect(CityStockManager.treasury_shekel == 6
		and laborer.is_waiting_for_first_payment()
		and hauler.is_waiting_for_first_payment()
		and crafter.is_waiting_for_first_payment()
		and later_laborer.is_waiting_for_first_payment(),
		"Midday funding and repeated callbacks do not pay workers before tomorrow.")

	_set_clock(13, 7, 59)
	TimeComponentManager.advance_minutes(1)
	_expect(CityStockManager.treasury_shekel == 0,
		"Enough treasury funds pay the full due group exactly once.")
	_expect(laborer.payroll_paid_from_day == 13
		and hauler.payroll_paid_from_day == 13
		and crafter.payroll_paid_from_day == 13
		and later_laborer.payroll_paid_from_day == 13,
		"All earlier pending workers receive the same first-payment day.")
	_expect(laborer.payroll_paid_until_day == 19
		and hauler.payroll_paid_until_day == 19
		and crafter.payroll_paid_until_day == 19
		and later_laborer.payroll_paid_until_day == 19,
		"Each initial payment records the seven-day paid-through date.")
	_expect(laborer.payroll_period_rate == 1
		and hauler.payroll_period_rate == 2
		and crafter.payroll_period_rate == 2
		and later_laborer.payroll_period_rate == 1,
		"Each worker records the fixture rate for their profession.")
	var paid_treasury: int = CityStockManager.treasury_shekel
	TimeComponentManager.hour_changed.emit(8)
	TimeComponentManager.emit_time_signal()
	_expect(CityStockManager.treasury_shekel == paid_treasury,
		"Duplicate callbacks and a state snapshot do not charge an already-paid group again.")

	_set_clock(13, 16, 59)
	var later_unpaid: WorkerData = _hire(TEST_WORKER_IDS[5])
	_expect(later_unpaid != null and later_unpaid.payroll_start_day == 14,
		"A new hire after the earlier group is paid starts on day 14.")
	if later_unpaid == null:
		return
	_set_clock(14, 7, 59)
	TimeComponentManager.advance_minutes(1)
	_expect(later_unpaid.is_waiting_for_first_payment()
		and later_unpaid.payroll_last_attempt_day == 14,
		"The later worker remains unpaid after its zero-funds first attempt.")
	_expect(laborer.payroll_paid_from_day == 13
		and laborer.payroll_paid_until_day == 19
		and hauler.payroll_paid_from_day == 13
		and crafter.payroll_paid_from_day == 13
		and later_laborer.payroll_paid_from_day == 13,
		"A later unpaid worker does not change the earlier workers' paid records.")

	_expect(WorkerDatabase.assign_worker(laborer.worker_id), "A paid worker remains assignable while a later group is unpaid.")
	WorkerDatabase.unassign_worker(laborer.worker_id)

func _hire(citizen_id: String) -> WorkerData:
	return WorkerDatabase.hire_applicant(citizen_id, 99)

func _set_clock(day: int, hour: int, minute: int) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute

func _finish() -> void:
	var status: String = "PASS" if failures == 0 else "FAIL"
	print("WorkerPayrollFixtureTest: %s (%d checks failed)" % [status, failures])
	get_tree().quit(0 if failures == 0 else 1)
