extends Node

## Fresh-process shutdown probes. This test only writes an isolated XDG profile.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const SAVE: String = "user://city_save/authored_map/checkpoint_v1.json"
const BASE_HUNGER: float = 0.2
const BASE_FATIGUE: float = 0.8
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _wait_for(predicate: Callable, milliseconds: int = 15000) -> bool:
	var deadline: int = Time.get_ticks_msec() + milliseconds
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())

func _run() -> void:
	var phase: String = OS.get_environment("TIP_QA_PHASE")
	var root: String = OS.get_environment("XDG_DATA_HOME").simplify_path().replace("\\", "/").trim_suffix("/")
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path().replace("\\", "/")
	var marker: String = OS.get_environment("TIP_QA_READY_FILE").simplify_path().replace("\\", "/")
	_check(root.is_absolute_path() and not root.is_empty() and user_root.begins_with(root + "/"), "The Godot user directory must be inside the isolated XDG profile")
	_check(phase in ["write", "active", "partial", "ready", "resumed", "read"], "A supported phase is required")
	if phase in ["active", "partial", "ready", "resumed"]:
		_check(marker.is_absolute_path() and marker.begins_with(root + "/") and not FileAccess.file_exists(marker), "The ready marker must be new and inside the isolated profile")
	if failures:
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var city: Node = CITY.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	for _frame: int in range(4):
		await get_tree().process_frame
	var player: Player = city.get_node("YSortWorld/Player")
	var nightmare: NightmareWorld = city.get_node("YSortWorld/NightmareWorld")
	var store: Node = WorkStateRuntime.get_node("CitySave")
	_check(store.disk.path == SAVE, "The actual authored city checkpoint slot must be used")
	player.debug_disable_player_needs = false
	player.debug_disable_fatigue = false
	if phase == "write":
		for suffix: String in ["", ".bak", ".tmp", ".pending"]:
			_check(not FileAccess.file_exists(SAVE + suffix), "The isolated slot must start empty")
		player.hunger = BASE_HUNGER
		player.fatigue = BASE_FATIGUE
		player.last_sleep_day = -1
		player.last_collapse_day = -1
		_check(_now() == 600, "The fresh world starts at 10:00 on day zero")
		_check(store.save_checkpoint(), "Write the valid isolated primary checkpoint: " + store.last_error)
		_check(store.save_checkpoint(), "Create a valid isolated backup through the actual save path: " + store.last_error)
		_check(FileAccess.file_exists(SAVE) and FileAccess.file_exists(SAVE + ".bak"), "Both primary and backup exist")
		_finish(phase)
		return
	var loaded: bool = store.load_checkpoint()
	_check(loaded and _now() == 600 and is_equal_approx(player.hunger, BASE_HUNGER)
		and is_equal_approx(player.fatigue, BASE_FATIGUE)
		and player.last_sleep_day == -1 and player.last_collapse_day == -1,
		"Fresh-process load restores the checkpoint, not unsaved Nightmare progress: " + store.last_error)
	if failures:
		_finish(phase)
		return
	if phase == "read":
		for _frame: int in range(15):
			await get_tree().process_frame
		_check(_now() == 600 and not nightmare.is_active and SceneTransition.get_node_or_null("NightmareReturnOperation") == null,
			"Loading never silently resumes an unfinished Nightmare transaction")
		_finish(phase)
		return
	_check(TimeComponentManager.advance_minutes(5), "Create five ordinary unsaved minutes before Nightmare")
	_check(_now() == 605 and is_equal_approx(player.hunger, 0.205) and is_equal_approx(player.fatigue, 0.8025),
		"The unsaved pre-Nightmare state is observable")
	_check(nightmare.start_nightmare(player, 1), "Start the real city Nightmare")
	nightmare.set_process(false)
	if phase == "partial":
		TimeComponentManager.minute_changed.connect(func(_minute: int) -> void:
			if _now() == 613:
				Inventory._bulk_transaction_in_progress = true)
	if phase != "active":
		nightmare.elapsed_seconds = 30.0
		nightmare.finish_nightmare(false)
		if phase == "partial":
			_check(await _wait_for(func() -> bool: return _now() == 613), "Exactly eight Nightmare minutes are committed before the held transaction")
			for _frame: int in range(40):
				await get_tree().process_frame
			_check(_now() == 613 and Inventory._bulk_transaction_in_progress
				and SceneTransition.has_node("NightmareReturnOperation") and not SceneTransition.continue_button.visible
				and is_equal_approx(player.hunger, 0.213) and is_equal_approx(player.fatigue, 0.8025),
				"The partial operation remains held without applying the fixed effects")
		else:
			_check(await _wait_for(func() -> bool: return SceneTransition.continue_button.visible), "The completed result reaches Continue")
			_check(_now() == 635 and is_equal_approx(player.hunger, 0.435)
				and is_equal_approx(player.fatigue, 0.5025), "Thirty minutes and one set of effects exist in memory")
			if phase == "resumed" and SceneTransition.continue_button.visible:
				SceneTransition.continue_button.pressed.emit()
				_check(await _wait_for(func() -> bool:
					return not SceneTransition.is_transitioning and not SceneTransition.has_node("NightmareReturnOperation")),
					"The real Continue action returns to normal play")
				_check(_now() == 635 and player.can_move and not player.is_sleeping and not TimeComponentManager.is_paused,
					"The completed Nightmare remains in memory after Continue")
	else:
		_check(nightmare.is_active and _now() == 605, "The active Nightmare has not yet advanced world time")
	if phase != "resumed":
		var before: PackedByteArray = FileAccess.get_file_as_bytes(SAVE)
		_check(not store.save_checkpoint() and FileAccess.get_file_as_bytes(SAVE) == before,
			"The actual save owner refuses a checkpoint during this stage")
	else:
		_check(store.snapshot.busy_reason(city).is_empty(), "Saving is available again after Continue, but this probe does not save")
	if failures:
		_finish(phase)
		return
	var file: FileAccess = FileAccess.open(marker, FileAccess.WRITE)
	_check(file != null, "The isolated readiness marker opens")
	if file == null:
		_finish(phase)
		return
	file.store_string(JSON.stringify({"phase": phase, "clock": _now(), "hunger": player.hunger, "fatigue": player.fatigue}))
	file.close()
	print("SHUTDOWN_BOUNDARY_READY ", phase, " clock=", _now(), " hunger=", player.hunger, " fatigue=", player.fatigue)
	if OS.get_environment("TIP_QA_SHUTDOWN") == "clean":
		_finish(phase)
		return
	while true:
		await get_tree().process_frame

func _finish(phase: String) -> void:
	print("NightmareShutdownBoundary ", phase, ": ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
