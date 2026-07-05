class_name OptionPanel extends PanelContainer

signal use_requested()
signal send_requested()
signal drop_requested()

@onready var use_button: Button = $OptionBackgroundTexture/OptionContainer/UseButtonTexture/UseButton
@onready var send_button: Button = $OptionBackgroundTexture/OptionContainer/SendButtonTexture/SendButton
@onready var drop_button: Button = $OptionBackgroundTexture/OptionContainer/DropButtonTexture/DropButton

# Setup / Public API

func _ready() -> void:
	use_button.pressed.connect(_on_use_button_pressed)
	send_button.pressed.connect(_on_send_button_pressed)
	drop_button.pressed.connect(_on_drop_button_pressed)

# Button callbacks

func _on_use_button_pressed() -> void:
	use_requested.emit()

func _on_send_button_pressed() -> void:
	send_requested.emit()

func _on_drop_button_pressed() -> void:
	drop_requested.emit()

# Action state

func set_actions_enabled(can_use: bool, can_send: bool, can_drop: bool) -> void:
	use_button.disabled = not can_use
	send_button.disabled = not can_send
	drop_button.disabled = not can_drop
