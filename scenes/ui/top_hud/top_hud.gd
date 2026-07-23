extends CanvasLayer

const OPEN_DURATION: float = 0.36
const CLOSE_DURATION: float = 0.30

@onready var root: Control = $Root
@onready var bar: TextureRect = $Root/Bar
@onready var toggle_button: TextureButton = $Root/ToggleButton
@onready var toggle_icon: TextureRect = $Root/ToggleButton/ToggleIcon

@onready var day_label: Label = $Root/Bar/IndicatorRow/DayIndicator/ValuePanel/ValueLabel
@onready var time_label: Label = $Root/Bar/IndicatorRow/TimeIndicator/ValuePanel/ValueLabel
@onready var weather_label: Label = $Root/Bar/IndicatorRow/WeatherIndicator/ValuePanel/ValueLabel
@onready var population_label: Label = $Root/Bar/IndicatorRow/PopulationIndicator/ValuePanel/ValueLabel

var nightmare_world_ref: NightmareWorld = null
var bar_tween: Tween

var is_expanded: bool = false
var expanded_bar_x: float = 0.0
var collapsed_bar_x: float = 0.0

# Lifecycle

func _ready() -> void:
	_setup_bar()
	_setup_nightmare_visibility()

	toggle_button.pressed.connect(_on_toggle_button_pressed)

	TimeComponentManager.time_changed.connect(_on_time_changed)
	_on_time_changed(
		TimeComponentManager.current_day,
		TimeComponentManager.current_hour,
		TimeComponentManager.current_minute,
		TimeComponentManager.current_weather
	)

	CitizenManager.citizen_added.connect(_on_citizen_added)
	_update_population()

# Bar setup and animation

func _setup_bar() -> void:
	expanded_bar_x = bar.position.x
	collapsed_bar_x = root.size.x

	is_expanded = false
	_set_bar_x(collapsed_bar_x)
	_update_toggle_icon()

func _on_toggle_button_pressed() -> void:
	toggle_button.release_focus()
	is_expanded = not is_expanded

	var target_x: float = (
		expanded_bar_x
		if is_expanded
		else collapsed_bar_x
	)
	var duration: float = (
		OPEN_DURATION
		if is_expanded
		else CLOSE_DURATION
	)

	_animate_bar(target_x, duration)
	_update_toggle_icon()

func _animate_bar(target_x: float, duration: float) -> void:
	if bar_tween != null:
		bar_tween.kill()

	bar_tween = create_tween()
	bar_tween.set_trans(Tween.TRANS_SINE)
	bar_tween.set_ease(Tween.EASE_IN_OUT)
	bar_tween.tween_method(
		_set_bar_x,
		bar.position.x,
		target_x,
		duration
	)

func _set_bar_x(value: float) -> void:
	var snapped_position: Vector2 = bar.position
	snapped_position.x = roundf(value)
	bar.position = snapped_position

func _update_toggle_icon() -> void:
	toggle_icon.flip_h = is_expanded

# Indicator presentation

func _on_time_changed(day: int, hour: int, minute: int, weather: String) -> void:
	day_label.text = str(day)
	time_label.text = "%02d:%02d" % [hour, minute]
	weather_label.text = weather.capitalize()

func _on_citizen_added(_citizen_data: CitizenData) -> void:
	_update_population()

func _update_population() -> void:
	population_label.text = str(
		CitizenManager.get_all_citizens().size()
	)

# Nightmare visibility

func _setup_nightmare_visibility() -> void:
	nightmare_world_ref = (
		get_tree().get_first_node_in_group("nightmare_world") as NightmareWorld
	)

	if nightmare_world_ref == null:
		show()
		return

	nightmare_world_ref.nightmare_active_changed.connect(
		_on_nightmare_active_changed
	)

	visible = not nightmare_world_ref.is_active

func _on_nightmare_active_changed(active: bool) -> void:
	visible = not active
