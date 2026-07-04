class_name ItemActionConfirmPanel extends Control

signal confirmed(action: String, item_id: String, quantity: int)
signal canceled()

@onready var confirm_actions: ConfirmActionPanel = $MarginContainer/ConfirmActions
@onready var item_icon: TextureRect = $MarginContainer/VBoxContainer/ItemPreviewRow/ItemIcon
@onready var action_label: Label = $MarginContainer/VBoxContainer/ItemPreviewRow/InfoVBox/ActionLabel
@onready var quantity_label: Label = $MarginContainer/VBoxContainer/ItemPreviewRow/InfoVBox/QuantityLabel
@onready var minus_button: Button = $MarginContainer/VBoxContainer/QuantityStepper/MinusButton
@onready var quantity_value_label: Label = $MarginContainer/VBoxContainer/QuantityStepper/QuantityValueLabel
@onready var plus_button: Button = $MarginContainer/VBoxContainer/QuantityStepper/PlusButton
@onready var step_1_button: Button = $MarginContainer/VBoxContainer/StepSelector/Step1Button
@onready var step_10_button: Button = $MarginContainer/VBoxContainer/StepSelector/Step10Button
@onready var step_25_button: Button = $MarginContainer/VBoxContainer/StepSelector/Step25Button
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/ConfirmButton

var current_action: String = ""
var current_item_id: String = ""
var current_quantity: int = 1
var max_quantity: int = 1
var quantity_step: int = 1

# Setup / Public API

func _ready() -> void:
	confirm_actions.confirmed.connect(_on_confirmed)
	confirm_actions.canceled.connect(_on_confirm_action_canceled)
	minus_button.pressed.connect(func(): _change_quantity(-quantity_step))
	plus_button.pressed.connect(func(): _change_quantity(quantity_step))
	step_1_button.pressed.connect(func(): _set_quantity_step(1))
	step_10_button.pressed.connect(func(): _set_quantity_step(10))
	step_25_button.pressed.connect(func(): _set_quantity_step(25))
	confirm_button.pressed.connect(_on_confirm_button_pressed)

	step_1_button.toggle_mode = true
	step_10_button.toggle_mode = true
	step_25_button.toggle_mode = true

func setup(action: String, item_id: String, item_data: ItemData, max_quantity_value: int) -> void:
	current_action = action
	current_item_id = item_id
	max_quantity = max(max_quantity_value, 1)
	current_quantity = 1
	quantity_step = 1
	_refresh_step_buttons()

	action_label.text = action.capitalize()
	item_icon.texture = item_data.icon if item_data.icon != null else null
	_refresh_display()

# Confirmation callbacks

func _on_confirmed() -> void:
	confirmed.emit(current_action, current_item_id, current_quantity)

# Quantity controls

func _change_quantity(amount: int) -> void:
	current_quantity = clampi(current_quantity + amount, 1, max_quantity)
	_refresh_display()

func _set_quantity_step(step: int) -> void:
	quantity_step = step
	_refresh_step_buttons()

func _refresh_display() -> void:
	quantity_value_label.text = str(current_quantity)
	quantity_label.text = "(Max %d)" % max_quantity

# Confirm panel callbacks

func _on_confirm_button_pressed() -> void:
	confirm_button.visible = false
	confirm_actions.visible = true

func _on_confirm_action_canceled() -> void:
	confirm_actions.visible = false
	confirm_button.visible = true

func _refresh_step_buttons() -> void:
	step_1_button.button_pressed = quantity_step == 1
	step_10_button.button_pressed = quantity_step == 10
	step_25_button.button_pressed = quantity_step == 25
