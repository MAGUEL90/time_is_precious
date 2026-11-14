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

@onready var title_label: Label = $Root/Center/Window/Margin/Content/Header/Title
@onready var subtitle: Label = $Root/Center/Window/Margin/Content/Subtitle
@onready var choices: VBoxContainer = $Root/Center/Window/Margin/Content/Choices
@onready var back_button: Button = $Root/Center/Window/Margin/Content/Footer/Back
@onready var close_button: BaseButton = $Root/Center/Window/Margin/Content/Header/CloseButton
@onready var done_button: Button = $Root/Center/Window/Margin/Content/Footer/Close

var current_category: String = ""
var selected_building: String = ""
var buttons: Dictionary = {}
var _plot_label: String = ""
var _closing: bool = false
var workshop_available: bool = true
var workshop_enabled: bool = true

func _ready() -> void:
	back_button.pressed.connect(go_back)
	close_button.pressed.connect(close_menu)
	done_button.pressed.connect(close_menu)

func open_menu(plot_label: String) -> void:
	_plot_label = plot_label
	_show_categories()
	show()

func _clear_choices() -> void:
	buttons.clear()
	for child: Node in choices.get_children():
		choices.remove_child(child)
		child.queue_free()

func _add_button(id: String, text: String, action: Callable, locked: bool = false) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.custom_minimum_size = Vector2(0, 20)
	button.theme_type_variation = &"HudShortcutButton"
	button.add_theme_font_size_override("font_size", 6)
	button.disabled = locked
	if not locked:
		button.pressed.connect(action)
	choices.add_child(button)
	buttons[id] = button
	return button

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

func _show_categories(focus_id: String = "residential") -> void:
	_clear_choices()
	current_category = ""
	selected_building = ""
	title_label.text = "BUILDING MENU"
	subtitle.text = _plot_label + " / Choose a category"
	back_button.hide()
	for id: String in CATEGORIES:
		_add_button(id, CATEGORIES[id], _show_category.bind(id))
	buttons[focus_id].grab_focus.call_deferred()

func _show_category(id: String, focus_id: String = "") -> void:
	if not CATEGORIES.has(id):
		return
	_clear_choices()
	current_category = id
	selected_building = ""
	title_label.text = CATEGORIES[id].to_upper()
	subtitle.text = _plot_label + " / Choose a building"
	back_button.show()
	match id:
		"residential":
			_add_button("house", "House", _show_building.bind("house"))
			_add_button("courtyard_house", "Courtyard House (Locked)", Callable(), true)
			buttons["house"].grab_focus.call_deferred()
		"production":
			if not workshop_enabled:
				_add_button("mudbrick_workshop", "Mudbrick Workshop (Locked)", Callable(), true)
				_add_notice("Not available yet.")
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
