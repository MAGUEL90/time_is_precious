extends Node

const HOME_SCENE: PackedScene = preload("res://scenes/player_home_interior/player_home_interior.tscn")
const CONTENT_SCENE_PATH: String = "res://scenes/content_scene/content_scene.tscn"
const NIGHTMARE_SCENE: PackedScene = preload("res://scenes/nightmare_world/nightmare_world.tscn")

var failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	Input.action_release(&"move_right")
	_expect(not SceneTransition.is_transitioning, "Test starts without an active scene transition.")
	if SceneTransition.is_transitioning:
		_finish()
		return

	var home: Node = HOME_SCENE.instantiate()
	get_tree().root.add_child(home)
	get_tree().current_scene = home
	await get_tree().process_frame
	await get_tree().physics_frame
	var outgoing_player: Player = home.get_node("YSortWorld/Player") as Player
	var exit_door: Area2D = home.get_node("YSortWorld/ExitDoor") as Area2D
	var outgoing_player_id: int = outgoing_player.get_instance_id()
	var outgoing_origin: Vector2 = exit_door.global_position
	outgoing_player.global_position = outgoing_origin
	for _frame: int in range(3):
		await get_tree().physics_frame

	if not await _wait_until(
		func(): return SceneTransition.is_transitioning,
		"Actual Home ExitDoor starts its scene transition."
	):
		_finish()
		return

	Input.action_press(&"move_right")
	var outgoing_max_drift: float = 0.0
	var incoming_max_drift: float = 0.0
	var incoming_spawn_seen: bool = false
	var replacement_seen: bool = false
	var replacement_movement_blocked_seen: bool = false
	var replacement_movement_allowed_seen: bool = false
	var transition_deadline: int = Time.get_ticks_msec() + 10000
	while SceneTransition.is_transitioning and Time.get_ticks_msec() < transition_deadline:
		var active_player: Player = get_tree().get_first_node_in_group("player") as Player
		var active_scene: Node = get_tree().current_scene
		if is_instance_valid(active_player) and is_instance_valid(active_scene):
			if active_player.get_instance_id() == outgoing_player_id:
				outgoing_max_drift = maxf(
					outgoing_max_drift,
					active_player.global_position.distance_to(outgoing_origin)
				)
			else:
				replacement_seen = true
				if active_player.can_move:
					replacement_movement_allowed_seen = true
				else:
					replacement_movement_blocked_seen = true
				var spawn_point: Marker2D = active_scene.get_node_or_null(
					"YSortWorld/SpawnPoints/HomeEntryPoint"
				) as Marker2D
				if spawn_point != null:
					var spawn_distance: float = active_player.global_position.distance_to(
						spawn_point.global_position
					)
					if spawn_distance <= 4.0:
						incoming_spawn_seen = true
					if incoming_spawn_seen:
						incoming_max_drift = maxf(
							incoming_max_drift,
							spawn_distance
						)
		await get_tree().physics_frame
	Input.action_release(&"move_right")

	if SceneTransition.is_transitioning:
		_expect(false, "Home-to-Content fade completes within the test timeout.")
		_finish()
		return
	var loaded_scene: Node = get_tree().current_scene
	_expect(
		is_instance_valid(loaded_scene) and loaded_scene.scene_file_path == CONTENT_SCENE_PATH,
		"The real ExitDoor loads the Content scene."
	)
	_expect(replacement_seen, "The scene swap creates a replacement Player during the fade.")
	_expect(replacement_movement_blocked_seen, "The replacement Player reports movement blocked during the fade.")
	_expect(not replacement_movement_allowed_seen, "The replacement Player never reports movement allowed during the fade.")
	_expect(outgoing_max_drift <= 0.5, "The outgoing Player stays still during the Home exit fade.")
	_expect(incoming_spawn_seen, "The replacement Player reaches the authored HomeEntryPoint during the fade.")
	_expect(incoming_max_drift <= 0.5, "The replacement Player stays still after reaching HomeEntryPoint during the fade.")

	var player: Player = get_tree().get_first_node_in_group("player") as Player
	_expect(is_instance_valid(player) and player.get_instance_id() != outgoing_player_id,
		"Content owns a different Player after the scene change.")
	if not is_instance_valid(player):
		_finish()
		return
	_expect(player.can_move and not SceneTransition.is_transitioning,
		"Movement becomes available after the door fade finishes.")
	await _expect_movement(player, "Movement resumes after the Home-to-Content fade.")

	player.can_move = false
	var failed_transition_succeeded: bool = await SceneTransition.run_with_fade(
		Callable(self, "_fail_transition"),
		0.02,
		0.0
	)
	_expect(not failed_transition_succeeded, "The controlled transition callback reports failure.")
	_expect(not SceneTransition.is_transitioning and not player.can_move,
		"A failed transition leaves an independent can_move restriction in place.")
	player.can_move = true
	_expect(player.can_move, "The owner can still release the independent can_move restriction.")

	var nightmare: NightmareWorld = NIGHTMARE_SCENE.instantiate() as NightmareWorld
	nightmare.position = Vector2(3000, 3000)
	get_tree().current_scene.add_child(nightmare)
	player.total_collapse_count = 0
	player.collapse()
	if not await _wait_until(
		func(): return nightmare.is_active and SceneTransition.is_transitioning,
		"Player collapse enters an active Nightmare while the entry fade is still running."
	):
		_finish()
		return

	_expect(not player.can_move, "Collapse and the entry transition keep Player movement locked.")
	_expect(
		nightmare.exit_npc.global_position.distance_to(player.global_position) > 32.0,
		"Nightmare spawn is separated from ExitNPC, so entry cannot trigger an immediate escape."
	)
	var entry_elapsed: float = nightmare.elapsed_seconds
	for _frame: int in range(15):
		await get_tree().process_frame
	_expect(
		absf(nightmare.elapsed_seconds - entry_elapsed) <= 0.0001,
		"Nightmare elapsed time stays frozen while its entry transition is active."
	)
	_expect(
		nightmare.is_active and not SceneTransition.continue_button.visible,
		"The Nightmare exit callback does not complete the run during entry."
	)

	if not await _wait_until(
		func(): return not SceneTransition.is_transitioning and player.can_move,
		"Nightmare entry finishes and releases the collapse movement lock."
	):
		_finish()
		return
	var playable_elapsed: float = nightmare.elapsed_seconds
	for _frame: int in range(8):
		await get_tree().process_frame
	_expect(nightmare.elapsed_seconds > playable_elapsed,
		"Nightmare elapsed time advances after the entry fade ends.")

	var return_position: Vector2 = nightmare.return_position
	nightmare.exit_npc.body_entered.emit(player)
	if not await _wait_until(
		func(): return SceneTransition.continue_button.visible,
		"Normal Nightmare escape opens its result screen."
	):
		_finish()
		return
	_expect(not player.can_move, "The existing Nightmare return lock blocks movement at the result screen.")
	_expect(player.global_position == return_position,
		"Nightmare escape returns Player to the position saved at entry.")
	SceneTransition.continue_button.pressed.emit()
	if not await _wait_until(
		func():
			return not SceneTransition.is_transitioning and player.can_move and not TimeComponentManager.is_paused,
		"Nightmare return fade releases its lock and resumes world time."
	):
		_finish()
		return
	await _expect_movement(player, "Movement resumes after normal Nightmare escape and return.")
	_finish()

func _fail_transition() -> bool:
	return false

func _expect_movement(player: Player, message: String) -> void:
	var before: Vector2 = player.global_position
	Input.action_press(&"move_right")
	for _frame: int in range(12):
		await get_tree().physics_frame
	Input.action_release(&"move_right")
	_expect(player.global_position.distance_to(before) > 1.0, message)

func _wait_until(predicate: Callable, message: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 10000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var completed: bool = predicate.call()
	_expect(completed, message)
	return completed

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _finish() -> void:
	Input.action_release(&"move_right")
	print("SceneTransitionTimingTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)
