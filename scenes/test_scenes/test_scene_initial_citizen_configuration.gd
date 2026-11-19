extends Node

## Exercises data-only starter changes using disposable profiles and in-memory
## resource edits. No authored scene, seed file, or real checkpoint is rewritten.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const STARTERS = preload("res://scenes/content_scene/startup/initial_worksites.gd")
const SEED = preload("res://scenes/content_scene/startup/initial_citizen_seed.gd")
const SEEDS: Array[InitialCitizenSeed] = [
	preload("res://scenes/content_scene/startup/initial_laborer_seed.tres"),
	preload("res://scenes/content_scene/startup/initial_worksite_laborer_seed.tres"),
	preload("res://scenes/content_scene/startup/initial_city_hauler_seed.tres")
]
const IDS: Array[String] = [STARTERS.APPLICANT_ID, STARTERS.HAULER_APPLICANT_ID, STARTERS.CITY_HAULER_APPLICANT_ID]
const NAMES: Array[String] = [STARTERS.LABORER_NAME, STARTERS.HAULER_NAME, STARTERS.CITY_HAULER_NAME]
const SLOT: String = "user://initial_citizen_configuration/checkpoint.json"
var checks: int = 0
var failures: int = 0
var launched: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS: ", message)

func _run() -> void:
	var root: String = OS.get_environment("XDG_DATA_HOME")
	var mode: String = OS.get_environment("TIP_STARTER_CONFIG_MODE")
	_check(root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(root.simplify_path().trim_suffix("/") + "/"), "Use disposable XDG data.")
	_check(mode in ["writer", "reader", "invalid"], "Use an explicit writer, reader or invalid-config mode.")
	_check(FileAccess.file_exists(SLOT) == (mode == "reader"), "Writer has a fresh slot; reader has its copied checkpoint.")
	if failures:
		_finish()
		return
	TimeComponentManager.set_process(false)
	_test_defaults_and_validation()
	_test_registration_guards()
	if mode == "invalid":
		var invalid_setup: Node = STARTERS.new()
		invalid_setup.city_hauler_seed = null
		invalid_setup._ready()
		_check(CitizenManager.citizens_by_id.is_empty() and WorkerDatabase.workers_by_id.is_empty(), "Invalid third seed aborts before publishing either earlier starter.")
		invalid_setup.free()
		print("EXPECTED_INVALID_SEED_GUARD failures=", failures)
		get_tree().quit(1 if failures == 0 else 2)
		return
	# Edits target the cached test-process copies, never .tres files on disk.
	_set_seed_revision(1 if mode == "writer" else 2)
	var original_hash: String = FileAccess.get_sha256(SLOT) if mode == "reader" else ""
	get_tree().current_scene = null
	var menu: Node = MENU.instantiate()
	menu.checkpoint_file.path = SLOT
	menu.session_started.connect(func(continued: bool): launched = continued == (mode == "reader"))
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await get_tree().process_frame
	if mode == "writer":
		menu.new_game_button.pressed.emit()
	else:
		menu.continue_button.pressed.emit()
	for _frame: int in range(1200):
		if launched:
			break
		await get_tree().process_frame
	_check(launched, "Actual Start Menu flow completes: " + mode)
	if not launched:
		_finish()
		return
	TimeComponentManager.set_process(false)
	for _frame: int in range(5):
		await get_tree().process_frame
	var city: Node = get_tree().current_scene
	var setup: Node = city.get_node("YSortWorld/InitialWorksites")
	var store: Node = WorkStateRuntime.get_node("CitySave")
	_verify_people(city)
	_check(CitizenManager.get_all_residents().size() == 3 and WorkerDatabase.workers_by_id.is_empty(), "The unchanged three residents exist, with no automatic hire.")
	_check(Inventory.items.is_empty(), "Configuration gives no personal inventory or money.")
	if mode == "writer":
		_check(store.save_checkpoint(), "Configured starters save through the unchanged codec: " + store.last_error)
		original_hash = FileAccess.get_sha256(SLOT)
		_set_seed_revision(2)
	for _repeat: int in range(3):
		setup._ready()
		_verify_people(city)
		_check(store.load_checkpoint(), "Saved configuration reloads without replacing identities: " + store.last_error)
		for _frame: int in range(4):
			await get_tree().process_frame
		_verify_people(city)
	_check(FileAccess.get_sha256(SLOT) == original_hash, "Repeated registration and Continue leave checkpoint bytes unchanged.")
	var legacy: VisualProfile = STARTERS.create_initial_visual_profile()
	_check(legacy.skin_tone == "light" and legacy.hair_style == "grey_male_01", "Changed new-citizen resources do not change legacy profile repair.")
	_check(STARTERS.CITY_HAULER_NAME == "Belum" and is_equal_approx(STARTERS.INITIAL_APPLICANT_SATISFACTION, 0.55), "Legacy missing-Hauler defaults remain frozen.")
	_finish()

func _test_defaults_and_validation() -> void:
	for index: int in range(SEEDS.size()):
		var seed: InitialCitizenSeed = SEEDS[index]
		_check(seed.validation_error().is_empty() and seed.display_name == NAMES[index] and is_equal_approx(seed.satisfaction, 0.55), "Default name and balance exactly match starter " + str(index))
		var profile: VisualProfile = seed.create_visual_profile()
		_check(profile.skin_tone == "light" and profile.expression == "base" and profile.hair_style == "grey_male_01" and profile.clothes_id == "clay_worn_wrap" and profile.accessory == "default", "Default appearance exactly matches starter " + str(index))
		profile.hair_style = "black_female_02"
		_check(seed.visual_profile.hair_style == "grey_male_01" and seed.create_visual_profile().hair_style == "grey_male_01", "Citizen profile edits do not mutate the shared seed.")
	var invalid: InitialCitizenSeed = SEEDS[0].duplicate(true)
	invalid.display_name = "  "
	_check(not invalid.validation_error().is_empty(), "Empty names are caught before startup.")
	invalid.display_name = "Test"
	for value: float in [-0.01, 1.01, INF, NAN]:
		invalid.satisfaction = value
		_check(not invalid.validation_error().is_empty(), "Out-of-range/nonfinite Satisfaction is rejected.")
	invalid.satisfaction = 0.55
	invalid.visual_profile = null
	_check(not invalid.validation_error().is_empty() and not STARTERS._seed_validation_error(null).is_empty(), "Missing profiles and missing seed resources are rejected.")

func _test_registration_guards() -> void:
	var setup: Node = STARTERS.new()
	var low: InitialCitizenSeed = SEEDS[0].duplicate(true)
	low.satisfaction = 0.49
	setup._register_applicant("configuration_threshold_probe", "Ignored", WorkerData.Profession.LABORER, low)
	var person: CitizenData = CitizenManager.get_citizen("configuration_threshold_probe")
	_check(person != null and person.population_status == CitizenData.PopulationStatus.RESIDENT and person.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED and not CitizenManager.get_all_applicants().has(person), "Data does not bypass the existing 50% applicant threshold.")
	person.population_status = CitizenData.PopulationStatus.LEFT_CITY
	low.satisfaction = 0.9
	setup._register_applicant(person.citizen_id, "Ignored", WorkerData.Profession.LABORER, low)
	_check(CitizenManager.get_citizen(person.citizen_id) == person and person.population_status == CitizenData.PopulationStatus.LEFT_CITY and is_equal_approx(person.satisfaction, 0.49), "A departed citizen is not recreated or reset.")
	var archived := WorkerData.new()
	archived.worker_id = "configuration_archive_probe"
	WorkerDatabase.dismissed_workers[archived.worker_id] = archived
	setup._register_applicant(archived.worker_id, "Ignored", WorkerData.Profession.LABORER, low)
	_check(CitizenManager.get_citizen(archived.worker_id) == null, "An archived worker is not recreated from configuration.")
	# Remove only these synthetic probes before opening the real fresh city.
	CitizenManager.citizens_by_id.erase(person.citizen_id)
	CitizenNeedsManager.satisfaction_last_minute.erase(person.citizen_id)
	CitizenNeedsManager.food_coverage_until.erase(person.citizen_id)
	CitizenNeedsManager.clothing_allocations.erase(person.citizen_id)
	CitizenNeedsManager.last_needs_results.erase(person.citizen_id)
	WorkerDatabase.dismissed_workers.erase(archived.worker_id)
	setup.free()

func _set_seed_revision(revision: int) -> void:
	for index: int in range(SEEDS.size()):
		SEEDS[index].display_name = "Configured starter " + str(index) if revision == 1 else "Later configuration " + str(index)
		SEEDS[index].satisfaction = 0.65 + index * 0.05 if revision == 1 else 0.9
		SEEDS[index].visual_profile.skin_tone = "dark" if revision == 1 else "warm"
		SEEDS[index].visual_profile.hair_style = "black_female_02" if revision == 1 else "red_female_03"

func _verify_people(city: Node) -> void:
	var visuals: Node = city.get_node("YSortWorld/WorkerRuntime/WorkerVisuals")
	for index: int in range(IDS.size()):
		var person: CitizenData = CitizenManager.get_citizen(IDS[index])
		_check(person != null, "Stable starter ID remains present: " + IDS[index])
		if person == null:
			continue
		_check(person.display_name == "Configured starter " + str(index) and is_equal_approx(person.satisfaction, 0.65 + index * 0.05), "Stored name and Satisfaction survive configuration changes: " + IDS[index])
		_check(person.visual_profile != SEEDS[index].visual_profile and person.visual_profile.skin_tone == "dark" and person.visual_profile.hair_style == "black_female_02", "Stored profile is independent of shared configuration: " + IDS[index])
		_check(person.profession == (WorkerData.Profession.HAULER if index == 2 else WorkerData.Profession.LABORER), "Configuration cannot change the fixed profession: " + IDS[index])
		var actor: Node = visuals.actors.get(IDS[index])
		_check(actor != null and actor.skin_tone == "dark" and actor.hair_style == "black_female_02", "Runtime visual projects the configured/saved profile: " + IDS[index])

func _finish() -> void:
	print("InitialCitizenConfigurationTest: ", "PASS" if failures == 0 else "FAIL", " checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
