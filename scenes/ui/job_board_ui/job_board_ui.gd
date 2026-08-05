class_name JobBoardUI extends CanvasLayer

signal closed

@onready var applicant_list: ItemList = $Root/Center/Window/Margin/MainVBox/ApplicantList
@onready var feedback_label: Label = $Root/Center/Window/Margin/MainVBox/FeedbackLabel
@onready var hire_button: Button = $Root/Center/Window/Margin/MainVBox/Actions/HireButton
@onready var close_button: Button = $Root/Center/Window/Margin/MainVBox/Actions/CloseButton

var applicants: Array[CitizenData] = []
var daily_wage: int = 1

# Lifecycle and visibility

func _ready() -> void:
	visible = false
	hire_button.pressed.connect(_on_hire_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func open(default_daily_wage: int = 1) -> void:
	daily_wage = maxi(0, default_daily_wage)
	get_tree().paused = true
	visible = true
	_refresh_applicants()

func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()

# Applicant list

func _refresh_applicants() -> void:
	applicant_list.clear()
	applicants = CitizenManager.get_all_applicants()

	for applicant_data in applicants:
		applicant_list.add_item("%s | %s | SAT %d%% | %d/day" % [
			applicant_data.display_name,
			_get_profession_name(applicant_data.profession),
			roundi(applicant_data.satisfaction * 100.0),
			daily_wage
		])

	hire_button.disabled = applicants.is_empty()

	if applicants.is_empty():
		feedback_label.text = "No applicants available."
		return

	applicant_list.select(0)
	feedback_label.text = "Select an applicant to hire."

# Actions

func _on_hire_button_pressed() -> void:
	var selected_indices: PackedInt32Array = applicant_list.get_selected_items()

	if selected_indices.is_empty():
		feedback_label.text = "Select an applicant first."
		return

	var selected_index: int = selected_indices[0]

	if selected_index < 0 or selected_index >= applicants.size():
		feedback_label.text = "Applicant selection is no longer valid."
		_refresh_applicants()
		return

	var applicant_data: CitizenData = applicants[selected_index]
	var hired_worker: WorkerData = WorkerDatabase.hire_applicant(
		applicant_data.citizen_id,
		daily_wage
	)

	if hired_worker == null:
		_refresh_applicants()
		feedback_label.text = "Applicant is no longer available."
		return

	var success_text: String = "Hired %s for %d/day." % [
		hired_worker.get_resolved_display_name(),
		hired_worker.wage_shekel_per_day
	]

	_refresh_applicants()
	feedback_label.text = success_text

func _on_close_button_pressed() -> void:
	close()

# Display helpers

func _get_profession_name(
	profession: WorkerData.Profession
) -> String:
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
			return "Unassigned"
