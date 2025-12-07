extends Control

@onready var label: Label = $VBoxContainer/Label

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	label.text = "Day: %02d: Hour: %02d: Minute: %02d" % [TimeComponentManager.current_day, TimeComponentManager.current_hour, TimeComponentManager.current_minute]
