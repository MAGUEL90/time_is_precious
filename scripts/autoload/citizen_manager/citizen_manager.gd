extends Node
signal citizen_added(citizen_data: CitizenData)

@export var seed_debug_citizens: bool = false
@export var seed_generated_citizen: bool = false

var citizens_by_id: Dictionary[String, CitizenData] = {}

func _ready() -> void:
	if seed_debug_citizens:
		add_citizen(_create_test_citizen(
			"01", "Gabbi", "black_female_01", "warm", "default"))
		add_citizen(_create_test_citizen(
			"02", "Gal-Sal", "brown_male_02", "tan", "default"))
		add_citizen(_create_test_citizen(
			"03", "Sukkalgir", "red_male_01", "dark", "default"))
	if seed_generated_citizen:
		var generated_citizen: CitizenData = CitizenGenerator.generate_citizen()
		generated_citizen.population_status = CitizenData.PopulationStatus.RESIDENT
		generated_citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
		generated_citizen.status = CitizenData.CitizenStatus.CITIZEN
		add_citizen(generated_citizen)

func _create_test_citizen(
	id: String,
	display_name: String,
	hair_style: String,
	skin_tone: String,
	accessory: String) -> CitizenData:
	
	var test_citizen: CitizenData = CitizenData.new()
	test_citizen.citizen_id = id
	test_citizen.display_name = display_name
	test_citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	test_citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	test_citizen.status = CitizenData.CitizenStatus.CITIZEN
	var visual_profile: VisualProfile = VisualProfile.new()
	visual_profile.hair_style = hair_style
	visual_profile.skin_tone = skin_tone
	visual_profile.accessory = accessory
	test_citizen.visual_profile = visual_profile
	return test_citizen

func add_citizen(citizen_data: CitizenData) -> void:
	if citizen_data == null:
		return 

	if citizen_data.population_status != CitizenData.PopulationStatus.RESIDENT:
		return

	var citizen_id: String = citizen_data.citizen_id
	var clean_citizen_id: String = citizen_id.strip_edges()
	
	citizen_data.citizen_id = clean_citizen_id
	
	if clean_citizen_id.is_empty():
		return
	
	if citizens_by_id.has(clean_citizen_id):
		return
	
	citizens_by_id[clean_citizen_id] = citizen_data
	citizen_added.emit(citizen_data)

func get_citizen(citizen_id: String) -> CitizenData:
	var clean_citizen_id: String = citizen_id.strip_edges()
	
	if clean_citizen_id.is_empty():
		return null
	
	if not citizens_by_id.has(clean_citizen_id):
		return null

	return citizens_by_id[clean_citizen_id]

func get_all_citizens() -> Array:
	return citizens_by_id.values()

func get_all_residents() -> Array[CitizenData]:
	var residents: Array[CitizenData] = []

	for citizen in citizens_by_id.values():
		if citizen.population_status == CitizenData.PopulationStatus.RESIDENT:
			residents.append(citizen)

	return residents

func get_all_applicants() -> Array[CitizenData]:
	var applicants: Array[CitizenData] = []

	for citizen in citizens_by_id.values():
		if citizen.population_status != CitizenData.PopulationStatus.RESIDENT:
			continue
		if citizen.employment_status != CitizenData.EmploymentStatus.APPLICANT:
			continue

		applicants.append(citizen)

	return applicants

func has_citizen(citizen_id: String) -> bool:
	var clean_citizen_id: String = citizen_id.strip_edges()
	
	if clean_citizen_id.is_empty():
		return false
		
	return citizens_by_id.has(clean_citizen_id)
