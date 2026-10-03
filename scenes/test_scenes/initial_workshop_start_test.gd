extends Node

var failures: int = 0
var content: Node
var player: Player
var start: Node

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _frames() -> void:
	for _frame in range(5):
		await get_tree().physics_frame
	await get_tree().process_frame

func _interact_at(target: Node2D) -> void:
	var interaction: Node2D = target.get_node_or_null("InteractableComponent")
	player.global_position = (interaction.global_position if interaction != null else target.global_position) + Vector2(0, 12)
	await _frames()
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventAction.new()
	event.action = "interact"
	get_viewport().push_input(event)
	await get_tree().process_frame

func _run() -> void:
	Inventory.items.clear()
	WorkerDatabase.dismissed_workers.clear()
	CitizenManager.citizens_by_id.clear()
	TimeComponentManager.seconds_per_minute = 100000.0
	content = preload("res://scenes/test_scenes/fixtures/content_worksites_map.tscn").instantiate()
	add_child(content)
	player = content.get_node("YSortWorld/Player")
	start = content.get_node("YSortWorld/InitialWorksites")
	await _frames()
	_expect(Inventory.items.is_empty(), "Starting content must not grant materials.")
	_expect(WorkerDatabase.get_all_workers().is_empty(), "Initial applicant must not be pre-hired.")
	var board: JobBoard = start.get_node("JobBoard")
	await _interact_at(board)
	_expect(is_instance_valid(board.job_board_ui), "E opens the authored Job Board.")
	if not is_instance_valid(board.job_board_ui):
		_finish()
		return
	_expect(board.job_board_ui.applicants.size() == 2, "Initial Laborer and Hauler applicants are visible.")
	var hauler_applicant_id: String = start.HAULER_APPLICANT_ID
	var hauler_applicant: CitizenData = CitizenManager.get_citizen(hauler_applicant_id)
	_expect(hauler_applicant != null and hauler_applicant.profession == WorkerData.Profession.HAULER, "Initial Hauler uses the existing citizen hiring flow.")
	await _capture("initial-job-board.png")
	board.job_board_ui.hire_button.pressed.emit()
	var worker: WorkerData = WorkerDatabase.get_worker_data(start.APPLICANT_ID)
	_expect(worker != null and worker.profession == WorkerData.Profession.LABORER, "Hire produces an actual Laborer.")
	_expect(worker.wage_shekel_per_day == board.default_daily_wage, "Existing daily wage is retained.")
	board.job_board_ui.close_button.pressed.emit()
	await get_tree().process_frame
	var worksites = content.get_node("YSortWorld/Worksites")
	for site_id: String in ["WoodSite", "ReedSite", "StrawSite", "WaterSite"]:
		var marker: Marker2D = worksites.get_node("WorksiteMarkers/" + site_id)
		var session = worksites.sites[StringName(site_id)]
		var before: int = _now()
		await _interact_at(marker)
		_expect(worksites.inspector.visible, "E opens the shared worksite inspector: " + site_id)
		worksites.inspector.close_button.pressed.emit()
		_expect(_now() == before and Inventory.items.is_empty(), "Closing inspection changes neither time nor inventory.")
		await _interact_at(marker)
		worksites.inspector.hourly_button.pressed.emit()
		worksites.inspector.next_button.pressed.emit()
		await _capture("worksite-" + site_id + ".png")
		var expected: int = mini(floori(180.0 / session.minutes_per_unit), session.stock)
		worksites.inspector.start_button.pressed.emit()
		worksites.inspector.start_button.pressed.emit()
		await worksites.work_finished
		_expect(_now() == before + 180, "Shared Hourly work spends exactly three hours, including double-click guard.")
		var ground: int = 0
		for drop: Node in worksites.get_node("GroundOutput").get_children():
			_expect(drop.item_id == session.item_id, "Overflow retains the selected resource identity.")
			ground += drop.quantity
			# Remove only test-created output between independent source checks.
			drop.free()
		_expect(int(Inventory.items.get(session.item_id, 0)) + ground == expected, "Inventory plus overflow equals earned worksite output.")
		_expect(not get_tree().paused and player.can_move, "Worksite completion restores controls.")
		Inventory.items.clear()
	# Obtain construction materials through the same player-facing Hourly path.
	for site_id: String in ["WoodSite", "ReedSite", "ClaySiteA"]:
		await _interact_at(worksites.get_node("WorksiteMarkers/" + site_id))
		worksites.inspector.hourly_button.pressed.emit()
		worksites.inspector.next_button.pressed.emit()
		worksites.inspector.start_button.pressed.emit()
		await worksites.work_finished
	_expect(Inventory.items.get("clay_lump", 0) >= 12, "Clay worksite supplies construction alongside Wood and Reed sites.")
	var plot = content.get_node("YSortWorld/WorkshopPlot")
	await _interact_at(plot)
	plot.menu._on_worker_assignment_next_requested([worker.worker_id] as Array[String])
	plot.menu.build_button.pressed.emit()
	TimeComponentManager.advance_minutes(plot.construction.CLEARING_MINUTES)
	await get_tree().process_frame
	plot.on_player_interact(player)
	plot.menu._on_worker_assignment_next_requested([worker.worker_id] as Array[String])
	plot.menu.build_button.pressed.emit()
	_expect(plot.construction.phase == "building", "Gathered materials and hired worker can start construction without debug supply.")
	TimeComponentManager.advance_minutes(plot.construction.SOLO_MINUTES)
	await _frames()
	_expect(plot.construction.phase == "built" and not worker.is_reserved(), "Workshop completes and releases hired builder.")
	var applicant_id: String = start.APPLICANT_ID
	var citizen = CitizenManager.get_citizen(applicant_id)
	content.free()
	content = preload("res://scenes/test_scenes/fixtures/content_worksites_map.tscn").instantiate()
	content.get_node("YSortWorld/Worksites").seed_playtest_hauler = false
	add_child(content)
	await _frames()
	_expect(CitizenManager.get_citizen(applicant_id) == citizen and WorkerDatabase.get_worker_data(applicant_id) == worker, "Reload keeps the existing hire instead of recreating the applicant.")
	_expect(CitizenManager.get_all_applicants().size() == 1 and CitizenManager.get_citizen(hauler_applicant_id) == hauler_applicant, "Reload keeps the unhired Hauler without recreating the hired Laborer.")
	_finish()

func _finish() -> void:
	get_tree().paused = false
	print("InitialWorkshopStartTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _capture(filename: String) -> void:
	var directory: String = OS.get_environment("TIP_START_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join(filename))
