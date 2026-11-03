extends Node

## Exercises the actual default review save path across processes. The caller
## must use a fresh isolated XDG_DATA_HOME, never an owner's real profile.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const CITY: String = "res://scenes/content_scene/content_scene.tscn"
const HOME: String = "res://scenes/player_home_interior/player_home_interior.tscn"
const SAVE: String = "user://city_save/checkpoint_v1.json"
var started: bool = false
var continued: bool = false
var errors: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		errors += 1
		push_error(message)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var phase: String = "write" if "--review-save=write" in args else ("read" if "--review-save=read" in args else "")
	_expect(not phase.is_empty(), "Choose write or read.")
	var user_dir: String = ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/")
	_expect(user_dir.ends_with("/time_is_precious_review_20261103"), "The preview uses its separate user data directory: " + user_dir)
	_expect(FileAccess.file_exists(SAVE) == (phase == "read"), "The default review slot has the expected starting state.")
	if errors:
		_finish(phase)
		return
	var bytes_before: PackedByteArray = FileAccess.get_file_as_bytes(SAVE) if phase == "read" else PackedByteArray()
	get_tree().current_scene = null
	var menu = MENU.instantiate()
	menu.session_started.connect(func(from_save: bool):
		continued = from_save
		started = true)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	if phase == "write":
		menu._request_new_game()
	else:
		menu._continue_game()
	for frame in range(1200):
		if started:
			break
		await get_tree().process_frame
	_expect(started and continued == (phase == "read"), "The default menu opens the requested review session.")
	if not started:
		_finish(phase)
		return
	var city: Node = get_tree().current_scene
	var store: Node = WorkStateRuntime.get_node("CitySave")
	var house: Node = city.get_node("YSortWorld/CitizenHousePlot").construction
	var marker: Node2D = city.get_node("AuthoredMap/YSortWorld/ToBeClean1")
	var footprint: TileMapLayer = city.get_node("AuthoredMap/Ground/Setelah Cleaning")
	TimeComponentManager.set_process(false)
	_expect(city.scene_file_path == CITY and store.disk.path == SAVE, "The preview map and default isolated checkpoint are active.")
	if phase == "write":
		_expect(bool(house.start_clearing([] as Array[String], true).get("success", false)), "Player begins clearing.")
		_expect(TimeComponentManager.advance_minutes(30), "Thirty clearing minutes advance.")
		house.interrupt_player_work()
		_expect(house.clearing_remaining == 150 and marker.visible and footprint.get_used_cells().size() == 4, "The partial job keeps its pre-cleaning visual.")
		_expect(store.save_checkpoint() and FileAccess.file_exists(SAVE), "The normal review checkpoint saves: " + store.last_error)
	else:
		_expect(FileAccess.get_file_as_bytes(SAVE) == bytes_before and house.clearing_remaining == 150
			and marker.visible and footprint.get_used_cells().size() == 4,
			"Continue restores the exact partial house without rewriting the save.")
		var player: Player = city.get_node("YSortWorld/Player")
		city.get_node("YSortWorld/HomeDoor")._on_body_entered(player)
		if not await _wait_scene(HOME):
			_finish(phase)
			return
		_expect(house.clearing_remaining == 150 and store.save_checkpoint(), "The unfinished house saves while player is home.")
		var home: Node = get_tree().current_scene
		home.get_node("YSortWorld/ExitDoor")._on_body_entered(home.get_node("YSortWorld/Player"))
		if not await _wait_scene(CITY):
			_finish(phase)
			return
		city = get_tree().current_scene
		marker = city.get_node("AuthoredMap/YSortWorld/ToBeClean1")
		_expect(house.clearing_remaining == 150 and marker.visible, "Leaving home returns to the review map with work preserved.")
		_expect(store.load_checkpoint(), "The home review checkpoint loads: " + store.last_error)
		if not await _wait_scene(HOME):
			_finish(phase)
			return
		for frame in range(600):
			if not store._busy:
				break
			await get_tree().process_frame
		_expect(store.status == "Loaded" and house.clearing_remaining == 150,
			"Continue returns home without losing the partial job.")
	_finish(phase)

func _wait_scene(path: String) -> bool:
	for frame in range(1200):
		var current: Node = get_tree().current_scene
		if current != null and current.scene_file_path == path and not SceneTransition.is_transitioning:
			return true
		await get_tree().process_frame
	_expect(false, "Timed out waiting for " + path)
	return false

func _finish(phase: String) -> void:
	print("ReviewDefaultSaveTest ", phase, ": ", "PASS" if errors == 0 else "FAIL (%d)" % errors)
	get_tree().quit(0 if errors == 0 else 1)
