extends Node

var display_name_container: Array[String] = [
	"Enkiya", "Lugal", "Naram", "Urani", "Dagan", "Ashur", "Nabu", "Tammuz", "Sinbel", "Iddin"]
var skin_tone_container: Array[String] = [
	"dark", "light", "tan", "warm"]
var hair_container: Array[String] = [
	"default", 
	"grey_female_01", "grey_female_02", "grey_female_03", 
	"grey_male_01", "grey_male_02", "grey_male_03", 
	"red_female_01", "red_female_02", "red_female_03", 
	"red_male_01", "red_male_02", "red_male_03",
	"black_female_01", "black_female_02", "black_female_03", 
	"black_male_01", "black_male_02", "black_male_03",
	"brown_female_01", "brown_female_02", "brown_female_03", 
	"brown_male_01", "brown_male_02", "brown_male_03"]
var clothes_container: Array[String] = [
	"default", "clay_worn_wrap", "plain_worn_wrap"]
var accessory_container: Array[String] = [
	"default", "farmer_hat"]
var counter_id: int = 0

func generate_citizen() -> CitizenData:
	counter_id += 1
	var citizen_data: CitizenData = CitizenData.new()
	citizen_data.citizen_id = "citizen_%03d" % counter_id
	citizen_data.display_name = display_name_container.pick_random()
	citizen_data.status = CitizenData.CitizenStatus.CITIZEN
	citizen_data.profession = WorkerData.Profession.NONE
	var visual_profile: VisualProfile = VisualProfile.new()
	visual_profile.skin_tone = skin_tone_container.pick_random()
	visual_profile.hair_style = hair_container.pick_random()
	visual_profile.clothes_id = clothes_container.pick_random()
	visual_profile.accessory = accessory_container.pick_random()
	citizen_data.visual_profile = visual_profile
	return citizen_data
