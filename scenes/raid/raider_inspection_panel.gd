extends Control
class_name RaiderInspectionPanel

signal back_requested

@onready var party_type_label: Label = $Center/Frame/Margin/Contents/PartyTypeLabel
@onready var eta_label: Label = $Center/Frame/Margin/Contents/EtaLabel
@onready var composition_label: Label = $Center/Frame/Margin/Contents/CompositionLabel
@onready var cards_container: HBoxContainer = $Center/Frame/Margin/Contents/CardsRow
@onready var back_button: Button = $Center/Frame/Margin/Contents/FooterRow/BackButton

var _card_type_ids: Array[String] = []
var _card_name_labels: Array[Label] = []
var _card_count_labels: Array[Label] = []
var _card_icons: Array[Control] = []

func _ready() -> void:
	back_button.pressed.connect(func(): back_requested.emit())

func show_inspection(inspection: Dictionary) -> void:
	var party_type: String = str(inspection.get("type", "")).strip_edges()
	party_type_label.text = party_type if not party_type.is_empty() else "Raider party"
	var phase: String = str(inspection.get("phase", ""))
	var eta_minutes: int = maxi(0, int(inspection.get("arrival_minutes_remaining", 0)))
	match phase:
		"warning":
			eta_label.text = "Approaching · ETA: %s" % _format_travel_time(eta_minutes)
		"attacking":
			eta_label.text = "Attacking · ETA: now"
		"looting":
			eta_label.text = "Looting · ETA: now"
		_:
			eta_label.text = "ETA unavailable"
	_update_unit_cards(inspection.get("units", null))
	visible = true

func clear_inspection() -> void:
	party_type_label.text = "Raider party"
	eta_label.text = "ETA unavailable"
	_update_unit_cards(null)

func _update_unit_cards(units_value: Variant) -> void:
	var entries: Array[Dictionary] = []
	if units_value is Array:
		for unit_value: Variant in units_value:
			if unit_value is Dictionary:
				var unit: Dictionary = unit_value
				if int(unit.get("count", 0)) > 0:
					entries.append(unit.duplicate(true))
	if entries.is_empty():
		_clear_cards()
		composition_label.text = "Composition unavailable"
		composition_label.show()
		cards_container.hide()
		return

	composition_label.hide()
	cards_container.show()
	var next_type_ids: Array[String] = []
	for entry: Dictionary in entries:
		next_type_ids.append(str(entry.get("id", "unknown")).to_lower())
	if next_type_ids != _card_type_ids:
		_rebuild_cards(entries, next_type_ids)
	else:
		_update_existing_cards(entries)

func _rebuild_cards(entries: Array[Dictionary], type_ids: Array[String]) -> void:
	_clear_cards()
	_card_type_ids = type_ids.duplicate()
	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index]
		var unit_id: String = type_ids[index]
		var card := PanelContainer.new()
		card.name = "UnitCard_%s" % unit_id.capitalize()
		card.custom_minimum_size = Vector2(88, 54)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color("#33271d")
		card_style.border_color = Color("#735638")
		card_style.set_border_width_all(1)
		card_style.set_content_margin_all(2)
		card.add_theme_stylebox_override("panel", card_style)
		cards_container.add_child(card)

		var card_contents := VBoxContainer.new()
		card_contents.name = "CardContents"
		card_contents.add_theme_constant_override("separation", 0)
		card.add_child(card_contents)
		var name_label := _small_label(str(entry.get("display_name", unit_id.capitalize())))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		card_contents.add_child(name_label)
		var icon := RaiderTypeIcon.new()
		icon.name = "TypeIcon_%s" % unit_id.capitalize()
		icon.custom_minimum_size = Vector2(26, 26)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card_contents.add_child(icon)
		var count_label := _small_label("x %d" % int(entry.get("count", 0)))
		count_label.name = "CountLabel"
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_contents.add_child(count_label)
		_card_name_labels.append(name_label)
		_card_count_labels.append(count_label)
		_card_icons.append(icon)
	_set_card_data(0, entries[0], type_ids[0])
	for index: int in range(1, entries.size()):
		_set_card_data(index, entries[index], type_ids[index])

func _update_existing_cards(entries: Array[Dictionary]) -> void:
	for index: int in range(entries.size()):
		_set_card_data(index, entries[index], _card_type_ids[index])

func _set_card_data(index: int, entry: Dictionary, unit_id: String) -> void:
	var display_name: String = str(entry.get("display_name", unit_id.capitalize()))
	_card_name_labels[index].text = display_name
	_card_count_labels[index].text = "x %d" % int(entry.get("count", 0))
	var texture_value: Variant = entry.get("icon", null)
	var texture: Texture2D = texture_value as Texture2D
	_card_icons[index].call("set_icon", unit_id, texture)

func _clear_cards() -> void:
	for card: Node in cards_container.get_children():
		cards_container.remove_child(card)
		card.queue_free()
	_card_type_ids.clear()
	_card_name_labels.clear()
	_card_count_labels.clear()
	_card_icons.clear()

func _small_label(label_text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HudLabelShortcut"
	label.add_theme_font_size_override("font_size", 6)
	label.text = label_text
	return label

func _format_travel_time(total_minutes: int) -> String:
	var days: int = total_minutes / 1440
	var hours: int = (total_minutes % 1440) / 60
	var minutes: int = total_minutes % 60
	if days > 0:
		return "%dd %dh" % [days, hours]
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm" % minutes
