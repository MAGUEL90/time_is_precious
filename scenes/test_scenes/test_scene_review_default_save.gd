extends Node

## Runs real menu/Save/Continue flows in a caller-provided isolated user root.
## A synthetic old-city checkpoint and its recovery files must remain intact.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const SAVE_FILE = preload("res://scenes/new_scenes/save_game/city_save_file.gd")
const CITY: String = "res://scenes/content_scene/content_scene.tscn"
const HOME: String = "res://scenes/player_home_interior/player_home_interior.tscn"
const SAVE: String = "user://city_save/authored_map/checkpoint_v1.json"
const LEGACY_SAVE: String = "user://city_save/checkpoint_v1.json"
const LEGACY_FIXTURE: String = "res://scenes/test_scenes/fixtures/legacy_houses_v13/clearing.json.gz"
const SUFFIXES: Array[String] = ["", ".bak", ".tmp", ".pending"]
var started: bool = false
var continued: bool = false
var errors: int = 0
var legacy_bytes: PackedByteArray

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		errors += 1
		push_error(message)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var phase: String = "write" if "--review-save=write" in args else ("read" if "--review-save=read" in args else ("restart" if "--review-save=restart" in args else ""))
	_expect(not phase.is_empty(), "Choose write, read, or restart.")
	var isolated_root: String = OS.get_environment("TIP_ISOLATED_DATA_ROOT").simplify_path().replace("\\", "/").trim_suffix("/")
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path().replace("\\", "/").trim_suffix("/")
	_expect(not isolated_root.is_empty() and isolated_root.is_absolute_path() and user_root.begins_with(isolated_root + "/"),
		"Use a fresh TIP_ISOLATED_DATA_ROOT containing the Godot user directory.")
	_expect(str(ProjectSettings.get_setting("application/config/name")) == "time_is_precious"
		and not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)),
		"The original application identity is retained.")
	_expect(SAVE_FILE.DEFAULT_PATH == SAVE and SAVE != LEGACY_SAVE, "The authored map owns a distinct checkpoint path.")
	if errors:
		_finish(phase)
		return
	legacy_bytes = FileAccess.get_file_as_bytes(LEGACY_FIXTURE).decompress_dynamic(1000000, FileAccess.COMPRESSION_GZIP)
	_expect(not legacy_bytes.is_empty(), "The synthetic old-city save is available.")
	if phase == "write":
		for suffix: String in SUFFIXES:
			_expect(not FileAccess.file_exists(LEGACY_SAVE + suffix) and not FileAccess.file_exists(SAVE + suffix),
				"The isolated profile starts without existing checkpoints.")
		if errors:
			_finish(phase)
			return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LEGACY_SAVE).get_base_dir())
		for index: int in range(SUFFIXES.size()):
			var file: FileAccess = FileAccess.open(LEGACY_SAVE + SUFFIXES[index], FileAccess.WRITE)
			_expect(file != null, "The synthetic legacy recovery file opens.")
			if file != null:
				file.store_buffer(_legacy_expected(index))
				file.close()
	_expect(_legacy_unchanged(), "The synthetic old checkpoint and all recovery files are intact before launch.")
	_expect(FileAccess.file_exists(SAVE) == (phase != "write"), "The new-map slot has the expected starting state.")
	if errors:
		_finish(phase)
		return
	var bytes_before: PackedByteArray = FileAccess.get_file_as_bytes(SAVE) if phase != "write" else PackedByteArray()
	get_tree().current_scene = null
	var menu = MENU.instantiate()
	var archive = menu.archive
	menu.session_started.connect(func(from_save: bool):
		continued = from_save
		started = true)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	_expect(menu.checkpoint_file.path == SAVE and menu.continue_button.disabled == (phase == "write"),
		"The real menu only offers Continue for the authored-map slot.")
	if phase == "read":
		menu._continue_game()
	else:
		menu._request_new_game()
		if phase == "restart":
			_expect(menu.confirmation.visible, "New Game asks before archiving the existing new-map save.")
			menu.confirmation.get_node("Buttons/Start").pressed.emit()
	for frame in range(1200):
		if started:
			break
		await get_tree().process_frame
	_expect(started and continued == (phase == "read"), "The normal menu opens the requested session.")
	if not started:
		_finish(phase)
		return
	var city: Node = get_tree().current_scene
	var store: Node = WorkStateRuntime.get_node("CitySave")
	var house: Node = city.get_node("YSortWorld/CitizenHousePlot").construction
	var marker: Node2D = city.get_node("AuthoredMap/YSortWorld/ToBeClean1")
	var footprint: TileMapLayer = city.get_node("AuthoredMap/Ground/Setelah Cleaning")
	TimeComponentManager.set_process(false)
	_expect(city.scene_file_path == CITY and store.disk.path == SAVE, "The authored map and separate checkpoint are active.")
	if phase == "write":
		_expect(archive.archive_path.is_empty(), "New Game does not archive the old-city slot.")
		_expect(bool(house.start_clearing([] as Array[String], true).get("success", false)), "Player begins clearing.")
		_expect(TimeComponentManager.advance_minutes(30), "Thirty clearing minutes advance.")
		house.interrupt_player_work()
		_expect(house.clearing_remaining == 150 and marker.visible and footprint.get_used_cells().size() == 4, "The partial job keeps its pre-cleaning visual.")
		_expect(store.save_checkpoint() and FileAccess.file_exists(SAVE), "The authored-map checkpoint saves: " + store.last_error)
	elif phase == "read":
		_expect(FileAccess.get_file_as_bytes(SAVE) == bytes_before and house.clearing_remaining == 150
			and marker.visible and footprint.get_used_cells().size() == 4,
			"Continue restores the partial house without rewriting the save.")
		var player: Player = city.get_node("YSortWorld/Player")
		city.get_node("YSortWorld/HomeDoor")._on_body_entered(player)
		if not await _wait_scene(HOME):
			_finish(phase)
			return
		var home: Node = get_tree().current_scene
		_expect(house.clearing_remaining == 150 and store.save_after_sleep(home.get_node("YSortWorld/Player")),
			"The ordinary sleep-save path writes the authored-map slot.")
		home.get_node("YSortWorld/ExitDoor")._on_body_entered(home.get_node("YSortWorld/Player"))
		if not await _wait_scene(CITY):
			_finish(phase)
			return
		city = get_tree().current_scene
		marker = city.get_node("AuthoredMap/YSortWorld/ToBeClean1")
		_expect(house.clearing_remaining == 150 and marker.visible, "Leaving home returns to the authored map with work preserved.")
		_expect(store.load_checkpoint(), "The new-map home checkpoint loads: " + store.last_error)
		if not await _wait_scene(HOME):
			_finish(phase)
			return
		for frame in range(600):
			if not store._busy:
				break
			await get_tree().process_frame
		_expect(store.status == "Loaded" and house.clearing_remaining == 150, "Continue returns home without losing the partial job.")
	else:
		_expect(archive.archive_path.begins_with("user://city_save/authored_map/archive/")
			and FileAccess.get_file_as_bytes(archive.archive_path.path_join("checkpoint_v1.json")) == bytes_before,
			"Restart archives only the new-map checkpoint in its own folder.")
		_expect(house.phase == "uncleared" and house.clearing_remaining == house.CLEARING_MINUTES,
			"A confirmed New Game begins with a fresh authored-map house.")
	_expect(_legacy_unchanged(), "The old checkpoint, backup and recovery files remain byte-for-byte intact.")
	_finish(phase)

func _legacy_expected(index: int) -> PackedByteArray:
	var result: PackedByteArray = legacy_bytes.duplicate()
	result.append_array(("\n" + " ".repeat(index)).to_utf8_buffer())
	return result

func _legacy_unchanged() -> bool:
	for index: int in range(SUFFIXES.size()):
		var path: String = LEGACY_SAVE + SUFFIXES[index]
		if not FileAccess.file_exists(path) or FileAccess.get_file_as_bytes(path) != _legacy_expected(index):
			return false
	return true

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
