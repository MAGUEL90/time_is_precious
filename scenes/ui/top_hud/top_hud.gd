extends CanvasLayer

@onready var day_label: Label = $Root/Bar/TemplateText1/DayLabel
@onready var time_label: Label = $Root/Bar/TemplateText2/TimeLabel
@onready var weather_label: Label = $Root/Bar/TemplateText3/WeatherLabel
@onready var pop_label: Label = $Root/Bar/TemplateText4/PopLabel
@onready var food_label: Label = $Root/Bar/TemplateText5/FoodLabel

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	TimeComponentManager.time_changed.connect(_on_time_changed)
	_on_time_changed(
		TimeComponentManager.current_day,
		TimeComponentManager.current_hour,
		TimeComponentManager.current_minute,
		TimeComponentManager.current_weather
	)

func _on_time_changed(day: int, hour: int, minute: int, weather: String) -> void:
	day_label.text = "day: %d" % day
	time_label.text = "%02d:%02d" % [hour, minute]
	weather_label.text = weather.capitalize()
