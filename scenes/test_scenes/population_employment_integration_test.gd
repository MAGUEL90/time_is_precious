extends Node

var test_failed: bool = false

func _ready() -> void:
	CitizenManager.citizens_by_id.clear()
	ImmigrationManager.pending_immigrants.clear()

	_test_generated_citizen_defaults()
	_test_resident_registration_guard()
	_test_immigration_acceptance()
	_test_immigration_rejection()

	CitizenManager.citizens_by_id.clear()
	ImmigrationManager.pending_immigrants.clear()

	if test_failed:
		push_error("PopulationEmploymentIntegrationTest FAILED")
		get_tree().quit(1)
		return

	print("PopulationEmploymentIntegrationTest PASSED")
	get_tree().quit(0)

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

func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	test_failed = true
	push_error(message)
