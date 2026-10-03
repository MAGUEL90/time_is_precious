extends Node

const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const STARTUP = preload("res://scenes/content_scene/startup/initial_worksites.gd")
@export var run_automatically: bool = true
var failures: int = 0
var content: Node
var player: Player
var worksites: Node2D

func _ready() -> void:
	if run_automatically:
		_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _settle() -> void:
	for _frame: int in range(5):
		await get_tree().physics_frame
	await get_tree().process_frame

func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventAction.new()
	event.action = action
	get_viewport().push_input(event)
	await get_tree().process_frame

func _load_map() -> void:
	content = CONTENT.instantiate()
	add_child(content)
	player = content.get_node("YSortWorld/Player")
	worksites = content.get_node("YSortWorld/Worksites")
	await _settle()

func _hire(ui: JobBoardUI, citizen_id: String) -> void:
	for index: int in range(ui.applicants.size()):
		if ui.applicants[index].citizen_id == citizen_id:
			ui.applicant_list.select(index)
			ui.hire_button.pressed.emit()
			return
	_expect(false, "Expected applicant is missing: " + citizen_id)

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.environment.color = Color.WHITE
	await _load_map()
	_expect(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(), "Map startup does not auto-hire workers or grant personal materials.")
	_expect(worksites.city_tools.units.size() == 1 and worksites.city_tools.units.has(STARTUP.CART_UNIT_ID), "Normal startup supplies exactly one city-owned Cart.")
	var hauler_citizen: CitizenData = CitizenManager.get_citizen(STARTUP.HAULER_APPLICANT_ID)
	var laborer_citizen: CitizenData = CitizenManager.get_citizen(STARTUP.APPLICANT_ID)
	_expect(hauler_citizen != null and hauler_citizen.profession == WorkerData.Profession.HAULER, "Normal startup registers a Hauler citizen applicant.")
	_expect(laborer_citizen != null and CitizenManager.get_all_applicants().size() == 2, "Existing Laborer is retained alongside one Hauler.")
	var board: JobBoard = content.get_node("YSortWorld/InitialWorksites/JobBoard")
	player.global_position = board.global_position + Vector2(0, 12)
	await _settle()
	await _press(&"interact")
	_expect(is_instance_valid(board.job_board_ui), "Actual map E interaction opens Job Board.")
	if not is_instance_valid(board.job_board_ui):
		_finish()
		return
	await _capture("main-map-hauler-applicants.png")
	_hire(board.job_board_ui, STARTUP.HAULER_APPLICANT_ID)
	var hauler: WorkerData = WorkerDatabase.get_worker_data(STARTUP.HAULER_APPLICANT_ID)
	_expect(hauler != null and hauler.profession == WorkerData.Profession.HAULER and hauler.get_linked_citizen() == hauler_citizen, "Job Board hires the real Hauler with its existing citizen identity.")
	_expect(hauler != null and hauler.wage_shekel_per_day == board.default_daily_wage, "Existing daily wage is retained for Hauler hiring.")
	_hire(board.job_board_ui, STARTUP.APPLICANT_ID)
	_expect(board.job_board_ui.applicants.is_empty() and board.job_board_ui.hire_button.disabled, "Both hires consume their applicants without automatic replacements.")
	board.job_board_ui.close_button.pressed.emit()
	await _settle()
	_expect(worksites.daily.unavailable(STARTUP.HAULER_APPLICANT_ID).begins_with("Requires a cart"), "Hired Hauler still requires explicitly equipped cart before assignment.")
	await _equip_and_haul()
	var provider: Node = worksites.city_tools
	content.free()
	await _load_map()
	_expect(worksites.city_tools == provider and WorkerDatabase.get_worker_data(STARTUP.HAULER_APPLICANT_ID) == hauler, "Map reload retains city supplies and the actual hired Hauler.")
	_expect(provider.units.size() == 1 and provider.has_equipped(hauler.worker_id, "cart"), "Reload preserves the equipped Cart without creating another unit.")
	_expect(CitizenManager.get_all_applicants().is_empty() and WorkerDatabase.get_all_workers().size() == 2, "Reload cannot duplicate either hire.")
	_expect(worksites.worker_management.fire(STARTUP.HAULER_APPLICANT_ID) == "Worker fired. Tools returned to City Storage.", "Idle Hauler can be fired through worker management.")
	_expect(str(provider.units[STARTUP.CART_UNIT_ID].worker_id).is_empty(), "Firing returns the physical Cart to available city stock.")
	content.free()
	await _load_map()
	_expect(not WorkerDatabase.has_worker_data(STARTUP.HAULER_APPLICANT_ID) and hauler_citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED, "Reload preserves dismissal instead of respawning the Hauler.")
	provider.units.erase(STARTUP.CART_UNIT_ID)
	content.free()
	await _load_map()
	_expect(provider.units.is_empty(), "Removing the supplied Cart cannot trigger a second startup grant on reload.")
	var opt_out = preload("res://scenes/content_scene/startup/initial_worksites.tscn").instantiate()
	opt_out.enable_initial_applicant = false
	CitizenManager.citizens_by_id.erase(STARTUP.APPLICANT_ID)
	WorkerDatabase.workers_by_id.erase(STARTUP.APPLICANT_ID)
	add_child(opt_out)
	_expect(CitizenManager.get_citizen(STARTUP.APPLICANT_ID) == null, "Existing fixture opt-out still disables startup registration.")
	_finish()

func _equip_and_haul() -> void:
	await _press(&"open_worker_hub")
	var hub: WorkerControlUI = worksites.worker_control
	_expect(hub.visible and get_tree().paused, "Worker Hub opens for equipment preparation.")
	hub.tools_tab_button.pressed.emit()
	for card: Node in hub.tools_worker_list.get_children():
		if card.worker_id == STARTUP.HAULER_APPLICANT_ID:
			card.pressed.emit()
			break
	hub.tools_tool_button.pressed.emit()
	_expect(hub.city_storage_view.visible, "Hauler's Tool slot opens the existing City Storage equipment view.")
	await _settle()
	var cart_slot: BaseButton
	for cell: Node in hub.city_storage_list.get_children():
		for slot: Node in cell.get_children():
			if slot is BaseButton and slot.get_meta("unit_id", "") == STARTUP.CART_UNIT_ID:
				cart_slot = slot
	_expect(cart_slot != null and not cart_slot.disabled, "Starting Cart is selectable from city supplies.")
	if cart_slot == null:
		hub.close()
		return
	cart_slot.pressed.emit()
	_expect(is_instance_valid(hub.city_action_panel), "Cart opens the normal Equip action.")
	await _settle()
	await _capture("main-map-hauler-cart-equip.png")
	hub.city_action_panel.use_button.pressed.emit()
	await _settle()
	_expect(worksites.city_tools.has_equipped(STARTUP.HAULER_APPLICANT_ID, "cart"), "Equip allocates the actual city-owned Cart to the hired Hauler.")
	_expect(worksites.daily.unavailable(STARTUP.HAULER_APPLICANT_ID).is_empty(), "Equipped Hauler satisfies the existing worksite requirement.")
	_expect(worksites.worker_management.equip(STARTUP.APPLICANT_ID, STARTUP.CART_UNIT_ID) != "Tool equipped.", "One physical Cart cannot be shared between workers.")
	_expect(Inventory.items.is_empty(), "Cart allocation never enters personal Inventory.")
	hub.city_storage_view.get_node("Close").pressed.emit()
	await _capture("main-map-hauler-cart-equipped.png")
	hub.close_button.pressed.emit()
	var site: Marker2D = worksites.get_node("WorksiteMarkers/WoodSite")
	player.global_position = site.global_position + Vector2(0, 8)
	await _settle()
	await _press(&"interact")
	_expect(worksites.inspector.visible and worksites._selected_site == site, "E opens Wood Site for normal Daily setup.")
	await _capture("main-map-worksite.png")
	worksites.inspector.daily_button.pressed.emit()
	var assignment = worksites.inspector.assignment_ui
	assignment._open_worker_selection(0)
	assignment._on_worker_selected(STARTUP.APPLICANT_ID)
	assignment._open_worker_selection(1)
	assignment._on_worker_selected(STARTUP.HAULER_APPLICANT_ID)
	var setup: Control = assignment.hauler_setup
	_expect(setup.visible, "Equipped Hauler opens destination and daily target setup.")
	var destination: StorageDestination = worksites.get_node("WoodStorage")
	var destination_path: NodePath = worksites.get_path_to(destination)
	for index: int in range(setup.destination_button.item_count):
		if setup.destination_button.get_item_metadata(index) == destination_path:
			setup.destination_button.select(index)
	setup.target_edit.text = "3"
	setup.target_edit.text_changed.emit("3")
	await _capture("main-map-hauler-daily-setup.png")
	setup.assign_button.pressed.emit()
	assignment.next_button.pressed.emit()
	await _capture("main-map-worksite-confirmation.png")
	worksites.inspector.start_button.pressed.emit()
	_expect(worksites.daily.jobs.has(&"WoodSite"), "Start Work commits the hired Laborer and equipped Hauler.")
	if not worksites.daily.jobs.has(&"WoodSite"):
		return
	var starts: int = worksites.daily.jobs[&"WoodSite"].starts[STARTUP.HAULER_APPLICANT_ID]
	_expect(starts / 1440 == TimeComponentManager.current_day + 1, "The existing next-day start rule is retained.")
	player.global_position = worksites.global_position + Vector2(0, 56)
	await _settle()
	TimeComponentManager.advance_minutes(starts + 180 - worksites.daily.now())
	await _settle()
	var storage: Node = destination.get_storage()
	var produced: int = worksites.daily.jobs[&"WoodSite"].stats[STARTUP.APPLICANT_ID].output
	_expect(storage.quantity == 3 and worksites.hauling.delivered_on_day(STARTUP.HAULER_APPLICANT_ID, TimeComponentManager.current_day) == 3, "Hired Hauler delivers the target to Wood Storage with the supplied Cart.")
	_expect(produced == 9 and worksites._daily_output_count(&"WoodSite") + storage.quantity == produced, "Normal gathering and hauling conserve the existing Wood output.")
	player.global_position = destination.global_position + Vector2(0, 5)
	await _settle()
	await _press(&"interact")
	_expect(storage.quantity == 0 and int(Inventory.items.get("wood_log", 0)) == 3, "Delivered Wood can be withdrawn through the existing E path.")

func _capture(filename: String) -> void:
	var directory: String = OS.get_environment("TIP_HAULER_START_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join(filename))

func _finish() -> void:
	get_tree().paused = false
	print("MainMapHaulerStartTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
