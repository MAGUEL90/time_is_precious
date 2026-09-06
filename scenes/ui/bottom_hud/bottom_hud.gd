extends CanvasLayer

const SHOW_STATUS_ACTION: StringName = &"show_player_status"

const DRAWER_OPEN_Y: float = -60.0
const DRAWER_CLOSED_Y: float = 24.0
const OPEN_DURATION: float = 0.14
const CLOSE_DURATION: float = 0.10

const CONDITION_NORMAL_COLOR: Color = Color.WHITE
const CONDITION_WARNING_COLOR: Color = Color(1.0, 0.65, 0.35, 1.0)
const CONDITION_CRITICAL_COLOR: Color = Color(1.0, 0.55, 0.48, 1.0)
const GAMEPLAY_THEME: Theme = preload("res://resources/ui_gameplay_theme/ui_gameplay_theme.tres")

@onready var status_drawer: Control = $Root/StatusDrawer
@onready var fatigue_indicator: HBoxContainer = $Root/StatusDrawer/IndicatorRow/FatigueIndicator
@onready var focus_indicator: HBoxContainer = $Root/StatusDrawer/IndicatorRow/FocusIndicator
@onready var hunger_indicator: HBoxContainer = $Root/StatusDrawer/IndicatorRow/HungerIndicator
@onready var fatigue_bar: TextureProgressBar = $Root/StatusDrawer/IndicatorRow/FatigueIndicator/Bar
@onready var focus_bar: TextureProgressBar = $Root/StatusDrawer/IndicatorRow/FocusIndicator/Bar
@onready var hunger_bar: TextureProgressBar = $Root/StatusDrawer/IndicatorRow/HungerIndicator/Bar
@onready var experience_bar: TextureProgressBar = $Root/StatusDrawer/IndicatorRow/ExperienceIndicator/Bar

var player_ref: Player = null
var nightmare_world_ref: NightmareWorld = null
var drawer_tween: Tween

# Lifecycle

func _ready() -> void:
	_setup_status_text()
	_set_drawer_y(DRAWER_CLOSED_Y)
	status_drawer.hide()
	_setup_nightmare_visibility()

	player_ref = get_tree().get_first_node_in_group("player") as Player

	if player_ref == null:
		push_warning("BottomHUD could not find player.")
		return

	player_ref.condition_changed.connect(_on_condition_changed)
	player_ref.experience_changed.connect(_on_experience_changed)

	_on_condition_changed()
	_on_experience_changed()

# Input handling

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(SHOW_STATUS_ACTION):
		_animate_drawer(DRAWER_OPEN_Y, OPEN_DURATION)
		get_viewport().set_input_as_handled()
	elif event.is_action_released(SHOW_STATUS_ACTION):
		_animate_drawer(DRAWER_CLOSED_Y, CLOSE_DURATION)
		get_viewport().set_input_as_handled()

# Player status presentation

func _on_condition_changed() -> void:
	var fatigue_remaining: int = 100 - player_ref.get_fatigue_percent()
	var focus_remaining: int = player_ref.get_focus_percent()
	var hunger_remaining: int = 100 - player_ref.get_hunger_percent()

	fatigue_bar.value = fatigue_remaining
	focus_bar.value = focus_remaining
	hunger_bar.value = hunger_remaining

	fatigue_indicator.modulate = _get_condition_color(player_ref.get_fatigue_severity())
	focus_indicator.modulate = _get_condition_color(player_ref.get_focus_severity())
	hunger_indicator.modulate = _get_condition_color(player_ref.get_hunger_severity())

func _on_experience_changed() -> void:
	experience_bar.max_value = player_ref.experience_required
	experience_bar.value = player_ref.current_experience

func _get_condition_color(severity: int) -> Color:
	if severity == Player.ConditionSeverity.CRITICAL:
		return CONDITION_CRITICAL_COLOR

	if severity == Player.ConditionSeverity.WARNING:
		return CONDITION_WARNING_COLOR

	return CONDITION_NORMAL_COLOR

func _make_status_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.theme = GAMEPLAY_THEME
	label.theme_type_variation = &"HudLabelShortcut"
	label.add_theme_font_size_override("font_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _setup_status_text() -> void:
	var names := HBoxContainer.new()
	names.name = "StatusNames"
	names.position = Vector2(0, -10)
	names.add_theme_constant_override("separation", 2)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for title in ["Energy", "Focus", "Satiety", "EXP"]:
		var label: Label = _make_status_label(title)
		label.custom_minimum_size.x = 38
		names.add_child(label)
	status_drawer.add_child(names)

# Drawer animation

func _animate_drawer(target_y: float, duration: float) -> void:
	if drawer_tween != null:
		drawer_tween.kill()
	status_drawer.show()

	drawer_tween = create_tween()
	drawer_tween.set_trans(Tween.TRANS_QUAD)
	drawer_tween.set_ease(Tween.EASE_OUT)
	drawer_tween.tween_method(
		_set_drawer_y,
		status_drawer.offset_top,
		target_y,
		duration
	)
	if target_y == DRAWER_CLOSED_Y:
		drawer_tween.tween_callback(status_drawer.hide)

func _set_drawer_y(value: float) -> void:
	status_drawer.offset_top = roundf(value)
	status_drawer.offset_bottom = roundf(value) + 16.0

# Nightmare visibility

func _setup_nightmare_visibility() -> void:
	nightmare_world_ref = (
		get_tree().get_first_node_in_group("nightmare_world")
		as NightmareWorld
	)

	if nightmare_world_ref == null:
		show()
		set_process_unhandled_input(true)
		return

	nightmare_world_ref.nightmare_active_changed.connect(
		_on_nightmare_active_changed
	)

func _on_nightmare_active_changed(active: bool) -> void:
	visible = not active
	set_process_unhandled_input(not active)

	if active:
		if drawer_tween != null:
			drawer_tween.kill()

		_set_drawer_y(DRAWER_CLOSED_Y)
		status_drawer.hide()
