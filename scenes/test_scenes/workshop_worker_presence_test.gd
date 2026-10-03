extends Node2D

const MAP = preload("res://scenes/content_scene/content_scene.tscn")
const DUST = preload("res://scenes/workshop_plot/worker_entry_dust.gd")
const SPLASH = preload("res://scenes/workshop_plot/construction_complete_splash.gd")
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _dust_count(plot: Node) -> int:
	var count: int = 0
	for child: Node in plot.get_children():
		if child.get_script() == DUST:
			count += 1
	return count

func _check_completion_pixels() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 24)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.size = Vector2(64, 24)
	viewport.add_child(background)
	var reference := TextureProgressBar.new()
	reference.texture_under = preload("res://assets/ui/ui_icon/empty_bar.png")
	reference.texture_progress = preload("res://assets/ui/ui_icon/filled_bar.png")
	reference.value = 100
	reference.position = Vector2(8, 8)
	viewport.add_child(reference)
	await RenderingServer.frame_post_draw
	var original: Image = viewport.get_texture().get_image()
	reference.hide()
	var effect = SPLASH.new()
	effect.texture = reference.texture_progress
	effect.under_texture = reference.texture_under
	effect.position = reference.position
	viewport.add_child(effect)
	effect.set_process(false)
	effect.elapsed = 0.35
	effect.queue_redraw()
	await RenderingServer.frame_post_draw
	var settled: Image = viewport.get_texture().get_image()
	_expect(original.get_data() == settled.get_data(), "Settled completion must exactly match the original full bar pixels.")
	for time: float in [0.475, 0.6, 0.725]:
		effect.elapsed = time
		effect.queue_redraw()
		await RenderingServer.frame_post_draw
		var faded: Image = viewport.get_texture().get_image()
		var opacity: float = 1.0 - smoothstep(0.35, 0.85, time)
		var matches: bool = true
		for y: int in range(24):
			for x: int in range(64):
				var expected: Color = original.get_pixel(x, y) * opacity
				var actual: Color = faded.get_pixel(x, y)
				if maxf(absf(expected.r - actual.r), maxf(absf(expected.g - actual.g), absf(expected.b - actual.b))) > 2.0 / 255.0:
					matches = false
		_expect(matches, "Fade at %.3fs changes only opacity, preserving every pixel position and color ratio." % time)
	viewport.queue_free()

func _run() -> void:
	await _check_completion_pixels()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var content = MAP.instantiate()
	add_child(content)
	var plot = content.get_node("YSortWorld/WorkshopPlot")
	plot.set_process(false) # Advance the cosmetic timer explicitly for repeatable assertions.
	var other_plot = content.get_node("YSortWorld/WorkshopPlot2")
	var visuals = content.get_node("YSortWorld/WorkerRuntime/WorkerVisuals")
	visuals.set_process(false)
	visuals.plot_presence.update(visuals, 0.0)
	var ids: Array[String] = []
	for i in range(8):
		var worker := WorkerData.new()
		worker.worker_id = "presence_worker_%d" % i
		worker.profession = WorkerData.Profession.LABORER
		WorkerDatabase.workers_by_id[worker.worker_id] = worker
		ids.append(worker.worker_id)
	var result: Dictionary = plot.construction.start_clearing([ids[0]] as Array[String], false)
	_expect(result.success, "Worker clearing starts through the existing state API.")
	var clearing_bar: TextureProgressBar = plot.get_node("BuildingProgress")
	_expect(clearing_bar.visible and clearing_bar.value == 0.0 and not plot.get_node("Label").visible,
		"Cleaning shows the same empty bar and hides its percentage label.")
	plot._process(2.0)
	_expect(_dust_count(plot) == 0, "No activity dust appears before a worker starts approaching.")
	visuals.plot_presence.update(visuals, 0.0)
	_expect(visuals.actors[ids[0]].visible, "Worker walks into the plot before hiding.")
	visuals.plot_presence.update(visuals, 0.25)
	plot._process(2.0)
	_expect(_dust_count(plot) == 0 and not plot._has_dust_activity(), "No dust spawns while the worker is still approaching.")
	var remaining: int = plot.construction.clearing_remaining
	visuals.plot_presence.update(visuals, 2.0)
	_expect(not visuals.actors[ids[0]].visible and _dust_count(plot) == 1,
		"Worker disappears at the entrance with one cosmetic dust puff.")
	_expect(plot.construction.clearing_remaining == remaining,
		"Walking and dust do not advance the gameplay timer.")
	var camera := Camera2D.new()
	add_child(camera)
	camera.global_position = plot.global_position + Vector2(0, 12)
	camera.zoom = Vector2(3, 3)
	camera.make_current()
	await get_tree().create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("tip-worker-entry-dust.png"))
	await get_tree().create_timer(0.6).timeout
	_expect(_dust_count(plot) == 0, "Dust removes itself after its short lifetime.")
	plot._worker_dust_rng.seed = 123
	var intervals: Array[float] = []
	var positions: Array[Vector2] = []
	for i in range(4):
		plot._process(2.0)
		intervals.append(plot._worker_dust_remaining)
	for child: Node in plot.get_children():
		if child.get_script() == DUST:
			positions.append(child.position)
			_expect(plot.worker_dust_area.has_point(child.position), "Activity dust stays inside the configured plot area.")
	_expect(positions.size() == 4 and positions[0] != positions[1], "Active clearing repeatedly spawns dust at changing positions.")
	_expect(intervals[0] != intervals[1], "The delay changes between puffs.")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("tip-worker-activity-dust.png"))
	for interval: float in intervals:
		_expect(interval >= plot.worker_dust_interval_min and interval <= plot.worker_dust_interval_max,
			"Random delays stay within the Inspector bounds.")
	get_tree().paused = true
	plot._process(2.0)
	_expect(_dust_count(plot) == 4, "Opening a paused menu stops new activity puffs.")
	get_tree().paused = false
	TimeComponentManager.advance_minutes(90)
	_expect(is_equal_approx(clearing_bar.value, 50.0), "Cleaning fills half the bar after 90 of its 180 minutes.")
	camera.global_position = plot.global_position + Vector2(0, -4)
	camera.zoom = Vector2(2, 2)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("tip-cleaning-progress.png"))
	TimeComponentManager.advance_minutes(90)
	_expect(not clearing_bar.visible and clearing_bar.value == 100.0 and not plot.get_node("Label").visible,
		"Finished cleaning hands the full bar to its completion animation without duplicating it.")
	var cleaning_splashes: int = 0
	for child: Node in plot.get_children():
		if child.get_script() == SPLASH:
			cleaning_splashes += 1
	_expect(cleaning_splashes == 1, "Cleaning completion emits one matching gold splash.")
	plot._process(2.0)
	_expect(_dust_count(plot) == 4, "Completing clearing stops new dust immediately.")
	await get_tree().create_timer(1.1).timeout
	_expect(_dust_count(plot) == 0, "The final activity puffs fade out after completion.")
	visuals.plot_presence.update(visuals, 0.0)
	_expect(visuals.actors[ids[0]].visible, "Worker reappears when clearing finishes.")
	plot.worker_dust_enabled = false
	for item_id: String in plot.construction.REQUIREMENTS:
		Inventory.add_item(item_id, plot.construction.REQUIREMENTS[item_id])
	_expect(plot.construction.start_build(ids).success, "Eight workers start construction with unchanged requirements.")
	var bar: TextureProgressBar = plot.get_node("BuildingProgress")
	_expect(bar.visible and not plot.get_node("Label").visible and bar.value == 0.0,
		"Construction shows the empty asset bar instead of the percentage label.")
	_expect(not plot._has_dust_activity(), "A previous clearing arrival cannot enable dust for a new building task.")
	plot._process(2.0)
	visuals.plot_presence.update(visuals, 2.0)
	visuals._process(0.2)
	_expect(plot._has_dust_activity(), "Building dust becomes eligible after builders arrive.")
	for id: String in ids:
		_expect(not visuals.actors[id].visible, "All eight builders remain hidden inside the plot.")
		_expect(not visuals.roaming.has(id), "Active builders cannot fall back to idle roaming.")
	_expect(_dust_count(plot) == 0, "Disabling dust leaves the enter/hide mechanism intact.")
	_expect(other_plot.construction.phase == "uncleared", "The neighboring plot remains independent.")
	TimeComponentManager.advance_minutes(270)
	_expect(is_equal_approx(bar.value, 50.0), "Half the construction duration fills exactly half the bar.")
	camera.global_position = plot.global_position + Vector2(0, -4)
	camera.zoom = Vector2(2, 2)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("tip-building-progress.png"))
	TimeComponentManager.advance_minutes(270)
	_expect(not bar.visible and bar.value == 100.0, "Completion hands the full bar to its bounce/highlight/fade animation.")
	plot._sync_construction()
	var splashes: int = 0
	for child: Node in plot.get_children():
		if child.get_script() == SPLASH:
			splashes += 1
			_expect(child.texture == bar.texture_progress and child.under_texture == bar.texture_under,
				"Completion keeps the original full bar textures.")
	_expect(splashes == 1, "Repeated synchronization cannot replay the completion splash.")
	await get_tree().create_timer(0.16).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("tip-building-complete-splash.png"))
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("tip-building-complete-fade.png"))
	await get_tree().create_timer(0.5).timeout
	plot._process(1.1)
	_expect(not bar.visible and plot.get_node("Label").visible,
		"After the splash, the full bar is replaced by the normal workshop label.")
	visuals.plot_presence.update(visuals, 0.0)
	for id: String in ids:
		_expect(visuals.actors[id].visible, "All builders reappear when construction completes.")
	var workshop: WorkShop = plot.get_node("BuiltWorkshop")
	var job: JobData = preload("res://resources/job_data/mudbrick_make.tres")
	for item_id: String in job.inputs:
		WorkShopStorage.add_item(item_id, job.inputs[item_id])
	_expect(workshop.start_job_from_storage(job, [ids[0]]), "Production starts through the real workshop API.")
	_expect(not plot._has_dust_activity(), "A previous building arrival cannot enable dust for a new production order.")
	visuals.plot_presence.update(visuals, 2.0)
	_expect(plot._has_dust_activity() and not other_plot._has_dust_activity(), "After arrival, production dust belongs only to its originating plot.")
	_expect(not visuals.actors[ids[0]].visible, "Production uses the same hide-inside presentation.")
	content.free()
	content = MAP.instantiate()
	add_child(content)
	_expect(not content.get_node("YSortWorld/WorkshopPlot/BuildingProgress").visible,
		"Reloading an already-built plot does not replay its completion bar.")
	visuals = content.get_node("YSortWorld/WorkerRuntime/WorkerVisuals")
	visuals.set_process(false)
	visuals.plot_presence.update(visuals, 0.0)
	_expect(not visuals.actors[ids[0]].visible, "Reloading the map retains the active production worker inside its plot.")
	_expect(content.get_node("YSortWorld/WorkshopPlot")._has_dust_activity(), "Restored workers already inside resume activity dust.")
	TimeComponentManager.advance_minutes(job.base_duration_minutes)
	visuals.plot_presence.update(visuals, 0.0)
	_expect(visuals.actors[ids[0]].visible, "Production completion restores the worker after a map reload.")
	print("WorkshopWorkerPresenceTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
