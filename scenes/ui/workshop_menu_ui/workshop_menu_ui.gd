class_name WorkshopMenuUI extends CanvasLayer

signal action_selected(action_id: int)
signal closed()

enum Action {
	MANAGE_STORAGE,
	ASSIGN_WORK,
	BUILD_AND_UPGRADE,
}

@onready var held_label: Label = (
	$Root/Center/Window/Margin/MainVBox/ReadyOutputRow/HeldLabel
)
@onready var pending_label: Label = (
	$Root/Center/Window/Margin/MainVBox/ReadyOutputRow/PendingLabel
)
@onready var held_fees_label: Label = (
	$Root/Center/Window/Margin/MainVBox/StatusRow/HeldFeesLabel
)
@onready var status_separator: TextureRect = (
	$Root/Center/Window/Margin/MainVBox/StatusRow/SeparatorIcon
)
@onready var processing_label: Label = (
	$Root/Center/Window/Margin/MainVBox/StatusRow/ProcessingLabel
)
@onready var manage_button: Button = $Root/Center/Window/Margin/MainVBox/ActionGrid/ManageButton
@onready var assign_button: Button = $Root/Center/Window/Margin/MainVBox/ActionGrid/AssignButton
@onready var build_button: Button = $Root/Center/Window/Margin/MainVBox/ActionGrid/BuildButton
@onready var close_button: BaseButton = $Root/Center/Window/CloseButton

func _ready() -> void:
	visible = false
	manage_button.pressed.connect(_on_manage_button_pressed)
	assign_button.pressed.connect(_on_assign_button_pressed)
	build_button.pressed.connect(_on_build_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)

func open_menu(storage_state: Dictionary) -> void:

	get_tree().paused = true
	visible = true
	_update_status(storage_state)

func _update_status(storage_state: Dictionary) -> void:
	var held_fee_totals: Dictionary = storage_state.get(
		"held_fee_totals",
		{}
	)
	var held_lots: Array = storage_state.get("held_lots", [])
	var pending_count: int = int(storage_state.get("pending_count", 0))

	held_label.text = "Held: %d" % held_lots.size()
	pending_label.text = "Pending: %d" % pending_count
	held_label.remove_theme_color_override("font_color")
	pending_label.remove_theme_color_override("font_color")
	held_fees_label.text = "Held Fees: %s" % _format_currency_totals(
		held_fee_totals
	)
	var active_processes: Array = storage_state.get(
		"active_processes",
		[]
	)
	var has_active_processes: bool = not active_processes.is_empty()
	status_separator.visible = has_active_processes
	processing_label.visible = has_active_processes
	processing_label.text = "Processing: %s" % (
		_format_active_processes(active_processes)
	)

func _format_active_processes(active_processes: Array) -> String:
	var parts: PackedStringArray = []
	for process_value in active_processes:
		var process_entry: Dictionary = process_value
		var title: String = str(
			process_entry.get("title", "Process")
		)
		var quantity: int = maxi(
			int(process_entry.get("total_quantity", 0)),
			0
		)
		parts.append("%s x%d" % [title, quantity])

	return ", ".join(parts)

func _format_currency_totals(currency_totals: Dictionary) -> String:
	if currency_totals.is_empty():
		return "-"

	var parts: PackedStringArray = []
	for currency_id_value in currency_totals.keys():
		var currency_id: String = str(currency_id_value)
		var display_name: String = currency_id.replace("_", " ").capitalize()
		var currency_data: ItemData = ItemDatabase.get_item_data(currency_id)
		if currency_data != null:
			display_name = currency_data.display_name
		parts.append(
			"%d %s" % [int(currency_totals[currency_id_value]), display_name]
		)

	return ", ".join(parts)

func _select_action(action_id: int) -> void:
	get_tree().paused = false
	hide()
	action_selected.emit(action_id)
	queue_free()

func _on_manage_button_pressed() -> void:
	_select_action(Action.MANAGE_STORAGE)

func _on_assign_button_pressed() -> void:
	_select_action(Action.ASSIGN_WORK)

func _on_build_button_pressed() -> void:
	_select_action(Action.BUILD_AND_UPGRADE)

func _on_close_button_pressed() -> void:
	get_tree().paused = false
	hide()
	closed.emit()
	queue_free()
