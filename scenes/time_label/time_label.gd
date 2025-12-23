extends Control

@onready var label: Label = $VBoxContainer/Label

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	TimeComponentManager.time_changed.connect(_on_time_changed)
	_on_time_changed(TimeComponentManager.current_day, TimeComponentManager.current_hour, int(TimeComponentManager.current_minute))

func _on_time_changed(day:int, hour:int, minute:int) -> void:
	label.text = "Day: %02d  Hour: %02d  Minute: %02d" % [day, hour, minute]

	
	
	
	
	
	
	
	
	
	
	
	
