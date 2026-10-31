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
		_expect(button.button_pressed == (int(button.get_meta("contract_days", -1)) == days),
			"Only the %d-day duration button is selected." % days)

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
	_expect(hub.contract_current_label.text == "Current contract ends:\nDay 104, 07:00",
		"Contract shows the actual new-contract expiry, including its hour.")
	var contract_title: Label = hub.get_node("Root/ContractWindow/Margin/MainVBox/HeaderLabel")
	_expect(contract_title.get_theme_font_size("font_size") == 12
		and hub.contract_current_label.get_theme_font_size("font_size") == 6, "Contract title and details retain their approved pixel sizes.")
	_expect(contract_title.get_theme_color("font_color") == hub.renew_price_label.get_theme_color("font_color")
		and hub.contract_current_label.get_theme_color("font_color") == hub.renew_price_label.get_theme_color("font_color"),
		"Contract title and details use the same brown text color as the price.")
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
	_expect(hub.contract_current_label.get_global_rect().position.y >= hub.manage_renew_button.get_global_rect().end.y
		and hub.contract_window.get_global_rect().encloses(hub.contract_current_label.get_global_rect()),
		"The current expiry note is below Renew and inside the Contract panel.")
	_expect(hub.contract_close_button.get_global_rect().position.y < hub.manage_renew_button.get_global_rect().position.y
		and hub.contract_window.get_global_rect().encloses(hub.contract_close_button.get_global_rect()),
		"Close is within the upper edge of Contract.")
	await _capture("worker-contract-panel")
	var ordinary_end: int = worker.payroll_paid_until_day
	worker.payroll_paid_until_day = WorkerDatabase.MAX_CONTRACT_DAY
	hub._update_contract_controls(_worker_rows()[0])
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(hub.contract_current_label.text == "Current contract ends:\nDay 100000001, 07:00"
		and hub.contract_window.get_global_rect().encloses(hub.contract_current_label.get_global_rect())
		and get_viewport().get_visible_rect().encloses(hub.contract_window.get_global_rect()),
		"The longest supported expiry remains inside the panel and viewport.")
	var expiry_font: Font = hub.contract_current_label.get_theme_font("font")
	var expiry_font_size: int = hub.contract_current_label.get_theme_font_size("font_size")
	var longest_expiry_line: float = maxf(
		expiry_font.get_string_size("Current contract ends:", HORIZONTAL_ALIGNMENT_LEFT, -1, expiry_font_size).x,
		expiry_font.get_string_size("Day 100000001, 07:00", HORIZONTAL_ALIGNMENT_LEFT, -1, expiry_font_size).x)
	_expect(hub.contract_current_label.size.x >= longest_expiry_line,
		"Even the longest supported expiry text fits without clipping or extra wrapping.")
	worker.payroll_paid_until_day = ordinary_end
	hub._update_contract_controls(_worker_rows()[0])
	TimeComponentManager.current_day = 104
	TimeComponentManager.current_hour = 6
	TimeComponentManager.current_minute = 59
	_expect(not worker.is_payroll_blocked() and hub._current_contract_text(worker) == "Current contract ends:\nDay 104, 07:00",
		"Active new contract displays its exclusive 07:00 expiry.")
	TimeComponentManager.current_hour = 7
	TimeComponentManager.current_minute = 0
	_expect(worker.is_payroll_blocked() and hub._current_contract_text(worker) == "Current contract ends:\nDay 104, 07:00",
		"Expired contract retains its actual expiry time.")
	worker.payroll_contract_days = 0
	TimeComponentManager.current_hour = 7
	TimeComponentManager.current_minute = 59
	_expect(not worker.is_payroll_blocked() and hub._current_contract_text(worker) == "Current contract ends:\nDay 104, 08:00",
		"Legacy contracts display the distinct 08:00 expiry.")
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_minute = 0
	_expect(worker.is_payroll_blocked(), "The legacy contract expires at 08:00.")
	worker.payroll_contract_days = 3
	var paid_from_before: int = worker.payroll_paid_from_day
	worker.payroll_paid_from_day = -1
	_expect(hub._current_contract_text(worker) == "Current contract ends:\n-", "Unpaid contracts do not invent an expiry.")
	worker.payroll_paid_from_day = paid_from_before
	TimeComponentManager.current_day = 100
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_minute = 1
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
	hub.contract_close_button.pressed.emit()
	hub._request_remove(_worker_rows()[0])
	_expect(hub._confirmation_overlay.visible and hub.find_child("RenewalCostRow", true, false) == null, "Fire confirmation never shows renewal price.")
	hub._confirm_no_button.pressed.emit()
	_expect(WorkerDatabase.get_worker_data(WORKER_ID) != null and Inventory.items.get("shekel", 0) == 8, "Cancel Fire preserves worker and wallet.")
	hub.close()
	print("WorkerRenewCurrencyTest: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
