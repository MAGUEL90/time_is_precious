class_name JobBoardUI extends CanvasLayer

signal closed

@onready var applicant_list: ItemList = $Root/Center/Window/Margin/MainVBox/ApplicantList
@onready var empty_state_label: Label = $Root/Center/Window/Margin/MainVBox/ApplicantList/EmptyStateLabel
@onready var feedback_label: Label = $Root/Center/Window/Margin/MainVBox/FeedbackLabel
@onready var hire_button: Button = $Root/Center/Window/Margin/MainVBox/Actions/HireButton
@onready var close_button: Button = $Root/Center/Window/Margin/MainVBox/Actions/CloseButton


var applicants: Array[CitizenData] = []
@onready var treasury_label: Label = $Root/Center/Window/Margin/MainVBox/TreasuryLabel
@onready var deposit_amount: SpinBox = $Root/Center/Window/Margin/MainVBox/Deposit/Amount
@onready var deposit_button: Button = $Root/Center/Window/Margin/MainVBox/Deposit/DepositButton

# Lifecycle and visibility

func _ready() -> void:
	visible = false
	# ItemList has no gameplay-theme variation; set its local font explicitly.
	applicant_list.add_theme_font_override("font", preload("res://assets/font/pixel_rpg.ttf"))
	applicant_list.add_theme_font_size_override("font_size", 6)
	_style_deposit_amount()
	hire_button.pressed.connect(_on_hire_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)
	deposit_button.pressed.connect(_deposit)
	applicant_list.item_selected.connect(func(_index: int): _refresh_quote())

func _style_deposit_amount() -> void:
	# SpinBox renders its number through a child LineEdit, not its own font overrides.
	var field: LineEdit = deposit_amount.get_line_edit()
	field.add_theme_font_override("font", preload("res://assets/font/pixel_rpg.ttf"))
	field.add_theme_font_size_override("font_size", 6)
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var arrow: Texture2D = preload("res://assets/ui/ui_icon/right_arrow_icon.png")
	for direction: String in ["up", "down"]:
		var pixels: Image = arrow.get_image()
		pixels.rotate_90(COUNTERCLOCKWISE if direction == "up" else CLOCKWISE)
		var icon: ImageTexture = ImageTexture.create_from_image(pixels)
		for suffix: String in ["", "_hover", "_pressed"]:
			deposit_amount.add_theme_icon_override(direction + suffix, icon)
		pixels.adjust_bcs(0.5, 1.0, 0.0)
		deposit_amount.add_theme_icon_override(direction + "_disabled", ImageTexture.create_from_image(pixels))

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
		var item_index: int = applicant_list.add_item("%s, %s, SAT %d%%, %s" % [
			applicant_data.display_name,
			_get_profession_name(applicant_data.profession),
			roundi(applicant_data.satisfaction * 100.0),
			_rate_text(applicant_data.profession)
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
		applicant_data.citizen_id
	)

	if hired_worker == null:
		_refresh_applicants()
		feedback_label.text = "Hiring unavailable: check hours, rate and applicant."
		return

	var success_text: String = "Hired %s. Start day %d, 08:00 after payment." % [
		hired_worker.get_resolved_display_name(), hired_worker.payroll_start_day]

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

func _rate_text(profession: WorkerData.Profession) -> String:
	var rate: int = WorkerDatabase.get_onboarding_rate(profession)
	return "%d / 7 days" % rate if rate > 0 else "Rate TBD"

func _refresh_quote() -> void:
	var day: int = TimeComponentManager.current_day + 1
	var quote: Dictionary = WorkerDatabase.get_payroll_quote(day)
	var selected: PackedInt32Array = applicant_list.get_selected_items()
	var rate: int = -1
	if not selected.is_empty() and selected[0] < applicants.size():
		rate = WorkerDatabase.get_onboarding_rate(applicants[selected[0]].profession)
		quote.total += maxi(0, rate)
		quote.count += 1
		quote.unpriced = quote.unpriced or rate <= 0
	var wallet: int = Inventory.items.get("shekel", 0)
	var treasury: int = CityStockManager.treasury_shekel
	treasury_label.text = "Wallet %d | City %d | Next 08:00: %s (%d workers)\nShortfall: %s | With selected hire; all paid or all wait" % [
		wallet, treasury, "TBD" if quote.unpriced else str(quote.total), quote.count,
		"TBD" if quote.unpriced else str(maxi(0, quote.total - treasury))]
	deposit_button.disabled = wallet <= 0 or treasury >= CityStockManager.MAX_SHEKEL
	deposit_amount.max_value = maxi(1, mini(wallet, CityStockManager.MAX_SHEKEL - treasury))
	hire_button.disabled = rate <= 0 or not WorkerDatabase.is_job_board_open()
	feedback_label.text = "Open 08:00–17:00. Hire starts tomorrow 08:00 after payment." if WorkerDatabase.is_job_board_open() else "Closed. Hiring opens 08:00–17:00."

func _deposit() -> void:
	var deposited: bool = CityStockManager.deposit_wallet_shekel(int(deposit_amount.value))
	_refresh_quote()
	feedback_label.text = "Deposited. Waiting workers retry tomorrow at 08:00." if deposited else "Deposit unavailable: check wallet and city capacity."
