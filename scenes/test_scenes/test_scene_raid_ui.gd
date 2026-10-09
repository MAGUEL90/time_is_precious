extends Node

## Presentation fixture only; these report values do not alter game balance/data.
class DisplayState extends Node:
	signal changed
	var status: Dictionary = {"phase": "attacking", "hp": 32, "max_hp": 50,
		"level": 1, "defend": 2, "seconds_left": 59.9, "raids_enabled": true,
		"status_text": "Raiders are attacking the castle wall!", "can_build": false, "can_repair": false,
		"work_kind": "", "work_remaining": 0, "work_total": 0, "work_message": "",
		"travel_total_minutes": 4320, "arrival_minutes_remaining": 1440}
	var report: Dictionary = {}
	func get_status() -> Dictionary:
		return status.duplicate(true)
	func get_last_report() -> Dictionary:
		return report.duplicate(true)

class DisplayMerchant extends Node:
	signal changed
	var status_text: String = "Next merchant: Tomorrow at 09:00"
	func get_status_text() -> String:
		return status_text

var failures: int = 0
var ui: CanvasLayer
var state: DisplayState
var world_indicator: WallWorldIndicator
var test_player: Player
var merchant: DisplayMerchant

func _ready() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	TimeComponentManager.set_process(false)
	test_player = preload("res://scenes/player/player.tscn").instantiate() as Player
	test_player.debug_disable_player_needs = true
	(test_player.get_node("Camera2D") as Camera2D).enabled = false
	add_child(test_player)
	state = DisplayState.new()
	add_child(state)
	merchant = DisplayMerchant.new()
	add_child(merchant)
	ui = preload("res://scenes/raid/raid_ui.tscn").instantiate()
	add_child(ui)
	ui.bind_state(state)
	ui.set_city_management_available(true)
	ui.bind_merchant_state(merchant)
	world_indicator = preload("res://scenes/raid/wall_world_indicator.tscn").instantiate()
	add_child(world_indicator)
	world_indicator.bind_state(state)
	await get_tree().process_frame
	_expect(not ui.status_panel.visible, "The persistent bottom-right raid card stays hidden.")
	_expect(ui.notification_button.visible, "The exclamation shortcut is available on the city map.")
	_expect(not ui.raid_notice.visible, "Detected raid text no longer overlaps the top HUD.")
	_expect(world_indicator.visible and world_indicator.progress_bar.value == 32.0, "An active raid shows current wall HP above the wall.")
	_expect(ui.hp_bar.value == 32 and ui.hp_bar.max_value == 50, "HP display follows authoritative current/max values.")
	_expect("60" in ui.time_left_label.text, "Fractional remaining seconds round up so the first second stays visible.")
	_expect(not ui.details_panel.visible, "An active raid keeps City Management closed until the player opens it.")
	ui.notification_button.pressed.emit()
	await get_tree().process_frame
	_expect(ui.notifications_popup.visible, "The exclamation shortcut opens the compact notifications popup.")
	_expect(ui.merchant_notice_label.text.contains("Tomorrow") and ui.notification_raid_label.text.contains("attacking"), "Notifications include live merchant status and the active raid.")
	_expect(ui.notification_button.modulate.r > ui.notification_button.modulate.g, "The notification icon turns red during an active threat.")
	_check_notification_bounds()
	player_pause_guard(true)
	ui.notifications_city_button.pressed.emit()
	_expect(not ui.details_panel.visible and ui.notifications_popup.visible, "The City Management action is blocked while the player cannot move.")
	player_pause_guard(false)
	ui.notifications_city_button.pressed.emit()
	_expect(ui.details_panel.visible and not ui.notifications_popup.visible, "The notification action opens City Management and closes the popup.")
	_expect(ui.travel_progress.visible and is_equal_approx(ui.travel_progress.progress_ratio, 2.0 / 3.0), "Detected travel progress uses the scheduled remaining time.")
	_expect(ui.status_detail_label.has_theme_color_override("font_color"), "The City Management threat status is red while raiders are attacking.")
	ui.close_details()
	await _capture("raid-hp.png")
	state.status = {"phase": "safe", "hp": 50, "max_hp": 50, "level": 0, "defend": 2,
		"seconds_left": 0.0, "raids_enabled": true, "status_text": "Wall construction is underway.",
		"can_build": false, "can_repair": false, "work_kind": "build", "work_remaining": 60,
		"work_total": 120, "work_message": "Wall construction started.",
		"travel_total_minutes": 4320, "arrival_minutes_remaining": 4320}
	state.changed.emit()
	await get_tree().process_frame
	_expect(ui.notification_raid_label.text == "No raiders detected.", "The notifications popup does not reveal undetected departures.")
	_expect(not ui.travel_progress.visible, "The City Management travel row is hidden before detection.")
	_expect(world_indicator.visible, "Construction progress appears above the wall while work is active.")
	_expect(world_indicator.progress_bar.value == 60.0, "World construction progress reflects a halfway job.")
	state.status.work_kind = ""
	state.status.work_remaining = 0
	state.changed.emit()
	await get_tree().process_frame
	_expect(not world_indicator.visible, "The world marker hides when wall work finishes.")
	state.status.phase = "attacking"
	state.status.hp = 19
	state.changed.emit()
	await get_tree().process_frame
	_expect(world_indicator.visible and world_indicator.progress_bar.value == 19.0, "An attack shows the live wall HP bar at the wall.")
	state.status.phase = "warning"
	state.status.arrival_minutes_remaining = 720
	state.changed.emit()
	await get_tree().process_frame
	TimeComponentManager.time_changed.emit(5, 0, 0, "clear")
	await get_tree().process_frame
	_expect(is_equal_approx(ui.travel_progress.progress_ratio, 5.0 / 6.0), "The travel icon advances from scheduled ETA updates during the warning phase.")
	state.status = {"phase": "looting", "hp": 0, "max_hp": 50, "level": 1, "defend": 2,
		"seconds_left": 18.0, "loot_seconds_remaining": 18.0, "raids_enabled": true,
		"status_text": "The wall is breached. Raiders are looting City Storage!", "can_build": false, "can_repair": false,
		"work_kind": "", "work_remaining": 0, "work_total": 0, "work_message": "",
		"travel_total_minutes": 4320, "arrival_minutes_remaining": 0,
		"stolen_so_far": {"apple": 2}, "loot_weight": 3.5, "loot_capacity_weight": 8.0}
	state.report = {"id": 99, "outcome": "breached", "stolen": {"apple": 1}}
	state.changed.emit()
	await get_tree().process_frame
	_expect(not ui.details_panel.visible, "An older raid report does not reopen while a new raid is looting.")
	_expect(ui.attack_warning.visible and ui.notification_button.modulate.r > ui.notification_button.modulate.g, "The red threat indicator remains active during looting.")
	_expect(ui.time_left_label.text == "Looting: 18s", "The active loot timer is shown in the raid status data.")
	_expect(world_indicator.visible and world_indicator.progress_bar.value == 0.0, "The world marker keeps showing wall HP at zero while the city is being looted.")
	_expect(ui.travel_progress.visible and is_equal_approx(ui.travel_progress.progress_ratio, 1.0), "The detected raider marker stays at the castle during looting.")
	_expect(ui.travel_eta_label.text.contains("Looted: 2 items") and ui.travel_eta_label.text.contains("3.50 / 8.00"), "Live looting displays the stolen count and weight.")
	_expect(ui.status_detail_label.has_theme_color_override("font_color"), "City Management keeps threat status red during looting.")
	ui.notification_button.pressed.emit()
	_expect(ui.notification_raid_label.text.contains("looting City Storage") and ui.notification_raid_label.text.contains("18s"), "Notifications identify the active loot and its countdown.")
	ui.notification_button.pressed.emit()
	state.report = {}
	state.status.phase = "recovery"
	state.status.hp = 0
	state.status.status_text = "Raiders have withdrawn. The city has time to recover."
	state.report = {"id": 1, "outcome": "breached", "day": 4, "hits": 6,
		"wall_damage": 50, "stolen": {"apple": 4, "simple_clothes": 2},
		"buildings_destroyed": {"Castle wall": 1}, "satisfaction_drop": 0.075,
		"citizens_fled": ["Arad"], "breach_seconds": 28.5, "looting_seconds": 22.0,
		"loot_weight": 3.5, "loot_capacity_weight": 8.0,
		"loot_preference": "valuables", "retreat_reason": "capacity_full"}
	state.changed.emit()
	await get_tree().process_frame
	_expect(ui.details_panel.visible, "A new report opens once.")
	_expect("7.5 pp" in ui.report_text, "Satisfaction uses actual percentage-point loss rather than relative percent.")
	_expect("1" in ui.report_text and "Arad" in ui.report_text and "Castle wall" in ui.report_text, "Report identifies the actual destruction and citizens who fled.")
	_expect("Breach after: 29s" in ui.report_text and "Looting: 22s" in ui.report_text, "Report shows breach timing and time spent looting.")
	_expect("Loot weight: 3.50 / 8.00" in ui.report_text and "Valuables" in ui.report_text and "carrying capacity was full" in ui.report_text, "Report explains carried weight, loot preference and withdrawal reason.")
	_expect("Raiders repelled" not in ui.report_text, "Breach outcome is not reported as victory.")
	_check_bounds()
	await _capture("raid-report.png")
	ui.close_details()
	state.changed.emit()
	_expect(not ui.details_panel.visible, "Refreshing the same report does not reopen it.")
	ui.bind_state(state)
	_expect(state.changed.get_connections().size() == 2, "Rebinding the same ledger avoids duplicate UI refresh signals alongside the world marker.")
	var long_names: Array[String] = []
	for index: int in range(35):
		long_names.append("Citizen with a very long recorded name %d" % index)
	state.report.id = 2
	state.report.citizens_fled = long_names
	state.changed.emit()
	await get_tree().process_frame
	_check_bounds()
	var scroll: ScrollContainer = ui.report_label.get_parent()
	_expect(scroll.get_v_scroll_bar().max_value > scroll.size.y, "Long reports scroll instead of growing beyond the panel.")
	await _capture("raid-report-long.png")
	var before: Dictionary = state.report.duplicate(true)
	ui.close_details()
	ui.open_details()
	_expect(state.report == before, "Opening/closing report never applies or mutates losses.")
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	Input.parse_input_event(escape)
	await get_tree().process_frame
	_expect(not ui.details_panel.visible and not get_tree().paused, "Escape closes wall details without pausing gameplay.")
	var replacement := DisplayState.new()
	add_child(replacement)
	ui.bind_state(replacement)
	_expect(state.changed.get_connections().size() == 1, "Switching ledgers disconnects the UI callback and leaves only the map-owned marker.")
	ui.bind_state(null)
	_expect(not ui.status_panel.visible and not ui.details_panel.visible, "Unbound UI cannot present stale castle state.")
	_expect(replacement.changed.get_connections().is_empty(), "Unbinding removes the remaining connection.")
	world_indicator.bind_state(null)
	_expect(state.changed.get_connections().is_empty(), "Removing the map-owned marker disconnects its ledger signal.")
	world_indicator.queue_free()
	ui.set_city_management_available(false)
	_expect(not ui._city_management_available, "Leaving the city map removes the shortcut.")
	_expect(not ui.notification_button.visible and not ui.notifications_popup.visible, "Leaving the city map closes and hides notifications.")
	ui.bind_merchant_state(null)
	_expect(merchant.changed.get_connections().is_empty(), "Merchant status subscriptions are cleaned up.")
	print("RaidUITest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _check_bounds() -> void:
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	_expect(viewport_rect.encloses(ui.details_panel.get_global_rect()), "Report remains inside the logical viewport.")

func _check_notification_bounds() -> void:
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	_expect(viewport_rect.encloses(ui.notifications_popup.get_global_rect()), "Notifications popup remains inside the logical viewport.")

func player_pause_guard(paused: bool) -> void:
	test_player.can_move = not paused

func _capture(file_name: String) -> void:
	var folder: String = OS.get_environment("TIP_RAID_CAPTURE_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(file_name))
