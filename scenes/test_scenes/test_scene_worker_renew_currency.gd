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
	_expect(hub.contract_days_option.get_selected_id() == days, "%d days is selected in the dropdown." % days)

func _select_duration(days: int) -> void:
	var option: OptionButton = hub.contract_days_option
	var index: int = option.get_item_index(days)
	_expect(index >= 0, "%d days is available in the dropdown." % days)
	if index >= 0:
		option.select(index)
		option.item_selected.emit(index)

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
	_expect(hub.contract_days_option.has_focus(), "Opening Contract gives keyboard focus to the duration dropdown.")
	_expect(hub.renew_price_label.text == "Price: 2" and hub.renew_price_icon.visible, "Contract displays the official three-day price and coin icon.")
	_expect(hub.contract_current_label.text == "Current contract ends:\nDay 104, 07:00",
		"Contract shows the actual new-contract expiry, including its hour.")
	var contract_title: Label = hub.get_node("Root/ContractWindow/Margin/MainVBox/HeaderLabel")
	_expect(contract_title.get_theme_font_size("font_size") == 12
		and hub.contract_current_label.get_theme_font_size("font_size") == 6, "Contract title and details retain their approved pixel sizes.")
	_expect(contract_title.get_theme_color("font_color") == hub.renew_price_label.get_theme_color("font_color")
		and hub.contract_current_label.get_theme_color("font_color") == hub.renew_price_label.get_theme_color("font_color"),
		"Contract title and details use the same brown text color as the price.")
	var option: OptionButton = hub.contract_days_option
	_expect(option.item_count == 3 and option.get_item_id(0) == 3 and option.get_item_id(1) == 6 and option.get_item_id(2) == 9,
		"The dropdown offers exactly three, six, and nine days.")
	var duration_text_width: float = option.get_theme_font("font").get_string_size("3 days", HORIZONTAL_ALIGNMENT_LEFT, -1, option.get_theme_font_size("font_size")).x
	_expect(option.size.x < 64 and option.size.x >= duration_text_width + 8.0
		and option.size.x <= duration_text_width + 22.0,
		"The duration selector is compact while leaving room for its arrow.")
	_expect(hub.contract_window.size.x <= 110.0,
		"The Contract frame uses the available space after narrowing the selector.")
	var popup_theme: Theme = option.get_popup().theme
	var list_panel: StyleBox = popup_theme.get_stylebox("panel", "PopupMenu")
	_expect(list_panel is StyleBoxTexture and (list_panel as StyleBoxTexture).texture == hub.contract_window.texture,
		"The dropdown list uses the same cream panel asset as Contract.")
	_expect(popup_theme.get_color("font_color", "PopupMenu") == hub.contract_current_label.get_theme_color("font_color")
		and popup_theme.get_color("font_hover_color", "PopupMenu") == hub.contract_current_label.get_theme_color("font_color"),
		"Dropdown items remain readable against the cream panel.")
	var expected_arrow: Image = preload("res://assets/ui/ui_icon/right_arrow_icon.png").get_image()
	expected_arrow.rotate_90(CLOCKWISE)
	_expect(option.get_theme_icon("arrow") != null, "The dropdown has an arrow icon.")
	if DisplayServer.get_name() != "headless":
		_expect(option.get_theme_icon("arrow").get_image().get_data() == expected_arrow.get_data(),
			"The dropdown arrow uses the existing rotated right-arrow asset.")
	hub.contract_close_button.grab_focus()
	_expect(hub.contract_close_button.has_focus(), "The Close icon is reachable by keyboard focus.")
	option.grab_focus()
	await _press_tab()
	_expect(hub.manage_renew_button.has_focus(), "Tab moves from the dropdown to Renew.")
	await _press_tab()
	_expect(hub.contract_close_button.has_focus(), "Tab moves from Renew to Close.")
	await _press_tab()
	_expect(option.has_focus(), "Tab remains within Contract and returns to the dropdown.")
	_expect_duration_selection(3)
	await _capture("worker-contract-day-3")
	option.show_popup()
	await get_tree().process_frame
	_expect(option.get_popup().visible and Inventory.items.get("shekel", 0) == wallet_before_contract,
		"Opening the duration dropdown makes no transaction.")
	var dropdown_rect := Rect2(Vector2(option.get_popup().position), Vector2(option.get_popup().size))
	_expect(get_viewport().get_visible_rect().encloses(dropdown_rect), "The open dropdown fits inside the viewport.")
	await _capture("worker-contract-dropdown")
	var dropdown_cancel := InputEventAction.new()
	dropdown_cancel.action = "ui_cancel"
	dropdown_cancel.pressed = true
	get_viewport().push_input(dropdown_cancel)
	await get_tree().process_frame
	_expect(not option.get_popup().visible and hub.contract_window.visible,
		"Cancel closes the dropdown before closing Contract.")
	option.show_popup()
	await get_tree().process_frame
	option.get_popup().set_focused_item(1)
	var dropdown_accept := InputEventKey.new()
	dropdown_accept.keycode = KEY_ENTER
	dropdown_accept.pressed = true
	Input.parse_input_event(dropdown_accept)
	await get_tree().process_frame
	_expect(option.get_selected_id() == 6 and not option.get_popup().visible,
		"Keyboard selection chooses six days and closes the dropdown.")
	_expect(hub.renew_price_label.text == "Price: 4" and hub.renew_price_icon.visible, "Six days shows the official six-day price and coin icon.")
	_expect(Inventory.items.get("shekel", 0) == wallet_before_contract and worker.payroll_paid_until_day == 103,
		"Changing contract length does not charge the wallet or alter the current contract.")
	_expect_duration_selection(6)
	await _capture("worker-contract-day-6")
	if DisplayServer.get_name() == "headless":
		_select_duration(9)
	else:
		option.show_popup()
		await get_tree().process_frame
		var popup: PopupMenu = option.get_popup()
		var target: Vector2 = Vector2(popup.position) + Vector2(popup.size.x * 0.5, popup.size.y * 0.84)
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
		_expect(option.get_selected_id() == 9 and not popup.visible,
			"Mouse selection chooses nine days and closes the dropdown.")
	_expect(hub.renew_price_label.text == "Price: 6" and Inventory.items.get("shekel", 0) == wallet_before_contract
		and worker.payroll_paid_until_day == 103, "Nine-day quote is accurate and changing duration remains free.")
	_expect_duration_selection(9)
	await _capture("worker-contract-day-9")
	var original_panel_position: Vector2 = hub.contract_window.position
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	hub.contract_window.position = viewport_size - hub.contract_window.size - Vector2(2, 2)
	await get_tree().process_frame
	option.show_popup()
	await get_tree().process_frame
	dropdown_rect = Rect2(Vector2(option.get_popup().position), Vector2(option.get_popup().size))
	_expect(get_viewport().get_visible_rect().encloses(dropdown_rect),
		"The dropdown stays inside the viewport when Contract is at the bottom-right edge.")
	option.get_popup().hide()
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
	option.grab_focus()
	await _press_tab()
	_expect(hub.contract_close_button.has_focus(), "Tab skips disabled Renew and reaches Close.")
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
