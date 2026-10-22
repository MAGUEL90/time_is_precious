extends Node

const CONSTRUCTION_SCRIPT: Script = preload("res://scenes/workshop_plot/workshop_construction_state.gd")
const DUE_WORKER_IDS: Array[String] = [
	"payroll_renewal_fixture_renewal_worker",
	"payroll_renewal_fixture_construction_worker",
	"payroll_renewal_fixture_new_worker",
	"payroll_renewal_fixture_waiting_worker"
]
const CONTINUING_WORKER_ID: String = "payroll_renewal_fixture_continuing_worker"
const LEGACY_WORKER_ID: String = "payroll_renewal_fixture_legacy_worker"
const FIXTURE_RATES: Dictionary = {
	WorkerData.Profession.LABORER: 3,
	WorkerData.Profession.HAULER: 2,
	WorkerData.Profession.CRAFTER: 1
}
const INITIAL_DAY: int = 20
const RENEWAL_DAY: int = INITIAL_DAY + 1
const RESUME_DAY: int = INITIAL_DAY + 2
const FIXTURE_JOB_ID: String = "payroll_renewal_fixture_long_job"
const FIXTURE_PROCESS_ID: String = "payroll_renewal_fixture_drying"
const FIXTURE_STATION_ID: String = "payroll_renewal_fixture_drying_station"
const FIXTURE_INPUTS: Dictionary = {
	"wood_log": 6,
	"clay_lump": 13,
	"reed_bundle": 8,
	"straw_bundle": 3,
	"water_jar": 3,
	"wet_mudbrick": 1,
	"shekel": 1
}

var failures: int = 0
var _construction_state: Variant

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = true
	TimeComponentManager.current_day = INITIAL_DAY
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_minute = 0
	TimeComponentManager.emit_time_signal()

	# All prices, periods, workers, cash, materials, and jobs below are fixture grants.
	# They isolate renewal behavior and do not define production balance values.
	WorkerDatabase.onboarding_period_rates = FIXTURE_RATES.duplicate()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	CitizenManager.citizens_by_id.clear()
	Inventory.items.clear()
	Inventory.add_bulk_item(FIXTURE_INPUTS)
	CityStockManager.treasury_shekel = 8
	_seed_existing_worker(DUE_WORKER_IDS[0], WorkerData.Profession.LABORER, INITIAL_DAY - 6, INITIAL_DAY, 1)
	_seed_existing_worker(DUE_WORKER_IDS[1], WorkerData.Profession.LABORER, INITIAL_DAY - 6, INITIAL_DAY, 2)
	_seed_existing_worker(CONTINUING_WORKER_ID, WorkerData.Profession.LABORER, INITIAL_DAY, INITIAL_DAY + 6, 2)
	_seed_waiting_worker(DUE_WORKER_IDS[3], WorkerData.Profession.CRAFTER, INITIAL_DAY, INITIAL_DAY)
	_seed_legacy_worker()
	_seed_new_hire()

	_expect(WorkerDatabase.get_worker_data(DUE_WORKER_IDS[0]).payroll_period_rate == 1
		and WorkerDatabase.get_worker_data(DUE_WORKER_IDS[1]).payroll_period_rate == 2
		and WorkerDatabase.get_worker_data(CONTINUING_WORKER_ID).payroll_period_rate == 2,
		"The fixture grants explicit older locked rates while the current laborer rate is higher.")
	_expect(not WorkerDatabase.get_worker_data(DUE_WORKER_IDS[0]).is_payroll_blocked()
		and not WorkerDatabase.get_worker_data(CONTINUING_WORKER_ID).is_payroll_blocked(),
		"Workers with a paid period remain entitled to work before their renewal boundary.")
	_expect(WorkerDatabase.get_worker_data(LEGACY_WORKER_ID).payroll_start_day == -1
		and not WorkerDatabase.get_worker_data(LEGACY_WORKER_ID).is_payroll_blocked()
		and not WorkerDatabase.get_worker_data(LEGACY_WORKER_ID).is_payroll_due(RENEWAL_DAY),
		"A legacy worker with no payroll start day remains exempt from payroll blocking.")

	var new_worker: WorkerData = WorkerDatabase.get_worker_data(DUE_WORKER_IDS[2])
	_expect(new_worker != null and new_worker.payroll_start_day == RENEWAL_DAY
		and new_worker.is_payroll_blocked(),
		"A hire made on day 20 joins the day 21 morning payroll group.")

	_start_fixture_construction()
	_start_fixture_work_order()
	_start_fixture_drying()
	_test_atomic_renewal_failure_and_resume()
	_finish()

func _seed_citizen(worker_id: String, profession: WorkerData.Profession, employment: CitizenData.EmploymentStatus) -> CitizenData:
	var citizen: CitizenData = CitizenData.new()
	citizen.citizen_id = worker_id
	citizen.display_name = "TEST " + worker_id
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = employment
	citizen.profession = profession
	citizen.satisfaction = 0.8
	CitizenManager.citizens_by_id[worker_id] = citizen
	return citizen

func _seed_existing_worker(worker_id: String, profession: WorkerData.Profession, paid_from_day: int, paid_until_day: int, locked_rate: int) -> WorkerData:
	_seed_citizen(worker_id, profession, CitizenData.EmploymentStatus.HIRED)
	var worker: WorkerData = WorkerData.new()
	worker.worker_id = worker_id
	worker.display_name = "TEST " + worker_id
	worker.profession = profession
	worker.payroll_start_day = paid_from_day
	worker.payroll_paid_from_day = paid_from_day
	worker.payroll_paid_until_day = paid_until_day
	worker.payroll_period_rate = locked_rate
	worker.payroll_last_attempt_day = paid_from_day
	WorkerDatabase.workers_by_id[worker_id] = worker
	return worker

func _seed_waiting_worker(worker_id: String, profession: WorkerData.Profession, start_day: int, last_attempt_day: int) -> WorkerData:
	_seed_citizen(worker_id, profession, CitizenData.EmploymentStatus.HIRED)
	var worker: WorkerData = WorkerData.new()
	worker.worker_id = worker_id
	worker.display_name = "TEST " + worker_id
	worker.profession = profession
	worker.payroll_start_day = start_day
	worker.payroll_paid_from_day = -1
	worker.payroll_paid_until_day = -1
	worker.payroll_period_rate = 0
	worker.payroll_last_attempt_day = last_attempt_day
	WorkerDatabase.workers_by_id[worker_id] = worker
	return worker

func _seed_legacy_worker() -> void:
	_seed_citizen(LEGACY_WORKER_ID, WorkerData.Profession.LABORER, CitizenData.EmploymentStatus.HIRED)
	var worker: WorkerData = WorkerData.new()
	worker.worker_id = LEGACY_WORKER_ID
	worker.profession = WorkerData.Profession.LABORER
	worker.payroll_start_day = -1
	worker.payroll_paid_from_day = -1
	worker.payroll_paid_until_day = -1
	worker.payroll_period_rate = 0
	WorkerDatabase.workers_by_id[LEGACY_WORKER_ID] = worker

func _seed_new_hire() -> void:
	_seed_citizen(DUE_WORKER_IDS[2], WorkerData.Profession.HAULER, CitizenData.EmploymentStatus.APPLICANT)
	var hired: WorkerData = WorkerDatabase.hire_applicant(DUE_WORKER_IDS[2])
	_expect(hired != null, "The new-hire fixture worker is hired through the Job Board flow.")

func _start_fixture_construction() -> void:
	_construction_state = CONSTRUCTION_SCRIPT.new()
	_construction_state.phase = "empty"
	add_child(_construction_state)
	var result: Dictionary = _construction_state.start_build([
		DUE_WORKER_IDS[1], CONTINUING_WORKER_ID
	] as Array[String])
	_expect(bool(result.get("success", false)),
		"Two currently paid fixture workers can start the 2160-minute construction job.")
	_expect(_construction_state.completes_at - _construction_state.started_at == 2160,
		"The two-worker construction fixture starts with its original 2160-minute duration.")

func _start_fixture_work_order() -> void:
	var job: JobData = JobData.new()
	job.job_id = FIXTURE_JOB_ID
	job.display_name = "Payroll renewal fixture"
	job.requirement_profession = WorkerData.Profession.LABORER
	job.base_duration_minutes = 10000
	job.inputs = {"clay_lump": 1}
	job.outputs = {"fixture_output": 1}
	var order_id: String = WorkManager.start_job(
		job,
		WorkOrder.Worker_Type.NPC,
		DUE_WORKER_IDS[0]
	)
	_expect(not order_id.is_empty(), "A renewal worker can start a job while the existing prepaid period is valid.")
	_expect(Inventory.items.get("clay_lump", 0) == 0,
		"The job consumes its input once when the order starts.")

func _start_fixture_drying() -> void:
	var drying: ProcessData = ProcessData.new()
	drying.process_id = FIXTURE_PROCESS_ID
	drying.display_name = "Fixture passive drying"
	drying.input_item_id = "wet_mudbrick"
	drying.output_item_id = "dry_mudbrick"
	drying.required_station_id = FIXTURE_STATION_ID
	drying.base_duration_minutes = 100000
	drying.batch_size = 1
	drying.requires_full_batch = false
	drying.weather_speed_multiplier = {"clear": 1.0, "cloudy": 1.0, "rainy": 1.0, "storm": 1.0}
	ProcessManager.set_source_item_store(Inventory)
	ProcessManager.set_output_item_store(Inventory)
	ProcessManager.set_weather_key("clear")
	_expect(ProcessManager.register_station(FIXTURE_STATION_ID, 1),
		"The passive drying fixture registers one station slot.")
	ProcessManager.register_process(drying)
	_expect(ProcessManager.start_registered_process(FIXTURE_PROCESS_ID, 1),
		"Passive drying starts using its own fixture input.")

func _test_atomic_renewal_failure_and_resume() -> void:
	var renewal_worker: WorkerData = WorkerDatabase.get_worker_data(DUE_WORKER_IDS[0])
	var construction_worker: WorkerData = WorkerDatabase.get_worker_data(DUE_WORKER_IDS[1])
	var continuing_worker: WorkerData = WorkerDatabase.get_worker_data(CONTINUING_WORKER_ID)
	var new_worker: WorkerData = WorkerDatabase.get_worker_data(DUE_WORKER_IDS[2])
	var waiting_worker: WorkerData = WorkerDatabase.get_worker_data(DUE_WORKER_IDS[3])
	var legacy_worker: WorkerData = WorkerDatabase.get_worker_data(LEGACY_WORKER_ID)
	var order_id: String = renewal_worker.current_order_id
	var order: WorkOrder = WorkManager.active_orders.get(order_id, null)
	var construction_start: int = _construction_state.started_at
	var construction_end: int = _construction_state.completes_at
	var drying_batch: ProcessBatch = ProcessManager.stations[FIXTURE_STATION_ID].slots[0]
	var cutoff_total: int = RENEWAL_DAY * 1440 + 8 * 60
	if order == null or drying_batch == null or _construction_state == null:
		_expect(false, "The work, drying, and construction fixtures must all start before time advances.")
		return

	# 07:59 is still covered by the old inclusive paid-through day.
	TimeComponentManager.advance_minutes(1439)
	_expect(TimeComponentManager.current_day == RENEWAL_DAY
		and TimeComponentManager.current_hour == 7
		and TimeComponentManager.current_minute == 59,
		"The simulated clock reaches 07:59 on the renewal day.")
	_expect(not renewal_worker.is_payroll_blocked()
		and renewal_worker.get_payroll_unpaid_minutes(cutoff_total, cutoff_total) == 0,
		"A renewal worker remains entitled to work until the exact next-day 08:00 boundary.")
	var due_quote: Dictionary = WorkerDatabase.get_payroll_quote(RENEWAL_DAY)
	_expect(int(due_quote.get("count", -1)) == 4
		and int(due_quote.get("total", -1)) == 9
		and int(due_quote.get("shortfall", -1)) == 1,
		"The morning quote combines two renewals, the new hire, and yesterday's unpaid worker at current rates.")
	_expect(not renewal_worker.is_payroll_due(RENEWAL_DAY - 1)
		and renewal_worker.is_payroll_due(RENEWAL_DAY),
		"The renewal becomes due on the first day after its paid-through date.")

	# This one-minute advance crosses the exact 08:00 payment boundary. The treasury is
	# one shekel short, so no due worker is charged and the existing cohort is paused together.
	TimeComponentManager.advance_minutes(1)
	_expect(TimeComponentManager.current_day == RENEWAL_DAY
		and TimeComponentManager.current_hour == 8
		and TimeComponentManager.current_minute == 0,
		"The renewal attempt runs at exactly 08:00.")
	_expect(CityStockManager.treasury_shekel == 8,
		"An insufficient atomic renewal group leaves city cash untouched.")
	_expect(renewal_worker.payroll_last_attempt_day == RENEWAL_DAY
		and construction_worker.payroll_last_attempt_day == RENEWAL_DAY
		and new_worker.payroll_last_attempt_day == RENEWAL_DAY
		and waiting_worker.payroll_last_attempt_day == RENEWAL_DAY,
		"The failed morning attempt records all four due workers together.")
	_expect(renewal_worker.is_payroll_blocked()
		and construction_worker.is_payroll_blocked()
		and new_worker.is_payroll_blocked()
		and waiting_worker.is_payroll_blocked()
		and not continuing_worker.is_payroll_blocked()
		and not legacy_worker.is_payroll_blocked(),
		"Only the due unpaid workers are blocked; a paid worker and legacy worker remain exempt.")
	_expect(renewal_worker.payroll_period_rate == 1
		and construction_worker.payroll_period_rate == 2
		and continuing_worker.payroll_period_rate == 2,
		"A changed current laborer rate does not rewrite locked rates during a paid period or failed renewal.")
	_expect(order != null and order.current_status == WorkOrder.Status.RUNNING,
		"The active NPC work order remains reserved after its worker becomes unpaid.")
	_expect(Inventory.items.get("clay_lump", 0) == 0,
		"Payroll pausing does not consume the NPC work input again.")
	_expect(drying_batch.progress_minutes == 1440,
		"Passive drying continues through the renewal boundary.")
	_expect(_construction_state.completes_at - _construction_state.started_at == construction_end - construction_start,
		"The construction deadline remains aligned to its original start deadline at the payment boundary.")
	var failed_quote: Dictionary = WorkerDatabase.get_payroll_quote(RENEWAL_DAY)
	_expect(int(failed_quote.get("count", -1)) == 4
		and CityStockManager.treasury_shekel == 8,
		"A duplicate quote after the failed attempt cannot charge or partially settle the group.")

	# A second signal and a state snapshot at the live 08:00 hour are deliberate duplicates.
	TimeComponentManager.hour_changed.emit(8)
	TimeComponentManager.emit_time_signal()
	_expect(CityStockManager.treasury_shekel == 8,
		"Duplicate payroll callbacks and a time snapshot do not charge a due group twice.")

	var original_order_start: int = order.start_time_total_minutes
	var original_order_end: int = order.end_time_total_minutes
	TimeComponentManager.advance_minutes(2)
	_expect(renewal_worker.get_payroll_unpaid_minutes(cutoff_total, cutoff_total + 2) == 2,
		"The unpaid-time helper counts only the two minutes after the expired period.")
	_expect(order.start_time_total_minutes == original_order_start + 2
		and order.end_time_total_minutes == original_order_end + 2
		and order.end_time_total_minutes - order.start_time_total_minutes == 10000,
		"WorkManager shifts both order timestamps across unpaid minutes and preserves duration.")
	_expect(TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute - order.start_time_total_minutes == 1440,
		"The active order's completed progress is unchanged while its worker is unpaid.")
	_expect(Inventory.items.get("clay_lump", 0) == 0,
		"Holding an order through unpaid time never consumes its input a second time.")
	_expect(drying_batch.progress_minutes == 1442,
		"The passive drying process advances during time when the NPC worker is blocked.")
	_expect(_construction_state.payroll_work_remainder == 0,
		"The team has no fractional construction minute before the first blocked minute.")
	var remaining_before_partial: int = int(_construction_state.get_preview([] as Array[String]).remaining_minutes)
	TimeComponentManager.advance_minutes(1)
	_expect(_construction_state.payroll_work_remainder == 1,
		"One paid builder out of two stores the half-minute remainder after one blocked minute.")
	TimeComponentManager.advance_minutes(1)
	_expect(_construction_state.payroll_work_remainder == 0
		and int(_construction_state.get_preview([] as Array[String]).remaining_minutes) == remaining_before_partial - 1,
		"Two blocked minutes with one paid builder complete exactly one construction minute.")
	_expect(not continuing_worker.is_payroll_blocked(),
		"The existing paid worker continues contributing to construction while its teammate is paused.")

	# Deposit midday to reach the exact total. The top-up is explicit and does not retry or resume work.
	var order_start_before_deposit: int = order.start_time_total_minutes
	var order_end_before_deposit: int = order.end_time_total_minutes
	_expect(CityStockManager.deposit_wallet_shekel(1),
		"A one-shekel fixture wallet deposit covers the remaining payroll shortfall.")
	_expect(CityStockManager.treasury_shekel == 9
		and renewal_worker.is_payroll_blocked()
		and order.start_time_total_minutes == order_start_before_deposit
		and order.end_time_total_minutes == order_end_before_deposit,
		"A midday deposit funds the treasury without immediately renewing or resuming the worker.")
	TimeComponentManager.hour_changed.emit(8)
	TimeComponentManager.emit_time_signal()
	_expect(CityStockManager.treasury_shekel == 9
		and renewal_worker.is_payroll_blocked(),
		"Midday duplicate callbacks do not retry or charge the waiting payroll group.")

	# Reach 07:59 on day 22. No missed wages accrue during the pause; a fresh seven-day
	# period begins only when the entire morning group is paid in full.
	TimeComponentManager.advance_minutes(1435)
	_expect(TimeComponentManager.current_day == RESUME_DAY
		and TimeComponentManager.current_hour == 7
		and TimeComponentManager.current_minute == 59,
		"The clock reaches the next morning without a midday retry.")
	_expect(renewal_worker.get_payroll_unpaid_minutes(cutoff_total,
		RESUME_DAY * 1440 + 8 * 60 - 1) == 1439,
		"The renewal pause is counted as unpaid time rather than accumulated wage arrears.")
	_expect(renewal_worker.is_payroll_blocked()
		and continuing_worker.is_payroll_blocked() == false,
		"Workers remain paused immediately before the next scheduled 08:00 attempt.")
	var resume_quote: Dictionary = WorkerDatabase.get_payroll_quote(RESUME_DAY)
	_expect(int(resume_quote.get("count", -1)) == 4
		and int(resume_quote.get("total", -1)) == 9
		and int(resume_quote.get("shortfall", -1)) == 0,
		"The next morning quote still covers the full original due group at current rates.")

	TimeComponentManager.advance_minutes(1)
	_expect(CityStockManager.treasury_shekel == 0,
		"The next 08:00 attempt pays the full due group once.")
	_expect(renewal_worker.payroll_paid_from_day == RESUME_DAY
		and renewal_worker.payroll_paid_until_day == RESUME_DAY + 6
		and construction_worker.payroll_paid_from_day == RESUME_DAY
		and construction_worker.payroll_paid_until_day == RESUME_DAY + 6
		and new_worker.payroll_paid_from_day == RESUME_DAY
		and waiting_worker.payroll_paid_from_day == RESUME_DAY,
		"All four workers receive fresh seven-day coverage beginning on the successful payment day.")
	_expect(renewal_worker.payroll_period_rate == 3
		and construction_worker.payroll_period_rate == 3
		and new_worker.payroll_period_rate == 2
		and waiting_worker.payroll_period_rate == 1,
		"The changed profession rates take effect only at the successful renewal/payment.")
	_expect(not renewal_worker.is_payroll_blocked()
		and renewal_worker.get_payroll_unpaid_minutes(cutoff_total,
			RESUME_DAY * 1440 + 8 * 60) == 1440
		and not renewal_worker.is_payroll_due(RESUME_DAY + 6)
		and renewal_worker.is_payroll_due(RESUME_DAY + 7),
		"Payment resumes work with seven new paid days and no wage arrears or shifted due date.")
	_expect(order.start_time_total_minutes == original_order_start + 1440
		and order.end_time_total_minutes == original_order_end + 1440
		and order.end_time_total_minutes - order.start_time_total_minutes == 10000,
		"The paused NPC order resumes with the same progress and duration after exactly one unpaid day.")
	_expect(order.current_status == WorkOrder.Status.RUNNING
		and renewal_worker.current_order_id == order_id
		and Inventory.items.get("clay_lump", 0) == 0,
		"Renewal resumes the same reserved order without duplicating its consumed input.")
	_expect(drying_batch.progress_minutes == 2880,
		"Passive drying keeps its full elapsed-time progress across the payroll pause.")
	_expect(int(WorkerDatabase.get_payroll_quote(RESUME_DAY).get("count", -1)) == 0,
		"A completed group is absent from that day's quote after payment.")
	TimeComponentManager.hour_changed.emit(8)
	TimeComponentManager.emit_time_signal()
	_expect(CityStockManager.treasury_shekel == 0,
		"Duplicate callbacks after successful settlement do not charge the treasury again.")

func _finish() -> void:
	var status: String = "PASS" if failures == 0 else "FAIL"
	print("WorkerPayrollRenewalFixtureTest: %s (%d checks failed)" % [status, failures])
	get_tree().quit(0 if failures == 0 else 1)
