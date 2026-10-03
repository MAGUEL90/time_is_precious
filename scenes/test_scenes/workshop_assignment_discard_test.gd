extends Node

const ASSIGNMENT_SCENE: PackedScene = preload(
	"res://scenes/ui/workshop_worker_assignment_ui/workshop_worker_assignment_ui.tscn"
)
const JOB_SCENE: PackedScene = preload(
	"res://scenes/ui/workshop_job_ui/workshop_job_ui.tscn"
)
const WORKSHOP_SCENE: PackedScene = preload(
	"res://scenes/workshop/workshop.tscn"
)
const MUDBRICK_JOB: JobData = preload(
	"res://resources/job_data/mudbrick_make.tres"
)

var failures: int = 0
var _worker_ids: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	TimeComponentManager.is_paused = true
	var daily = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_daily.gd").new()
	var draft_worker: WorkerData = _register_worker(
		"assignment_discard_draft"
	)
	var active_worker: WorkerData = _register_worker(
		"assignment_discard_active"
	)

	var workshop: WorkShop = WORKSHOP_SCENE.instantiate() as WorkShop
	var other_workshop: WorkShop = WORKSHOP_SCENE.instantiate() as WorkShop
	add_child(workshop)
	add_child(other_workshop)

	var player: Player = Player.new()
	player.claim_menu_workshop = workshop
	var assignment: WorkshopWorkerAssignmentUI = (
		ASSIGNMENT_SCENE.instantiate() as WorkshopWorkerAssignmentUI
	)
	add_child(assignment)
	assignment.confirm_discard_on_exit = true
	assignment.assignment_changed.connect(
		player._on_workshop_worker_assignment_changed
	)
	assignment.assignment_back_requested.connect(
		player._on_workshop_worker_assignment_back_requested
	)
	assignment.assignment_cancelled.connect(
		player._on_workshop_worker_assignment_cancelled
	)
	assignment.open_assignment([], 1)
	assignment._open_worker_selection(0)
	var draft_button: Button = _find_worker_button(
		assignment,
		draft_worker.worker_id
	)
	_expect(draft_button != null, "Draft worker must appear in the selector.")
	if draft_button != null:
		draft_button.pressed.emit()
	_expect(
		workshop.get_assigned_worker_ids() == [draft_worker.worker_id],
		"Selecting a worker must reserve the linked citizen for this setup."
	)
	_expect(
		not _get_citizen(draft_worker.worker_id).can_be_assigned(),
		"A selected worker must be unavailable to another site until discard."
	)
	_expect(not daily.unavailable(draft_worker.worker_id).is_empty(),
		"Worksite Daily rejects the unfinished workshop reservation.")

	assignment.close_button.pressed.emit()
	_expect(
		assignment.confirm_discard_panel.visible,
		"X must warn before leaving a worker draft."
	)
	await RenderingServer.frame_post_draw
	_save_guard_screenshot()
	var keep_button: Button = assignment.discard_guard_keep_button
	keep_button.pressed.emit()
	_expect(
		assignment.visible
			and workshop.get_assigned_worker_ids() == [draft_worker.worker_id]
			and _get_citizen(draft_worker.worker_id).employment_status
			== CitizenData.EmploymentStatus.ASSIGNED,
		"Stay must retain the current worker draft."
	)

	assignment.back_button.pressed.emit()
	_expect(
		assignment.confirm_discard_panel.visible,
		"Back to production must warn before leaving a worker draft."
	)
	keep_button.pressed.emit()
	var cancel_event := InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	assignment._input(cancel_event)
	_expect(
		assignment.confirm_discard_panel.visible,
		"Escape must open the same discard warning as X."
	)
	assignment._input(cancel_event)
	_expect(
		not assignment.confirm_discard_panel.visible
			and workshop.get_assigned_worker_ids() == [draft_worker.worker_id],
		"Escape on the warning must stay in Assign Work and retain the draft."
	)

	assignment.close_menu()
	_expect(
		assignment.confirm_discard_panel.visible,
		"close_menu must use the discard guard."
	)
	assignment.discard_guard_discard_button.pressed.emit()
	await get_tree().process_frame
	_expect(
		workshop.get_assigned_worker_ids().is_empty()
			and _get_citizen(draft_worker.worker_id).employment_status
			== CitizenData.EmploymentStatus.HIRED,
		"Discard must clear the draft and release the linked citizen."
	)
	_expect(
		_get_citizen(draft_worker.worker_id).can_be_assigned()
			and other_workshop.assign_workers([draft_worker.worker_id]),
		"A discarded worker must be available for another workshop."
	)
	other_workshop.assign_workers([])
	_expect(daily.unavailable(draft_worker.worker_id).is_empty(),
		"Worksite Daily accepts the worker after the workshop draft is discarded.")

	# The following job-details step already had a prompt, but also leaked its draft.
	player.claim_menu_workshop = workshop
	workshop.assign_workers([draft_worker.worker_id])
	var draft_job: WorkshopJobUI = JOB_SCENE.instantiate() as WorkshopJobUI
	add_child(draft_job)
	draft_job.cancelled.connect(player._on_workshop_job_cancelled)
	draft_job.open_job(workshop, [draft_worker.worker_id], MUDBRICK_JOB)
	draft_job._input(cancel_event)
	_expect(draft_job.confirm_discard_panel.visible,
		"Leaving unstarted job details warns before discarding the worker draft.")
	draft_job.keep_button.pressed.emit()
	_expect(not daily.unavailable(draft_worker.worker_id).is_empty(),
		"Staying in job details retains the draft reservation.")
	draft_job.close_button.pressed.emit()
	draft_job.discard_button.pressed.emit()
	await get_tree().process_frame
	_expect(workshop.get_assigned_worker_ids().is_empty()
		and daily.unavailable(draft_worker.worker_id).is_empty(),
		"Discarding unstarted job details clears the slots and releases Worksite availability.")

	player.claim_menu_workshop = workshop
	workshop.assign_workers([active_worker.worker_id, draft_worker.worker_id])
	active_worker.start_work("assignment_discard_active_order", "mudbrick_make")
	var job_ui: WorkshopJobUI = JOB_SCENE.instantiate() as WorkshopJobUI
	add_child(job_ui)
	job_ui.cancelled.connect(player._on_workshop_job_cancelled)
	job_ui.open_job(
		workshop,
		workshop.get_assigned_worker_ids(),
		MUDBRICK_JOB
	)
	job_ui.show_start_result(true, "Workshop job started.")
	job_ui.close_button.pressed.emit()
	await get_tree().process_frame
	_expect(
		active_worker.is_reserved()
			and active_worker.current_order_id == "assignment_discard_active_order"
			and _get_citizen(active_worker.worker_id).employment_status
			== CitizenData.EmploymentStatus.ASSIGNED
			and workshop.get_assigned_worker_ids() == [active_worker.worker_id],
		"Closing a started job must preserve its active worker and order."
	)
	_expect(
		_get_citizen(draft_worker.worker_id).employment_status
			== CitizenData.EmploymentStatus.HIRED,
		"Closing a started job must release any separate unstarted draft worker."
	)

	active_worker.finish_work("assignment_discard_active_order")
	workshop.assign_workers([])
	player.free()
	for worker_id in _worker_ids:
		WorkerDatabase.workers_by_id.erase(worker_id)
		CitizenManager.citizens_by_id.erase(worker_id)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	print(
		"WorkshopAssignmentDiscardTest %s"
		% ("PASSED" if failures == 0 else "FAILED")
	)
	get_tree().quit(0 if failures == 0 else 1)


func _register_worker(worker_id: String) -> WorkerData:
	var citizen := CitizenData.new()
	citizen.citizen_id = worker_id
	citizen.display_name = worker_id
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.HIRED
	citizen.profession = WorkerData.Profession.LABORER
	CitizenManager.citizens_by_id[worker_id] = citizen

	var worker := WorkerData.new()
	worker.worker_id = worker_id
	worker.display_name = worker_id
	worker.profession = WorkerData.Profession.LABORER
	WorkerDatabase.workers_by_id[worker_id] = worker
	_worker_ids.append(worker_id)
	return worker


func _get_citizen(worker_id: String) -> CitizenData:
	return CitizenManager.get_citizen(worker_id)


func _find_worker_button(
	assignment: WorkshopWorkerAssignmentUI,
	worker_id: String
) -> Button:
	for child in assignment.worker_list.get_children():
		if child is Button and str(child.get_meta("worker_id", "")) == worker_id:
			return child as Button
	return null


func _save_guard_screenshot() -> void:
	var temp_directory: String = OS.get_environment("TEMP")
	if temp_directory.is_empty():
		push_warning("TEMP is unavailable; discard-guard screenshot was skipped.")
		return

	var screenshot_path: String = temp_directory.path_join(
		"tip-workshop-assignment-discard.png"
	)
	var screenshot: Image = get_viewport().get_texture().get_image()
	var save_result: Error = screenshot.save_png(screenshot_path)
	_expect(
		save_result == OK,
		"Discard-guard screenshot must save to TEMP."
	)
	if save_result == OK:
		print("Discard guard screenshot: ", screenshot_path)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
