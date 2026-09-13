extends Control

signal confirmed(id: String, destination_path: NodePath, daily_target: int)
signal cancelled

var worker_id: String = ""
@onready var destination_button: OptionButton = $Center/Panel/Margin/Body/DestinationRow/DestinationButton
@onready var target_edit: LineEdit = $Center/Panel/Margin/Body/TargetRow/TargetEdit
@onready var feedback: Label = $Center/Panel/Margin/Body/Feedback
@onready var assign_button: Button = $Center/Panel/Margin/Body/Footer/AssignButton

func _ready() -> void:
	# Keep the shared theme untouched; native form controls need the same
	# pixel font and button skin as the scene-authored worksite controls.
	theme = theme.duplicate()
	theme.default_font = preload("res://assets/font/pixel_rpg.ttf")
	theme.default_font_size = 6
	for style: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		destination_button.add_theme_stylebox_override(style, theme.get_stylebox(style, "HudShortcutButton"))
	target_edit.add_theme_stylebox_override("normal", theme.get_stylebox("normal", "HudShortcutButton"))
	target_edit.add_theme_stylebox_override("focus", theme.get_stylebox("focus", "HudShortcutButton"))
	destination_button.get_popup().theme = theme
	hide()
	$Center/Panel/Margin/Body/Header/CloseButton.pressed.connect(func(): cancelled.emit())
	$Center/Panel/Margin/Body/Footer/CancelButton.pressed.connect(func(): cancelled.emit())
	$Center/Panel/Margin/Body/TargetRow/MinusButton.pressed.connect(_adjust_target.bind(-1))
	$Center/Panel/Margin/Body/TargetRow/PlusButton.pressed.connect(_adjust_target.bind(1))
	assign_button.pressed.connect(_confirm)
	destination_button.item_selected.connect(func(_index: int): _validate())
	target_edit.text_changed.connect(func(_text: String): _validate())
	target_edit.text_submitted.connect(func(_text: String): _confirm())

func open_for(id: String, worker_name: String, destinations: Array[Dictionary]) -> void:
	worker_id = id
	$Center/Panel/Margin/Body/WorkerLabel.text = worker_name
	destination_button.clear()
	var first_available: int = -1
	for entry: Dictionary in destinations:
		var index: int = destination_button.item_count
		destination_button.add_item(str(entry.name))
		destination_button.set_item_metadata(index, entry.path)
		destination_button.set_item_disabled(index, not bool(entry.available))
		if first_available < 0 and bool(entry.available):
			first_available = index
	destination_button.select(first_available)
	destination_button.disabled = first_available < 0
	if destinations.is_empty():
		destination_button.text = "No storage"
	elif first_available < 0:
		destination_button.text = "Unavailable"
	target_edit.text = "20"
	_validate()
	show()
	if destination_button.disabled:
		$Center/Panel/Margin/Body/Footer/CancelButton.grab_focus()
	else:
		destination_button.grab_focus()

func set_error(message: String) -> void:
	feedback.text = message

func _validate() -> void:
	var selected: int = destination_button.selected
	var has_destination: bool = selected >= 0 and not destination_button.is_item_disabled(selected)
	var valid_target: bool = target_edit.text.is_valid_int() and int(target_edit.text) > 0
	assign_button.disabled = not has_destination or not valid_target
	feedback.text = "Counts items received by storage."
	if not has_destination:
		feedback.text = "No available storage destination."
	elif not valid_target:
		feedback.text = "Enter at least 1 item per day."

func _adjust_target(amount: int) -> void:
	target_edit.text = str(maxi(1, int(target_edit.text) + amount))
	_validate()

func _confirm() -> void:
	_validate()
	if not assign_button.disabled:
		confirmed.emit(worker_id, destination_button.get_selected_metadata(), int(target_edit.text))
