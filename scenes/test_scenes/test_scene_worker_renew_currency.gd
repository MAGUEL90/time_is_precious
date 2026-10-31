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
	var buttons: Array[Button] = [hub.contract_days_3_button, hub.contract_days_6_button, hub.contract_days_9_button]
	var selected_count: int = 0
	for button: Button in buttons:
		var expected_selected: bool = button.text == "%d days" % days
		if button.button_pressed:
			selected_count += 1
		_expect(button.button_pressed == expected_selected, "%d days is the only selected duration." % days)
		_expect((button.icon != null) == expected_selected, "%d days has the only checklist indicator." % days)
	_expect(selected_count == 1, "Exactly one contract duration is selected.")

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
	_expect(hub.contract_days_3_button.has_focus(), "Opening Contract gives keyboard focus to the first duration.")
	_expect(hub.renew_price_label.text == "Price: 2" and hub.renew_price_icon.visible, "Contract displays the official three-day price and coin icon.")
	_expect(hub.contract_current_label.text.contains("Paid through Day %d" % worker.payroll_paid_until_day)
		and hub.contract_current_label.text.contains("Current term: 3 days"), "Contract panel shows the current paid-through day and term.")
	var contract_title: Label = hub.get_node("Root/ContractWindow/Margin/MainVBox/HeaderLabel")
	_expect(contract_title.get_theme_font_size("font_size") == 12
		and hub.contract_current_label.get_theme_font_size("font_size") == 6, "Contract title and details retain their approved pixel sizes.")
	_expect(contract_title.get_theme_color("font_color") == hub.renew_price_label.get_theme_color("font_color")
		and hub.contract_current_label.get_theme_color("font_color") == hub.renew_price_label.get_theme_color("font_color"),
		"Contract title and details use the same brown text color as the price.")
	_expect(hub.contract_days_3_button.text == "3 days" and hub.contract_days_6_button.text == "6 days"
		and hub.contract_days_9_button.text == "9 days" and hub.contract_days_9_button.text.find("12") == -1,
		"Contract offers exactly three, six, and nine days.")
	_expect_duration_selection(3)
	await _capture("worker-contract-day-3")
	hub.contract_days_6_button.pressed.emit()
	_expect(hub.renew_price_label.text == "Price: 4" and hub.renew_price_icon.visible, "Six days shows the official six-day price and coin icon.")
	_expect(Inventory.items.get("shekel", 0) == wallet_before_contract and worker.payroll_paid_until_day == 103,
		"Changing contract length does not charge the wallet or alter the current contract.")
	_expect_duration_selection(6)
	await _capture("worker-contract-day-6")
	hub.contract_days_9_button.pressed.emit()
	_expect(hub.renew_price_label.text == "Price: 6" and Inventory.items.get("shekel", 0) == wallet_before_contract
		and worker.payroll_paid_until_day == 103, "Nine-day quote is accurate and changing duration remains free.")
	_expect_duration_selection(9)
	await _capture("worker-contract-day-9")
	hub.contract_days_6_button.pressed.emit()
	_expect_duration_selection(6)
	_expect(hub.renew_price_icon.tooltip_text.is_empty() and hub.renew_price_icon.accessibility_name == "Shekel", "The currency icon has no tooltip and retains its accessible name.")
	for control: Control in hub.find_children("*", "Control", true, false):
		_expect(control.tooltip_text.is_empty(), "Worker Hub control has no hover tooltip: " + str(control.get_path()))
	var text_width: float = hub.renew_price_label.get_theme_font("font").get_string_size(hub.renew_price_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hub.renew_price_label.get_theme_font_size("font_size")).x
	_expect(hub.renew_price_label.size.x >= text_width and hub.renew_price_label.size.y <= 12, "The renewal price fits on one line.")
	_expect(hub.renew_price_icon.get_global_rect().position.x - hub.renew_price_label.get_global_rect().end.x <= 3.0, "The currency icon stays beside the price.")
	_expect(get_viewport().get_visible_rect().encloses(hub.contract_window.get_global_rect()) and hub.contract_window.get_global_rect().encloses(hub.manage_renew_button.get_global_rect()), "Contract panel and Renew button stay within their frames.")
	await _capture("worker-contract-panel")
	var original_end: int = worker.payroll_paid_until_day
	hub.contract_back_button.pressed.emit()
	_expect(not hub.contract_window.visible and hub.manage_window.visible and Inventory.items.get("shekel", 0) == wallet_before_contract
		and worker.payroll_paid_until_day == original_end, "Back cancels the contract panel without changing wallet or contract.")
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
	hub.contract_days_6_button.pressed.emit()
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
	hub.manage_renew_button.pressed.emit()
	_expect(Inventory.items.get("shekel", 0) == 8 and worker.payroll_paid_until_day == original_end + 6,
		"A repeated Renew click cannot charge or extend the same selection twice.")
	hub.contract_days_3_button.pressed.emit()
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
	hub.contract_back_button.pressed.emit()
	hub._request_remove(_worker_rows()[0])
	_expect(hub._confirmation_overlay.visible and hub.find_child("RenewalCostRow", true, false) == null, "Fire confirmation never shows renewal price.")
	hub._confirm_no_button.pressed.emit()
	_expect(WorkerDatabase.get_worker_data(WORKER_ID) != null and Inventory.items.get("shekel", 0) == 8, "Cancel Fire preserves worker and wallet.")
	hub.close()
	print("WorkerRenewCurrencyTest: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
