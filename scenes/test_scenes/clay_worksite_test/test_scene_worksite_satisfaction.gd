extends Node

const DAILY = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_daily.gd")
const SESSION = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_session.gd")
const MANAGEMENT = preload("res://scenes/test_scenes/clay_worksite_test/clay_worker_management.gd")
const SITE: StringName = &"TestSite"
var failures: int = 0
var schedule
var session
var management
var dropped: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	TimeComponentManager.is_paused = true
	_test_tiers_and_full_shifts()
	_test_partial_and_changing_satisfaction()
	_test_multiple_and_depleted_stock()
	_test_fast_site_and_exact_boundaries()
	_test_arrival_and_payroll()
	_cleanup()
	if failures == 0:
		print("WorksiteSatisfactionTest PASSED")
	else:
		printerr("WorksiteSatisfactionTest FAILED: ", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _setup(satisfactions: Array, minutes_per_unit: float = 10.0, stock: int = 1000, start_minute: int = 420) -> void:
	_cleanup()
	WorkerDatabase.workers_by_id.clear()
	CitizenManager.citizens_by_id.clear()
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = start_minute / 60
	TimeComponentManager.current_minute = start_minute % 60
	session = SESSION.new()
	session.minutes_per_unit = minutes_per_unit
	session.stock = stock
	schedule = DAILY.new()
	schedule.setup({SITE: session})
	management = MANAGEMENT.new()
	management.schedule = schedule
	schedule.gathered.connect(management.record_contribution)
	dropped = 0
	for index in range(satisfactions.size()):
		var worker := WorkerData.new()
		worker.worker_id = "gather_%d" % index
		worker.satisfaction = float(satisfactions[index])
		WorkerDatabase.workers_by_id[worker.worker_id] = worker
		_expect(schedule.toggle(SITE, worker.worker_id), "Select worker %s" % worker.worker_id)
	_expect(schedule.start(SITE, _drop), "Start assignment")

func _advance(minutes: int) -> void:
	for unused: int in range(minutes):
		var total: int = schedule.now() + 1
		TimeComponentManager.current_day = total / 1440
		TimeComponentManager.current_hour = (total % 1440) / 60
		TimeComponentManager.current_minute = total % 60
		schedule.tick()

func _drop(quantity: int) -> bool:
	dropped += quantity
	return true

func _cleanup() -> void:
	if schedule != null:
		schedule.cleanup()
		schedule = null

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _test_tiers_and_full_shifts() -> void:
	# Per-item completion floors the end-of-shift fraction. Batch WorkManager
	# rounds its 48-unit result, hence low satisfaction gives 40 here vs 41 there.
	for case: Array in [[0.0, 40], [0.399999, 40], [0.4, 48], [0.749999, 48], [0.75, 50], [1.0, 50]]:
		_setup([case[0]])
		_advance(480)
		var expected: int = case[1]
		var worker: WorkerData = WorkerDatabase.get_worker_data("gather_0")
		_expect(schedule.jobs[SITE].stats.gather_0.output == expected, "Full shift output at satisfaction %s" % case[0])
		_expect(dropped == expected and session.stock == 1000 - expected and worker.profession_xp == expected,
			"Stock, ground output, and XP conserve completed items at %s" % case[0])
		var expected_partial: float = snappedf(480.0 * worker.get_satisfaction_work_multiplier() - expected * session.minutes_per_unit, schedule.PROGRESS_PRECISION)
		_expect(int(schedule.minutes_by_worker.gather_0) == 480 and is_equal_approx(float(schedule.jobs[SITE].progress.gather_0), expected_partial),
			"Full shift consumes 480 minutes and retains incomplete work")
		_advance(60)
		_expect(dropped == expected, "No extra gathering outside the shift")

func _test_partial_and_changing_satisfaction() -> void:
	_setup([0.2])
	_advance(10)
	_expect(dropped == 0 and is_equal_approx(schedule.jobs[SITE].progress.gather_0, 8.5), "Low satisfaction has partial work after 10 minutes")
	_advance(1)
	_expect(dropped == 0 and is_equal_approx(schedule.jobs[SITE].progress.gather_0, 9.35), "Incomplete item is not awarded at 11 minutes")
	_advance(1)
	_expect(dropped == 1 and is_equal_approx(schedule.jobs[SITE].progress.gather_0, 0.2), "First item and remainder are awarded at minute 12")
	_setup([0.9])
	var citizen := CitizenData.new()
	citizen.citizen_id = "gather_0"
	citizen.satisfaction = 0.2
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.HIRED
	citizen.profession = WorkerData.Profession.LABORER
	CitizenManager.citizens_by_id[citizen.citizen_id] = citizen
	_advance(5)
	citizen.satisfaction = 0.8
	_advance(5)
	_expect(dropped == 0 and is_equal_approx(schedule.jobs[SITE].progress.gather_0, 9.5), "Live linked-citizen Satisfaction changes only future progress")
	_advance(1)
	_expect(dropped == 1 and is_equal_approx(schedule.jobs[SITE].progress.gather_0, 0.55), "Updated linked-citizen Satisfaction produces the next item")
	_expect(schedule.withdraw(SITE, "gather_0") and dropped == 1, "Withdrawing discards only the incomplete remainder")

func _test_multiple_and_depleted_stock() -> void:
	_setup([0.2, 0.8])
	_advance(200)
	_expect(schedule.jobs[SITE].stats.gather_0.output == 17 and schedule.jobs[SITE].stats.gather_1.output == 21,
		"Workers accumulate separate Satisfaction-adjusted progress")
	_expect(dropped == 38 and session.stock == 962, "Two workers conserve shared stock and delivered items")
	_setup([0.8, 0.8], 10.0, 1)
	_advance(20)
	var output: int = int(schedule.jobs[SITE].stats.gather_0.output) + int(schedule.jobs[SITE].stats.gather_1.output)
	_expect(output == 1 and dropped == 1 and session.stock == 0, "Competing workers never exceed depleted stock")
	_expect(is_equal_approx(float(schedule.jobs[SITE].progress.gather_0), 0.5)
		and is_equal_approx(float(schedule.jobs[SITE].progress.gather_1), 9.45),
		"Depleted site retains each worker's unfinished item separately")

func _test_fast_site_and_exact_boundaries() -> void:
	_setup([0.8], 1.0)
	_advance(20)
	_expect(dropped == 21 and session.stock == 979, "Fast sites can complete two items in a minute without losing work")
	_expect(is_zero_approx(float(schedule.jobs[SITE].progress.gather_0)), "Fast-site exact boundary leaves no remainder")
	_setup([0.2], 7.5)
	_advance(150)
	_expect(dropped == 17 and is_zero_approx(float(schedule.jobs[SITE].progress.gather_0)), "Fractional item duration hits exact low-tier boundary")

func _test_arrival_and_payroll() -> void:
	_setup([0.8])
	schedule.physical_arrival = func(_site: StringName, _id: String, _day: int) -> int: return 430
	_advance(10)
	_expect(dropped == 0 and not schedule.minutes_by_worker.has("gather_0"), "Travel before arrival does not produce work")
	_advance(10)
	_expect(dropped == 1 and int(schedule.minutes_by_worker.gather_0) == 10, "Work begins at actual arrival")
	_setup([0.8])
	var worker: WorkerData = WorkerDatabase.get_worker_data("gather_0")
	worker.payroll_start_day = 0
	worker.payroll_paid_from_day = -1
	_advance(20)
	_expect(dropped == 0 and not schedule.minutes_by_worker.has("gather_0"), "Unpaid work remains blocked")
