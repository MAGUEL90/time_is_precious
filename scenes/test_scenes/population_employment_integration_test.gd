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
