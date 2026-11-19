extends Node

# Generation Data

var display_name_container: Array[String] = [
	"Enkiya", "Lugal", "Naram", "Urani", "Dagan",
	"Ashur", "Nabu", "Tammuz", "Sinbel", "Iddin"
]

var skin_tone_container: Array[String] = [
	"dark", "light", "tan", "warm"
]

var hair_container: Array[String] = [
	"default",
	"grey_female_01", "grey_female_02", "grey_female_03",
	"grey_male_01", "grey_male_02", "grey_male_03",
	"red_female_01", "red_female_02", "red_female_03",
	"red_male_01", "red_male_02", "red_male_03",
	"black_female_01", "black_female_02", "black_female_03",
	"black_male_01", "black_male_02", "black_male_03",
	"brown_female_01", "brown_female_02", "brown_female_03",
	"brown_male_01", "brown_male_02", "brown_male_03"
]

var clothes_container: Array[String] = [
	"default", "clay_worn_wrap", "plain_worn_wrap"
]

var accessory_container: Array[String] = [
	"default", "farmer_hat"
]

var counter_id: int = 0

# Generation API

func generate_citizen() -> CitizenData:
	var available: Array[Vector2i] = []
	var used: Dictionary = {}
	# Include saved former residents and pending arrivals, not just visible actors.
	for citizen: CitizenData in CitizenManager.citizens_by_id.values():
		if citizen.visual_profile != null:
			used[_appearance_key(citizen.visual_profile)] = true
	for citizen: CitizenData in ImmigrationManager.pending_immigrants:
		if citizen.visual_profile != null:
			used[_appearance_key(citizen.visual_profile)] = true
	for skin_index: int in range(skin_tone_container.size()):
		for hair_index: int in range(hair_container.size()):
			var key: String = skin_tone_container[skin_index] + "|" + hair_container[hair_index]
			if not used.has(key):
				available.append(Vector2i(skin_index, hair_index))
	# Finite art cannot provide unlimited distinct identities. Never silently clone.
	if available.is_empty():
		return null
	var choice: Vector2i = available.pick_random()
	counter_id += 1
	var citizen_data: CitizenData = CitizenData.new()
	citizen_data.citizen_id = "citizen_%03d" % counter_id
	citizen_data.display_name = display_name_container.pick_random()
	citizen_data.population_status = CitizenData.PopulationStatus.MIGRANT
	citizen_data.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	citizen_data.profession = WorkerData.Profession.NONE
	var visual_profile: VisualProfile = VisualProfile.new()
	visual_profile.skin_tone = skin_tone_container[choice.x]
	visual_profile.hair_style = hair_container[choice.y]
	# visual_profile.clothes_id = clothes_container.pick_random()
	# visual_profile.accessory = accessory_container.pick_random()
	citizen_data.visual_profile = visual_profile
	return citizen_data

func _appearance_key(profile: VisualProfile) -> String:
	return profile.skin_tone + "|" + profile.hair_style
