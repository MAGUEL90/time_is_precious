class_name JobBoardUI extends CanvasLayer

signal closed

const CandidateCard = preload("res://scenes/ui/job_board_ui/job_board_candidate_card.gd")
const CARD_SCENE: PackedScene = preload("res://scenes/ui/job_board_ui/job_board_candidate_card.tscn")
const SCROLL_PANEL: Texture2D = preload("res://assets/ui/ui_panel/brown_panel_16x16.png")

# Preserve the native selection/quote handles for existing callers.
@onready var applicant_list: ItemList = $Root/Center/Window/Margin/MainVBox/ApplicantList
@onready var candidate_scroll: ScrollContainer = $Root/Center/Window/Margin/MainVBox/CandidateScroll
@onready var candidate_rows: VBoxContainer = candidate_scroll.get_node("CandidateRows")
@onready var empty_state_panel: NinePatchRect = $Root/Center/Window/Margin/MainVBox/EmptyStatePanel
@onready var empty_state_label: Label = empty_state_panel.get_node("EmptyStateLabel")
@onready var feedback_label: Label = $Root/Center/Window/Margin/MainVBox/FeedbackLabel
@onready var quote_label: Label = $Root/Center/Window/Margin/MainVBox/QuoteLabel
@onready var wallet_label: Label = $Root/Center/Window/Margin/MainVBox/WalletLabel
@onready var hire_button: Button = $Root/Center/Window/Margin/MainVBox/Actions/HireButton
@onready var close_button: TextureButton = $Root/Center/Window/CloseButton
@onready var contract_days_option: OptionButton = $Root/Center/Window/Margin/MainVBox/ContractRow/ContractDaysOption
@onready var refresh_timer: Timer = $RefreshTimer

var applicants: Array[CitizenData] = []
var cards: Array[CandidateCard] = []
var _hiring: bool = false

func _ready() -> void:
	visible = false
	applicant_list.select_mode = ItemList.SELECT_MULTI
	for days: int in WorkerDatabase.CONTRACT_DAYS:
		contract_days_option.add_item("%d days" % days, days)
	contract_days_option.select(0)
	hire_button.pressed.connect(_on_hire_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)
	close_button.texture_focused = close_button.texture_hover
	applicant_list.item_selected.connect(func(_index: int): _refresh_quote())
	contract_days_option.item_selected.connect(func(_index: int): _refresh_quote())
	refresh_timer.timeout.connect(_poll_applicants)
	_style_scrollbar()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func open(_default_daily_wage: int = 1) -> void:
	get_tree().paused = true
	visible = true
	_refresh_applicants(false)
	refresh_timer.start()

func close() -> void:
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
	return contract_days_option.get_selected_id() if contract_days_option.item_count > 0 else 3

func _refresh_quote(reset_feedback: bool = true) -> void:
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
		quote_label.text = "Select applicants to see the total contract price."
	elif valid:
		var prefix: String = "%d workers | " % selected.size() if selected.size() > 1 else ""
		quote_label.text = prefix + "%d-day prepaid: %d Shekel from your wallet" % [days, total]
	else:
		quote_label.text = "Contract price unavailable for this selection."
	wallet_label.text = "Wallet: %d Shekel | Hours 08:00-17:00" % int(Inventory.items.get("shekel", 0))
	hire_button.disabled = _hiring or not valid or not WorkerDatabase.is_job_board_open()
	if reset_feedback or not WorkerDatabase.is_job_board_open() or feedback_label.text == "Closed | Opens 08:00":
		feedback_label.text = "Today's remaining time + %d full days starting tomorrow." % days if WorkerDatabase.is_job_board_open() else "Closed | Opens 08:00"

func _on_hire_button_pressed() -> void:
	if _hiring:
		return
	var selected: PackedInt32Array = applicant_list.get_selected_items()
	if selected.is_empty():
		feedback_label.text = "Select applicants first."
		return
	var citizen_ids := PackedStringArray()
	for index: int in selected:
		if index < 0 or index >= applicants.size():
			_refresh_applicants()
			feedback_label.text = "Applicant selection is no longer valid."
			return
		citizen_ids.append(applicants[index].citizen_id)
	_hiring = true
	var hired: Array[WorkerData] = WorkerDatabase.hire_applicants(citizen_ids, 1, _selected_contract_days())
	_hiring = false
	_refresh_applicants()
	if hired.is_empty():
		feedback_label.text = "None hired: check wallet and applicant availability."
	else:
		feedback_label.text = "Hired %d. Paid through Day %d." % [hired.size(), hired[0].payroll_paid_until_day]
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
