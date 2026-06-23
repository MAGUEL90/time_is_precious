class_name WorkshopWorkerAssignmentUI extends CanvasLayer

signal assignment_next_requested(worker_ids: Array[String])
signal assignment_back_requested()
signal assignment_cancelled()

const GAMEPLAY_THEME: Theme = preload("res://resources/ui_gameplay_theme/ui_gameplay_theme.tres")

enum ExitIntent { NONE, BACK, CLOSE }

@onready var close_button: Button = $Root/Center/Window/Margin/MainVBox/Header/CloseButton
@onready var info_label: Label = $Root/Center/Window/Margin/MainVBox/InfoLabel
@onready var slot_grid: GridContainer = $Root/Center/Window/Margin/MainVBox/Body/AssignedPanel/SlotGrid
@onready var worker_list: VBoxContainer = $Root/Center/Window/Margin/MainVBox/Body/AvailablePanel/WorkerScroll/WorkerList
@onready var feedback_label: Label = $Root/Center/Window/Margin/MainVBox/FeedbackLabel
@onready var back_button: Button = $Root/Center/Window/Margin/MainVBox/Footer/BackButton
@onready var next_button: Button = $Root/Center/Window/Margin/MainVBox/Footer/NextButton
@onready var confirm_discard_panel: PanelContainer = $Root/Center/Window/Margin/MainVBox/ConfirmDiscardPanel
@onready var keep_button: Button = $Root/Center/Window/Margin/MainVBox/ConfirmDiscardPanel/ConfirmMargin/ConfirmVBox/ConfirmButtons/KeepButton
@onready var discard_button: Button = $Root/Center/Window/Margin/MainVBox/ConfirmDiscardPanel/ConfirmMargin/ConfirmVBox/ConfirmButtons/DiscardButton

var selected_worker_ids: Array[String] = ["", ""]
var max_worker_slots: int = 2
var active_slot_index: int = 0
var pending_exit_intent: int = ExitIntent.NONE

# Setup / Public API

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_cancel_pressed)
	back_button.pressed.connect(_on_back_pressed)
	next_button.pressed.connect(_on_next_pressed)
	keep_button.pressed.connect(_on_keep_pressed)
	discard_button.pressed.connect(_on_discard_pressed)

func open_assignment(current_worker_ids: Array[String], slot_count: int = 2) -> void:
	confirm_discard_panel.visible = false
	pending_exit_intent = ExitIntent.NONE

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
	info_label.text = "Assigned workers: %d / %d" % [_get_assigned_worker_count(), max_worker_slots]
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
		slot_button.custom_minimum_size = Vector2(150, 76)
		slot_button.theme = GAMEPLAY_THEME
		slot_button.theme_type_variation = &"HudShortcutButton"
		slot_button.alignment = HORIZONTAL_ALIGNMENT_CENTER

		var worker_id: String = selected_worker_ids[slot_index]
		if not worker_id.is_empty():
			var worker_data: WorkerData = WorkerDatabase.get_worker_data(worker_id)
			if worker_data != null:
				slot_button.text = "%s\n%s\nClick to clear" % [
					worker_data.display_name,
					_get_worker_profession_name(worker_data.profession)
				]
			else:
				slot_button.text = "Unknown Worker\nClick to clear"
		else:
			slot_button.text = "+\nEmpty Slot"

		slot_button.pressed.connect(_on_slot_pressed.bind(slot_index))
		slot_grid.add_child(slot_button)

	info_label.text = "Assigned workers: %d / %d" % [_get_assigned_worker_count(), max_worker_slots]

func _refresh_worker_list() -> void:
	for child in worker_list.get_children():
		child.queue_free()

	var worker_count: int = 0
	for worker in WorkerDatabase.get_all_workers():
		if not (worker is WorkerData):
			continue

		var worker_data: WorkerData = worker as WorkerData
		var worker_button: Button = Button.new()
		worker_button.custom_minimum_size = Vector2(240, 46)
		worker_button.theme = GAMEPLAY_THEME
		worker_button.theme_type_variation = &"HudShortcutButton"
		worker_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		worker_button.text = "%s | %s | %s" % [
			worker_data.display_name,
			_get_worker_profession_name(worker_data.profession),
			_get_worker_status_text(worker_data)
		]

		if selected_worker_ids.has(worker_data.worker_id):
			worker_button.disabled = true
			worker_button.text += " | Assigned"
		elif worker_data.is_working():
			worker_button.disabled = true
		else:
			worker_button.pressed.connect(_on_worker_selected.bind(worker_data.worker_id))

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

	if slot_index < selected_worker_ids.size():
		selected_worker_ids[slot_index] = ""
		feedback_label.text = "Worker slot cleared."
	else:
		feedback_label.text = "Choose a worker for slot %d." % (slot_index + 1)

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
	feedback_label.text = "Worker assigned."
	_refresh_slots()
	_refresh_worker_list()
	_refresh_next_state()

# Navigation callbacks

func _on_next_pressed() -> void:
	var assigned_ids: Array[String] = []
	for worker_id in selected_worker_ids:
		if not worker_id.is_empty():
			assigned_ids.append(worker_id)

	visible = false
	get_tree().paused = false
	assignment_next_requested.emit(assigned_ids)
	queue_free()

func _on_cancel_pressed() -> void:
	if _get_assigned_worker_count() > 0:
		_show_discard_guard(ExitIntent.CLOSE)
		return
	_finish_close()

func _on_back_pressed() -> void:
	if _get_assigned_worker_count() > 0:
		_show_discard_guard(ExitIntent.BACK)
		return
	_finish_back()

func _on_keep_pressed() -> void:
	pending_exit_intent = ExitIntent.NONE
	confirm_discard_panel.visible = false
	_set_main_controls_disabled(false)
	_refresh_slots()
	_refresh_worker_list()
	_refresh_next_state()
	feedback_label.text = "Choose an empty slot, then pick a worker"

func _on_discard_pressed() -> void:
	if pending_exit_intent == ExitIntent.BACK:
		_finish_back()
	elif pending_exit_intent == ExitIntent.CLOSE:
		_finish_close()

# Discard guard

func _show_discard_guard(exit_intent: int) -> void:
	pending_exit_intent = exit_intent
	confirm_discard_panel.visible = true
	_set_main_controls_disabled(true)
	feedback_label.text = "Confirm before leaving"

func _set_main_controls_disabled(disabled: bool) -> void:
	close_button.disabled = disabled
	back_button.disabled = disabled
	next_button.disabled = disabled

	if disabled:
		close_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		next_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		close_button.mouse_filter = Control.MOUSE_FILTER_STOP
		back_button.mouse_filter = Control.MOUSE_FILTER_STOP
		next_button.mouse_filter = Control.MOUSE_FILTER_STOP

	close_button.release_focus()
	back_button.release_focus()
	next_button.release_focus()
	_set_dynamic_button_disabled(disabled)

# UI state helpers

func _set_dynamic_button_disabled(disabled: bool) -> void:
	for child in slot_grid.get_children():
		if child is Button:
			var button: Button = child as Button
			button.disabled = disabled
			if disabled:
				button.mouse_filter = Control.MOUSE_FILTER_IGNORE
			else:
				button.mouse_filter = Control.MOUSE_FILTER_STOP
			button.release_focus()

	for child in worker_list.get_children():
		if child is Button:
			var button: Button = child as Button
			button.disabled = disabled
			if disabled:
				button.mouse_filter = Control.MOUSE_FILTER_IGNORE
			else:
				button.mouse_filter = Control.MOUSE_FILTER_STOP
			button.release_focus()

# Display helpers

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
