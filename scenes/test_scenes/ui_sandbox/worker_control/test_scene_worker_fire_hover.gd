extends Node

const WORKSITE_FIXTURE: PackedScene = preload("res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn")

const WORKING_ID: String = "fire_hover_working"
const TRAVELLING_ID: String = "fire_hover_travelling"
const HAULER_ID: String = "fire_hover_hauler"
const RESERVED_ID: String = "fire_hover_reserved"
const WORKSHOP_ID: String = "fire_hover_workshop"
const IDLE_ID: String = "fire_hover_idle"

var failures: int = 0
var fire_review_dir: String = ""
var fire_hover_enter_events: int = 0
var fire_hover_exit_events: int = 0
var fixture
var worker_control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	fire_review_dir = ProjectSettings.globalize_path("user://fire-hover-review")
	DirAccess.make_dir_recursive_absolute(fire_review_dir)
	print("Worker Fire hover screenshots: " + fire_review_dir)
	fixture = WORKSITE_FIXTURE.instantiate()
	fixture.prepare_nightmare_test = false
	fixture.test_hauler_carts = 0
	add_child(fixture)
	fixture.player.debug_disable_player_needs = true
	worker_control = fixture.worker_control
	await get_tree().process_frame
	await get_tree().process_frame
	worker_control._fire_hover_detector.mouse_entered.connect(_on_fire_hover_probe_entered)
	worker_control._fire_hover_detector.mouse_exited.connect(_on_fire_hover_probe_exited)
	_expect(get_viewport().get_visible_rect().size == Vector2(400, 225), "Test uses the approved 400 x 225 logical viewport.")
	_expect(get_window().size == Vector2i(1200, 675), "Test uses the 1200 x 675 development window.")
	print("Worker Fire hover sizes: logical=%s window=%s" % [get_viewport().get_visible_rect().size, get_window().size])

	_add_worker(WORKING_ID, WorkerData.Profession.LABORER, WorkerData.WorkStatus.WORKING, "working_order")
	_add_worker(TRAVELLING_ID, WorkerData.Profession.LABORER, WorkerData.WorkStatus.TRAVELLING, "travel_order")
	_add_worker(HAULER_ID, WorkerData.Profession.HAULER, WorkerData.WorkStatus.IDLE)
	_add_worker(RESERVED_ID, WorkerData.Profession.CRAFTER, WorkerData.WorkStatus.RESTING, "reserved_order")
	_add_worker(WORKSHOP_ID, WorkerData.Profession.CRAFTER, WorkerData.WorkStatus.IDLE)
	_add_worker(IDLE_ID, WorkerData.Profession.LABORER, WorkerData.WorkStatus.IDLE)
	_add_assigned_citizen(WORKSHOP_ID)
	fixture.hauling.routes[HAULER_ID] = {"phase": "outbound", "removing": false}
	worker_control.open()
	await get_tree().process_frame
	await get_tree().process_frame

	await _check_disabled_hover(WORKING_ID, "Working now", "working")
	await _check_disabled_hover(TRAVELLING_ID, "Travelling", "travelling")
	await _check_disabled_hover(HAULER_ID, "Hauler trip", "hauler-trip")
	await _check_disabled_hover(RESERVED_ID, "Job reserved", "reserved")
	await _check_disabled_hover(WORKSHOP_ID, "Workshop assigned", "workshop-assigned")
	await _check_generic_fallback()
	await _check_stale_state_refresh()
	await _check_edge_clamping()
	await _check_enabled_fire_confirmation()

	worker_control.close()
	if failures > 0:
		push_error("Worker Fire hover review failed with %d assertion(s)." % failures)
		get_tree().quit(1)
		return
	print("Worker Fire hover review passed.")
	get_tree().quit(0)


func _add_worker(worker_id: String, profession: WorkerData.Profession, status: WorkerData.WorkStatus, order_id: String = "") -> WorkerData:
	var worker := WorkerData.new()
	worker.worker_id = worker_id
	worker.display_name = worker_id
	worker.profession = profession
	worker.current_work_status = status
	worker.current_order_id = order_id
	WorkerDatabase.workers_by_id[worker_id] = worker
	return worker


func _add_assigned_citizen(worker_id: String) -> void:
	var citizen := CitizenData.new()
	citizen.citizen_id = worker_id
	citizen.display_name = worker_id
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.ASSIGNED
	CitizenManager.add_citizen(citizen)


func _row_for(worker_id: String) -> Dictionary:
	for row: Dictionary in worker_control._get_worker_rows():
		if str(row.get("id", "")) == worker_id:
			return row
	return {}


func _move_mouse_to(logical_position: Vector2) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var window_size: Vector2 = get_window().size
	var scale: Vector2 = window_size / viewport_size
	Input.warp_mouse((logical_position * scale).round())
	await get_tree().create_timer(0.08, true).timeout
	await get_tree().process_frame
	await get_tree().process_frame


func _on_fire_hover_probe_entered() -> void:
	fire_hover_enter_events += 1


func _on_fire_hover_probe_exited() -> void:
	fire_hover_exit_events += 1


func _click_at(logical_position: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = logical_position
	down.global_position = logical_position
	down.pressed = true
	get_viewport().push_input(down, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = logical_position
	up.global_position = logical_position
	up.pressed = false
	get_viewport().push_input(up, true)
	await get_tree().process_frame


func _check_disabled_hover(worker_id: String, reason: String, capture_name: String) -> void:
	worker_control._show_manage(worker_id)
	await get_tree().process_frame
	await get_tree().process_frame
	var row: Dictionary = _row_for(worker_id)
	_expect(bool(row.get("can_fire", true)) == false or bool(row.get("working", false)), "%s row is blocked by its real worker state." % capture_name)
	_expect(str(row.get("fire_block_reason", "")) == reason, "%s row supplies the matching Fire block reason." % capture_name)
	_expect(worker_control.manage_fire_button.disabled, "%s Fire remains disabled." % capture_name)
	var fire_rect: Rect2 = worker_control.manage_fire_button.get_global_rect()
	await _move_mouse_to(Vector2(3, 3))
	var enters_before: int = fire_hover_enter_events
	await _move_mouse_to(fire_rect.get_center())
	_expect(fire_rect.has_point(get_viewport().get_mouse_position()), "%s OS mouse pointer reaches Fire in viewport coordinates." % capture_name)
	_expect(fire_hover_enter_events > enters_before, "%s real mouse motion produces a hover-enter event." % capture_name)
	_expect(worker_control._fire_block_feedback.visible, "%s actual mouse hover displays rendered feedback." % capture_name)
	_expect(worker_control._fire_block_feedback.text == reason, "%s feedback matches the current cause." % capture_name)
	await _capture(capture_name + ".png")
	var exits_before: int = fire_hover_exit_events
	await _move_mouse_to(Vector2(3, 3))
	_expect(fire_hover_exit_events > exits_before, "%s real mouse motion produces a hover-exit event." % capture_name)
	_expect(not worker_control._fire_block_feedback.visible and worker_control.manage_window.visible,
		"%s feedback hides after hover exit while Manage stays open." % capture_name)
	var reenters_before: int = fire_hover_enter_events
	await _move_mouse_to(fire_rect.get_center())
	_expect(fire_hover_enter_events > reenters_before, "%s real mouse motion produces a second hover-enter event." % capture_name)
	_expect(worker_control._fire_block_feedback.visible and worker_control._fire_block_feedback.text == reason,
		"%s feedback reappears on mouse re-entry." % capture_name)
	await _click_at(fire_rect.get_center())
	_expect(worker_control.manage_fire_button.disabled and not worker_control._confirmation_overlay.visible, "%s click does not activate disabled Fire." % capture_name)
	worker_control._close_manage()
	_expect(not worker_control._fire_block_feedback.visible and not worker_control._fire_hover_detector.visible,
		"%s popup close hides feedback and the hover detector." % capture_name)
	await get_tree().process_frame


func _check_generic_fallback() -> void:
	worker_control.rows_provider = func() -> Array[Dictionary]:
		return [{"id": "generic", "name": "Generic", "profession": "Laborer", "working": false,
			"can_fire": false, "can_goto": false}]
	worker_control._show_manage("generic")
	await get_tree().process_frame
	await get_tree().process_frame
	var fire_rect: Rect2 = worker_control.manage_fire_button.get_global_rect()
	await _move_mouse_to(Vector2(3, 3))
	await _move_mouse_to(fire_rect.get_center())
	_expect(worker_control._fire_block_feedback.visible and worker_control._fire_block_feedback.text == "Cannot fire",
		"Unknown disabled cause uses a short honest fallback.")
	await _capture("generic-fallback.png")
	worker_control._close_manage()
	worker_control.rows_provider = fixture.worker_management.rows
	await get_tree().process_frame


func _check_stale_state_refresh() -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(TRAVELLING_ID)
	worker.current_work_status = WorkerData.WorkStatus.TRAVELLING
	worker_control._show_manage(TRAVELLING_ID)
	await get_tree().process_frame
	await get_tree().process_frame
	var fire_rect: Rect2 = worker_control.manage_fire_button.get_global_rect()
	await _move_mouse_to(Vector2(3, 3))
	await _move_mouse_to(fire_rect.get_center())
	_expect(worker_control._fire_block_feedback.visible and worker_control._fire_block_feedback.text == "Travelling",
		"Fresh travel state is visible before it changes.")
	worker.current_work_status = WorkerData.WorkStatus.WORKING
	await _move_mouse_to(Vector2(3, 3))
	await _move_mouse_to(fire_rect.get_center())
	_expect(not worker_control._fire_block_feedback.visible,
		"A stale hover refresh hides old feedback until the pointer leaves again.")
	await _move_mouse_to(Vector2(3, 3))
	await _move_mouse_to(fire_rect.get_center())
	_expect(worker_control._fire_block_feedback.visible and worker_control._fire_block_feedback.text == "Working now",
		"Re-entry displays updated reason (text=%s cached=%s pointer_inside=%s ignore=%s mouse=%s rect=%s)." % [
			worker_control._fire_block_feedback.text, worker_control._fire_block_reason,
			worker_control._fire_hover_pointer_inside, worker_control._fire_hover_ignore_until_exit,
			get_viewport().get_mouse_position(), worker_control.manage_fire_button.get_global_rect()])
	worker_control.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not worker_control._fire_block_feedback.visible, "Roster refresh hides feedback while status is updated.")
	worker.current_work_status = WorkerData.WorkStatus.IDLE
	worker.current_order_id = ""
	await _move_mouse_to(Vector2(3, 3))
	await _move_mouse_to(fire_rect.get_center())
	_expect(not worker_control.manage_fire_button.disabled and not worker_control._fire_block_feedback.visible,
		"Stale disabled state is cleared when the worker becomes idle.")
	await _move_mouse_to(Vector2(3, 3))
	await _move_mouse_to(fire_rect.get_center())
	worker_control.manage_fire_button.pressed.emit()
	await get_tree().process_frame
	_expect(worker_control._confirmation_overlay.visible,
		"Fire works normally after the stale disabled state clears.")
	worker_control._cancel_remove_confirmation()
	worker_control._close_manage()
	worker.current_work_status = WorkerData.WorkStatus.TRAVELLING
	worker.current_order_id = "travel_order"
	await get_tree().process_frame


func _check_edge_clamping() -> void:
	worker_control._show_manage(WORKING_ID)
	await get_tree().process_frame
	await get_tree().process_frame
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var popup_size: Vector2 = worker_control.manage_window.size
	worker_control.manage_window.position = Vector2(2, 2)
	worker_control._sync_fire_hover_detector()
	await get_tree().process_frame
	await _move_mouse_to(Vector2(3, 3))
	var top_left_fire_rect: Rect2 = worker_control.manage_fire_button.get_global_rect()
	await _move_mouse_to(top_left_fire_rect.get_center())
	_expect(top_left_fire_rect.has_point(get_viewport().get_mouse_position()),
		"Top-left edge mouse reaches Fire in viewport coordinates.")
	_expect(worker_control._fire_block_feedback.visible, "Edge placement still shows actual hover feedback.")
	var label_rect: Rect2 = worker_control._fire_block_feedback.get_global_rect()
	_expect(label_rect.position.x >= 0 and label_rect.position.y >= 0
		and label_rect.end.x <= viewport_size.x and label_rect.end.y <= viewport_size.y,
		"Top-left feedback label stays inside the logical viewport.")
	await _capture("edge-top-left.png")
	worker_control.manage_window.position = Vector2(viewport_size.x - popup_size.x - 2.0,
		viewport_size.y - popup_size.y - 2.0)
	worker_control._sync_fire_hover_detector()
	await get_tree().process_frame
	await _move_mouse_to(Vector2(3, 3))
	var bottom_right_fire_rect: Rect2 = worker_control.manage_fire_button.get_global_rect()
	await _move_mouse_to(bottom_right_fire_rect.get_center())
	_expect(bottom_right_fire_rect.has_point(get_viewport().get_mouse_position()),
		"Bottom-right edge mouse reaches Fire in viewport coordinates.")
	_expect(worker_control._fire_block_feedback.visible, "Bottom-right edge placement still shows actual hover feedback.")
	label_rect = worker_control._fire_block_feedback.get_global_rect()
	_expect(label_rect.position.x >= 0 and label_rect.position.y >= 0
		and label_rect.end.x <= viewport_size.x and label_rect.end.y <= viewport_size.y,
		"Bottom-right feedback label stays inside the logical viewport.")
	await _capture("edge-bottom-right.png")
	worker_control._close_manage()


func _check_enabled_fire_confirmation() -> void:
	worker_control._show_manage(IDLE_ID)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not worker_control.manage_fire_button.disabled, "Idle worker keeps the normal enabled Fire action.")
	var fire_center: Vector2 = worker_control.manage_fire_button.get_global_rect().get_center()
	await _move_mouse_to(fire_center)
	worker_control.manage_fire_button.pressed.emit()
	await get_tree().process_frame
	_expect(worker_control._confirmation_overlay.visible,
		"Enabled Fire opens confirmation (disabled=%s mouse=%s rect=%s)." % [
			worker_control.manage_fire_button.disabled, get_viewport().get_mouse_position(),
			worker_control.manage_fire_button.get_global_rect()])
	var no_center: Vector2 = worker_control._confirm_no_button.get_global_rect().get_center()
	await _move_mouse_to(no_center)
	worker_control._confirm_no_button.pressed.emit()
	await get_tree().process_frame
	_expect(not worker_control._confirmation_overlay.visible and WorkerDatabase.has_worker_data(IDLE_ID),
		"No cancels Fire and retains the worker.")
	await _move_mouse_to(fire_center)
	worker_control.manage_fire_button.pressed.emit()
	await get_tree().process_frame
	_expect(worker_control._confirmation_overlay.visible, "Fire can open confirmation again after No.")
	var yes_center: Vector2 = worker_control._confirm_yes_button.get_global_rect().get_center()
	await _move_mouse_to(yes_center)
	worker_control._confirm_yes_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not worker_control._confirmation_overlay.visible and not WorkerDatabase.has_worker_data(IDLE_ID),
		"Yes confirms Fire through the existing worker manager path.")
	await _capture("enabled-confirmed.png")


func _capture(file_name: String) -> void:
	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(fire_review_dir.path_join(file_name))
	print("Captured %s at %s" % [file_name, image.get_size()])
