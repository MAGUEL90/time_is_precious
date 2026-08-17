extends Node

var test_failed: bool = false

# Test runner

func _ready() -> void:
	CitizenManager.citizens_by_id.clear()
	ImmigrationManager.pending_immigrants.clear()

	_test_generated_citizen_defaults()
	_test_resident_registration_guard()
	_test_immigration_acceptance()
	_test_immigration_rejection()
	_test_applicant_hiring_lifecycle()
	_test_worker_assignment_lifecycle()
	_test_job_role_requirements()
	_test_worker_data_linking_and_needs_integration()

	CitizenManager.citizens_by_id.clear()
	ImmigrationManager.pending_immigrants.clear()

	if test_failed:
		push_error("PopulationEmploymentIntegrationTest FAILED")
		get_tree().quit(1)
		return

	print("PopulationEmploymentIntegrationTest PASSED")
	get_tree().quit(0)

# Population and immigration lifecycle

func _test_generated_citizen_defaults() -> void:
	var generated_citizen: CitizenData = CitizenGenerator.generate_citizen()

	_expect(
		generated_citizen.population_status == CitizenData.PopulationStatus.MIGRANT,
		"Generated citizens must start as migrants.")
	_expect(
		generated_citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED,
		"Generated citizens must start unemployed.")

func _test_resident_registration_guard() -> void:
	var migrant: CitizenData = CitizenGenerator.generate_citizen()
	CitizenManager.add_citizen(migrant)

	_expect(
		not CitizenManager.has_citizen(migrant.citizen_id),
		"Migrants must not enter the resident registry.")
	_expect(
		CitizenManager.get_all_residents().is_empty(),
		"The resident registry must remain empty after rejecting a migrant.")

func _test_immigration_acceptance() -> void:
	ImmigrationManager.spawn_immigration(1)
	_expect(
		ImmigrationManager.pending_immigrants.size() == 1,
		"Immigration must create one pending migrant.")
	_expect(
		CitizenNeedsManager.get_citizen_count() == 0,
		"Pending migrants must not count toward resident needs.")
	if ImmigrationManager.pending_immigrants.is_empty():
		return

	var immigrant: CitizenData = ImmigrationManager.pending_immigrants[0]
	var accepted: bool = ImmigrationManager.accept_pending_immigrants()

	_expect(accepted, "Accepting a pending migrant must succeed.")
	_expect(
		immigrant.population_status == CitizenData.PopulationStatus.RESIDENT,
		"Accepted migrants must become residents.")
	_expect(
		immigrant.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED,
		"Accepted residents must start unemployed.")
	_expect(
		CitizenManager.has_citizen(immigrant.citizen_id),
		"Accepted residents must enter CitizenManager.")
	_expect(
		CitizenNeedsManager.get_citizen_count() == 1,
		"Accepted residents must count toward resident needs.")

	immigrant.employment_status = CitizenData.EmploymentStatus.APPLICANT
	_expect(
		CitizenManager.get_all_applicants().has(immigrant),
		"Resident applicants must appear in the applicant query.")

func _test_immigration_rejection() -> void:
	ImmigrationManager.spawn_immigration(1)
	_expect(
		ImmigrationManager.pending_immigrants.size() == 1,
		"Immigration must create a pending migrant for rejection.")
	_expect(
		CitizenNeedsManager.get_citizen_count() == 1,
		"Pending migrants must not inflate the existing resident count.")
	if ImmigrationManager.pending_immigrants.is_empty():
		return

	var immigrant: CitizenData = ImmigrationManager.pending_immigrants[0]
	var rejected: bool = ImmigrationManager.reject_pending_immigrants()

	_expect(rejected, "Rejecting a pending migrant must succeed.")
	_expect(
		immigrant.population_status == CitizenData.PopulationStatus.REJECTED,
		"Rejected migrants must retain a rejected population state.")
	_expect(
		immigrant.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED,
		"Rejected migrants must remain unemployed.")
	_expect(
		not CitizenManager.has_citizen(immigrant.citizen_id),
		"Rejected migrants must not enter CitizenManager.")

# Applicant hiring lifecycle

func _test_applicant_hiring_lifecycle() -> void:
	CitizenManager.citizens_by_id.clear()

	var applicant: CitizenData = CitizenData.new()
	applicant.citizen_id = "hiring_test"
	applicant.display_name = "Hiring Test"
	applicant.population_status = CitizenData.PopulationStatus.RESIDENT
	applicant.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	applicant.satisfaction = 0.49
	CitizenManager.add_citizen(applicant)
	var rejected_application: bool = CitizenManager.register_applicant(
		applicant.citizen_id,
		WorkerData.Profession.LABORER
	)

	_expect(
		not rejected_application,
		"Resident below the satisfaction threshold must remain unemployed."
	)
	_expect(
		applicant.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED,
		"Rejected application must not change employment status."
	)

	applicant.satisfaction = CitizenData.MIN_APPLICANT_SATISFACTION
	var registered_count: int = CitizenManager.evaluate_daily_applications()
	_expect(
		registered_count == 1,
		"Daily evaluation must register one eligible resident."
	)

	var job_board_scene: PackedScene = load(
		"res://scenes/job_board/job_board.tscn"
	)
	var job_board: JobBoard = job_board_scene.instantiate()
	add_child(job_board)
	job_board.default_daily_wage = 2

	job_board.on_player_interact(null)

	var job_board_ui: JobBoardUI = job_board.job_board_ui
	var hired_worker: WorkerData = null

	_expect(
		job_board_ui != null,
		"Job Board interaction must open JobBoardUI."
	)

	if job_board_ui != null:
		_expect(job_board_ui.visible, "JobBoardUI must be visible.")
		_expect(
			get_tree().paused,
			"Opening JobBoardUI must pause the world."
		)
		_expect(
			job_board_ui.applicants.has(applicant),
			"JobBoardUI must contain the eligible applicant."
		)
		_expect(
			job_board_ui.applicant_list.item_count == 1,
			"JobBoardUI must display one applicant."
		)
		_expect(
			job_board_ui.applicant_list.get_item_text(0).contains(
				applicant.display_name
			),
			"Applicant row must show the citizen name."
		)

		job_board_ui.hire_button.pressed.emit()
		hired_worker = WorkerDatabase.get_worker_data(
			applicant.citizen_id
		)

	_expect(hired_worker != null, "Eligible applicant must be hired.")

	_expect(
		applicant.employment_status == CitizenData.EmploymentStatus.HIRED,
		"Hired applicant must enter the HIRED employment state."
	)
	_expect(
		WorkerDatabase.get_worker_data(applicant.citizen_id) == hired_worker,
		"Hired applicant must receive linked WorkerData."
	)

	if hired_worker != null:
		_expect(
			hired_worker.has_linked_citizen(),
			"Hired WorkerData must link back to CitizenData."
		)
		_expect(
			hired_worker.profession == WorkerData.Profession.LABORER,
			"Hired worker must inherit the applicant profession."
		)
		_expect(
			hired_worker.wage_shekel_per_day == 2,
			"Hired worker must receive the agreed wage."
		)

	if job_board_ui != null:
		_expect(
			not job_board_ui.applicants.has(applicant),
			"Hired citizen must disappear from JobBoardUI."
		)
		_expect(
			job_board_ui.applicant_list.item_count == 0,
			"Applicant list must refresh after hiring."
		)
		_expect(
			job_board_ui.hire_button.disabled,
			"Hire button must be disabled when no applicants remain."
		)
		_expect(
			job_board_ui.feedback_label.text.contains("Hired"),
			"JobBoardUI must show successful hiring feedback."
		)

		job_board_ui.close()

	_expect(
		not get_tree().paused,
		"Closing JobBoardUI must resume the world."
	)
	_expect(
		job_board.job_board_ui == null,
		"Closed JobBoardUI must be released by JobBoard."
	)

	job_board.free()

	var duplicate_hire: WorkerData = WorkerDatabase.hire_applicant(
		applicant.citizen_id,
		2
	)
	_expect(duplicate_hire == null, "A hired citizen cannot be hired twice.")

	WorkerDatabase.workers_by_id.erase(applicant.citizen_id)
	CitizenManager.citizens_by_id.erase(applicant.citizen_id)

func _test_worker_assignment_lifecycle() -> void:
	var first_citizen: CitizenData = CitizenData.new()
	first_citizen.citizen_id = "assignment_test_first"
	first_citizen.display_name = "First Assignment Worker"
	first_citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	first_citizen.employment_status = CitizenData.EmploymentStatus.HIRED
	first_citizen.profession = WorkerData.Profession.LABORER
	CitizenManager.add_citizen(first_citizen)

	var first_worker: WorkerData = WorkerData.new()
	first_worker.worker_id = first_citizen.citizen_id
	first_worker.profession = first_citizen.profession
	WorkerDatabase.workers_by_id[first_worker.worker_id] = first_worker

	var second_citizen: CitizenData = CitizenData.new()
	second_citizen.citizen_id = "assignment_test_second"
	second_citizen.display_name = "Second Assignment Worker"
	second_citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	second_citizen.employment_status = CitizenData.EmploymentStatus.HIRED
	second_citizen.profession = WorkerData.Profession.LABORER
	CitizenManager.add_citizen(second_citizen)

	var second_worker: WorkerData = WorkerData.new()
	second_worker.worker_id = second_citizen.citizen_id
	second_worker.profession = second_citizen.profession
	WorkerDatabase.workers_by_id[second_worker.worker_id] = second_worker

	var workshop: WorkShop = WorkShop.new()
	workshop.max_assigned_worker_slots = 1

	var first_assignment: Array[String] = [first_worker.worker_id]
	_expect(
		workshop.assign_workers(first_assignment),
		"A hired worker must be assignable to a workshop."
	)
	_expect(
		first_citizen.employment_status == CitizenData.EmploymentStatus.ASSIGNED,
		"Assigned worker must enter the ASSIGNED employment state."
	)
	_expect(
		workshop.get_assigned_worker_ids() == first_assignment,
		"Workshop must retain the confirmed worker assignment."
	)

	var second_assignment: Array[String] = [second_worker.worker_id]
	_expect(
		workshop.assign_workers(second_assignment),
		"A second hired worker must replace the previous assignment."
	)
	_expect(
		first_citizen.employment_status == CitizenData.EmploymentStatus.HIRED,
		"Removed worker must return to the HIRED employment state."
	)
	_expect(
		second_citizen.employment_status == CitizenData.EmploymentStatus.ASSIGNED,
		"Replacement worker must enter the ASSIGNED employment state."
	)
	_expect(
		workshop.get_assigned_worker_ids() == second_assignment,
		"Workshop must retain only the replacement worker."
	)

	var empty_assignment: Array[String] = []
	_expect(
		workshop.assign_workers(empty_assignment),
		"Clearing all worker assignments must succeed."
	)
	_expect(
		workshop.get_assigned_worker_ids().is_empty(),
		"Workshop must have no assigned workers after clearing."
	)
	_expect(
		second_citizen.employment_status == CitizenData.EmploymentStatus.HIRED,
		"Cleared worker must return to the HIRED employment state."
	)

	workshop.free()
	WorkerDatabase.workers_by_id.erase(first_worker.worker_id)
	WorkerDatabase.workers_by_id.erase(second_worker.worker_id)
	CitizenManager.citizens_by_id.erase(first_citizen.citizen_id)
	CitizenManager.citizens_by_id.erase(second_citizen.citizen_id)

# Job role requirements

func _test_job_role_requirements() -> void:
	var laborer: WorkerData = WorkerData.new()
	laborer.worker_id = "role_test_laborer"
	laborer.profession = WorkerData.Profession.LABORER
	WorkerDatabase.workers_by_id[laborer.worker_id] = laborer

	var crafter: WorkerData = WorkerData.new()
	crafter.worker_id = "role_test_crafter"
	crafter.profession = WorkerData.Profession.CRAFTER
	WorkerDatabase.workers_by_id[crafter.worker_id] = crafter

	var job: JobData = preload(
		"res://resources/job_data/mudbrick_make.tres"
	) as JobData

	_expect(
		job.requirement_profession == WorkerData.Profession.LABORER,
		"Mudbrick Making must require a Laborer."
	)

	var workshop: WorkShop = WorkShop.new()
	workshop.max_assigned_worker_slots = 2

	var mixed_assignment: Array[String] = [
		crafter.worker_id,
		laborer.worker_id
	]

	_expect(
		workshop.assign_workers(mixed_assignment),
		"Workers must be assignable before checking job roles."
	)
	_expect(
		workshop.get_first_available_assigned_worker_id(job) == laborer.worker_id,
		"The workshop must select the worker whose profession matches the job."
	)

	var crafter_only: Array[String] = [crafter.worker_id]
	workshop.assign_workers(crafter_only)

	_expect(
		workshop.get_first_available_assigned_worker_id(job).is_empty(),
		"A job must not select a worker with the wrong profession."
	)

	var rejected_order_id: String = WorkManager.start_job(
		job,
		WorkOrder.Worker_Type.NPC,
		crafter.worker_id,
		null,
		Inventory,
		Inventory,
		0
	)
	_expect(
		rejected_order_id.is_empty(),
		"WorkManager must reject a worker with the wrong profession."
	)
	_expect(
		WorkManager.get_last_start_job_error().to_lower().contains("profession"),
		"WorkManager must report the profession mismatch."
	)

	workshop.free()
	WorkerDatabase.workers_by_id.erase(laborer.worker_id)
	WorkerDatabase.workers_by_id.erase(crafter.worker_id)

# Worker linking and legacy compatibility

func _test_worker_data_linking_and_needs_integration() -> void:
	var original_workers: Array = WorkerDatabase.get_all_workers()
	var original_food_supply: int = CityStockManager.food_supply
	var original_clothing_supply: int = CityStockManager.clothing_supply
	var original_shelter_capacity: int = CityStockManager.shelter_capacity

	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()

	var resident: CitizenData = CitizenData.new()
	resident.citizen_id = "linked_worker_test"
	resident.display_name = "Linked Worker"
	resident.satisfaction = 0.80
	resident.reliability = 0.90
	resident.population_status = CitizenData.PopulationStatus.RESIDENT
	resident.employment_status = CitizenData.EmploymentStatus.HIRED
	CitizenManager.add_citizen(resident)

	var linked_worker: WorkerData = WorkerData.new()
	linked_worker.worker_id = resident.citizen_id
	linked_worker.display_name = "Legacy Worker"
	linked_worker.satisfaction = 0.10
	linked_worker.reliability = 0.20
	WorkerDatabase.workers_by_id[linked_worker.worker_id] = linked_worker

	_expect(
		linked_worker.get_resolved_display_name() == "Linked Worker",
		"Linked workers must resolve their display name from CitizenData."
	)
	_expect(
		is_equal_approx(linked_worker.get_resolved_satisfaction(), 0.80),
		"Linked workers must resolve satisfaction from CitizenData."
	)
	_expect(
		is_equal_approx(linked_worker.get_resolved_reliability(), 0.90),
		"Linked workers must resolve reliability from CitizenData."
	)
	_expect(
		is_equal_approx(linked_worker.get_satisfaction_work_multiplier(), 1.05),
		"Linked worker satisfaction must affect the work multiplier."
	)
	_expect(
		is_equal_approx(linked_worker.get_reliability_success_chance(), 0.95),
		"Linked worker reliability must affect success chance."
	)

	var legacy_worker: WorkerData = WorkerData.new()
	legacy_worker.worker_id = "legacy_worker_test"
	legacy_worker.display_name = "Legacy Worker"
	legacy_worker.satisfaction = 0.30
	legacy_worker.reliability = 0.60
	legacy_worker.food_fulfilled = true
	legacy_worker.clothing_fulfilled = true
	legacy_worker.shelter_fulfilled = true

	_expect(
		not legacy_worker.has_linked_citizen(),
		"Legacy workers must remain unlinked when no matching CitizenData exists."
	)
	_expect(
		legacy_worker.get_resolved_display_name() == "Legacy Worker",
		"Unlinked workers must retain their WorkerData display name."
	)
	_expect(
		is_equal_approx(legacy_worker.get_resolved_satisfaction(), 0.30),
		"Unlinked workers must retain their WorkerData satisfaction."
	)
	_expect(
		is_equal_approx(legacy_worker.get_resolved_reliability(), 0.60),
		"Unlinked workers must retain their WorkerData reliability."
	)
	_expect(
		legacy_worker.are_basic_needs_fulfilled(),
		"Unlinked workers must retain their WorkerData needs state."
	)
	_expect(
		is_equal_approx(legacy_worker.get_satisfaction_work_multiplier(), 0.85),
		"Unlinked worker satisfaction must retain its work multiplier."
	)
	_expect(
		is_equal_approx(legacy_worker.get_reliability_success_chance(), 0.85),
		"Unlinked worker reliability must retain its success chance."
	)

	CityStockManager.food_supply = 2
	CityStockManager.clothing_supply = 2
	CityStockManager.shelter_capacity = 1

	CitizenNeedsManager.process_daily_needs()

	_expect(
		is_equal_approx(linked_worker.satisfaction, 0.10),
		"Linked workers must not update legacy WorkerData satisfaction during daily needs."
	)
	_expect(
		is_equal_approx(linked_worker.reliability, 0.20),
		"Linked workers must not update legacy WorkerData reliability during daily needs."
	)
	_expect(
		linked_worker.has_linked_citizen(),
		"Worker must resolve its matching CitizenData."
	)
	_expect(
		CityStockManager.food_supply == 1,
		"Linked workers must not consume food twice."
	)
	_expect(
		CityStockManager.clothing_supply == 1,
		"Linked workers must not consume clothing twice."
	)

	WorkerDatabase.workers_by_id.clear()
	for original_worker in original_workers:
		if original_worker is WorkerData:
			var worker_data: WorkerData = original_worker as WorkerData
			WorkerDatabase.workers_by_id[worker_data.worker_id] = worker_data

	CityStockManager.food_supply = original_food_supply
	CityStockManager.clothing_supply = original_clothing_supply
	CityStockManager.shelter_capacity = original_shelter_capacity

# Assertion helper

func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	test_failed = true
	push_error(message)
