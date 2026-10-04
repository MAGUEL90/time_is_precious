extends Node

const CONTENT_SCENE: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const HAULER_ID: String = "initial_worksite_hauler"
const LABORER_ID: String = "initial_workshop_laborer"
const FIRST_TIME_ID: String = "audit_first_time_applicant"
const EARNED_PROFESSION_XP: int = 7

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
	var content: Node = CONTENT_SCENE.instantiate()
	add_child(content)
	await get_tree().process_frame
	content.get_node("TimeDebugOverlay").set_process(false)

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
	var hauler: WorkerData = WorkerDatabase.hire_applicant(HAULER_ID, 2)
	_expect(hauler != null and hauler.profession == WorkerData.Profession.HAULER,
		"The actual initial Hauler applicant is hired as a Hauler.")
	if hauler == null:
		_finish()
		return
	hauler.profession_xp = EARNED_PROFESSION_XP
	_expect(WorkerDatabase.dismiss_worker(HAULER_ID), "The hired Hauler can be dismissed before the daily application pass.")

	var ineligible_worker: WorkerData = WorkerDatabase.hire_applicant(LABORER_ID, 1)
	_expect(ineligible_worker != null, "The initial Laborer can be hired for the ineligible reapplication case.")
	if ineligible_worker == null:
		_finish()
		return
	laborer_citizen.satisfaction = 0.1
	_expect(WorkerDatabase.dismiss_worker(LABORER_ID), "The low-satisfaction Laborer can be dismissed.")

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

	var rehired: WorkerData = WorkerDatabase.hire_applicant(HAULER_ID, 3)
	_expect(rehired == hauler and rehired.worker_id == HAULER_ID,
		"Rehiring restores the same WorkerData object and worker ID.")
	_expect(rehired != null and rehired.profession == WorkerData.Profession.HAULER
		and rehired.profession_xp == EARNED_PROFESSION_XP,
		"Rehiring preserves the Hauler role and previously earned profession XP.")
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
