extends Node

const MENU = preload("res://scenes/ui/start_menu/start_menu.tscn")
const TEST_PATH: String = "user://start_menu_test/checkpoint.json"
var failures: int = 0
var menu: CanvasLayer
var launched: bool = false
var continued: bool = false
var mode: String = "empty"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _expect(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
		push_error(text)

func _run() -> void:
	TimeComponentManager.set_process(false)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--menu-mode="):
			mode = argument.trim_prefix("--menu-mode=")
	var path: String = TEST_PATH
	if mode == "city":
		path = "user://city_save_test/checkpoint.json"
	elif mode == "home":
		path = "user://city_sleep_save_test/checkpoint.json"
	else:
		for suffix: String in ["", ".bak", ".tmp", ".pending"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(path + suffix)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		if mode == "corrupt":
			_write(path, "{broken")
			_write(path + ".bak", "prior checkpoint")
	menu = MENU.instantiate()
	menu.checkpoint_file.path = path
	menu.session_started.connect(func(was_continue: bool): launched = true; continued = was_continue)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _settle()
	_expect(get_tree().paused, "Startup holds the world paused.")
	await _capture("start-menu-" + mode)
	if mode in ["city", "home"]:
		_expect(not menu.continue_button.disabled, "Continue is available for a checkpoint.")
		var bytes_before: PackedByteArray = FileAccess.get_file_as_bytes(path)
		var expected: Dictionary = JSON.parse_string(bytes_before.get_string_from_utf8())
		menu.continue_button.pressed.emit()
		await _wait_launch()
		_expect(launched and continued, "Continue finishes successfully.")
		var store: Node = WorkStateRuntime.get_node("CitySave")
		var expected_scene: String = store.snapshot.HOME_PATH if mode == "home" else "res://scenes/content_scene/content_scene.tscn"
		_expect(get_tree().current_scene.scene_file_path == expected_scene, "Continue opens the saved location.")
		var actual: Dictionary = store.snapshot.capture(get_tree().current_scene)
		var evidence: String = OS.get_environment("TIP_START_CAPTURE_DIR")
		if not evidence.is_empty():
			_write(evidence.path_join("actual-" + mode + ".json"), JSON.stringify(actual, "", true, true))
			_write(evidence.path_join("expected-" + mode + ".json"), JSON.stringify(expected, "", true, true))
		var codec = preload("res://scenes/new_scenes/save_game/city_save_values.gd").new()
		var saved_sources: Dictionary = codec.decode(expected.state).pickup_sources
		_expect(store.snapshot._sources.capture() == saved_sources, "Continue restores every registered pickup source exactly.")
		if mode == "city":
			var view_count: int = 0
			for index: int in range(6):
				var palm: Node = get_tree().current_scene.get_node("YSortWorld/DatePalmTree" + ("" if index == 0 else str(index + 1)))
				var slots: Array = saved_sources[str(palm.state.name)].available
				view_count += slots.count(true)
				for slot: int in range(slots.size()):
					_expect(palm._pickups.has(slot) == slots[slot], "Continue projects the saved slot for " + str(palm.name))
			_expect(get_tree().get_nodes_in_group("date_palm_pickups").size() == view_count, "Continue creates no duplicate palm views.")
		_expect(_same_snapshot(actual, expected), "Continue restores the full checkpoint without elapsed time or extra sleep.")
		_expect(FileAccess.get_file_as_bytes(path) == bytes_before, "Continue never rewrites the checkpoint.")
		await _capture("continued-" + mode)
	elif mode == "corrupt":
		menu.continue_button.pressed.emit()
		await _wait_idle()
		_expect(not launched and get_tree().paused and menu.message.text.contains("Could not load"), "Invalid save leaves a paused, usable menu with feedback.")
		_expect(FileAccess.get_file_as_string(path) == "{broken", "Failed Continue preserves the invalid checkpoint.")
		await _capture("start-menu-invalid")
		menu.new_game_button.pressed.emit()
		_expect(menu.confirmation.visible, "New Game asks before archiving an existing save.")
		await _capture("start-menu-confirm")
		menu.confirmation.get_node("Buttons/Cancel").pressed.emit()
		_expect(FileAccess.file_exists(path), "Cancelling preserves the checkpoint.")
		menu.new_game_button.pressed.emit()
		# A save changed after confirmation must not be moved.
		_write(path, "{changed")
		menu.confirmation.get_node("Buttons/Start").pressed.emit()
		await _wait_idle()
		_expect(not launched and FileAccess.get_file_as_string(path) == "{changed", "Changed checkpoints are not archived without a new choice.")
		menu.new_game_button.pressed.emit()
		var archiver: RefCounted = menu.archive
		menu.confirmation.get_node("Buttons/Start").pressed.emit()
		await _wait_launch()
		_expect(launched and not continued, "Confirmed New Game can recover from an invalid save.")
		_expect(not FileAccess.file_exists(path) and FileAccess.get_file_as_string(archiver.archive_path.path_join("checkpoint.json")) == "{changed", "New Game preserves the old primary in its archive.")
		_expect(FileAccess.get_file_as_string(archiver.archive_path.path_join("checkpoint.json.bak")) == "prior checkpoint", "New Game also preserves the old backup.")
		var store: Node = WorkStateRuntime.get_node("CitySave")
		_expect(store.save_checkpoint(), "The fresh game can save after an invalid slot was archived.")
	else:
		_expect(menu.continue_button.disabled, "Continue is disabled without a checkpoint.")
		menu.new_game_button.pressed.emit()
		await _wait_launch()
		_expect(launched and not continued, "New Game opens the authored city.")
		_expect(not FileAccess.file_exists(path), "Starting a game does not save before sleep.")
		var merchant: Node = get_tree().current_scene.get_node("YSortWorld/TravelingMerchant")
		_expect(not merchant.debug_first_day_visit and not merchant.state.is_present(), "A normal startup does not force a day-zero merchant.")
		var player: Player = get_tree().current_scene.get_node("YSortWorld/Player")
		_expect(not player.debug_disable_player_needs and not player.debug_disable_fatigue, "New Game uses normal player needs.")
	_expect(not get_tree().paused, "Successful startup resumes gameplay.")
	print("StartMenuTest ", mode, ": ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _settle() -> void:
	for frame: int in range(3):
		await get_tree().process_frame

func _wait_launch() -> void:
	var deadline: int = Time.get_ticks_msec() + 10000
	while not launched and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await _settle()

func _wait_idle() -> void:
	var deadline: int = Time.get_ticks_msec() + 10000
	while is_instance_valid(menu) and menu._busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await _settle()

func _capture(name: String) -> void:
	var folder: String = OS.get_environment("TIP_START_CAPTURE_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(name + ".png"))

func _same_snapshot(left: Variant, right: Variant) -> bool:
	# JSON reads schema numbers as floats and can shift float payloads by one ULP.
	# Encoded integer counts and RNG states are strings and must still match exactly.
	if (left is float or left is int) and (right is float or right is int):
		return absf(float(left) - float(right)) < 0.0000000001
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _same_snapshot(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for index: int in left.size():
			if not _same_snapshot(left[index], right[index]):
				return false
		return true
	return left == right
