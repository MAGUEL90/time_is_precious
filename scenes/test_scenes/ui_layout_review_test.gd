extends Node

var failures: int = 0
var captures: String

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _capture(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(captures.path_join(name + ".png"))

func _run() -> void:
	captures = OS.get_environment("TIP_MVP_CAPTURE_DIR")
	if captures.is_empty():
		captures = OS.get_environment("TEMP")
	TimeComponentManager.set_process(false)
	var ids: Array[String] = []
	for index in range(8):
		var worker := WorkerData.new()
		worker.worker_id = "ui_review_%d" % index
		worker.display_name = "Workshop Laborer With A Long Name" if index == 0 else "Worker %d" % index
		WorkerDatabase.workers_by_id[worker.worker_id] = worker
		ids.append(worker.worker_id)
	var assignment = preload("res://scenes/ui/workshop_worker_assignment_ui/workshop_worker_assignment_ui.tscn").instantiate()
	add_child(assignment)
	assignment.open_assignment(ids, 8)
	await _capture("review-eight-workers")
	var window: Control = assignment.get_node("Root/Center/TextureWindow")
	var main: Control = window.get_node("Margin/MainVBox")
	_expect(get_viewport().get_visible_rect().encloses(window.get_global_rect()), "Eight-worker window fits the screen.")
	_expect(window.get_global_rect().grow(-12).encloses(main.get_global_rect()), "Eight-worker content stays inside the frame padding.")
	assignment._on_worker_info_pressed(ids[0], WorkerDatabase.get_worker_data(ids[0]))
	await _capture("review-worker-long-name")
	var info: Control = assignment.get_node("Root/WorkerInfoLayer/Center/InfoWindow")
	_expect(info.get_global_rect().grow(-10).encloses(info.get_node("Margin/InfoVBox").get_global_rect()), "Long worker details stay inside the popup frame.")
	WorkerDatabase.get_worker_data(ids[0]).display_name = "Worksite Hauler"
	assignment._on_worker_info_pressed(ids[0], WorkerDatabase.get_worker_data(ids[0]))
	await _capture("review-worker-compact-info")
	assignment._hide_worker_info()
	assignment._open_worker_selection(0)
	await _capture("review-worker-roster")
	assignment.free()
	get_tree().paused = false
	var transfer = preload("res://scenes/ui/item_transfer_ui/item_transfer_ui.tscn").instantiate()
	add_child(transfer)
	transfer.open_transfer("Deposit Materials", {"wood_log": 24, "clay_lump": 24, "reed_bundle": 24, "straw_bundle": 24, "water_jar": 24}, "Deposit")
	await _capture("review-item-transfer")
	_expect(get_viewport().get_visible_rect().encloses(transfer.get_node("Root/Center/Window").get_global_rect()), "Transfer window fits the screen.")
	transfer.free()
	get_tree().paused = false
	var progress = preload("res://scenes/ui/work_progress_ui/work_progress_ui.tscn").instantiate()
	add_child(progress)
	progress.open_panel()
	await _capture("review-progress-empty")
	progress.close_panel()
	progress.free()
	var board = preload("res://scenes/ui/job_board_ui/job_board_ui.tscn").instantiate()
	add_child(board)
	board.open()
	await _capture("review-job-board-empty")
	_expect(board.hire_button.disabled, "Empty applicant list keeps Hire disabled.")
	board.close()
	board.free()
	var storage = preload("res://scenes/ui/workshop_storage_menu_ui/workshop_storage_menu_ui.tscn").instantiate()
	add_child(storage)
	storage.open_menu(WorkShopStorage.get_storage_state())
	await _capture("review-storage-empty")
	var storage_window: Control = storage.get_node("Root/Center/TextureWindow")
	var storage_content: Control = storage_window.get_node("Margin/MainVBox")
	_expect(get_viewport().get_visible_rect().encloses(storage_window.get_global_rect()), "Storage window fits the viewport.")
	_expect(storage_window.get_global_rect().grow(-16).encloses(storage_content.get_global_rect()), "Storage title and footer stay inside the frame padding.")
	storage.free()
	get_tree().paused = false
	print("UILayoutReviewTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
