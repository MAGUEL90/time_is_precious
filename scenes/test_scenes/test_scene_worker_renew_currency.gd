extends Node

## Explicit worker, wallet, and clock for renewal and Fire presentation checks.
const WORKER_ID: String = "renew_currency_fixture"
var failures: int = 0
var hub: WorkerControlUI

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _worker_rows() -> Array:
	return [{"id": WORKER_ID, "name": "Fixture Laborer", "profession": "Laborer", "working": false, "can_fire": true}]

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
	var citizen := CitizenData.new()
	citizen.citizen_id = WORKER_ID
	citizen.display_name = "Fixture Laborer"
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
	hub.renew_days_option.select(1)
	hub.renew_days_option.item_selected.emit(1)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(hub.renew_price_label.text == "Price: 4" and hub.renew_price_icon.visible, "Manage displays the six-day price and coin icon.")
	_expect(hub.renew_price_icon.tooltip_text.is_empty() and hub.renew_price_icon.accessibility_name == "Shekel", "The currency icon has no tooltip and retains its accessible name.")
	for control: Control in hub.find_children("*", "Control", true, false):
		_expect(control.tooltip_text.is_empty(), "Worker Hub control has no hover tooltip: " + str(control.get_path()))
	var text_width: float = hub.renew_price_label.get_theme_font("font").get_string_size(hub.renew_price_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hub.renew_price_label.get_theme_font_size("font_size")).x
	_expect(hub.renew_price_label.size.x >= text_width and hub.renew_price_label.size.y <= 12, "The renewal price fits on one line.")
	_expect(hub.renew_price_icon.get_global_rect().position.x - hub.renew_price_label.get_global_rect().end.x <= 3.0, "The currency icon stays beside the price.")
	_expect(get_viewport().get_visible_rect().encloses(hub.manage_window.get_global_rect()) and hub.manage_window.get_global_rect().encloses(hub.manage_renew_button.get_global_rect()), "Manage and its Renew button stay within their frames.")
	await _capture("worker-renew-menu")
	var original_end: int = worker.payroll_paid_until_day
	hub.manage_renew_button.pressed.emit()
	_expect(hub._confirmation_overlay.visible and hub._confirm_cost_row.visible and hub._confirm_cost_label.text == "Cost: 4", "Renewal confirmation shows the coin price before payment.")
	_expect(not hub._confirm_label.text.contains("Shekel") and hub._confirm_no_button.has_focus(), "Confirmation uses the icon and defaults to the cancel action.")
	await _capture("worker-renew-confirm")
	hub._confirm_no_button.pressed.emit()
	_expect(Inventory.items.get("shekel", 0) == 18 and worker.payroll_paid_until_day == original_end, "Cancel changes neither wallet nor contract.")
	hub.manage_renew_button.pressed.emit()
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 3
	hub._confirm_yes_button.pressed.emit()
	_expect(hub._confirmation_overlay.visible and hub._confirm_cost_label.text == "Cost: 6" and Inventory.items.get("shekel", 0) == 18, "A changed price requires review before payment.")
	hub._confirm_yes_button.pressed.emit()
	_expect(Inventory.items.get("shekel", 0) == 12 and worker.payroll_paid_until_day == original_end + 6, "Confirmation pays the revised price once and extends six days.")
	hub._confirm_yes_button.pressed.emit()
	_expect(Inventory.items.get("shekel", 0) == 12 and worker.payroll_paid_until_day == original_end + 6, "A stale confirmation cannot pay twice.")
	hub._request_remove(_worker_rows()[0])
	_expect(hub._confirmation_overlay.visible and not hub._confirm_cost_row.visible, "Fire confirmation never shows renewal price.")
	hub._confirm_no_button.pressed.emit()
	_expect(WorkerDatabase.get_worker_data(WORKER_ID) != null and Inventory.items.get("shekel", 0) == 12, "Cancel Fire preserves worker and wallet.")
	hub.close()
	print("WorkerRenewCurrencyTest: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
