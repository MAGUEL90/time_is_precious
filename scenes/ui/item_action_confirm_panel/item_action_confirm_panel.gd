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
@onready var initial_actions: HBoxContainer = $MarginContainer/VBoxContainer/InitialActions
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/InitialActions/ConfirmButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/InitialActions/CancelButton
@onready var quantity_stepper: HBoxContainer = $MarginContainer/VBoxContainer/QuantityStepper
@onready var step_selector: HBoxContainer = $MarginContainer/VBoxContainer/StepSelector

var current_action: String = ""
var current_item_id: String = ""
var current_quantity: int = 1
var max_quantity: int = 1
var quantity_step: int = 1
var quantity_steps: Array[int] = [1, 10, 25]
var requires_final_confirmation: bool = true

# Lifecycle

func _ready() -> void:
	confirm_actions.confirmed.connect(_on_confirmed)
	confirm_actions.canceled.connect(_on_confirm_action_canceled)
	minus_button.pressed.connect(func(): _change_quantity(-quantity_step))
	plus_button.pressed.connect(func(): _change_quantity(quantity_step))
	step_1_button.pressed.connect(_set_quantity_step_by_index.bind(0))
	step_10_button.pressed.connect(_set_quantity_step_by_index.bind(1))
	step_25_button.pressed.connect(_set_quantity_step_by_index.bind(2))
	confirm_button.pressed.connect(_on_confirm_button_pressed)
	cancel_button.pressed.connect(_on_cancel_button_pressed)
	item_icon.gui_input.connect(_on_item_icon_gui_input)

	step_1_button.toggle_mode = true
	step_10_button.toggle_mode = true
	step_25_button.toggle_mode = true

# Public API

func setup(
	action: String,
	item_id: String,
	item_data: ItemData,
	max_quantity_value: int,
	step_values: Array = [],
	require_final_confirmation: bool = true
) -> void:
	current_action = action
	current_item_id = item_id
	max_quantity = max(max_quantity_value, 1)
	current_quantity = 1
	quantity_steps = _get_safe_quantity_steps(step_values)
	quantity_step = quantity_steps[0]
	requires_final_confirmation = require_final_confirmation
	quantity_stepper.visible = true
	step_selector.visible = true
	initial_actions.visible = true
	confirm_actions.visible = false
	_refresh_step_buttons()

	action_label.text = action.capitalize()
	item_icon.texture = item_data.icon if item_data.icon != null else null
	_refresh_display()

# Quantity controls

func _change_quantity(amount: int) -> void:
	current_quantity = clampi(current_quantity + amount, 1, max_quantity)
	_refresh_display()

func _on_item_icon_gui_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = (
		event as InputEventMouseButton
	)
	if mouse_event == null or not mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_change_quantity(quantity_step)
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		_change_quantity(-quantity_step)
	else:
		return

	item_icon.accept_event()

func _set_quantity_step(step: int) -> void:
	quantity_step = step
	_refresh_step_buttons()

func _set_quantity_step_by_index(step_index: int) -> void:
	if step_index < 0 or step_index >= quantity_steps.size():
		return
	_set_quantity_step(quantity_steps[step_index])

func _get_safe_quantity_steps(step_values: Array) -> Array[int]:
	if step_values.size() != 3:
		return [1, 10, 25]

	var safe_steps: Array[int] = []
	for step_value in step_values:
		safe_steps.append(maxi(step_value, 1))
	return safe_steps

func _refresh_display() -> void:
	quantity_value_label.text = str(current_quantity)
	quantity_label.text = "(Max %d)" % max_quantity

func _refresh_step_buttons() -> void:
	var step_buttons: Array[Button] = [
		step_1_button,
		step_10_button,
		step_25_button
	]
	for step_index in range(step_buttons.size()):
		var step_button: Button = step_buttons[step_index]
		var step_value: int = quantity_steps[step_index]
		step_button.text = "x%d" % step_value
		step_button.button_pressed = quantity_step == step_value

# Confirmation flow

func _on_confirm_button_pressed() -> void:
	if not requires_final_confirmation:
		confirmed.emit(current_action, current_item_id, current_quantity)
		return

	quantity_stepper.visible = false
	step_selector.visible = false
	initial_actions.visible = false
	confirm_actions.visible = true

func _on_cancel_button_pressed() -> void:
	canceled.emit()

func _on_confirmed() -> void:
	confirmed.emit(current_action, current_item_id, current_quantity)

func _on_confirm_action_canceled() -> void:
	quantity_stepper.visible = true
	step_selector.visible = true
	confirm_actions.visible = false
	initial_actions.visible = true
