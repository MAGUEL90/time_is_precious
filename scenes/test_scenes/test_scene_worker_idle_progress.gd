extends Node

## Isolated, headless construction fixture. No user save or shortcut to arrival.
const MAP = preload("res://scenes/content_scene/content_scene.tscn")
const SAVE_STATE = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const DUST = preload("res://scenes/workshop_plot/worker_entry_dust.gd")
const WORKER_ID: String = "idle_progress_fixture"
const SAVE_FILE: String = "user://worker_idle_save_fixture.json"
var failures: int = 0
var camera: Camera2D

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _visible_dust_count(plot: Node) -> int:
	var count: int = 0
	for child: Node in plot.get_children():
		if child.get_script() == DUST and child.visible and not child.is_queued_for_deletion():
			count += 1
	return count

func _check_returning_dust(plot: Node, visuals: Node2D, worker: WorkerData, bar: TextureProgressBar) -> void:
	var distance: float = worker.physical_approach.position.distance_to(worker.physical_approach.target)
	var step: float = minf(0.1, distance / (24.0 * 8.0))
	for _index: int in range(3):
		_check(not worker.physical_approach.arrived and bar.material != null, "A returning worker keeps the progress bar inactive.")
		plot._process(2.0)
		_check(not plot._has_dust_activity() and _visible_dust_count(plot) == 0, "Renewed workers produce no dust while still travelling.")
		visuals.plot_presence.update(visuals, step)

func _capture_animation_frame(directory: String, index: int) -> void:
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	_check(frame.get_size() == Vector2i(400, 225), "Dust animation uses the native logical viewport.")
	if frame.get_size() == Vector2i(400, 225):
		_check(frame.save_png(directory.path_join("frame-%04d.png" % index)) == OK, "Save dust animation frame.")

func _capture(stage: String) -> void:
	var directory: String = OS.get_environment("TIP_MVP_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	frame.resize(1200, 675, Image.INTERPOLATE_NEAREST)
	_check(frame.save_png(directory.path_join("worker-idle-" + stage + ".png")) == OK, "Save worker render: " + stage)

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 4
	TimeComponentManager.current_hour = 7
	TimeComponentManager.current_minute = 0
	var content: Node = MAP.instantiate()
	add_child(content)
	# Long construction time jumps should not start an unrelated Player collapse.
	var player: Player = content.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	var plot: Node = content.get_node("YSortWorld/WorkshopPlot")
	if not OS.get_environment("TIP_MVP_CAPTURE_DIR").is_empty() and DisplayServer.get_name() != "headless":
		get_window().content_scale_size = Vector2i(400, 225)
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().size = Vector2i(1200, 675)
		camera = Camera2D.new()
		content.add_child(camera)
		camera.global_position = plot.global_position
		camera.zoom = Vector2(2, 2)
		camera.make_current()
	var visuals: Node2D = content.get_node("YSortWorld/WorkerRuntime/WorkerVisuals")
	visuals.set_process(false)
	var mode: String = "roundtrip"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--idle-phase="):
			mode = arg.trim_prefix("--idle-phase=")
	if mode == "read":
		_read_departure(content, plot, visuals)
		return
	var person := CitizenData.new()
	person.citizen_id = WORKER_ID
	person.display_name = "Idle progress fixture"
	person.population_status = CitizenData.PopulationStatus.RESIDENT
	person.employment_status = CitizenData.EmploymentStatus.HIRED
	person.profession = WorkerData.Profession.LABORER
	CitizenManager.citizens_by_id[WORKER_ID] = person
	var worker := WorkerData.new()
	worker.worker_id = WORKER_ID
	worker.profession = WorkerData.Profession.LABORER
	worker.payroll_start_day = 1
	worker.payroll_paid_from_day = 1
	worker.payroll_paid_until_day = 4
	worker.payroll_paid_start_minute = 1 * 1440 + 420
	worker.payroll_contract_days = 3
	worker.payroll_period_rate = WorkerDatabase.get_contract_price(worker.profession, 3)
	worker.payroll_last_attempt_day = 1
	WorkerDatabase.workers_by_id[WORKER_ID] = worker
	plot.construction.phase = "empty" # Already-cleared fixture; native build consumes its recipe.
	for item_id: String in plot.construction.REQUIREMENTS:
		Inventory.add_item(item_id, int(plot.construction.REQUIREMENTS[item_id]))
	_check(plot.construction.start_build([WORKER_ID] as Array[String]).success, "Native construction starts with the original materials.")
	var bar: TextureProgressBar = plot.get_node("BuildingProgress")
	_check(bar.visible and bar.material != null, "Pending physical arrival shows gray progress.")
	for _frame: int in range(4000):
		if worker.physical_approach.get("arrived", false):
			break
		visuals.plot_presence.update(visuals, 0.1)
	_check(worker.physical_approach.get("arrived", false), "Worker physically reaches the plot.")
	_check(bar.material == null, "Active worker restores the normal progress color.")
	TimeComponentManager.advance_minutes(30)
	var progress: float = bar.value
	_check(progress > 0.0, "Paid arrived worker advances construction.")
	plot._process(2.0)
	_check(_visible_dust_count(plot) > 0, "Active paid construction shows activity dust.")
	await _capture("active")
	var now: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	TimeComponentManager.advance_minutes(worker.get_paid_end_minute() - now)
	progress = bar.value
	_check(worker.is_payroll_blocked() and progress > 0.0 and bar.material != null, "Expiry preserves progress and grays the bar.")
	_check(_visible_dust_count(plot) == 0, "The gray-bar transition hides all existing activity dust immediately.")
	var entry: Vector2 = worker.physical_approach.position
	visuals.plot_presence.update(visuals, 0.1)
	_check(not worker.physical_approach.arrived and worker.physical_approach.arrival_minute == -1, "Unpaid worker leaves working state and needs a new physical arrival.")
	_check(worker.physical_approach.position.distance_to(entry) <= 2.401 and visuals.actors[WORKER_ID].visible, "Departure begins visibly within walking speed, without teleporting.")
	await _capture("leaving")
	if mode == "write":
		var codec = SAVE_STATE.new()
		var document: Dictionary = codec.capture(content)
		_check(not document.is_empty(), "Native schema captures a builder mid-departure: " + codec.error)
		if not document.is_empty():
			var file := FileAccess.open(SAVE_FILE, FileAccess.WRITE)
			_check(file != null, "Isolated user:// fixture can be written.")
			if file != null:
				file.store_string(JSON.stringify(document, "", true, true))
				file.close()
		_finish()
		return
	TimeComponentManager.advance_minutes(180)
	_check(is_equal_approx(bar.value, progress), "An unpaid worker grants no progress during a +3h jump.")
	plot._process(2.0)
	_check(_visible_dust_count(plot) == 0 and not plot._has_dust_activity(), "Expired construction cannot spawn new dust.")
	var departure: Node2D = visuals.get_parent().get_node("WorkerDeparture/NearSpawn")
	for _frame: int in range(4000):
		if worker.physical_approach.position.distance_to(departure.global_position) <= 0.1:
			break
		visuals.plot_presence.update(visuals, 0.1)
	visuals.plot_presence.update(visuals, 0.0)
	_check(worker.physical_approach.position.distance_to(departure.global_position) <= 0.1 and not visuals.actors[WORKER_ID].visible, "Unpaid worker exits the plot along the authored route.")
	await _capture("paused")
	var animation_dir: String = OS.get_environment("TIP_DUST_ANIMATION_DIR")
	var recording: bool = not animation_dir.is_empty() and DisplayServer.get_name() != "headless"
	var animation_frame: int = 0
	if recording:
		DirAccess.make_dir_recursive_absolute(animation_dir)
		for _frame: int in range(5):
			await _capture_animation_frame(animation_dir, animation_frame)
			animation_frame += 1
	var price: int = WorkerDatabase.get_contract_price(worker.profession, 3)
	Inventory.add_item("shekel", price)
	_check(WorkerDatabase.renew_contract(WORKER_ID, 3), "The normal paid renewal succeeds.")
	visuals.plot_presence.update(visuals, 0.1)
	_check(visuals.actors[WORKER_ID].visible and bar.material != null, "Renewed worker returns visibly while progress remains gray.")
	_check_returning_dust(plot, visuals, worker, bar)
	await _capture("returning")
	for _frame: int in range(4000):
		if worker.physical_approach.get("arrived", false):
			break
		plot._process(0.1)
		_check(not plot._has_dust_activity() and _visible_dust_count(plot) == 0 and bar.material != null,
			"Dust stays stopped and progress stays gray throughout the renewed return.")
		visuals.plot_presence.update(visuals, 0.1)
		if recording:
			await _capture_animation_frame(animation_dir, animation_frame)
			animation_frame += 1
	_check(worker.physical_approach.get("arrived", false) and bar.material == null, "Returning worker reaches the plot before progress turns active.")
	TimeComponentManager.advance_minutes(30)
	_check(bar.value > progress, "Construction resumes from the preserved value after renewal.")
	plot._process(2.0)
	_check(_visible_dust_count(plot) > 0, "Activity dust resumes only after paid physical return.")
	if recording:
		for _frame: int in range(10):
			plot._process(0.1)
			await _capture_animation_frame(animation_dir, animation_frame)
			animation_frame += 1
	await _capture("resumed")
	_finish()

func _read_departure(content: Node, plot: Node, visuals: Node2D) -> void:
	var document_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_FILE))
	_check(document_value is Dictionary, "Fresh process reads the isolated departure checkpoint.")
	if not document_value is Dictionary:
		_finish()
		return
	var codec = SAVE_STATE.new()
	_check(codec.prepare(document_value, content), "Fresh process validates the native departure schema: " + codec.error)
	if codec.prepared.is_empty():
		_finish()
		return
	codec.apply_prepared(content, false)
	var worker: WorkerData = WorkerDatabase.get_worker_data(WORKER_ID)
	var bar: TextureProgressBar = plot.get_node("BuildingProgress")
	var pose: Vector2 = worker.physical_approach.position
	var progress: float = bar.value
	_check(plot.construction.phase == "building" and worker.is_payroll_blocked() and not worker.physical_approach.arrived and worker.physical_approach.arrival_minute == -1,
		"Continue retains building, expired contract and the pending departure pose.")
	_check(progress > 0.0 and bar.material != null, "Continue retains partial progress and gray presentation.")
	_check(_visible_dust_count(plot) == 0 and not plot._has_dust_activity(), "Continue starts the unpaid builder without activity dust.")
	visuals.plot_presence.update(visuals, 0.1)
	_check(worker.physical_approach.position.distance_to(pose) <= 2.401, "Fresh process continues bounded departure movement.")
	var departure: Node2D = visuals.get_parent().get_node("WorkerDeparture/NearSpawn")
	for _frame: int in range(4000):
		if worker.physical_approach.position.distance_to(departure.global_position) <= 0.1:
			break
		visuals.plot_presence.update(visuals, 0.1)
	TimeComponentManager.advance_minutes(180)
	_check(is_equal_approx(bar.value, progress), "Continue plus +3h cannot advance expired construction.")
	plot._process(2.0)
	_check(_visible_dust_count(plot) == 0, "Continue and +3h keep activity dust stopped.")
	var price: int = WorkerDatabase.get_contract_price(worker.profession, 3)
	Inventory.add_item("shekel", price)
	_check(WorkerDatabase.renew_contract(WORKER_ID, 3), "Normal renewal works after process restart.")
	visuals.plot_presence.update(visuals, 0.1)
	_check_returning_dust(plot, visuals, worker, bar)
	for _frame: int in range(4000):
		if worker.physical_approach.arrived:
			break
		plot._process(0.1)
		_check(not plot._has_dust_activity() and _visible_dust_count(plot) == 0 and bar.material != null,
			"After Continue, dust stays stopped and progress stays gray throughout the renewed return.")
		visuals.plot_presence.update(visuals, 0.1)
	_check(worker.physical_approach.arrived and bar.material == null, "Renewed worker physically returns after Continue.")
	TimeComponentManager.advance_minutes(30)
	_check(bar.value > progress, "Continue preserves progress and resumes only after return.")
	_finish()

func _finish() -> void:
	print("WorkerIdleProgressTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
