class_name GameplayHUD extends CanvasLayer

@onready var label_day: Label = $Root/MarginContainer/TopLayer/TopLeftPanel/MarginContainer/VBoxContainer/LabelDay
@onready var label_time: Label = $Root/MarginContainer/TopLayer/TopLeftPanel/MarginContainer/VBoxContainer/LabelTime
@onready var label_weather: Label = $Root/MarginContainer/TopLayer/TopLeftPanel/MarginContainer/VBoxContainer/LabelWeather

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	TimeComponentManager.time_changed.connect(_on_time_changed)
	_on_time_changed(TimeComponentManager.current_day, TimeComponentManager.current_hour, 
			int(TimeComponentManager.current_minute), TimeComponentManager.current_weather)

func _on_time_changed(day:int, hour:int, minute:int, weather: String) -> void:
	label_day.text = "Day: %02d " % [day]
	label_time.text = "Hour: %02d Minute: %02d " % [hour, minute]
	label_weather.text = "Weather: %s" % [weather]
