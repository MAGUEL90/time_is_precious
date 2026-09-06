class_name ActionChoicePanel extends NinePatchRect

signal primary_selected()
signal secondary_selected()
signal cancelled()

@onready var message_label: Label = $ContentMargin/ContentVBox/MessageLabel
@onready var primary_button: Button = $ContentMargin/ContentVBox/ActionButtons/PrimaryButton
@onready var secondary_button: Button = $ContentMargin/ContentVBox/ActionButtons/SecondaryButton
@onready var close_button: TextureButton = $CloseButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	primary_button.pressed.connect(_on_primary_pressed)
	secondary_button.pressed.connect(_on_secondary_pressed)
	close_button.pressed.connect(_on_close_pressed)

func setup(
	message: String,
	primary_text: String,
	secondary_text: String,
	show_close: bool = false
) -> void:
	message_label.text = message
	primary_button.text = primary_text
	secondary_button.text = secondary_text
	close_button.visible = show_close

func _on_primary_pressed() -> void:
	primary_selected.emit()

func _on_secondary_pressed() -> void:
	secondary_selected.emit()

func _on_close_pressed() -> void:
	cancelled.emit()
