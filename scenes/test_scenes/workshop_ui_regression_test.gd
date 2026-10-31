extends Node

var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_check_back_navigation_controls()
	_check_storage_presentation()
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
	production.production_info_panel.get_node("CloseButton").pressed.emit()
	_expect(not production.production_info_panel.visible, "Detail close must hide the panel.")
	await get_tree().process_frame
	production.queue_free()

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
	assignment._open_worker_selection(0)
	var busy_candidate: Button = assignment.worker_list.get_child(0)
	_expect(busy_candidate.modulate == assignment.WORKING_CARD_COLOR and busy_candidate.disabled, "Working worker remains unavailable and has the red activity tint.")
	worker.finish_work("ui_order")
	assignment.open_assignment(worker_ids, 2, WorkerData.Profession.LABORER)
	_expect(not assignment.next_button.disabled, "Idle assigned worker must allow Next.")
	_expect(assignment.slot_grid.get_child(0).get_node_or_null("InfoButton") == null, "Overview must not have an info button.")
	assignment._open_worker_selection(1)
	var candidate: Button = assignment.worker_list.get_child(0)
	_expect(candidate.modulate == Color.WHITE, "Idle worker returns to the normal card color.")
	_expect(candidate.get_node_or_null("InfoButton") != null, "Worker selection must have an info button.")
	candidate.get_node("InfoButton").pressed.emit()
	_expect(assignment.worker_info_layer.visible, "Worker info click must open its panel.")
	assignment._hide_worker_info()
	assignment._remove_worker_from_slot(0)
	_expect(assignment.next_button.disabled, "Removing the last worker must disable Next.")
	assignment.queue_free()
	WorkerDatabase.workers_by_id.erase(worker.worker_id)
	get_tree().paused = false

	var job = load("res://scenes/ui/workshop_job_ui/workshop_job_ui.tscn").instantiate()
	add_child(job)
	_expect(not job.close_button.visible, "Job review hides its duplicate graphical Close.")
	job.show_start_result(true, "Started")
	_expect(not job.back_button.disabled, "Back remains available after successful Start.")
	job.queue_free()
	# Let queued UI children and renderer resources finish cleanup before shutdown.
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	print("WorkshopUIRegressionTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)

func _check_back_navigation_controls() -> void:
	var cases: Array = [
		["res://scenes/ui/item_transfer_ui/item_transfer_ui.tscn", "Root/Center/Window/CloseButton", "Root/Center/Window/MarginContainer/MainVBox/Footer/BackButton"],
		["res://scenes/ui/workshop_storage_menu_ui/workshop_storage_menu_ui.tscn", "Root/Center/TextureWindow/CloseButton", "Root/Center/TextureWindow/Margin/MainVBox/Footer/BackButton"],
		["res://scenes/ui/workshop_production_ui/workshop_production_ui.tscn", "Root/Center/TextureWindow/CloseButton", "Root/Center/TextureWindow/Margin/MainVBox/Footer/BackButton"],
		["res://scenes/ui/workshop_worker_assignment_ui/workshop_worker_assignment_ui.tscn", "Root/Center/TextureWindow/CloseButton", "Root/Center/TextureWindow/Margin/MainVBox/OverviewPage/Footer/BackButton"],
		["res://scenes/ui/workshop_job_ui/workshop_job_ui.tscn", "Root/Center/TextureWindow/CloseButton", "Root/Center/TextureWindow/Margin/MainVBox/Footer/BackButton"],
		["res://scenes/ui/workshop_build_ui/workshop_build_ui.tscn", "Root/Center/TextureWindow/CloseButton", "Root/Center/TextureWindow/Margin/MainVBox/SelectionPage/Footer/BackButton"],
		["res://scenes/storage_destination/city_storage.tscn", "Close", "Margin/Content/Footer/Back"],
	]
	for entry: Array in cases:
		var panel: Node = load(entry[0]).instantiate()
		add_child(panel)
		_expect(not panel.get_node(entry[1]).visible and panel.get_node(entry[2]).visible, "Panel keeps Back and hides duplicate Close: " + entry[0])
		panel.queue_free()
	var top: WorkshopMenuUI = load("res://scenes/ui/workshop_menu_ui/workshop_menu_ui.tscn").instantiate()
	add_child(top)
	_expect(top.close_button.visible, "Top-level workshop keeps Close because it has no Back.")
	top.queue_free()
	var choice: ActionChoicePanel = load("res://scenes/ui/action_choice_panel/action_choice_panel.tscn").instantiate()
	add_child(choice)
	choice.setup("Output fee", "Pay", "Back", true)
	_expect(not choice.close_button.visible, "Dynamic Back confirmation has no duplicate Close.")
	choice.setup("Confirmation", "Confirm", "Cancel", true)
	_expect(choice.close_button.visible, "A confirmation without Back retains its configured Close.")
	choice.queue_free()

func _check_storage_presentation() -> void:
	var storage: WorkshopStorageMenuUI = load("res://scenes/ui/workshop_storage_menu_ui/workshop_storage_menu_ui.tscn").instantiate()
	add_child(storage)
	var state: Dictionary = {"used_capacity": 12.0, "max_capacity": 250.0}
	storage.refresh_storage(state)
	_expect(storage.capacity_icon.texture != null and storage.capacity_label.text == "12/250", "Capacity uses the storage icon and live values.")
	_expect(storage.empty_held_output.visible and not storage.held_grid.get_parent().visible, "No held lots show the no-output presentation.")
	_expect(storage.next_step_label.text.is_empty() and not storage.next_step_label.visible and not storage.feedback_label.visible, "Removed helper text stays hidden without active processing.")
	state["used_capacity"] = 40.0
	state["max_capacity"] = 300.0
	state["held_lots"] = [{"lot_id": "presentation_fixture", "items": {"stone": 1}}]
	storage.refresh_storage(state)
	_expect(storage.capacity_label.text == "40/300" and storage.capacity_icon.tooltip_text.is_empty() and storage.capacity_icon.accessibility_name == "Load 40 / 300", "Capacity refresh updates the numbers and accessible name without a tooltip.")
	for control: Control in storage.find_children("*", "Control", true, false):
		_expect(control.tooltip_text.is_empty(), "Workshop Storage control has no hover tooltip: " + str(control.get_path()))
	_expect(not storage.empty_held_output.visible and storage.held_grid.get_parent().visible, "Held output replaces the empty presentation.")
	storage.show_payment_result(false, "Fixture payment declined.", state)
	_expect(storage.feedback_label.visible and storage.feedback_label.text == "Fixture payment declined.", "Transaction errors remain visible after helper removal.")
	storage.queue_free()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
