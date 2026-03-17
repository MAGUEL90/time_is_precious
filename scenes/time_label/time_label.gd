extends Control

@onready var day_label: Label = $VBoxContainer/HBoxContainer/DayLabel
@onready var time_label: Label = $VBoxContainer/HBoxContainer/TimeLabel
@onready var weather_label: Label = $VBoxContainer/WeatherLabel


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	TimeComponentManager.time_changed.connect(_on_time_changed)
	_on_time_changed(TimeComponentManager.current_day, TimeComponentManager.current_hour, 
			int(TimeComponentManager.current_minute), TimeComponentManager.current_weather)

func _on_time_changed(day:int, hour:int, minute:int, weather: String) -> void:
	pass

	
	
	
	
	
	
	
	
	
	
	
	
