extends Node

## Isolated, deterministic regression for the actual Player/Nightmare return.
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const NIGHTMARE_SCENE: PackedScene = preload("res://scenes/nightmare_world/nightmare_world.tscn")

class RouteGate extends Node:
	var target_minute: int = -1
	var blocked: bool = false
	var calls: int = 0
	var clock_changed_while_blocked: bool = false
	func prepare_simulated_minute(_arrival_minute: int) -> bool:
		var now: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
		if blocked and now >= target_minute:
			calls += 1
			if now != target_minute:
				clock_changed_while_blocked = true
			return false
		return true

var failures: int = 0
var fixture: Node2D
var player: Player
var nightmare: NightmareWorld
var gate: RouteGate
var start_minute: int = 0
var simulated_events: int = 0
var collapse_events: Array[int] = []
var completions: Array[Dictionary] = []
var reentrant_calls: Array[bool] = []
var block_transaction_after: int = -1
var other_stage_finished: bool = false
var other_stage_result: Dictionary = {}
var finish_await_returned: bool = false

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _run() -> void:
	var data_root: String = OS.get_environment("XDG_DATA_HOME")
	_expect(data_root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(data_root.simplify_path().trim_suffix("/") + "/"), "Use an isolated data directory")
	TimeComponentManager.set_process(false)
	TimeComponentManager.simulated_minute_started.connect(_on_simulated_minute)
	TimeComponentManager.minute_changed.connect(_on_minute_changed)
	await _test_partial_wait("route")
	await _test_partial_wait("transaction")
	await _test_scene_pause_and_resume()
	await _test_replaced_scene_player()
	await _test_scene_changed_during_effects()
	await _test_scene_changed_during_completion()
	await _test_concurrent_transition()
	await _test_competing_staged_time()
	await _test_timeout_and_level()
	await _test_preexisting_pause()
	await _test_player_removed_before_return()
	await _test_awaitable_finish_contract()
	Inventory._bulk_transaction_in_progress = false
	TimeComponentManager.simulated_minute_started.disconnect(_on_simulated_minute)
	TimeComponentManager.minute_changed.disconnect(_on_minute_changed)
	print("NightmareReturnStagedRegression: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _setup(previous_pause: bool = false) -> void:
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 4
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	TimeComponentManager.emit_time_signal()
	fixture = Node2D.new()
	fixture.name = "NightmareTestScene"
	get_tree().root.add_child(fixture)
	get_tree().current_scene = fixture
	player = PLAYER_SCENE.instantiate() as Player
	fixture.add_child(player)
	nightmare = NIGHTMARE_SCENE.instantiate() as NightmareWorld
	fixture.add_child(nightmare)
	gate = RouteGate.new()
	add_child(gate)
	gate.add_to_group("staged_time_participants")
	await get_tree().process_frame
	player.debug_disable_player_needs = false
	player.debug_disable_fatigue = false
	player.hunger = 0.2
	player.fatigue = 0.8
	player.global_position = Vector2(20, 30)
	simulated_events = 0
	collapse_events.clear()
	completions.clear()
	reentrant_calls.clear()
	block_transaction_after = -1
	player.collapse_completed.connect(func(total: int) -> void: collapse_events.append(total))
	player.condition_changed.connect(func() -> void: reentrant_calls.append(player.apply_nightmare_consequences(2)))
	nightmare.nightmare_completed.connect(func(base: int, extra: int, total: int) -> void:
		completions.append({"base":base,"extra":extra,"total":total}))
	TimeComponentManager.is_paused = previous_pause
	_expect(nightmare.start_nightmare(player, 1), "Start the real Nightmare")
	nightmare.elapsed_seconds = 30.0
	start_minute = _now()
	gate.target_minute = start_minute + 8

func _wait_until(predicate: Callable, seconds: float = 10.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())

func _operation() -> Node:
	return SceneTransition.get_node_or_null("NightmareReturnOperation")

func _check_partial(label: String) -> void:
	_expect(_now() == start_minute + 8 and simulated_events == 8
		and is_equal_approx(player.hunger, 0.208) and is_equal_approx(player.fatigue, 0.8)
		and collapse_events.is_empty() and completions.is_empty()
		and not SceneTransition.continue_button.visible and not player.can_move,
		label + ": committed minutes remain eight, without fixed effects or premature completion")

func _check_full(label: String) -> void:
	_expect(_now() == start_minute + 30 and simulated_events == 30
		and is_equal_approx(player.hunger, 0.43) and is_equal_approx(player.fatigue, 0.5)
		and collapse_events == [30] and completions.is_empty() and reentrant_calls == [false],
		label + ": all 30 minutes and fixed effects commit exactly once before Continue")
	_expect(player.last_sleep_day == TimeComponentManager.current_day and player.last_collapse_day == TimeComponentManager.current_day,
		label + ": normal daily collapse and sleep latches are retained")

func _complete(label: String) -> void:
	var shown: bool = await _wait_until(func() -> bool: return SceneTransition.continue_button.visible)
	_expect(shown, label + ": Continue appears after the entire transaction")
	if not shown:
		return
	_check_full(label)
	SceneTransition.continue_button.pressed.emit()
	var done: bool = await _wait_until(func() -> bool: return not SceneTransition.is_transitioning and _operation() == null)
	_expect(done and completions.size() == 1 and int(completions[0].total) == 30
		and not TimeComponentManager.is_paused and player.can_move and not player.is_sleeping,
		label + ": world, movement and one completion are restored")
	await _dispose()

func _dispose() -> void:
	gate.remove_from_group("staged_time_participants")
	gate.queue_free()
	if is_instance_valid(fixture) and not fixture.is_queued_for_deletion():
		fixture.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _test_partial_wait(mode: String) -> void:
	await _setup()
	gate.blocked = mode == "route"
	block_transaction_after = gate.target_minute if mode == "transaction" else -1
	nightmare.finish_nightmare(false)
	var reached: bool = await _wait_until(func() -> bool:
		var op: Node = _operation()
		return is_instance_valid(op) and int(op.advanced_minutes) == 8, 15.0)
	_expect(reached, mode + ": a 600-frame wait returns the partial cursor for retry")
	if not reached:
		Inventory._bulk_transaction_in_progress = false
		gate.blocked = false
		return
	_check_partial(mode)
	_expect(not player.apply_nightmare_consequences(1) and not nightmare.start_nightmare(player, 1),
		mode + ": nested/repeated Nightmare requests are rejected")
	if mode == "route":
		_expect(gate.calls >= 600 and not gate.clock_changed_while_blocked, "Pending route does not consume an extra minute")
	gate.blocked = false
	Inventory._bulk_transaction_in_progress = false
	block_transaction_after = -1
	await _complete(mode)

func _test_scene_pause_and_resume() -> void:
	await _setup()
	gate.blocked = true
	nightmare.finish_nightmare(false)
	var blocked: bool = await _wait_until(func() -> bool: return gate.calls >= 3)
	_expect(blocked, "Scene switch fixture reaches the pending route after eight minutes")
	var other := Node2D.new()
	get_tree().root.add_child(other)
	get_tree().current_scene = other
	for _frame: int in range(12):
		await get_tree().process_frame
	var op: Node = _operation()
	_expect(is_instance_valid(op) and int(op.advanced_minutes) == 8 and _now() == start_minute + 8
		and is_equal_approx(player.fatigue, 0.8) and collapse_events.is_empty() and completions.is_empty(),
		"A temporary scene change keeps the eight-minute cursor and withholds fixed effects")
	get_tree().current_scene = fixture
	gate.blocked = false
	other.queue_free()
	await _complete("scene restored")

func _test_replaced_scene_player() -> void:
	await _setup()
	gate.blocked = true
	nightmare.finish_nightmare(false)
	var blocked: bool = await _wait_until(func() -> bool: return gate.calls >= 3)
	_expect(blocked, "Replacement fixture reaches the pending route after eight minutes")
	var old_fixture: Node2D = fixture
	var new_scene := Node2D.new()
	new_scene.name = "ReplacementScene"
	get_tree().root.add_child(new_scene)
	get_tree().current_scene = new_scene
	old_fixture.queue_free()
	for _frame: int in range(650):
		await get_tree().process_frame
	var op: Node = _operation()
	_expect(is_instance_valid(op) and int(op.advanced_minutes) == 8 and _now() == start_minute + 8
		and not SceneTransition.continue_button.visible and TimeComponentManager.is_paused and completions.is_empty(),
		"The transition owner preserves the partial cursor while no replacement Player exists")
	fixture = new_scene
	nightmare = NIGHTMARE_SCENE.instantiate() as NightmareWorld
	fixture.add_child(nightmare)
	nightmare.nightmare_completed.connect(func(base: int, extra: int, total: int) -> void:
		completions.append({"base":base,"extra":extra,"total":total}))
	player = PLAYER_SCENE.instantiate() as Player
	fixture.add_child(player)
	player.global_position = Vector2(123, 45)
	player.collapse_completed.connect(func(total: int) -> void: collapse_events.append(total))
	player.condition_changed.connect(func() -> void: reentrant_calls.append(player.apply_nightmare_consequences(2)))
	await get_tree().process_frame
	_expect(is_equal_approx(player.hunger, 0.208) and is_equal_approx(player.fatigue, 0.8),
		"The replacement Player inherits the already committed condition exactly once")
	gate.blocked = false
	var shown: bool = await _wait_until(func() -> bool: return SceneTransition.continue_button.visible)
	_expect(shown and player.global_position == Vector2(123, 45), "The replacement keeps its new-scene spawn position")
	if shown:
		_check_full("scene replaced")
		SceneTransition.continue_button.pressed.emit()
		var done: bool = await _wait_until(func() -> bool: return not SceneTransition.is_transitioning and _operation() == null)
		_expect(done and completions.size() == 1 and not TimeComponentManager.is_paused and player.can_move,
			"The replacement scene completes once and restores its own movement")
	await _dispose()


func _test_scene_changed_during_effects() -> void:
	await _setup()
	var old_fixture: Node2D = fixture
	var new_scene := Node2D.new()
	new_scene.name = "EffectSignalReplacementScene"
	get_tree().root.add_child(new_scene)
	var switched: Array[bool] = [false]
	player.condition_changed.connect(func() -> void:
		if not switched[0]:
			switched[0] = true
			get_tree().current_scene = new_scene
			old_fixture.queue_free())
	nightmare.finish_nightmare(false)
	var switched_in_time: bool = await _wait_until(func() -> bool: return switched[0])
	_expect(switched_in_time and _now() == start_minute + 30, "Condition callback changes scene only after all world minutes")
	for _frame: int in range(4):
		await get_tree().process_frame
	_expect(not SceneTransition.continue_button.visible and completions.is_empty(),
		"An effect callback changing scenes must wait for a live replacement before Continue")
	fixture = new_scene
	nightmare = NIGHTMARE_SCENE.instantiate() as NightmareWorld
	fixture.add_child(nightmare)
	nightmare.nightmare_completed.connect(func(base: int, extra: int, total: int) -> void:
		completions.append({"base":base,"extra":extra,"total":total}))
	player = PLAYER_SCENE.instantiate() as Player
	fixture.add_child(player)
	player.global_position = Vector2(123, 45)
	player.collapse_completed.connect(func(total: int) -> void: collapse_events.append(total))
	var clock_before_nested: int = _now()
	var hunger_before_nested: float = player.hunger
	var fatigue_before_nested: float = player.fatigue
	_expect(not player.apply_nightmare_consequences(1) and _now() == clock_before_nested
		and is_equal_approx(player.hunger, hunger_before_nested) and is_equal_approx(player.fatigue, fatigue_before_nested),
		"A replacement Player cannot reenter Nightmare consequences while the first return is still pending")
	await get_tree().process_frame
	var shown: bool = await _wait_until(func() -> bool: return SceneTransition.continue_button.visible)
	_expect(shown and player.global_position == Vector2(123, 45)
		and is_equal_approx(player.hunger, 0.43) and is_equal_approx(player.fatigue, 0.5)
		and collapse_events == [30] and reentrant_calls == [false],
		"The replacement inherits effects once and receives the deferred collapse completion")
	if shown:
		SceneTransition.continue_button.pressed.emit()
		var done: bool = await _wait_until(func() -> bool: return not SceneTransition.is_transitioning and _operation() == null)
		_expect(done and completions.size() == 1 and not TimeComponentManager.is_paused and player.can_move,
			"The effect-signal scene replacement completes once without stale locks")
	await _dispose()


func _test_scene_changed_during_completion() -> void:
	await _setup()
	var old_fixture: Node2D = fixture
	var new_scene := Node2D.new()
	new_scene.name = "CompletionSignalReplacementScene"
	get_tree().root.add_child(new_scene)
	var switched: Array[bool] = [false]
	player.collapse_completed.connect(func(_total: int) -> void:
		if not switched[0]:
			switched[0] = true
			get_tree().current_scene = new_scene
			old_fixture.queue_free())
	nightmare.finish_nightmare(false)
	var switched_in_time: bool = await _wait_until(func() -> bool: return switched[0])
	_expect(switched_in_time and _now() == start_minute + 30 and collapse_events == [30],
		"The completion callback changes scene after its one completion signal")
	for _frame: int in range(4):
		await get_tree().process_frame
	_expect(not SceneTransition.continue_button.visible and completions.is_empty(),
		"A completion callback changing scenes must wait for a live replacement before Continue")
	fixture = new_scene
	nightmare = NIGHTMARE_SCENE.instantiate() as NightmareWorld
	fixture.add_child(nightmare)
	nightmare.nightmare_completed.connect(func(base: int, extra: int, total: int) -> void:
		completions.append({"base":base,"extra":extra,"total":total}))
	player = PLAYER_SCENE.instantiate() as Player
	fixture.add_child(player)
	player.collapse_completed.connect(func(total: int) -> void: collapse_events.append(total))
	await get_tree().process_frame
	var shown: bool = await _wait_until(func() -> bool: return SceneTransition.continue_button.visible)
	_expect(shown and is_equal_approx(player.hunger, 0.43) and is_equal_approx(player.fatigue, 0.5)
		and collapse_events == [30] and reentrant_calls == [false],
		"Scene replacement after the completion signal neither reapplies effects nor emits a duplicate")
	if shown:
		SceneTransition.continue_button.pressed.emit()
		var done: bool = await _wait_until(func() -> bool: return not SceneTransition.is_transitioning and _operation() == null)
		_expect(done and completions.size() == 1 and not TimeComponentManager.is_paused and player.can_move,
			"Completion-signal scene replacement restores world and movement once")
	await _dispose()


func _test_concurrent_transition() -> void:
	await _setup()
	SceneTransition.run_with_fade(Callable(self, "_successful_transition"), 0.05, 0.3)
	_expect(SceneTransition.is_transitioning, "Independent transition starts before Nightmare return")
	nightmare.finish_nightmare(false)
	for _frame: int in range(10):
		await get_tree().process_frame
	_expect(_now() == start_minute and completions.is_empty() and collapse_events.is_empty()
		and not player.can_move and _operation() != null,
		"Nightmare waits for an existing transition without declaring completion")
	await _complete("concurrent transition")

func _successful_transition() -> bool:
	return true


func _test_competing_staged_time() -> void:
	await _setup()
	gate.target_minute = start_minute
	gate.blocked = true
	other_stage_finished = false
	other_stage_result.clear()
	var owner := Node.new()
	fixture.add_child(owner)
	_capture_competing_stage(owner)
	var waiting: bool = await _wait_until(func() -> bool: return gate.calls >= 3)
	_expect(waiting and TimeComponentManager.is_staged_advance_active(), "A different staged time owner is already active")
	nightmare.elapsed_seconds = 30.0 # Set after the wait so frame time cannot round the base to 31.
	nightmare.finish_nightmare(false)
	var score_shown: bool = await _wait_until(func() -> bool: return SceneTransition.scoreboard_panel.visible)
	for _frame: int in range(8):
		await get_tree().process_frame
	_expect(score_shown and not player.is_sleeping and _now() == start_minute
		and collapse_events.is_empty() and not SceneTransition.continue_button.visible,
		"Nightmare waits for the other staged owner before changing Player sleep state")
	gate.blocked = false
	var other_done: bool = await _wait_until(func() -> bool: return other_stage_finished)
	_expect(other_done and bool(other_stage_result.get("completed", false))
		and int(other_stage_result.get("advanced_minutes", 0)) == 3,
		"The existing owner completes its own three minutes")
	var shown: bool = await _wait_until(func() -> bool: return SceneTransition.continue_button.visible)
	print("COMPETING_STAGE_DIAG: shown=", shown, " elapsed=", _now() - start_minute,
		" events=", simulated_events, " hunger=", player.hunger, " fatigue=", player.fatigue,
		" collapse=", collapse_events, " completions=", completions, " other=", other_stage_result)
	_expect(shown and _now() == start_minute + 33 and simulated_events == 33
		and is_equal_approx(player.hunger, 0.433) and is_equal_approx(player.fatigue, 0.5015)
		and collapse_events == [30] and completions.is_empty(),
		"Only the subsequent 30 minutes use Nightmare sleep state and its effects apply once")
	if shown:
		SceneTransition.continue_button.pressed.emit()
		var done: bool = await _wait_until(func() -> bool: return not SceneTransition.is_transitioning and _operation() == null)
		print("COMPETING_STAGE_END: done=", done, " completions=", completions, " paused=", TimeComponentManager.is_paused)
		_expect(done and completions.size() == 1 and int(completions[0].total) == 30,
			"The concurrent staged owner cannot duplicate the Nightmare completion")
	await _dispose()

func _capture_competing_stage(owner: Node) -> void:
	other_stage_result = await TimeComponentManager.advance_minutes_staged(3, owner)
	other_stage_finished = true

func _test_timeout_and_level() -> void:
	await _setup()
	nightmare.collapse_tier = 5 # Test fixture selects the existing maximum tier.
	nightmare.elapsed_seconds = 60.0
	nightmare.finish_nightmare(true)
	var shown: bool = await _wait_until(func() -> bool: return SceneTransition.continue_button.visible)
	_expect(shown and _now() == start_minute + 150 and simulated_events == 150
		and is_equal_approx(player.hunger, 0.55) and is_equal_approx(player.fatigue, 0.5)
		and collapse_events == [150] and reentrant_calls == [false] and completions.is_empty(),
		"Maximum-tier timeout keeps 60 base, 60 tier and 30 timeout minutes and applies effects once")
	if shown:
		SceneTransition.continue_button.pressed.emit()
		var done: bool = await _wait_until(func() -> bool: return not SceneTransition.is_transitioning and _operation() == null)
		_expect(done and completions.size() == 1 and int(completions[0].base) == 60
			and int(completions[0].extra) == 90 and int(completions[0].total) == 150,
			"Timeout scoreboard completion retains the existing tier and penalty values")
	await _dispose()


func _test_preexisting_pause() -> void:
	await _setup(true)
	nightmare.elapsed_seconds = 1.0
	nightmare.finish_nightmare(false)
	var shown: bool = await _wait_until(func() -> bool: return SceneTransition.continue_button.visible)
	_expect(shown and _now() == start_minute + 1 and collapse_events == [1]
		and is_equal_approx(player.hunger, 0.401) and is_equal_approx(player.fatigue, 0.5),
		"One Nightmare minute and its effects still process when the world was already paused")
	if shown:
		SceneTransition.continue_button.pressed.emit()
		var done: bool = await _wait_until(func() -> bool: return not SceneTransition.is_transitioning and _operation() == null)
		_expect(done and TimeComponentManager.is_paused and player.can_move and completions.size() == 1,
			"The existing world pause remains owned by its original caller after Nightmare")
	TimeComponentManager.is_paused = false
	await _dispose()


func _test_player_removed_before_return() -> void:
	await _setup()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	player = PLAYER_SCENE.instantiate() as Player
	fixture.add_child(player)
	player.global_position = Vector2(123, 45)
	player.collapse_completed.connect(func(total: int) -> void: collapse_events.append(total))
	player.condition_changed.connect(func() -> void: reentrant_calls.append(player.apply_nightmare_consequences(2)))
	nightmare.elapsed_seconds = 30.0
	nightmare.finish_nightmare(false)
	var shown: bool = await _wait_until(func() -> bool: return SceneTransition.continue_button.visible)
	_expect(shown and player.global_position == Vector2(123, 45),
		"An invalid original Player is replaced safely without applying the old spawn")
	if shown:
		_check_full("player replaced before return")
		SceneTransition.continue_button.pressed.emit()
		var done: bool = await _wait_until(func() -> bool: return not SceneTransition.is_transitioning and _operation() == null)
		_expect(done and completions.size() == 1 and player.can_move and not TimeComponentManager.is_paused,
			"A replacement before return completes once without stale-object errors")
	await _dispose()


func _test_awaitable_finish_contract() -> void:
	await _setup()
	finish_await_returned = false
	_capture_awaited_finish()
	var shown: bool = await _wait_until(func() -> bool: return SceneTransition.continue_button.visible)
	_expect(shown and not finish_await_returned and completions.is_empty(),
		"Awaiting finish_nightmare remains pending until the result is continued")
	if shown:
		SceneTransition.continue_button.pressed.emit()
		var done: bool = await _wait_until(func() -> bool: return finish_await_returned and _operation() == null)
		_expect(done and completions.size() == 1 and not SceneTransition.is_transitioning,
			"Awaited finish resolves after the transition and the single completion signal")
	await _dispose()

func _capture_awaited_finish() -> void:
	await nightmare.finish_nightmare(false)
	_expect(_operation() == null, "The completed operation releases its global guard before an awaited caller resumes")
	finish_await_returned = true

func _on_simulated_minute(_minute: int) -> void:
	simulated_events += 1

func _on_minute_changed(_minute: int) -> void:
	if block_transaction_after >= 0 and _now() == block_transaction_after:
		Inventory._bulk_transaction_in_progress = true
		block_transaction_after = -1
