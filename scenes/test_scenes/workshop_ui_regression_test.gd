extends Node

var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var production = load("res://scenes/ui/workshop_production_ui/workshop_production_ui.tscn").instantiate()
	add_child(production)
	var card = load("res://scenes/ui/work_order_card/work_order_card.tscn").instantiate()
	card.work_order_id = "mudbrick_make"
	card.card_title = "Shape Wet Mudbricks"
	production.work_order_grid.add_child(card)
	card.pressed.connect(production._on_card_pressed.bind(card))
	card.details_requested.connect(production._on_card_details_requested.bind(card))
	card.mouse_entered.emit()
	_expect(card.selection_frame.visible, "Hover must show the work selector.")
	card.pressed.emit()
	_expect(production.selected_card == card, "Click must select work.")
	_expect(not production.production_info_panel.visible, "Card click must not open details.")
	var info: Button = card.get_node("InfoButton")
	_expect(info.mouse_filter == Control.MOUSE_FILTER_STOP, "Info clicks must not pass to the card.")
	_expect(info.has_theme_color_override("icon_hover_color") and info.has_theme_color_override("icon_pressed_color"), "Info needs hover and pressed feedback.")
	info.pressed.emit()
	_expect(production.production_info_panel.visible, "Info click must open details.")
	production.production_info_panel.get_node("MarginContainer/DetailVBox/Header/CloseButton").pressed.emit()
	_expect(not production.production_info_panel.visible, "Detail close must hide the panel.")
	await get_tree().process_frame
	production.free()

	var worker := WorkerData.new()
	worker.worker_id = "ui_regression_worker"
	worker.profession = WorkerData.Profession.LABORER
	worker.start_work("ui_order", "mudbrick_make")
	WorkerDatabase.workers_by_id[worker.worker_id] = worker
	var assignment = load("res://scenes/ui/workshop_worker_assignment_ui/workshop_worker_assignment_ui.tscn").instantiate()
	add_child(assignment)
	var worker_ids: Array[String] = [worker.worker_id]
	assignment.open_assignment(worker_ids, 2, WorkerData.Profession.LABORER)
	_expect(assignment._get_selected_worker_ids().is_empty(), "Reopening must exclude a busy worker.")
	_expect(assignment.next_button.disabled, "Next must be disabled without an available worker.")
	worker.finish_work("ui_order")
	assignment.open_assignment(worker_ids, 2, WorkerData.Profession.LABORER)
	_expect(not assignment.next_button.disabled, "Idle assigned worker must allow Next.")
	_expect(assignment.slot_grid.get_child(0).get_node_or_null("InfoButton") == null, "Overview must not have an info button.")
	assignment._open_worker_selection(1)
	var candidate: Button = assignment.worker_list.get_child(0)
	_expect(candidate.get_node_or_null("InfoButton") != null, "Worker selection must have an info button.")
	candidate.get_node("InfoButton").pressed.emit()
	_expect(assignment.worker_info_layer.visible, "Worker info click must open its panel.")
	assignment._hide_worker_info()
	assignment._remove_worker_from_slot(0)
	_expect(assignment.next_button.disabled, "Removing the last worker must disable Next.")
	assignment.free()
	WorkerDatabase.workers_by_id.erase(worker.worker_id)
	get_tree().paused = false

	var job = load("res://scenes/ui/workshop_job_ui/workshop_job_ui.tscn").instantiate()
	add_child(job)
	_expect(job.close_button is TextureButton, "Workshop Job must use the shared graphical close button.")
	_expect(job.close_button.texture_hover != null and job.close_button.texture_pressed != null, "Close needs hover and pressed textures.")
	job.free()
	print("WorkshopUIRegressionTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
