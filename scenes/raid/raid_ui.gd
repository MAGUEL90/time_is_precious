class_name RaidUI extends CanvasLayer

signal build_requested
signal repair_requested

const GAMEPLAY_THEME: Theme = preload("res://resources/ui_gameplay_theme/ui_gameplay_theme.tres")

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

const WARNING_PULSE_SECONDS: float = 1.6
var _warning_elapsed: float = 0.0

var raid_state: Node
var report_text: String = ""
var _status_data: Dictionary = {}
var _last_report: Dictionary = {}
var _last_shown_report_id: int = -1
var _last_phase: String = ""

func _ready() -> void:
	visible = true
	status_panel.visible = false
	details_panel.visible = false
	build_button.pressed.connect(_on_build_pressed)
	repair_button.pressed.connect(_on_repair_pressed)
	$Root/RaidStatusPanel/Margin/Contents/FooterRow/DetailsButton.pressed.connect(open_details)
	$Root/Center/DetailsPanel/Margin/Contents/FooterRow/CloseButton.pressed.connect(close_details)
	_apply_theme()
	refresh()

func _process(delta: float) -> void:
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return
	_warning_elapsed = fmod(_warning_elapsed + delta, WARNING_PULSE_SECONDS)
	# A soft pulse at the edges leaves the center and controls readable.
	attack_warning.modulate.a = 0.35 + 0.65 * (0.5 - 0.5 * cos(TAU * _warning_elapsed / WARNING_PULSE_SECONDS))

func _set_attack_warning(active: bool) -> void:
	if attack_warning.visible != active:
		_warning_elapsed = 0.0
		attack_warning.modulate.a = 0.35
	attack_warning.visible = active
	set_process(active)

func _exit_tree() -> void:
	_unbind_state()

func _unhandled_input(event: InputEvent) -> void:
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
	if not is_instance_valid(raid_state):
		return
	_render_details()
	details_panel.visible = true

func close_details() -> void:
	details_panel.visible = false

func refresh() -> void:
	if not is_instance_valid(raid_state):
		_set_attack_warning(false)
		status_panel.visible = false
		details_panel.visible = false
		_status_data.clear()
		_last_report.clear()
		report_text = "No raid report yet."
		return

	_status_data.clear()
	if raid_state.has_method("get_status"):
		var status_value: Variant = raid_state.call("get_status")
		if status_value is Dictionary:
			_status_data = status_value.duplicate(true)
	var phase: String = str(_status_data.get("phase", ""))
	_set_attack_warning(phase == "attacking")
	if phase == "attacking" and _last_phase != phase:
		close_details()
	_last_phase = phase
	status_panel.visible = true
	_render_status()

	_last_report.clear()
	if raid_state.has_method("get_last_report"):
		var report_value: Variant = raid_state.call("get_last_report")
		if report_value is Dictionary:
			_last_report = report_value.duplicate(true)
	_render_details()

	if phase != "attacking" and _last_report.has("id"):
		var report_id: int = int(_last_report.get("id", -1))
		if report_id != _last_shown_report_id:
			_last_shown_report_id = report_id
			open_details()

func _unbind_state() -> void:
	if not is_instance_valid(raid_state):
		return
	if raid_state.has_signal("changed"):
		var changed_callable: Callable = Callable(self, "_on_state_changed")
		if raid_state.is_connected("changed", changed_callable):
			raid_state.disconnect("changed", changed_callable)
	raid_state = null

func _on_state_changed() -> void:
	refresh()

func _on_build_pressed() -> void:
	if bool(_status_data.get("can_build", false)):
		build_requested.emit()

func _on_repair_pressed() -> void:
	if bool(_status_data.get("can_repair", false)):
		repair_requested.emit()

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
	if bool(_status_data.get("raids_enabled", true)) and phase == "attacking":
		var seconds_left: float = maxf(0.0, float(_status_data.get("seconds_left", 0.0)))
		time_left_label.text = "Raid: %ds" % int(ceil(seconds_left))
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
	status_detail_label.text = status_text

	var can_build: bool = bool(_status_data.get("can_build", false))
	var can_repair: bool = bool(_status_data.get("can_repair", false))
	build_button.visible = can_build
	repair_button.visible = can_repair
	build_button.text = "Rebuild wall (free)" if level > 0 else "Build wall (free)"
	repair_button.text = "Repair wall (free)"
	action_row.visible = can_build or can_repair
	var has_report: bool = not _last_report.is_empty()
	report_scroll.visible = has_report
	details_panel.custom_minimum_size = Vector2(376, 209) if has_report else Vector2(280, 120)
	report_text = _format_report(_last_report)
	report_label.text = report_text

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
	lines.append("Buildings destroyed: %s" % _format_counts(report.get("buildings_destroyed", {}), false))
	var satisfaction_drop: float = clampf(float(report.get("satisfaction_drop", 0.0)), 0.0, 1.0)
	lines.append("Satisfaction drop: %.1f pp" % (satisfaction_drop * 100.0))
	lines.append("Citizens who fled: %s" % _format_names(report.get("citizens_fled", [])))
	return "\n".join(lines)

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
