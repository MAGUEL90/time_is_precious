class_name JobBoardUI extends CanvasLayer

signal closed

const CandidateCard = preload("res://scenes/ui/job_board_ui/job_board_candidate_card.gd")
const CARD_SCENE: PackedScene = preload("res://scenes/ui/job_board_ui/job_board_candidate_card.tscn")
const SCROLL_PANEL: Texture2D = preload("res://assets/ui/ui_panel/brown_panel_16x16.png")
const PIXEL_FONT: Font = preload("res://assets/font/pixel_rpg.ttf")
const CHECK_ICON: Texture2D = preload("res://assets/ui/ui_icon/checklist_icon.png")
const MAX_CONFIRM_NAME_LENGTH: int = 22

# Preserve the native selection/quote handles for existing callers.
@onready var applicant_list: ItemList = $Root/Center/Window/Margin/MainVBox/ApplicantList
@onready var candidate_scroll: ScrollContainer = $Root/Center/Window/Margin/MainVBox/CandidateScroll
@onready var candidate_rows: VBoxContainer = candidate_scroll.get_node("CandidateRows")
@onready var empty_state_panel: NinePatchRect = $Root/Center/Window/Margin/MainVBox/EmptyStatePanel
@onready var empty_state_label: Label = empty_state_panel.get_node("EmptyStateLabel")
@onready var feedback_label: Label = $Root/Center/Window/Margin/MainVBox/FeedbackLabel
@onready var quote_label: Label = $Root/Center/Window/Margin/MainVBox/QuoteRow/QuoteLabel
@onready var quote_icon: TextureRect = $Root/Center/Window/Margin/MainVBox/QuoteRow/QuoteIcon
@onready var quote_amount_label: Label = $Root/Center/Window/Margin/MainVBox/QuoteRow/QuoteAmount
@onready var wallet_label: Label = $Root/Center/Window/Margin/MainVBox/WalletRow/WalletLabel
@onready var confirmation_layer: Control = $Root/HireConfirmLayer
@onready var confirmation_panel: Control = $Root/HireConfirmLayer/ConfirmationPanel
@onready var selected_names_container: VBoxContainer = $Root/HireConfirmLayer/ConfirmationPanel/SelectedNamesScroll/SelectedNames
@onready var duration_button_container: VBoxContainer = $Root/HireConfirmLayer/ConfirmationPanel/DurationButtons
@onready var confirm_quote_label: Label = $Root/HireConfirmLayer/ConfirmationPanel/ConfirmQuoteRow/ConfirmQuoteLabel
@onready var confirm_quote_icon: TextureRect = $Root/HireConfirmLayer/ConfirmationPanel/ConfirmQuoteRow/ConfirmQuoteIcon
@onready var confirm_quote_amount_label: Label = $Root/HireConfirmLayer/ConfirmationPanel/ConfirmQuoteRow/ConfirmQuoteAmount
@onready var confirmation_feedback_label: Label = $Root/HireConfirmLayer/ConfirmationPanel/ConfirmationFeedbackLabel
@onready var confirm_hire_button: Button = $Root/HireConfirmLayer/ConfirmationPanel/ConfirmationActions/ConfirmHireButton
@onready var cancel_hire_button: Button = $Root/HireConfirmLayer/ConfirmationPanel/ConfirmationActions/CancelHireButton
@onready var close_confirmation_button: Button = $Root/HireConfirmLayer/ConfirmationPanel/CloseConfirmationButton
@onready var hire_button: Button = $Root/Center/Window/Margin/MainVBox/Actions/HireButton
@onready var close_button: TextureButton = $Root/Center/Window/CloseButton
@onready var refresh_timer: Timer = $RefreshTimer

var applicants: Array[CitizenData] = []
var cards: Array[CandidateCard] = []
var duration_buttons: Array[Button] = []
var confirmation_open: bool = false
var _hiring: bool = false
var _selected_contract_days_value: int = 3
var _pending_hire_ids: PackedStringArray = []
var _displayed_quote_ids: PackedStringArray = []
var _displayed_quote_total: int = -1
var _displayed_quote_days: int = -1
var _duration_button_group: ButtonGroup

func _ready() -> void:
	visible = false
	applicant_list.select_mode = ItemList.SELECT_MULTI
	_build_duration_buttons()
	_configure_confirmation_focus()
	hire_button.pressed.connect(_on_hire_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)
	confirm_hire_button.pressed.connect(_confirm_hire)
	cancel_hire_button.pressed.connect(func(): _cancel_confirmation())
	close_confirmation_button.pressed.connect(func(): _cancel_confirmation())
	close_button.texture_focused = close_button.texture_hover
	applicant_list.item_selected.connect(func(_index: int): _refresh_quote())
	refresh_timer.timeout.connect(_poll_applicants)
	_style_scrollbar()
	confirmation_layer.visible = false
	confirmation_panel.visible = false

func _build_duration_buttons() -> void:
	_duration_button_group = ButtonGroup.new()
	_duration_button_group.allow_unpress = false
	for days: int in WorkerDatabase.CONTRACT_DAYS:
		if days not in [3, 6, 9]:
			continue
		var button := Button.new()
		button.name = "ContractDays%dButton" % days
		button.text = "%d days" % days
		button.tooltip_text = "Choose a %d-day contract." % days
		button.toggle_mode = true
		button.button_group = _duration_button_group
		button.custom_minimum_size = Vector2(96, 17)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.theme_type_variation = &"HudShortcutButton"
		button.add_theme_font_size_override("font_size", 6)
		var focus_style := StyleBoxFlat.new()
		focus_style.draw_center = false
		focus_style.border_color = Color(1.0, 0.86, 0.46)
		focus_style.set_border_width_all(1)
		button.add_theme_stylebox_override("focus", focus_style)
		button.set_meta("contract_days", days)
		button.pressed.connect(_select_contract_days.bind(days))
		duration_button_container.add_child(button)
	duration_buttons.clear()
	for child: Node in duration_button_container.get_children():
		if child is Button:
			duration_buttons.append(child as Button)
	_select_contract_days(_selected_contract_days_value)

func _configure_confirmation_focus() -> void:
	var controls: Array[Control] = []
	controls.append_array(duration_buttons)
	controls.append_array([cancel_hire_button, confirm_hire_button, close_confirmation_button])
	for index: int in range(controls.size()):
		var control: Control = controls[index]
		var previous: NodePath = control.get_path_to(controls[(index - 1 + controls.size()) % controls.size()])
		var next: NodePath = control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = previous
		control.focus_next = next
		control.focus_neighbor_top = previous
		control.focus_neighbor_left = previous
		control.focus_neighbor_bottom = next
		control.focus_neighbor_right = next

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if confirmation_open:
			_cancel_confirmation()
		else:
			close()
		get_viewport().set_input_as_handled()

func open(_default_daily_wage: int = 1) -> void:
	get_tree().paused = true
	visible = true
	feedback_label.text = ""
	_cancel_confirmation(false)
	_refresh_applicants(false)
	refresh_timer.start()

func close() -> void:
	_cancel_confirmation(false)
	refresh_timer.stop()
	visible = false
	get_tree().paused = false
	closed.emit()

func _on_close_button_pressed() -> void:
	close()

func _ids(data: Array[CitizenData]) -> PackedStringArray:
	var result := PackedStringArray()
	for citizen: CitizenData in data:
		result.append(citizen.citizen_id)
	return result

func _poll_applicants() -> void:
	if not visible or _hiring:
		return
	var current: Array[CitizenData] = CitizenManager.get_all_applicants()
	if _ids(current) != _ids(applicants):
		_refresh_applicants()
	else:
		applicants = current
		_refresh_quote(false)

func _refresh_applicants(preserve_selection: bool = true) -> void:
	var keep_scroll: int = candidate_scroll.scroll_vertical if preserve_selection else 0
	var selected_ids := PackedStringArray()
	var selected: PackedInt32Array = applicant_list.get_selected_items()
	if preserve_selection:
		for index: int in selected:
			if index >= 0 and index < applicants.size():
				selected_ids.append(applicants[index].citizen_id)
	for card: CandidateCard in cards:
		candidate_rows.remove_child(card)
		card.queue_free()
	cards.clear()
	applicant_list.clear()
	applicants = CitizenManager.get_all_applicants()
	for citizen: CitizenData in applicants:
		var index: int = applicant_list.add_item("%s | %s" % [citizen.display_name, _get_profession_name(citizen.profession)])
		applicant_list.set_item_tooltip_enabled(index, false)
		var card: CandidateCard = CARD_SCENE.instantiate()
		candidate_rows.add_child(card)
		card.selection_toggled.connect(_on_card_toggled.bind(index))
		card.selection_button.focus_entered.connect(_on_card_focused.bind(card))
		cards.append(card)
		if selected_ids.has(citizen.citizen_id):
			applicant_list.select(index, false)
	if not preserve_selection and not applicants.is_empty():
		applicant_list.select(0)
	empty_state_panel.visible = applicants.is_empty()
	candidate_scroll.visible = not applicants.is_empty()
	_refresh_quote()
	_restore_scroll.call_deferred(keep_scroll)

func _restore_scroll(value: int) -> void:
	candidate_scroll.scroll_vertical = value

func _on_card_focused(card: CandidateCard) -> void:
	candidate_scroll.ensure_control_visible.call_deferred(card.selection_button)

func _on_card_toggled(checked: bool, index: int) -> void:
	# Checkboxes are independent; the backend commits the whole selection atomically.
	if checked:
		applicant_list.select(index, false)
	else:
		applicant_list.deselect(index)
	_refresh_quote()

func _selected_contract_days() -> int:
	return _selected_contract_days_value

func _select_contract_days(days: int) -> void:
	if days not in [3, 6, 9] or days not in WorkerDatabase.CONTRACT_DAYS:
		return
	_selected_contract_days_value = days
	for button: Button in duration_buttons:
		var selected: bool = int(button.get_meta("contract_days", -1)) == days
		button.set_pressed_no_signal(selected)
		button.icon = CHECK_ICON if selected else null
	confirmation_feedback_label.text = "" if confirmation_open else confirmation_feedback_label.text
	_refresh_quote(false)

func _refresh_quote(_reset_feedback: bool = true) -> void:
	var selected: PackedInt32Array = applicant_list.get_selected_items()
	var days: int = _selected_contract_days()
	var total: int = 0
	var valid: bool = not selected.is_empty()
	for i: int in range(cards.size()):
		var citizen: CitizenData = applicants[i]
		cards[i].show_applicant(citizen, WorkerDatabase.get_contract_price(citizen.profession, days), days, _get_profession_name(citizen.profession))
		cards[i].set_selected(selected.has(i))
	for index: int in selected:
		if index < 0 or index >= applicants.size():
			valid = false
			break
		var price: int = WorkerDatabase.get_contract_price(applicants[index].profession, days)
		if price <= 0 or total > 9223372036854775807 - price:
			valid = false
			break
		total += price
	if selected.is_empty():
		quote_label.text = "Select candidates to see total"
		quote_amount_label.text = ""
		quote_icon.visible = false
	elif valid:
		quote_label.text = "%d day%s · %d candidate%s · Total" % [days, "s" if days != 1 else "", selected.size(), "s" if selected.size() != 1 else ""]
		quote_amount_label.text = str(total)
		quote_icon.visible = true
	else:
		quote_label.text = "Contract total unavailable"
		quote_amount_label.text = ""
		quote_icon.visible = false
	wallet_label.text = str(int(Inventory.items.get("shekel", 0)))
	wallet_label.tooltip_text = "Wallet balance: %s Shekel. Hires are paid from your wallet." % wallet_label.text
	hire_button.disabled = _hiring or confirmation_open or not valid or not WorkerDatabase.is_job_board_open()
	if confirmation_open:
		_refresh_confirmation_panel()

func _on_hire_button_pressed() -> void:
	if _hiring or confirmation_open:
		return
	var selected: PackedInt32Array = applicant_list.get_selected_items()
	if selected.is_empty():
		feedback_label.text = "Select applicants first."
		return
	_pending_hire_ids.clear()
	for index: int in selected:
		if index < 0 or index >= applicants.size():
			_refresh_applicants()
			feedback_label.text = "Applicant selection is no longer valid."
			return
		_pending_hire_ids.append(applicants[index].citizen_id)
	_open_confirmation()

func _open_confirmation() -> void:
	if _hiring or confirmation_open:
		return
	if _pending_hire_ids.is_empty():
		var selected: PackedInt32Array = applicant_list.get_selected_items()
		for index: int in selected:
			if index < 0 or index >= applicants.size():
				feedback_label.text = "Applicant selection is no longer valid."
				return
			_pending_hire_ids.append(applicants[index].citizen_id)
	if _pending_hire_ids.is_empty():
		feedback_label.text = "Select applicants first."
		return
	feedback_label.text = ""
	confirmation_open = true
	confirmation_feedback_label.text = ""
	confirmation_layer.visible = true
	confirmation_panel.visible = true
	_refresh_quote(false)
	if duration_buttons.size() > 0:
		for button: Button in duration_buttons:
			if int(button.get_meta("contract_days", -1)) == _selected_contract_days_value:
				button.grab_focus()
				break

func _cancel_confirmation(restore_focus: bool = true) -> void:
	confirmation_open = false
	confirmation_layer.visible = false
	confirmation_panel.visible = false
	_pending_hire_ids.clear()
	_displayed_quote_ids.clear()
	_displayed_quote_total = -1
	_displayed_quote_days = -1
	confirmation_feedback_label.text = ""
	if is_instance_valid(hire_button):
		_refresh_quote(false)
		if restore_focus and visible:
			hire_button.grab_focus()

func _confirm_hire() -> void:
	if _hiring or not confirmation_open:
		return
	var quote: Dictionary = _quote_for_ids(_pending_hire_ids, _selected_contract_days())
	if not bool(quote.get("valid", false)):
		confirmation_feedback_label.text = "Applicant availability changed. Review the selection."
		_refresh_confirmation_panel()
		return
	if (
		_pending_hire_ids != _displayed_quote_ids
		or _selected_contract_days() != _displayed_quote_days
		or int(quote.get("total", -1)) != _displayed_quote_total
	):
		confirmation_feedback_label.text = "Quote changed. Review the updated total before confirming."
		_refresh_confirmation_panel()
		return
	_hiring = true
	confirm_hire_button.disabled = true
	var hired: Array[WorkerData] = WorkerDatabase.hire_applicants(_pending_hire_ids.duplicate(), 1, _selected_contract_days())
	if hired.is_empty():
		_hiring = false
		_refresh_applicants()
		confirmation_feedback_label.text = "Hire failed. Check your wallet and applicant availability."
		_refresh_confirmation_panel()
		return
	var success_text: String = "Hired %d. Paid through Day %d." % [hired.size(), hired[0].payroll_paid_until_day]
	_cancel_confirmation(false)
	_hiring = false
	_refresh_applicants()
	feedback_label.text = success_text

func _refresh_confirmation_panel() -> void:
	if not confirmation_open:
		return
	for child: Node in selected_names_container.get_children():
		selected_names_container.remove_child(child)
		child.queue_free()
	var all_names_valid: bool = not _pending_hire_ids.is_empty()
	for citizen_id: String in _pending_hire_ids:
		var citizen: CitizenData = _find_applicant(citizen_id)
		if citizen == null:
			all_names_valid = false
			continue
		var name_label := Label.new()
		name_label.text = _short_display_name(citizen.display_name, MAX_CONFIRM_NAME_LENGTH)
		name_label.tooltip_text = citizen.display_name
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.add_theme_font_override("font", PIXEL_FONT)
		name_label.add_theme_font_size_override("font_size", 6)
		name_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.77))
		selected_names_container.add_child(name_label)
	var quote: Dictionary = _quote_for_ids(_pending_hire_ids, _selected_contract_days())
	var quote_valid: bool = all_names_valid and bool(quote.get("valid", false))
	if quote_valid:
		var count: int = _pending_hire_ids.size()
		var days: int = _selected_contract_days()
		confirm_quote_label.text = "%d day%s · %d candidate%s · Total" % [days, "s" if days != 1 else "", count, "s" if count != 1 else ""]
		confirm_quote_amount_label.text = str(int(quote.get("total", 0)))
		confirm_quote_icon.visible = true
		confirm_quote_amount_label.tooltip_text = "Total cost: %s Shekel from your wallet." % confirm_quote_amount_label.text
		_displayed_quote_ids = _pending_hire_ids.duplicate()
		_displayed_quote_total = int(quote.get("total", 0))
		_displayed_quote_days = days
	else:
		confirm_quote_label.text = "Contract total unavailable"
		confirm_quote_amount_label.text = ""
		confirm_quote_icon.visible = false
		_displayed_quote_ids.clear()
		_displayed_quote_total = -1
		_displayed_quote_days = -1
	confirm_hire_button.disabled = not quote_valid or _hiring

func _quote_for_ids(citizen_ids: PackedStringArray, days: int) -> Dictionary:
	var total: int = 0
	var valid: bool = not citizen_ids.is_empty() and days in [3, 6, 9] and days in WorkerDatabase.CONTRACT_DAYS
	for citizen_id: String in citizen_ids:
		var citizen: CitizenData = _find_applicant(citizen_id)
		if citizen == null:
			valid = false
			break
		var price: int = WorkerDatabase.get_contract_price(citizen.profession, days)
		if price <= 0 or total > 9223372036854775807 - price:
			valid = false
			break
		total += price
	return {"valid": valid, "total": total}

func _find_applicant(citizen_id: String) -> CitizenData:
	for citizen: CitizenData in applicants:
		if citizen.citizen_id == citizen_id:
			return citizen
	return null

func _short_display_name(full_name: String, max_length: int) -> String:
	if full_name.length() <= max_length:
		return full_name
	return full_name.left(maxi(max_length - 3, 1)) + "..."
func _get_profession_name(profession: WorkerData.Profession) -> String:
	match profession:
		WorkerData.Profession.LABORER: return "Laborer"
		WorkerData.Profession.CRAFTER: return "Crafter"
		WorkerData.Profession.HAULER: return "Hauler"
		WorkerData.Profession.FARMER: return "Farmer"
		WorkerData.Profession.SCAVENGER: return "Scavenger"
		_: return "Unassigned"
func _scroll_style(region: Rect2) -> StyleBoxTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = SCROLL_PANEL
	atlas.region = region
	var style := StyleBoxTexture.new()
	style.texture = atlas
	style.texture_margin_left = 1
	style.texture_margin_top = 1
	style.texture_margin_right = 1
	style.texture_margin_bottom = 1
	style.content_margin_left = 0
	style.content_margin_top = 0
	style.content_margin_right = 0
	style.content_margin_bottom = 0
	return style

func _style_scrollbar() -> void:
	var bar: VScrollBar = candidate_scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 8
	for state: String in ["scroll", "scroll_focus"]:
		bar.add_theme_stylebox_override(state, _scroll_style(Rect2(35, 1, 16, 16)))
	bar.add_theme_stylebox_override("grabber", _scroll_style(Rect2(1, 1, 16, 16)))
	for state: String in ["grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(state, _scroll_style(Rect2(18, 1, 16, 16)))
	var blank := AtlasTexture.new()
	blank.atlas = SCROLL_PANEL
	blank.region = Rect2(0, 0, 1, 1)
	for icon_name: String in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
		bar.add_theme_icon_override(icon_name, blank)
