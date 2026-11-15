extends CanvasLayer

signal closed
signal house_requested
signal workshop_requested

const CATEGORIES: Dictionary = {
	"residential": "Residential",
	"production": "Production",
	"food_farming": "Food & Farming",
	"storage_logistic": "Storage & Logistic",
	"civic_services": "Civic & Services",
}
const PLACEHOLDER_ICON: Texture2D = preload("res://assets/ui/ui_icon/plus_icon_2.png")
const LOCK_ICON: Texture2D = preload("res://assets/ui/ui_icon/lock_icon.png")
const SELECTOR_SHEET: Texture2D = preload("res://assets/ui/ui_icon/icon_24.06.2026.png")
const MIN_WINDOW_WIDTH: float = 180.0

@onready var window: Control = $Root/Center/Window
@onready var window_margin: MarginContainer = $Root/Center/Window/Margin
@onready var title_label: Label = $Root/Center/Window/Margin/Content/Header/Title
@onready var subtitle: Label = $Root/Center/Window/Margin/Content/Subtitle
@onready var choices: VBoxContainer = $Root/Center/Window/Margin/Content/Choices
@onready var back_button: Button = $Root/Center/Window/Margin/Content/Footer/Back
@onready var close_button: TextureButton = $Root/Center/Window/Margin/Content/Header/CloseButton
@onready var hover_name: Label = $Root/HoverName

var current_category: String = ""
var selected_building: String = ""
var buttons: Dictionary = {}
var _choice_row: HBoxContainer
var _hovered_button: Button
var _hovered_choice: Button
var _keyboard_navigation: bool = false
var _selector_texture: AtlasTexture
var _closing: bool = false
var workshop_available: bool = true
var workshop_enabled: bool = true

func _ready() -> void:
	_selector_texture = AtlasTexture.new()
	_selector_texture.atlas = SELECTOR_SHEET
	_selector_texture.region = Rect2(133, 101, 22, 22)
	back_button.pressed.connect(go_back)
	close_button.pressed.connect(close_menu)
	close_button.texture_focused = close_button.texture_hover
	window_margin.minimum_size_changed.connect(_fit_window_to_content)
	_fit_window_to_content.call_deferred()

func _fit_window_to_content() -> void:
	# NinePatchRect does not inherit the minimum size of its anchored content.
	var content_size := window_margin.get_combined_minimum_size()
	window.custom_minimum_size = Vector2(maxf(MIN_WINDOW_WIDTH, content_size.x), content_size.y)

func open_menu(_plot_label: String) -> void:
	_show_categories()
	show()

func _clear_choices() -> void:
	_hide_hover_name()
	_hovered_choice = null
	buttons.clear()
	for child: Node in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	_choice_row = HBoxContainer.new()
	_choice_row.name = "ChoiceRow"
	_choice_row.add_theme_constant_override("separation", 3)
	_choice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	choices.add_child(_choice_row)

func _add_button(id: String, text: String, action: Callable, locked: bool = false) -> Button:
	var tile := VBoxContainer.new()
	tile.name = "%sTile" % id
	tile.custom_minimum_size = Vector2(16, 0)
	tile.add_theme_constant_override("separation", 2)
	_choice_row.add_child(tile)

	var button := Button.new()
	button.name = id
	button.custom_minimum_size = Vector2(16, 16)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.theme_type_variation = &"WorkshopSquareButton16"
	button.add_theme_font_size_override("font_size", 6)
	button.icon = LOCK_ICON if locked else PLACEHOLDER_ICON
	button.expand_icon = false
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.accessibility_name = text
	button.disabled = locked
	if locked:
		button.add_theme_color_override("icon_disabled_color", Color.WHITE)
	else:
		button.pressed.connect(action)
	tile.add_child(button)
	# Match the Inventory and Work Order selector instead of changing panel fill.
	button.add_theme_stylebox_override("hover", button.get_theme_stylebox("normal"))
	var selection_frame := NinePatchRect.new()
	selection_frame.name = "SelectionFrame"
	selection_frame.texture = _selector_texture
	selection_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	selection_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_frame.patch_margin_left = 5
	selection_frame.patch_margin_top = 5
	selection_frame.patch_margin_right = 5
	selection_frame.patch_margin_bottom = 5
	selection_frame.visible = false
	button.add_child(selection_frame)
	selection_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.mouse_entered.connect(_on_choice_mouse_entered.bind(button))
	button.mouse_exited.connect(_on_choice_mouse_exited.bind(button))
	button.focus_entered.connect(_refresh_choice_highlights)
	button.focus_exited.connect(_refresh_choice_highlights)

	button.mouse_entered.connect(_show_hover_name.bind(text, button))
	button.mouse_exited.connect(_hide_hover_name)
	buttons[id] = button
	return button

func _on_choice_mouse_entered(button: Button) -> void:
	_hovered_choice = button
	_keyboard_navigation = false
	_refresh_choice_highlights()

func _on_choice_mouse_exited(button: Button) -> void:
	if _hovered_choice == button:
		_hovered_choice = null
	_refresh_choice_highlights()

func _refresh_choice_highlights() -> void:
	var use_mouse: bool = not _keyboard_navigation and is_instance_valid(_hovered_choice)
	for button: Button in buttons.values():
		var frame: NinePatchRect = button.get_node("SelectionFrame") as NinePatchRect
		frame.visible = (
			not button.disabled
			and (button == _hovered_choice if use_mouse else button.has_focus())
		)

func _show_hover_name(text: String, button: Button) -> void:
	_hovered_button = button
	hover_name.text = text
	hover_name.reset_size()
	_position_hover_name(get_viewport().get_mouse_position())
	hover_name.show()

func _hide_hover_name() -> void:
	_hovered_button = null
	hover_name.hide()

func _position_hover_name(mouse_position: Vector2) -> void:
	var bounds: Rect2 = get_viewport().get_visible_rect()
	var pos := mouse_position + Vector2(6, -hover_name.size.y - 4)
	if is_instance_valid(_hovered_button):
		pos.y = minf(pos.y, _hovered_button.get_global_rect().position.y - hover_name.size.y - 2)
	if pos.x + hover_name.size.x > bounds.end.x:
		pos.x = mouse_position.x - hover_name.size.x - 6
	if pos.y < bounds.position.y:
		pos.y = mouse_position.y + 6
	pos.x = clampf(pos.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - hover_name.size.x))
	pos.y = clampf(pos.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - hover_name.size.y))
	hover_name.position = pos

func _add_notice(text: String) -> void:
	var label := Label.new()
	label.name = "Notice"
	label.text = text
	label.theme_type_variation = &"HudLabelShortcut"
	label.add_theme_font_size_override("font_size", 6)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choices.add_child(label)

func _prepare_icon_row() -> void:
	_choice_row.add_theme_constant_override("separation", 8)
	# Leave room above the icons for the name without covering the subtitle.
	choices.remove_child(_choice_row)
	var hover_space := MarginContainer.new()
	hover_space.add_theme_constant_override("margin_top", 8)
	choices.add_child(hover_space)
	hover_space.add_child(_choice_row)

func _show_categories(focus_id: String = "residential") -> void:
	_clear_choices()
	_prepare_icon_row()
	current_category = ""
	selected_building = ""
	title_label.text = "BUILDING MENU"
	subtitle.text = "Choose a category"
	back_button.hide()
	for id: String in CATEGORIES:
		_add_button(id, CATEGORIES[id], _show_category.bind(id))
	buttons[focus_id].grab_focus.call_deferred()

func _show_category(id: String, focus_id: String = "") -> void:
	if not CATEGORIES.has(id):
		return
	_clear_choices()
	if id == "residential" or id == "production":
		_prepare_icon_row()
	current_category = id
	selected_building = ""
	title_label.text = CATEGORIES[id].to_upper()
	subtitle.text = "Choose a building"
	back_button.show()
	match id:
		"residential":
			_add_button("house", "House", _show_building.bind("house"))
			_add_button("courtyard_house", "Courtyard House", Callable(), true)
			buttons["house"].grab_focus.call_deferred()
		"production":
			if not workshop_enabled:
				_add_button("mudbrick_workshop", "Mudbrick Workshop", Callable(), true)
				back_button.grab_focus.call_deferred()
				return
			_add_button("mudbrick_workshop", "Mudbrick Workshop" if workshop_available else "Mudbrick Workshop (Limit: 1)", _show_building.bind("mudbrick_workshop"), not workshop_available)
			if workshop_available:
				buttons["mudbrick_workshop"].grab_focus.call_deferred()
			else:
				_add_notice("A Mudbrick Workshop is already being built or is ready.")
				back_button.grab_focus.call_deferred()
		_:
			_add_notice("No buildings available yet.")
			back_button.grab_focus.call_deferred()
	if buttons.has(focus_id) and not buttons[focus_id].disabled:
		buttons[focus_id].grab_focus.call_deferred()

func _show_building(id: String) -> void:
	if not ((current_category == "residential" and id == "house") or (current_category == "production" and id == "mudbrick_workshop")):
		return
	if id == "house":
		# The plot revalidates access and opens its existing construction panel.
		house_requested.emit()
		return
	if workshop_enabled and workshop_available:
		workshop_requested.emit()

func go_back() -> void:
	if not selected_building.is_empty():
		_show_category(current_category, selected_building)
	elif not current_category.is_empty():
		_show_categories(current_category)
	else:
		close_menu()

func close_menu() -> void:
	if _closing:
		return
	_closing = true
	hide()
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if not visible or _closing:
		return
	if event is InputEventMouseMotion:
		if _keyboard_navigation:
			_keyboard_navigation = false
			_refresh_choice_highlights()
		if hover_name.visible:
			_position_hover_name(event.position)
	elif (
		event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")
		or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down")
		or event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev")
	):
		if not _keyboard_navigation:
			_keyboard_navigation = true
			_refresh_choice_highlights()
	if event.is_action_pressed("ui_cancel"):
		go_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or event.is_action_pressed("open_inventory") or event.is_action_pressed("open_work_progress"):
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	# Also release the owner's modal lock if the UI is removed externally.
	if not _closing:
		_closing = true
		closed.emit()
