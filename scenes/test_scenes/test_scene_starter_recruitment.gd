extends Node

## Focused clock/save regression for the three authored starters. The player
## protection and clock advances are explicit fixture controls, not New Game.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const STARTERS = preload("res://scenes/content_scene/startup/initial_worksites.gd")
const STARTER_IDS: Array[String] = [STARTERS.APPLICANT_ID, STARTERS.HAULER_APPLICANT_ID, STARTERS.CITY_HAULER_APPLICANT_ID]
const MINUTE_RATE: float = 0.05 / 1440.0
const SLOT: String = "user://starter_recruitment/checkpoint.json"
var failures: int = 0
var launched: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _frames() -> void:
	for _frame: int in range(5):
		await get_tree().physics_frame

func _run() -> void:
	_check(_isolated_profile_is_safe(), "Use distinct disposable XDG directories under the sibling citysave_suite_qa directory.")
	_check(not FileAccess.file_exists(SLOT), "Use a fresh starter checkpoint.")
	if failures > 0:
		get_tree().quit(1)
		return
	get_tree().current_scene = null
	var menu: Node = MENU.instantiate()
	menu.checkpoint_file.path = SLOT
	menu.session_started.connect(func(continued: bool): launched = not continued)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	menu.new_game_button.pressed.emit()
	for _frame: int in range(1200):
		if launched:
			break
		await get_tree().process_frame
	_check(launched, "Start Menu launches the actual New Game.")
	if not launched:
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	var city: Node = get_tree().current_scene
	var player: Player = city.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	_check_starters(0.55, 3, "New Game seeds all three starters at 55% without hiring them.")
	_check(Inventory.items.is_empty(), "New Game grants no personal resources.")
	for id: String in STARTER_IDS:
		var needs: Dictionary = CitizenNeedsManager.get_person_needs_summary(id)
		_check(not bool(needs.food) and not bool(needs.clothing) and not bool(needs.shelter),
			"The starter shortage begins with no fulfilled need: " + id)
	var minute_of_day: int = TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	var to_open: int = 1440 - minute_of_day + 8 * 60
	_check(to_open > 0 and to_open < 1440, "The next 08:00 opening is less than one full day after this New Game.")
	_check(TimeComponentManager.advance_minutes(to_open), "The fixture reaches the next normal Job Board opening.")
	_check_starters(0.55 - MINUTE_RATE * float(to_open), 3,
		"The next opening applies only the actual elapsed shortage minutes, not a whole-day deduction.")
	var saved_satisfaction: float = 0.55 - MINUTE_RATE * float(to_open)
	var later_satisfaction: float = saved_satisfaction - 0.05
	_check(saved_satisfaction > 0.5 and later_satisfaction < 0.5,
		"The next opening and the following day lie on opposite sides of the unchanged hiring threshold.")
	var store: Node = WorkStateRuntime.get_node("CitySave")
	var saved: bool = store.save_checkpoint()
	_check(saved, "The first-opening starter state saves: " + store.last_error)
	if not saved:
		get_tree().quit(1)
		return
	var saved_files: Dictionary = _checkpoint_files()
	_check(TimeComponentManager.advance_minutes(1440), "Advance one complete shortage day after the saved opening.")
	_check_starters(later_satisfaction, 0, "Another 24 unmet hours lowers actual Satisfaction by five points and removes eligible applicants.")
	var first: CitizenData = CitizenManager.get_citizen(STARTERS.APPLICANT_ID)
	var initial: Node = city.get_node("YSortWorld/InitialWorksites")
	initial._register_applicant(STARTERS.APPLICANT_ID, STARTERS.LABORER_NAME, WorkerData.Profession.LABORER)
	_check(absf(first.satisfaction - later_satisfaction) < 0.000000001, "Revisiting starter registration does not reset an existing resident.")
	var loaded: bool = store.load_checkpoint()
	_check(loaded, "The earlier starter checkpoint reloads: " + store.last_error)
	if loaded:
		_check_starters(saved_satisfaction, 3, "Continue restores the exact saved opening state and all three eligible applicants.")
		_check(_checkpoint_files() == saved_files, "Continue preserves all checkpoint filenames and bytes.")
		_check(store.load_checkpoint(), "The first-opening checkpoint can be loaded repeatedly.")
		_check_starters(saved_satisfaction, 3, "Repeated Continue does not reapply elapsed needs or duplicate applicants.")
		_check(_checkpoint_files() == saved_files, "Repeated Continue preserves all checkpoint bytes.")
	print("StarterRecruitmentTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _check_starters(expected: float, eligible: int, message: String) -> void:
	var valid: bool = CitizenManager.get_all_residents().size() == STARTER_IDS.size()
	for id: String in STARTER_IDS:
		var citizen: CitizenData = CitizenManager.get_citizen(id)
		valid = valid and citizen != null and absf(citizen.satisfaction - expected) < 0.000000001 \
			and citizen.employment_status == CitizenData.EmploymentStatus.APPLICANT \
			and not WorkerDatabase.has_worker_data(id)
	_check(valid and CitizenManager.get_all_applicants().size() == eligible, message)

func _checkpoint_files() -> Dictionary:
	var files: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		files[suffix] = FileAccess.get_file_as_bytes(SLOT + suffix) if FileAccess.file_exists(SLOT + suffix) else null
	return files

func _isolated_profile_is_safe() -> bool:
	var qa_root: String = ProjectSettings.globalize_path("res://../citysave_suite_qa").simplify_path()
	var homes: Array[String] = []
	for variable: String in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		var home: String = OS.get_environment(variable).simplify_path()
		if home.is_empty() or not home.is_absolute_path() or not DirAccess.dir_exists_absolute(home) \
			or not home.begins_with(qa_root + "/") or homes.has(home):
			return false
		homes.append(home)
	return ProjectSettings.globalize_path("user://").simplify_path().begins_with(homes[0] + "/")
