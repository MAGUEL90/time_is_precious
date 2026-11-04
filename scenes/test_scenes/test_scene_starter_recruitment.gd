extends Node

## Focused clock/save regression for the two authored starters. The player
## protection and clock advances are explicit fixture controls, not New Game.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const STARTERS = preload("res://scenes/content_scene/startup/initial_worksites.gd")
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
	var root: String = OS.get_environment("XDG_DATA_HOME")
	_check(root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(root.simplify_path().trim_suffix("/") + "/"), "Use a disposable XDG data directory.")
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
	var first: CitizenData = CitizenManager.get_citizen(STARTERS.APPLICANT_ID)
	var second: CitizenData = CitizenManager.get_citizen(STARTERS.HAULER_APPLICANT_ID)
	_check(first != null and second != null and is_equal_approx(first.satisfaction, 0.55)
		and is_equal_approx(second.satisfaction, 0.55) and Inventory.items.is_empty(),
		"Only the authored starters begin at 55%, with no personal resources granted.")
	var minute_of_day: int = TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	_check(TimeComponentManager.advance_minutes(1440 - minute_of_day + 8 * 60), "The fixture reaches the first normal Job Board opening.")
	_check(is_equal_approx(first.satisfaction, 0.5) and is_equal_approx(second.satisfaction, 0.5)
		and CitizenManager.get_all_applicants().size() == 2,
		"One unmet day leaves both starters eligible at the unchanged 50% threshold.")
	var store: Node = WorkStateRuntime.get_node("CitySave")
	_check(store.save_checkpoint(), "The 50% starter state saves: " + store.last_error)
	_check(TimeComponentManager.advance_minutes(1440), "The fixture reaches the second daily settlement.")
	_check(is_equal_approx(first.satisfaction, 0.45) and is_equal_approx(second.satisfaction, 0.45)
		and CitizenManager.get_all_applicants().is_empty(),
		"A second neglected day still lowers satisfaction and removes the applicants.")
	var initial: Node = city.get_node("YSortWorld/InitialWorksites")
	initial._register_applicant(STARTERS.APPLICANT_ID, STARTERS.LABORER_NAME, WorkerData.Profession.LABORER)
	_check(is_equal_approx(first.satisfaction, 0.45), "Revisiting starter registration does not reset an existing resident.")
	_check(store.load_checkpoint(), "The earlier starter checkpoint reloads: " + store.last_error)
	first = CitizenManager.get_citizen(STARTERS.APPLICANT_ID)
	second = CitizenManager.get_citizen(STARTERS.HAULER_APPLICANT_ID)
	_check(first != null and second != null and is_equal_approx(first.satisfaction, 0.5)
		and is_equal_approx(second.satisfaction, 0.5) and CitizenManager.get_all_applicants().size() == 2,
		"Loading preserves saved satisfaction rather than reapplying the starter buffer.")
	print("StarterRecruitmentTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
