extends Node

## The real authored city and checkpoint owner run only inside a fresh XDG profile.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const TEST_SAVE: String = "user://nightmare_roundtrip/checkpoint.json"
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _wait_until(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 15000
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())

func _run() -> void:
	var data_root: String = OS.get_environment("XDG_DATA_HOME")
	_check(data_root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(data_root.simplify_path().trim_suffix("/") + "/"), "Use isolated checkpoint data")
	_check(not FileAccess.file_exists(TEST_SAVE), "Use a fresh checkpoint path")
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
	store.disk.path = TEST_SAVE
	player.debug_disable_player_needs = false
	player.debug_disable_fatigue = false
	player.hunger = 0.2
	player.fatigue = 0.8
	var start: int = _now()
	var initial_saved: bool = store.save_checkpoint()
	_check(initial_saved, "Create a valid isolated checkpoint before Nightmare: " + store.last_error)
	if not initial_saved:
		get_tree().quit(1)
		return
	var initial_bytes: PackedByteArray = FileAccess.get_file_as_bytes(TEST_SAVE)
	_check(nightmare.start_nightmare(player, 1), "The authored city Nightmare starts")
	_check(not store.save_checkpoint() and FileAccess.get_file_as_bytes(TEST_SAVE) == initial_bytes,
		"An active Nightmare refuses to overwrite the valid checkpoint")
	nightmare.elapsed_seconds = 30.0
	nightmare.finish_nightmare(false)
	var shown: bool = await _wait_until(func() -> bool: return SceneTransition.continue_button.visible)
	_check(shown and _now() == start + 30 and is_equal_approx(player.hunger, 0.43)
		and is_equal_approx(player.fatigue, 0.5), "Normal return applies time and conditions once")
	if not shown:
		get_tree().quit(1)
		return
	_check(not store.save_checkpoint() and FileAccess.get_file_as_bytes(TEST_SAVE) == initial_bytes,
		"The result screen also refuses to overwrite the existing checkpoint")
	SceneTransition.continue_button.pressed.emit()
	var finished: bool = await _wait_until(func() -> bool:
		return not SceneTransition.is_transitioning and SceneTransition.get_node_or_null("NightmareReturnOperation") == null)
	_check(finished and not TimeComponentManager.is_paused and player.can_move and not player.is_sleeping,
		"The completed return releases its pause and locks")
	var final_saved: bool = store.save_checkpoint()
	_check(final_saved, "A completed Nightmare permits a valid checkpoint: " + store.last_error)
	if not final_saved:
		get_tree().quit(1)
		return
	var saved_bytes: PackedByteArray = FileAccess.get_file_as_bytes(TEST_SAVE)
	_check(saved_bytes != initial_bytes, "The post-Nightmare checkpoint records the new world state")
	player.hunger = 0.1
	player.fatigue = 0.9
	player.last_sleep_day = -1
	player.last_collapse_day = -1
	for attempt: int in range(2):
		var loaded: bool = store.load_checkpoint()
		_check(loaded and _now() == start + 30 and is_equal_approx(player.hunger, 0.43)
			and is_equal_approx(player.fatigue, 0.5) and player.last_sleep_day == TimeComponentManager.current_day
			and player.last_collapse_day == TimeComponentManager.current_day
			and FileAccess.get_file_as_bytes(TEST_SAVE) == saved_bytes,
			"Continue %d restores the completed Nightmare once without rewriting the checkpoint: %s" % [attempt + 1, store.last_error])
	print("NightmareCheckpointRoundtripTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
