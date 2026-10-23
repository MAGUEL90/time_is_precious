class_name JobBoardUI extends CanvasLayer

signal closed

@onready var applicant_list: ItemList = $Root/Center/Window/Margin/MainVBox/ApplicantList
@onready var empty_state_label: Label = $Root/Center/Window/Margin/MainVBox/ApplicantList/EmptyStateLabel
@onready var feedback_label: Label = $Root/Center/Window/Margin/MainVBox/FeedbackLabel
@onready var hire_button: Button = $Root/Center/Window/Margin/MainVBox/Actions/HireButton
@onready var close_button: Button = $Root/Center/Window/Margin/MainVBox/Actions/CloseButton
@onready var contract_days_option: OptionButton = $Root/Center/Window/Margin/MainVBox/ContractRow/ContractDaysOption


var applicants: Array[CitizenData] = []
@onready var quote_label: Label = $Root/Center/Window/Margin/MainVBox/QuoteLabel

# Lifecycle and visibility

func _ready() -> void:
	visible = false
	# ItemList has no gameplay-theme variation; set its local font explicitly.
	applicant_list.add_theme_font_override("font", preload("res://assets/font/pixel_rpg.ttf"))
	applicant_list.add_theme_font_size_override("font_size", 6)
	for days: int in WorkerDatabase.CONTRACT_DAYS:
		contract_days_option.add_item("%d days" % days, days)
	contract_days_option.select(0)
	hire_button.pressed.connect(_on_hire_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)
	applicant_list.item_selected.connect(func(_index: int): _refresh_quote())
	contract_days_option.item_selected.connect(func(_index: int): _refresh_quote())

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func open(_default_daily_wage: int = 1) -> void:
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
		var item_index: int = applicant_list.add_item("%s | %s" % [
			applicant_data.display_name,
			_get_profession_name(applicant_data.profession)
		])
		applicant_list.set_item_tooltip_enabled(item_index, false)

	var no_applicants: bool = applicants.is_empty()
	empty_state_label.visible = no_applicants
	hire_button.disabled = no_applicants or not WorkerDatabase.is_job_board_open()

	if no_applicants:
		_refresh_quote()
		return

	applicant_list.select(0)
	_refresh_quote()

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
		1,
		_selected_contract_days()
	)

	if hired_worker == null:
		_refresh_applicants()
		feedback_label.text = "Hiring failed: check wallet and applicant availability."
		return

	var success_text: String = "Hired. Paid through Day %d." % hired_worker.payroll_paid_until_day

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

func _selected_contract_days() -> int:
	if contract_days_option.item_count == 0:
		return 3
	return contract_days_option.get_selected_id()

func _refresh_quote() -> void:
	var selected: PackedInt32Array = applicant_list.get_selected_items()
	var price: int = -1
	var days: int = _selected_contract_days()
	if not selected.is_empty() and selected[0] < applicants.size():
		price = WorkerDatabase.get_contract_price(applicants[selected[0]].profession, days)
	if selected.is_empty() or selected[0] >= applicants.size():
		quote_label.text = "Select an applicant to see the package price."
	elif price > 0:
		quote_label.text = "%d-day prepaid: %d Shekel from your wallet" % [days, price]
	else:
		quote_label.text = "Package price unavailable for this profession."
	hire_button.disabled = price <= 0 or not WorkerDatabase.is_job_board_open()
	feedback_label.text = "Today's remaining time + %d full days starting tomorrow." % days if WorkerDatabase.is_job_board_open() else "Closed | Opens 08:00"
