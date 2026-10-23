extends Node

const CONTENT_SCENE: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const HAULER_ID: String = "initial_worksite_hauler"
const LABORER_ID: String = "initial_workshop_laborer"
const FIRST_TIME_ID: String = "audit_first_time_applicant"
const EARNED_PROFESSION_XP: int = 7
const FIXTURE_RATES: Dictionary = {
	WorkerData.Profession.LABORER: 1,
	WorkerData.Profession.HAULER: 2,
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
	TimeComponentManager.current_day = 200
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	WorkerDatabase.onboarding_period_rates = FIXTURE_RATES.duplicate()
	Inventory.items.clear()
	Inventory.items["shekel"] = 100
	CityStockManager.treasury_shekel = 0
	var content: Node = CONTENT_SCENE.instantiate()
	add_child(content)
	await get_tree().process_frame
	content.get_node("TimeDebugOverlay").set_process(false)
	TimeComponentManager.set_process(false)
	TimeComponentManager.current_day = 200
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0

	var hauler_citizen: CitizenData = CitizenManager.get_citizen(HAULER_ID)
	var laborer_citizen: CitizenData = CitizenManager.get_citizen(LABORER_ID)
	_expect(hauler_citizen != null and hauler_citizen.profession == WorkerData.Profession.HAULER,
		"ContentScene registers its initial Hauler applicant with the Hauler profession.")
	_expect(laborer_citizen != null and laborer_citizen.profession == WorkerData.Profession.LABORER,
		"ContentScene retains its initial Laborer applicant.")
	if hauler_citizen == null or laborer_citizen == null:
		_finish()
		return

	hauler_citizen.satisfaction = 0.8
	var wallet_before_hauler: int = Inventory.items.get("shekel", 0)
	var hauler: WorkerData = WorkerDatabase.hire_applicant(HAULER_ID, 2)
	_expect(hauler != null and hauler.profession == WorkerData.Profession.HAULER,
		"The actual initial Hauler applicant is hired as a Hauler.")
	_expect(hauler != null and hauler.payroll_paid_from_day == TimeComponentManager.current_day
		and hauler.payroll_paid_until_day == TimeComponentManager.current_day + 3
		and hauler.payroll_period_rate == 2
		and Inventory.items.get("shekel", 0) == wallet_before_hauler - 2,
		"The fixture pays the Hauler's three-day contract up front from the personal wallet.")
	if hauler == null:
		_finish()
		return
	hauler.profession_xp = EARNED_PROFESSION_XP
	_expect(WorkerDatabase.dismiss_worker(HAULER_ID), "The hired Hauler can be dismissed before the daily application pass.")
	_expect(Inventory.items.get("shekel", 0) == wallet_before_hauler - 2,
		"Dismissing the prepaid Hauler gives no refund.")

	var wallet_before_laborer: int = Inventory.items.get("shekel", 0)
	var ineligible_worker: WorkerData = WorkerDatabase.hire_applicant(LABORER_ID, 1)
	_expect(ineligible_worker != null, "The initial Laborer can be hired for the ineligible reapplication case.")
	_expect(ineligible_worker != null and ineligible_worker.payroll_paid_from_day == TimeComponentManager.current_day
		and ineligible_worker.payroll_paid_until_day == TimeComponentManager.current_day + 3
		and ineligible_worker.payroll_period_rate == 1
		and Inventory.items.get("shekel", 0) == wallet_before_laborer - 1,
		"The fixture pays the Laborer's three-day contract up front from the personal wallet.")
	if ineligible_worker == null:
		_finish()
		return
	laborer_citizen.satisfaction = 0.1
	_expect(WorkerDatabase.dismiss_worker(LABORER_ID), "The low-satisfaction Laborer can be dismissed.")
	_expect(Inventory.items.get("shekel", 0) == wallet_before_laborer - 1,
		"Dismissing the prepaid Laborer gives no refund.")

	var first_time_citizen := CitizenData.new()
	first_time_citizen.citizen_id = FIRST_TIME_ID
	first_time_citizen.display_name = "First Time Applicant"
	first_time_citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	first_time_citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	first_time_citizen.profession = WorkerData.Profession.NONE
	first_time_citizen.satisfaction = 0.8
	CitizenManager.add_citizen(first_time_citizen)

	var previous_day: int = TimeComponentManager.current_day
	var minutes_to_midnight: int = 1440 - TimeComponentManager.current_hour * 60 - TimeComponentManager.current_minute
	TimeComponentManager.advance_minutes(minutes_to_midnight)
	_expect(TimeComponentManager.current_day == previous_day + 1 and TimeComponentManager.current_hour == 0,
		"The actual game clock crosses midnight and starts the daily needs/application pass.")
	_expect(is_equal_approx(hauler_citizen.satisfaction, 0.75),
		"The seeded Hauler remains eligible after the unchanged daily needs adjustment to 0.75 satisfaction.")
	_expect(hauler_citizen.employment_status == CitizenData.EmploymentStatus.APPLICANT
		and hauler_citizen.profession == WorkerData.Profession.HAULER,
		"Midnight reapplication preserves the dismissed citizen's Hauler profession.")
	_expect(first_time_citizen.employment_status == CitizenData.EmploymentStatus.APPLICANT
		and first_time_citizen.profession == WorkerData.Profession.LABORER,
		"A first-time eligible citizen with no profession receives the existing Laborer default.")
	_expect(laborer_citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and not _is_applicant(LABORER_ID),
		"An ineligible dismissed citizen is not reapplied for work.")

	var applicant_count: int = CitizenManager.get_all_applicants().size()
	var duplicate_registration_count: int = CitizenManager.evaluate_daily_applications()
	_expect(duplicate_registration_count == 0
		and CitizenManager.get_all_applicants().size() == applicant_count
		and _is_applicant(HAULER_ID)
		and _is_applicant(FIRST_TIME_ID),
		"A repeated daily evaluation does not create duplicate applicants or change their existing roles.")

	# Rehiring is a new purchase, and the Job Board is open again at 10:00.
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	var wallet_before_rehire: int = Inventory.items.get("shekel", 0)
	var rehired: WorkerData = WorkerDatabase.hire_applicant(HAULER_ID, 3)
	_expect(rehired == hauler and rehired.worker_id == HAULER_ID,
		"Rehiring restores the same WorkerData object and worker ID.")
	_expect(rehired != null and rehired.profession == WorkerData.Profession.HAULER
		and rehired.profession_xp == EARNED_PROFESSION_XP,
		"Rehiring preserves the Hauler role and previously earned profession XP.")
	_expect(rehired != null and rehired.payroll_start_day == TimeComponentManager.current_day
		and rehired.payroll_paid_from_day == TimeComponentManager.current_day
		and rehired.payroll_paid_until_day == TimeComponentManager.current_day + 3
		and rehired.payroll_period_rate == 2
		and Inventory.items.get("shekel", 0) == wallet_before_rehire - 2,
		"Rehiring starts a fresh prepaid contract and charges the current three-day package again.")
	_expect(hauler_citizen.employment_status == CitizenData.EmploymentStatus.HIRED,
		"Successful rehire updates the linked citizen's employment status.")
	_finish()

func _is_applicant(citizen_id: String) -> bool:
	for applicant: CitizenData in CitizenManager.get_all_applicants():
		if applicant.citizen_id == citizen_id:
			return true
	return false

func _finish() -> void:
	print("WorkerRehireRegressionTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
