extends Node

const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const FIRST_ID: String = "initial_workshop_laborer"
const SECOND_ID: String = "initial_worksite_hauler"
const EXTRA_ID: String = "resident_visibility_fixture"
const SAVE_PATH: String = "user://city_resident_test/checkpoint.json"
var launched: bool = false
var failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

func _capture(stage: String) -> void:
	var directory: String = OS.get_environment("TIP_RESIDENT_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_expect(get_viewport().get_texture().get_image().save_png(directory.path_join(stage + ".png")) == OK, "Capture " + stage)

func _run() -> void:
	if OS.get_name() == "Linux":
		var root: String = OS.get_environment("XDG_DATA_HOME")
		_expect(root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(root.simplify_path().trim_suffix("/") + "/"), "A disposable XDG_DATA_HOME is required.")
	_expect(not FileAccess.file_exists(SAVE_PATH), "Refuse to overwrite a checkpoint.")
	if failures:
		get_tree().quit(1)
		return
	get_tree().current_scene = null
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = SAVE_PATH
	menu.session_started.connect(func(continued: bool): launched = not continued)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await get_tree().process_frame
	menu.new_game_button.pressed.emit()
	for frame: int in range(1200):
		if launched:
			break
		await get_tree().process_frame
	_expect(launched, "The real New Game launches.")
	if not launched:
		get_tree().quit(1)
		return
	await get_tree().create_timer(1.5).timeout
	var city: Node = get_tree().current_scene
	var residents: Array[CitizenData] = CitizenManager.get_all_residents()
	var applicants: Array[CitizenData] = CitizenManager.get_all_applicants()
	print("RESIDENT_START day=", TimeComponentManager.current_day, " hour=", TimeComponentManager.current_hour, " minute=", TimeComponentManager.current_minute, " needs_day=", CitizenNeedsManager.last_processed_day, " residents=", residents.size(), " applicants=", applicants.size())
	for person: CitizenData in residents:
		print("RESIDENT_START_PERSON id=", person.citizen_id, " satisfaction=", person.satisfaction, " employment=", person.employment_status)
	_expect(TimeComponentManager.is_processing() and TimeComponentManager.current_day == 0 and CitizenNeedsManager.last_processed_day == -1, "Day-zero startup runs the clock without settling daily needs.")
	_expect(residents.size() == 2 and applicants.size() == 2, "The original residents are eligible applicants on day zero.")
	await _capture("day0-city")
	var board: JobBoard = city.get_node("YSortWorld/InitialWorksites/JobBoard")
	board.on_player_interact(city.get_node("YSortWorld/Player"))
	_expect(board.job_board_ui != null and board.job_board_ui.visible and board.job_board_ui.cards.size() == 2, "The real Job Board displays both cards without any wallet grant.")
	await _capture("day0-board")
	if board.job_board_ui != null:
		board.job_board_ui.close()
	var visuals: Node = city.get_node("YSortWorld/WorkerRuntime/WorkerVisuals")
	var population_label: Label = city.get_node("TopHUD").population_label
	_expect(visuals.actors.has(FIRST_ID) and visuals.actors.has(SECOND_ID), "Both actual residents have world actors.")
	_expect(visuals.actors.size() == residents.size() and CitizenNeedsManager.get_daily_shelter_capacity_need() == residents.size() and population_label.text == str(residents.size()), "The world, HUD and resident need count agree on day zero.")
	for person: CitizenData in residents:
		_expect(visuals.actors.has(person.citizen_id) and visuals.actors[person.citizen_id].is_visible_in_tree(), "Each initial resident is visibly represented by identity.")

	# An unemployed person who cannot apply is still an actual resident.
	var extra := CitizenData.new()
	extra.citizen_id = EXTRA_ID
	extra.display_name = "Resident fixture"
	extra.population_status = CitizenData.PopulationStatus.RESIDENT
	extra.satisfaction = 0.4
	extra.visual_profile = VisualProfile.new()
	extra.visual_profile.skin_tone = "dark"
	extra.visual_profile.hair_style = "brown_female_01"
	CitizenManager.add_citizen(extra)
	_expect(visuals.actors.size() == 3 and visuals.actors.has(EXTRA_ID) and visuals.actors[EXTRA_ID].is_visible_in_tree(), "An ineligible unemployed resident appears without an application.")
	if visuals.actors.has(EXTRA_ID):
		var extra_actor: Node = visuals.actors[EXTRA_ID]
		_expect(extra_actor.skin_tone == "dark" and extra_actor.hair_style == "brown_female_01", "The resident visual uses the person's own profile.")
	_expect(CitizenNeedsManager.get_daily_shelter_capacity_need() == 3 and population_label.text == "3" and CitizenManager.get_all_applicants().size() == 2, "Population counts the additional resident once, while the Job Board does not offer them.")
	_expect(CitizenManager.leave_city(EXTRA_ID) and not visuals.actors.has(EXTRA_ID), "A departed citizen is removed from the world immediately.")
	_expect(CitizenManager.get_all_residents().size() == 2 and CitizenNeedsManager.get_daily_shelter_capacity_need() == 2 and population_label.text == "2", "Departure immediately reduces the actual population, HUD and need.")

	# Advance the real clock over midnight with no supplies. Player protection is
	# test-only and does not affect citizen needs, payroll or applicant rules.
	var player: Player = city.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	var now: int = TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	_expect(TimeComponentManager.advance_minutes(1440 - now + 8 * 60), "The real clock advances to day one, 08:00.")
	var first: CitizenData = CitizenManager.get_citizen(FIRST_ID)
	var second: CitizenData = CitizenManager.get_citizen(SECOND_ID)
	print("RESIDENT_DAY1 day=", TimeComponentManager.current_day, " needs_day=", CitizenNeedsManager.last_processed_day, " satisfaction=", first.satisfaction, ",", second.satisfaction, " applicants=", CitizenManager.get_all_applicants().size())
	_expect(TimeComponentManager.current_day == 1 and CitizenNeedsManager.last_processed_day == 1 and is_equal_approx(first.satisfaction, 0.5) and is_equal_approx(second.satisfaction, 0.5), "One unmet day lowers the starting residents from 55% to 50%.")
	_expect(CitizenManager.get_all_applicants().size() == 2, "Both starters remain eligible through the first merchant visit.")
	_expect(TimeComponentManager.advance_minutes(1440), "The real clock reaches the second daily settlement.")
	_expect(TimeComponentManager.current_day == 2 and CitizenNeedsManager.last_processed_day == 2 and is_equal_approx(first.satisfaction, 0.45) and is_equal_approx(second.satisfaction, 0.45), "A second unmet day lowers both starting residents to 45%.")
	_expect(CitizenManager.get_all_applicants().is_empty() and CitizenManager.get_all_residents().size() == 2 and visuals.actors.size() == 2, "Both ineligible applicants remain real, visible residents on day two.")
	for person: CitizenData in CitizenManager.get_all_residents():
		_expect(visuals.actors.has(person.citizen_id) and visuals.actors[person.citizen_id].is_visible_in_tree(), "Day-two residents remain visible despite ineligibility.")
	board.on_player_interact(player)
	_expect(board.job_board_ui != null and board.job_board_ui.empty_state_panel.visible and board.job_board_ui.applicants.is_empty(), "The actual day-two board shows its empty state under these conditions.")
	if board.job_board_ui != null:
		var empty_label: Label = board.job_board_ui.empty_state_label
		_expect(empty_label.text.contains("Food") and empty_label.text.contains("Clothing") and empty_label.text.contains("Shelter")
			and empty_label.text.contains("50%") and empty_label.text.contains("daily"), "The empty board explains the actual needs and daily recovery threshold.")
		_expect(empty_label.size.x > 0 and empty_label.size.y > 0 and empty_label.get_line_count() >= 3
			and empty_label.get_line_height() * empty_label.get_line_count() <= empty_label.size.y,
			"The recovery guidance fits inside the existing empty-state label.")
		for line: String in empty_label.text.split("\n"):
			_expect(empty_label.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, empty_label.get_theme_font_size("font_size")).x <= empty_label.size.x,
				"Each line of recovery guidance fits the label width.")
	await _capture("day1-board")
	if board.job_board_ui != null:
		board.job_board_ui.close()
	await get_tree().process_frame

	# Restore eligibility and fund a hire only as a fixture for visual lifecycle.
	first.satisfaction = 0.5
	var price: int = WorkerDatabase.get_contract_price(WorkerData.Profession.LABORER, 3)
	Inventory.add_item("shekel", price)
	var store: Node = WorkStateRuntime.get_node("CitySave")
	_expect(store.save_checkpoint(), "An idle-resident checkpoint saves: " + store.last_error)
	board.on_player_interact(player)
	var ui: JobBoardUI = board.job_board_ui
	_expect(ui != null and ui.applicants.size() == 1 and ui.applicants[0].citizen_id == FIRST_ID, "An eligible resident reappears on the real Job Board.")
	if ui == null or ui.applicants.is_empty():
		get_tree().quit(1)
		return
	var first_actor: Node2D = visuals.actors[FIRST_ID]
	ui.applicant_list.select(0)
	ui.hire_button.pressed.emit()
	ui.confirm_hire_button.pressed.emit()
	_expect(WorkerDatabase.has_worker_data(FIRST_ID) and visuals.actors[FIRST_ID] == first_actor and visuals.actors.size() == 2, "Hiring retains exactly the existing resident visual.")
	ui.close()
	await get_tree().process_frame
	var construction: Node = city.get_node("YSortWorld/CitizenHousePlot").construction
	construction.phase = "empty" # Test-only cleaned plot; the real assignment path follows.
	construction.changed.emit()
	Inventory.add_bulk_item({"wood_log": 4, "clay_lump": 8, "reed_bundle": 6})
	var ids: Array[String] = [FIRST_ID]
	var start: Dictionary = construction.start_build(ids)
	_expect(bool(start.get("success", false)), "The paid resident can be assigned to build: " + str(start))
	await get_tree().process_frame
	_expect(visuals.actors.get(FIRST_ID) == first_actor and CitizenManager.get_all_residents().size() == 2 and visuals.actors.size() == 2, "Assignment reuses the same identity without changing population.")
	var worker: WorkerData = WorkerDatabase.get_worker_data(FIRST_ID)
	_expect(worker != null and not worker.physical_approach.is_empty(), "The assigned resident uses the normal physical approach.")

	store.disk.path = SAVE_PATH.get_base_dir().path_join("assigned.json")
	_expect(store.save_checkpoint(), "The real city saves its existing schema: " + store.last_error)
	_expect(CitizenManager.leave_city(SECOND_ID) and not visuals.actors.has(SECOND_ID), "An unsaved departure updates the world.")
	_expect(population_label.text == "1", "The HUD immediately reflects the unsaved departure.")
	_expect(store.load_checkpoint(), "The isolated city checkpoint loads: " + store.last_error)
	for frame: int in range(4):
		await get_tree().process_frame
	_expect(CitizenManager.get_all_residents().size() == 2 and population_label.text == "2" and visuals.actors.size() == 2 and visuals.actors.has(FIRST_ID) and visuals.actors.has(SECOND_ID), "Load updates the HUD and rebuilds exactly one visual per restored resident.")
	worker = WorkerDatabase.get_worker_data(FIRST_ID)
	_expect(worker != null and worker.is_reserved() and not worker.physical_approach.is_empty(), "Load retains the assigned worker and commute.")
	_expect(store.load_checkpoint(), "The same checkpoint can be loaded again: " + store.last_error)
	for frame: int in range(4):
		await get_tree().process_frame
	_expect(visuals.actors.size() == 2 and visuals.actors.has(FIRST_ID) and visuals.actors.has(SECOND_ID), "Repeated load does not duplicate resident visuals.")
	_expect(visuals.plot_presence.tracked.has(FIRST_ID), "The assigned worker is tracked by the plot visual owner.")
	store.disk.path = SAVE_PATH
	_expect(store.load_checkpoint(), "The earlier idle-resident checkpoint loads: " + store.last_error)
	for frame: int in range(4):
		await get_tree().process_frame
	_expect(not WorkerDatabase.has_worker_data(FIRST_ID) and visuals.actors.size() == 2 and visuals.actors.has(FIRST_ID) and visuals.actors[FIRST_ID].is_visible_in_tree(), "Loading an idle resident after an assigned worker leaves no stale hidden work visual.")
	print("CityResidentTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
