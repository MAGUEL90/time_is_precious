extends Node

var failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var content: Node = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	var player: Player = content.get_node("YSortWorld/Player") as Player
	var plot = content.get_node("YSortWorld/WorkshopPlot")
	content.get_node("TimeDebugOverlay").set_player_guard(false)
	content.get_node("TimeDebugOverlay").set_process(false)
	# The authoring map has no Nightmare. Supply the existing component in this fixture.
	var nightmare: NightmareWorld = load("res://scenes/nightmare_world/nightmare_world.tscn").instantiate() as NightmareWorld
	nightmare.position = Vector2(3000, 3000)
	content.add_child(nightmare)
	player.global_position = plot.get_node("InteractableComponent").global_position + Vector2(0, 4)
	for _frame: int in range(3):
		await get_tree().physics_frame
	await get_tree().process_frame
	player.fatigue = 0.89975
	player.hunger = 0.0
	player.focus = 1.0
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventAction.new()
	event.action = "interact"
	get_viewport().push_input(event)
	_expect(is_instance_valid(plot.menu) and get_tree().paused and not player.can_move,
		"Actual E interaction opens the plot menu and owns its movement restriction.")
	if not is_instance_valid(plot.menu):
		_finish()
		return
	plot.menu.clearing_requested.emit([] as Array[String], true)
	if not await _wait_until(func(): return player.is_collapsing and not plot._manual_clearing,
		"The first critical work minute interrupts manual clearing and closes its modal."):
		_finish()
		return
	_expect(not is_instance_valid(plot.menu) and not get_tree().paused and not player.can_move,
		"Closing the plot releases its modal while collapse still owns movement.")
	_expect(plot.construction.phase == "uncleared", "Interrupted clearing preserves its existing incomplete phase.")
	if not await _wait_until(func(): return nightmare.is_active and not player.is_collapsing and not SceneTransition.is_transitioning,
		"Nightmare entry finishes after plot clearing is interrupted."):
		_finish()
		return
	_expect(player.can_move, "The finished plot restriction does not strand the player in Nightmare.")
	nightmare.exit_npc.body_entered.emit(player)
	if not await _wait_until(func(): return SceneTransition.continue_button.visible, "Nightmare escape offers Continue."):
		_finish()
		return
	SceneTransition.continue_button.pressed.emit()
	await _wait_until(func(): return not SceneTransition.is_transitioning, "Nightmare return completes.")
	_expect(player.can_move and not TimeComponentManager.is_paused and not get_tree().paused,
		"World movement and time are restored after interrupted plot clearing and Nightmare.")
	content.free()
	_finish()

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
	print("PlotCollapseHandoffTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)
