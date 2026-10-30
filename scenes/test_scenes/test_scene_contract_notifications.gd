extends Node

class DisplayState extends Node:
	signal changed
	var notification_seen_keys: Dictionary = {}
	var _expedition_sequence: int = 5
	var _report_sequence: int = 0
	var status: Dictionary = {
		"phase": "safe", "hp": 50, "max_hp": 50, "level": 1, "defend": 2,
		"seconds_left": 0.0, "raids_enabled": true,
		"status_text": "No signs of raiders.", "can_build": false, "can_repair": false,
		"work_kind": "", "work_remaining": 0, "work_total": 0, "work_message": "",
		"travel_total_minutes": 2880, "arrival_minutes_remaining": 1440,
		"watchtower_built": false, "warning_days": 2, "can_inspect": false,
		"raider_type": "Unknown",
	}
	var report: Dictionary = {}

	func get_status() -> Dictionary:
		return status.duplicate(true)

	func get_last_report() -> Dictionary:
		return report.duplicate(true)

	func inspect_raiders() -> Dictionary:
		return {}

class DisplayMerchant extends Node:
	signal changed
	var config: Resource = preload("res://resources/traveling_merchant/common_merchant.tres")
	var _visit_day: int = -1
	var _present: bool = false
	var status_text: String = "Next merchant: Tomorrow at 08:00"

	func is_present() -> bool:
		return _present

	func get_status_text() -> String:
		return status_text

class DisplayCityProgression extends Node:
	signal changed
	var level: int = 1
	var progress: int = 0
	var last_event: String = ""
	var last_daily: Dictionary = {}

const TEST_DAY: int = 10
const CONTRACT_FROM_DAY: int = 9
const CONTRACT_UNTIL_DAY: int = 11

var failures: int = 0
var ui: RaidUI
var state: DisplayState
var merchant: DisplayMerchant
var test_player: Player

func _ready() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	get_tree().paused = false
	TimeComponentManager.is_paused = false
	TimeComponentManager.set_process(false)
	_set_clock(TEST_DAY, 10, 0, false)
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()

	test_player = preload("res://scenes/player/player.tscn").instantiate() as Player
	test_player.debug_disable_player_needs = true
	(test_player.get_node("Camera2D") as Camera2D).enabled = false
	add_child(test_player)
	state = DisplayState.new()
	add_child(state)
	merchant = DisplayMerchant.new()
	add_child(merchant)
	var city_progression := DisplayCityProgression.new()
	add_child(city_progression)
	ui = preload("res://scenes/raid/raid_ui.tscn").instantiate() as RaidUI
	add_child(ui)
	ui.bind_state(state)
	ui.set_city_management_available(true)
	ui.bind_merchant_state(merchant)
	ui.bind_city_progression(city_progression)
	await get_tree().process_frame

	var new_contract: WorkerData = _make_paid_worker("notice_new", "New contract worker", true)
	var legacy_contract: WorkerData = _make_paid_worker("notice_legacy", "Legacy contract worker", false)
	var pending_worker: WorkerData = _make_pending_worker("notice_pending", "Pending contract worker")
	WorkerDatabase.workers_by_id[new_contract.worker_id] = new_contract
	WorkerDatabase.workers_by_id[legacy_contract.worker_id] = legacy_contract
	WorkerDatabase.workers_by_id[pending_worker.worker_id] = pending_worker
	WorkerDatabase.payroll_changed.emit()
	await get_tree().process_frame
	_expect(new_contract.get_paid_end_minute() == (CONTRACT_UNTIL_DAY + 1) * 1440 + 420,
		"A new contract keeps its exact 07:00 paid-end boundary.")
	_expect(legacy_contract.get_paid_end_minute() == (CONTRACT_UNTIL_DAY + 1) * 1440 + 480,
		"A legacy contract retains its 08:00 paid-end boundary.")
	_expect(ui._unread_notification and ui._notice_emergency,
		"Near-expiry and pending contracts pulse the existing exclamation button.")
	_expect(_worker_notice_text_contains("New contract worker")
		and _worker_notice_text_contains("Legacy contract worker")
		and _worker_notice_text_contains("Pending contract worker"),
		"The popup lists near-expiry and pending contracts by worker name.")
	_open_notifications()
	_expect(not ui._unread_notification and not ui._notice_emergency,
		"Opening notifications acknowledges current worker contract events.")
	_expect(_seen_worker_key("notice_new", CONTRACT_UNTIL_DAY, "expiring")
		and _seen_worker_key("notice_legacy", CONTRACT_UNTIL_DAY, "expiring")
		and _seen_worker_key("notice_pending", TEST_DAY + 1, "pending"),
		"Acknowledgement stores stable worker ID, expiry and status keys.")
	await _capture("contract-notices")
	var encoded_seen: Variant = JSON.parse_string(JSON.stringify(state.notification_seen_keys))
	_expect(encoded_seen is Dictionary and encoded_seen == state.notification_seen_keys,
		"Notification acknowledgement values remain serializable as raid snapshot state.")
	_close_notifications()

	merchant._visit_day = TimeComponentManager.current_day
	merchant._present = true
	merchant.status_text = "Common merchant | Leaves today at 18:00"
	merchant.changed.emit()
	await get_tree().process_frame
	_expect(ui._unread_notification and ui._notice_emergency
		and ui.notification_button.modulate.r > ui.notification_button.modulate.g,
		"A new merchant arrival pulses the existing exclamation button.")
	_open_notifications()
	_expect(str(state.notification_seen_keys.get("merchant", "")) == "visit:%d:arrived" % merchant._visit_day
		and not ui._unread_notification,
		"Opening notifications acknowledges the merchant visit fingerprint.")
	_close_notifications()

	state.status.phase = "warning"
	state.status.arrival_minutes_remaining = 1440
	state.changed.emit()
	await get_tree().process_frame
	_expect(ui._unread_notification and state.notification_seen_keys.get("raid", "") == "",
		"A newly detected raid phase creates a separate unread event.")
	_open_notifications()
	_expect(str(state.notification_seen_keys.get("raid", "")).ends_with(":warning")
		and not ui._unread_notification,
		"Opening notifications acknowledges the expedition phase.")
	ui.set_process(false)
	var pulse_elapsed: float = ui._notice_elapsed
	var warning_fingerprint: String = str(state.notification_seen_keys.get("raid", ""))
	state.status.arrival_minutes_remaining = 1439
	TimeComponentManager.current_minute = 1
	TimeComponentManager.time_changed.emit(TEST_DAY, 10, 1, "clear")
	await get_tree().process_frame
	var pulse_advance: float = fposmod(ui._notice_elapsed - pulse_elapsed, RaidUI.NOTICE_PULSE_SECONDS)
	_expect(not ui._unread_notification and pulse_advance < 0.25
		and str(state.notification_seen_keys.get("raid", "")) == warning_fingerprint,
		"A countdown-minute refresh keeps the same notification fingerprint and does not restart the pulse.")
	_close_notifications()

	state.status.phase = "attacking"
	state.status.status_text = "Raiders are attacking the castle wall!"
	state.changed.emit()
	await get_tree().process_frame
	_expect(ui.attack_warning.visible and ui._unread_notification,
		"The attack edge warning remains active and its phase creates a new event.")
	_open_notifications()
	_expect(not ui._unread_notification and ui._notice_emergency and ui.attack_warning.visible,
		"Acknowledging notifications preserves the existing active-raid edge warning.")
	_close_notifications()
	state.status.phase = "safe"
	state.status.status_text = "No signs of raiders."
	state.changed.emit()
	await get_tree().process_frame

	_set_clock(TEST_DAY, 18, 0, true)
	merchant._present = false
	merchant.status_text = "Next merchant: Day 13 at 08:00"
	merchant.changed.emit()
	await get_tree().process_frame
	_expect(ui._unread_notification
		and str(state.notification_seen_keys.get("merchant", "")).ends_with(":arrived"),
		"A merchant departure is a new event after the arrival was acknowledged.")
	_open_notifications()
	merchant._visit_day = TEST_DAY + 3
	merchant._present = true
	merchant.status_text = "Common merchant | Leaves today at 18:00"
	merchant.changed.emit()
	await get_tree().process_frame
	_expect(str(state.notification_seen_keys.get("merchant", "")) == "visit:%d:arrived" % merchant._visit_day
		and not ui._unread_notification,
		"A new merchant event that arrives while the popup is open is acknowledged immediately.")
	_close_notifications()

	_set_clock(CONTRACT_UNTIL_DAY + 1, 6, 59, true)
	_expect(not _worker_notice_text_contains("Expired")
		and _worker_notice_text_contains("New contract worker — Paid through Day")
		and _worker_notice_text_contains("Legacy contract worker — Paid through Day"),
		"Both contracts show a near-expiry notice before their exact paid-end hour.")
	_set_clock(CONTRACT_UNTIL_DAY + 1, 7, 0, true)
	_expect(ui._unread_notification and not _seen_worker_key("notice_new", CONTRACT_UNTIL_DAY, "expired")
		and not _seen_worker_key("notice_legacy", CONTRACT_UNTIL_DAY, "expired")
		and _worker_notice_text_contains("New contract worker — Expired")
		and _worker_notice_text_contains("Legacy contract worker — Paid through Day"),
		"A new contract expiry at 07:00 is unread while the legacy contract remains paid through 07:59.")
	_open_notifications()
	_expect(not ui._unread_notification and _seen_worker_key("notice_new", CONTRACT_UNTIL_DAY, "expired"),
		"Opening the popup acknowledges the 07:00 contract expiry.")
	_set_clock(CONTRACT_UNTIL_DAY + 1, 8, 0, true)
	_expect(not ui._unread_notification and _seen_worker_key("notice_legacy", CONTRACT_UNTIL_DAY, "expired")
		and _worker_notice_text_contains("Legacy contract worker — Expired"),
		"A legacy contract expires at 08:00 and the open popup acknowledges it automatically.")

	_expect(WorkerDatabase.dismiss_worker("notice_legacy"), "The legacy fixture worker can be dismissed.")
	_expect(not _has_seen_worker_id("notice_legacy"),
		"Dismissing a worker prunes its obsolete notification acknowledgement.")
	_close_notifications()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.payroll_changed.emit()
	for index: int in range(24):
		var long_name: String = "Citizen with a very long recorded name %02d" % index
		var worker: WorkerData = _make_pending_worker("scroll_%02d" % index, long_name)
		WorkerDatabase.workers_by_id[worker.worker_id] = worker
	WorkerDatabase.payroll_changed.emit()
	await get_tree().process_frame
	_open_notifications()
	await get_tree().process_frame
	await get_tree().process_frame
	_check_scroll_layout()
	await _capture("long-notices")
	_expect(ui._unread_notification == false and ui.worker_notices_list.get_child_count() == 24,
		"Many long worker notices fit inside the scrollable popup and are acknowledged on open.")

	ui.set_city_management_available(false)
	ui.bind_state(null)
	ui.bind_merchant_state(null)
	ui.bind_city_progression(null)
	ui.queue_free()
	state.queue_free()
	merchant.queue_free()
	city_progression.queue_free()
	test_player.queue_free()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	print("ContractNotificationsTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(1 if failures > 0 else 0)

func _make_paid_worker(worker_id: String, worker_name: String, new_contract: bool) -> WorkerData:
	var worker: WorkerData = WorkerData.new()
	worker.worker_id = worker_id
	worker.display_name = worker_name
	worker.payroll_start_day = CONTRACT_FROM_DAY
	worker.payroll_paid_from_day = CONTRACT_FROM_DAY
	worker.payroll_paid_until_day = CONTRACT_UNTIL_DAY
	worker.payroll_period_rate = 1
	worker.payroll_last_attempt_day = CONTRACT_FROM_DAY
	worker.payroll_contract_days = 3 if new_contract else 0
	if new_contract:
		worker.payroll_paid_start_minute = CONTRACT_FROM_DAY * 1440 + 420
	else:
		worker.payroll_paid_start_minute = -1
	return worker

func _make_pending_worker(worker_id: String, worker_name: String) -> WorkerData:
	var worker: WorkerData = WorkerData.new()
	worker.worker_id = worker_id
	worker.display_name = worker_name
	worker.payroll_start_day = TimeComponentManager.current_day + 1
	return worker

func _open_notifications() -> void:
	if not ui.notifications_popup.visible:
		ui.notification_button.pressed.emit()
	await get_tree().process_frame

func _close_notifications() -> void:
	if ui.notifications_popup.visible:
		ui.notification_button.pressed.emit()

func _set_clock(day: int, hour: int, minute: int, emit_signal: bool) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute
	TimeComponentManager.current_weather = "clear"
	if emit_signal:
		TimeComponentManager.time_changed.emit(day, hour, minute, "clear")

func _worker_notice_text_contains(text_value: String) -> bool:
	for child: Node in ui.worker_notices_list.get_children():
		if child is Label and str(child.text).contains(text_value):
			return true
	return false

func _seen_worker_key(worker_id: String, expiry_day: int, status: String) -> bool:
	var key: String = "worker:%s:%d:%s" % [worker_id, expiry_day, status]
	return state.notification_seen_keys.has(key)

func _has_seen_worker_id(worker_id: String) -> bool:
	for key: Variant in state.notification_seen_keys:
		if str(key).begins_with("worker:%s:" % worker_id):
			return true
	return false

func _check_scroll_layout() -> void:
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var popup_rect: Rect2 = ui.notifications_popup.get_global_rect()
	var inner_rect: Rect2 = popup_rect.grow(-16)
	var scroll: ScrollContainer = ui.get_node("Root/NotificationsPopup/Margin/Contents/WorkerNoticesScroll")
	_expect(viewport_rect.encloses(popup_rect), "The contract notification popup stays within the 400x225 viewport.")
	_expect(inner_rect.encloses(scroll.get_global_rect()), "The scroll viewport clears the popup frame and stays inside its contents.")
	_expect(ui.worker_notices_list.get_combined_minimum_size().y > scroll.size.y,
		"Long worker names create a scrollable content height instead of extending the popup.")
	for path: String in ["WorkerNoticesTitleLabel", "MerchantNoticeLabel", "RaidNoticeLabel", "ActionsRow"]:
		var control: Control = ui.get_node("Root/NotificationsPopup/Margin/Contents/" + path)
		_expect(inner_rect.encloses(control.get_global_rect()), "Notification control fits inside the frame: " + path)

func _capture(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://contract_notifications")
	var capture: Image = get_viewport().get_texture().get_image()
	_expect(capture.save_png("user://contract_notifications/%s.png" % file_name) == OK,
		"Notification screenshot is saved.")
