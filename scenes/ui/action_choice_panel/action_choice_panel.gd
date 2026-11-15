class_name ActionChoicePanel extends NinePatchRect

signal primary_selected()
signal secondary_selected()
signal cancelled()

@onready var message_label: Label = $ContentMargin/ContentVBox/MessageLabel
@onready var action_buttons: HBoxContainer = $ContentMargin/ContentVBox/ActionButtons
@onready var back_spacer: Control = $ContentMargin/ContentVBox/ActionButtons/BackSpacer
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
	var primary_is_back: bool = primary_text.strip_edges().to_lower() == "back"
	var secondary_is_back: bool = secondary_text.strip_edges().to_lower() == "back"
	var has_back: bool = primary_is_back or secondary_is_back
	close_button.visible = show_close and not has_back
	back_spacer.visible = has_back
	action_buttons.size_flags_vertical = Control.SIZE_EXPAND_FILL if has_back else Control.SIZE_FILL
	primary_button.size_flags_vertical = Control.SIZE_SHRINK_END if has_back else Control.SIZE_FILL
	secondary_button.size_flags_vertical = Control.SIZE_SHRINK_END if has_back else Control.SIZE_FILL
	if has_back:
		var back_button: Button = primary_button if primary_is_back else secondary_button
		action_buttons.alignment = BoxContainer.ALIGNMENT_BEGIN
		action_buttons.move_child(back_button, 0)
		action_buttons.move_child(back_spacer, 1)
	else:
		action_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
		action_buttons.move_child(primary_button, 0)

func _on_primary_pressed() -> void:
	primary_selected.emit()

func _on_secondary_pressed() -> void:
	secondary_selected.emit()

func _on_close_pressed() -> void:
	cancelled.emit()
