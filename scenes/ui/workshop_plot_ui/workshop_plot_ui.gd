class_name WorkshopPlotUI extends CanvasLayer

const PANEL_16_ATLAS: Texture2D = preload(
	"res://assets/ui/ui_panel/brown_panel_16x16.png"
)
const SCROLL_GRABBER_TEXTURE: Texture2D = preload(
	"res://assets/ui/ui_icon/filled_bar.png"
)
const WORKER_PORTRAIT_ICON: Texture2D = preload(
	"res://assets/ui/ui_icon/worker_portrait_icon.png"
)
const WORKER_CARD_SIZE: Vector2 = Vector2(24, 24)
const WORKER_PORTRAIT_SIZE: Vector2 = Vector2(11, 15)
const MISSING_MATERIAL_COLOR: Color = Color(1.0, 0.82, 0.78, 1.0)
const WORKER_ASSIGNMENT_UI: PackedScene = preload(
	"res://scenes/ui/workshop_worker_assignment_ui/workshop_worker_assignment_ui.tscn"
)

signal closed
signal build_requested(worker_ids: Array[String])
signal clearing_requested(worker_ids: Array[String], use_player: bool)

@onready var requirements_page: VBoxContainer = $Root/Center/Window/Margin/MainVBox/RequirementsPage
@onready var window: NinePatchRect = $Root/Center/Window
@onready var materials_list: VBoxContainer = $Root/Center/Window/Margin/MainVBox/RequirementsPage/MaterialsList
@onready var assign_workers_button: Button = $Root/Center/Window/Margin/MainVBox/RequirementsPage/BuilderHeader/AssignWorkersButton
@onready var worker_scroll: ScrollContainer = $Root/Center/Window/Margin/MainVBox/RequirementsPage/WorkerScroll
@onready var worker_list: HBoxContainer = $Root/Center/Window/Margin/MainVBox/RequirementsPage/WorkerScroll/WorkerList
@onready var duration_label: Label = $Root/Center/Window/Margin/MainVBox/RequirementsPage/DurationRow/DurationLabel
@onready var status_label: Label = $Root/Center/Window/Margin/MainVBox/RequirementsPage/StatusLabel
@onready var cancel_button: Button = $Root/Center/Window/Margin/MainVBox/RequirementsPage/Footer/CancelButton
@onready var build_button: Button = $Root/Center/Window/Margin/MainVBox/RequirementsPage/Footer/BuildButton
@onready var progress_page: VBoxContainer = $Root/Center/Window/Margin/MainVBox/ProgressPage
@onready var progress_title: Label = $Root/Center/Window/Margin/MainVBox/ProgressPage/ProgressTitle
@onready var progress_bar: ProgressBar = $Root/Center/Window/Margin/MainVBox/ProgressPage/ProgressBar
@onready var remaining_label: Label = $Root/Center/Window/Margin/MainVBox/ProgressPage/RemainingLabel
@onready var team_label: Label = $Root/Center/Window/Margin/MainVBox/ProgressPage/TeamLabel
@onready var progress_close_button: Button = $Root/Center/Window/Margin/MainVBox/ProgressPage/Footer/CloseButton
@onready var close_button: BaseButton = $Root/Center/Window/Margin/MainVBox/TitleHeader/CloseButton

var _construction: Node
var _selected_worker_ids: Array[String] = []
var _status_override: String = ""
var _is_closing: bool = false
var _worker_assignment_menu: WorkshopWorkerAssignmentUI
var _use_player: bool = false
var player_button: Button


func _ready() -> void:
	visible = false
	requirements_page.show()
	progress_page.hide()
	cancel_button.pressed.connect(close_menu)
	build_button.pressed.connect(_on_build_pressed)
	progress_close_button.pressed.connect(close_menu)
	close_button.pressed.connect(close_menu)
	assign_workers_button.pressed.connect(_open_worker_assignment)
	_style_worker_scrollbar()
	player_button = Button.new()
	player_button.text = "Assign Player"
	player_button.theme_type_variation = &"HudShortcutButton"
	player_button.add_theme_font_size_override("font_size", 6)
	player_button.toggle_mode = true
	player_button.toggled.connect(_on_player_selected)
	assign_workers_button.get_parent().add_child(player_button)

func _on_player_selected(selected: bool) -> void:
	_use_player = selected
	if selected:
		_selected_worker_ids.clear()
	_refresh_view()


func _style_worker_scrollbar() -> void:
	var scrollbar: HScrollBar = worker_scroll.get_h_scroll_bar()
	var grabber := StyleBoxTexture.new()
	grabber.texture = SCROLL_GRABBER_TEXTURE
	grabber.texture_margin_left = 3.0
	grabber.texture_margin_top = 3.0
	grabber.texture_margin_right = 3.0
	grabber.texture_margin_bottom = 3.0
	scrollbar.add_theme_stylebox_override("grabber", grabber)
	scrollbar.add_theme_stylebox_override("grabber_highlight", grabber)
	scrollbar.add_theme_stylebox_override("grabber_pressed", grabber)


func open_menu(construction: Node = null) -> void:
	if _is_closing:
		return
	_set_construction(construction)
	_connect_inventory()
	_status_override = ""
	visible = true
	_refresh_view()
	_focus_primary_control()


func close_menu() -> void:
	if _is_closing:
		return
	_is_closing = true
	if is_instance_valid(_worker_assignment_menu):
		_worker_assignment_menu.close_menu()
		_worker_assignment_menu = null
	visible = false
	_disconnect_sources()
	closed.emit()
	queue_free()


func show_error(message: String) -> void:
	if _is_closing:
		return
	_status_override = message
	if requirements_page.visible:
		status_label.text = message
		_set_status_color(message)
		status_label.show()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(_worker_assignment_menu):
			_worker_assignment_menu.close_menu()
		else:
			close_menu()
		get_viewport().set_input_as_handled()
		return

	if (
		event.is_action_pressed("open_inventory")
		or event.is_action_pressed("open_work_progress")
		or event.is_action_pressed("interact")
	):
		get_viewport().set_input_as_handled()


func _set_construction(construction: Node) -> void:
	if _construction == construction:
		return
	_disconnect_construction()
	_construction = construction
	_selected_worker_ids.clear()
	if is_instance_valid(_construction) and _construction.has_signal("changed"):
		_construction.connect("changed", _on_construction_changed)


func _connect_inventory() -> void:
	if (
		Inventory != null
		and Inventory.has_signal("items_changed")
		and not Inventory.is_connected("items_changed", _on_inventory_items_changed)
	):
		Inventory.connect("items_changed", _on_inventory_items_changed)


func _disconnect_construction() -> void:
	if (
		is_instance_valid(_construction)
		and _construction.has_signal("changed")
		and _construction.is_connected("changed", _on_construction_changed)
	):
		_construction.disconnect("changed", _on_construction_changed)


func _disconnect_sources() -> void:
	_disconnect_construction()
	if (
		Inventory != null
		and Inventory.has_signal("items_changed")
		and Inventory.is_connected("items_changed", _on_inventory_items_changed)
	):
		Inventory.disconnect("items_changed", _on_inventory_items_changed)


func _on_construction_changed() -> void:
	_status_override = ""
	_refresh_view()


func _on_inventory_items_changed() -> void:
	if not visible or _is_closing:
		return
	_status_override = ""
	if requirements_page.visible:
		_populate_material_rows()
		_refresh_preview()


func _refresh_view() -> void:
	if _is_closing or not visible:
		return

	var was_showing_progress: bool = progress_page.visible
	var phase: String = _get_phase()
	var clearing: bool = phase in ["uncleared", "clearing"]
	var show_requirements: bool = phase in ["empty", "uncleared"]
	materials_list.visible = not clearing
	requirements_page.get_node("MaterialsTitle").visible = not clearing
	player_button.visible = phase == "uncleared"
	player_button.set_pressed_no_signal(_use_player)
	build_button.text = "Start Cleaning" if clearing else "Build"
	$Root/Center/Window/Margin/MainVBox/TitleHeader/TitleLabel.text = "CLEAR SITE" if clearing else "BUILD WORKSHOP"
	$Root/Center/Window/Margin/MainVBox/RequirementsPage/BuilderHeader/BuildersTitle.text = "Cleaner" if clearing else "Builder team"
	requirements_page.visible = show_requirements
	progress_page.visible = not show_requirements
	window.custom_minimum_size = Vector2(220, 160 if clearing else 208) if show_requirements else Vector2(220, 118)

	if show_requirements:
		_populate_material_rows()
		_populate_worker_rows()
		_refresh_preview()
	else:
		_update_progress_page(phase, _get_preview())
		if not was_showing_progress:
			progress_close_button.grab_focus()


func _get_phase() -> String:
	if not is_instance_valid(_construction):
		return "empty"
	return str(_construction.get("phase"))


func _get_requirements() -> Dictionary:
	if not is_instance_valid(_construction) or not _construction.has_method("get_requirements"):
		return {}
	var result: Variant = _construction.call("get_requirements")
	return result if result is Dictionary else {}


func _get_worker_options() -> Array:
	if not is_instance_valid(_construction) or not _construction.has_method("get_worker_options"):
		return []
	var result: Variant = _construction.call("get_worker_options")
	return result if result is Array else []


func _get_preview() -> Dictionary:
	if not is_instance_valid(_construction) or not _construction.has_method("get_preview"):
		return {"message": "Construction is unavailable.", "can_start": false}
	var selected_ids: Array[String] = _selected_worker_ids.duplicate()
	if _get_phase() in ["uncleared", "clearing"]:
		return _construction.get_clearing_preview(selected_ids, _use_player)
	var result: Variant = _construction.call("get_preview", selected_ids)
	return result if result is Dictionary else {"message": "Preview is unavailable.", "can_start": false}


func _populate_material_rows() -> void:
	_clear_children(materials_list)
	var requirements: Dictionary = _get_requirements()
	for item_id_value in requirements.keys():
		var item_id: String = str(item_id_value)
		var required: int = int(requirements[item_id_value])
		_add_material_row(item_id, int(Inventory.items.get(item_id, 0)), required)


func _add_material_row(item_id: String, held: int, required: int) -> void:
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 18)
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	materials_list.add_child(row)

	var icon_panel := TextureRect.new()
	icon_panel.custom_minimum_size = Vector2(16, 16)
	icon_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_panel.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_panel.texture = _make_panel_16_texture()
	row.add_child(icon_panel)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(16, 16)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if item_data != null:
		icon.texture = item_data.icon
	icon_panel.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.theme_type_variation = &"HudLabelShortcut"
	name_label.add_theme_font_size_override("font_size", 6)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text = item_data.display_name if item_data != null else item_id.replace("_", " ").capitalize()
	row.add_child(name_label)

	var quantity_label := Label.new()
	quantity_label.custom_minimum_size = Vector2(46, 18)
	quantity_label.theme_type_variation = &"HudLabelShortcut"
	quantity_label.add_theme_font_size_override("font_size", 6)
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	quantity_label.text = "%d / %d" % [held, required]
	row.add_child(quantity_label)


func _make_panel_16_texture() -> AtlasTexture:
	var panel_texture := AtlasTexture.new()
	panel_texture.atlas = PANEL_16_ATLAS
	panel_texture.region = Rect2(1, 1, 16, 16)
	return panel_texture


func _populate_worker_rows() -> void:
	_clear_children(worker_list)
	var options: Array = _get_worker_options()
	var valid_ids: Array[String] = []
	var options_by_id: Dictionary = {}
	for option_value in options:
		if option_value is Dictionary:
			var option: Dictionary = option_value
			var worker_id: String = str(option.get("id", ""))
			if not worker_id.is_empty():
				valid_ids.append(worker_id)
				options_by_id[worker_id] = option
	_selected_worker_ids = _keep_selected_workers(valid_ids)

	if _selected_worker_ids.is_empty():
		var empty_label := _make_label("Player assigned." if _get_phase() == "uncleared" and _use_player else "No workers selected.", 16)
		worker_list.add_child(empty_label)
		return

	for worker_id in _selected_worker_ids:
		var option: Dictionary = options_by_id.get(worker_id, {})
		_add_worker_row(bool(option.get("available", false)))


func _keep_selected_workers(valid_ids: Array[String]) -> Array[String]:
	var retained: Array[String] = []
	for worker_id in _selected_worker_ids:
		if valid_ids.has(worker_id):
			retained.append(worker_id)
	return retained


func _add_worker_row(available: bool) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 26)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	worker_list.add_child(row)

	var icon_panel := Button.new()
	icon_panel.custom_minimum_size = WORKER_CARD_SIZE
	icon_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_panel.theme_type_variation = &"WorkshopSquareButton24"
	icon_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_panel.focus_mode = Control.FOCUS_NONE
	row.add_child(icon_panel)

	var portrait_layer := Control.new()
	portrait_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_panel.add_child(portrait_layer)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = WORKER_PORTRAIT_SIZE
	portrait.position = Vector2(6, 4)
	portrait.size = WORKER_PORTRAIT_SIZE
	portrait.texture = WORKER_PORTRAIT_ICON
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not available:
		portrait.modulate = Color(0.55, 0.55, 0.55, 1.0)
	portrait_layer.add_child(portrait)


func _open_worker_assignment() -> void:
	if _is_closing or is_instance_valid(_worker_assignment_menu):
		return
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		show_error("Worker assignment is unavailable.")
		return

	var worker_options: Array[Dictionary] = []
	for option_value in _get_worker_options():
		if option_value is Dictionary:
			worker_options.append(option_value)

	_worker_assignment_menu = WORKER_ASSIGNMENT_UI.instantiate() as WorkshopWorkerAssignmentUI
	if _worker_assignment_menu == null:
		show_error("Worker assignment is unavailable.")
		return
	_worker_assignment_menu.layer = maxi(layer + 1, 11)
	_worker_assignment_menu.assignment_changed.connect(_on_worker_assignment_changed)
	_worker_assignment_menu.assignment_next_requested.connect(_on_worker_assignment_next_requested)
	_worker_assignment_menu.assignment_back_requested.connect(_on_worker_assignment_returned)
	_worker_assignment_menu.assignment_cancelled.connect(_on_worker_assignment_returned)
	current_scene.add_child(_worker_assignment_menu)
	_worker_assignment_menu.open_assignment(
		_selected_worker_ids,
		1 if _get_phase() == "uncleared" else maxi(worker_options.size(), 1),
		WorkerData.Profession.NONE,
		worker_options
	)


func _on_worker_assignment_changed(worker_ids: Array[String]) -> void:
	if _is_closing:
		return
	_selected_worker_ids = worker_ids.duplicate()
	if not worker_ids.is_empty():
		_use_player = false
	_status_override = ""
	_refresh_view()


func _on_worker_assignment_next_requested(worker_ids: Array[String]) -> void:
	_worker_assignment_menu = null
	if _is_closing:
		return
	get_tree().paused = true
	_selected_worker_ids = worker_ids.duplicate()
	if not worker_ids.is_empty():
		_use_player = false
	_status_override = ""
	_refresh_view()


func _on_worker_assignment_returned() -> void:
	_worker_assignment_menu = null
	if _is_closing:
		return
	get_tree().paused = true
	_status_override = ""
	_refresh_view()


func _refresh_preview() -> void:
	var preview: Dictionary = _get_preview()
	var duration: int = int(preview.get("duration_minutes", 0))
	var selected_count: int = _selected_worker_ids.size()
	if _get_phase() == "uncleared" and _use_player:
		duration_label.text = "%s, Player" % _format_duration(duration, false)
	elif selected_count == 0:
		duration_label.text = "-"
	else:
		var worker_word: String = "builder" if selected_count == 1 else "builders"
		duration_label.text = "%s, %d %s" % [
			_format_duration(duration, false),
			selected_count,
			worker_word
		]

	if _status_override.is_empty():
		status_label.text = str(preview.get("message", ""))
	else:
		status_label.text = _status_override
	_set_status_color(status_label.text)
	status_label.visible = not status_label.text.is_empty()
	build_button.disabled = not bool(preview.get("can_start", false))


func _set_status_color(message: String) -> void:
	if message.to_lower().contains("missing material"):
		status_label.add_theme_color_override("font_color", MISSING_MATERIAL_COLOR)
	else:
		status_label.remove_theme_color_override("font_color")


func _update_progress_page(phase: String, preview: Dictionary) -> void:
	var progress: float = clampf(float(preview.get("progress_ratio", 0.0)), 0.0, 1.0)
	var remaining: int = int(preview.get("remaining_minutes", 0))
	var worker_count: int = int(preview.get("worker_count", 0))
	progress_bar.value = progress * 100.0
	if phase in ["building", "clearing"]:
		progress_title.text = ("Clearing: %d%%" if phase == "clearing" else "Construction: %d%%") % roundi(progress * 100.0)
		remaining_label.text = "Remaining: %s" % _format_duration(remaining, true)
	else:
		progress_bar.value = 100.0
		progress_title.text = "Workshop construction complete"
		remaining_label.text = "Remaining: complete"
	team_label.text = "%d %s on the construction team" % [
		worker_count,
		"builder" if worker_count == 1 else "builders"
	]
	if phase == "clearing":
		team_label.text = "Player clearing the site" if _construction.clearing_by_player else "1 worker clearing the site"


func _format_duration(total_minutes: int, include_zero_units: bool) -> String:
	var remaining: int = maxi(total_minutes, 0)
	var days: int = int(remaining / 1440)
	remaining %= 1440
	var hours: int = int(remaining / 60)
	var minutes: int = remaining % 60
	var parts := PackedStringArray()
	if include_zero_units or days > 0:
		parts.append("%dd" % days)
	if include_zero_units or hours > 0:
		parts.append("%dh" % hours)
	if include_zero_units or minutes > 0:
		parts.append("%dm" % minutes)
	if parts.is_empty():
		parts.append("0m")
	return " ".join(parts)


func _focus_primary_control() -> void:
	if progress_page.visible:
		progress_close_button.grab_focus()
		return
	assign_workers_button.grab_focus()


func _make_label(label_text: String, height: int) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(0, height)
	label.theme_type_variation = &"HudLabelShortcut"
	label.add_theme_font_size_override("font_size", 6)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = label_text
	return label


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _on_build_pressed() -> void:
	if build_button.disabled:
		return
	if _get_phase() == "uncleared":
		clearing_requested.emit(_selected_worker_ids.duplicate(), _use_player)
		return
	if _get_phase() != "empty":
		return
	build_requested.emit(_selected_worker_ids.duplicate())
	if not _is_closing:
		_refresh_view()
