extends CanvasLayer

# Clock references

@onready var day_label: Label = $Root/Bar/TemplateText1/DayLabel
@onready var time_label: Label = $Root/Bar/TemplateText2/TimeLabel
@onready var weather_label: Label = $Root/Bar/TemplateText3/WeatherLabel
@onready var pop_label: Label = $Root/Bar/TemplateText4/PopLabel
@onready var food_label: Label = $Root/Bar/TemplateText5/FoodLabel

# Player condition references

@onready var fatigue_row: HBoxContainer = $Root/PlayerStatusPanel/StatusContainer/VBoxContainer/FatigueRow
@onready var focus_row: HBoxContainer = $Root/PlayerStatusPanel/StatusContainer/VBoxContainer/FocusRow
@onready var hunger_row: HBoxContainer = $Root/PlayerStatusPanel/StatusContainer/VBoxContainer/HungerRow
@onready var fatigue_icon: TextureRect = $Root/PlayerStatusPanel/StatusContainer/VBoxContainer/FatigueRow/FatigueIcon
@onready var fatigue_progress_bar: TextureProgressBar = $Root/PlayerStatusPanel/StatusContainer/VBoxContainer/FatigueRow/FatigueProgressBar
@onready var focus_icon: TextureRect = $Root/PlayerStatusPanel/StatusContainer/VBoxContainer/FocusRow/FocusIcon
@onready var focus_progress_bar: TextureProgressBar = $Root/PlayerStatusPanel/StatusContainer/VBoxContainer/FocusRow/FocusProgressBar
@onready var hunger_icon: TextureRect = $Root/PlayerStatusPanel/StatusContainer/VBoxContainer/HungerRow/HungerIcon
@onready var hunger_progress_bar: TextureProgressBar = $Root/PlayerStatusPanel/StatusContainer/VBoxContainer/HungerRow/HungerProgressBar
@onready var experience_icon: TextureRect = $Root/PlayerStatusPanel/StatusContainer/VBoxContainer/ExperienceRow/ExperienceIcon
@onready var experience_progress_bar: TextureProgressBar = $Root/PlayerStatusPanel/StatusContainer/VBoxContainer/ExperienceRow/ExperienceProgressBar

const CONDITION_NORMAL_COLOR: Color = Color.WHITE
const CONDITION_WARNING_COLOR: Color = Color("f2cf5b")
const CONDITION_CRITICAL_COLOR: Color = Color("e85d5d")

var player_ref: Player = null
var nightmare_world_ref: NightmareWorld = null

# Setup and signal bindings

func _ready() -> void:
	nightmare_world_ref = (
		get_tree().get_first_node_in_group("nightmare_world")
		as NightmareWorld
	)

	if nightmare_world_ref != null:
		nightmare_world_ref.nightmare_active_changed.connect(
			_on_nightmare_active_changed
		)

		visible = not nightmare_world_ref.is_active
	else:
		visible = true

	player_ref = get_tree().get_first_node_in_group("player")

	if player_ref == null:
		push_warning("TopHUD could not find player.")
		return

	TimeComponentManager.time_changed.connect(_on_time_changed)
	_on_time_changed(
		TimeComponentManager.current_day,
		TimeComponentManager.current_hour,
		TimeComponentManager.current_minute,
		TimeComponentManager.current_weather
	)

	player_ref.condition_changed.connect(_on_condition_changed)
	player_ref.experience_changed.connect(_on_experience_changed)

	_on_condition_changed()
	_on_experience_changed()

# Clock presentation

func _on_time_changed(day: int, hour: int, minute: int, weather: String) -> void:
	day_label.text = "day: %d" % day
	time_label.text = "%02d:%02d" % [hour, minute]
	weather_label.text = weather.capitalize()

# Player condition presentation

func _on_condition_changed() -> void:
	var fatigue_percent: int = player_ref.get_fatigue_percent()
	var focus_percent: int = player_ref.get_focus_percent()
	var hunger_percent: int = player_ref.get_hunger_percent()

	fatigue_progress_bar.value = 100 - fatigue_percent
	focus_progress_bar.value = focus_percent
	hunger_progress_bar.value = 100 - hunger_percent
	_update_condition_colors()

func _on_experience_changed() -> void:
	experience_progress_bar.max_value = player_ref.experience_required
	experience_progress_bar.value = player_ref.current_experience

func _update_condition_colors() -> void:
	fatigue_row.modulate = _get_severity_color(
		player_ref.get_fatigue_severity()
	)
	focus_row.modulate = _get_severity_color(
		player_ref.get_focus_severity()
	)
	hunger_row.modulate = _get_severity_color(
		player_ref.get_hunger_severity()
	)

func _get_severity_color(severity: int) -> Color:
	match severity:
		Player.ConditionSeverity.WARNING:
			return CONDITION_WARNING_COLOR
		Player.ConditionSeverity.CRITICAL:
			return CONDITION_CRITICAL_COLOR
		_:
			return CONDITION_NORMAL_COLOR

# Nightmare visibility

func _on_nightmare_active_changed(active: bool) -> void:
	if active:
		hide()
	else:
		show()
