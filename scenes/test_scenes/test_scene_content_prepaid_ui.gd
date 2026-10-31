extends Node

## Isolated fixture only: explicit prices/funds exercise production UI bindings.
const BOARD: PackedScene = preload("res://scenes/ui/job_board_ui/job_board_ui.tscn")
var failures: int = 0
var board: JobBoardUI
var callbacks: int = 0
var observed_ids := PackedStringArray()
var expected_wallet: int = 0
var expected_workers: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _expect_no_tooltips(node: Node) -> void:
	for control: Control in node.find_children("*", "Control", true, false):
		_expect(control.tooltip_text.is_empty(), "Job Board control has no hover tooltip: " + str(control.get_path()))
		if control is ItemList:
			var list: ItemList = control as ItemList
			for index: int in range(list.item_count):
				_expect(not list.is_item_tooltip_enabled(index), "Job Board item tooltips stay disabled.")

func _confirmation_geometry_controls() -> Array[Control]:
	var controls: Array[Control] = [board.duration_button_container]
	for button: Button in board.duration_buttons:
		controls.append(button)
	controls.append(board.confirm_quote_label.get_parent() as Control)
	controls.append(board.confirm_quote_label)
	controls.append(board.confirm_quote_icon)
	controls.append(board.confirm_quote_amount_label)
	return controls

func _capture_confirmation_geometry() -> Array[Rect2]:
	var geometry: Array[Rect2] = []
	for control: Control in _confirmation_geometry_controls():
		geometry.append(control.get_global_rect())
	return geometry

func _expect_confirmation_geometry(expected: Array[Rect2], context: String) -> void:
	var controls: Array[Control] = _confirmation_geometry_controls()
	_expect(expected.size() == controls.size(), context + ": geometry control count stays fixed.")
	if expected.size() != controls.size():
		return
	for index: int in range(controls.size()):
		var actual: Rect2 = controls[index].get_global_rect()
		var same_position: bool = actual.position.is_equal_approx(expected[index].position)
		var same_size: bool = actual.size.is_equal_approx(expected[index].size)
		_expect(same_position and same_size,
			"%s: control %d keeps its position and size (%s vs %s)." % [context, index, str(expected[index]), str(actual)])

func _expect_confirmation_text_white(first_name: Label) -> void:
	var labels: Array[Label] = [
		board.confirmation_panel.get_node("ConfirmationTitle") as Label,
		board.confirmation_panel.get_node("SelectedHeading") as Label,
		board.confirmation_panel.get_node("DurationHeading") as Label,
		first_name,
		board.confirm_quote_label,
		board.confirm_quote_amount_label,
		board.confirmation_feedback_label,
	]
	for label: Label in labels:
		_expect(label.get_theme_color("font_color").is_equal_approx(Color.WHITE),
			"Contract modal label %s uses white text." % label.name)
		var expected_size: int = 12 if label.name == "ConfirmationTitle" else 6
		_expect(label.get_theme_font_size("font_size") == expected_size,
			"Contract modal label %s retains its existing font size." % label.name)
	var buttons: Array[Button] = [board.cancel_hire_button, board.confirm_hire_button]
	buttons.append_array(board.duration_buttons)
	for button: Button in buttons:
		_expect(button.get_theme_font_size("font_size") == 6,
			"Contract modal button %s retains the 6-pixel font." % button.name)
		for state: StringName in [
			&"font_color", &"font_hover_color", &"font_pressed_color",
			&"font_hover_pressed_color", &"font_focus_color", &"font_disabled_color",
		]:
			_expect(button.get_theme_color(state).is_equal_approx(Color.WHITE),
				"Contract modal button %s uses white text for %s." % [button.name, state])

func _hover_without_tooltip(control: Control) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var point: Vector2 = control.size / 2.0
	get_viewport().warp_mouse(control.global_position + point)
	var motion := InputEventMouseMotion.new()
	motion.position = control.global_position + point
	get_viewport().push_input(motion)
	await get_tree().create_timer(float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5)) + 0.2, true).timeout
	_expect(get_viewport().gui_get_hovered_control() == control, "The mouse is actually over the wallet icon.")
	_expect(control.get_tooltip(point).is_empty(), "Hovering the wallet icon after the native delay has no tooltip.")

func _seed(id: String, profession: WorkerData.Profession, satisfaction: float) -> CitizenData:
	var citizen := CitizenData.new()
	citizen.citizen_id = id
	citizen.display_name = "Fixture " + id
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.APPLICANT
	citizen.profession = profession
	citizen.satisfaction = satisfaction
	CitizenManager.add_citizen(citizen)
	return citizen

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.current_day = 100
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_minute = 0
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	WorkerDatabase.onboarding_period_rates = {WorkerData.Profession.LABORER: 2, WorkerData.Profession.HAULER: 3}
	Inventory.items.clear()
	CityStockManager.treasury_shekel = 987
	var first_citizen: CitizenData = _seed("first", WorkerData.Profession.LABORER, 0.62)
	first_citizen.display_name = "Naram"
	var second_citizen: CitizenData = _seed("second", WorkerData.Profession.HAULER, 0.87)
	second_citizen.display_name = "Lugal"
	var long_name: String = "A Very Long Worker Name Preserved In The Save"
	var long_candidate: CitizenData
	for i: int in range(5):
		var candidate: CitizenData = _seed("scroll_%d" % i, WorkerData.Profession.LABORER, 0.5)
		if i == 0:
			candidate.display_name = long_name
			long_candidate = candidate
	board = BOARD.instantiate()
	add_child(board)
	board.open()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(board.cards.size() == 7 and board.applicant_list.item_count == 7, "All available applicants have cards and native list entries.")
	_expect(WorkerDatabase.workers_by_id.is_empty() and Inventory.items.is_empty(), "Opening the board does not hire or charge.")
	_expect(board.applicant_list.get_selected_items().is_empty() and board.hire_button.disabled,
		"Opening the board leaves every applicant unselected and Hire disabled.")
	_expect(board.cards[0].name_label.text == "Naram" and board.cards[0].satisfaction_bar.value == 62, "Cards display actual names and satisfaction values.")
	_expect(board.cards[0].portrait.size == Vector2(32, 32), "Portrait control retains native 32x32 size.")
	_expect(board.feedback_label.text.is_empty(), "Remaining-time feedback is absent on open.")
	_expect(not board.wallet_label.text.contains("Shekel") and not board.wallet_label.text.contains("Hours"), "Wallet and hours text do not appear in the menu.")
	_expect(board.wallet_label.text == "0", "The balance remains the personal wallet even when city cash differs.")
	_expect(not board.quote_label.is_visible_in_tree(), "The persistent summary is hidden on the Job Board.")
	var scroll_rect: Rect2 = board.candidate_scroll.get_global_rect()
	var wallet_row: Control = board.wallet_label.get_parent()
	var wallet_icon: TextureRect = wallet_row.get_node("WalletIcon")
	_expect(wallet_icon.texture != null and wallet_icon.texture.resource_path == "res://assets/ui/ui_icon/city_wallet_icon.png"
		and wallet_icon.size == Vector2(16, 16) and wallet_icon.stretch_mode == TextureRect.STRETCH_KEEP_CENTERED,
		"The supplied wallet icon is displayed at its native size without stretching.")
	if wallet_icon.texture != null:
		var icon_image: Image = wallet_icon.texture.get_image()
		_expect(icon_image.get_size() == Vector2i(16, 16) and is_zero_approx(icon_image.get_pixel(0, 0).a),
			"The imported wallet icon keeps its dimensions and transparent background.")
		var original_icon := Image.new()
		var png_status: Error = original_icon.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/ui/ui_icon/city_wallet_icon.png"))
		var pixels_match: bool = png_status == OK and original_icon.get_size() == icon_image.get_size()
		if pixels_match:
			for y: int in range(16):
				for x: int in range(16):
					var source_pixel: Color = original_icon.get_pixel(x, y)
					var imported_pixel: Color = icon_image.get_pixel(x, y)
					if not is_equal_approx(source_pixel.a, imported_pixel.a) or (source_pixel.a > 0.0 and not source_pixel.is_equal_approx(imported_pixel)):
						pixels_match = false
		_expect(pixels_match, "Import preserves all visible icon pixels and their alpha.")
	_expect(board.cards[1].get_global_rect().end.y <= scroll_rect.end.y + 0.1, "Two candidate cards fit fully in the expanded viewport.")
	_expect(not board.feedback_label.get_global_rect().intersects(scroll_rect), "Contextual feedback does not overlap the candidate viewport.")
	_expect(wallet_row.get_global_rect().position.x > board.hire_button.get_global_rect().end.x and wallet_row.get_global_rect().position.y >= scroll_rect.end.y,
		"The wallet group is at the lower right, clear of the candidate area and Hire.")
	_expect(board.cards[2].name_label.text != long_name and board.cards[2].name_label.tooltip_text.is_empty() and board.cards[2].name_label.accessibility_name == long_name and long_candidate.display_name == long_name, "Only the displayed name is shortened; the original identity remains accessible without a hover tooltip.")
	_expect(board.cards[2].name_label.get_global_rect().end.x <= board.cards[2].role_label.get_global_rect().position.x, "Long display name does not overlap the role.")
	_expect_no_tooltips(board)
	await _hover_without_tooltip(wallet_icon)
	await _capture("job-board-wallet-hover")
	await _capture("job-board-initial")
	board.cards[0].selection_button.set_pressed(true)
	_expect(board.applicant_list.get_selected_items() == PackedInt32Array([0]) and not board.hire_button.disabled,
		"Manually checking a candidate selects it and enables Hire.")
	Inventory.items["shekel"] = 9223372036854775807
	board._refresh_quote()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(board.wallet_label.get_global_rect().end.x <= wallet_row.get_global_rect().end.x + 0.1
		and wallet_icon.get_global_rect().position.x >= board.hire_button.get_global_rect().end.x
		and wallet_row.get_global_rect().end.x <= board.get_node("Root/Center/Window").get_global_rect().end.x - 8.0,
		"The largest supported wallet amount remains inside its lower-right space.")
	await _capture("job-board-large-wallet")
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 3074457345618258602
	board._refresh_quote()
	board.hire_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(board.confirm_quote_amount_label.text == "3074457345618258602"
		and board.confirm_quote_amount_label.get_global_rect().end.x <= board.confirmation_panel.get_global_rect().end.x - 10.0,
		"A large valid contract total remains fully visible inside the confirmation panel.")
	_expect(WorkerDatabase.workers_by_id.is_empty() and Inventory.items.get("shekel", 0) == 9223372036854775807,
		"Opening a large quote does not hire or debit the wallet.")
	await _capture("job-board-confirm-large-total")
	board.cancel_hire_button.pressed.emit()
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 2
	Inventory.items.clear()
	board._refresh_quote()
	board.hire_button.pressed.emit()
	_expect(board.confirmation_open and board.confirmation_layer.visible, "Hire opens the duration and confirmation panel.")
	_expect(WorkerDatabase.workers_by_id.is_empty() and Inventory.items.is_empty(), "Opening the confirmation panel does not hire or charge.")
	_expect(board.duration_buttons.size() == 3, "Only 3, 6, and 9-day buttons are offered.")
	await get_tree().process_frame
	_expect(board.selected_names_container.get_child_count() == 1, "Selected name appears in the confirmation panel.")
	_expect(board.selected_names_container.get_global_rect().position.x < board.duration_button_container.get_global_rect().position.x, "Names are to the left of duration buttons.")
	var title: Label = board.confirmation_panel.get_node("ConfirmationTitle")
	var panel_rect: Rect2 = board.confirmation_panel.get_global_rect()
	var first_name: Label = board.selected_names_container.get_child(0)
	var confirmation_names_scroll: ScrollContainer = board.selected_names_container.get_parent()
	_expect_confirmation_text_white(first_name)
	_expect(first_name.get_theme_font_size("font_size") == 6 and first_name.scale == Vector2.ONE
		and board.selected_names_container.scale == Vector2.ONE and confirmation_names_scroll.scale == Vector2.ONE,
		"Candidate names use the requested native 6-pixel font without control scaling.")
	_expect(confirmation_names_scroll.get_global_rect().position.x >= panel_rect.position.x + 18.0
		and confirmation_names_scroll.get_global_rect().end.x <= board.duration_buttons[0].get_global_rect().position.x - 8.0,
		"Candidate names keep clear margins beside the panel and duration choices.")
	var confirm_text_width: float = board.confirm_hire_button.get_theme_font("font").get_string_size(
		board.confirm_hire_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, board.confirm_hire_button.get_theme_font_size("font_size")).x
	_expect(board.confirm_hire_button.size == board.cancel_hire_button.size
		and board.confirm_hire_button.size.x < 72.0 and board.confirm_hire_button.size.x >= confirm_text_width + 8.0,
		"Back and Confirm have equal compact dimensions and room for the longer label.")
	for duration_button: Button in board.duration_buttons:
		_expect(duration_button.size.x < 72.0 and duration_button.size.x >= duration_button.get_combined_minimum_size().x,
			"Each duration button fits its contents without the old wide panel.")
	_expect(panel_rect.size.x < 290.0 and title.get_theme_font_size("font_size") == 12, "The narrower contract panel uses a 12-pixel title.")
	_expect(title.get_global_rect().position.y >= panel_rect.position.y + 12.0
		and board.confirm_hire_button.get_global_rect().end.y <= panel_rect.end.y - 12.0,
		"Title and actions retain margins within the confirmation panel.")
	_expect(title.get_theme_font("font").get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= title.size.x,
		"The contract title fits without horizontal clipping.")
	_expect(board.duration_buttons[0].has_focus(), "The selected duration has keyboard focus on opening.")
	_expect(board.confirmation_panel.get_node_or_null("CloseConfirmationButton") == null, "Back is the only visible cancellation button in the confirmation panel.")
	_expect(board.cancel_hire_button.text == "Back" and board.confirm_hire_button.text == "Confirm", "Confirmation actions use the requested labels.")
	for button: Button in board.duration_buttons:
		_expect(button.get_tooltip(button.size / 2.0).is_empty(), "Contract duration choices show no native tooltip.")
	_expect_no_tooltips(board)
	var visited_focus: Array[Control] = [board.duration_buttons[0]]
	for step: int in range(8):
		var focus_event := InputEventAction.new()
		focus_event.action = "ui_focus_next"
		focus_event.pressed = true
		get_viewport().push_input(focus_event)
		focus_event = InputEventAction.new()
		focus_event.action = "ui_focus_next"
		get_viewport().push_input(focus_event)
		await get_tree().process_frame
		var focus: Control = get_viewport().gui_get_focus_owner()
		_expect(focus != null and board.confirmation_panel.is_ancestor_of(focus), "Keyboard focus stays within the open confirmation panel.")
		if focus != null and not visited_focus.has(focus):
			visited_focus.append(focus)
	for control: Control in [board.duration_buttons[0], board.duration_buttons[1], board.duration_buttons[2], board.cancel_hire_button, board.confirm_hire_button]:
		_expect(visited_focus.has(control), "Every duration and remaining action is reachable by keyboard focus.")
	await get_tree().process_frame
	await get_tree().process_frame
	var duration_and_quote_geometry: Array[Rect2] = _capture_confirmation_geometry()
	await _capture("job-board-confirm-single")
	for option: int in range(3):
		var days: int = WorkerDatabase.CONTRACT_DAYS[option]
		_expect(int(board.duration_buttons[option].get_meta("contract_days")) == days, "A duration button maps to the existing allowed duration.")
		board.duration_buttons[option].pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_expect(board.cards[0].wage_label.text == str(2 * (option + 1)), "Laborer card shows its price without trailing duration text.")
		_expect(board.cards[1].wage_label.text == str(3 * (option + 1)), "Hauler card shows its own profession price.")
		_expect(board.confirm_quote_amount_label.text == str(2 * (option + 1)) and board.confirm_quote_icon.visible, "The quoted price and coin are visible before confirmation.")
		_expect(WorkerDatabase.workers_by_id.is_empty() and Inventory.items.is_empty(), "Choosing a duration does not hire or charge.")
		_expect_confirmation_geometry(duration_and_quote_geometry, "%d-day selection keeps selector and quote geometry fixed" % days)
	var single_to_double_totals: Array[String] = ["5", "10", "15"]
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 5
	var single_to_double_geometry: Array[Rect2] = []
	for option: int in range(3):
		board.duration_buttons[option].pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_expect(board.confirm_quote_amount_label.text == single_to_double_totals[option],
			"Duration %d shows the correctly scaled one- or two-digit quote." % WorkerDatabase.CONTRACT_DAYS[option])
		if option == 0:
			single_to_double_geometry = _capture_confirmation_geometry()
		else:
			_expect_confirmation_geometry(single_to_double_geometry,
				"One- to two-digit totals keep selector and quote geometry fixed")
	var large_totals: Array[String] = [
		"3074457345618258602", "6148914691236517204", "9223372036854775806",
	]
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 3074457345618258602
	var large_total_geometry: Array[Rect2] = []
	for option: int in range(3):
		board.duration_buttons[option].pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_expect(board.confirm_quote_amount_label.text == large_totals[option],
			"Duration %d retains its exact valid 19-digit quote." % WorkerDatabase.CONTRACT_DAYS[option])
		if option == 0:
			large_total_geometry = _capture_confirmation_geometry()
		else:
			_expect_confirmation_geometry(large_total_geometry,
				"19-digit totals keep selector and quote geometry fixed")
		var coin_to_total_gap: float = (
			board.confirm_quote_amount_label.get_global_rect().position.x
			- board.confirm_quote_icon.get_global_rect().end.x
		)
		_expect(is_equal_approx(coin_to_total_gap, 3.0),
			"The quote coin stays adjacent to the amount at every supported duration.")
	_expect(board.confirm_quote_amount_label.size.x >= 95.0
		and board.confirm_quote_amount_label.get_global_rect().end.x <= panel_rect.end.x - 10.0,
		"A 19-digit quote fits its fixed amount slot inside the panel.")
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 2
	board.duration_buttons[2].pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	board.cancel_hire_button.pressed.emit()
	_expect(not board.confirmation_open and board.visible and board.hire_button.has_focus() and WorkerDatabase.workers_by_id.is_empty() and Inventory.items.is_empty(), "Back returns focus to the board without hiring or charging.")
	for index: int in range(1, board.cards.size()):
		board.cards[index].selection_button.set_pressed(true)
	board.hire_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var names_scroll: ScrollContainer = board.selected_names_container.get_parent()
	for _frame: int in range(6):
		await get_tree().process_frame
	_expect(board.selected_names_container.get_child_count() == 7 and names_scroll.clip_contents
		and names_scroll.get_global_rect().end.x < board.duration_buttons[0].get_global_rect().position.x,
		"A full selection stays clipped to its own confirmation column.")
	_expect(not board.confirm_quote_amount_label.text.is_empty() and Inventory.items.is_empty(), "A full selection shows its total without charging.")
	await _capture("job-board-confirm-many")
	var last_name: Control = board.selected_names_container.get_child(6)
	names_scroll.ensure_control_visible(last_name)
	await get_tree().process_frame
	await get_tree().process_frame
	# The board can rebuild confirmation names during its periodic refresh.
	last_name = board.selected_names_container.get_child(6)
	_expect(names_scroll.scroll_vertical > 0
		and last_name.get_global_rect().end.y <= names_scroll.get_global_rect().end.y + 0.1,
		"The last selected candidate remains reachable in the enlarged scrollable list.")
	await _capture("job-board-confirm-many-scrolled")
	var previous_name_scroll: int = names_scroll.scroll_vertical
	board._poll_applicants()
	await get_tree().process_frame
	await get_tree().process_frame
	var last_name_after_poll: Control = board.selected_names_container.get_child(6)
	_expect(names_scroll.scroll_vertical == previous_name_scroll
		and last_name_after_poll.get_global_rect().end.y <= names_scroll.get_global_rect().end.y + 0.1,
		"Polling preserves the selected-name scroll position and last visible candidate.")
	board.cancel_hire_button.pressed.emit()
	for index: int in range(1, board.cards.size()):
		board.cards[index].selection_button.set_pressed(false)
	board.cards[1].selection_button.set_pressed(true)
	_expect(board.applicant_list.get_selected_items() == PackedInt32Array([0, 1]), "Checkboxes select independently.")
	board.hire_button.pressed.emit()
	_expect(board.confirm_quote_amount_label.text == "15" and board.selected_names_container.get_child_count() == 2, "Nine-day batch quote totals the selected candidates.")
	await get_tree().process_frame
	await get_tree().process_frame
	var name_one: Label = board.selected_names_container.get_child(0)
	var name_two: Label = board.selected_names_container.get_child(1)
	_expect(name_two.position.y >= name_one.position.y + name_one.size.y + 3.0, "Selected candidates have visible vertical spacing.")
	for candidate_name: Label in [name_one, name_two]:
		_expect(candidate_name.get_theme_font("font").get_string_size(candidate_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x <= candidate_name.size.x,
			"The normal candidate name fits without being clipped at native font size.")
	await _capture("job-board-confirm-batch")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	board._unhandled_input(cancel)
	_expect(not board.confirmation_open and board.visible and Inventory.items.is_empty(), "Escape backs out of the panel without charging.")
	board.hire_button.pressed.emit()
	Inventory.items["shekel"] = 100
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 3
	board.confirm_hire_button.pressed.emit()
	_expect(board.confirmation_open and board.confirm_quote_amount_label.text == "18" and Inventory.items.get("shekel", 0) == 100 and WorkerDatabase.workers_by_id.is_empty(), "A changed quote requires a fresh confirmation without charging.")
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 2
	board.confirm_hire_button.pressed.emit()
	_expect(board.confirmation_open and board.confirm_quote_amount_label.text == "15" and Inventory.items.get("shekel", 0) == 100, "A second changed quote also requires review.")
	Inventory.items["shekel"] = 14
	board.confirm_hire_button.pressed.emit()
	_expect(board.confirmation_open and WorkerDatabase.workers_by_id.is_empty() and Inventory.items.get("shekel", 0) == 14, "Insufficient batch funds hire none and charge nothing.")
	_expect(not board.confirmation_feedback_label.text.is_empty(), "An unsuccessful hire supplies contextual feedback.")
	await _capture("job-board-insufficient-batch")
	Inventory.items["shekel"] = 15
	observed_ids = PackedStringArray(["first", "second"])
	expected_wallet = 0
	expected_workers = 2
	Inventory.items_changed.connect(_observe_batch)
	WorkerDatabase.payroll_changed.connect(_observe_batch)
	board.confirm_hire_button.pressed.emit()
	Inventory.items_changed.disconnect(_observe_batch)
	WorkerDatabase.payroll_changed.disconnect(_observe_batch)
	_expect(callbacks == 2, "UI batch notifies once per signal with reentrant clicks blocked.")
	var hired: WorkerData = WorkerDatabase.get_worker_data("first")
	_expect(hired != null and hired.payroll_contract_days == 9 and hired.payroll_paid_until_day == 109, "Exact funds hire the selected nine-day native contract.")
	_expect(int(Inventory.items.get("shekel", 0)) == 0 and WorkerDatabase.workers_by_id.size() == 2, "Final confirmation buys both contracts atomically once.")
	_expect(CityStockManager.treasury_shekel == 987, "Hiring leaves city cash unchanged.")
	_expect(board.feedback_label.text.is_empty(), "Successful hiring leaves no success toast on the Job Board.")
	Inventory.items["shekel"] = 100
	board.confirm_hire_button.pressed.emit()
	_expect(int(Inventory.items.get("shekel", 0)) == 100 and WorkerDatabase.workers_by_id.size() == 2, "Stale repeated confirmation cannot buy another batch.")
	board._refresh_applicants(false)
	await get_tree().process_frame
	for index: int in range(board.applicants.size()):
		if board.applicants[index].citizen_id == "scroll_0":
			board.applicant_list.deselect_all()
			board.applicant_list.select(index)
			board.candidate_scroll.ensure_control_visible(board.cards[index])
			break
	board._refresh_quote()
	board.hire_button.pressed.emit()
	await get_tree().process_frame
	var displayed_name: Label = board.selected_names_container.get_child(0)
	_expect(displayed_name.text != long_name and displayed_name.tooltip_text.is_empty() and displayed_name.accessibility_name == long_name and long_candidate.display_name == long_name, "Confirmation shortens only the displayed name, keeping the original accessible without a tooltip.")
	_expect(displayed_name.get_global_rect().end.x <= board.selected_names_container.get_parent().get_global_rect().end.x + 0.1,
		"A long displayed name stays within its confirmation column.")
	await _capture("job-board-confirm-long-name")
	board.cancel_hire_button.pressed.emit()
	var connections: int = board.confirm_hire_button.pressed.get_connections().size()
	for cycle: int in range(4):
		board.hire_button.pressed.emit()
		_expect(board.confirmation_open, "Confirmation reopens on cycle %d." % cycle)
		board.cancel_hire_button.pressed.emit()
	_expect(board.confirm_hire_button.pressed.get_connections().size() == connections and Inventory.items.get("shekel", 0) == 100, "Repeated open and cancel neither duplicates signals nor charges.")
	board.candidate_scroll.scroll_vertical = 80
	var saved_scroll: int = board.candidate_scroll.scroll_vertical
	board._poll_applicants()
	_expect(saved_scroll > 0 and board.candidate_scroll.scroll_vertical == saved_scroll and board.candidate_scroll.clip_contents, "Polling preserves manual scroll and clips cards.")
	TimeComponentManager.current_hour = 17
	board._refresh_quote()
	_expect(board.hire_button.disabled and not board.feedback_label.text.contains("08:00"), "Closing time disables hiring without displaying menu hours.")
	board.close_button.pressed.emit()
	_expect(not board.visible and not get_tree().paused and board.refresh_timer.is_stopped(), "Top Close closes and resumes gameplay.")
	board.open()
	board._unhandled_input(cancel)
	_expect(not board.visible and not get_tree().paused, "Escape closes after reopening.")
	CitizenManager.citizens_by_id.clear()
	board.open()
	_expect(board.empty_state_panel.visible and board.hire_button.disabled, "Empty state disables Hire.")
	board.close()
	_test_atomic_backend()
	CityStockManager.treasury_shekel = 0
	print("ContentPrepaidUITest: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)

func _capture(label: String) -> void:
	var directory: String = OS.get_environment("TIP_MVP_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	_expect(error == OK, "Capture directory can be created.")
	if error != OK:
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_expect(get_window().size == Vector2i(1200, 675), "Rendered fixture uses the 1200x675 window.")
	var logical: Image = get_viewport().get_texture().get_image()
	_expect(logical.get_size() == Vector2i(400, 225), "GL capture uses the native logical viewport.")
	if logical.get_size() != Vector2i(400, 225):
		logical.resize(400, 225, Image.INTERPOLATE_NEAREST)
	_expect(logical.save_png(directory.path_join(label + "-400x225.png")) == OK, "Save logical capture " + label)
	logical.resize(1200, 675, Image.INTERPOLATE_NEAREST)
	_expect(logical.save_png(directory.path_join(label + "-1200x675.png")) == OK, "Save nearest-scaled capture " + label)

func _reset_backend() -> void:
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	WorkerDatabase._payroll_settling = false
	WorkerDatabase.onboarding_period_rates = {WorkerData.Profession.LABORER: 2, WorkerData.Profession.HAULER: 3}
	Inventory.items.clear()
	TimeComponentManager.current_day = 100
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_minute = 15

func _observe_batch() -> void:
	callbacks += 1
	_expect(WorkerDatabase.workers_by_id.size() == expected_workers and int(Inventory.items.get("shekel", 0)) == expected_wallet, "Observers see all memberships and total debit together.")
	for id: String in observed_ids:
		_expect(WorkerDatabase.get_worker_data(id) != null and CitizenManager.get_citizen(id).employment_status == CitizenData.EmploymentStatus.HIRED, "Every candidate is hired before notifications.")
	_expect(WorkerDatabase.hire_applicants(PackedStringArray(["other"]), 1, 3).is_empty(), "Reentrant batch hire is rejected.")
	_expect(WorkerDatabase.hire_applicant("other", 1, 3) == null, "Reentrant single hire is rejected.")
	_expect(not WorkerDatabase.renew_contract(observed_ids[0], 3), "Reentrant renewal is rejected.")
	if board._hiring:
		board._on_hire_button_pressed()
		board._confirm_hire()

func _test_atomic_backend() -> void:
	for days: int in WorkerDatabase.CONTRACT_DAYS:
		_reset_backend()
		_seed("a", WorkerData.Profession.LABORER, 0.5)
		_seed("b", WorkerData.Profession.HAULER, 0.5)
		_seed("other", WorkerData.Profession.LABORER, 0.5)
		Inventory.items["shekel"] = 5 * (days / 3) + 50
		observed_ids = PackedStringArray(["a", "b"])
		expected_wallet = 50
		expected_workers = 2
		callbacks = 0
		Inventory.items_changed.connect(_observe_batch)
		WorkerDatabase.payroll_changed.connect(_observe_batch)
		var hired: Array[WorkerData] = WorkerDatabase.hire_applicants(observed_ids, 1, days)
		Inventory.items_changed.disconnect(_observe_batch)
		WorkerDatabase.payroll_changed.disconnect(_observe_batch)
		_expect(hired.size() == 2 and callbacks == 2 and not WorkerDatabase._payroll_settling, "Batch sends one notification per signal and releases its guard.")
		for worker: WorkerData in hired:
			_expect(worker.payroll_contract_days == days and worker.payroll_paid_until_day == 100 + days and worker.payroll_paid_start_minute == 100 * 1440 + 495, "Batch preserves duration, expiry and exact purchase minute.")
		_expect(WorkerDatabase.hire_applicants(observed_ids, 1, days).is_empty() and Inventory.items.get("shekel", 0) == 50, "Repeated completed batch does not charge again.")
	_reset_backend()
	var a: CitizenData = _seed("a", WorkerData.Profession.LABORER, 0.5)
	var b: CitizenData = _seed("b", WorkerData.Profession.HAULER, 0.5)
	Inventory.items["shekel"] = 100
	for ids: PackedStringArray in [PackedStringArray(), PackedStringArray(["a", "a"]), PackedStringArray(["a", " a "]), PackedStringArray(["a", "missing"])]:
		_expect(WorkerDatabase.hire_applicants(ids).is_empty(), "Empty, duplicate, alias-duplicate and missing IDs reject the complete batch.")
	for invalid_days: int in [0, -3, 4, 9223372036854775807]:
		_expect(WorkerDatabase.hire_applicants(PackedStringArray(["a", "b"]), 1, invalid_days).is_empty(), "Invalid durations reject without mutation.")
	b.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	_expect(WorkerDatabase.hire_applicants(PackedStringArray(["a", "b"])).is_empty(), "Unavailable member cancels the whole batch.")
	b.employment_status = CitizenData.EmploymentStatus.APPLICANT
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.HAULER] = -1
	_expect(WorkerDatabase.hire_applicants(PackedStringArray(["a", "b"])).is_empty(), "Unpriced profession cancels the whole batch.")
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.HAULER] = 3
	TimeComponentManager.current_hour = 17
	_expect(WorkerDatabase.hire_applicants(PackedStringArray(["a", "b"])).is_empty(), "Closed board rejects the entire batch.")
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_day = WorkerDatabase.MAX_CONTRACT_DAY - 2
	_expect(WorkerDatabase.hire_applicants(PackedStringArray(["a", "b"])).is_empty(), "Day limit rejects before mutation.")
	TimeComponentManager.current_day = 100
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 3000000000000000000
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.HAULER] = 3000000000000000000
	Inventory.items["shekel"] = 9223372036854775807
	_expect(WorkerDatabase.hire_applicants(PackedStringArray(["a", "b"]), 1, 9).is_empty(), "Aggregate overflow rejects the entire batch.")
	_expect(WorkerDatabase.workers_by_id.is_empty() and a.employment_status == CitizenData.EmploymentStatus.APPLICANT and Inventory.items.get("shekel", 0) == 9223372036854775807, "Invalid batches leave membership and wallet untouched.")
	_reset_backend()
	_seed("a", WorkerData.Profession.LABORER, 0.5)
	_seed("b", WorkerData.Profession.HAULER, 0.5)
	var retained := WorkerData.new()
	retained.worker_id = "a"
	retained.profession_xp = 72
	retained.profession_star = 2
	WorkerDatabase.dismissed_workers["a"] = retained
	Inventory.items["shekel"] = 5
	var rehired: Array[WorkerData] = WorkerDatabase.hire_applicants(PackedStringArray(["a", "b"]))
	_expect(rehired.size() == 2 and rehired[0] == retained and retained.profession_xp == 72 and retained.profession_star == 2, "Atomic rehire preserves the worker resource and earned profession progress.")
	_expect(Inventory.items.get("shekel", 0) == 0 and not WorkerDatabase.dismissed_workers.has("a"), "Exact funds consume only the total and remove retained dismissed membership.")
