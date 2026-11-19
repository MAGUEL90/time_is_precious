extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

class StagedParticipant:
	extends Node
	var pending_frames: int = 0
	var terminal_ready: bool = false
	var preparations: int = 0

	func prepare_simulated_minute(_arrival_minute: int) -> bool:
		preparations += 1
		if terminal_ready:
			return true
		if pending_frames > 0:
			pending_frames -= 1
			return false
		return true

class TestOwner:
	extends Node
	var may_continue: bool = true

	func can_continue() -> bool:
		return may_continue

signal stage_done
signal sleep_done

var failures: int = 0
var _stage_finished: bool = false
var _stage_result: Dictionary = {}
var _sleep_finished: bool = false
var _sleep_succeeded: bool = false
var _minute_events: int = 0
var _switch_scene_after_minute: int = -1
var _interrupt_sleep_after_minute: int = -1
var _sleep_to_interrupt: Player
var _alternate_scene: Node
var _sleep_completion_count: int = 0
var _sleep_completion_minutes: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	if not TimeComponentManager.simulated_minute_started.is_connected(_on_simulated_minute_started):
		TimeComponentManager.simulated_minute_started.connect(_on_simulated_minute_started)
	_set_clock(0)
	_alternate_scene = Node.new()
	_alternate_scene.name = "StagedTimeAlternateScene"
	get_tree().root.add_child(_alternate_scene)
	var participant := StagedParticipant.new()
	participant.name = "StagedParticipant"
	participant.add_to_group("staged_time_participants")
	add_child(participant)

	# Pending route preparation must hold the clock and transaction lock without
	# producing a simulated movement. Once ready, exactly one minute is committed.
	var owner := TestOwner.new()
	owner.name = "PendingRouteOwner"
	add_child(owner)
	participant.pending_frames = 50
	var before: int = _now()
	_minute_events = 0
	_start_stage(1, owner, Callable(owner, "can_continue"))
	await get_tree().process_frame
	_expect(_now() == before and _minute_events == 0, "Pending route preparation consumes no game time and emits no movement minute.")
	_expect(TimeComponentManager.is_dispatching_time() and not TimeComponentManager.advance_minutes(1), "The staged lock blocks synchronous clock advancement while it awaits a route.")
	participant.pending_frames = 0
	await _wait_for_stage()
	_expect(bool(_stage_result.get("completed", false)) and int(_stage_result.get("advanced_minutes", 0)) == 1, "A ready staged minute commits once.")
	_expect(_now() == before + 1 and _minute_events == 1, "The commit emits one standard simulated-minute movement.")
	owner.queue_free()
	await get_tree().process_frame

	# A terminal route result is ready to commit; it must not be treated as a
	# permanently pending search.
	var terminal_owner := TestOwner.new()
	add_child(terminal_owner)
	participant.terminal_ready = true
	before = _now()
	var terminal_result: Dictionary = await _run_stage_and_wait(1, terminal_owner, Callable(terminal_owner, "can_continue"))
	_expect(bool(terminal_result.get("completed", false)) and int(terminal_result.get("advanced_minutes", 0)) == 1 and _now() == before + 1, "A terminal route state does not hold staged time indefinitely.")
	terminal_owner.queue_free()
	participant.terminal_ready = false
	await get_tree().process_frame
	var invalid_guard_owner := TestOwner.new()
	add_child(invalid_guard_owner)
	var invalid_guard_result: Dictionary = await _run_stage_and_wait(1, invalid_guard_owner, Callable(invalid_guard_owner, "missing_guard_method"))
	_expect(invalid_guard_result.get("reason") == "invalid_guard" and int(invalid_guard_result.get("advanced_minutes", 0)) == 0, "An invalid non-empty guard is rejected without consuming time.")
	invalid_guard_owner.queue_free()

	# Owner destruction and scene changes cancel before another minute can commit.
	var doomed_owner := TestOwner.new()
	add_child(doomed_owner)
	participant.pending_frames = 500
	before = _now()
	_start_stage(4, doomed_owner, Callable(doomed_owner, "can_continue"))
	await get_tree().process_frame
	doomed_owner.queue_free()
	await _wait_for_stage()
	_expect(_stage_result.get("reason") == "owner_invalid" and int(_stage_result.get("advanced_minutes", 0)) == 0 and _now() == before, "A queued owner is rejected before an extra minute commits.")

	var scene_owner := TestOwner.new()
	add_child(scene_owner)
	participant.pending_frames = 500
	before = _now()
	_start_stage(4, scene_owner, Callable(scene_owner, "can_continue"))
	await get_tree().process_frame
	get_tree().current_scene = _alternate_scene
	await _wait_for_stage()
	_expect(_stage_result.get("reason") == "scene_changed" and int(_stage_result.get("advanced_minutes", 0)) == 0 and _now() == before, "A scene change cancels a waiting stage without consuming time.")
	get_tree().current_scene = self
	scene_owner.queue_free()
	participant.pending_frames = 0
	await get_tree().process_frame

	# A normal sleep completes and applies recovery for the requested duration.
	_set_clock(0)
	var full_sleep: Player = PLAYER_SCENE.instantiate()
	add_child(full_sleep)
	full_sleep.sleep_duration_minutes = 8
	full_sleep.fatigue = 0.8
	full_sleep.hunger = 0.0
	full_sleep.fatigue_increase_per_min = 0.0
	full_sleep.sleep_completed.connect(_on_sleep_completed)
	var full_before: float = full_sleep.fatigue
	var full_sleep_ok: bool = await full_sleep.sleep_for_minutes_staged(8)
	_expect(full_sleep_ok and int(full_sleep.last_staged_sleep_result.get("advanced_minutes", 0)) == 8, "An uninterrupted staged sleep completes its full interval.")
	_expect(is_equal_approx(full_before - full_sleep.fatigue, full_sleep.sleep_fatigue_recovery) and _sleep_completion_minutes == 8, "Full sleep applies the existing recovery amount and emits one completion.")
	var zero_before: float = full_sleep.fatigue
	var completion_before: int = _sleep_completion_count
	_expect(not await full_sleep.sleep_for_minutes_staged(0), "A zero-minute sleep is rejected.")
	_expect(is_equal_approx(full_sleep.fatigue, zero_before) and _sleep_completion_count == completion_before, "Zero minutes produce no recovery or completion event.")

	# Eight successful minutes form one partial sleep when its scene changes at
	# the frame-yield boundary of a longer request.
	_set_clock(0)
	TimeComponentManager.current_day = 1
	TimeComponentManager.emit_time_signal()
	var partial_sleep: Player = PLAYER_SCENE.instantiate()
	add_child(partial_sleep)
	partial_sleep.sleep_duration_minutes = 16
	partial_sleep.fatigue = 0.8
	partial_sleep.hunger = 0.0
	partial_sleep.fatigue_increase_per_min = 0.0
	partial_sleep.sleep_completed.connect(_on_sleep_completed)
	_sleep_completion_count = 0
	_interrupt_sleep_after_minute = 8
	_sleep_to_interrupt = partial_sleep
	_minute_events = 0
	_sleep_finished = false
	_capture_sleep(partial_sleep, 16)
	await _wait_for_sleep()
	_interrupt_sleep_after_minute = -1
	_sleep_to_interrupt = null
	var partial_minutes: int = int(partial_sleep.last_staged_sleep_result.get("advanced_minutes", 0))
	_expect(not _sleep_succeeded and partial_minutes == 8 and _now() == 1 * 1440 + 10 * 60 + 8, "Interrupted sleep reports only the eight minutes actually advanced.")
	_expect(is_equal_approx(0.8 - partial_sleep.fatigue, partial_sleep.sleep_fatigue_recovery * 0.5) and _sleep_completion_count == 1 and _sleep_completion_minutes == 8, "Partial sleep applies proportional recovery and emits exactly one partial completion.")
	_expect(partial_sleep.last_sleep_day == 1 and not partial_sleep.is_sleeping and partial_sleep.can_move, "A partial sleep records its day and returns the player to awake, movable state.")

	# A scene change after committed minutes reports the actual amount but has no
	# stale-scene recovery/completion effects and releases only the old player's lock.
	_set_clock(0)
	TimeComponentManager.current_day = 2
	TimeComponentManager.emit_time_signal()
	var cancelled_sleep: Player = PLAYER_SCENE.instantiate()
	add_child(cancelled_sleep)
	cancelled_sleep.sleep_duration_minutes = 16
	cancelled_sleep.fatigue = 0.8
	cancelled_sleep.hunger = 0.0
	cancelled_sleep.fatigue_increase_per_min = 0.0
	cancelled_sleep.sleep_completed.connect(_on_sleep_completed)
	var cancelled_fatigue: float = cancelled_sleep.fatigue
	_sleep_completion_count = 0
	_switch_scene_after_minute = 8
	_minute_events = 0
	_sleep_finished = false
	_capture_sleep(cancelled_sleep, 16)
	await _wait_for_sleep()
	_switch_scene_after_minute = -1
	var cancelled_minutes: int = int(cancelled_sleep.last_staged_sleep_result.get("advanced_minutes", 0))
	_expect(not _sleep_succeeded and cancelled_minutes == 8 and _now() == 2 * 1440 + 10 * 60 + 8, "Scene-change cancellation still reports minutes already committed.")
	_expect(is_equal_approx(cancelled_sleep.fatigue, cancelled_fatigue) and _sleep_completion_count == 0, "A stale-scene sleep does not recover fatigue or emit completion callbacks.")
	_expect(not cancelled_sleep.is_sleeping and cancelled_sleep.can_move, "The surviving old player clears only its own sleep state and lock after scene cancellation.")
	get_tree().current_scene = self

	# A condition listener may queue-free the player; no completion signal or
	# stale self-access should follow that callback.
	_set_clock(0)
	TimeComponentManager.current_day = 3
	TimeComponentManager.emit_time_signal()
	var callback_sleep: Player = PLAYER_SCENE.instantiate()
	add_child(callback_sleep)
	callback_sleep.sleep_duration_minutes = 8
	callback_sleep.fatigue = 0.8
	callback_sleep.hunger = 0.0
	callback_sleep.fatigue_increase_per_min = 0.0
	callback_sleep.sleep_completed.connect(_on_sleep_completed)
	callback_sleep.condition_changed.connect(_queue_free_on_condition.bind(callback_sleep))
	_sleep_completion_count = 0
	var callback_sleep_result: bool = await callback_sleep.sleep_for_minutes_staged(8)
	_expect(callback_sleep_result and callback_sleep.is_queued_for_deletion() and _sleep_completion_count == 0, "A player freed by condition_changed receives no later sleep_completed callback.")

	partial_sleep.queue_free()
	cancelled_sleep.queue_free()
	full_sleep.queue_free()
	participant.queue_free()
	await get_tree().process_frame
	if TimeComponentManager.simulated_minute_started.is_connected(_on_simulated_minute_started):
		TimeComponentManager.simulated_minute_started.disconnect(_on_simulated_minute_started)
	_alternate_scene.queue_free()
	print("StagedTimeProgressionTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _start_stage(total_minutes: int, owner: Node, guard: Callable) -> void:
	_stage_finished = false
	_stage_result.clear()
	_capture_stage(total_minutes, owner, guard)

func _capture_stage(total_minutes: int, owner: Node, guard: Callable) -> void:
	_stage_result = await TimeComponentManager.advance_minutes_staged(total_minutes, owner, guard)
	_stage_finished = true
	stage_done.emit()

func _run_stage_and_wait(total_minutes: int, owner: Node, guard: Callable) -> Dictionary:
	_start_stage(total_minutes, owner, guard)
	await _wait_for_stage()
	return _stage_result

func _wait_for_stage() -> void:
	var frames: int = 0
	while not _stage_finished and frames < 700:
		frames += 1
		await get_tree().process_frame
	_expect(_stage_finished, "A staged clock operation completes within its bounded test window.")

func _capture_sleep(player: Player, duration_minutes: int) -> void:
	_sleep_succeeded = await player.sleep_for_minutes_staged(duration_minutes)
	_sleep_finished = true
	sleep_done.emit()

func _wait_for_sleep() -> void:
	var frames: int = 0
	while not _sleep_finished and frames < 300:
		frames += 1
		await get_tree().process_frame
	_expect(_sleep_finished, "Staged sleep exits after completion or cancellation.")

func _on_simulated_minute_started(_arrival_minute: int) -> void:
	_minute_events += 1
	if _interrupt_sleep_after_minute > 0 and _minute_events == _interrupt_sleep_after_minute and is_instance_valid(_sleep_to_interrupt):
		_sleep_to_interrupt.is_sleeping = false
	if _switch_scene_after_minute > 0 and _minute_events == _switch_scene_after_minute:
		get_tree().current_scene = _alternate_scene

func _on_sleep_completed(duration_minutes: int, _recovery_quality: float) -> void:
	_sleep_completion_count += 1
	_sleep_completion_minutes = duration_minutes

func _queue_free_on_condition(player: Player) -> void:
	player.queue_free()

func _set_clock(minute: int) -> void:
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = minute
	TimeComponentManager._timer = 0.0
	TimeComponentManager.emit_time_signal()

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
