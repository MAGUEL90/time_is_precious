extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	TimeComponentManager.is_paused = true
	var content = preload("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	await get_tree().process_frame
	var state = content.get_node("YSortWorld/WorkshopPlot").construction
	var board = content.get_node("YSortWorld/InitialWorksites/JobBoard")
	var ui = preload("res://scenes/ui/job_board_ui/job_board_ui.tscn").instantiate()
	add_child(ui)
	ui.open(board.default_daily_wage)
	print("ROSTER BEFORE HIRE: ", state.get_worker_options())
	var starts_empty: bool = state.get_worker_options().is_empty()
	for applicant in ui.applicants:
		print("JOB BOARD APPLICANT: ", applicant.citizen_id, " / ", applicant.display_name)
	var target: int = -1
	for index in range(ui.applicants.size()):
		if ui.applicants[index].citizen_id == "initial_workshop_laborer":
			target = index
	if target < 0:
		push_error("Initial applicant missing")
		get_tree().quit(1)
		return
	ui.applicant_list.select(target)
	ui.hire_button.pressed.emit()
	print("ROSTER AFTER HIRE: ", state.get_worker_options())
	var found: bool = false
	for option in state.get_worker_options():
		if option.id == "initial_workshop_laborer":
			found = option.available and option.name == "Workshop Laborer"
	var no_longer_applicant: bool = true
	for applicant in ui.applicants:
		if applicant.citizen_id == "initial_workshop_laborer":
			no_longer_applicant = false
	var hired_worker = WorkerDatabase.get_worker_data("initial_workshop_laborer")
	var only_hired: bool = state.get_worker_options().size() == 1
	ui.close()
	content.free()
	content = preload("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	await get_tree().process_frame
	state = content.get_node("YSortWorld/WorkshopPlot").construction
	var reload_preserves: bool = state.get_worker_options().size() == 1 and WorkerDatabase.get_worker_data("initial_workshop_laborer") == hired_worker
	var dismissed: bool = WorkerDatabase.dismiss_worker("initial_workshop_laborer")
	var dismissal_synced: bool = dismissed and state.get_worker_options().is_empty()
	var ok: bool = starts_empty and found and no_longer_applicant and only_hired and reload_preserves and dismissal_synced
	print("WorkshopHiringRosterAudit: ", "PASS" if ok else "FAIL")
	ui.close()
	get_tree().quit(0 if ok else 1)
