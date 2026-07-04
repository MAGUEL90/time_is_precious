class_name InventoryCategorySelector extends HBoxContainer

signal category_changed(category)

const CATEGORY_ALL: int = -1
const ARROW_NORMAL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const ARROW_HOVER_COLOR: Color = Color(1.35, 1.25, 0.75, 1.0)
const ARROW_PRESSED_SCALE: Vector2 = Vector2(0.88, 0.88)

@onready var prev_button: Button = $PrevButton
@onready var next_button: Button = $NextButton
@onready var category_label: Label = $LabelFrame/CategoryLabel

var categories: Array[int] = [
	CATEGORY_ALL,
	ItemEnums.ItemCategory.RESOURCE,
	ItemEnums.ItemCategory.CONSUMABLE,
	ItemEnums.ItemCategory.EQUIPMENT,
	ItemEnums.ItemCategory.PLACEABLE,
	ItemEnums.ItemCategory.KEY_ITEM
]

var category_labels: Array[String] = [
	"ALL",
	"RESOURCE",
	"FOOD",
	"EQUIP",
	"BUILD",
	"QUEST"]

var selected_category_index: int = 0

# Setup / Public API

func _ready() -> void:
	prev_button.pressed.connect(_on_prev_button_pressed)
	next_button.pressed.connect(_on_next_button_pressed)

	_setup_arrow_button(prev_button)
	_setup_arrow_button(next_button)
	call_deferred("_refresh_arrow_button_pivots")

	_update_category_label()
	category_changed.emit(categories[selected_category_index])

# Category navigation

func _on_prev_button_pressed() -> void:
	var category_count: int = _get_category_count()
	selected_category_index = wrapi(selected_category_index - 1, 0, category_count)
	_update_category_label()
	category_changed.emit(categories[selected_category_index])

func _on_next_button_pressed() -> void:
	var category_count: int = _get_category_count()
	selected_category_index = wrapi(selected_category_index + 1, 0, category_count)
	_update_category_label()
	category_changed.emit(categories[selected_category_index])

func _update_category_label():
	category_label.text = category_labels[selected_category_index]

func _get_category_count() -> int:
	return min(categories.size(), category_labels.size())

func get_selected_category() -> int:
	return categories[selected_category_index]

# Arrow button feedback

func _setup_arrow_button(button: Button) -> void:
	button.self_modulate = ARROW_NORMAL_COLOR
	button.mouse_entered.connect(_on_arrow_button_mouse_entered.bind(button))
	button.mouse_exited.connect(_on_arrow_button_mouse_exited.bind(button))
	button.button_down.connect(_on_arrow_button_down.bind(button))
	button.button_up.connect(_on_arrow_button_up.bind(button))

func _refresh_arrow_button_pivots() -> void:
	prev_button.pivot_offset = prev_button.size * 0.5
	next_button.pivot_offset = next_button.size * 0.5

func _on_arrow_button_mouse_entered(button: Button) -> void:
	button.self_modulate = ARROW_HOVER_COLOR

func _on_arrow_button_mouse_exited(button: Button) -> void:
	button.self_modulate = ARROW_NORMAL_COLOR

func _on_arrow_button_down(button: Button) -> void:
	button.scale = ARROW_PRESSED_SCALE

func _on_arrow_button_up(button: Button) -> void:
	button.scale = Vector2.ONE
