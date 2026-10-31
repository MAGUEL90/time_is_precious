extends Node
## Separate-process diagnostic for worker expiry, renewal and notification sources.
## Run each mode in its own XDG user-data profile with write, renew and read phases.

const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const LABORER_ID: String = "initial_workshop_laborer"
const HAULER_ID: String = "initial_worksite_hauler"
const INITIAL_WALLET: int = 4
const TEST_RATE: int = 1
const CONTRACT_DAYS: int = 3
const EXPIRY_OFFSET_DAYS: int = 4
const PROFILE_ROOT: String = "user://expired_notice_regression"

var failures: int = 0
var phase: String = ""
var mode: String = ""
var launched: bool = false
var launch_continued: bool = false
var worker_ids: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--notice-phase="):
			phase = argument.trim_prefix("--notice-phase=")
		elif argument.begins_with("--notice-mode="):
			mode = argument.trim_prefix("--notice-mode=")
	_check(phase in ["write", "renew", "partial-read", "read"],
		"Pass --notice-phase=write|renew|partial-read|read.")
	_check(mode in ["single", "multi", "merchant"], "Pass --notice-mode=single|multi|merchant.")
	if phase == "partial-read":
		_check(mode == "multi", "The partial-read phase is specific to --notice-mode=multi.")
	if failures > 0:
		_finish()
		return

	worker_ids.clear()
	worker_ids.append(LABORER_ID)
	if mode == "multi":
		worker_ids.append(HAULER_ID)
	get_tree().current_scene = null
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	WorkerDatabase.onboarding_period_rates = {
		WorkerData.Profession.LABORER: TEST_RATE,
		WorkerData.Profession.HAULER: TEST_RATE,
	}
	if phase == "write":
		_check(not FileAccess.file_exists(_checkpoint_path()),
			"The write phase requires a fresh isolated profile; it never deletes or replaces a checkpoint.")
		if mode == "multi":
			_check(not FileAccess.file_exists(_partial_checkpoint_path()),
				"The multi write phase requires a fresh partial-checkpoint slot; it never replaces one.")
	elif phase == "partial-read":
		_check(FileAccess.file_exists(_partial_checkpoint_path()),
			"The partial-read phase requires the multi mode's separately saved partial checkpoint.")
	else:
		_check(FileAccess.file_exists(_checkpoint_path()),
			"The %s phase requires the preceding phase's checkpoint in the same isolated mode profile." % phase)
	if failures > 0:
		_finish()
		return

	var menu = MENU.instantiate()
	menu.checkpoint_file.path = _phase_checkpoint_path()
	menu.session_started.connect(_on_session_started)
	get_tree().root.add_child(menu)
	if phase == "write":
		menu._request_new_game()
	else:
		menu.continue_button.pressed.emit()
	for _frame: int in range(600):
		if launched:
			break
		await get_tree().process_frame
	_check(launched, "The real start menu must finish the %s phase." % phase)
	if not launched:
		_finish()
		return
	_check(launch_continued == (phase != "write"), "New Game/Continue used the expected start-menu path.")

	get_tree().paused = false
	TimeComponentManager.is_paused = false
	TimeComponentManager.set_process(false)
	var city: Node = get_tree().current_scene
	var store: Node = WorkStateRuntime.get_node("CitySave")
	var raid_state: Node = WorkStateRuntime.get_node("CityRaid")
	var ui: RaidUI = raid_state.get_node("RaidUI") as RaidUI
	var merchant: Node = WorkStateRuntime.get_node("CommonTravelingMerchant")
	var runtime: Node = city.get_node("YSortWorld/WorkerRuntime")
	var hub: WorkerControlUI = runtime.worker_control as WorkerControlUI
	_check(city.scene_file_path == "res://scenes/content_scene/content_scene.tscn",
		"The fixture runs in the real main city scene.")
	_check(store.disk.path == _phase_checkpoint_path(), "CitySave uses the expected isolated phase checkpoint.")
	_check(is_instance_valid(ui) and ui._city_management_available,
		"The real city notification UI is active.")
	_check(is_instance_valid(hub), "The main-map Worker Hub is available.")
	if not is_instance_valid(ui) or not is_instance_valid(hub):
		_finish()
		return
	if ui.details_panel.visible:
		ui.close_details()
	if phase == "write":
		_check(WorkerDatabase.get_all_workers().is_empty(), "Real New Game starts with an empty hired-worker roster.")
		await _write_expired_checkpoint(store, ui, merchant, raid_state)
	elif phase == "renew":
		await _renew_after_continue(city, store, ui, merchant, raid_state, hub)
	elif phase == "partial-read":
		await _read_partial_after_continue(city, store, ui, merchant, raid_state)
	else:
		await _read_after_continue(city, store, ui, merchant, raid_state)
	_finish()


func _on_session_started(continued: bool) -> void:
	launch_continued = continued
	launched = true


func _write_expired_checkpoint(store: Node, ui: RaidUI, merchant: Node, raid_state: Node) -> void:
	if failures > 0:
		return
	_check(not ui.notifications_popup.visible, "The notification popup starts closed.")
	var first_day: int = int(merchant.config.first_day)
	var interval_days: int = int(merchant.config.interval_days)
	var hire_day: int = _select_hire_day(TimeComponentManager.current_day, first_day, interval_days)
	_check(hire_day >= TimeComponentManager.current_day,
		"The fixture can align expiry with a real merchant visit day.")
	if hire_day < TimeComponentManager.current_day:
		return
	_place_clock(hire_day * 1440 + 10 * 60)
	_check(not _is_merchant_visit_day(hire_day, first_day, interval_days),
		"The hire clock is not itself a scheduled merchant visit.")
	Inventory.add_item("shekel", INITIAL_WALLET)
	var hires := PackedStringArray()
	for worker_id: String in worker_ids:
		hires.append(worker_id)
	var hired: Array[WorkerData] = WorkerDatabase.hire_applicants(hires, 1, CONTRACT_DAYS)
	_check(hired.size() == worker_ids.size(), "Hire the authored applicant(s) through WorkerDatabase.")
	if hired.size() != worker_ids.size():
		return
	for index: int in range(hired.size()):
		_check(hired[index].worker_id == worker_ids[index]
			and hired[index].payroll_paid_from_day == hire_day
			and hired[index].payroll_contract_days == CONTRACT_DAYS,
			"Authored applicant %s has a real three-day paid contract." % worker_ids[index])
	_check(Inventory.items.get("shekel", 0) == INITIAL_WALLET - hired.size(),
		"Initial contracts debit only the explicitly granted wallet shekels.")
	var expiry_minute: int = hired[0].get_paid_end_minute()
	for worker: WorkerData in hired:
		_check(worker.get_paid_end_minute() == expiry_minute,
			"All fixture workers share the exact same expiry minute.")
	_place_clock(expiry_minute - 1)
	TimeComponentManager.advance_minutes(1)
	await _frames(2)
	_check(_now() == expiry_minute and hired[0].is_payroll_blocked(),
		"One real elapsed clock minute reaches the exact new-contract expiry boundary.")
	_check(not ui.notifications_popup.visible and ui._unread_notification and ui._notice_emergency
		and _is_red(ui.notification_button.modulate),
		"Expiry is unread and red before the notification popup has been opened.")
	_check(_has_worker_fingerprint(ui, hired[0].worker_id, "expired"),
		"The expired worker has a current notification fingerprint.")
	_check(str(ui._get_merchant_event_fingerprint()).is_empty()
		and str(ui._get_raid_event_fingerprint()).is_empty(),
		"No merchant or raid event is active at the worker-only expiry boundary.")
	_check(not merchant.is_present(), "The scheduled merchant has not arrived at the 07:00 expiry boundary.")
	_check(str(raid_state.phase) in ["unbuilt", "safe"], "No raid threat is active in the fixture.")
	await _capture("write-expired")
	_record("write-expired", ui, merchant, raid_state)
	if failures == 0:
		_check(store.save_checkpoint(), "Save the real expired and unread city checkpoint: " + store.last_error)
	_record("write-saved", ui, merchant, raid_state)


func _renew_after_continue(city: Node, store: Node, ui: RaidUI, merchant: Node, raid_state: Node, hub: WorkerControlUI) -> void:
	if failures > 0:
		return
	_check(_assert_exact_continue(city, store, _checkpoint_path()), "Continue restores the exact expired checkpoint.")
	_check(not ui.notifications_popup.visible and ui._unread_notification and ui._notice_emergency
		and _is_red(ui.notification_button.modulate),
		"Continue recomputes the still-unread expired worker event with the popup closed.")
	_check(not merchant.is_present() and str(raid_state.phase) in ["unbuilt", "safe"],
		"Merchant and raid sources are neutral before renewal.")
	await _capture("renew-continued-expired")
	_record("renew-continued-expired", ui, merchant, raid_state)
	if failures > 0:
		return
	if mode == "merchant":
		_place_clock(TimeComponentManager.current_day * 1440 + 7 * 60 + 59)
		TimeComponentManager.advance_minutes(1)
		await _frames(2)
		_check(merchant.is_present() and _is_merchant_visit_day(TimeComponentManager.current_day,
			int(merchant.config.first_day), int(merchant.config.interval_days)),
			"The real merchant arrives at 08:00 before opening Worker Hub.")
		_check(ui._unread_notification and ui._notice_emergency and _is_red(ui.notification_button.modulate)
			and _has_worker_fingerprint(ui, worker_ids[0], "expired")
			and str(ui._get_merchant_event_fingerprint()).ends_with(":arrived"),
			"Before renewal, both expired worker and merchant arrival are visible unread sources.")
		await _capture("renew-expired-plus-merchant")
		_record("renew-expired-plus-merchant", ui, merchant, raid_state)

	await _press_action(&"open_worker_hub")
	_check(hub.visible and get_tree().paused, "The real Worker Hub opens through its input action.")
	if not hub.visible:
		return
	await _renew_through_hub(hub, worker_ids[0], ui, merchant, raid_state, "after-first-renew")
	if mode == "multi":
		_check(ui._unread_notification and ui._notice_emergency,
			"Renewing one worker leaves the second expired worker unread and red.")
		_check(_is_red(ui.notification_button.modulate), "The visible notification button remains red after one renewal.")
		_check(_has_worker_fingerprint(ui, worker_ids[1], "expired"),
			"The second expired worker remains an active notification source.")
		await _press_action(&"open_worker_hub")
		_check(not hub.visible and not get_tree().paused, "Close Worker Hub to inspect the notification button in the HUD.")
		await _capture("renew-one-of-two-still-red")
		TimeComponentManager.advance_minutes(1)
		await _frames(2)
		_check(ui._unread_notification and ui._notice_emergency and _is_red(ui.notification_button.modulate)
			and _has_worker_fingerprint(ui, worker_ids[1], "expired"),
			"After one clock tick, the other expired worker still keeps the visible button red.")
		_record("renew-one-of-two-after-clock-tick", ui, merchant, raid_state)
		await _capture("renew-one-of-two-partial-save")
		store.disk.path = _partial_checkpoint_path()
		if failures == 0:
			_check(store.save_checkpoint(), "Save the real one-renewed/one-expired checkpoint: " + store.last_error)
		_record("renew-partial-saved", ui, merchant, raid_state)
		store.disk.path = _checkpoint_path()
		await _press_action(&"open_worker_hub")
		_check(hub.visible and get_tree().paused, "Reopen the real Worker Hub for the second worker.")
		await _renew_through_hub(hub, worker_ids[1], ui, merchant, raid_state, "after-all-renewed")
		_check(not ui._unread_notification and not ui._notice_emergency and _is_white(ui.notification_button.modulate),
			"Renewing every worker clears the worker-only indicator.")
	else:
		if mode == "merchant":
			_check(ui._unread_notification and ui._notice_emergency and _is_red(ui.notification_button.modulate)
				and _worker_fingerprint_count(ui) == 0
				and str(ui._get_merchant_event_fingerprint()).ends_with(":arrived"),
				"After worker renewal, the unread merchant event alone keeps the visible button red.")
		else:
			_check(not ui._unread_notification and not ui._notice_emergency and _is_white(ui.notification_button.modulate),
				"Renewing the only expired worker clears its unread indicator immediately.")

	await _press_action(&"open_worker_hub")
	_check(not hub.visible and not get_tree().paused, "Closing Worker Hub restores live city time.")
	TimeComponentManager.advance_minutes(1)
	await _frames(2)
	if mode == "single":
		_check(not ui._unread_notification and not ui._notice_emergency and _is_white(ui.notification_button.modulate)
			and _worker_fingerprint_count(ui) == 0,
			"The single-worker indicator stays normal after one clock tick.")
	elif mode == "multi":
		_check(not ui._unread_notification and not ui._notice_emergency and _is_white(ui.notification_button.modulate)
			and _worker_fingerprint_count(ui) == 0,
			"The multi-worker indicator stays normal after every worker is renewed and one clock tick passes.")
	else:
		_check(ui._unread_notification and ui._notice_emergency and _is_red(ui.notification_button.modulate)
			and _worker_fingerprint_count(ui) == 0
			and str(ui._get_merchant_event_fingerprint()).ends_with(":arrived"),
			"After one clock tick, merchant alone keeps the button red after worker renewal.")
	_record("renew-after-clock-tick", ui, merchant, raid_state)
	await _capture("renew-worker-source-cleared")

	_check(not ui.notifications_popup.visible, "No notification popup was opened during renewal.")
	for worker_id: String in worker_ids:
		var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
		_check(worker != null and worker.payroll_paid_from_day == TimeComponentManager.current_day
			and worker.payroll_paid_until_day == TimeComponentManager.current_day + CONTRACT_DAYS
			and worker.payroll_contract_days == CONTRACT_DAYS,
			"Renewed entitlement is published for %s." % worker_id)
	_record("renew-before-save", ui, merchant, raid_state)
	if failures == 0:
		_check(store.save_checkpoint(), "Save the renewed notification checkpoint: " + store.last_error)
	_record("renew-saved", ui, merchant, raid_state)


func _renew_through_hub(hub: WorkerControlUI, worker_id: String, ui: RaidUI, merchant: Node, raid_state: Node, label: String) -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
	var manage_button: Button = hub._find_manage_button(worker_id)
	_check(worker != null and manage_button != null, "The real Worker Hub lists Manage for %s." % worker_id)
	if worker == null or manage_button == null:
		return
	var wallet_before: int = int(Inventory.items.get("shekel", 0))
	var expiry_before: int = worker.payroll_paid_until_day
	manage_button.pressed.emit()
	await get_tree().process_frame
	_check(hub.manage_window.visible and hub._manage_worker_id == worker_id,
		"Manage opens for %s through the roster button." % worker_id)
	_check(hub.renew_days_option.get_selected_id() == CONTRACT_DAYS,
		"The normal Worker Hub renewal choice is three days.")
	_check(not hub.manage_renew_button.disabled, "The funded renewal control is enabled.")
	hub.manage_renew_button.pressed.emit()
	await get_tree().process_frame
	_check(hub._confirmation_overlay.visible, "Renew opens its normal confirmation panel.")
	if not hub._confirmation_overlay.visible:
		return
	_check(ui.notifications_popup.visible == false, "Renewal leaves the notification popup closed.")
	hub._confirm_yes_button.pressed.emit()
	worker = WorkerDatabase.get_worker_data(worker_id)
	_check(worker != null and worker.payroll_paid_from_day == TimeComponentManager.current_day
		and worker.payroll_paid_until_day == TimeComponentManager.current_day + CONTRACT_DAYS
		and worker.payroll_paid_until_day != expiry_before,
		"The confirmation action renews %s through the real Worker Hub path." % worker_id)
	_check(int(Inventory.items.get("shekel", 0)) == wallet_before - TEST_RATE,
		"The confirmed renewal charges exactly one wallet shekel.")
	_record(label + "-immediate", ui, merchant, raid_state)
	if mode == "multi" and worker_id == worker_ids[0]:
		_check(ui._unread_notification and ui._notice_emergency
			and _is_red(ui.notification_button.modulate)
			and _has_worker_fingerprint(ui, worker_ids[1], "expired"),
			"Immediately after the first confirmation, the second worker keeps the indicator red.")
	elif mode == "merchant":
		_check(ui._unread_notification and ui._notice_emergency and _is_red(ui.notification_button.modulate)
			and _worker_fingerprint_count(ui) == 0
			and str(ui._get_merchant_event_fingerprint()).ends_with(":arrived"),
			"Immediately after renewal, the merchant is the sole unread source keeping the button red.")
	else:
		_check(not ui._unread_notification and not ui._notice_emergency and _is_white(ui.notification_button.modulate),
			"Immediately after confirmation, no worker-only unread event remains.")
	await _frames(2)
	_record(label + "-after-frame", ui, merchant, raid_state)
	if mode == "multi" and worker_id == worker_ids[0]:
		_check(ui._unread_notification and ui._notice_emergency and _is_red(ui.notification_button.modulate),
			"After a frame, the other expired worker still keeps the indicator red.")
	elif mode == "merchant":
		_check(ui._unread_notification and ui._notice_emergency and _is_red(ui.notification_button.modulate)
			and _worker_fingerprint_count(ui) == 0,
			"After a frame, the merchant alone keeps the button red.")
	else:
		_check(not ui._unread_notification and not ui._notice_emergency and _is_white(ui.notification_button.modulate),
			"After a frame, the worker-only indicator remains normal.")


func _read_partial_after_continue(city: Node, store: Node, ui: RaidUI, merchant: Node, raid_state: Node) -> void:
	if failures > 0:
		return
	_check(_assert_exact_continue(city, store, _partial_checkpoint_path()),
		"Separate-process partial Continue restores the exact one-renewed/one-expired checkpoint.")
	_check(not ui.notifications_popup.visible, "Partial Continue leaves the notification popup closed.")
	var renewed_worker: WorkerData = WorkerDatabase.get_worker_data(worker_ids[0])
	var expired_worker: WorkerData = WorkerDatabase.get_worker_data(worker_ids[1])
	if renewed_worker == null or expired_worker == null:
		_check(false, "Partial Continue restores both authored workers.")
		return
	_check(renewed_worker != null and not renewed_worker.is_payroll_blocked()
		and renewed_worker.payroll_paid_from_day == TimeComponentManager.current_day
		and renewed_worker.payroll_paid_until_day == TimeComponentManager.current_day + CONTRACT_DAYS,
		"Partial Continue restores the first worker's newly paid entitlement.")
	_check(expired_worker != null and expired_worker.is_payroll_blocked()
		and _now() >= expired_worker.get_paid_end_minute(),
		"Partial Continue restores the second worker as expired and blocked.")
	_check(_worker_fingerprint_count(ui) == 1
		and _has_worker_fingerprint(ui, expired_worker.worker_id, "expired"),
		"The second worker is the sole worker notification source after partial Continue.")
	_check(ui._unread_notification and ui._notice_emergency and _is_red(ui.notification_button.modulate),
		"The still-unread second worker keeps the actual HUD button red after partial Continue.")
	_check(int(Inventory.items.get("shekel", 0)) == INITIAL_WALLET - worker_ids.size() - 1
		and CityStockManager.treasury_shekel == 0,
		"Partial Continue restores the one-renewal wallet balance without charging again.")
	_check(str(ui._get_merchant_event_fingerprint()).is_empty() and not merchant.is_present()
		and str(ui._get_raid_event_fingerprint()).is_empty()
		and str(raid_state.phase) in ["unbuilt", "safe"],
		"Merchant and raid sources remain neutral in the partial multi-worker checkpoint.")
	await _capture("partial-read-continued")
	_record("partial-read-continued", ui, merchant, raid_state)


func _read_after_continue(city: Node, store: Node, ui: RaidUI, merchant: Node, raid_state: Node) -> void:
	if failures > 0:
		return
	_check(_assert_exact_continue(city, store, _checkpoint_path()), "Read phase Continue restores the exact renewed checkpoint.")
	_check(not ui.notifications_popup.visible, "Continue leaves the notification popup closed.")
	for worker_id: String in worker_ids:
		var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
		_check(worker != null and worker.payroll_contract_days == CONTRACT_DAYS
			and worker.payroll_paid_until_day == worker.payroll_paid_from_day + CONTRACT_DAYS,
			"Continue restores the paid entitlement for %s." % worker_id)
	_check(_worker_fingerprint_count(ui) == 0 and not _has_worker_notice_text(ui, "Expired"),
		"Continue shows no expired worker notice after renewal.")
	if mode == "merchant":
		_check(merchant.is_present() and str(ui._get_merchant_event_fingerprint()).ends_with(":arrived"),
			"Continue restores the real merchant visit that arrived before saving.")
		_check(ui._unread_notification and ui._notice_emergency and _is_red(ui.notification_button.modulate),
			"The unread merchant arrival alone keeps the Continue indicator red.")
	else:
		_check(not merchant.is_present() and str(ui._get_merchant_event_fingerprint()).is_empty(),
			"Single/multi Continue has no merchant event source.")
		_check(not ui._unread_notification and not ui._notice_emergency and _is_white(ui.notification_button.modulate),
			"Single/multi Continue has no unread source and a normal indicator.")
	await _capture("read-continued")
	_record("read-continued", ui, merchant, raid_state)
	if mode == "merchant":
		ui.notification_button.pressed.emit()
		await _frames(2)
		_check(ui.notifications_popup.visible, "The real notifications button opens the popup.")
		_check(not ui._unread_notification and not ui._notice_emergency and _is_white(ui.notification_button.modulate),
			"Acknowledging the sole merchant event returns the indicator to normal without a raid threat.")
		_record("read-merchant-acknowledged", ui, merchant, raid_state)
		await _capture("read-merchant-acknowledged")


func _assert_exact_continue(city: Node, store: Node, checkpoint_path: String) -> bool:
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(checkpoint_path))
	if not disk is Dictionary:
		_check(false, "Continue checkpoint JSON remains readable.")
		return false
	var restored: Dictionary = store.snapshot.capture(city)
	var equal: bool = _canonical(restored) == _canonical(disk)
	_check(equal, "Separate-process Continue restores every captured checkpoint owner exactly.")
	return equal


func _canonical(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))


func _place_clock(target_minute: int) -> void:
	TimeComponentManager.current_day = floori(float(target_minute) / 1440.0)
	var minute_of_day: int = posmod(target_minute, 1440)
	TimeComponentManager.current_hour = minute_of_day / 60
	TimeComponentManager.current_minute = minute_of_day % 60
	TimeComponentManager.current_weather = "clear"
	TimeComponentManager._timer = 0.0
	TimeComponentManager.emit_time_signal()


func _select_hire_day(start_day: int, first_visit_day: int, interval_days: int) -> int:
	if interval_days <= 0:
		return -1
	for offset: int in range(interval_days):
		var candidate: int = start_day + offset
		var expiry_day: int = candidate + EXPIRY_OFFSET_DAYS
		if posmod(expiry_day - first_visit_day, interval_days) == 0 \
			and posmod(candidate - first_visit_day, interval_days) != 0:
			return candidate
	return -1


func _is_merchant_visit_day(day: int, first_visit_day: int, interval_days: int) -> bool:
	return day >= first_visit_day and interval_days > 0 \
		and posmod(day - first_visit_day, interval_days) == 0


func _worker_fingerprint_count(ui: RaidUI) -> int:
	return ui._worker_notification_fingerprints.size()


func _has_worker_fingerprint(ui: RaidUI, worker_id: String, status: String) -> bool:
	for key: Variant in ui._worker_notification_fingerprints:
		if str(key).begins_with("worker:%s:" % worker_id) and str(key).ends_with(":%s" % status):
			return true
	return false


func _has_worker_notice_text(ui: RaidUI, phrase: String) -> bool:
	for child: Node in ui.worker_notices_list.get_children():
		if child is Label and str((child as Label).text).contains(phrase):
			return true
	return false


func _is_red(color: Color) -> bool:
	return color.r > color.g and color.r > color.b


func _is_white(color: Color) -> bool:
	return is_equal_approx(color.r, 1.0) and is_equal_approx(color.g, 1.0) \
		and is_equal_approx(color.b, 1.0) and is_equal_approx(color.a, 1.0)


func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute


func _record(label: String, ui: RaidUI, merchant: Node, raid_state: Node) -> void:
	var workers: Array[Dictionary] = []
	for worker_id: String in worker_ids:
		var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
		if worker == null:
			workers.append({"id": worker_id, "status": "missing"})
			continue
		var status: String = "normal"
		if worker.payroll_paid_from_day < 0 or worker.payroll_paid_until_day < 0:
			status = "pending"
		elif worker.is_payroll_blocked() and _now() >= worker.get_paid_end_minute():
			status = "expired"
		elif TimeComponentManager.current_day >= worker.payroll_paid_until_day - 1:
			status = "expiring"
		workers.append({"id": worker_id, "name": worker.get_resolved_display_name(),
			"status": status, "blocked": worker.is_payroll_blocked(),
			"paid_from_day": worker.payroll_paid_from_day, "paid_until_day": worker.payroll_paid_until_day,
			"paid_start_minute": worker.get_paid_start_minute(), "paid_end_minute": worker.get_paid_end_minute(),
			"contract_days": worker.payroll_contract_days})
	var color: Color = ui.notification_button.modulate
	var fingerprints: Dictionary = {
		"workers": ui._worker_notification_fingerprints.duplicate(true),
		"merchant": ui._get_merchant_event_fingerprint(),
		"raid": ui._get_raid_event_fingerprint(),
	}
	var observation: Dictionary = {
		"phase": phase, "mode": mode, "label": label, "clock_minute": _now(),
		"unread_notification": ui._unread_notification, "notice_emergency": ui._notice_emergency,
		"notification_color": color.to_html(true), "notification_color_components": [color.r, color.g, color.b, color.a],
		"notification_popup_open": ui.notifications_popup.visible,
		"fingerprint_sources": fingerprints, "seen_keys": ui._get_notification_seen_keys(),
		"workers": workers, "wallet_shekel": int(Inventory.items.get("shekel", 0)),
		"city_treasury_shekel": CityStockManager.treasury_shekel,
		"merchant_present": merchant.is_present(), "raid_phase": str(raid_state.phase),
	}
	print("ExpiredNoticeDiagnostic ", JSON.stringify(observation))
	var directory: String = ProjectSettings.globalize_path(_profile_dir())
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(_observation_path(label), FileAccess.WRITE)
	if file == null:
		_check(false, "Write diagnostic record %s: %s" % [label, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(observation, "\t"))
	file.close()


func _capture(label: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image.is_empty():
		_check(false, "Capture rendered PNG %s in a graphical display profile." % label)
		return
	var directory: String = ProjectSettings.globalize_path(_profile_dir())
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = _profile_dir().path_join("%s-%s.png" % [phase, label])
	_check(image.save_png(ProjectSettings.globalize_path(path)) == OK,
		"Save rendered notification evidence %s." % label)


func _profile_dir() -> String:
	return PROFILE_ROOT.path_join(mode)


func _phase_checkpoint_path() -> String:
	return _partial_checkpoint_path() if phase == "partial-read" else _checkpoint_path()


func _checkpoint_path() -> String:
	return _profile_dir().path_join("checkpoint.json")


func _partial_checkpoint_path() -> String:
	return _profile_dir().path_join("partial-checkpoint.json")


func _observation_path(label: String) -> String:
	return _profile_dir().path_join("%s-%s.json" % [phase, label])


func _press_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = action
	get_viewport().push_input(event)
	await get_tree().process_frame


func _frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _finish() -> void:
	get_tree().paused = false
	print("ExpiredNoticeRegression %s %s: %s (%d failures)" % [mode, phase,
		"PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures > 0 else 0)
