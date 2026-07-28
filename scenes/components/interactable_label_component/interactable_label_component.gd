class_name InteractableLabelComponent extends Control

const INTERACT_TEXT: String = "E"

@export var position_offset: Vector2 = Vector2(-5, -30)
@onready var label: Label = $NinePatchRect/Label

# Lifecycle

func _ready() -> void:
	position = position_offset
	label.text = INTERACT_TEXT


# Public API

func set_text(_new_text: String) -> void:
	label.text = INTERACT_TEXT
