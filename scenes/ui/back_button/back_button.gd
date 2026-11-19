extends Button

const BACK_ICON: Texture2D = preload("res://assets/ui/ui_icon/back_button.png")
const ORIGINAL_STATE_META: StringName = &"_back_button_original_presentation_state"
const STYLEBOX_NAMES: Array[StringName] = [
	&"normal",
	&"hover",
	&"pressed",
	&"hover_pressed",
	&"disabled",
]


static func set_back_presentation(button: Button, enabled: bool) -> void:
	if not is_instance_valid(button):
		return

	if enabled:
		var original_state: Dictionary = _get_or_store_original_state(button)
		button.custom_minimum_size = Vector2(64, 18)
		button.icon = BACK_ICON
		button.expand_icon = false
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var resolved_styleboxes: Dictionary = original_state["resolved_styleboxes"]
		for style_name: StringName in STYLEBOX_NAMES:
			var original_stylebox: StyleBox = resolved_styleboxes.get(style_name) as StyleBox
			if original_stylebox == null:
				continue
			var back_stylebox: StyleBox = original_stylebox.duplicate() as StyleBox
			back_stylebox.content_margin_top = 1.0
			back_stylebox.content_margin_bottom = 1.0
			button.add_theme_stylebox_override(style_name, back_stylebox)
		return

	if not button.has_meta(ORIGINAL_STATE_META):
		return

	var original_state: Dictionary = button.get_meta(ORIGINAL_STATE_META)
	button.custom_minimum_size = original_state["custom_minimum_size"]
	button.icon = original_state["icon"]
	button.expand_icon = original_state["expand_icon"]
	button.texture_filter = original_state["texture_filter"]
	var original_stylebox_overrides: Dictionary = original_state["stylebox_overrides"]
	for style_name: StringName in STYLEBOX_NAMES:
		if original_stylebox_overrides.has(style_name):
			button.add_theme_stylebox_override(style_name, original_stylebox_overrides[style_name])
		else:
			button.remove_theme_stylebox_override(style_name)
	button.remove_meta(ORIGINAL_STATE_META)


static func set_back_pair_size(button: Button) -> void:
	if not is_instance_valid(button):
		return
	_get_or_store_original_state(button)
	button.custom_minimum_size = Vector2(64, 18)


static func _get_or_store_original_state(button: Button) -> Dictionary:
	if button.has_meta(ORIGINAL_STATE_META):
		return button.get_meta(ORIGINAL_STATE_META)

	var original_stylebox_overrides: Dictionary = {}
	var original_resolved_styleboxes: Dictionary = {}
	for style_name: StringName in STYLEBOX_NAMES:
		if button.has_theme_stylebox_override(style_name):
			original_stylebox_overrides[style_name] = button.get_theme_stylebox(style_name)
		original_resolved_styleboxes[style_name] = button.get_theme_stylebox(style_name)

	var original_state: Dictionary = {
		"custom_minimum_size": button.custom_minimum_size,
		"icon": button.icon,
		"expand_icon": button.expand_icon,
		"texture_filter": button.texture_filter,
		"stylebox_overrides": original_stylebox_overrides,
		"resolved_styleboxes": original_resolved_styleboxes,
	}
	button.set_meta(ORIGINAL_STATE_META, original_state)
	return original_state


func _ready() -> void:
	set_back_presentation(self, true)
