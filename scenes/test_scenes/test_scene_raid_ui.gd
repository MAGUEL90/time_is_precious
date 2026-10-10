extends Node

## Presentation fixture only; these report values do not alter game balance/data.
class DisplayState extends Node:
	signal changed
	var status: Dictionary = {"phase": "attacking", "hp": 32, "max_hp": 50,
		"level": 1, "defend": 2, "seconds_left": 59.9, "raids_enabled": true,
		"status_text": "Raiders are attacking the castle wall!", "can_build": false, "can_repair": false,
		"work_kind": "", "work_remaining": 0, "work_total": 0, "work_message": "",
		"travel_total_minutes": 5760, "arrival_minutes_remaining": 1440, "party_id": 1,
		"units": [
			{"id": "light", "display_name": "Light", "count": 2, "attack": 1, "travel_days": 2},
			{"id": "normal", "display_name": "Normal", "count": 1, "attack": 2, "travel_days": 3},
			{"id": "heavy", "display_name": "Heavy", "count": 3, "attack": 4, "travel_days": 4}],
		"watchtower_built": false, "warning_days": 2, "can_inspect": false, "raider_type": "Unknown"}
	var report: Dictionary = {}
	func get_status() -> Dictionary:
		return status.duplicate(true)
	func get_last_report() -> Dictionary:
		return report.duplicate(true)
	func inspect_raiders() -> Dictionary:
		if not bool(status.get("watchtower_built", false)) or not bool(status.get("can_inspect", false)):
			return {}
		var result: Dictionary = {"id": int(status.get("party_id", 1)),
			"type": str(status.get("raider_type", "Unknown")),
			"arrival_minutes_remaining": int(status.get("arrival_minutes_remaining", 0)),
			"travel_total_minutes": int(status.get("travel_total_minutes", 0)),
			"total_count": 6, "attack_strength": 16,
			"phase": str(status.get("phase", ""))}
		if status.has("units"):
			result["units"] = status["units"]
		return result

class DisplayMerchant extends Node:
	signal changed
	var status_text: String = "Next merchant: Tomorrow at 09:00"
	func get_status_text() -> String:
		return status_text

var failures: int = 0
var ui: CanvasLayer
var inspection_panel: Control
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
	inspection_panel = ui.get_node("Root/RaiderInspectionPanel")
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
	_expect(not ui.notifications_city_button.visible, "Notifications no longer show a City Management button.")
	_expect(ui.merchant_notice_label.text.begins_with("- ") and ui.notification_raid_label.text.begins_with("- "), "Separate notices have bullet markers.")
	_expect(ui.get_node("Root/NotificationsPopup/Margin/Contents/TitleLabel").get_theme_font_size("font_size") == 6, "Notifications title uses pixel font size 6.")
	ui.open_details()
	_expect(ui.details_panel.visible and not ui.notifications_popup.visible, "Opening current city closes notifications.")
	_expect(ui.travel_progress.visible and is_equal_approx(ui.travel_progress.progress_ratio, 3.0 / 4.0), "Detected travel progress uses the scheduled remaining time.")
	_expect(ui.status_detail_label.has_theme_color_override("font_color"), "The City Management threat status is red while raiders are attacking.")
	_expect(ui.watchtower_status_label.text.contains("Unknown"), "Current city shows raiders as unknown when the watchtower is missing.")
	_expect(ui.inspect_button.visible and ui.inspect_button.disabled, "Inspect is visible during a detected threat but locked without a watchtower.")
	_expect(ui.inspect_button.tooltip_text.is_empty(), "A locked Inspect button has no stale watchtower tooltip.")
	state.status.phase = "warning"
	state.status.watchtower_built = true
	state.status.can_inspect = true
	state.status.raider_type = "Dune raiders"
	state.changed.emit()
	await get_tree().process_frame
	_expect(not ui.inspect_button.disabled, "A completed watchtower enables inspection once raiders are detected.")
	_expect(not ui.watchtower_status_label.text.contains("Dune raiders"), "Raider type remains hidden until the player uses Inspect.")
	ui.inspect_button.pressed.emit()
	_expect(ui.watchtower_status_label.text.contains("6 raiders") and ui.travel_eta_label.text.contains("1d 0h"), "Inspect adds a concise party count while the travel row keeps the ETA.")
	_expect(inspection_panel.visible and not ui.details_panel.visible, "Inspect opens a separate panel above City Management.")
	var inspection_contents: Control = inspection_panel.get_node("Center/Frame/Margin/Contents")
	var cards: HBoxContainer = inspection_contents.get_node("CardsRow")
	_expect(cards.visible and cards.get_child_count() == 3, "Inspection shows one horizontal card for each nonzero raider type.")
	_expect(cards.get_node("UnitCard_Light/CardContents/CountLabel").text == "x 2"
		and cards.get_node("UnitCard_Normal/CardContents/CountLabel").text == "x 1"
		and cards.get_node("UnitCard_Heavy/CardContents/CountLabel").text == "x 3", "Each raider card shows its fixture quantity beneath the icon.")
	_expect(inspection_contents.get_node("TitleLabel").get_theme_font_size("font_size") == 12
		and cards.get_node("UnitCard_Light/CardContents/CountLabel").get_theme_font_size("font_size") == 6, "Inspection uses the requested 12/6 pixel font sizes.")
	await get_tree().process_frame
	await get_tree().process_frame
	var frame: Control = inspection_panel.get_node("Center/Frame")
	_expect(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(frame.get_global_rect()), "The actual inspection frame stays within the logical viewport.")
	_expect(frame.get_global_rect().encloses(inspection_contents.get_global_rect())
		and inspection_contents.get_global_rect().encloses(cards.get_global_rect()), "Three cards and the inspection content fit inside the visible frame.")
	var first_card_id: int = cards.get_child(0).get_instance_id()
	_expect(ui.travel_progress.visible, "Inspect keeps the existing travel bar visible.")
	state.status.arrival_minutes_remaining = 720
	state.changed.emit()
	await get_tree().process_frame
	_expect(ui.watchtower_status_label.text.contains("6 raiders") and ui.travel_eta_label.text.contains("12h 0m"), "Refreshing updates the existing City Management ETA.")
	_expect(inspection_panel.get_node("Center/Frame/Margin/Contents/EtaLabel").text == "Approaching · ETA: 12h 0m"
		and cards.get_child(0).get_instance_id() == first_card_id, "The same party refreshes ETA while keeping its card nodes stable.")
	ui.notification_button.pressed.emit()
	_expect(not inspection_panel.visible and ui._inspected_raiders.is_empty() and not ui.details_panel.visible
		and inspection_panel.get_node("Center/Frame/Margin/Contents/CardsRow").get_child_count() == 0
		and inspection_panel.get_node("Center/Frame/Margin/Contents/PartyTypeLabel").text == "Raider party",
		"Opening notifications closes Inspect, clears its hidden cards, and closes City Management.")
	ui.notification_button.pressed.emit()
	ui.open_details()
	ui.inspect_button.pressed.emit()
	_expect(cards.get_child_count() == 3, "Reopening Inspect rebuilds a single set of cards without duplicates.")
	var back_button: Button = inspection_panel.get_node("Center/Frame/Margin/Contents/FooterRow/BackButton")
	back_button.pressed.emit()
	_expect(not inspection_panel.visible and ui.details_panel.visible, "Back returns from Inspect to City Management.")
	ui.inspect_button.pressed.emit()
	await _press_key(KEY_ESCAPE)
	_expect(not inspection_panel.visible and ui.details_panel.visible, "Escape closes Inspect first and returns to City Management.")
	await _press_key(KEY_ESCAPE)
	_expect(not ui.details_panel.visible, "A second Escape closes City Management.")
	ui.open_details()
	ui.inspect_button.pressed.emit()
	await _press_key(KEY_C)
	_expect(not inspection_panel.visible and not ui.details_panel.visible and ui._inspected_raiders.is_empty(), "C closes Inspect and City Management together.")
	ui.open_details()
	ui.inspect_button.pressed.emit()
	state.status.party_id = 2
	state.status.raider_type = "Changed party"
	state.changed.emit()
	await get_tree().process_frame
	_expect(not inspection_panel.visible and ui._inspected_raiders.is_empty() and ui.details_panel.visible,
		"A new party ID closes Inspect and clears prior intelligence until the next click.")
	ui.inspect_button.pressed.emit()
	_expect(inspection_panel.visible and inspection_panel.get_node("Center/Frame/Margin/Contents/PartyTypeLabel").text == "Changed party",
		"Inspect reveals the new party only after a fresh click.")
	state.status.erase("units")
	state.changed.emit()
	await get_tree().process_frame
	_expect(inspection_panel.visible and cards.get_child_count() == 0
		and inspection_panel.get_node("Center/Frame/Margin/Contents/CompositionLabel").text == "Composition unavailable",
		"Legacy inspection data shows unavailable composition without inventing unit counts.")
	state.status.phase = "attacking"
	state.changed.emit()
	await get_tree().process_frame
	_expect(not inspection_panel.visible and ui._inspected_raiders.is_empty(), "The warning-to-combat transition closes Inspect and clears its details.")
	ui.open_details()
	ui.inspect_button.pressed.emit()
	_expect(inspection_panel.get_node("Center/Frame/Margin/Contents/EtaLabel").text == "Attacking · ETA: now",
		"An inspection during combat shows its current phase without adding effects.")
	state.status.phase = "looting"
	state.changed.emit()
	await get_tree().process_frame
	_expect(inspection_panel.visible and inspection_panel.get_node("Center/Frame/Margin/Contents/EtaLabel").text == "Looting · ETA: now",
		"The same inspected party refreshes to the authoritative looting phase.")
	state.status.watchtower_built = false
	state.status.can_inspect = false
	state.status.raider_type = "Unknown"
	state.changed.emit()
	await get_tree().process_frame
	_expect(ui.inspect_button.disabled and not inspection_panel.visible and ui.watchtower_status_label.text.contains("Unknown") and not ui.watchtower_status_label.text.contains("Changed party"), "Losing inspection permission clears previously shown intelligence.")
	ui.close_details()
	await _capture("raid-hp.png")
	state.status = {"phase": "safe", "hp": 50, "max_hp": 50, "level": 0, "defend": 2,
		"seconds_left": 0.0, "raids_enabled": true, "status_text": "Wall construction is underway.",
		"can_build": false, "can_repair": false, "work_kind": "build", "work_remaining": 60,
		"work_total": 120, "work_message": "Wall construction started.",
		"travel_total_minutes": 4320, "arrival_minutes_remaining": 4320,
		"watchtower_built": true, "warning_days": 5, "can_inspect": false, "raider_type": "Unknown"}
	state.changed.emit()
	await get_tree().process_frame
	_expect(ui.notification_raid_label.text == "- No raiders detected.", "The notifications popup does not reveal undetected departures.")
	ui.open_details()
	_expect(ui.watchtower_status_label.text.contains("Built") and not ui.inspect_button.visible, "A completed watchtower remains compact and Inspect stays hidden during the undetected journey.")
	ui.close_details()
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
	_expect(ui.result_box.visible and not ui.report_scroll.visible, "Raid results use compact UI instead of the long report.")
	ui.close_details()
	ui.open_details()
	_expect(not ui.result_box.visible and ui.report_toggle.visible, "Reopening city management defaults to current state, with optional last raid.")
	state.status.phase = "warning"
	state.status.arrival_minutes_remaining = 1440
	state.status.watchtower_built = true
	state.status.can_inspect = true
	state.status.raider_type = "Marsh raiders"
	state.changed.emit()
	await get_tree().process_frame
	_expect(ui.travel_progress.visible and not ui.result_box.visible, "A new detected party displays travel even with a previous raid report.")
	_expect(ui.watchtower_status_label.text.contains("Unknown") and not ui.watchtower_status_label.text.contains("Dune raiders"), "Previous party intelligence is cleared for a new journey until Inspect is used again.")
	ui.inspect_button.pressed.emit()
	_expect(ui.watchtower_status_label.text.contains("6 raiders")
		and inspection_panel.get_node("Center/Frame/Margin/Contents/PartyTypeLabel").text.contains("Marsh raiders"),
		"Inspect reveals the current party panel and a concise count after the previous report.")
	var before_progress: float = ui.travel_progress.progress_ratio
	state.status.arrival_minutes_remaining = 720
	TimeComponentManager.time_changed.emit(6, 0, 0, "clear")
	_expect(ui.travel_progress.progress_ratio > before_progress, "The next raid progress continues moving after the first report.")
	state.status.phase = "recovery"
	state.changed.emit()
	_expect(not inspection_panel.visible and ui._inspected_raiders.is_empty() and cards.get_child_count() == 0,
		"The inspection panel and its hidden card data clear when the raid ends.")
	ui.report_toggle.pressed.emit()

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
	state.status.phase = "warning"
	state.status.watchtower_built = true
	state.status.can_inspect = true
	state.status.party_id = 9
	state.status.raider_type = "Old map raiders"
	state.changed.emit()
	await get_tree().process_frame
	ui.open_details()
	ui.inspect_button.pressed.emit()
	_expect(inspection_panel.visible and not ui._inspected_raiders.is_empty(), "A bound city can hold open inspection data before rebinding.")
	var replacement := DisplayState.new()
	replacement.status.phase = "warning"
	replacement.status.watchtower_built = true
	replacement.status.can_inspect = true
	replacement.status.party_id = 10
	replacement.status.raider_type = "Fresh raiders"
	add_child(replacement)
	ui.bind_state(replacement)
	_expect(not inspection_panel.visible and ui._inspected_raiders.is_empty()
		and inspection_panel.get_node("Center/Frame/Margin/Contents/PartyTypeLabel").text == "Raider party",
		"Rebinding to another map closes Inspect and clears the prior party details.")
	_expect(state.changed.get_connections().size() == 1, "Switching ledgers disconnects the UI callback and leaves only the map-owned marker.")
	replacement.status.watchtower_built = true
	replacement.status.can_inspect = true
	replacement.status.raider_type = "Fresh raiders"
	replacement.changed.emit()
	await get_tree().process_frame
	ui.open_details()
	ui.inspect_button.pressed.emit()
	_expect(not ui._inspected_raiders.is_empty(), "The current map has transient inspected party details before exit.")
	ui.set_city_management_available(false)
	_expect(ui._inspected_raiders.is_empty() and not ui.details_panel.visible and not inspection_panel.visible
		and inspection_panel.get_node("Center/Frame/Margin/Contents/CardsRow").get_child_count() == 0,
		"Leaving the city map clears inspection details and closes City Management.")
	ui.bind_state(null)
	_expect(not ui.status_panel.visible and not ui.details_panel.visible, "Unbound UI cannot present stale castle state.")
	_expect(replacement.changed.get_connections().is_empty(), "Unbinding removes the remaining connection.")
	world_indicator.bind_state(null)
	_expect(state.changed.get_connections().is_empty(), "Removing the map-owned marker disconnects its ledger signal.")
	world_indicator.queue_free()
	_expect(not ui._city_management_available, "Leaving the city map removes the shortcut.")
	_expect(not ui.notification_button.visible and not ui.notifications_popup.visible, "Leaving the city map closes and hides notifications.")
	ui.bind_merchant_state(null)
	_expect(merchant.changed.get_connections().is_empty(), "Merchant status subscriptions are cleaned up.")
	print("RaidUITest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _check_bounds() -> void:
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	_expect(viewport_rect.encloses(ui.details_panel.get_global_rect()), "Report remains inside the logical viewport.")
	_expect(viewport_rect.encloses(inspection_panel.get_node("Center/Frame").get_global_rect()), "The inspection frame remains inside the logical viewport.")

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

func _press_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
