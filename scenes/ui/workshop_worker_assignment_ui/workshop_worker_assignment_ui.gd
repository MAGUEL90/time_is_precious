class_name WorkshopWorkerAssignmentUI extends CanvasLayer

signal assignment_changed(worker_ids: Array[String])
signal assignment_next_requested(worker_ids: Array[String])
signal assignment_back_requested()
signal assignment_cancelled()

const GAMEPLAY_THEME: Theme = preload(
	"res://resources/ui_gameplay_theme/ui_gameplay_theme.tres"
)
const PLUS_ICON: Texture2D = preload(
	"res://assets/ui/ui_icon/plus_icon.png"
)
const LOCK_ICON: Texture2D = preload(
	"res://assets/ui/ui_icon/lock_icon.png"
)
const WORKER_PORTRAIT_ICON: Texture2D = preload(
	"res://assets/ui/ui_icon/worker_portrait_icon.png"
)
const INFO_ICON: Texture2D = preload(
	"res://assets/ui/ui_icon/exclamation_mark_icon.png"
)

const MINIMUM_VISIBLE_SLOTS: int = 3
const SLOT_SIZE: Vector2 = Vector2(24, 24)

@onready var close_button: BaseButton = (
	$Root/Center/TextureWindow/Margin/MainVBox/Header/CloseButton
)
@onready var assigned_info_label: Label = (
	$Root/Center/TextureWindow/Margin/MainVBox/InfoRow/AssignedInfoLabel
)
@onready var total_workers_label: Label = (
	$Root/Center/TextureWindow/Margin/MainVBox/InfoRow/TotalWorkersLabel
)
@onready var overview_page: VBoxContainer = (
	$Root/Center/TextureWindow/Margin/MainVBox/OverviewPage
)
@onready var slot_grid: GridContainer = (
	$Root/Center/TextureWindow/Margin/MainVBox/OverviewPage/SlotCenter/SlotGrid
)
@onready var feedback_label: Label = (
	$Root/Center/TextureWindow/Margin/MainVBox/OverviewPage/FeedbackLabel
)
@onready var back_button: Button = (
	$Root/Center/TextureWindow/Margin/MainVBox/OverviewPage/Footer/BackButton
)
@onready var next_button: Button = (
	$Root/Center/TextureWindow/Margin/MainVBox/OverviewPage/Footer/NextButton
)
@onready var worker_selection_page: VBoxContainer = (
	$Root/Center/TextureWindow/Margin/MainVBox/WorkerSelectionPage
)
@onready var selection_title_label: Label = (
	$Root/Center/TextureWindow/Margin/MainVBox/WorkerSelectionPage/SelectionTitleLabel
)
@onready var worker_list: GridContainer = (
	$Root/Center/TextureWindow/Margin/MainVBox/WorkerSelectionPage/WorkerScroll/WorkerList
)
@onready var selection_back_button: Button = (
	$Root/Center/TextureWindow/Margin/MainVBox/WorkerSelectionPage/Footer/BackButton
)
@onready var worker_info_layer: Control = $Root/WorkerInfoLayer
@onready var worker_info_close_button: BaseButton = (
	$Root/WorkerInfoLayer/Center/InfoWindow/Margin/InfoVBox/Header/CloseButton
)
@onready var worker_info_name_label: Label = (
	$Root/WorkerInfoLayer/Center/InfoWindow/Margin/InfoVBox/Body/Details/NameLabel
)
@onready var worker_info_profession_label: Label = (
	$Root/WorkerInfoLayer/Center/InfoWindow/Margin/InfoVBox/Body/Details/ProfessionLabel
)
@onready var worker_info_status_label: Label = (
	$Root/WorkerInfoLayer/Center/InfoWindow/Margin/InfoVBox/Body/Details/StatusLabel
)

var selected_worker_ids: Array[String] = ["", ""]
var max_worker_slots: int = 2
var required_profession: WorkerData.Profession = WorkerData.Profession.NONE
var active_slot_index: int = 0


# Setup / Public API

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_cancel_pressed)
	back_button.pressed.connect(_on_back_pressed)
	next_button.pressed.connect(_on_next_pressed)
	selection_back_button.pressed.connect(_show_overview)
	worker_info_close_button.pressed.connect(_hide_worker_info)

func open_assignment(
	current_worker_ids: Array[String],
	slot_count: int = 2,
	job_profession: WorkerData.Profession = WorkerData.Profession.NONE
) -> void:
	required_profession = job_profession
	max_worker_slots = maxi(slot_count, 1)
	selected_worker_ids.clear()
	for slot_index in range(max_worker_slots):
		selected_worker_ids.append("")

	for worker_id in current_worker_ids:
		if worker_id.strip_edges().is_empty():
			continue
		if not WorkerDatabase.has_worker_data(worker_id):
			continue
		if WorkerDatabase.get_worker_data(worker_id).is_working():
			continue

		var empty_slot_index: int = _get_first_empty_slot_index()
		if empty_slot_index < 0:
			break
		selected_worker_ids[empty_slot_index] = worker_id

	var first_empty_slot: int = _get_first_empty_slot_index()
	active_slot_index = 0 if first_empty_slot < 0 else first_empty_slot
	feedback_label.text = "Choose an empty slot to assign a worker."
	worker_info_layer.hide()
	visible = true
	get_tree().paused = true
	_refresh_info_label()
	_refresh_slots()
	_refresh_next_state()
	_show_overview()


# Slot overview

func _show_overview() -> void:
	worker_info_layer.hide()
	worker_selection_page.hide()
	overview_page.show()
	_refresh_info_label()
	_refresh_slots()
	_refresh_next_state()

func _refresh_slots() -> void:
	for child in slot_grid.get_children():
		slot_grid.remove_child(child)
		child.queue_free()

	var visible_slot_count: int = maxi(
		max_worker_slots,
		MINIMUM_VISIBLE_SLOTS
	)
	for slot_index in range(visible_slot_count):
		if slot_index >= max_worker_slots:
			_add_locked_slot()
			continue

		var worker_id: String = selected_worker_ids[slot_index]
		if worker_id.is_empty():
			_add_empty_slot(slot_index)
		else:
			_add_worker_slot(slot_index, worker_id)

func _make_slot_button() -> Button:
	var slot_button := Button.new()
	slot_button.custom_minimum_size = SLOT_SIZE
	slot_button.focus_mode = Control.FOCUS_NONE
	slot_button.theme = GAMEPLAY_THEME
	slot_button.theme_type_variation = &"WorkshopSquareButton24"
	slot_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return slot_button

func _add_empty_slot(slot_index: int) -> void:
	var slot_button: Button = _make_slot_button()
	_add_centered_slot_content(
		slot_button,
		PLUS_ICON,
		Vector2(10, 10),
		""
	)
	slot_button.pressed.connect(_open_worker_selection.bind(slot_index))
	slot_grid.add_child(slot_button)

func _add_locked_slot() -> void:
	var slot_button: Button = _make_slot_button()
	slot_button.disabled = true
	_add_centered_slot_content(
		slot_button,
		LOCK_ICON,
		Vector2(9, 10),
		""
	)
	slot_grid.add_child(slot_button)

func _add_worker_slot(slot_index: int, worker_id: String) -> void:
	var slot_button: Button = _make_slot_button()
	_add_centered_slot_content(
		slot_button, WORKER_PORTRAIT_ICON, Vector2(11, 15), ""
	)
	slot_button.button_mask = MOUSE_BUTTON_MASK_RIGHT
	slot_button.pressed.connect(_remove_worker_from_slot.bind(slot_index))
	slot_grid.add_child(slot_button)

func _add_centered_slot_content(
	slot_button: Button,
	icon_texture: Texture2D,
	icon_size: Vector2,
	label_text: String,
	content_modulate: Color = Color.WHITE
) -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 3)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_right", 3)
	margin.add_theme_constant_override("margin_bottom", 3)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 1)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.modulate = content_modulate

	content.add_child(_make_icon_rect(icon_texture, icon_size))
	if not label_text.is_empty():
		var label := _make_worker_text_label(label_text)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(label)
	margin.add_child(content)
	slot_button.add_child(margin)

func _add_worker_slot_content(
	slot_button: Button,
	worker_id: String,
	worker_data: WorkerData
) -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_right", 7)
	margin.add_theme_constant_override("margin_bottom", 2)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 0)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE

	content.add_child(
		_make_icon_rect(WORKER_PORTRAIT_ICON, Vector2(11, 15))
	)
	margin.add_child(content)
	slot_button.add_child(margin)

	var info_button := Button.new()
	info_button.name = "InfoButton"
	info_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_button.offset_left = -7.0
	info_button.offset_top = 2.0
	info_button.offset_right = -1.0
	info_button.offset_bottom = 15.0
	info_button.custom_minimum_size = Vector2(6, 13)
	info_button.focus_mode = Control.FOCUS_NONE
	info_button.theme = GAMEPLAY_THEME
	info_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	info_button.icon = INFO_ICON
	info_button.expand_icon = false
	info_button.flat = true
	info_button.mouse_filter = Control.MOUSE_FILTER_STOP
	info_button.add_theme_color_override("icon_normal_color", Color.WHITE)
	info_button.add_theme_color_override("icon_hover_color", Color(1.4, 1.4, 1.2))
	info_button.add_theme_color_override("icon_pressed_color", Color(0.65, 0.65, 0.65))
	info_button.add_theme_color_override("icon_hover_pressed_color", Color(0.65, 0.65, 0.65))
	var empty_style := StyleBoxEmpty.new()
	for state_name in [
		"normal",
		"hover",
		"pressed",
		"hover_pressed",
		"disabled",
		"focus"
	]:
		info_button.add_theme_stylebox_override(state_name, empty_style)
	info_button.pressed.connect(
		_on_worker_info_pressed.bind(worker_id, worker_data)
	)
	slot_button.add_child(info_button)

func _make_icon_rect(
	icon_texture: Texture2D,
	icon_size: Vector2
) -> TextureRect:
	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = icon_size
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_rect.texture = icon_texture
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon_rect

func _open_worker_selection(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= selected_worker_ids.size():
		return
	if not selected_worker_ids[slot_index].is_empty():
		return

	active_slot_index = slot_index
	overview_page.hide()
	worker_selection_page.show()
	selection_title_label.text = "Choose Worker for Slot %d" % (
		slot_index + 1
	)
	_refresh_worker_list()

func _remove_worker_from_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= selected_worker_ids.size():
		return
	if selected_worker_ids[slot_index].is_empty():
		return

	selected_worker_ids[slot_index] = ""
	active_slot_index = slot_index
	feedback_label.text = "Worker unassigned."
	assignment_changed.emit(_get_selected_worker_ids())
	_show_overview()

func _on_worker_info_pressed(
	worker_id: String,
	worker_data: WorkerData
) -> void:
	if worker_data == null:
		feedback_label.text = "Worker information unavailable."
		return

	worker_info_name_label.text = "Name: %s" % worker_data.get_resolved_display_name()
	worker_info_profession_label.text = "Role: %s" % _get_worker_profession_name(
		worker_data.profession
	)
	worker_info_status_label.text = "Status: %s" % _get_worker_status_text(worker_data)
	worker_info_layer.show()

func _hide_worker_info() -> void:
	worker_info_layer.hide()

# Worker selection page

func _refresh_worker_list() -> void:
	for child in worker_list.get_children():
		worker_list.remove_child(child)
		child.queue_free()

	var worker_count: int = 0
	for worker in _get_workers_in_requirement_order():
		if not (worker is WorkerData):
			continue

		var worker_data: WorkerData = worker as WorkerData
		var worker_button: Button = _make_slot_button()
		_add_worker_slot_content(worker_button, worker_data.worker_id, worker_data)

		if selected_worker_ids.has(worker_data.worker_id):
			worker_button.disabled = true
		elif worker_data.is_working():
			worker_button.disabled = true
		else:
			worker_button.pressed.connect(
				_on_worker_selected.bind(worker_data.worker_id)
			)
		worker_list.add_child(worker_button)
		worker_count += 1

	if worker_count == 0:
		var empty_label := Label.new()
		empty_label.theme = GAMEPLAY_THEME
		empty_label.theme_type_variation = &"HudLabelShortcut"
		empty_label.add_theme_font_size_override("font_size", 6)
		empty_label.text = "No workers available."
		worker_list.add_child(empty_label)

func _get_workers_in_requirement_order() -> Array:
	var matching_workers: Array = []
	var other_workers: Array = []
	for worker in WorkerDatabase.get_all_workers():
		if not (worker is WorkerData):
			continue
		if required_profession != WorkerData.Profession.NONE and worker.profession == required_profession:
			matching_workers.append(worker)
		else:
			other_workers.append(worker)
	matching_workers.append_array(other_workers)
	return matching_workers

func _on_worker_selected(worker_id: String) -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
	if worker == null or worker.is_working():
		return
	if worker_id.strip_edges().is_empty():
		return
	if selected_worker_ids.has(worker_id):
		return
	if active_slot_index < 0 or active_slot_index >= selected_worker_ids.size():
		return
	if not selected_worker_ids[active_slot_index].is_empty():
		return

	selected_worker_ids[active_slot_index] = worker_id
	assignment_changed.emit(_get_selected_worker_ids())
	feedback_label.text = "Worker assigned."
	var next_empty_slot: int = _get_first_empty_slot_index()
	if next_empty_slot >= 0:
		active_slot_index = next_empty_slot
	_show_overview()

func _refresh_next_state() -> void:
	next_button.disabled = not _has_available_selected_worker()

func _has_available_selected_worker() -> bool:
	for worker_id in selected_worker_ids:
		var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
		if worker != null and not worker.is_working():
			return true
	return false


# Navigation callbacks

func _on_next_pressed() -> void:
	if not _has_available_selected_worker():
		_refresh_next_state()
		return
	var assigned_ids: Array[String] = _get_selected_worker_ids()
	visible = false
	get_tree().paused = false
	assignment_next_requested.emit(assigned_ids)
	queue_free()

func _on_cancel_pressed() -> void:
	_finish_close()

func _on_back_pressed() -> void:
	_finish_back()


# Display helpers

func _refresh_info_label() -> void:
	var total_workers: int = WorkerDatabase.get_all_workers().size()
	assigned_info_label.text = "Assigned: %d/%d" % [
		_get_assigned_worker_count(),
		max_worker_slots
	]
	total_workers_label.text = "Workers: %d" % total_workers

func _make_worker_text_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.custom_minimum_size = Vector2(0, 8)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme = GAMEPLAY_THEME
	label.theme_type_variation = &"HudLabelShortcut"
	label.add_theme_font_size_override("font_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
func _get_worker_status_text(worker_data: WorkerData) -> String:
	if worker_data.is_working():
		return "Working"
	return "Idle"

func _get_worker_profession_name(
	profession: WorkerData.Profession
) -> String:
	match profession:
		WorkerData.Profession.LABORER:
			return "Laborer"
		WorkerData.Profession.CRAFTER:
			return "Crafter"
		WorkerData.Profession.HAULER:
			return "Hauler"
		WorkerData.Profession.FARMER:
			return "Farmer"
		WorkerData.Profession.SCAVENGER:
			return "Scavenger"
		_:
			return "Unknown"

func _get_selected_worker_ids() -> Array[String]:
	var worker_ids: Array[String] = []
	for worker_id in selected_worker_ids:
		if not worker_id.is_empty():
			worker_ids.append(worker_id)
	return worker_ids

func _get_assigned_worker_count() -> int:
	var count: int = 0
	for worker_id in selected_worker_ids:
		if not worker_id.is_empty():
			count += 1
	return count

func _get_first_empty_slot_index() -> int:
	for slot_index in range(selected_worker_ids.size()):
		if selected_worker_ids[slot_index].is_empty():
			return slot_index
	return -1


# Exit helpers

func _finish_back() -> void:
	visible = false
	get_tree().paused = false
	assignment_back_requested.emit()
	queue_free()

func _finish_close() -> void:
	visible = false
	get_tree().paused = false
	assignment_cancelled.emit()
	queue_free()
