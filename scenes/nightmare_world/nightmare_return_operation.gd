extends Node

signal finished

## One transient return transaction. It is a child of the existing transition
## autoload, so its committed-minute cursor survives a scene-local Player swap.
## No checkpoint schema or on-disk save is changed.
var advanced_minutes: int = 0
var _total_minutes: int = 0
var _base_minutes: int = 0
var _extra_minutes: int = 0
var _return_position: Vector2
var _previous_time_paused: bool = false
var _scoreboard: String = ""
var _scoreboard_duration: float = 4.0
var _world_ref: WeakRef
var _player_ref: WeakRef
var _starting_player_ref: WeakRef
var _sleep_owner_id: int = 0
var _effects_committed: bool = false

func begin(world: Node, player: Player, position: Vector2, previous_pause: bool,
		base: int, extra: int, total: int, scoreboard: String, duration: float) -> void:
	_world_ref = weakref(world)
	_player_ref = weakref(player) if is_instance_valid(player) else null
	_starting_player_ref = weakref(player) if is_instance_valid(player) else null
	_return_position = position
	_previous_time_paused = previous_pause
	_base_minutes = base
	_extra_minutes = extra
	_total_minutes = total
	_scoreboard = scoreboard
	_scoreboard_duration = duration
	if is_instance_valid(player):
		player.set_movement_locked(&"nightmare_return", true)
	else:
		# Lock an already available replacement without applying the old spawn.
		var scene: Node = get_tree().current_scene
		for node: Node in get_tree().get_nodes_in_group("player"):
			var candidate: Player = node as Player
			if _player_belongs_to_scene(candidate, scene):
				_player_ref = weakref(candidate)
				candidate.set_movement_locked(&"nightmare_return", true)
				break
	_run.call_deferred()


func _run() -> void:
	# A forced exit during an existing fade must wait for its owner, not claim
	# success when run_with_fade refuses a concurrent transition.
	while SceneTransition.is_transitioning:
		TimeComponentManager.is_paused = true
		await get_tree().process_frame
	var succeeded: bool = await SceneTransition.run_with_fade(
		Callable(self, "_return_to_world"), 0.35, _scoreboard_duration, _scoreboard, true)
	TimeComponentManager.is_paused = _previous_time_paused
	var player: Player = _player_ref.get_ref() as Player if _player_ref != null else null
	if is_instance_valid(player) and not player.is_queued_for_deletion():
		if _sleep_owner_id == player.get_instance_id():
			player.is_sleeping = false
		player.set_movement_locked(&"nightmare_return", false)
	var world: Node = _current_nightmare_world()
	if world != null:
		world.nightmare_active_changed.emit(false)
		# The visibility signal can remove or replace its emitting scene.
		world = _current_nightmare_world()
		if world != null and succeeded and _effects_committed:
			world.nightmare_completed.emit(_base_minutes, _extra_minutes, _total_minutes)
	# Drop the global operation guard before resuming a caller awaiting finish.
	# The queued node stays alive long enough to emit its final signal.
	get_parent().remove_child(self)
	queue_free()
	finished.emit()


func _return_to_world() -> bool:
	var world: Node = _world_ref.get_ref() as Node if _world_ref != null else null
	if is_instance_valid(world) and is_instance_valid(world.nightmare_ui):
		world.nightmare_ui.hide()
	var player: Player = await _wait_for_player()
	if player == null:
		return _fail_return()
	# An actual scene replacement creates a different Player at its own spawn;
	# never apply the old scene's coordinates to that replacement.
	var starting_player: Player = _starting_player_ref.get_ref() as Player if _starting_player_ref != null else null
	if player == starting_player:
		player.global_position = _return_position

	while advanced_minutes < _total_minutes:
		player = await _wait_for_player()
		if player == null:
			return _fail_return()
		var remaining: int = _total_minutes - advanced_minutes
		var result: Dictionary = await TimeComponentManager.advance_minutes_staged(
			remaining, self, Callable(self, "_can_continue"))
		var committed: int = int(result.get("advanced_minutes", 0))
		if committed < 0 or committed > remaining:
			return _fail_return()
		advanced_minutes += committed
		if advanced_minutes >= _total_minutes:
			break
		var reason: String = str(result.get("reason", ""))
		if reason not in ["time_busy", "transaction_wait_limit", "route_wait_limit", "scene_changed", "guard_invalidated"]:
			return _fail_return()
		# Even after a wait limit, retain the committed cursor and retry only the
		# outstanding minutes. Retry wait limits immediately so another action
		# cannot advance the clock in an unlocked gap between attempts.
		if reason in ["time_busy", "scene_changed", "guard_invalidated"]:
			await get_tree().process_frame

	# A scene or Player can change on the final minute itself. Resolve the live
	# Player again before applying the fixed consequences or emitting signals.
	player = await _wait_for_player()
	if player == null or _effects_committed:
		return _fail_return()
	_effects_committed = true
	var effect_result: int = player._complete_nightmare_consequences(_total_minutes)
	if effect_result == 0:
		_effects_committed = false
		return _fail_return()
	_sleep_owner_id = 0
	# condition_changed or collapse_completed can synchronously replace the
	# scene. Never expose Continue until a valid current Player is available.
	# Only the completion signal is deferred; costs are never applied again.
	player = await _wait_for_player(false)
	if player == null:
		return _fail_return()
	if effect_result == 1:
		if not player._emit_deferred_nightmare_completion(_total_minutes):
			return _fail_return()
		player = await _wait_for_player(false)
		if player == null:
			return _fail_return()
	return true


func _wait_for_player(for_advancement: bool = true) -> Player:
	while is_inside_tree() and not is_queued_for_deletion():
		# The Nightmare owns this pause until its transition has completed.
		TimeComponentManager.is_paused = true
		# Do not bind the Player while an independent staged transaction still
		# owns the clock: its minutes must retain their original effects.
		if TimeComponentManager.is_dispatching_time():
			await get_tree().process_frame
			continue
		var scene: Node = get_tree().current_scene
		var previous: Player = _player_ref.get_ref() as Player if _player_ref != null else null
		if is_instance_valid(scene) and not scene.is_queued_for_deletion():
			if _player_belongs_to_scene(previous, scene):
				if _take_player(previous, for_advancement):
					return previous
			elif not is_instance_valid(previous) or not previous.is_inside_tree() or previous.is_queued_for_deletion():
				# Rebind only after the former Player has left; PlayerRuntimeState
				# transfers its condition to the newly created scene-local Player.
				for node: Node in get_tree().get_nodes_in_group("player"):
					var candidate: Player = node as Player
					if _player_belongs_to_scene(candidate, scene) and _take_player(candidate, for_advancement):
						return candidate
		await get_tree().process_frame
	return null


func _take_player(player: Player, for_advancement: bool) -> bool:
	if player.is_sleeping and _sleep_owner_id != player.get_instance_id():
		return false
	var previous: Player = _player_ref.get_ref() as Player if _player_ref != null else null
	if is_instance_valid(previous) and previous != player and not previous.is_queued_for_deletion():
		if _sleep_owner_id == previous.get_instance_id():
			previous.is_sleeping = false
		previous.set_movement_locked(&"nightmare_return", false)
	_player_ref = weakref(player)
	player.set_movement_locked(&"nightmare_return", true)
	if for_advancement:
		player.is_sleeping = true
		_sleep_owner_id = player.get_instance_id()
	else:
		_sleep_owner_id = 0
	return true


func _can_continue() -> bool:
	var scene: Node = get_tree().current_scene
	var player: Player = _player_ref.get_ref() as Player if _player_ref != null else null
	return _player_belongs_to_scene(player, scene) and player.is_sleeping \
		and player.get_instance_id() == _sleep_owner_id


func _player_belongs_to_scene(player: Player, scene: Node) -> bool:
	return is_instance_valid(scene) and not scene.is_queued_for_deletion() \
		and is_instance_valid(player) and player.is_inside_tree() \
		and not player.is_queued_for_deletion() and scene.is_ancestor_of(player)


func _current_nightmare_world() -> Node:
	var scene: Node = get_tree().current_scene
	var world: Node = _world_ref.get_ref() as Node if _world_ref != null else null
	var player: Player = _player_ref.get_ref() as Player if _player_ref != null else null
	if is_instance_valid(world) and _player_belongs_to_scene(player, scene) \
			and scene.is_ancestor_of(world) and not world.is_queued_for_deletion():
		return world
	if is_instance_valid(scene):
		for candidate: Node in get_tree().get_nodes_in_group("nightmare_world"):
			if is_instance_valid(candidate) and not candidate.is_queued_for_deletion() and scene.is_ancestor_of(candidate):
				return candidate
	return null


func _fail_return() -> bool:
	# The shared transition shows Continue even when its action fails. Make an
	# incomplete result explicit and never publish nightmare_completed.
	if is_instance_valid(SceneTransition.scoreboard_label):
		SceneTransition.scoreboard_label.text = "NIGHTMARE INTERRUPTED\nWorld time was not fully applied."
	return false
