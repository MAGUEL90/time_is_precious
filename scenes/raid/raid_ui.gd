class_name RaidUI extends CanvasLayer

signal build_requested
signal repair_requested

const GAMEPLAY_THEME: Theme = preload("res://resources/ui_gameplay_theme/ui_gameplay_theme.tres")
const THREAT_COLOR: Color = Color(0.96, 0.24, 0.18, 1.0)

@onready var raid_notice: Label = $Root/RaidNotice
@onready var notification_button: Button = $Root/NotificationsButton
@onready var notifications_popup: NinePatchRect = $Root/NotificationsPopup
@onready var merchant_notice_label: Label = $Root/NotificationsPopup/Margin/Contents/MerchantNoticeLabel
@onready var notification_raid_label: Label = $Root/NotificationsPopup/Margin/Contents/RaidNoticeLabel
@onready var notifications_city_button: Button = $Root/NotificationsPopup/Margin/Contents/ActionsRow/CityManagementButton
@onready var travel_progress: RaidTravelProgress = $Root/Center/DetailsPanel/Margin/Contents/TravelProgressRow
@onready var travel_eta_label: Label = $Root/Center/DetailsPanel/Margin/Contents/TravelEtaLabel
@onready var attack_warning: ColorRect = $Root/AttackWarning
@onready var status_panel: Control = $Root/RaidStatusPanel
@onready var status_label: Label = $Root/RaidStatusPanel/Margin/Contents/StatusLabel
@onready var wall_value_label: Label = $Root/RaidStatusPanel/Margin/Contents/WallRow/WallValueLabel
@onready var hp_bar: ProgressBar = $Root/RaidStatusPanel/Margin/Contents/HPBar
@onready var time_left_label: Label = $Root/RaidStatusPanel/Margin/Contents/FooterRow/TimeLeftLabel
@onready var details_panel: Control = $Root/Center/DetailsPanel
@onready var wall_summary_label: Label = $Root/Center/DetailsPanel/Margin/Contents/WallSummaryLabel
@onready var defend_label: Label = $Root/Center/DetailsPanel/Margin/Contents/DefendLabel
@onready var status_detail_label: Label = $Root/Center/DetailsPanel/Margin/Contents/StatusDetailLabel
@onready var action_row: Control = $Root/Center/DetailsPanel/Margin/Contents/ActionRow
@onready var report_scroll: ScrollContainer = $Root/Center/DetailsPanel/Margin/Contents/ReportScroll
@onready var build_button: Button = $Root/Center/DetailsPanel/Margin/Contents/ActionRow/BuildButton
@onready var repair_button: Button = $Root/Center/DetailsPanel/Margin/Contents/ActionRow/RepairButton
@onready var report_label: Label = $Root/Center/DetailsPanel/Margin/Contents/ReportScroll/ReportLabel

const WARNING_PULSE_SECONDS: float = 3.0
var _warning_elapsed: float = 0.0

var raid_state: Node
var merchant_state: Node
var report_text: String = ""
var _status_data: Dictionary = {}
var _last_report: Dictionary = {}
var _last_shown_report_id: int = -1
var _last_phase: String = ""
var _city_management_available: bool = false
var show_last_raid: bool = false
var metrics: HBoxContainer
var wall_meter: ProgressBar
var satisfaction_meter: ProgressBar
var satisfaction_value: Label
var wall_value: Label
var storage_summary: Label
var result_box: VBoxContainer
var result_heading: Label
var result_stats: Label
var loot_slots: HFlowContainer
var result_note: Label
var report_toggle: Button
var _loot_display_key: String = ""


func _ready() -> void:
	visible = true
	status_panel.visible = false
	details_panel.visible = false
	notifications_popup.visible = false
	add_to_group("city_notification_ui")
	notification_button.pressed.connect(_toggle_notifications)
	$Root/NotificationsPopup/Margin/Contents/ActionsRow/CloseButton.pressed.connect(_close_notifications)
	notifications_city_button.hide()
	$Root/RaidStatusPanel/Margin/Contents/FooterRow/DetailsButton.pressed.connect(open_details)
	$Root/Center/DetailsPanel/Margin/Contents/FooterRow/CloseButton.pressed.connect(close_details)
	_create_dashboard()
	_apply_theme()
	if not TimeComponentManager.time_changed.is_connected(_on_clock_changed):
		TimeComponentManager.time_changed.connect(_on_clock_changed)
	CitizenManager.citizen_added.connect(_on_residents_changed)
	CitizenManager.citizen_left.connect(_on_residents_changed)
	bind_merchant_state(WorkStateRuntime.get_node_or_null("CommonTravelingMerchant"))
	refresh()

func _process(delta: float) -> void:
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return
	_warning_elapsed = fmod(_warning_elapsed + delta, WARNING_PULSE_SECONDS)
	# A soft pulse at the edges leaves the center and controls readable.
	attack_warning.modulate.a = 0.65 + 0.35 * (0.5 - 0.5 * cos(TAU * _warning_elapsed / WARNING_PULSE_SECONDS))

func _set_attack_warning(active: bool) -> void:
	if attack_warning.visible != active:
		_warning_elapsed = 0.0
		attack_warning.modulate.a = 0.65
	attack_warning.visible = active
	set_process(active)

func _exit_tree() -> void:
	CitizenManager.citizen_added.disconnect(_on_residents_changed)
	CitizenManager.citizen_left.disconnect(_on_residents_changed)
	_unbind_state()
	_unbind_merchant_state()
	if TimeComponentManager.time_changed.is_connected(_on_clock_changed):
		TimeComponentManager.time_changed.disconnect(_on_clock_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if details_panel.visible:
			close_details()
			get_viewport().set_input_as_handled()
		elif _can_use_city_ui():
			open_details()
		if details_panel.visible:
			get_viewport().set_input_as_handled()
		return
	if notifications_popup.visible and event.is_action_pressed("ui_cancel"):
		_close_notifications()
		get_viewport().set_input_as_handled()
	if details_panel.visible and event.is_action_pressed("ui_cancel"):
		close_details()
		get_viewport().set_input_as_handled()

func bind_state(next_state: Node) -> void:
	if raid_state == next_state:
		refresh()
		return

	_unbind_state()
	raid_state = next_state
	_last_shown_report_id = -1
	_last_phase = ""
	if is_instance_valid(raid_state) and raid_state.has_signal("changed"):
		var changed_callable: Callable = Callable(self, "_on_state_changed")
		if not raid_state.is_connected("changed", changed_callable):
			raid_state.connect("changed", changed_callable)
	refresh()

func open_details() -> void:
	set_process(attack_warning.visible)
	if not is_instance_valid(raid_state):
		return
	_close_notifications()
	show_last_raid = false
	if raid_state.has_method("get_status"):
		_status_data = raid_state.get_status().duplicate(true)
	_render_details()
	details_panel.visible = true

func close_details() -> void:
	details_panel.visible = false
	set_process(attack_warning.visible)

func set_city_management_available(available: bool) -> void:
	_city_management_available = available
	if not available:
		_close_notifications()
		close_details()
	notification_button.visible = available

func bind_merchant_state(next_state: Node) -> void:
	if merchant_state == next_state:
		_refresh_merchant_notice()
		return
	_unbind_merchant_state()
	merchant_state = next_state
	if is_instance_valid(merchant_state) and merchant_state.has_signal("changed"):
		var changed_callable: Callable = Callable(self, "_on_merchant_state_changed")
		if not merchant_state.is_connected("changed", changed_callable):
			merchant_state.connect("changed", changed_callable)
	_refresh_merchant_notice()

func refresh() -> void:
	if not is_instance_valid(raid_state):
		raid_notice.hide()
		_set_attack_warning(false)
		status_panel.visible = false
		details_panel.visible = false
		_status_data.clear()
		_refresh_raid_notice()
		_last_report.clear()
		report_text = "No raid report yet."
		return

	_status_data.clear()
	if raid_state.has_method("get_status"):
		var status_value: Variant = raid_state.call("get_status")
		if status_value is Dictionary:
			_status_data = status_value.duplicate(true)
	var phase: String = str(_status_data.get("phase", ""))
	if phase != _last_phase:
		show_last_raid = false
	# Keep the former top-center notice hidden for compatibility; notifications live in one popup.
	raid_notice.visible = false
	_refresh_raid_notice()
	var raid_active: bool = phase in ["attacking", "looting"]
	_set_attack_warning(raid_active)
	if raid_active and _last_phase not in ["attacking", "looting"]:
		close_details()
	_last_phase = phase
	# Keep the former persistent card hidden; its nodes remain for compatibility.
	status_panel.visible = false
	_render_status()

	_last_report.clear()
	if raid_state.has_method("get_last_report"):
		var report_value: Variant = raid_state.call("get_last_report")
		if report_value is Dictionary:
			_last_report = report_value.duplicate(true)
	_render_details()

	if not raid_active and _last_report.has("id"):
		var report_id: int = int(_last_report.get("id", -1))
		if report_id != _last_shown_report_id:
			_last_shown_report_id = report_id
			open_details()
			show_last_raid = true
			_render_details()

func _unbind_state() -> void:
	close_details()
	if not is_instance_valid(raid_state):
		return
	if raid_state.has_signal("changed"):
		var changed_callable: Callable = Callable(self, "_on_state_changed")
		if raid_state.is_connected("changed", changed_callable):
			raid_state.disconnect("changed", changed_callable)
	raid_state = null
	_refresh_raid_notice()

func _unbind_merchant_state() -> void:
	if not is_instance_valid(merchant_state):
		merchant_state = null
		_refresh_merchant_notice()
		return
	if merchant_state.has_signal("changed"):
		var changed_callable: Callable = Callable(self, "_on_merchant_state_changed")
		if merchant_state.is_connected("changed", changed_callable):
			merchant_state.disconnect("changed", changed_callable)
	merchant_state = null
	_refresh_merchant_notice()

func _on_residents_changed(_citizen: CitizenData) -> void:
	refresh()

func _on_state_changed() -> void:
	refresh()

func _on_merchant_state_changed() -> void:
	_refresh_merchant_notice()

func _on_clock_changed(_day: int, _hour: int, _minute: int, _weather: String) -> void:
	if is_instance_valid(raid_state):
		refresh()

func _toggle_notifications() -> void:
	if notifications_popup.visible:
		_close_notifications()
		return
	if not _can_use_city_ui():
		return
	notifications_popup.visible = true
	_refresh_merchant_notice()
	_refresh_raid_notice()

func _close_notifications() -> void:
	notifications_popup.visible = false

func _open_city_management_from_notifications() -> void:
	if not _can_use_city_ui():
		return
	_close_notifications()
	open_details()

func _can_use_city_ui() -> bool:
	if not _city_management_available or get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return false
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	return is_instance_valid(player) and player.can_move and not player.is_sleeping and not player.is_collapsing

func _refresh_merchant_notice() -> void:
	if not is_instance_valid(merchant_state):
		merchant_notice_label.text = "- Merchant unavailable"
		return
	if merchant_state.has_method("get_status_text"):
		merchant_notice_label.text = "- " + str(merchant_state.call("get_status_text")).replace("Common merchant | Leaves today at ", "Merchant leaves at ")
	else:
		merchant_notice_label.text = "- Merchant unavailable"

func _refresh_raid_notice() -> void:
	var phase: String = str(_status_data.get("phase", ""))
	var threat_active: bool = phase in ["warning", "attacking", "looting"]
	notification_button.modulate = THREAT_COLOR if threat_active else Color.WHITE
	if phase == "warning":
		var remaining: int = maxi(int(_status_data.get("arrival_minutes_remaining", 0)), 0)
		notification_raid_label.text = "Raiders detected. Arrival in %s." % _format_travel_time(remaining)
	elif phase == "attacking":
		notification_raid_label.text = "Raiders are attacking the castle wall."
	elif phase == "looting":
		var seconds_left: float = maxf(0.0, float(_status_data.get("loot_seconds_remaining", 0.0)))
		notification_raid_label.text = "Raiders are looting City Storage. %ds left." % int(ceil(seconds_left))
	else:
		# Do not expose the scheduled journey before its detection phase.
		notification_raid_label.text = "No raiders detected."
	notification_raid_label.text = "- " + notification_raid_label.text
	if threat_active:
		notification_raid_label.add_theme_color_override("font_color", THREAT_COLOR)
	else:
		notification_raid_label.remove_theme_color_override("font_color")

func _format_travel_time(total_minutes: int) -> String:
	var days: int = total_minutes / 1440
	var hours: int = (total_minutes % 1440) / 60
	var minutes: int = total_minutes % 60
	if days > 0:
		return "%dd %dh" % [days, hours]
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm" % minutes

func _render_status() -> void:
	var status_text: String = str(_status_data.get("status_text", ""))
	if status_text.is_empty():
		status_text = _fallback_status(str(_status_data.get("phase", "safe")))
	status_label.text = status_text

	var hp: int = int(_status_data.get("hp", 0))
	var max_hp: int = int(_status_data.get("max_hp", 0))
	var level: int = int(_status_data.get("level", 0))
	if level <= 0:
		wall_value_label.text = "Ruined"
	else:
		wall_value_label.text = "%d / %d" % [hp, max_hp]
	hp_bar.max_value = float(maxi(max_hp, 1))
	hp_bar.value = float(clampi(hp, 0, maxi(max_hp, 1)))

	var phase: String = str(_status_data.get("phase", "safe"))
	if bool(_status_data.get("raids_enabled", true)) and phase in ["attacking", "looting"]:
		var seconds_left: float = maxf(0.0, float(_status_data.get("seconds_left", 0.0)))
		time_left_label.text = ("Looting: %ds" if phase == "looting" else "Raid: %ds") % int(ceil(seconds_left))
	elif not str(_status_data.get("work_kind", "")).is_empty():
		time_left_label.text = "Work: %dm" % int(_status_data.get("work_remaining", 0))
	elif level <= 0:
		time_left_label.text = "Wall ruins"
	else:
		time_left_label.text = "Wall level %d" % level

func _render_details() -> void:
	var hp: int = int(_status_data.get("hp", 0))
	var max_hp: int = int(_status_data.get("max_hp", 0))
	var level: int = int(_status_data.get("level", 0))
	if level <= 0:
		wall_summary_label.text = "Castle wall durability: Ruined · Level 0"
	else:
		wall_summary_label.text = "Castle HP (wall durability): %d / %d · Level %d" % [hp, max_hp, level]

	var raids_enabled: bool = bool(_status_data.get("raids_enabled", true))
	defend_label.visible = raids_enabled
	if raids_enabled:
		defend_label.text = "Defend: %s" % str(_status_data.get("defend", "—"))

	var status_text: String = str(_status_data.get("status_text", ""))
	if status_text.is_empty():
		status_text = _fallback_status(str(_status_data.get("phase", "safe")))
	var phase: String = str(_status_data.get("phase", ""))
	var detected_threat: bool = phase in ["warning", "attacking", "looting"]
	if detected_threat:
		status_detail_label.add_theme_color_override("font_color", THREAT_COLOR)
	else:
		status_detail_label.remove_theme_color_override("font_color")
	status_detail_label.text = status_text
	travel_progress.visible = detected_threat
	travel_eta_label.visible = detected_threat
	if detected_threat:
		var travel_total: int = maxi(int(_status_data.get("travel_total_minutes", 0)), 1)
		var arrival_remaining: int = clampi(int(_status_data.get("arrival_minutes_remaining", 0)), 0, travel_total)
		travel_progress.set_travel_progress(travel_total, arrival_remaining)
		if phase == "warning":
			travel_eta_label.text = "Estimated arrival: %s" % _format_travel_time(arrival_remaining)
		elif phase == "looting":
			var seconds_left: float = maxf(0.0, float(_status_data.get("loot_seconds_remaining", 0.0)))
			travel_eta_label.text = "Raiders inside the city · %ds left" % int(ceil(seconds_left))
			var stolen_units: int = 0
			for count: Variant in _status_data.get("stolen_so_far", {}).values():
				stolen_units += int(count)
			travel_eta_label.text += "\nLooted: %d items · Weight: %.2f / %.2f" % [stolen_units, float(_status_data.get("loot_weight", 0.0)), float(_status_data.get("loot_capacity_weight", 0.0))]
		else:
			travel_eta_label.text = "Raiders have reached the wall."
	# Current city state and previous results never compete for the same space.
	wall_summary_label.hide()
	defend_label.hide()
	build_button.hide()
	repair_button.hide()
	action_row.hide()
	report_scroll.hide()
	report_text = _format_report(_last_report)
	report_label.text = report_text
	_render_dashboard(phase, hp, max_hp, level, detected_threat)

func _create_dashboard() -> void:
	var contents: VBoxContainer = $Root/Center/DetailsPanel/Margin/Contents
	metrics = HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 10)
	contents.add_child(metrics)
	contents.move_child(metrics, 1)
	var wall_card := VBoxContainer.new()
	wall_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.add_child(wall_card)
	wall_value = _small_label(wall_card, "Wall")
	wall_meter = _meter(wall_card, Color(0.8, 0.57, 0.23))
	var satisfaction_card := VBoxContainer.new()
	satisfaction_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.add_child(satisfaction_card)
	satisfaction_value = _small_label(satisfaction_card, "Satisfaction")
	satisfaction_meter = _meter(satisfaction_card, Color(0.48, 0.66, 0.38))
	storage_summary = _small_label(contents, "City Storage")
	contents.move_child(storage_summary, 2)
	result_box = VBoxContainer.new()
	result_box.add_theme_constant_override("separation", 5)
	contents.add_child(result_box)
	contents.move_child(result_box, contents.get_child_count() - 2)
	result_heading = _small_label(result_box, "")
	result_stats = _small_label(result_box, "")
	var loot_scroll := ScrollContainer.new()
	loot_scroll.custom_minimum_size = Vector2(0, 34)
	loot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	result_box.add_child(loot_scroll)
	loot_slots = HFlowContainer.new()
	loot_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loot_slots.add_theme_constant_override("h_separation", 6)
	loot_scroll.add_child(loot_slots)
	result_note = _small_label(result_box, "")
	result_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var footer: HBoxContainer = contents.get_node("FooterRow")
	footer.add_theme_constant_override("separation", 6)
	report_toggle = Button.new()
	report_toggle.theme_type_variation = &"HudShortcutButton"
	report_toggle.add_theme_font_size_override("font_size", 6)
	report_toggle.custom_minimum_size = Vector2(54, 14)
	footer.add_child(report_toggle)
	footer.move_child(report_toggle, 0)
	report_toggle.pressed.connect(func():
		show_last_raid = not show_last_raid
		_render_details())

func _small_label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HudLabelShortcut"
	label.add_theme_font_size_override("font_size", 6)
	label.text = text
	parent.add_child(label)
	return label

func _meter(parent: Node, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(110, 6)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.23, 0.17, 0.11)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar

func _render_dashboard(phase: String, hp: int, max_hp: int, level: int, detected: bool) -> void:
	var residents: Array[CitizenData] = CitizenManager.get_all_residents()
	var satisfaction: float = 0.0
	for citizen: CitizenData in residents:
		satisfaction += citizen.satisfaction
	if not residents.is_empty():
		satisfaction /= residents.size()
	satisfaction_value.text = "Satisfaction  %d%%" % roundi(satisfaction * 100.0) if not residents.is_empty() else "Satisfaction  --"
	satisfaction_value.tooltip_text = "Average of %d residents" % residents.size() if not residents.is_empty() else "No residents yet"
	satisfaction_meter.value = satisfaction * 100.0
	satisfaction_meter.modulate.a = 1.0 if not residents.is_empty() else 0.4
	storage_summary.text = "City Storage  %d lootable items" % int(_status_data.get("storage_item_count", 0))
	storage_summary.tooltip_text = "Whole items that fit a raider bag. Equipment, personal inventory and resource silos are separate."
	wall_value.text = "Wall  %d/%d  Lv.%d" % [hp, max_hp, level]
	wall_meter.max_value = maxi(max_hp, 1)
	wall_meter.value = hp
	wall_value.tooltip_text = "Defend: %s" % str(_status_data.get("defend", 0))
	if not str(_status_data.get("work_kind", "")).is_empty():
		wall_value.text = "Wall work  %dm" % int(_status_data.get("work_remaining", 0))
		wall_meter.max_value = maxi(int(_status_data.get("work_total", 1)), 1)
		wall_meter.value = wall_meter.max_value - int(_status_data.get("work_remaining", 0))
	status_detail_label.text = {"unbuilt": "Ruined wall · Talk to Iddin-Sin", "safe": "No raiders detected", "warning": "Raiders approaching", "attacking": "Wall under attack", "looting": "City Storage under attack", "recovery": "Raid over · Recovering"}.get(phase, "No raiders detected")
	if hp == 0 and phase == "recovery":
		status_detail_label.text = "Ruined wall · Talk to Iddin-Sin"
	var viewing_report: bool = show_last_raid and not _last_report.is_empty()
	status_detail_label.visible = not viewing_report
	travel_progress.visible = detected and not viewing_report
	travel_eta_label.visible = detected and not viewing_report
	result_box.visible = viewing_report
	storage_summary.visible = not viewing_report
	report_toggle.visible = not _last_report.is_empty()
	report_toggle.text = "Current city" if viewing_report else "Last raid"
	$Root/Center/DetailsPanel/Margin/Contents/TitleLabel.text = "LAST RAID" if viewing_report else "CITY MANAGEMENT"
	details_panel.custom_minimum_size = Vector2(300, 176 if viewing_report else (160 if detected else 126))
	details_panel.size = details_panel.custom_minimum_size
	if not viewing_report:
		return
	result_heading.text = "Day %d  ·  %s" % [int(_last_report.get("day", 0)), "Wall breached" if _last_report.get("outcome") == "breached" else "Raiders repelled"]
	result_stats.text = "Wall -%d HP    Satisfaction -%.1f pp\nBuildings: %d    Fled: %d" % [int(_last_report.get("wall_damage", 0)), float(_last_report.get("satisfaction_drop", 0.0)) * 100.0, _last_report.get("buildings_destroyed", {}).values().reduce(func(a, b): return a + int(b), 0), _last_report.get("citizens_fled", []).size()]
	if int(_last_report.get("residents_affected", -1)) == 0:
		result_stats.text = result_stats.text.replace("Satisfaction -0.0 pp", "No residents")
	var reason: String = str(_last_report.get("retreat_reason", ""))
	result_note.text = {"wall_held": "Wall held", "time_up": "Time ran out", "capacity_full": "Raider bags full", "no_carryable_loot": "No carryable goods in City Storage"}.get(reason, "Raid ended")
	var stolen: Dictionary = _last_report.get("stolen", {})
	var key: String = str(stolen)
	if key == _loot_display_key and loot_slots.get_child_count() > 0:
		return
	_loot_display_key = key
	for child: Node in loot_slots.get_children():
		child.free()
	if stolen.is_empty():
		_small_label(loot_slots, "No items stolen")
	for id: String in stolen:
		var slot := HBoxContainer.new()
		slot.custom_minimum_size = Vector2(40, 20)
		loot_slots.add_child(slot)
		var data: ItemData = ItemDatabase.get_item_data(id)
		slot.tooltip_text = data.display_name if data != null else id
		if data != null and data.icon != null:
			var icon := TextureRect.new()
			icon.texture = data.icon
			icon.custom_minimum_size = Vector2(16, 16)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			slot.add_child(icon)
		else:
			_small_label(slot, id)
		_small_label(slot, "x%d" % int(stolen[id]))

func _format_report(report: Dictionary) -> String:
	if report.is_empty():
		return "No raid report yet."

	var lines: PackedStringArray = []
	var outcome: String = str(report.get("outcome", ""))
	if outcome == "repelled":
		lines.append("Outcome: Raiders repelled")
	elif outcome == "breached":
		lines.append("Outcome: Castle breached")
	else:
		lines.append("Outcome: %s" % (outcome.capitalize() if not outcome.is_empty() else "Unknown"))
	lines.append("Day: %s    Hits: %s" % [str(report.get("day", "—")), str(report.get("hits", "—"))])
	lines.append("Wall damage: %s" % str(report.get("wall_damage", "—")))
	lines.append("Items stolen: %s" % _format_counts(report.get("stolen", {}), true))
	if report.has("breach_seconds") or report.has("looting_seconds"):
		var breach_seconds: float = float(report.get("breach_seconds", -1.0))
		var breach_text: String = "No breach" if breach_seconds < 0.0 else _format_seconds(breach_seconds)
		lines.append("Breach after: %s · Looting: %s" % [breach_text, _format_seconds(float(report.get("looting_seconds", 0.0)))])
	if report.has("loot_weight") or report.has("loot_capacity_weight"):
		lines.append("Loot weight: %.2f / %.2f" % [float(report.get("loot_weight", 0.0)), float(report.get("loot_capacity_weight", 0.0))])
	if report.has("loot_preference"):
		lines.append("Loot preference: %s" % str(report.get("loot_preference", "balanced")).capitalize())
	var retreat_reason: String = str(report.get("retreat_reason", ""))
	if not retreat_reason.is_empty():
		lines.append("Raiders withdrew: %s" % _retreat_reason_text(retreat_reason))
	lines.append("Buildings destroyed: %s" % _format_counts(report.get("buildings_destroyed", {}), false))
	var satisfaction_drop: float = clampf(float(report.get("satisfaction_drop", 0.0)), 0.0, 1.0)
	lines.append("Satisfaction drop: %.1f pp" % (satisfaction_drop * 100.0))
	lines.append("Citizens who fled: %s" % _format_names(report.get("citizens_fled", [])))
	return "\n".join(lines)

func _format_seconds(seconds: float) -> String:
	var whole_seconds: int = maxi(0, int(round(seconds)))
	var minutes: int = whole_seconds / 60
	var remainder: int = whole_seconds % 60
	if minutes > 0:
		return "%dm %02ds" % [minutes, remainder]
	return "%ds" % whole_seconds

func _retreat_reason_text(reason: String) -> String:
	match reason:
		"wall_held":
			return "the wall held"
		"time_up":
			return "time ran out"
		"capacity_full":
			return "their carrying capacity was full"
		"no_carryable_loot":
			return "no more suitable loot remained"
		"":
			return "unknown"
		_:
			return reason.replace("_", " ").capitalize()

func _format_counts(value: Variant, item_ids: bool) -> String:
	if not (value is Dictionary) or value.is_empty():
		return "None"
	var entries: PackedStringArray = []
	for raw_name: Variant in value:
		var count: int = int(value[raw_name])
		if count <= 0:
			continue
		var display_name: String = str(raw_name)
		if item_ids:
			var item_data: ItemData = ItemDatabase.get_item_data(display_name)
			if item_data != null:
				display_name = item_data.display_name
			else:
				display_name = display_name.replace("_", " ").capitalize()
		entries.append("%s × %d" % [display_name, count])
	return ", ".join(entries) if not entries.is_empty() else "None"

func _format_names(value: Variant) -> String:
	if not (value is Array) or value.is_empty():
		return "0"
	var names: PackedStringArray = []
	for raw_name: Variant in value:
		var display_name: String = str(raw_name).strip_edges()
		if not display_name.is_empty():
			names.append(display_name)
	if names.is_empty():
		return "0"
	return "%d — %s" % [names.size(), ", ".join(names)]

func _fallback_status(phase: String) -> String:
	match phase:
		"warning":
			return "Raid warning"
		"attacking":
			return "Raiders are attacking"
		"looting":
			return "Raiders are looting City Storage"
		"recovery":
			return "After the raid"
		"unbuilt":
			return "Castle wall is ruined"
		_:
			return "Safe"

func _apply_theme() -> void:
	for label in [status_label, wall_value_label, time_left_label, wall_summary_label, defend_label, status_detail_label, report_label]:
		label.theme = GAMEPLAY_THEME
	for button in [build_button, repair_button, $Root/RaidStatusPanel/Margin/Contents/FooterRow/DetailsButton, $Root/Center/DetailsPanel/Margin/Contents/FooterRow/CloseButton]:
		button.theme = GAMEPLAY_THEME
		button.theme_type_variation = &"HudShortcutButton"
