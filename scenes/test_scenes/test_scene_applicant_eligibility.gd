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
	_test_hauler_recruitment()
	_test_hauler_reapplies()
	_test_hauler_migration_preserves_workers()
	_test_empty_board_guidance()
	print("ApplicantEligibilityTest: %s (%d checks failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _test_empty_board_guidance() -> void:
	_reset_fixture()
	var board: JobBoardUI = preload("res://scenes/ui/job_board_ui/job_board_ui.tscn").instantiate()
	_expect(board._get_empty_state_message() == "No applicants available.", "An empty city does not invent a satisfaction problem.")
	var resident: CitizenData = _add_resident("waiting", 0.45)
	var hint: String = board._get_empty_state_message()
	_expect(hint.contains("Food") and hint.contains("Clothing") and hint.contains("Shelter") and hint.contains("50%"), "An unhappy recruitable resident gets the recovery guidance.")
	resident.profession = WorkerData.Profession.HAULER
	_expect(board._get_empty_state_message().contains("50%"), "An unhappy Hauler receives the same recovery guidance.")
	resident.profession = WorkerData.Profession.LABORER
	resident.employment_status = CitizenData.EmploymentStatus.HIRED
	_expect(board._get_empty_state_message() == "No applicants available.", "A low-satisfaction worker already hired does not trigger misleading applicant guidance.")
	board.free()

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

func _test_hauler_recruitment() -> void:
	_reset_fixture()
	var laborer: CitizenData = _add_applicant("valid_laborer")
	var hauler: CitizenData = _add_resident("legacy_hauler", 0.8)
	hauler.profession = WorkerData.Profession.HAULER
	hauler.employment_status = CitizenData.EmploymentStatus.APPLICANT
	_expect(CitizenManager.get_all_applicants().has(hauler) and CitizenManager.get_all_applicants().has(laborer),
		"Both Laborer and legacy Hauler applicants appear when eligible.")
	hauler.satisfaction = 0.49
	for ids: PackedStringArray in [PackedStringArray([laborer.citizen_id, hauler.citizen_id]), PackedStringArray([hauler.citizen_id, laborer.citizen_id])]:
		_expect(WorkerDatabase.hire_applicants(ids).is_empty(), "Mixed batches reject a stale Hauler in either order.")
		_expect(Inventory.items.get("shekel", 0) == FIXTURE_WALLET and WorkerDatabase.workers_by_id.is_empty(),
			"A rejected mixed batch changes neither wallet nor worker roster.")
	hauler.satisfaction = 0.8
	var hired: Array[WorkerData] = WorkerDatabase.hire_applicants(PackedStringArray([laborer.citizen_id, hauler.citizen_id]))
	_expect(hired.size() == 2 and hired[0].profession == WorkerData.Profession.LABORER and hired[1].profession == WorkerData.Profession.HAULER
		and Inventory.items.get("shekel", 0) == FIXTURE_WALLET - 2 * FIXTURE_RATE,
		"An eligible mixed hire charges both contracts exactly once.")
	_expect(WorkerDatabase.hire_applicant(hauler.citizen_id) == null and Inventory.items.get("shekel", 0) == FIXTURE_WALLET - 2 * FIXTURE_RATE,
		"Repeated hire does not debit again.")

func _test_hauler_reapplies() -> void:
	_reset_fixture()
	var citizen: CitizenData = _add_resident("former_hauler", CitizenData.MIN_APPLICANT_SATISFACTION)
	citizen.profession = WorkerData.Profession.HAULER
	var archived := WorkerData.new()
	archived.worker_id = citizen.citizen_id
	archived.profession = WorkerData.Profession.HAULER
	archived.profession_xp = 17
	WorkerDatabase.dismissed_workers[citizen.citizen_id] = archived
	_expect(CitizenManager.evaluate_daily_applications() == 1 and CitizenManager.evaluate_daily_applications() == 0
		and CitizenManager.get_all_applicants().has(citizen), "A recovered former Hauler reapplies once at the normal threshold.")
	var hired: WorkerData = WorkerDatabase.hire_applicant(citizen.citizen_id)
	_expect(hired == archived and hired.profession_xp == 17 and hired.profession == WorkerData.Profession.HAULER,
		"Paid Hauler rehire preserves archived profession and XP.")
	_expect(Inventory.items.get("shekel", 0) == FIXTURE_WALLET - FIXTURE_RATE and not WorkerDatabase.dismissed_workers.has(citizen.citizen_id),
		"Rehire debits the contract once and removes the archive entry.")

func _test_hauler_migration_preserves_workers() -> void:
	_reset_fixture()
	var starters = preload("res://scenes/content_scene/startup/initial_worksites.gd")
	var person: CitizenData = _add_resident(starters.HAULER_APPLICANT_ID, 0.8)
	var existing := WorkerData.new()
	existing.worker_id = person.citizen_id
	existing.profession = WorkerData.Profession.LABORER
	existing.profession_xp = 17
	person.employment_status = CitizenData.EmploymentStatus.HIRED
	WorkerDatabase.workers_by_id[person.citizen_id] = existing
	starters.ensure_city_hauler_applicant()
	var hauler: CitizenData = CitizenManager.get_citizen(starters.CITY_HAULER_APPLICANT_ID)
	_expect(person.profession == WorkerData.Profession.LABORER and existing.profession == WorkerData.Profession.LABORER and existing.profession_xp == 17,
		"An already-hired Laborer is never converted or stripped of progress.")
	_expect(hauler != null and hauler.profession == WorkerData.Profession.HAULER and CitizenManager.get_all_applicants().has(hauler),
		"A separate Hauler applicant is added when an old save has none.")
	var count: int = CitizenManager.citizens_by_id.size()
	starters.ensure_city_hauler_applicant()
	_expect(CitizenManager.citizens_by_id.size() == count, "Repeated migration does not duplicate the candidate.")
	if hauler != null:
		hauler.population_status = CitizenData.PopulationStatus.LEFT_CITY
		starters.ensure_city_hauler_applicant()
		_expect(CitizenManager.get_citizen(hauler.citizen_id) == hauler and hauler.population_status == CitizenData.PopulationStatus.LEFT_CITY,
			"A departed candidate is not silently recreated.")
	CitizenManager.citizens_by_id.erase(starters.CITY_HAULER_APPLICANT_ID)
	person.profession = WorkerData.Profession.HAULER
	existing.profession = WorkerData.Profession.HAULER
	starters.ensure_city_hauler_applicant()
	_expect(CitizenManager.get_citizen(starters.CITY_HAULER_APPLICANT_ID) == null and existing.profession_xp == 17,
		"A pre-existing legacy Hauler prevents a duplicate and keeps XP.")
