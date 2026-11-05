extends Node

## The writer runs on the earlier city layout, where (0, -270) was ordinary
## walkable ground; the reader uses the real Start Menu in the newer layout.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const SAVE_PATH: String = "user://old_door_continue/checkpoint.json"
const OLD_GROUND: Vector2 = Vector2(0, -270)
var errors: int = 0
var started: bool = false
var continued: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		errors += 1
		push_error(message)

func _run() -> void:
	var phase: String = "write"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--door-phase="):
			phase = arg.trim_prefix("--door-phase=")
	var data_root: String = OS.get_environment("XDG_DATA_HOME").simplify_path().trim_suffix("/")
	_expect(data_root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(data_root + "/"),
		"Use a disposable XDG profile.")
	_expect(phase in ["write", "read"] and FileAccess.file_exists(SAVE_PATH) == (phase == "read"),
		"Use an isolated writer followed by its reader.")
	if errors:
		_finish(phase)
		return
	get_tree().current_scene = null
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = SAVE_PATH
	menu.session_started.connect(func(from_save: bool):
		started = true
		continued = from_save)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	if phase == "write":
		menu._request_new_game()
	else:
		menu._continue_game()
	for frame: int in range(1200):
		if started:
			break
		await get_tree().process_frame
	_expect(started and continued == (phase == "read"), "The real menu starts the requested session.")
	if not started:
		_finish(phase)
		return
	var city: Node = get_tree().current_scene
	var player: Player = city.get_node("YSortWorld/Player")
	TimeComponentManager.set_process(false)
	if phase == "write":
		var old_door: Node2D = city.get_node("YSortWorld/HomeDoor")
		_expect(old_door.global_position.distance_to(OLD_GROUND) > 30.0,
			"Run the writer on the original bdf5dd9 layout, where this is not a doorway.")
		player.global_position = OLD_GROUND
		_expect(WorkStateRuntime.get_node("CitySave").save_checkpoint(), "The old layout saves the player position.")
	else:
		_expect(player.global_position.is_equal_approx(OLD_GROUND), "Continue restores the saved world position.")
		var saved_bytes: PackedByteArray = FileAccess.get_file_as_bytes(SAVE_PATH)
		for frame: int in range(120):
			await get_tree().physics_frame
			if get_tree().current_scene != city:
				break
		_expect(get_tree().current_scene == city and not SceneTransition.is_transitioning,
			"Continue does not automatically enter the moved home without player input.")
		_expect(FileAccess.get_file_as_bytes(SAVE_PATH) == saved_bytes, "Continue leaves the checkpoint bytes unchanged.")
		if errors:
			_finish(phase)
			return
		_expect(WorkStateRuntime.get_node("CitySave").load_checkpoint(), "Loading the same checkpoint again succeeds.")
		for frame: int in range(60):
			await get_tree().physics_frame
			if get_tree().current_scene != city:
				break
		_expect(get_tree().current_scene == city and not SceneTransition.is_transitioning
			and player.global_position.is_equal_approx(OLD_GROUND),
			"Repeated Load also keeps the player at the saved city position.")
		if errors:
			_finish(phase)
			return
		var raid_ui: RaidUI = WorkStateRuntime.get_node("CityRaid/RaidUI") as RaidUI
		if raid_ui.details_panel.visible:
			raid_ui.close_details()
		Input.action_press("move_down")
		for frame: int in range(120):
			await get_tree().physics_frame
			if player.global_position.y > OLD_GROUND.y + 24.0:
				break
		Input.action_release("move_down")
		_expect(player.global_position.y > OLD_GROUND.y + 24.0 and get_tree().current_scene == city,
			"The player can walk out of the restored doorway overlap.")
		Input.action_press("move_up")
		for frame: int in range(120):
			await get_tree().physics_frame
			if SceneTransition.is_transitioning:
				break
		Input.action_release("move_up")
		for frame: int in range(120):
			if get_tree().current_scene != city and not SceneTransition.is_transitioning:
				break
			await get_tree().process_frame
		_expect(get_tree().current_scene != city
			and get_tree().current_scene.scene_file_path == "res://scenes/player_home_interior/player_home_interior.tscn",
			"Walking back through the doorway still enters the home normally.")
	_finish(phase)

func _finish(phase: String) -> void:
	get_tree().paused = false
	print("OldDoorContinueTest ", phase, ": ", "PASS" if errors == 0 else "FAIL (%d)" % errors)
	get_tree().quit(0 if errors == 0 else 1)
