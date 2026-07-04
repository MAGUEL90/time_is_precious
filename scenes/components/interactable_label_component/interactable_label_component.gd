class_name InteractableLabelComponent extends Control

@export var position_offset: Vector2 = Vector2(-35, -30)
@onready var label: Label = $TextureRect/Label

# Setup / Public API

func _ready() -> void:
	position = position_offset

func set_text(new_text: String) -> void:
	label.text = new_text
