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
	var contract_days: int = 9
	var contract_index: int = WorkerDatabase.CONTRACT_DAYS.find(contract_days)
	var contract_price: int = WorkerDatabase.get_contract_price(WorkerData.Profession.LABORER, contract_days)
	_expect(contract_index >= 0 and contract_price > 0, "The Laborer has the configured nine-day package that covers construction.")
	if contract_index < 0 or contract_price <= 0:
		_finish()
		return
	board.job_board_ui.contract_days_option.select(contract_index)
	board.job_board_ui.contract_days_option.item_selected.emit(contract_index)
	_expect(board.job_board_ui.applicant_list.get_selected_items() == PackedInt32Array([0])
		and board.job_board_ui.quote_label.text.contains("%d-day prepaid: %d" % [contract_days, contract_price]),
		"The native Job Board selects the Laborer and quotes the full prepaid package.")
	board.job_board_ui.hire_button.pressed.emit()
	_expect(WorkerDatabase.get_worker_data(start.APPLICANT_ID) == null and Inventory.items.is_empty(),
		"An empty wallet cannot hire the applicant or create unpaid work.")
	# This fixture supplies only the exact hiring price; materials still come from worksite actions below.
	Inventory.add_item("shekel", contract_price)
	board.job_board_ui.contract_days_option.item_selected.emit(contract_index)
	_expect(not board.job_board_ui.hire_button.disabled and board.job_board_ui.wallet_label.text.contains("Wallet: %d Shekel" % contract_price),
		"The funded prepaid Hire action is available through the real Job Board.")
	var hire_day: int = TimeComponentManager.current_day
	board.job_board_ui.hire_button.pressed.emit()
	var worker: WorkerData = WorkerDatabase.get_worker_data(start.APPLICANT_ID)
	_expect(worker != null and worker.profession == WorkerData.Profession.LABORER, "Hire produces an actual Laborer.")
	if worker == null:
		_finish()
		return
	_expect(worker.payroll_contract_days == contract_days and worker.payroll_paid_from_day == hire_day
		and worker.payroll_paid_until_day == hire_day + contract_days and not worker.is_payroll_blocked(),
		"The selected prepaid period activates immediately and covers the planned construction.")
	_expect(Inventory.items.is_empty(), "Hiring debits the exact wallet quote once without granting materials.")
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
	_expect(plot.construction.phase == "clearing" and worker.matches_physical_approach("plot",
		plot.construction.order_id + ":clearing", plot.construction.order_id),
		"Clearing starts with the native physical approach to the workshop.")
	TimeComponentManager.advance_minutes(30)
	_expect(plot.construction.phase == "clearing" and plot.construction.completes_at - _now() == plot.construction.CLEARING_MINUTES,
		"A clock jump before physical arrival grants no clearing progress.")
	_complete_fixture_plot_arrival(worker, plot, "clearing")
	TimeComponentManager.advance_minutes(plot.construction.CLEARING_MINUTES)
	await get_tree().process_frame
	_expect(plot.construction.phase == "empty" and not worker.is_reserved(),
		"Paid clearing completes only after arrival and releases the worker for construction.")
	plot.on_player_interact(player)
	plot.menu._on_worker_assignment_next_requested([worker.worker_id] as Array[String])
	plot.menu.build_button.pressed.emit()
	_expect(plot.construction.phase == "building", "Gathered materials and hired worker can start construction without debug supply.")
	_complete_fixture_plot_arrival(worker, plot, "building")
	TimeComponentManager.advance_minutes(plot.construction.SOLO_MINUTES)
	await _frames()
	_expect(plot.construction.phase == "built" and not worker.is_reserved() and not worker.is_payroll_blocked(),
		"The workshop completes under the paid contract and releases the hired builder.")
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

func _complete_fixture_plot_arrival(worker: WorkerData, plot: Node, phase: String) -> void:
	# This preserved worksite fixture has no WorkerRuntime. The current-map
	# arrival regression drives the actual route; here the native arrival gate
	# still has to validate the worker's pose before construction can advance.
	var task_key: String = plot.construction.order_id + ":" + phase
	_expect(worker.matches_physical_approach("plot", task_key, plot.construction.order_id),
		"The builder has the native approach task for " + phase + ".")
	if not worker.physical_approach.arrived:
		if worker.physical_approach.position.distance_to(worker.physical_approach.target) > 0.1:
			_expect(not worker.mark_physical_arrival(task_key),
				"The arrival gate rejects a builder still short of the workshop entrance.")
		worker.physical_approach.position = worker.physical_approach.target
	plot.mark_worker_arrived(worker.worker_id, task_key)
	_expect(worker.matches_physical_approach("plot", task_key, plot.construction.order_id) and worker.physical_approach.arrived,
		"The paid builder reaches the validated plot entrance before " + phase + " time counts.")

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
