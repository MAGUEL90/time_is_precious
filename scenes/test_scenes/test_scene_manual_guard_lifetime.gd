extends Node

const WORKSHOP_PLOT_SCENE: PackedScene = preload("res://scenes/workshop_plot/workshop_plot.tscn")
const HOUSE_PLOT_SCENE: PackedScene = preload("res://scenes/citizen_house_plot/citizen_house_plot.tscn")
const MENU_SCENE: PackedScene = preload("res://scenes/ui/workshop_plot_ui/workshop_plot_ui.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const HOUSE_SCRIPT: Script = preload("res://scenes/citizen_house_plot/citizen_house_plot.gd")

var failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene = self
	_run.call_deferred()


func _run() -> void:
	get_tree().paused = false
	await _test_plot_boundaries(WORKSHOP_PLOT_SCENE, "manual_guard_lifetime_workshop", "_manual_clearing_guard", true)
	await _test_plot_boundaries(HOUSE_PLOT_SCENE, "manual_guard_lifetime_house", "_manual_house_work_guard", false)
	print("ManualGuardLifetimeTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _test_plot_boundaries(scene: PackedScene, identity: String, guard_name: String, test_context: bool) -> void:
	var plot: Node = scene.instantiate()
	plot.set("plot_id", identity)
	add_child(plot)
	plot.set_process(false)
	var player: Player = _new_player(plot)
	var menu: CanvasLayer = _new_menu(plot)
	plot.set("_menu_session_scene", self)
	await get_tree().process_frame
	_expect(get_tree().current_scene == self and is_instance_valid(plot.get("construction")),
		"The in-tree plot fixture owns a construction state and uses the test scene as its ancestor.")

	for freed_index: int in range(4):
		var construction: Node = plot.get("construction")
		var scene_ref: Node = self
		if freed_index == 2:
			scene_ref = Node.new()
		var construction_ref: Node = construction
		if freed_index == 3:
			construction_ref = Node.new()
		var refs: Array = [menu, player, scene_ref, construction_ref]
		var phase: String = "clearing" if test_context else "building"
		var guard_callable: Callable = Callable(plot, guard_name).bind(
			refs[0], refs[1], refs[2], refs[3], phase)
		var context_callable: Callable
		if test_context:
			context_callable = Callable(plot, "_manual_clearing_context_is_valid").bind(
				refs[0], refs[1], refs[2], refs[3])
		var finish_callable: Callable
		if freed_index < 3:
			finish_callable = Callable(plot, "_finish_manual_session").bind(refs[0], refs[1], refs[2])
		var freed_ref: Node = refs[freed_index] as Node
		freed_ref.free()
		_expect(not is_instance_valid(freed_ref), "Exactly one cached argument is freed before each guard call.")

		var before_guard: Dictionary = _state_snapshot(plot)
		var guard_result: Variant = guard_callable.call()
		_expect(typeof(guard_result) == TYPE_BOOL and not bool(guard_result),
			"%s returns false for a freed cached argument at index %d." % [guard_name, freed_index])
		_expect(_state_snapshot(plot) == before_guard,
			"%s does not mutate plot or pause state for a freed cached argument at index %d." % [guard_name, freed_index])

		if test_context:
			var before_context: Dictionary = _state_snapshot(plot)
			var context_result: Variant = context_callable.call()
			_expect(typeof(context_result) == TYPE_BOOL and not bool(context_result),
				"The workshop context check returns false for a freed cached argument at index %d." % freed_index)
			_expect(_state_snapshot(plot) == before_context,
				"The workshop context check does not mutate plot or pause state for a freed cached argument at index %d." % freed_index)

		if freed_index < 3:
			if freed_index == 0:
				# A different live owner makes finish return before touching session state.
				menu = _new_menu(plot)
				plot.set("_menu_session_menu", menu)
			var before_finish: Dictionary = _state_snapshot(plot)
			finish_callable.call()
			_expect(_state_snapshot(plot) == before_finish,
				"Finishing with a freed cached menu, player, or scene does not mutate plot or pause state at index %d." % freed_index)

		if freed_index == 1:
			player = _new_player(plot)
			plot.set("_menu_session_player", player)

	plot.set("menu", null)
	plot.set("player", null)
	plot.set("_menu_session_menu", null)
	plot.set("_menu_session_player", null)
	plot.set("_menu_session_scene", null)
	plot.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _new_player(plot: Node) -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	plot.set("player", player)
	plot.set("_menu_session_player", player)
	return player


func _new_menu(plot: Node) -> CanvasLayer:
	var menu: CanvasLayer = MENU_SCENE.instantiate() as CanvasLayer
	plot.add_child(menu)
	plot.set("menu", menu)
	plot.set("_menu_session_menu", menu)
	menu.closed.connect(Callable(plot, "_on_menu_closed").bind(menu))
	return menu


func _state_snapshot(plot: Node) -> Dictionary:
	var snapshot: Dictionary = {
		"manual_clearing": plot.get("_manual_clearing"),
		"previous_paused": plot.get("_previous_paused"),
		"menu_valid": is_instance_valid(plot.get("menu")),
		"player_valid": is_instance_valid(plot.get("player")),
		"session_menu_valid": is_instance_valid(plot.get("_menu_session_menu")),
		"session_player_valid": is_instance_valid(plot.get("_menu_session_player")),
		"session_scene_valid": is_instance_valid(plot.get("_menu_session_scene")),
		"tree_paused": get_tree().paused,
	}
	if plot.get_script() == HOUSE_SCRIPT:
		snapshot["manual_house_work"] = plot.get("_manual_house_work")
	return snapshot


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
