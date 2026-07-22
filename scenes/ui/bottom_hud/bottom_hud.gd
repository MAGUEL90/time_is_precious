extends CanvasLayer

const SHOW_STATUS_ACTION: StringName = &"show_player_status"

const DRAWER_OPEN_Y: float = 120.0
const DRAWER_CLOSED_Y: float = 144.0
const OPEN_DURATION: float = 0.14
const CLOSE_DURATION: float = 0.10

const CONDITION_NORMAL_COLOR: Color = Color.WHITE
const CONDITION_WARNING_COLOR: Color = Color(1.0, 0.65, 0.35, 1.0)
const CONDITION_CRITICAL_COLOR: Color = Color.DARK_RED

@export_group("Condition Alert Thresholds")
@export_range(0.0, 100.0, 1.0) var warning_remaining_percent: float = 40.0
@export_range(0.0, 100.0, 1.0) var critical_remaining_percent: float = 20.0

@onready var status_drawer: Control = $Root/StatusDrawer
@onready var fatigue_indicator: HBoxContainer = $Root/StatusDrawer/IndicatorRow/FatigueIndicator
@onready var focus_indicator: HBoxContainer = $Root/StatusDrawer/IndicatorRow/FocusIndicator
@onready var hunger_indicator: HBoxContainer = $Root/StatusDrawer/IndicatorRow/HungerIndicator
@onready var fatigue_bar: TextureProgressBar = $Root/StatusDrawer/IndicatorRow/FatigueIndicator/Bar
@onready var focus_bar: TextureProgressBar = $Root/StatusDrawer/IndicatorRow/FocusIndicator/Bar
@onready var hunger_bar: TextureProgressBar = $Root/StatusDrawer/IndicatorRow/HungerIndicator/Bar
@onready var experience_bar: TextureProgressBar = $Root/StatusDrawer/IndicatorRow/ExperienceIndicator/Bar

var player_ref: Player = null
var drawer_tween: Tween

# Lifecycle

func _ready() -> void:
	_set_drawer_y(DRAWER_CLOSED_Y)

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

	fatigue_indicator.modulate = _get_condition_color(fatigue_remaining)
	focus_indicator.modulate = _get_condition_color(focus_remaining)
	hunger_indicator.modulate = _get_condition_color(hunger_remaining)

func _on_experience_changed() -> void:
	experience_bar.max_value = player_ref.experience_required
	experience_bar.value = player_ref.current_experience

func _get_condition_color(remaining_percent: float) -> Color:
	if remaining_percent <= critical_remaining_percent:
		return CONDITION_CRITICAL_COLOR

	if remaining_percent <= warning_remaining_percent:
		return CONDITION_WARNING_COLOR

	return CONDITION_NORMAL_COLOR

# Drawer animation

func _animate_drawer(target_y: float, duration: float) -> void:
	if drawer_tween != null:
		drawer_tween.kill()

	drawer_tween = create_tween()
	drawer_tween.set_trans(Tween.TRANS_QUAD)
	drawer_tween.set_ease(Tween.EASE_OUT)
	drawer_tween.tween_method(
		_set_drawer_y,
		status_drawer.position.y,
		target_y,
		duration
	)

func _set_drawer_y(value: float) -> void:
	var snapped_position := status_drawer.position
	snapped_position.y = roundf(value)
	status_drawer.position = snapped_position
