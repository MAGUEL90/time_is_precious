extends CanvasLayer

signal site_selected(site_id: String)
signal add_worker_requested
signal deplete_requested
signal finish_requested
signal save_requested
signal continue_requested

const PANEL_SIZE: Vector2 = Vector2(236.0, 178.0)
const UI_FONT_SIZE: int = 8

var site_option: OptionButton
var state_label: Label
var add_worker_button: Button
var deplete_button: Button
var finish_button: Button
var save_button: Button
var continue_button: Button
var panel: PanelContainer
var panel_toggle: Button

var _action_buttons: Array[Button] = []
var _busy: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build_ui()


func set_sites(entries: Array[Dictionary]) -> void:
	if not is_instance_valid(site_option):
		return
	site_option.clear()
	for entry: Dictionary in entries:
		var site_id: String = str(entry.get("id", ""))
		var site_label: String = str(entry.get("label", site_id))
		if site_id.is_empty():
			continue
		var index: int = site_option.item_count
		site_option.add_item(site_label)
		site_option.set_item_metadata(index, site_id)
	if site_option.item_count > 0:
		site_option.select(0)
	set_busy(_busy)

func select_site(site_id: String) -> void:
	if not is_instance_valid(site_option):
		return
	for index: int in range(site_option.item_count):
		if str(site_option.get_item_metadata(index)) == site_id:
			site_option.select(index)
			return


func show_state(message: String) -> void:
	if is_instance_valid(state_label):
		state_label.text = "State / timer: " + message


func set_busy(busy: bool) -> void:
	_busy = busy
	if is_instance_valid(site_option):
		site_option.disabled = busy
	for button: Button in _action_buttons:
		if is_instance_valid(button):
			button.disabled = busy


func _build_ui() -> void:
	panel_toggle = _make_button("Open Lab Controls", Vector2(96.0, 18.0))
	panel_toggle.name = "LabControlsToggle"
	panel_toggle.position = Vector2(8.0, 8.0)
	panel_toggle.pressed.connect(_toggle_panel)
	add_child(panel_toggle)

	panel = PanelContainer.new()
	panel.name = "ResourceRespawnLabPanel"
	panel.position = Vector2(8.0, 29.0)
	panel.size = PANEL_SIZE
	panel.custom_minimum_size = PANEL_SIZE
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.055, 0.075, 0.94)
	panel_style.border_color = Color(0.39, 0.72, 0.72, 0.95)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(3)
	panel_style.content_margin_left = 5.0
	panel_style.content_margin_top = 4.0
	panel_style.content_margin_right = 5.0
	panel_style.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 1)
	panel.add_child(margin)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 2)
	margin.add_child(layout)

	var title: Label = Label.new()
	title.text = "RESOURCE RESPAWN LAB"
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color(0.75, 0.94, 0.91))
	layout.add_child(title)

	var notice: Label = Label.new()
	notice.text = "TEST ONLY · FIXED POINTS · ISOLATED SAVE"
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.custom_minimum_size.y = 17.0
	notice.add_theme_font_size_override("font_size", 7)
	notice.add_theme_color_override("font_color", Color(1.0, 0.78, 0.42))
	layout.add_child(notice)

	var site_row: HBoxContainer = HBoxContainer.new()
	site_row.add_theme_constant_override("separation", 3)
	layout.add_child(site_row)
	var site_caption: Label = Label.new()
	site_caption.text = "Site"
	site_caption.custom_minimum_size.x = 25.0
	site_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	site_caption.add_theme_font_size_override("font_size", UI_FONT_SIZE)
	site_row.add_child(site_caption)
	site_option = OptionButton.new()
	site_option.name = "SiteOption"
	site_option.custom_minimum_size = Vector2(190.0, 18.0)
	site_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	site_option.add_theme_font_size_override("font_size", UI_FONT_SIZE)
	site_option.item_selected.connect(_on_site_item_selected)
	site_row.add_child(site_option)

	var state_frame: Control = Control.new()
	state_frame.custom_minimum_size = Vector2(220.0, 36.0)
	state_frame.clip_contents = true
	layout.add_child(state_frame)

	state_label = Label.new()
	state_label.name = "StateTimerLabel"
	state_label.text = "State / timer: waiting for sandbox state."
	state_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state_label.clip_text = true
	state_label.add_theme_font_size_override("font_size", UI_FONT_SIZE)
	state_frame.add_child(state_label)

	var worker_row: HBoxContainer = HBoxContainer.new()
	worker_row.add_theme_constant_override("separation", 3)
	layout.add_child(worker_row)
	add_worker_button = _make_button("Add Test Worker", Vector2(126.0, 18.0))
	deplete_button = _make_button("Deplete", Vector2(82.0, 18.0))
	worker_row.add_child(add_worker_button)
	worker_row.add_child(deplete_button)

	finish_button = _make_button("Finish Timer (Debug)", Vector2(220.0, 18.0))
	layout.add_child(finish_button)

	var save_row: HBoxContainer = HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 3)
	layout.add_child(save_row)
	save_button = _make_button("Save Debug", Vector2(92.0, 18.0))
	continue_button = _make_button("Continue Debug", Vector2(124.0, 18.0))
	save_row.add_child(save_button)
	save_row.add_child(continue_button)

	_action_buttons = [add_worker_button, deplete_button, finish_button, save_button, continue_button]
	add_worker_button.pressed.connect(_on_add_worker_pressed)
	deplete_button.pressed.connect(_on_deplete_pressed)
	finish_button.pressed.connect(_on_finish_pressed)
	save_button.pressed.connect(_on_save_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	set_busy(_busy)


func _toggle_panel() -> void:
	panel.visible = not panel.visible
	panel_toggle.text = "Hide Lab Controls" if panel.visible else "Open Lab Controls"


func _make_button(caption: String, minimum_size: Vector2) -> Button:
	var button: Button = Button.new()
	button.text = caption
	button.custom_minimum_size = minimum_size
	button.add_theme_font_size_override("font_size", UI_FONT_SIZE)
	return button


func _on_site_item_selected(index: int) -> void:
	if _busy or index < 0 or index >= site_option.item_count:
		return
	var site_id: String = str(site_option.get_item_metadata(index))
	if not site_id.is_empty():
		site_selected.emit(site_id)


func _on_add_worker_pressed() -> void:
	if not _busy:
		add_worker_requested.emit()


func _on_deplete_pressed() -> void:
	if not _busy:
		deplete_requested.emit()


func _on_finish_pressed() -> void:
	if not _busy:
		finish_requested.emit()


func _on_save_pressed() -> void:
	if not _busy:
		save_requested.emit()


func _on_continue_pressed() -> void:
	if not _busy:
		continue_requested.emit()
