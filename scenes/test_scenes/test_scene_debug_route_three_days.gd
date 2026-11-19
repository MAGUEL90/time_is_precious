extends "res://scenes/test_scenes/test_scene_worker_route_budget.gd"

## Real +3d button with one reachable and one enclosed worker. The established
## retry-after-reopening problem is observed and reported, not treated as fixed.
func _run() -> void:
	var profile: String = OS.get_environment("APPDATA").replace("\\", "/").to_lower().trim_suffix("/")
	var user_path: String = ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower()
	_expect(not profile.is_empty() and user_path.begins_with(profile + "/"), "Use a separate APPDATA profile.")
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	TimeComponentManager.emit_time_signal()
	var content: Node = CONTENT.instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	for _frame: int in range(4):
		await get_tree().process_frame
	runtime = content.get_node("YSortWorld/WorkerRuntime")
	visuals = runtime.get_node("WorkerVisuals")
	visuals.set_process(false)
	state = content.get_node("YSortWorld/CitizenHousePlot").construction
	var player: Player = content.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	Inventory.add_item("shekel", 100)
	var trapped: WorkerData = _hire("route_3d_trapped")
	open_worker = _hire("route_3d_open")
	if trapped == null or open_worker == null:
		_finish()
		return
	blocked.clear()
	blocked.append(trapped)
	TimeComponentManager.current_day = 1
	TimeComponentManager.current_hour = 7
	TimeComponentManager.current_minute = 0
	TimeComponentManager.emit_time_signal()
	state.phase = "empty"
	state.changed.emit()
	Inventory.add_bulk_item({"wood_log": 4, "clay_lump": 8, "reed_bundle": 6})
	_expect(bool(state.start_build([trapped.worker_id, open_worker.worker_id] as Array[String]).get("success", false)), "Two fixture workers start the house.")
	for _frame: int in range(5):
		await get_tree().process_frame
	var target: Vector2 = state.worker_entry_position
	var origin: Vector2 = target + Vector2(-64, 0)
	navigation = NAV.new()
	fixture_geometry = Node2D.new()
	add_child(fixture_geometry)
	_add_collider(_wall(origin, Vector2(-16, -16), Vector2(16, -12)))
	_add_collider(_wall(origin, Vector2(-16, 12), Vector2(16, 16)))
	_add_collider(_wall(origin, Vector2(-16, -12), Vector2(-12, 12)))
	gate = _add_collider(_wall(origin, Vector2(12, -12), Vector2(16, 12)))
	_add_collider(_wall(Vector2(10000, 10000), Vector2.ZERO, Vector2(100, 100)))
	navigation.configure(fixture_geometry)
	runtime.worksite_navigation = navigation
	trapped.begin_physical_approach("plot", HOUSE_ID + ":building", HOUSE_ID, origin, target)
	open_worker.begin_physical_approach("plot", HOUSE_ID + ":building", HOUSE_ID, target + Vector2(0, 8), target)
	visuals.plot_presence.states.clear()
	_expect(TimeComponentManager.advance_minutes(2) and open_worker.physical_approach.get("arrived", false), "The reachable worker can arrive before the skip.")
	var debug: Node = content.get_node("TimeDebugOverlay")
	debug.set_process(false)
	debug._refresh_controls()
	_expect(debug.can_advance() and debug.step_buttons[2].text == "+3d" and not debug.step_buttons[2].disabled, "The real +3d control is available.")
	var before: int = _now()
	var started: int = Time.get_ticks_msec()
	debug.step_buttons[2].pressed.emit()
	var elapsed: int = Time.get_ticks_msec() - started
	var approach: Dictionary = trapped.physical_approach
	_expect(_now() - before == 4320, "Three calendar days actually advance with workers present.")
	_expect(not approach.get("arrived", false) and (approach.is_empty() or approach.get("position") == origin), "The enclosed worker does not falsely arrive or teleport.")
	await get_tree().process_frame
	print("DEBUG_ROUTE_3D minutes=", _now() - before, " elapsed_ms=", elapsed, " trapped_arrived=", approach.get("arrived", false), " phase=", state.phase)
	print("DebugRouteThreeDaysTest ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
