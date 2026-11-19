extends Node

## Exercises the actual map and Debug buttons using a disposable Godot profile.
const CONTENT := preload("res://scenes/content_scene/content_scene.tscn")
var failures: int = 0
var minute_events: int = 0
var day_events: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _click(button: Button) -> void:
	var scale_to_window: Vector2 = Vector2(get_window().size) / get_viewport().get_visible_rect().size
	var point: Vector2 = button.get_global_rect().get_center() * scale_to_window
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		get_viewport().push_input(event)
		await get_tree().process_frame

func _run() -> void:
	var profile: String = OS.get_environment("APPDATA").replace("\\", "/").to_lower().trim_suffix("/")
	var user_path: String = ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower()
	_expect(not profile.is_empty() and user_path.begins_with(profile + "/"), "Use a separate APPDATA profile for this test.")
	if failures > 0:
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	TimeComponentManager.seconds_per_minute = 1.0
	TimeComponentManager._timer = 0.0
	TimeComponentManager.emit_time_signal()
	var content: Node = CONTENT.instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	for _frame: int in range(4):
		await get_tree().process_frame
	var player: Player = content.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	player.can_move = true
	var debug: Node = content.get_node("TimeDebugOverlay")
	debug.set_process(false)
	debug.panel.show()
	debug._refresh_controls()
	for _frame: int in range(3):
		await get_tree().process_frame
	_expect(debug.can_advance(), "The real map allows debug time advancement.")
	_expect(debug.speed_buttons.size() == 3 and debug.step_buttons.size() == 3, "Exactly three speed and three skip buttons are shown.")
	var speed_labels: Array[String] = []
	var step_labels: Array[String] = []
	for button: Button in debug.speed_buttons:
		speed_labels.append(button.text)
	for button: Button in debug.step_buttons:
		step_labels.append(button.text)
	_expect(speed_labels == ["x1", "x10", "x25"] and step_labels == ["+3h", "+1d", "+3d"], "The requested button labels are present in order.")
	var viewport_rect := get_viewport().get_visible_rect()
	_expect(viewport_rect.encloses(debug.panel.get_global_rect()), "The Debug panel fits in the logical viewport.")
	for button: Button in debug.speed_buttons + debug.step_buttons:
		_expect(debug.panel.get_global_rect().encloses(button.get_global_rect()) and button.size.x >= button.get_combined_minimum_size().x,
			"The control fits without clipping: " + button.text)
	var capture: String = OS.get_environment("TIP_TIME_CAPTURE_DIR")
	if not capture.is_empty() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(capture)
		await RenderingServer.frame_post_draw
		_expect(get_viewport().get_texture().get_image().save_png(capture.path_join("debug-time-options.png")) == OK, "Debug panel screenshot saved.")
	TimeComponentManager.minute_changed.connect(func(_minute: int): minute_events += 1)
	TimeComponentManager.day_changed.connect(func(_day: int): day_events += 1)
	for item: Array in [[0, 1], [1, 10], [2, 25], [0, 1]]:
		debug.speed_buttons[int(item[0])].pressed.emit()
		TimeComponentManager._timer = 0.0
		var before: int = _now()
		minute_events = 0
		debug._process(1.0)
		TimeComponentManager._process(1.0)
		_expect(_now() - before == int(item[1]) and minute_events == int(item[1]) and debug.get_effective_speed() == int(item[1]),
			"Speed x%d advances exactly its number of normal minute events." % item[1])
	debug.speed_buttons[2].pressed.emit()
	debug._process(0.02)
	debug.speed_buttons[0].pressed.emit()
	var reset_before: int = _now()
	TimeComponentManager._timer = 0.0
	debug._process(1.0)
	TimeComponentManager._process(1.0)
	_expect(_now() - reset_before == 1 and is_zero_approx(debug._extra_minutes), "Reset to x1 discards fractional extra time.")
	debug.set_speed(60)
	_expect(debug.speed_multiplier == 1, "Removed x60 is no longer accepted.")
	var first_skip: bool = true
	for item: Array in [[0, 180], [1, 1440], [2, 4320], [0, 180], [2, 4320]]:
		var before: int = _now()
		var day_before: int = TimeComponentManager.current_day
		minute_events = 0
		day_events = 0
		var started: int = Time.get_ticks_msec()
		if first_skip and DisplayServer.get_name() != "headless":
			await _click(debug.step_buttons[int(item[0])])
			first_skip = false
		else:
			debug.step_buttons[int(item[0])].pressed.emit()
		var elapsed: int = Time.get_ticks_msec() - started
		var advanced: int = _now() - before
		print("DEBUG_SKIP requested=", item[1], " advanced=", advanced, " minute_events=", minute_events, " days=", day_events, " elapsed_ms=", elapsed)
		_expect(advanced == int(item[1]) and minute_events == int(item[1])
			and day_events == TimeComponentManager.current_day - day_before,
			"Repeated button skip advances the requested minutes and calendar signals: " + str(item[1]))
		await get_tree().process_frame
	get_tree().paused = true
	debug._refresh_controls()
	var paused_before: int = _now()
	for button: Button in debug.step_buttons:
		_expect(button.disabled, "A paused tree disables " + button.text)
		button.pressed.emit()
	debug._process(1.0)
	_expect(_now() == paused_before, "A paused game blocks every skip and acceleration.")
	get_tree().paused = false
	var raid: Node = WorkStateRuntime.get_node_or_null("CityRaid")
	_expect(is_instance_valid(raid), "The map has its normal raid state.")
	if is_instance_valid(raid):
		var previous_phase: String = raid.phase
		debug.set_speed(25)
		raid.phase = "attacking"
		debug._refresh_controls()
		var raid_before: int = _now()
		debug.step_buttons[2].pressed.emit()
		debug.set_speed(10)
		_expect(_now() == raid_before and debug.get_effective_speed() == 1 and debug.speed_multiplier == 25,
			"Raid blocks skips and speed changes, temporarily enforcing x1.")
		raid.phase = previous_phase
		_expect(debug.get_effective_speed() == 25, "After the raid the chosen speed is restored.")
		debug.set_speed(1)
	content.free()
	print("DebugTimeOptionsTest ", "PASSED" if failures == 0 else "FAILED %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
