extends Node

const CONTENT = preload("res://scenes/content_scene/content_scene.tscn")
const COMPLETION_SPLASH: Script = preload("res://scenes/workshop_plot/construction_complete_splash.gd")
var failures: int = 0
var player: Player
var content: Node
var observed_worker: WorkerData
var observed_construction: Node
var eligible_minutes: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.environment.color = Color.WHITE
	content = CONTENT.instantiate()
	# Explicit time jumps simulate travel only for the active gameplay owner.
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	player = content.get_node("YSortWorld/Player")
	# This fixture tests multi-day debug/construction and depth, not player collapse.
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	var debug = content.get_node("TimeDebugOverlay")
	debug.set_process(false)
	player.can_move = false
	player.player_visual.hide()
	var image := Image.create(16, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color.MAGENTA)
	var probe := Sprite2D.new()
	probe.texture = ImageTexture.create_from_image(image)
	probe.position = Vector2(0, -12)
	player.add_child(probe)
	var plot = content.get_node("YSortWorld/WorkshopPlot")
	var second_plot = content.get_node("YSortWorld/WorkshopPlot2")
	var board: Sprite2D = second_plot.get_node("Board")
	var keeper: Node2D = plot.get_node("Craftsman")
	var wall: Sprite2D = plot.get_node("LeftWall")
	var job_board: Sprite2D = content.get_node("YSortWorld/InitialWorksites/JobBoard/Sprite2D")
	_expect(not plot.get_node("Board").visible and plot.interaction_area.position == keeper.position + Vector2(0, -4),
		"The main workshop anchors interaction to its visible keeper.")
	_expect(board.visible and board.position + board.offset == second_plot.interaction_area.position,
		"The second workshop preserves its visible Board image/interaction center.")
	_expect(plot.get_node("Plot").position + plot.get_node("Plot").offset == Vector2(0, -17.5), "Rear wall regions retain their authored image placement.")
	await _probe_occlusion(board, Vector2(0, -2), "plot-board")
	await _probe_occlusion(wall, Vector2(0, 2), "plot-wall")
	await _probe_occlusion(job_board, Vector2(0, -2), "job-board")
	# A player inside the ruin must appear in front of its rear wall, even
	# while their feet remain above the side walls' lower edge.
	player.global_position = plot.global_position
	await _settle()
	var rear_point: Vector2 = plot.get_global_transform_with_canvas() * Vector2(0, -18)
	var rear_color: Color = get_viewport().get_texture().get_image().get_pixel(roundi(rear_point.x), roundi(rear_point.y))
	_expect(rear_color.r > 0.9 and rear_color.g < 0.05 and rear_color.b > 0.9,
		"Player inside the plot must appear in front of the rear wall.")
	probe.free()
	player.player_visual.show()
	# Compare the same real animation frame in all four screenshots.
	var player_layers: Array[AnimatedSprite2D] = _pause_animation_layers(player.player_visual)
	keeper.set_process(false)
	var keeper_layers: Array[AnimatedSprite2D] = _pause_animation_layers(keeper)
	await _native_occlusion(plot.get_node("Plot"), "native-rear-wall")
	await _native_occlusion(keeper, "native-keeper")
	await _native_occlusion(job_board, "native-job-board")
	await _native_occlusion(second_plot.get_node("Board"), "native-second-board")
	_resume_animation_layers(player_layers)
	_resume_animation_layers(keeper_layers)
	keeper.set_process(true)
	player.can_move = true
	player.global_position = plot.interaction_area.global_position + Vector2(0, 4)
	await _settle()
	var before: int = _now()
	await _key(KEY_QUOTELEFT)
	_expect(debug.panel.visible and not get_tree().paused and _now() == before, "Debug toggle opens its separate panel without pausing or advancing time.")
	_expect(Inventory.items.is_empty(), "Opening Debug does not grant materials automatically.")
	TimeComponentManager.seconds_per_minute = 1.0
	debug.speed_buttons[1].pressed.emit()
	debug._process(1.0)
	_expect(_now() - before == 9, "x10 adds nine minutes to the normal clock's one minute per second.")
	TimeComponentManager.advance_one_minute()
	_expect(_now() - before == 10, "Combined normal/debug clock rate is x10.")
	debug.speed_buttons[2].pressed.emit()
	before = _now()
	debug._process(1.0)
	TimeComponentManager.advance_one_minute()
	_expect(_now() - before == 60 and TimeComponentManager.seconds_per_minute == 1.0, "x60 advances real minute signals without changing the base clock or physics.")
	get_tree().paused = true
	before = _now()
	debug._process(1.0)
	debug.step_minutes(180)
	_expect(_now() == before and debug.step_buttons[1].disabled, "Paused gameplay blocks acceleration and time jumps.")
	get_tree().paused = false
	TimeComponentManager.is_paused = true
	debug._process(1.0)
	_expect(_now() == before, "Clock-level pause also blocks debug acceleration.")
	TimeComponentManager.is_paused = false
	debug.set_speed(1)
	var worker := WorkerData.new()
	worker.worker_id = "time_debug_cleaner"
	worker.satisfaction = 1.0 # Needs remain active throughout the multi-day fixture.
	WorkerDatabase.workers_by_id[worker.worker_id] = worker
	_expect(plot.construction.start_clearing([worker.worker_id] as Array[String], false).success, "Fixture worker starts clearing for real time-jump validation.")
	# Wait for deferred collider/navigation changes exactly as gameplay does
	# before the player can interact with the debug panel again.
	for frame: int in range(4):
		await get_tree().process_frame
	debug._refresh_controls()
	var clearing_start: int = _now()
	_expect(not debug.step_buttons[1].disabled, "The real +3h control is enabled after assignment.")
	debug.step_buttons[1].pressed.emit()
	var arrival: int = int(worker.physical_approach.get("arrival_minute", -1))
	var shift_start: int = (clearing_start / 1440) * 1440 + 7 * 60
	var shift_end: int = (clearing_start / 1440) * 1440 + 15 * 60
	var eligible_clear: int = maxi(0, mini(_now(), shift_end) - maxi(maxi(clearing_start, shift_start), arrival))
	_expect(_now() - clearing_start == 180 and arrival >= clearing_start and arrival < _now()
		and eligible_clear > 0 and eligible_clear < 180 and plot.construction.phase == "clearing"
		and plot.construction._remaining_work_units() == 180 - eligible_clear and worker.is_reserved(),
		"+3h counts only the paid shift minutes after actual physical arrival.")
	var clearing_remainder: int = plot.construction._remaining_work_units()
	var extra_start: int = _now()
	debug.step_minutes(clearing_remainder)
	_expect(_now() - extra_start == clearing_remainder and plot.construction.phase == "empty" and not worker.is_reserved(),
		"The remaining physically eligible cleaning minutes finish once and release the worker.")
	for frame: int in range(4):
		await get_tree().process_frame
	_expect(not plot.construction.get_preview([worker.worker_id] as Array[String]).can_start,
		"Construction correctly rejects an empty personal Inventory.")
	Inventory.add_item("wood_log", 8)
	Inventory.add_item("clay_lump", 1)
	debug.materials_button.pressed.emit()
	_expect(Inventory.items == {"wood_log": 8, "clay_lump": 12, "reed_bundle": 8},
		"Build materials fills only deficits and preserves surplus.")
	var supplied: Dictionary = Inventory.items.duplicate()
	debug.materials_button.pressed.emit()
	_expect(Inventory.items == supplied, "Repeated material clicks do not stack extra kits.")
	Inventory.items.clear()
	Inventory.add_item("wood_log", 33)
	var full_bag: Dictionary = Inventory.items.duplicate()
	_expect(not debug.give_build_materials() and Inventory.items == full_bag,
		"A full bag rejects the whole kit without partial mutation or capacity bypass.")
	Inventory.items.clear()
	Inventory.add_bulk_item(supplied)
	Inventory.remove_item("reed_bundle", 1)
	plot.on_player_interact(player)
	_expect(is_instance_valid(plot.keeper_dialogue), "The current main-workshop keeper opens its greeting first.")
	if is_instance_valid(plot.keeper_dialogue):
		plot.keeper_dialogue.continued.emit()
	_expect(is_instance_valid(plot.menu) and get_tree().paused and not player.can_move,
		"The real build menu pauses gameplay before the debug refill.")
	var paused_time: int = _now()
	debug._refresh_controls()
	_expect(not debug.materials_button.disabled and debug.give_build_materials() and _now() == paused_time,
		"Explicit supplies work inside the paused build menu without advancing time.")
	if is_instance_valid(plot.menu):
		plot.close_menu()
	_expect(plot.construction.get_preview([worker.worker_id] as Array[String]).can_start,
		"Debug kit satisfies the real construction material check.")
	before = _now()
	debug._refresh_controls()
	_expect(not debug.step_buttons[2].disabled, "The real +1d control is enabled after closing the menu.")
	debug.step_buttons[2].pressed.emit()
	_expect(_now() - before == 1440, "+1d advances a whole day with normal calendar events.")
	debug.speed_buttons[0].pressed.emit()
	before = _now()
	debug._process(1.0)
	_expect(_now() == before and debug.speed_multiplier == 1, "x1 removes extra advancement.")
	debug._refresh_controls()
	await _capture("debug-time-panel")
	_expect(plot.construction.start_build([worker.worker_id] as Array[String]).success,
		"The debug-supplied kit starts normal construction.")
	_expect(Inventory.items == {"wood_log": 2}, "Normal construction consumes its kit exactly once.")
	for frame: int in range(4):
		await get_tree().process_frame
	observed_worker = worker
	observed_construction = plot.construction
	TimeComponentManager.simulated_minute_started.connect(_count_eligible_minute)
	eligible_minutes = 0
	var remaining_before: int = plot.construction._remaining_work_units()
	var calendar_before: int = _now()
	debug.step_minutes(plot.construction.SOLO_MINUTES)
	_expect(_now() - calendar_before == plot.construction.SOLO_MINUTES
		and plot.construction.phase == "building" and second_plot.construction.phase == "uncleared"
		and eligible_minutes > 0 and eligible_minutes <= 3 * 8 * 60
		and plot.construction._remaining_work_units() == remaining_before - eligible_minutes,
		"Three calendar days credit only physically arrived, eligible minutes inside the shifts.")
	for day: int in range(12):
		if plot.construction.phase == "built":
			break
		remaining_before = plot.construction._remaining_work_units()
		calendar_before = _now()
		eligible_minutes = 0
		debug.step_minutes(1440)
		_expect(_now() - calendar_before == 1440 and eligible_minutes <= 8 * 60
			and plot.construction._remaining_work_units() == maxi(0, remaining_before - eligible_minutes),
			"Each additional day credits only actual paid, arrived shift minutes.")
		if plot.construction.phase != "built":
			_expect(WorkerDatabase.has_worker_data(worker.worker_id) and worker.get_resolved_satisfaction() > 0.0,
				"The fixture builder remains eligible while daily needs stay enabled.")
		for frame: int in range(3):
			await get_tree().process_frame
	TimeComponentManager.simulated_minute_started.disconnect(_count_eligible_minute)
	_expect(plot.construction.phase == "built" and second_plot.construction.phase == "uncleared" and not worker.is_reserved(),
		"The assigned plot eventually completes once and releases its worker.")
	await _key(KEY_QUOTELEFT)
	_expect(not debug.panel.visible, "Backtick closes the debug panel.")
	player.can_move = false
	# z=11 completion splashes overlap sampled pixels and invalidate built-art comparisons.
	await _wait_for_completion_splashes(plot)
	player_layers = _pause_animation_layers(player.player_visual)
	keeper.set_process(false)
	keeper_layers = _pause_animation_layers(keeper)
	await _native_occlusion(plot.get_node("FinishedBuilding"), "native-built-workshop")
	await _native_occlusion(keeper, "native-built-keeper")
	await _native_occlusion(board, "native-second-board-after-build")
	_resume_animation_layers(player_layers)
	_resume_animation_layers(keeper_layers)
	keeper.set_process(true)
	player.global_position = plot.global_position + Vector2(0, 0)
	await _settle()
	await _capture("native-built-interior")
	player.can_move = true
	content.free()
	print("ContentDepthTimeDebugTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _count_eligible_minute(_arrival_minute: int) -> void:
	if not is_instance_valid(observed_construction) or observed_construction.phase != "building" or observed_worker == null:
		return
	var now: int = _now()
	var minute_of_day: int = now % 1440
	var approach: Dictionary = observed_worker.physical_approach
	if minute_of_day >= 7 * 60 and minute_of_day < 15 * 60 \
			and not observed_worker.is_payroll_blocked() and not observed_worker.resignation_pending \
			and observed_worker.get_resolved_satisfaction() > 0.0 \
			and observed_construction.worker_ids.has(observed_worker.worker_id) \
			and approach.get("arrived", false) and int(approach.get("arrival_minute", now + 1)) <= now:
		eligible_minutes += 1

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventKey.new()
	event.keycode = code
	get_viewport().push_input(event)
	await get_tree().process_frame

func _settle() -> void:
	for _frame in range(4):
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw

func _probe_occlusion(target: Sprite2D, sample: Vector2, caption: String) -> void:
	for front in [false, true]:
		player.global_position = target.global_position + Vector2(sample.x, 2 if front else -2)
		await _settle()
		var point: Vector2 = target.get_global_transform_with_canvas() * (target.offset + sample)
		var image: Image = get_viewport().get_texture().get_image()
		var color: Color = image.get_pixel(roundi(point.x), roundi(point.y))
		var magenta: bool = color.r > 0.9 and color.g < 0.05 and color.b > 0.9
		_expect(magenta == front, "Actual rendered pixels must put Player %s %s." % ["in front of" if front else "behind", caption])
		await _capture("depth-" + caption + ("-front" if front else "-behind"))

func _native_occlusion(target: Node2D, caption: String) -> void:
	# Compare the real layered Player against separately rendered background,
	# object and Player frames; synthetic probes alone miss artwork-specific cases.
	var duplicate: Sprite2D = target.get_parent().get_node_or_null("ResourceIcon") if target.name == "Board" else null
	var duplicate_visible: bool = is_instance_valid(duplicate) and duplicate.visible
	if is_instance_valid(duplicate):
		duplicate.hide()
	for front in [false, true]:
		player.global_position = target.global_position + Vector2(0, 2 if front else -2)
		await _settle()
		var controls: Array[Node] = content.get_node("YSortWorld").find_children("*", "Control", true, false)
		var visible_controls: Array[CanvasItem] = []
		for control: CanvasItem in controls:
			if control.visible:
				visible_controls.append(control)
				control.hide()
		player.player_visual.hide()
		target.hide()
		var background: Image = await _render_image()
		target.show()
		var object_only: Image = await _render_image()
		target.hide()
		player.player_visual.show()
		var player_only: Image = await _render_image()
		target.show()
		var combined: Image = await _render_image()
		var foot: Vector2 = player.get_global_transform_with_canvas().origin
		var overlap: int = 0
		var wrong: int = 0
		for y in range(maxi(roundi(foot.y) - 32, 0), mini(roundi(foot.y), combined.get_height())):
			for x in range(maxi(roundi(foot.x) - 16, 0), mini(roundi(foot.x) + 16, combined.get_width())):
				var bg: Color = background.get_pixel(x, y)
				var pc: Color = player_only.get_pixel(x, y)
				var oc: Color = object_only.get_pixel(x, y)
				if pc.is_equal_approx(bg) or oc.is_equal_approx(bg) or pc.is_equal_approx(oc):
					continue
				overlap += 1
				if not combined.get_pixel(x, y).is_equal_approx(pc if front else oc):
					wrong += 1
		_expect(overlap > 0 and wrong == 0,
			"Native Player layers must appear %s %s (%d overlap pixels, %d wrong)." % ["in front of" if front else "behind", caption, overlap, wrong])
		for control: CanvasItem in visible_controls:
			control.show()
		await _capture(caption + ("-front" if front else "-behind"))
	if duplicate_visible:
		duplicate.show()

func _pause_animation_layers(owner: Node) -> Array[AnimatedSprite2D]:
	var paused: Array[AnimatedSprite2D] = []
	for node: Node in owner.find_children("*", "AnimatedSprite2D", true, false):
		var layer: AnimatedSprite2D = node as AnimatedSprite2D
		if layer.is_playing():
			layer.pause()
			paused.append(layer)
	return paused

func _resume_animation_layers(layers: Array[AnimatedSprite2D]) -> void:
	for layer: AnimatedSprite2D in layers:
		if is_instance_valid(layer):
			layer.play()

func _wait_for_completion_splashes(plot: Node) -> void:
	var started_msec: int = Time.get_ticks_msec()
	while _has_completion_splash(plot) and Time.get_ticks_msec() - started_msec < 3000:
		await RenderingServer.frame_post_draw
	_expect(not _has_completion_splash(plot), "Construction completion splashes must leave the plot before built depth checks.")

func _has_completion_splash(plot: Node) -> bool:
	for child: Node in plot.get_children():
		if child.get_script() == COMPLETION_SPLASH:
			return true
	return false

func _render_image() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

func _capture(caption: String) -> void:
	var folder := OS.get_environment("TIP_DEPTH_CAPTURE_DIR")
	if folder.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(caption + ".png"))
