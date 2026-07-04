class_name ConfirmActionPanel extends Control

signal confirmed()
signal canceled()

@onready var confirm_button: Button = $VBoxContainer/HBoxContainer/ConfirmButton
@onready var cancel_button: Button = $VBoxContainer/HBoxContainer/CancelButton

# Setup / Public API

func _ready() -> void:
	confirm_button.pressed.connect(func(): confirmed.emit())
	cancel_button.pressed.connect(func(): canceled.emit())
