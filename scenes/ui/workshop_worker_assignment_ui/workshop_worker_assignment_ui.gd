class_name WorkshopWorkerAssignmentUI extends CanvasLayer

signal assignment_changed(worker_ids: Array[String])
signal assignment_next_requested(worker_ids: Array[String])
signal assignment_back_requested()
signal assignment_cancelled()

const GAMEPLAY_THEME: Theme = preload("res://resources/ui_gameplay_theme/ui_gameplay_theme.tres")

@onready var close_button: Button = $Root/Center/TextureWindow/Margin/MainVBox/Header/CloseButton
@onready var info_label: Label = $Root/Center/TextureWindow/Margin/MainVBox/InfoLabel
@onready var slot_grid: GridContainer = $Root/Center/TextureWindow/Margin/MainVBox/Body/AssignedPanel/SlotGrid
@onready var worker_list: VBoxContainer = $Root/Center/TextureWindow/Margin/MainVBox/Body/AvailablePanel/WorkerScroll/WorkerList
@onready var feedback_label: Label = $Root/Center/TextureWindow/Margin/MainVBox/FeedbackLabel
@onready var back_button: Button = $Root/Center/TextureWindow/Margin/MainVBox/Footer/BackButton
@onready var next_button: Button = $Root/Center/TextureWindow/Margin/MainVBox/Footer/NextButton

var selected_worker_ids: Array[String] = ["", ""]
var max_worker_slots: int = 2
var active_slot_index: int = 0

# Setup / Public API

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_cancel_pressed)
	back_button.pressed.connect(_on_back_pressed)
	next_button.pressed.connect(_on_next_pressed)

func open_assignment(current_worker_ids: Array[String], slot_count: int = 2) -> void:
	max_worker_slots = max(slot_count, 1)
	selected_worker_ids.clear()
	for i in range(max_worker_slots):
		selected_worker_ids.append("")

	for worker_id in current_worker_ids:
		if worker_id.strip_edges().is_empty():
			continue
		if not WorkerDatabase.has_worker_data(worker_id):
			continue

		var empty_slot_index: int = _get_first_empty_slot_index()
		selected_worker_ids[empty_slot_index] = worker_id

	active_slot_index = _get_first_empty_slot_index()
	feedback_label.text = "Choose an empty slot, then pick a worker."
	visible = true
	get_tree().paused = true
	_refresh_slots()
	_refresh_worker_list()
	_refresh_next_state()

# Slot and worker list UI

func _refresh_slots() -> void:
	for child in slot_grid.get_children():
		child.queue_free()

	for slot_index in range(max_worker_slots):
		var slot_button: Button = Button.new()
		slot_button.custom_minimum_size = Vector2(60, 36)
		slot_button.add_theme_font_size_override("font_size", 6)
		slot_button.clip_text = true
		slot_button.theme = GAMEPLAY_THEME
		slot_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_button.focus_mode = Control.FOCUS_NONE

		var worker_id: String = selected_worker_ids[slot_index]

		slot_button.theme_type_variation = &"HudShortcutButton"
		slot_button.toggle_mode = true
		slot_button.button_pressed = (
			slot_index == active_slot_index and worker_id.is_empty()
		)

		if not worker_id.is_empty():
			var worker_data: WorkerData = WorkerDatabase.get_worker_data(worker_id)
			if worker_data != null:
				var display_name: String = (
					worker_data.get_resolved_display_name()
				)
				var profession_name: String = (
					_get_worker_profession_name(worker_data.profession)
				)

				if display_name.to_lower() == profession_name.to_lower():
					slot_button.text = display_name
				else:
					slot_button.text = "%s\n%s" % [
						display_name,
						profession_name
					]
			else:
				slot_button.text = "Unknown Worker"
		else:
			slot_button.text = "+\nEmpty Slot"

		slot_button.pressed.connect(_on_slot_pressed.bind(slot_index))
		slot_grid.add_child(slot_button)

	_refresh_info_label()

func _refresh_worker_list() -> void:
	for child in worker_list.get_children():
		child.queue_free()

	var worker_count: int = 0
	for worker in WorkerDatabase.get_all_workers():
		if not (worker is WorkerData):
			continue

		var worker_data: WorkerData = worker as WorkerData
		var worker_button: Button = Button.new()
		worker_button.custom_minimum_size = Vector2(98, 23)
		worker_button.add_theme_font_size_override("font_size", 6)
		worker_button.clip_text = true
		worker_button.theme = GAMEPLAY_THEME
		worker_button.theme_type_variation = &"HudShortcutButton"
		worker_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		worker_button.focus_mode = Control.FOCUS_NONE

		var display_name: String = worker_data.get_resolved_display_name()
		var profession_name: String = _get_worker_profession_name(
			worker_data.profession
		)
		var status_text: String = _get_worker_status_text(worker_data)

		if selected_worker_ids.has(worker_data.worker_id):
			status_text = "Assigned"
			worker_button.disabled = true
		elif worker_data.is_working():
			status_text = "Working"
			worker_button.disabled = true
		else:
			worker_button.pressed.connect(_on_worker_selected.bind(worker_data.worker_id))

		if display_name.to_lower() == profession_name.to_lower():
			worker_button.text = "%s | %s" % [
				display_name,
				status_text
			]
		else:
			worker_button.text = "%s\n%s | %s" % [
				display_name,
				profession_name,
				status_text
			]

		worker_list.add_child(worker_button)
		worker_count += 1

	if worker_count == 0:
		var empty_label: Label = Label.new()
		empty_label.theme = GAMEPLAY_THEME
		empty_label.theme_type_variation = &"HudLabelShortcut"
		empty_label.text = "No workers available."
		worker_list.add_child(empty_label)

func _refresh_next_state() -> void:
	next_button.disabled = _get_assigned_worker_count() <= 0

# Selection callbacks

func _on_slot_pressed(slot_index: int) -> void:
	active_slot_index = slot_index

	if slot_index < 0 or slot_index >= selected_worker_ids.size():
		return

	if selected_worker_ids[slot_index].is_empty():
		feedback_label.text = "Choose a worker for this slot."
	else:
		selected_worker_ids[slot_index] = ""
		feedback_label.text = "Worker unassigned."
		assignment_changed.emit(_get_selected_worker_ids())

	_refresh_slots()
	_refresh_worker_list()
	_refresh_next_state()

func _on_worker_selected(worker_id: String) -> void:
	if worker_id.strip_edges().is_empty():
		return
	if selected_worker_ids.has(worker_id):
		return
	if not selected_worker_ids[active_slot_index].is_empty():
		feedback_label.text = "Choose an empty slot."
		return

	if active_slot_index < 0 or active_slot_index >= selected_worker_ids.size():
		return

	selected_worker_ids[active_slot_index] = worker_id
	assignment_changed.emit(_get_selected_worker_ids())
	feedback_label.text = "Worker assigned. Click the slot to remove."
	_refresh_slots()
	_refresh_worker_list()
	_refresh_next_state()

# Navigation callbacks

func _on_next_pressed() -> void:
	var assigned_ids: Array[String] = _get_selected_worker_ids()

	visible = false
	get_tree().paused = false
	assignment_next_requested.emit(assigned_ids)
	queue_free()

func _on_cancel_pressed() -> void:
	_finish_close()

func _on_back_pressed() -> void:
	_finish_back()

# Display helpers

func _refresh_info_label() -> void:
	var total_workers: int = WorkerDatabase.get_all_workers().size()

	info_label.text = "Assigned: %d / %d | Total Workers: %d" % [
		_get_assigned_worker_count(),
		max_worker_slots,
		total_workers
	]

func _get_worker_status_text(worker_data: WorkerData) -> String:
	if worker_data.is_working():
		return "Working"
	return "Idle"

func _get_worker_profession_name(profession: WorkerData.Profession) -> String:
	match profession:
		WorkerData.Profession.LABORER:
			return "Laborer"
		WorkerData.Profession.CRAFTER:
			return "Crafter"
		WorkerData.Profession.HAULER:
			return "Hauler"
		WorkerData.Profession.FARMER:
			return "Farmer"
		WorkerData.Profession.SCAVENGER:
			return "Scavenger"
		_:
			return "Unknown"

func _get_selected_worker_ids() -> Array[String]:
	var worker_ids: Array[String] = []

	for worker_id in selected_worker_ids:
		if not worker_id.is_empty():
			worker_ids.append(worker_id)

	return worker_ids

func _get_assigned_worker_count() -> int:
	var count: int = 0
	for worker_id in selected_worker_ids:
		if not worker_id.is_empty():
			count += 1

	return count

func _get_first_empty_slot_index() -> int:
	for slot_index in range(selected_worker_ids.size()):
		if selected_worker_ids[slot_index].is_empty():
			return slot_index

	return 0

# Exit helpers

func _finish_back() -> void:
	visible = false
	get_tree().paused = false
	assignment_back_requested.emit()
	queue_free()

func _finish_close() -> void:
	visible = false
	get_tree().paused = false
	assignment_cancelled.emit()
	queue_free()
