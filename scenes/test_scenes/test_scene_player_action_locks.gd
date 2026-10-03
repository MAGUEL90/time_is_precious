extends Node

const FIXTURE: PackedScene = preload("res://scenes/test_scenes/test_scene_feature_consumable-fatigue/test_scene_consumable.tscn")

var failures: int = 0
var player: Player
var nightmare: NightmareWorld

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	TimeComponentManager.set_process(false)
	var fixture: Node = FIXTURE.instantiate()
	add_child(fixture)
	player = fixture.get_node("WorldObjects/Player") as Player
	nightmare = fixture.get_node("NightmareWorld") as NightmareWorld
	player.debug_disable_player_needs = false
	player.debug_disable_fatigue = false
	await get_tree().process_frame
	await _existing_owner_survives_actions()

	for scenario: String in ["pickup", "dialogue", "normal"]:
		player.hunger = 0.0
		player.fatigue = 0.89975
		player.focus = 1.0
		TimeComponentManager.is_paused = false
		if scenario == "pickup":
			var pickup: Node2D = fixture.get_node("WorldObjects/Pickups/PickupItem4") as Node2D
			player.global_position = pickup.global_position + Vector2(0, 2)
			for _frame: int in range(4):
				await get_tree().physics_frame
			Inventory.items.clear()
			_press_interact()
			_expect(Inventory.items.get("roasted_drumstick", 0) == 1, "Actual interaction collects the pickup.")
			_expect(not player.can_move and player.player_visual.current_action == "pickup", "Pickup owns its temporary movement restriction.")
		elif scenario == "dialogue":
			TimeComponentManager.is_paused = true
			BaseDialogueManager.dialogue_activated.emit()

		TimeComponentManager.advance_minutes(1)
		_expect(player.is_collapsing and not player.can_move, "%s: critical minute starts collapse." % scenario)
		if scenario == "dialogue":
			BaseDialogueManager.dialogue_deactivated.emit()
			_expect(not player.can_move, "Dialogue completion cannot release the ongoing collapse lock.")
		if scenario == "pickup":
			var visual: PlayerVisual = player.player_visual
			var duration: float = visual._get_animation_duration(visual.body_sprite, "%s_pickup_right" % visual.body_id)
			await get_tree().create_timer(duration + 0.05).timeout
			_expect(player.is_collapsing and not player.can_move, "Pickup completion cannot release the ongoing collapse lock.")
			if not SceneTransition.is_transitioning:
				_expect(visual.current_action == "faint" and visual.is_action_locked, "A completed pickup timer cannot replace the faint animation.")

		if not await _wait_until(func(): return nightmare.is_active and not player.is_collapsing and not SceneTransition.is_transitioning, "%s: Nightmare entry completes." % scenario):
			_finish()
			return
		_expect(player.can_move, "%s: entry releases only completed actions." % scenario)
		await _expect_movement("%s: movement works inside Nightmare." % scenario)

		if scenario == "pickup":
			nightmare.elapsed_seconds = nightmare.max_duration_seconds
		else:
			nightmare.exit_npc.body_entered.emit(player)
		if not await _wait_until(func(): return SceneTransition.continue_button.visible, "%s: return scoreboard opens." % scenario):
			_finish()
			return
		_expect(not player.can_move, "%s: return transition still blocks movement." % scenario)
		SceneTransition.continue_button.pressed.emit()
		if not await _wait_until(func(): return not SceneTransition.is_transitioning, "%s: return fade completes." % scenario):
			_finish()
			return
		_expect(not nightmare.is_active and not TimeComponentManager.is_paused and player.can_move, "%s: world time and movement are restored." % scenario)
		await _expect_movement("%s: movement works after returning to the world." % scenario)

	fixture.free()
	_finish()

func _existing_owner_survives_actions() -> void:
	player.can_move = false
	await player._play_pickup_action()
	_expect(not player.can_move, "Pickup cannot clear an existing external movement restriction.")
	TimeComponentManager.is_paused = true
	BaseDialogueManager.dialogue_activated.emit()
	player.can_move = true
	_expect(not player.can_move, "An external release cannot bypass an active dialogue restriction.")
	player.can_move = false
	BaseDialogueManager.dialogue_deactivated.emit()
	_expect(not player.can_move, "Dialogue cannot clear an existing external movement restriction.")
	player.last_sleep_day = -1
	_expect(player.sleep_for_minutes(1), "A short sleep runs for the ownership regression.")
	_expect(not player.can_move, "Sleep cannot clear an existing external movement restriction.")
	player.can_move = true
	_expect(player.can_move, "The original owner can release its own restriction.")

func _press_interact() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventAction.new()
	event.action = "interact"
	get_viewport().push_input(event)

func _expect_movement(message: String) -> void:
	var before: Vector2 = player.global_position
	Input.action_press("move_right")
	for _frame: int in range(12):
		await get_tree().physics_frame
	Input.action_release("move_right")
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
	Input.action_release("move_right")
	print("PlayerActionLocksTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)
