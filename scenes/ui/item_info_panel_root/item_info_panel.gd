class_name ItemInfoPanel extends Control

const PANEL_WIDTH: float = 260.0
const PANEL_MIN_HEIGHT: float = 40.0
const PANEL_ANCHOR_HEIGHT: float = 64.0
const PANEL_VERTICAL_PADDING: float = 12.0
const EFFECT_COLOR: Color = Color(0.24, 0.52, 0.72, 1.0)
const PANEL_HORIZONTAL_PADDING: float = 12.0
const NAME_LINE_HEIGHT: float = 10.0

@onready var name_label: Label = $MarginContainer/LabelContainer/NameLabel
@onready var category_label: Label = $MarginContainer/LabelContainer/CategoryWeightContainer/CategoryLabel
@onready var weight_label: Label = $MarginContainer/LabelContainer/CategoryWeightContainer/WeightLabel
@onready var description_label: Label = $MarginContainer/LabelContainer/DescriptionLabel
@onready var effect_label: Label = $MarginContainer/LabelContainer/EffectLabel
@onready var label_container: VBoxContainer = $MarginContainer/LabelContainer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_MIN_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Control in find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_size()
	visible = false

func display_item(item_id: String) -> bool:
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if item_data == null:
		clear_item()
		return false

	var item_name: String = (
		item_data.display_name
		if not item_data.display_name.is_empty()
		else item_id
	)

	name_label.text = "name: %s" % item_name
	category_label.text = "category: %s" % _get_category_text(item_data.category)
	weight_label.text = "weight: -" if bool(item_data.get_meta("weight_pending", false)) else "weight: %.2f" % item_data.weight
	var effect_text: String = _get_effect_text(item_data)
	effect_label.text = "effect: %s" % effect_text
	if effect_text == "none":
		effect_label.remove_theme_color_override("font_color")
	else:
		effect_label.add_theme_color_override("font_color", EFFECT_COLOR)
	description_label.text = (
		item_data.description
		if not item_data.description.is_empty()
		else "-"
	)

	_refresh_size()
	visible = true
	return true

func clear_item() -> void:
	visible = false

func position_lower_center(bottom_limit: float) -> void:
	var bounds: Vector2 = get_viewport().get_visible_rect().size
	global_position = Vector2(
		maxf(4, (bounds.x - size.x) * 0.5),
		clampf(bottom_limit - PANEL_ANCHOR_HEIGHT - 4, 4, maxf(4, bounds.y - PANEL_ANCHOR_HEIGHT - 4))
	).round()

func bind_slot(slot: ItemSlot, footer: Control) -> void:
	slot.slot_hovered.connect(func(item_id: String, _quantity: int, _slot: ItemSlot):
		if display_item(item_id):
			position_lower_center(footer.global_position.y)
	)
	slot.slot_unhovered.connect(func(_slot: ItemSlot): clear_item())

func _get_category_text(category: ItemEnums.ItemCategory) -> String:
	match category:
		ItemEnums.ItemCategory.RESOURCE:
			return "RESOURCE"
		ItemEnums.ItemCategory.CONSUMABLE:
			return "FOOD"
		ItemEnums.ItemCategory.EQUIPMENT:
			return "EQUIP"
		ItemEnums.ItemCategory.PLACEABLE:
			return "BUILD"
		ItemEnums.ItemCategory.KEY_ITEM:
			return "QUEST"
		_:
			return "UNKNOWN"

func _get_effect_text(item_data: ItemData) -> String:
	var effects: Array[String] = []

	if item_data.hunger_reduction > 0.0:
		effects.append(
			"hunger -%d%%"
			% int(round(item_data.hunger_reduction * 100.0))
		)

	if item_data.fatigue_reduction > 0.0:
		effects.append(
			"fatigue -%d%%"
			% int(round(item_data.fatigue_reduction * 100.0))
		)

	if item_data.food_supply_value > 0:
		effects.append("food supply +%d" % item_data.food_supply_value)

	if item_data.clothing_supply_value > 0:
		effects.append(
			"clothing supply +%d"
			% item_data.clothing_supply_value
		)

	return "none" if effects.is_empty() else ", ".join(effects)

func _get_minimum_size() -> Vector2:
	if not is_node_ready():
		return Vector2(PANEL_WIDTH, PANEL_MIN_HEIGHT)
	return Vector2(PANEL_WIDTH, maxf(PANEL_MIN_HEIGHT, label_container.get_combined_minimum_size().y + PANEL_VERTICAL_PADDING))

func _fit_wrapped_label(label: Label) -> void:
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var max_lines: int = label.max_lines_visible
	var text_size: Vector2 = font.get_multiline_string_size(
		label.text,
		label.horizontal_alignment,
		PANEL_WIDTH - PANEL_HORIZONTAL_PADDING,
		font_size,
		max_lines
	)
	var base_line_height: float = maxf(font.get_height(font_size), 1.0)
	var line_count: int = maxi(
		int(ceilf(text_size.y / base_line_height)),
		1
	)
	# Glyph descenders can increase measured height without adding a line.
	# Treat text that fits on one line as one line even when it has underscores.
	if not label.text.contains("\n") and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= PANEL_WIDTH - PANEL_HORIZONTAL_PADDING:
		line_count = 1

	if max_lines > 0:
		line_count = mini(line_count, max_lines)

	var line_spacing: int = label.get_theme_constant("line_spacing")

	var line_height: float = NAME_LINE_HEIGHT if label == name_label else float(label.get_line_height())
	label.custom_minimum_size.y = float(
		line_count * line_height
		+ maxi(line_count - 1, 0) * line_spacing
	)

	label.update_minimum_size()

func _refresh_size() -> void:
	_fit_wrapped_label(name_label)
	_fit_wrapped_label(effect_label)
	_fit_wrapped_label(description_label)

	label_container.update_minimum_size()
	update_minimum_size()
	size = _get_minimum_size()
	pivot_offset = size * 0.5
