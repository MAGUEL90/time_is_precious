class_name ItemTransferUI extends CanvasLayer

signal transfer_confirmed(selected_items: Dictionary)
signal transfer_back_requested()
signal transfer_cancelled()

@onready var title_label: Label = $Root/Center/Window/MarginContainer/MainVBox/Header/TitleLabel
@onready var close_button: Button = $Root/Center/Window/MarginContainer/MainVBox/Header/CloseButton
@onready var info_label: Label = $Root/Center/Window/MarginContainer/MainVBox/InfoLabel
@onready var grid_container: GridContainer = $Root/Center/Window/MarginContainer/MainVBox/ScrollContainer/GridContainer
@onready var selected_summary_label: Label = $Root/Center/Window/MarginContainer/MainVBox/Footer/SelectedSummaryLabel
@onready var back_button: Button = $Root/Center/Window/MarginContainer/MainVBox/Footer/BackButton
@onready var confirm_button: Button = $Root/Center/Window/MarginContainer/MainVBox/Footer/ConfirmButton

var selected_items: Dictionary[String, int] = {}
var source_items: Dictionary = {}
var allowed_category: int = ItemEnums.ItemCategory.RESOURCE

func _ready() -> void:
	visible = false
	back_button.pressed.connect(_on_back_pressed)
	close_button.pressed.connect(_on_close_pressed)
	confirm_button.pressed.connect(_on_confirm_button)

func open_transfer(title: String, items: Dictionary, confirm_text: String) -> void:
	title_label.text = title
	confirm_button.text = confirm_text
	source_items = items
	selected_items.clear()
	visible = true
	get_tree().paused = true
	_refresh_grid()
	_refresh_summary()

func _on_back_pressed() -> void:
	visible = false
	get_tree().paused = false
	transfer_back_requested.emit()
	queue_free()

func _on_close_pressed() -> void:
	visible = false
	get_tree().paused = false
	transfer_cancelled.emit()
	queue_free()

func _on_confirm_button() -> void:
	visible = false
	get_tree().paused = false
	transfer_confirmed.emit(selected_items.duplicate(true))
	queue_free()

func _refresh_grid() -> void:
	for child in grid_container.get_children():
		child.queue_free()

	for item_id in source_items.keys():
		var qty: int = int(source_items[item_id])
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		if item_data == null:
			continue

		if item_data.category != allowed_category:
			continue

		var slot_scene: PackedScene = preload("res://scenes/ui/item_slot/item_slot.tscn")
		var item_slot: ItemSlot = slot_scene.instantiate()
		grid_container.add_child(item_slot)
		item_slot.set_item(item_id, qty, item_data.icon)
		item_slot.slot_clicked.connect(_on_item_slot_clicked)
		item_slot.slot_deposit_requested.connect(_on_item_slot_decrease_requested)

func _refresh_summary() -> void:
	var total_selected: int = 0

	for item_id in selected_items.keys():
		total_selected += int(selected_items[item_id])

	selected_summary_label.text = "Selected: %d" % total_selected
	confirm_button.disabled = total_selected <= 0

func _on_item_slot_clicked(item_id: String, quantity: int, _slot_ref: ItemSlot) -> void:
	var current_selected: int = selected_items.get(item_id, 0)
	var step: int = _get_transfer_step()
	var next_qty: int = min(current_selected + step, quantity)

	if current_selected >= quantity:
		return

	selected_items[item_id] = next_qty
	_slot_ref.set_selected_quantity(next_qty)
	_refresh_summary()

func _on_item_slot_decrease_requested(item_id: String, _quantity: int, _slot_ref: ItemSlot) -> void:
	var current_selected: int = selected_items.get(item_id, 0)
	if current_selected <= 0:
		return

	var step: int = _get_transfer_step()
	var next_qty: int = max(current_selected - step, 0)

	if next_qty <= 0:
		selected_items.erase(item_id)
	else:
		selected_items[item_id] = next_qty

	_refresh_summary()
	_slot_ref.set_selected_quantity(next_qty)

func _get_transfer_step() -> int:
	if Input.is_key_pressed(KEY_CTRL):
		return 50

	if Input.is_key_pressed(KEY_SHIFT):
		return 10

	return 1
