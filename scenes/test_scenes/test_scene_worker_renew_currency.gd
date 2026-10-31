extends Node

## Explicit worker, wallet, and clock for renewal and Fire presentation checks.
const WORKER_ID: String = "renew_currency_fixture"
const REVIEW_WORKER_NAME: String = "Naram"
var failures: int = 0
var hub: WorkerControlUI

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _worker_rows() -> Array:
	return [{"id": WORKER_ID, "name": REVIEW_WORKER_NAME, "profession": "Laborer", "working": false, "can_fire": true}]

func _capture(label: String) -> void:
	var directory: String = OS.get_environment("TIP_MVP_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	_expect(frame.get_size() == Vector2i(400, 225), "Capture uses the native logical viewport.")
	if frame.get_size() != Vector2i(400, 225):
		return
	_expect(frame.save_png(directory.path_join(label + "-400x225.png")) == OK, "Logical capture is saved.")
	frame.resize(1200, 675, Image.INTERPOLATE_NEAREST)
	_expect(frame.save_png(directory.path_join(label + "-1200x675.png")) == OK, "Scaled capture is saved.")

func _expect_contract_popup_fits(state_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var panel_rect: Rect2 = hub.contract_window.get_global_rect()
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var feedback_rect: Rect2 = hub.contract_feedback_label.get_global_rect()
	var renew_rect: Rect2 = hub.manage_renew_button.get_global_rect()
	_expect(viewport_rect.encloses(panel_rect), "%s feedback keeps Contract inside the viewport." % state_name)
	_expect(panel_rect.encloses(feedback_rect) and panel_rect.encloses(renew_rect)
		and viewport_rect.encloses(feedback_rect) and viewport_rect.encloses(renew_rect),
		"%s feedback and Renew remain inside Contract and the viewport." % state_name)

func _expect_duration_selection(days: int) -> void:
	_expect(hub._selected_contract_days == days, "%d days is the selected contract duration." % days)
	for button: Button in hub.contract_day_buttons:
		var selected: bool = int(button.get_meta("contract_days", -1)) == days
		var marker: TextureRect = button.get_node_or_null("SelectionMarker") as TextureRect
		_expect(button.button_pressed == selected,
			"Only the %d-day duration button is pressed." % days)
		_expect(marker != null and marker.visible == selected,
			"Only the %d-day duration button shows its SelectionMarker." % days)

func _select_duration(days: int) -> void:
	for button: Button in hub.contract_day_buttons:
		if int(button.get_meta("contract_days", -1)) == days:
			button.pressed.emit()
			return
	_expect(false, "%d days has a duration button." % days)

func _capture_duration_geometry() -> Array[Rect2]:
	var bounds: Array[Rect2] = [hub.contract_window.get_global_rect(), hub.renew_price_label.get_global_rect()]
	for button: Button in hub.contract_day_buttons:
		bounds.append(button.get_global_rect())
	return bounds

func _capture_contract_range_geometry() -> Array[Rect2]:
	var bounds: Array[Rect2] = [
		hub.contract_window.get_global_rect(),
		hub.get_node("Root/ContractWindow/Margin").get_global_rect(),
		hub.get_node("Root/ContractWindow/Margin/MainVBox").get_global_rect(),
		hub.contract_range_row.get_global_rect(),
		hub.contract_current_day_label.get_global_rect(),
		hub.contract_range_arrow.get_global_rect(),
		hub.contract_new_day_label.get_global_rect(),
		hub.renew_price_label.get_global_rect(),
		hub.renew_price_icon.get_global_rect(),
		hub.manage_renew_button.get_global_rect(),
		hub.contract_close_button.get_global_rect(),
	]
	return bounds

func _expect_contract_range_geometry(expected: Array[Rect2], state_name: String) -> void:
	var actual: Array[Rect2] = _capture_contract_range_geometry()
	_expect(actual.size() == expected.size(), "%s keeps the Contract layout controls." % state_name)
	if actual.size() != expected.size():
		return
	for index: int in range(actual.size()):
		_expect(actual[index].position.is_equal_approx(expected[index].position)
			and actual[index].size.is_equal_approx(expected[index].size),
			"%s keeps the Contract panel, range row, arrow and price/actions geometry stable (control %d)." % [state_name, index])

func _capture_contract_range_content_geometry() -> Array[Rect2]:
	var panel_position: Vector2 = hub.contract_window.get_global_rect().position
	var controls: Array[Control] = [
		hub.contract_current_day_label,
		hub.contract_range_arrow,
		hub.contract_new_day_label,
	]
	for button: Button in hub.contract_day_buttons:
		controls.append(button)
		var marker: Control = button.get_node_or_null("SelectionMarker") as Control
		if marker != null:
			controls.append(marker)
	var bounds: Array[Rect2] = []
	for control: Control in controls:
		var rect: Rect2 = control.get_global_rect()
		rect.position -= panel_position
		bounds.append(rect)
	return bounds

func _expect_contract_range_content_geometry(expected: Array[Rect2], state_name: String) -> void:
	var actual: Array[Rect2] = _capture_contract_range_content_geometry()
	_expect(actual.size() == expected.size(), "%s keeps the range and duration controls." % state_name)
	if actual.size() != expected.size():
		return
	for index: int in range(actual.size()):
		_expect(actual[index].position.is_equal_approx(expected[index].position)
			and actual[index].size.is_equal_approx(expected[index].size),
			"%s keeps the date range and duration controls fixed relative to Contract (control %d)." % [state_name, index])

func _set_contract_date_fixture(worker: WorkerData, current_day: int, hour: int, minute: int,
		start_day: int, paid_from_day: int, paid_until_day: int, contract_days: int,
		paid_start_minute: int) -> void:
	TimeComponentManager.current_day = current_day
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute
	worker.payroll_start_day = start_day
	worker.payroll_paid_from_day = paid_from_day
	worker.payroll_paid_until_day = paid_until_day
	worker.payroll_contract_days = contract_days
	worker.payroll_paid_start_minute = paid_start_minute
	hub._show_manage_contract()

func _exercise_contract_range_case(worker: WorkerData, state_name: String, current_day: int, hour: int,
		minute: int, start_day: int, paid_from_day: int, paid_until_day: int, contract_days: int,
		paid_start_minute: int, days: int, expected_current: String, expected_new: String) -> void:
	var saved_worker: Dictionary = {
		"start_day": worker.payroll_start_day,
		"paid_from_day": worker.payroll_paid_from_day,
		"paid_until_day": worker.payroll_paid_until_day,
		"contract_days": worker.payroll_contract_days,
		"paid_start_minute": worker.payroll_paid_start_minute,
		"period_rate": worker.payroll_period_rate,
		"last_attempt_day": worker.payroll_last_attempt_day,
	}
	var saved_clock: Array[int] = [TimeComponentManager.current_day, TimeComponentManager.current_hour,
		TimeComponentManager.current_minute]
	var had_wallet: bool = Inventory.items.has("shekel")
	var saved_wallet: int = int(Inventory.items.get("shekel", 0))
	var saved_selection: int = hub._selected_contract_days
	var saved_completed: bool = hub._renew_completed_for_selection
	var saved_request_active: bool = hub._renew_request_active
	var saved_feedback: String = hub._renew_feedback_text
	var saved_contract_visible: bool = hub.contract_window.visible
	var saved_manage_visible: bool = hub.manage_window.visible
	var saved_focus: Control = get_viewport().gui_get_focus_owner()

	_set_contract_date_fixture(worker, current_day, hour, minute, start_day, paid_from_day,
		paid_until_day, contract_days, paid_start_minute)
	_select_duration(days)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(hub.contract_current_day_label.text == expected_current,
		"%s %dD shows the historical exclusive expiry %s." % [state_name, days, expected_current])
	_expect(hub.contract_new_day_label.text == expected_new,
		"%s %dD previews the exclusive expiry %s." % [state_name, days, expected_new])
	var expected_active: bool = state_name in ["active", "prepaid before 07:00", "legacy before 08:00"]
	var is_active: bool = not worker.is_payroll_blocked()
	_expect(is_active == expected_active,
		"%s case uses the expected active/expired renewal basis." % state_name)
	if worker.payroll_paid_from_day >= 0 and worker.payroll_paid_until_day >= worker.payroll_paid_from_day:
		_expect(hub.contract_current_day_label.text == "Day %d" % int(worker.get_paid_end_minute() / 1440),
			"%s current range label matches the worker's actual exclusive expiry." % state_name)
	else:
		_expect(hub.contract_current_day_label.text == "Day -",
			"%s without a paid contract shows no historical expiry." % state_name)
	var predicted_expiry_day: int = -1
	if expected_new.begins_with("Day ") and expected_new != "Day -":
		predicted_expiry_day = expected_new.trim_prefix("Day ").to_int()
	var wallet_before_renew: int = int(Inventory.items.get("shekel", 0))
	var renewal_price: int = WorkerDatabase.get_contract_price(worker.profession, days)
	Inventory.items["shekel"] = maxi(wallet_before_renew, renewal_price + 1)
	wallet_before_renew = int(Inventory.items.get("shekel", 0))
	hub.manage_renew_button.pressed.emit()
	var actual_expiry_day: int = int(worker.get_paid_end_minute() / 1440)
	_expect(predicted_expiry_day >= 0 and worker.payroll_contract_days == days
		and actual_expiry_day == predicted_expiry_day,
		"%s %dD preview matches the exclusive expiry after successful renewal." % [state_name, days])
	_expect(Inventory.items.get("shekel", 0) == wallet_before_renew - renewal_price,
		"%s %dD renewal charges the official price once." % [state_name, days])

	worker.payroll_start_day = int(saved_worker["start_day"])
	worker.payroll_paid_from_day = int(saved_worker["paid_from_day"])
	worker.payroll_paid_until_day = int(saved_worker["paid_until_day"])
	worker.payroll_contract_days = int(saved_worker["contract_days"])
	worker.payroll_paid_start_minute = int(saved_worker["paid_start_minute"])
	worker.payroll_period_rate = int(saved_worker["period_rate"])
	worker.payroll_last_attempt_day = int(saved_worker["last_attempt_day"])
	TimeComponentManager.current_day = saved_clock[0]
	TimeComponentManager.current_hour = saved_clock[1]
	TimeComponentManager.current_minute = saved_clock[2]
	if had_wallet:
		Inventory.items["shekel"] = saved_wallet
	else:
		Inventory.items.erase("shekel")
	hub._selected_contract_days = saved_selection
	hub._renew_completed_for_selection = saved_completed
	hub._renew_feedback_text = saved_feedback
	hub._renew_request_active = saved_request_active
	hub._update_contract_day_selection()
	hub._update_contract_controls(_worker_rows()[0])
	hub.contract_window.visible = saved_contract_visible
	hub.manage_window.visible = saved_manage_visible
	if is_instance_valid(saved_focus) and saved_focus.is_inside_tree():
		saved_focus.grab_focus()

func _preview_contract_range(worker: WorkerData, current_day: int, hour: int, minute: int,
		start_day: int, paid_from_day: int, paid_until_day: int, contract_days: int,
		paid_start_minute: int, selected_days: int) -> void:
	_set_contract_date_fixture(worker, current_day, hour, minute, start_day, paid_from_day,
		paid_until_day, contract_days, paid_start_minute)
	_select_duration(selected_days)
	await get_tree().process_frame
	await get_tree().process_frame

func _expect_duration_geometry(expected: Array[Rect2], days: int) -> void:
	var actual: Array[Rect2] = _capture_duration_geometry()
	_expect(actual.size() == expected.size(), "%d-day choice keeps the same controls." % days)
	if actual.size() != expected.size():
		return
	for index: int in range(actual.size()):
		_expect(actual[index].position.is_equal_approx(expected[index].position)
			and actual[index].size.is_equal_approx(expected[index].size),
			"%d-day choice keeps the Contract panel, price and button geometry stable (control %d)." % [days, index])

func _press_tab() -> void:
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	Input.parse_input_event(tab)
	await get_tree().process_frame
	tab = tab.duplicate()
	tab.pressed = false
	Input.parse_input_event(tab)
	await get_tree().process_frame

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.current_day = 100
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_minute = 1
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	WorkerDatabase.onboarding_period_rates = {WorkerData.Profession.LABORER: 2}
	CitizenManager.citizens_by_id.clear()
	Inventory.items.clear()
	Inventory.items["shekel"] = 20
	_expect(CitizenGenerator.display_name_container.has(REVIEW_WORKER_NAME), "Review name comes from the game's citizen name pool.")
	var citizen := CitizenData.new()
	citizen.citizen_id = WORKER_ID
	citizen.display_name = REVIEW_WORKER_NAME
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.APPLICANT
	citizen.profession = WorkerData.Profession.LABORER
	CitizenManager.add_citizen(citizen)
	var worker: WorkerData = WorkerDatabase.hire_applicant(WORKER_ID, 1, 3)
	_expect(worker != null and Inventory.items.get("shekel", 0) == 18, "Fixture hires the worker with its initial contract.")
	if worker == null:
		get_tree().quit(1)
		return
	hub = preload("res://scenes/test_scenes/ui_sandbox/worker_control/worker_control.tscn").instantiate()
	hub.rows_provider = _worker_rows
	add_child(hub)
	hub.open()
	hub._show_manage(WORKER_ID)
	await get_tree().process_frame
	await get_tree().process_frame
	var actions: VBoxContainer = hub.get_node("Root/ManageWindow/Margin/MainVBox/Actions")
	var action_names: Array[String] = []
	for action: Node in actions.get_children():
		action_names.append(action.name)
	_expect(action_names == ["FireButton", "GotoButton", "DetailsButton", "ContractButton"], "Manage actions are ordered Fire, Go To, Details, Contract.")
	_expect(hub.manage_goto_button.text == "Go To" and hub.get_node_or_null("Root/ManageWindow/Margin/MainVBox/RenewDaysOption") == null, "Manage has no duration picker or Renew action.")
	await _capture("worker-contract-menu")
	var wallet_before_contract: int = int(Inventory.items.get("shekel", 0))
	hub.manage_contract_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not hub.manage_window.visible and hub.contract_window.visible, "Contract opens in its own panel.")
	_expect(hub.contract_day_buttons.size() == 3, "Contract has exactly three visible duration buttons.")
	if hub.contract_day_buttons.size() != 3:
		get_tree().quit(1)
		return
	var buttons: Array[Button] = hub.contract_day_buttons
	_expect(buttons[0].has_focus(), "Opening Contract gives keyboard focus to the first duration button.")
	_expect(hub.renew_price_label.text == "Price: 2" and hub.renew_price_icon.visible, "Contract displays the official three-day price and coin icon.")
	_expect(hub.contract_current_day_label.text == "Day 104"
		and hub.contract_new_day_label.text == "Day 107",
		"Contract shows the current exclusive expiry and the selected 3D renewal preview.")
	var contract_title: Label = hub.get_node("Root/ContractWindow/Margin/MainVBox/HeaderLabel")
	_expect(contract_title.get_theme_font_size("font_size") == 12
		and hub.contract_current_day_label.get_theme_font_size("font_size") == 6
		and hub.contract_new_day_label.get_theme_font_size("font_size") == 6,
		"Contract title and date range retain their approved pixel sizes.")
	_expect(hub.contract_current_day_label.get_theme_color("font_color").is_equal_approx(Color.WHITE)
		and hub.contract_new_day_label.get_theme_color("font_color").is_equal_approx(Color.WHITE),
		"Both expiry labels use white text.")
	_expect(hub.contract_range_arrow.texture == preload("res://assets/ui/ui_icon/right_arrow_icon.png"),
		"The date range uses the existing right-arrow icon.")
	for range_label: Label in [hub.contract_current_day_label, hub.contract_new_day_label]:
		var range_font: Font = range_label.get_theme_font("font")
		var range_font_size: int = range_label.get_theme_font_size("font_size")
		var range_text_width: float = range_font.get_string_size(range_label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, range_font_size).x
		_expect(range_label.get_line_count() == 1 and range_label.size.x >= range_text_width,
			"Each expiry label stays on one unclipped line.")
	var day_values: Array[int] = [3, 6, 9]
	var duration_labels: Array[String] = ["3D", "6D", "9D"]
	var title_rect: Rect2 = contract_title.get_global_rect()
	var quote_rect: Rect2 = hub.renew_price_label.get_global_rect()
	var first_button_rect: Rect2 = buttons[0].get_global_rect()
	for index: int in range(buttons.size()):
		var button: Button = buttons[index]
		var button_rect: Rect2 = button.get_global_rect()
		_expect(button.visible and button.text == duration_labels[index]
			and int(button.get_meta("contract_days", -1)) == day_values[index],
			"Duration %d is always visible with the correct label and value." % day_values[index])
		_expect(button_rect.size.is_equal_approx(first_button_rect.size) and button_rect.size.x <= 40.0
			and button_rect.size.x >= 16.0 and button_rect.position.y >= title_rect.end.y
			and button_rect.end.y <= quote_rect.position.y,
			"Duration %d is compact, equal-sized, and between the title and price." % day_values[index])
		if index > 0:
			var previous_rect: Rect2 = buttons[index - 1].get_global_rect()
			_expect(button_rect.position.x >= previous_rect.end.x
				and is_equal_approx(button_rect.position.y, previous_rect.position.y),
				"Duration buttons form one non-overlapping horizontal row.")
		_expect(button.get_theme_font_size("font_size") == 6
			and button.get_theme_color("font_color").is_equal_approx(Color.WHITE)
			and button.get_theme_color("font_pressed_color").is_equal_approx(Color.WHITE),
			"Duration %d uses the white size-6 UI font." % day_values[index])
		var panel_style: StyleBox = button.get_theme_stylebox("normal")
		var panel_texture: AtlasTexture = (panel_style as StyleBoxTexture).texture as AtlasTexture if panel_style is StyleBoxTexture else null
		_expect(panel_texture != null
			and panel_texture.atlas == preload("res://assets/ui/ui_panel/brown_panel_24x24.png"),
			"Duration %d reuses the existing brown 24x24 panel asset." % day_values[index])
	_expect(hub.contract_window.find_children("*", "OptionButton", true, false).is_empty(),
		"Contract no longer has a duration dropdown.")
	_expect(hub.contract_window.find_children("*", "PopupMenu", true, false).is_empty(),
		"Choosing a duration requires no popup menu.")
	_expect(get_viewport().get_visible_rect().encloses(hub.contract_window.get_global_rect()),
		"Contract and the duration row fit inside the viewport.")
	hub.contract_close_button.grab_focus()
	_expect(hub.contract_close_button.has_focus(), "The Close icon is reachable by keyboard focus.")
	buttons[0].grab_focus()
	await _press_tab()
	_expect(buttons[1].has_focus(), "Tab moves from 3D to 6D.")
	await _press_tab()
	_expect(buttons[2].has_focus(), "Tab moves from 6D to 9D.")
	await _press_tab()
	_expect(hub.manage_renew_button.has_focus(), "Tab moves from 9D to Renew.")
	await _press_tab()
	_expect(hub.contract_close_button.has_focus(), "Tab moves from Renew to Close.")
	await _press_tab()
	_expect(buttons[0].has_focus(), "Tab remains within Contract and returns to 3D.")
	_expect_duration_selection(3)
	var original_geometry: Array[Rect2] = _capture_duration_geometry()
	await _capture("worker-contract-day-3")
	buttons[1].grab_focus()
	var accept := InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.pressed = true
	Input.parse_input_event(accept)
	await get_tree().process_frame
	accept = accept.duplicate()
	accept.pressed = false
	Input.parse_input_event(accept)
	await get_tree().process_frame
	_expect_duration_selection(6)
	_expect(hub.renew_price_label.text == "Price: 4" and hub.renew_price_icon.visible, "Six days shows the official six-day price and coin icon.")
	_expect(Inventory.items.get("shekel", 0) == wallet_before_contract and worker.payroll_paid_until_day == 103,
		"Changing contract length does not charge the wallet or alter the current contract.")
	_expect_duration_geometry(original_geometry, 6)
	await _capture("worker-contract-day-6")
	if DisplayServer.get_name() == "headless":
		_select_duration(9)
	else:
		var target: Vector2 = buttons[2].get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = target
		motion.global_position = target
		get_viewport().push_input(motion, true)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = target
		click.global_position = target
		click.pressed = true
		get_viewport().push_input(click, true)
		click = click.duplicate()
		click.pressed = false
		get_viewport().push_input(click, true)
		await get_tree().process_frame
		click = click.duplicate()
		click.pressed = true
		get_viewport().push_input(click, true)
		click = click.duplicate()
		click.pressed = false
		get_viewport().push_input(click, true)
		await get_tree().process_frame
	_expect(hub.renew_price_label.text == "Price: 6" and Inventory.items.get("shekel", 0) == wallet_before_contract
		and worker.payroll_paid_until_day == 103, "Nine-day selection, including a repeated click, remains free and shows the correct quote.")
	_expect_duration_selection(9)
	_expect_duration_geometry(original_geometry, 9)
	await _capture("worker-contract-day-9")
	var original_panel_position: Vector2 = hub.contract_window.position
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	hub.contract_window.position = viewport_size - hub.contract_window.size - Vector2(2, 2)
	await get_tree().process_frame
	for button: Button in buttons:
		_expect(get_viewport().get_visible_rect().encloses(button.get_global_rect()),
			"Every duration button stays inside the viewport at the bottom-right edge.")
	hub.contract_window.position = original_panel_position
	await get_tree().process_frame
	_select_duration(6)
	_expect_duration_selection(6)
	_expect(hub.renew_price_icon.tooltip_text.is_empty() and hub.renew_price_icon.accessibility_name == "Shekel", "The currency icon has no tooltip and retains its accessible name.")
	for control: Control in hub.find_children("*", "Control", true, false):
		_expect(control.tooltip_text.is_empty(), "Worker Hub control has no hover tooltip: " + str(control.get_path()))
	var text_width: float = hub.renew_price_label.get_theme_font("font").get_string_size(hub.renew_price_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hub.renew_price_label.get_theme_font_size("font_size")).x
	_expect(hub.renew_price_label.size.x >= text_width and hub.renew_price_label.size.y <= 12, "The renewal price fits on one line.")
	_expect(hub.renew_price_icon.get_global_rect().position.x - hub.renew_price_label.get_global_rect().end.x <= 3.0, "The currency icon stays beside the price.")
	var price_rect: Rect2 = hub.renew_price_label.get_global_rect()
	var icon_rect: Rect2 = hub.renew_price_icon.get_global_rect()
	_expect(absf(price_rect.get_center().y - icon_rect.get_center().y) <= 0.5,
		"Price text and the shekel icon are vertically aligned.")
	_expect(get_viewport().get_visible_rect().encloses(hub.contract_window.get_global_rect()) and hub.contract_window.get_global_rect().encloses(hub.manage_renew_button.get_global_rect()), "Contract panel and Renew button stay within their frames.")
	_expect(hub.contract_window.get_global_rect().encloses(hub.contract_range_row.get_global_rect())
		and hub.contract_window.get_global_rect().encloses(hub.contract_current_day_label.get_global_rect())
		and hub.contract_window.get_global_rect().encloses(hub.contract_range_arrow.get_global_rect())
		and hub.contract_window.get_global_rect().encloses(hub.contract_new_day_label.get_global_rect()),
		"Both expiry labels and the arrow stay inside the Contract panel.")
	_expect(hub.contract_close_button.get_global_rect().position.y < hub.manage_renew_button.get_global_rect().position.y
		and hub.contract_window.get_global_rect().encloses(hub.contract_close_button.get_global_rect()),
		"Close is within the upper edge of Contract.")
	await _capture("worker-contract-panel")
	var original_worker_dates: Dictionary = {
		"start_day": worker.payroll_start_day,
		"paid_from_day": worker.payroll_paid_from_day,
		"paid_until_day": worker.payroll_paid_until_day,
		"contract_days": worker.payroll_contract_days,
		"paid_start_minute": worker.payroll_paid_start_minute,
		"period_rate": worker.payroll_period_rate,
		"last_attempt_day": worker.payroll_last_attempt_day,
	}
	var original_clock: Array[int] = [TimeComponentManager.current_day, TimeComponentManager.current_hour,
		TimeComponentManager.current_minute]
	var original_range_focus: Control = get_viewport().gui_get_focus_owner()
	var active_range_cases: Array[Dictionary] = [
		{"name": "active", "day": 3, "hour": 6, "minute": 59, "start": 1, "from": 1, "until": 3, "term": 3, "start_minute": 1 * 1440 + 480, "current": "Day 4", "new3": "Day 7", "new6": "Day 10", "new9": "Day 13"},
		{"name": "prepaid before 07:00", "day": 4, "hour": 6, "minute": 59, "start": 1, "from": 1, "until": 3, "term": 3, "start_minute": 1 * 1440 + 480, "current": "Day 4", "new3": "Day 7", "new6": "Day 10", "new9": "Day 13"},
		{"name": "prepaid at 07:00", "day": 4, "hour": 7, "minute": 0, "start": 1, "from": 1, "until": 3, "term": 3, "start_minute": 1 * 1440 + 480, "current": "Day 4", "new3": "Day 8", "new6": "Day 11", "new9": "Day 14"},
		{"name": "expired", "day": 9, "hour": 8, "minute": 1, "start": 1, "from": 1, "until": 3, "term": 3, "start_minute": 1 * 1440 + 480, "current": "Day 4", "new3": "Day 13", "new6": "Day 16", "new9": "Day 19"},
		{"name": "unpaid", "day": 20, "hour": 12, "minute": 30, "start": 19, "from": -1, "until": -1, "term": 0, "start_minute": -1, "current": "Day -", "new3": "Day 24", "new6": "Day 27", "new9": "Day 30"},
		{"name": "legacy before 08:00", "day": 5, "hour": 7, "minute": 59, "start": 1, "from": 1, "until": 4, "term": 0, "start_minute": -1, "current": "Day 5", "new3": "Day 8", "new6": "Day 11", "new9": "Day 14"},
		{"name": "legacy at 08:00", "day": 5, "hour": 8, "minute": 0, "start": 1, "from": 1, "until": 4, "term": 0, "start_minute": -1, "current": "Day 5", "new3": "Day 9", "new6": "Day 12", "new9": "Day 15"},
	]
	var range_days: Array[int] = [3, 6, 9]
	var range_new_keys: Array[String] = ["new3", "new6", "new9"]
	for case: Dictionary in active_range_cases:
		for index: int in range(range_days.size()):
			await _exercise_contract_range_case(worker, str(case["name"]), int(case["day"]),
				int(case["hour"]), int(case["minute"]), int(case["start"]), int(case["from"]),
				int(case["until"]), int(case["term"]), int(case["start_minute"]), range_days[index],
				str(case["current"]), str(case[range_new_keys[index]]))
	_set_contract_date_fixture(worker, 5, 7, 59, 1, 1, 4, 0, -1)
	_expect(not worker.is_payroll_blocked(), "Legacy contract remains active at 07:59 before its 08:00 expiry.")
	_set_contract_date_fixture(worker, 5, 8, 0, 1, 1, 4, 0, -1)
	_expect(worker.is_payroll_blocked(), "Legacy contract is expired at its exact 08:00 boundary.")

	# Selecting 3/6/9 for one fixed contract keeps the date controls and panel fixed.
	await _preview_contract_range(worker, 8, 6, 59, 1, 1, 8, 3, 1 * 1440 + 480, 3)
	_expect(hub.contract_current_day_label.text == "Day 9" and hub.contract_new_day_label.text == "Day 12",
		"Active renewal preview crosses Day 9 to Day 12.")
	var range_geometry_day_9: Array[Rect2] = _capture_contract_range_geometry()
	for days: int in [6, 9]:
		_select_duration(days)
		await get_tree().process_frame
		await get_tree().process_frame
		var expected_new_day: int = 8 + days + 1
		_expect(hub.contract_current_day_label.text == "Day 9"
			and hub.contract_new_day_label.text == "Day %d" % expected_new_day,
			"Day 9 historical expiry stays correct for the %dD choice." % days)
		_expect_contract_range_geometry(range_geometry_day_9, "Day 9 to Day %d preview" % expected_new_day)
	await _preview_contract_range(worker, 98, 6, 59, 1, 1, 98, 3, 1 * 1440 + 480, 3)
	_expect(hub.contract_current_day_label.text == "Day 99" and hub.contract_new_day_label.text == "Day 102",
		"The Day 99 historical expiry previews the three-day exclusive expiry.")
	var range_geometry_day_99: Array[Rect2] = _capture_contract_range_geometry()
	for days: int in [6, 9]:
		_select_duration(days)
		await get_tree().process_frame
		await get_tree().process_frame
		var expected_new_day: int = 98 + days + 1
		_expect(hub.contract_current_day_label.text == "Day 99"
			and hub.contract_new_day_label.text == "Day %d" % expected_new_day,
			"Day 99 historical expiry stays correct for the %dD choice." % days)
		_expect_contract_range_geometry(range_geometry_day_99, "Day 99 to Day %d preview" % expected_new_day)

	# The largest valid renewal may display the exclusive day after MAX_CONTRACT_DAY.
	await _preview_contract_range(worker, WorkerDatabase.MAX_CONTRACT_DAY - 9, 6, 59,
		1, 1, WorkerDatabase.MAX_CONTRACT_DAY - 9, 3, 1 * 1440 + 480, 9)
	_expect(hub.contract_new_day_label.text == "Day %d" % (WorkerDatabase.MAX_CONTRACT_DAY + 1),
		"A renewal ending on the supported maximum shows its exclusive expiry without clipping.")
	var max_label: Label = hub.contract_new_day_label
	var max_font: Font = max_label.get_theme_font("font")
	var max_font_size: int = max_label.get_theme_font_size("font_size")
	var max_line_width: float = max_font.get_string_size(max_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, max_font_size).x
	_expect(max_label.size.x >= max_line_width and max_label.get_line_count() == 1
		and hub.contract_window.get_global_rect().encloses(max_label.get_global_rect())
		and get_viewport().get_visible_rect().encloses(hub.contract_window.get_global_rect()),
		"The maximum supported exclusive expiry fits on one line inside Contract and the viewport.")
	await _preview_contract_range(worker, 100, 8, 1, 1, 1, WorkerDatabase.MAX_CONTRACT_DAY, 3,
		1 * 1440 + 480, 9)
	_expect(hub.contract_current_day_label.text == "Day %d" % (WorkerDatabase.MAX_CONTRACT_DAY + 1)
		and hub.contract_new_day_label.text == "Day -",
		"A contract already at the maximum shows its historical expiry and an unavailable renewal date.")

	worker.payroll_start_day = int(original_worker_dates["start_day"])
	worker.payroll_paid_from_day = int(original_worker_dates["paid_from_day"])
	worker.payroll_paid_until_day = int(original_worker_dates["paid_until_day"])
	worker.payroll_contract_days = int(original_worker_dates["contract_days"])
	worker.payroll_paid_start_minute = int(original_worker_dates["paid_start_minute"])
	worker.payroll_period_rate = int(original_worker_dates["period_rate"])
	worker.payroll_last_attempt_day = int(original_worker_dates["last_attempt_day"])
	TimeComponentManager.current_day = original_clock[0]
	TimeComponentManager.current_hour = original_clock[1]
	TimeComponentManager.current_minute = original_clock[2]
	hub._show_manage_contract()
	_select_duration(6)
	if is_instance_valid(original_range_focus) and original_range_focus.is_inside_tree():
		original_range_focus.grab_focus()
	var original_end: int = worker.payroll_paid_until_day
	hub.contract_close_button.pressed.emit()
	_expect(not hub.contract_window.visible and hub.manage_window.visible and Inventory.items.get("shekel", 0) == wallet_before_contract
		and worker.payroll_paid_until_day == original_end, "Close dismisses the contract panel without changing wallet or contract.")
	hub.manage_contract_button.pressed.emit()
	await get_tree().process_frame
	_expect_duration_selection(3)
	for button: Button in buttons:
		_expect(button.visible, "Every duration button remains visible after reopening Contract.")
	_expect(Inventory.items.get("shekel", 0) == wallet_before_contract and worker.payroll_paid_until_day == original_end,
		"Reopening Contract does not charge or change the existing contract.")
	var cancel_event := InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	get_viewport().push_input(cancel_event)
	await get_tree().process_frame
	_expect(not hub.contract_window.visible and hub.manage_window.visible and hub.manage_contract_button.has_focus()
		and Inventory.items.get("shekel", 0) == wallet_before_contract and worker.payroll_paid_until_day == original_end,
		"Keyboard cancel returns focus to Contract without changing wallet or contract.")
	hub.manage_contract_button.pressed.emit()
	_select_duration(6)
	_expect(hub.renew_price_label.text == "Price: 4", "Reopening Contract presents a fresh official quote.")
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 3
	hub.manage_renew_button.pressed.emit()
	_expect(not hub._confirmation_overlay.visible and hub.renew_price_label.text == "Price: 6"
		and Inventory.items.get("shekel", 0) == 18 and worker.payroll_paid_until_day == original_end,
		"A changed quote is shown and requires a fresh Renew click before payment.")
	_expect(hub.contract_feedback_label.text == "Price updated; review and renew.", "A changed quote has a clear review message.")
	await _expect_contract_popup_fits("Price updated")
	await _capture("worker-contract-price-updated")
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.CRAFTER] = 5
	worker.profession = WorkerData.Profession.CRAFTER
	hub.manage_renew_button.pressed.emit()
	_expect(hub.renew_price_label.text == "Price: 10" and Inventory.items.get("shekel", 0) == 18
		and worker.payroll_paid_until_day == original_end,
		"A changed worker profession updates the quote from current WorkerData and requires review before payment.")
	hub.manage_renew_button.pressed.emit()
	_expect(Inventory.items.get("shekel", 0) == 8 and worker.payroll_paid_until_day == original_end + 6,
		"Renew pays the reviewed actual-profession price once and extends the selected six-day term.")
	_expect(hub.manage_renew_button.disabled, "A completed renewal disables Renew.")
	buttons[2].grab_focus()
	await _press_tab()
	_expect(hub.contract_close_button.has_focus(), "Tab moves from 9D past disabled Renew to Close.")
	hub.manage_renew_button.pressed.emit()
	_expect(Inventory.items.get("shekel", 0) == 8 and worker.payroll_paid_until_day == original_end + 6,
		"A repeated Renew click cannot charge or extend the same selection twice.")
	_select_duration(3)
	Inventory.items["shekel"] = 1
	var paid_end_after_renewal: int = worker.payroll_paid_until_day
	hub.manage_renew_button.pressed.emit()
	_expect(Inventory.items.get("shekel", 0) == 1 and worker.payroll_paid_until_day == paid_end_after_renewal
		and hub.contract_window.visible and hub.contract_feedback_label.text == "Not enough funds.",
		"Insufficient funds leave the contract and wallet unchanged and show a clear error.")
	await _expect_contract_popup_fits("Not enough funds")
	await _capture("worker-contract-not-enough-funds")
	Inventory.items["shekel"] = 8
	_expect(not hub.manage_renew_button.disabled, "A failed payment keeps the contract open for a later retry.")
	# Clear the existing failure message through normal duration choices before
	# comparing geometry; hiding that message intentionally changes panel height.
	_select_duration(6)
	_select_duration(3)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not hub.contract_feedback_label.visible, "Changing duration clears the previous payment error.")
	var saved_crafter_rate: int = int(WorkerDatabase.onboarding_period_rates[WorkerData.Profession.CRAFTER])
	var saved_price_selection: int = hub._selected_contract_days
	var saved_price_feedback: String = hub._renew_feedback_text
	var saved_price_completed: bool = hub._renew_completed_for_selection
	var saved_price_focus: Control = get_viewport().gui_get_focus_owner()
	var wallet_before_price_width_checks: int = int(Inventory.items.get("shekel", 0))
	var contract_end_before_price_width_checks: int = worker.payroll_paid_until_day
	var one_digit_price_geometry: Array[Rect2] = _capture_contract_range_content_geometry()
	_select_duration(9)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(hub.renew_price_label.text == "Price: 15", "A selected nine-day quote can move from one to two digits.")
	_expect_contract_range_content_geometry(one_digit_price_geometry, "Price 5 to Price 15")
	var two_digit_price_geometry: Array[Rect2] = _capture_contract_range_content_geometry()
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.CRAFTER] = 1000000
	hub._update_contract_controls(_worker_rows()[0])
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(hub.renew_price_label.text == "Price: 3000000"
		and WorkerDatabase.get_contract_price(WorkerData.Profession.CRAFTER, 9) == 3000000,
		"A large but valid quote is formatted in the price column.")
	_expect_contract_range_content_geometry(two_digit_price_geometry, "Price 15 to Price 3000000")
	var large_price_font: Font = hub.renew_price_label.get_theme_font("font")
	var large_price_width: float = large_price_font.get_string_size(hub.renew_price_label.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, hub.renew_price_label.get_theme_font_size("font_size")).x
	_expect(hub.renew_price_label.size.x >= large_price_width
		and hub.contract_window.get_global_rect().encloses(hub.contract_range_row.get_global_rect())
		and get_viewport().get_visible_rect().encloses(hub.contract_window.get_global_rect()),
		"A large valid price stays readable without displacing the date range outside Contract or the viewport.")
	_expect(Inventory.items.get("shekel", 0) == wallet_before_price_width_checks
		and worker.payroll_paid_until_day == contract_end_before_price_width_checks,
		"Changing contract quotes leaves wallet and paid-through date untouched.")
	# A valid rate may cross a digit boundary while the user changes duration.
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.CRAFTER] = 99999999999999999
	_select_duration(3)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var large_quote_geometry: Array[Rect2] = _capture_contract_range_geometry()
	_select_duration(9)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(hub.renew_price_label.text == "Price: 299999999999999997",
		"A large valid nine-day price is displayed exactly.")
	_expect_contract_range_geometry(large_quote_geometry, "Large price across 3D and 9D")
	_expect(Inventory.items.get("shekel", 0) == wallet_before_price_width_checks
		and worker.payroll_paid_until_day == contract_end_before_price_width_checks,
		"Selecting a large valid quote does not charge or extend the contract.")
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.CRAFTER] = saved_crafter_rate
	hub._selected_contract_days = saved_price_selection
	hub._renew_feedback_text = saved_price_feedback
	hub._renew_completed_for_selection = saved_price_completed
	hub._update_contract_day_selection()
	hub._update_contract_controls(_worker_rows()[0])
	if is_instance_valid(saved_price_focus) and saved_price_focus.is_inside_tree():
		saved_price_focus.grab_focus()
	hub.contract_close_button.pressed.emit()
	hub._request_remove(_worker_rows()[0])
	_expect(hub._confirmation_overlay.visible and hub.find_child("RenewalCostRow", true, false) == null, "Fire confirmation never shows renewal price.")
	hub._confirm_no_button.pressed.emit()
	_expect(WorkerDatabase.get_worker_data(WORKER_ID) != null and Inventory.items.get("shekel", 0) == 8, "Cancel Fire preserves worker and wallet.")
	hub.close()
	print("WorkerRenewCurrencyTest: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
