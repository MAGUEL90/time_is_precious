class_name WorkshopJobUI extends CanvasLayer

signal start_job_requested(job_data: JobData, worker_ids: Array[String], work_days: int)
signal back_requested(worker_ids: Array[String])
signal cancelled()

@onready var status_label: Label = $Root/Center/Window/Margin/MainVBox/StatusLabel
@onready var job_label: Label = $Root/Center/Window/Margin/MainVBox/JobLabel
@onready var requirement_label: Label = $Root/Center/Window/Margin/MainVBox/RequirementLabel
@onready var back_button: Button = $Root/Center/Window/Margin/MainVBox/Footer/BackButton
@onready var start_button: Button = $Root/Center/Window/Margin/MainVBox/Footer/StartButton
@onready var close_button: Button = $Root/Center/Window/Margin/MainVBox/Header/CloseButton
@onready var confirm_discard_panel: PanelContainer = $Root/Center/Window/Margin/MainVBox/ConfirmDiscardPanel
@onready var keep_button: Button = $Root/Center/Window/Margin/MainVBox/ConfirmDiscardPanel/ConfirmMargin/ConfirmVBox/ConfirmButtons/KeepButton
@onready var discard_button: Button = $Root/Center/Window/Margin/MainVBox/ConfirmDiscardPanel/ConfirmMargin/ConfirmVBox/ConfirmButtons/DiscardButton

var current_workshop: Node = null
var assigned_worker_ids: Array[String] = ["", ""]
var work_days: int = 1
var job_started: bool = false

const MUDBRICK_JOB: JobData = preload("res://resources/job_data/mudbrick_make.tres")
const MIN_WORKER_COUNT: int = 1

# Setup / Public API

func _ready() -> void:
	visible = false
	confirm_discard_panel.visible = false
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)
	close_button.pressed.connect(_on_close_pressed)
	keep_button.pressed.connect(_on_keep_pressed)
	discard_button.pressed.connect(_on_discard_pressed)

func open_job(workshop: WorkShop, worker_ids: Array[String]) -> void:
	job_started = false
	confirm_discard_panel.visible = false
	current_workshop = workshop
	assigned_worker_ids = worker_ids.duplicate(true)
	work_days = 1
	visible = true
	get_tree().paused = true

	status_label.text = "Workers: %d | Minimum: %d" % [assigned_worker_ids.size(), MIN_WORKER_COUNT]
	job_label.text = MUDBRICK_JOB.display_name
	_refresh_start_state()

func show_start_result(success: bool, message: String) -> void:
	requirement_label.text = message
	job_started = success
	start_button.disabled = success
	back_button.disabled = success

	if not success:
		start_button.disabled = not _get_requirement_message().is_empty()

# Button callbacks

func _on_start_pressed() -> void:
	start_button.disabled = true
	back_button.disabled = true
	start_job_requested.emit(MUDBRICK_JOB, assigned_worker_ids.duplicate(true), work_days)

func _on_back_pressed() -> void:
	visible = false
	get_tree().paused = false
	back_requested.emit(assigned_worker_ids.duplicate(true))
	queue_free()

func _on_close_pressed() -> void:
	if not job_started and _has_worker_draft():
		_show_discard_guard()
		return

	_finish_close()

func _on_keep_pressed() -> void:
	confirm_discard_panel.visible = false
	_set_main_controls_disabled(false)
	_refresh_start_state()

func _on_discard_pressed() -> void:
	_finish_close()

# Start job state

func _refresh_start_state() -> void:
	var messages: Array[String] = _get_requirement_message()
	start_button.disabled = not messages.is_empty()

	if messages.is_empty():
		requirement_label.text = "Requirements met"
	else:
		var text: String = ""
		for message in messages:
			if not text.is_empty():
				text += "\n"
			text += "- " + message

		requirement_label.text = text

# Discard guard

func _show_discard_guard() -> void:
	confirm_discard_panel.visible = true
	close_button.release_focus()
	back_button.release_focus()
	start_button.release_focus()
	_set_main_controls_disabled(true)

func _set_main_controls_disabled(disabled: bool) -> void:
	close_button.disabled = disabled
	back_button.disabled = disabled
	start_button.disabled = disabled

	if disabled:
		close_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		start_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		close_button.mouse_filter = Control.MOUSE_FILTER_STOP
		back_button.mouse_filter = Control.MOUSE_FILTER_STOP
		start_button.mouse_filter = Control.MOUSE_FILTER_STOP

# State checks

func _has_worker_draft() -> bool:
	for worker_id in assigned_worker_ids:
		if not worker_id.strip_edges().is_empty():
			return true
	return false

func _has_minimum_workers() -> bool:
	return assigned_worker_ids.size() >= MIN_WORKER_COUNT

func _has_matching_worker(job: JobData) -> bool:
	for worker_id in assigned_worker_ids:
		var worker_data := WorkerDatabase.get_worker_data(worker_id)
		if worker_data != null and worker_data.profession == job.requirement_profession:
			return true
	return false

# Requirement messages

func _get_requirement_message() -> Array[String]:
	var messages: Array[String] = []

	if not _has_minimum_workers():
		messages.append("Assign at least %d worker." % MIN_WORKER_COUNT)
	elif not _has_matching_worker(MUDBRICK_JOB):
		messages.append("Needs a %s worker." % _get_profession_name(MUDBRICK_JOB.requirement_profession))

	for item_id in MUDBRICK_JOB.inputs.keys():
		var required_amount: int = int(MUDBRICK_JOB.inputs[item_id])
		var stored_amount: int = int(WorkShopStorage.items.get(item_id, 0))

		if stored_amount < required_amount:
			messages.append("Needs %s x %d. Stored: %d." % [
				_get_item_display_name(item_id),
				required_amount,
				stored_amount
			])

	return messages

func _get_item_display_name(item_id: String) -> String:
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if item_data == null:
		return item_id

	return item_data.display_name

func _get_profession_name(profession: int) -> String:
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

# Exit helpers

func _finish_close() -> void:
	visible = false
	get_tree().paused = false
	cancelled.emit()
	queue_free()
