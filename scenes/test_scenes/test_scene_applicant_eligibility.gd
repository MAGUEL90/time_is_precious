extends Node

## Isolates the existing applicant threshold and prepaid hiring APIs.
const FIXTURE_RATE: int = 2
const FIXTURE_WALLET: int = 10

var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_stale_single_hire_and_visibility()
	_test_stale_batch_is_atomic()
	_test_unemployed_recovery_and_paid_rehire()
	_test_legacy_hauler_is_not_recruited()
	_test_legacy_hauler_does_not_reapply()
	print("ApplicantEligibilityTest: %s (%d checks failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _reset_fixture() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 50
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 15
	WorkerDatabase._payroll_settling = false
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	WorkerDatabase.onboarding_period_rates = {WorkerData.Profession.LABORER: FIXTURE_RATE, WorkerData.Profession.HAULER: FIXTURE_RATE}
	CitizenManager.citizens_by_id.clear()
	Inventory.items.clear()
	Inventory.items["shekel"] = FIXTURE_WALLET

func _add_resident(id: String, satisfaction: float) -> CitizenData:
	var citizen := CitizenData.new()
	citizen.citizen_id = id
	citizen.display_name = id
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	citizen.profession = WorkerData.Profession.LABORER
	citizen.satisfaction = satisfaction
	CitizenManager.add_citizen(citizen)
	return citizen

func _add_applicant(id: String) -> CitizenData:
	var citizen: CitizenData = _add_resident(id, CitizenData.MIN_APPLICANT_SATISFACTION)
	_expect(CitizenManager.register_applicant(id, WorkerData.Profession.LABORER),
		"The eligible fixture resident registers as an applicant.")
	return citizen

func _test_stale_single_hire_and_visibility() -> void:
	_reset_fixture()
	var applicant: CitizenData = _add_applicant("single")
	_expect(applicant.can_be_hired() and CitizenManager.get_all_applicants().has(applicant),
		"An applicant at exactly 50% is eligible and appears on the board.")
	applicant.satisfaction = 0.499999
	_expect(not applicant.can_be_hired() and not CitizenManager.get_all_applicants().has(applicant),
		"A stale applicant below 50% is not eligible or shown.")
	_expect(WorkerDatabase.hire_applicant(applicant.citizen_id) == null,
		"Single hire rejects a stale applicant below 50%.")
	_expect(Inventory.items.get("shekel", 0) == FIXTURE_WALLET
		and WorkerDatabase.workers_by_id.is_empty()
		and applicant.employment_status == CitizenData.EmploymentStatus.APPLICANT,
		"Rejected single hire changes neither the wallet nor the roster or applicant state.")
	applicant.satisfaction = 0.500001
	_expect(applicant.can_be_hired() and CitizenManager.get_all_applicants().has(applicant),
		"The same applicant reappears when Satisfaction rises above 50%.")
	applicant.satisfaction = CitizenData.MIN_APPLICANT_SATISFACTION
	_expect(CitizenManager.get_all_applicants().has(applicant),
		"The exact 50% boundary remains visible after recovery.")
	applicant.profession = WorkerData.Profession.NONE
	_expect(not applicant.can_be_hired() and not CitizenManager.get_all_applicants().has(applicant),
		"The board also excludes an applicant without a hireable profession.")
	applicant.profession = WorkerData.Profession.LABORER
	applicant.population_status = CitizenData.PopulationStatus.LEFT_CITY
	_expect(not applicant.can_be_hired() and not CitizenManager.get_all_applicants().has(applicant),
		"The board excludes an applicant who is no longer a resident.")
	applicant.population_status = CitizenData.PopulationStatus.RESIDENT
	var hired: WorkerData = WorkerDatabase.hire_applicant(applicant.citizen_id)
	_expect(hired != null and applicant.employment_status == CitizenData.EmploymentStatus.HIRED
		and Inventory.items.get("shekel", 0) == FIXTURE_WALLET - FIXTURE_RATE,
		"Recovery to exactly 50% permits a normal paid single hire.")

func _test_stale_batch_is_atomic() -> void:
	_reset_fixture()
	var eligible: CitizenData = _add_applicant("eligible")
	var stale: CitizenData = _add_applicant("stale")
	stale.satisfaction = 0.499999
	for ids: PackedStringArray in [PackedStringArray(["eligible", "stale"]), PackedStringArray(["stale", "eligible"])]:
		_expect(WorkerDatabase.hire_applicants(ids).is_empty(),
			"A batch containing a below-threshold applicant is rejected in either order.")
		_expect(Inventory.items.get("shekel", 0) == FIXTURE_WALLET
			and WorkerDatabase.workers_by_id.is_empty()
			and eligible.employment_status == CitizenData.EmploymentStatus.APPLICANT
			and stale.employment_status == CitizenData.EmploymentStatus.APPLICANT,
			"Rejected batches debit nothing and leave both applicant records intact.")
	stale.satisfaction = 0.500001
	var hired: Array[WorkerData] = WorkerDatabase.hire_applicants(PackedStringArray(["eligible", "stale"]))
	_expect(hired.size() == 2 and Inventory.items.get("shekel", 0) == FIXTURE_WALLET - 2 * FIXTURE_RATE,
		"A batch at and above 50% hires both workers for the full quoted price.")

func _test_unemployed_recovery_and_paid_rehire() -> void:
	_reset_fixture()
	var resident: CitizenData = _add_resident("returning", 0.499999)
	var retained := WorkerData.new()
	retained.worker_id = resident.citizen_id
	retained.profession = WorkerData.Profession.LABORER
	retained.profession_xp = 17
	retained.payroll_start_day = 1
	retained.payroll_paid_from_day = 1
	retained.payroll_paid_until_day = 500
	retained.payroll_period_rate = 6
	retained.payroll_last_attempt_day = 1
	retained.payroll_contract_days = 9
	retained.payroll_paid_start_minute = 1 * 1440 + 600
	WorkerDatabase.dismissed_workers[resident.citizen_id] = retained
	_expect(CitizenManager.evaluate_daily_applications() == 0
		and resident.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and not CitizenManager.get_all_applicants().has(resident),
		"An unemployed resident below 50% does not reapply.")
	# Simulate the upstream recovery; this test does not change daily needs rules.
	resident.satisfaction = CitizenData.MIN_APPLICANT_SATISFACTION
	_expect(CitizenManager.evaluate_daily_applications() == 1
		and resident.employment_status == CitizenData.EmploymentStatus.APPLICANT
		and CitizenManager.get_all_applicants().has(resident),
		"At 50%, the normal daily evaluation registers the returning resident.")
	var rehired: WorkerData = WorkerDatabase.hire_applicant(resident.citizen_id)
	_expect(rehired == retained and rehired != null,
		"Paid rehire restores the archived worker.")
	if rehired != null:
		_expect(rehired.profession_xp == 17 and rehired.payroll_paid_from_day == 50
			and rehired.payroll_paid_until_day == 53 and rehired.payroll_contract_days == 3,
			"Rehire preserves earned XP and replaces the old prepaid period with a new contract.")
	_expect(Inventory.items.get("shekel", 0) == FIXTURE_WALLET - FIXTURE_RATE
		and not WorkerDatabase.dismissed_workers.has(resident.citizen_id),
		"Rehire charges the new contract once and removes the archive entry.")
	_expect(WorkerDatabase.hire_applicant(resident.citizen_id) == null
		and Inventory.items.get("shekel", 0) == FIXTURE_WALLET - FIXTURE_RATE,
		"A repeated hire neither succeeds nor charges again.")

func _test_legacy_hauler_is_not_recruited() -> void:
	_reset_fixture()
	var laborer: CitizenData = _add_applicant("valid_laborer")
	var legacy: CitizenData = _add_resident("legacy_hauler", 0.8)
	legacy.profession = WorkerData.Profession.HAULER
	legacy.employment_status = CitizenData.EmploymentStatus.APPLICANT
	_expect(legacy.can_be_hired() and WorkerDatabase.get_contract_price(legacy.profession, 3) == FIXTURE_RATE,
		"The old applicant is otherwise eligible and its legacy contract price remains available.")
	_expect(not CitizenManager.get_all_applicants().has(legacy) and CitizenManager.get_all_applicants().has(laborer),
		"An old Hauler applicant stays in the population but is absent from the board list.")
	_expect(WorkerDatabase.hire_applicant(legacy.citizen_id) == null,
		"A direct single hire rejects an otherwise eligible legacy Hauler.")
	for ids: PackedStringArray in [PackedStringArray([laborer.citizen_id, legacy.citizen_id]), PackedStringArray([legacy.citizen_id, laborer.citizen_id])]:
		_expect(WorkerDatabase.hire_applicants(ids).is_empty(), "Mixed batches reject a Hauler in either order.")
		_expect(Inventory.items.get("shekel", 0) == FIXTURE_WALLET and WorkerDatabase.workers_by_id.is_empty()
			and laborer.employment_status == CitizenData.EmploymentStatus.APPLICANT
			and legacy.employment_status == CitizenData.EmploymentStatus.APPLICANT,
			"Rejected single and batch hires preserve funds, workers and both citizen records.")
	var hired: Array[WorkerData] = WorkerDatabase.hire_applicants(PackedStringArray([laborer.citizen_id]))
	_expect(hired.size() == 1 and hired[0].profession == WorkerData.Profession.LABORER
		and Inventory.items.get("shekel", 0) == FIXTURE_WALLET - FIXTURE_RATE,
		"The normal Laborer hire still succeeds and charges exactly once.")

func _test_legacy_hauler_does_not_reapply() -> void:
	_reset_fixture()
	var citizen: CitizenData = _add_resident("former_hauler", CitizenData.MIN_APPLICANT_SATISFACTION)
	citizen.profession = WorkerData.Profession.HAULER
	var archived := WorkerData.new()
	archived.worker_id = citizen.citizen_id
	archived.profession = WorkerData.Profession.HAULER
	archived.profession_xp = 17
	WorkerDatabase.dismissed_workers[citizen.citizen_id] = archived
	_expect(not CitizenManager.register_applicant(citizen.citizen_id, WorkerData.Profession.HAULER),
		"An old Hauler cannot register a new application directly.")
	_expect(CitizenManager.evaluate_daily_applications() == 0 and CitizenManager.evaluate_daily_applications() == 0,
		"Repeated daily evaluations do not re-register an old Hauler at 50%.")
	_expect(citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and citizen.profession == WorkerData.Profession.HAULER and CitizenManager.get_citizen(citizen.citizen_id) == citizen
		and WorkerDatabase.dismissed_workers.get(citizen.citizen_id) == archived and archived.profession_xp == 17,
		"The former worker remains an unemployed citizen with the original profession and archived XP.")
