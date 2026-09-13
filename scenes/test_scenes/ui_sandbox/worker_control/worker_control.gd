class_name WorkerControlUI
extends CanvasLayer

## Scene-local Worker Hub presentation for the UI sandbox.
##
## Worker rules remain outside this scene. The root fixture supplies worker rows,
## tool rows, and the optional open gate, then handles the emitted requests.

signal equip_requested(worker_id: String, unit_id: String)
signal unequip_requested(worker_id: String, unit_id: String)
signal remove_requested(worker_id: String)
signal goto_requested(worker_id: String)
signal close_requested

var rows_provider: Callable = Callable()
var tools_provider: Callable = Callable()
var can_open: Callable = Callable()

@onready var overlay: Control = $Root/Overlay
@onready var window: NinePatchRect = $Root/Center/Window
@onready var city_storage_view: Control = $Root/Center/CityStorage
@onready var city_storage_list: GridContainer = $Root/Center/CityStorage/Margin/Content/BagGrid/Margin/MainVBox/Scroll/Grid
@onready var manage_window: NinePatchRect = $Root/ManageWindow
@onready var details_window: NinePatchRect = $Root/DetailsWindow
@onready var close_button: TextureButton = $Root/Center/Window/Margin/MainVBox/Header/CloseButton
@onready var status_tab_button: Button = $Root/Center/Window/Margin/MainVBox/Tabs/StatusTab
@onready var tools_tab_button: Button = $Root/Center/Window/Margin/MainVBox/Tabs/ToolsTab
@onready var level_tab_button: Button = $Root/Center/Window/Margin/MainVBox/Tabs/LevelTab
@onready var status_page: Control = $Root/Center/Window/Margin/MainVBox/PageStack/StatusPage
@onready var tools_page: Control = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage
@onready var level_page: Control = $Root/Center/Window/Margin/MainVBox/PageStack/LevelPage
@onready var status_list: VBoxContainer = $Root/Center/Window/Margin/MainVBox/PageStack/StatusPage/StatusScroll/StatusList
@onready var tools_worker_list: GridContainer = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage/ToolsBody/ToolsWorkerScroll/ToolsWorkerList
@onready var tools_unit_list: VBoxContainer = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage/ToolsBody/ToolsRightPane/ToolsPickerWindow/PickerMargin/PickerVBox/ToolsUnitScroll/ToolsUnitList
@onready var tools_selected_label: Label = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage/ToolsBody/ToolsRightPane/SelectedWorkerLabel
@onready var tools_feedback_label: Label = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage/ToolsBody/ToolsRightPane/FeedbackArea/ToolsFeedbackLabel
@onready var level_list: VBoxContainer = $Root/Center/Window/Margin/MainVBox/PageStack/LevelPage/LevelScroll/LevelList
@onready var feedback_label: Label = tools_feedback_label
@onready var tools_worker_scroll: ScrollContainer = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage/ToolsBody/ToolsWorkerScroll
@onready var tools_preview_anchor: Control = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage/ToolsBody/ToolsRightPane/PreviewRow/PreviewAnchor
@onready var tools_picker_window: PanelContainer = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage/ToolsBody/ToolsRightPane/ToolsPickerWindow
@onready var tools_picker_label: Label = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage/ToolsBody/ToolsRightPane/ToolsPickerWindow/PickerMargin/PickerVBox/PickerLabel
@onready var tools_hands_button: Button = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage/ToolsBody/ToolsRightPane/PreviewRow/RightSlots/HandsSlot
@onready var tools_feet_button: Button = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage/ToolsBody/ToolsRightPane/PreviewRow/RightSlots/FeetSlot
@onready var tools_accessory_button_1: Button = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage/ToolsBody/ToolsRightPane/PreviewRow/LeftSlots/BodySlot
@onready var tools_accessory_button_2: Button = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage/ToolsBody/ToolsRightPane/PreviewRow/RightSlots/AccessorySlot2
@onready var tools_cart_required_label: Label = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage/ToolsBody/ToolsRightPane/FeedbackArea/CartRequiredLabel
@onready var manage_fire_button: Button = $Root/ManageWindow/Margin/MainVBox/Actions/FireButton
@onready var manage_goto_button: Button = $Root/ManageWindow/Margin/MainVBox/Actions/GotoButton
@onready var manage_details_button: Button = $Root/ManageWindow/Margin/MainVBox/Actions/DetailsButton
@onready var details_header_label: Label = $Root/DetailsWindow/Margin/MainVBox/Header/TitleLabel
@onready var details_label: Label = $Root/DetailsWindow/Margin/MainVBox/DetailsLabel
@onready var details_close_button: TextureButton = $Root/DetailsWindow/Margin/MainVBox/Header/CloseButton

const CONFIRM_SCENE: PackedScene = preload("res://scenes/ui/confirm_discard_panel/confirm_discard_panel.tscn")
const SEPARATOR_TEXTURE: Texture2D = preload("res://assets/ui/ui_icon/separator_icon_2.png")
const TOOL_CARD_SCENE: PackedScene = preload("res://scenes/test_scenes/ui_sandbox/worker_control/worker_tool_card.tscn")
const BASE_WORKER_VISUAL_SCENE: PackedScene = preload("res://scenes/worker_visual/base_worker_visual.tscn")
const WORKER_PORTRAIT_ICON: Texture2D = preload("res://assets/ui/ui_icon/worker_portrait_icon.png")
const HAMMER_ICON: Texture2D = preload("res://assets/items/stone_hammer.png")

const DEFAULT_FIRE_CONFIRMATION_TEXT: String = (
	"Fire this worker?\nTheir assignment will end.\nTools return to City Storage."
)

var _active_tab: String = "status"
var _selected_worker_id: String = ""
var _pending_remove_id: String = ""
var _pending_remove_row: Dictionary = {}
var _manage_worker_id: String = ""
var _manage_source_button: Button
var _active_tool_slot: String = ""
var _tools_preview_visual: Node2D
var city_item_info: ItemInfoPanel
var city_action_panel: OptionPanel
@onready var tools_extra_accessory_button: Button = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage/ToolsBody/ToolsRightPane/PreviewRow/LeftSlots/AccessorySlot1
@onready var tools_tool_button: Button = $Root/Center/Window/Margin/MainVBox/PageStack/ToolsPage/ToolsBody/ToolsRightPane/PreviewRow/LeftSlots/ToolSlot
var _details_return_tab: String = "status"
var fire_confirmation_text: String = DEFAULT_FIRE_CONFIRMATION_TEXT
var _confirmation_overlay: Control
var _confirm_no_button: Button
var _confirm_yes_button: Button
var _confirm_label: Label
var _previous_tree_paused: bool = false
var _owns_pause: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	city_item_info = preload("res://scenes/ui/item_info_panel_root/item_info_panel.tscn").instantiate()
	$Root.add_child(city_item_info)
	visible = false
	close_button.pressed.connect(close)
	status_tab_button.pressed.connect(_show_status_tab)
	tools_tab_button.pressed.connect(_show_tools_tab)
	level_tab_button.pressed.connect(_show_level_tab)
	_build_confirmation()
	manage_fire_button.pressed.connect(_request_manage_fire)
	manage_goto_button.pressed.connect(_request_manage_goto)
	manage_details_button.pressed.connect(_show_manage_details)
	details_close_button.pressed.connect(_close_details)
	tools_hands_button.pressed.connect(_show_hands_picker)
	city_storage_view.get_node("Margin/Content/TitleRow/Close").pressed.connect(_close_tools_picker)
	city_storage_list.get_parent().vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tools_preview_anchor.resized.connect(_position_tools_preview)
	tools_picker_window.get_node("PickerMargin/PickerVBox/PickerBack").pressed.connect(_close_tools_picker)
	tools_feet_button.pressed.connect(_show_feet_picker)
	tools_tool_button.pressed.connect(_show_tool_picker.bind("tool"))
	tools_extra_accessory_button.pressed.connect(_show_tool_picker.bind("accessory_1"))
	tools_accessory_button_1.pressed.connect(_show_tool_picker.bind("body"))
	tools_accessory_button_2.pressed.connect(_show_tool_picker.bind("accessory"))
	city_storage_view.get_node("Margin/Content/Header/Categories").category_changed.connect(func(_category): _render_tools_units(_get_worker_rows()))
	_configure_scrollbars()
	manage_window.hide()
	details_window.hide()
	tools_picker_window.hide()
	_set_active_tab("status")


func _exit_tree() -> void:
	_restore_pause()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("open_worker_hub"):
		if visible:
			close()
		elif _can_open_now():
			open()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if is_instance_valid(city_action_panel):
		if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
			_close_city_action()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed and not city_action_panel.get_global_rect().has_point(event.position):
			_close_city_action()
	if _confirmation_overlay != null and _confirmation_overlay.visible:
		if event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
			if _confirm_no_button.has_focus():
				_confirm_yes_button.grab_focus()
			else:
				_confirm_no_button.grab_focus()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
			_cancel_remove_confirmation()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("open_inventory") or event.is_action_pressed("open_work_progress") or event.is_action_pressed("show_player_status"):
			get_viewport().set_input_as_handled()
		return
	if manage_window.visible or details_window.visible:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var active_popup: Control = details_window if details_window.visible else manage_window
			if not active_popup.get_global_rect().has_point(event.position):
				_close_manage()
			return
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
			_close_manage()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		if tools_picker_window.visible or city_storage_view.visible:
			_close_tools_picker()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_inventory") or event.is_action_pressed("open_work_progress") or event.is_action_pressed("show_player_status"):
		get_viewport().set_input_as_handled()


func open() -> void:
	if visible or not _can_open_now():
		return
	_previous_tree_paused = get_tree().paused
	_owns_pause = true
	get_tree().paused = true
	visible = true
	_pending_remove_id = ""
	_pending_remove_row.clear()
	if _selected_worker_id.is_empty():
		_selected_worker_id = _first_worker_id()
	refresh()
	_set_active_tab(_active_tab)
	if _active_tab == "status":
		status_tab_button.grab_focus()


func close() -> void:
	if not visible:
		return
	if _confirmation_overlay != null and _confirmation_overlay.visible:
		_cancel_remove_confirmation()
	_pending_remove_id = ""
	_pending_remove_row.clear()
	_manage_worker_id = ""
	_close_manage()
	_close_tools_picker()
	_restore_pause()
	visible = false
	close_requested.emit()


func refresh() -> void:
	"""Render provider data on demand; this UI intentionally has no frame poll."""
	var rows: Array = _get_worker_rows()
	if _selected_worker_id.is_empty() or not _has_worker(rows, _selected_worker_id):
		_selected_worker_id = str(rows[0].get("id", "")) if not rows.is_empty() else ""
	_render_status(rows)
	_render_tools_workers(rows)
	_render_tools_units(rows)
	_render_level(rows)
	_set_active_tab(_active_tab)
	if not _manage_worker_id.is_empty():
		var managed_row: Dictionary = _find_worker(rows, _manage_worker_id)
		if managed_row.is_empty():
			_close_manage()
		else:
			_manage_source_button = _find_manage_button(_manage_worker_id)
			_update_manage_controls(managed_row)
			if manage_window.visible:
				_position_popup(manage_window, _manage_source_button)
			elif details_window.visible:
				_position_popup(details_window, _manage_source_button)


func set_feedback(text: String) -> void:
	feedback_label.text = text
	city_storage_view.get_node("Margin/Content/Feedback").text = text
	_refresh_tools_feedback_visibility()


func _refresh_tools_feedback_visibility() -> void:
	# Both messages share one fixed footer; neither changes the equipment layout.
	tools_cart_required_label.visible = not tools_cart_required_label.text.is_empty()
	tools_feedback_label.visible = not tools_cart_required_label.visible


func _can_open_now() -> bool:
	if not can_open.is_valid():
		return true
	return bool(can_open.call())


func _get_worker_rows() -> Array:
	if not rows_provider.is_valid():
		return []
	var value: Variant = rows_provider.call()
	return value if value is Array else []


func _get_tool_rows(worker_id: String) -> Array:
	if worker_id.is_empty() or not tools_provider.is_valid():
		return []
	var value: Variant = tools_provider.call(worker_id)
	return value if value is Array else []


func _first_worker_id() -> String:
	var rows: Array = _get_worker_rows()
	return str(rows[0].get("id", "")) if not rows.is_empty() else ""


func _has_worker(rows: Array, worker_id: String) -> bool:
	for row: Dictionary in rows:
		if str(row.get("id", "")) == worker_id:
			return true
	return false


func _render_status(rows: Array) -> void:
	_clear_children(status_list)
	if rows.is_empty():
		status_list.add_child(_make_empty_label("No workers available."))
		return
	for row: Dictionary in rows:
		status_list.add_child(_make_status_row(row))


func _make_status_row(row: Dictionary) -> Control:
	var row_control := HBoxContainer.new()
	row_control.custom_minimum_size = Vector2(0, 18)
	row_control.add_theme_constant_override("separation", 2)
	row_control.alignment = BoxContainer.ALIGNMENT_CENTER

	var name_label := _make_label(str(row.get("name", "Unnamed worker")), 6)
	name_label.clip_text = false
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row_control.add_child(name_label)
	row_control.add_child(_make_separator())
	var role_label := _make_label(str(row.get("profession", "")), 6)
	role_label.clip_text = false
	role_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row_control.add_child(role_label)
	row_control.add_child(_make_separator())
	var activity_label := _make_label("Work" if bool(row.get("working", false)) else "Idle", 6)
	activity_label.clip_text = false
	activity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row_control.add_child(activity_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_control.add_child(spacer)
	var manage_button := _make_button("Manage", 42, 15)
	manage_button.name = "ManageButton"
	manage_button.set_meta("worker_id", str(row.get("id", "")))
	manage_button.pressed.connect(_show_manage.bind(str(row.get("id", "")), manage_button))
	row_control.add_child(manage_button)
	return row_control


func _make_separator() -> TextureRect:
	var separator := TextureRect.new()
	separator.custom_minimum_size = Vector2(4, 10)
	separator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	separator.texture = SEPARATOR_TEXTURE
	separator.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	separator.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return separator


func _render_tools_workers(rows: Array) -> void:
	_clear_children(tools_worker_list)
	if rows.is_empty():
		tools_worker_list.add_child(_make_empty_label("No workers available."))
		return
	for row: Dictionary in rows:
		var worker_id := str(row.get("id", ""))
		var card := TOOL_CARD_SCENE.instantiate() as WorkerToolCard
		if card == null:
			continue
		card.set_worker(row)
		card.set_meta("worker_id", worker_id)
		card.toggle_mode = true
		card.button_pressed = worker_id == _selected_worker_id
		card.pressed.connect(_select_worker_for_tools.bind(worker_id))
		card.details_requested.connect(_show_details.bind("tools"))
		tools_worker_list.add_child(card)
	for index in range(maxi(12 - rows.size(), 0)):
		var empty := TOOL_CARD_SCENE.instantiate() as WorkerToolCard
		tools_worker_list.add_child(empty)
		empty.disabled = true
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty.get_node("Portrait").hide()
		empty.details_button.hide()


func _render_tools_units(rows: Array) -> void:
	_close_city_action()
	city_item_info.clear_item()
	_clear_children(tools_unit_list)
	_clear_children(city_storage_list)
	var worker_row: Dictionary = _find_worker(rows, _selected_worker_id)
	if worker_row.is_empty():
		tools_selected_label.text = "Select a worker"
		tools_feedback_label.text = ""
		tools_cart_required_label.text = ""
		_refresh_tools_feedback_visibility()
		tools_picker_window.hide()
		_clear_tools_preview()
		tools_hands_button.disabled = true
		tools_feet_button.disabled = true
		return
	var worker_name := str(worker_row.get("name", "Unnamed worker"))
	tools_selected_label.text = worker_name
	var worker_locked := bool(worker_row.get("tools_locked", false))
	var lock_reason := str(worker_row.get("lock_reason", ""))
	tools_feedback_label.text = "Tools locked while working." if worker_locked else ""
	var units: Array = _get_tool_rows(_selected_worker_id)
	_render_tool_slots(worker_row, units)
	_refresh_tools_preview(worker_row)
	if _active_tool_slot.is_empty():
		tools_picker_window.hide()
		return
	tools_picker_label.text = _active_tool_slot.capitalize()
	var category: int = city_storage_view.get_node("Margin/Content/Header/Categories").get_selected_category()
	var occupied := _has_equipped_tool_in_slot(units, _active_tool_slot)
	for unit: Dictionary in units:
		if category == -1 or category == ItemEnums.ItemCategory.EQUIPMENT:
			_add_city_tool_cell(unit, worker_locked, occupied)
	for index in range(maxi(15 - city_storage_list.get_child_count(), 0)):
		var empty = preload("res://scenes/ui/item_slot/item_slot.tscn").instantiate()
		city_storage_list.add_child(empty)
		empty.set_empty()
	tools_picker_window.hide()

func _add_city_tool_cell(unit: Dictionary, worker_locked: bool, occupied: bool) -> void:
	var cell := VBoxContainer.new()
	city_storage_list.add_child(cell)
	var slot = preload("res://scenes/ui/item_slot/item_slot.tscn").instantiate()
	cell.add_child(slot)
	var unit_id := str(unit.get("unit_id", ""))
	var equipped := bool(unit.get("equipped", false))
	slot.set_item(str(unit.get("tool_id", "")), 1, _tool_icon(unit, preload("res://assets/ui/ui_icon/cart_icon.png")))
	# Storage owns allocation; suppress the player-inventory drag protocol.
	slot.interaction_locked = true
	slot.selected_qty.text = "E"
	slot.selected_qty.visible = equipped or not bool(unit.get("available", false))
	slot.set_meta("unit_id", unit_id)
	slot.disabled = str(unit.get("slot", "")) != _active_tool_slot or worker_locked or (equipped and not bool(unit.get("can_unequip", true))) or (not equipped and (occupied or not bool(unit.get("available", false))))
	slot.mouse_entered.connect(_show_city_item_info.bind(unit))
	slot.mouse_exited.connect(city_item_info.clear_item)
	slot.pressed.connect(_open_city_action.bind(unit, slot))


func _close_city_action() -> void:
	if is_instance_valid(city_action_panel):
		city_action_panel.hide()
		city_action_panel.queue_free()
	city_action_panel = null


func _open_city_action(unit: Dictionary, slot: Button) -> void:
	if slot.disabled or not city_storage_view.visible:
		return
	_close_city_action()
	city_item_info.clear_item()
	city_action_panel = preload("res://scenes/ui/option_panel/option_panel.tscn").instantiate()
	$Root.add_child(city_action_panel)
	city_action_panel.use_button.text = "Unequip" if bool(unit.get("equipped", false)) else "Equip"
	city_action_panel.send_button.get_parent().hide()
	city_action_panel.drop_button.text = "Cancel"
	city_action_panel.use_requested.connect(func():
		_close_city_action()
		if bool(unit.get("equipped", false)):
			_request_unequip(str(unit.unit_id))
		else:
			_request_equip(str(unit.unit_id))
	)
	city_action_panel.drop_requested.connect(_close_city_action)
	_position_city_action.call_deferred(slot.get_global_rect())


func _position_city_action(rect: Rect2) -> void:
	if not is_instance_valid(city_action_panel):
		return
	city_action_panel.reset_size()
	var bounds := get_viewport().get_visible_rect().size
	city_action_panel.global_position = Vector2(
		clampf(rect.end.x + 2, 4, maxf(4, bounds.x - city_action_panel.size.x - 4)),
		clampf(rect.position.y, 4, maxf(4, bounds.y - city_action_panel.size.y - 4))
	).round()


func _show_city_item_info(unit: Dictionary) -> void:
	if not city_storage_view.visible or is_instance_valid(city_action_panel):
		return
	if not city_item_info.display_item(str(unit.get("tool_id", ""))):
		# Scene-local tool units do not all have ItemDatabase entries yet.
		city_item_info.name_label.text = "name: %s" % unit.get("name", "Tool")
		city_item_info.category_label.text = "category: EQUIP"
		city_item_info.weight_label.text = "weight: -"
		city_item_info.description_label.text = "Worker hauling cart." if unit.get("tool_id") == "cart" else "-"
		city_item_info.effect_label.text = "effect: 3 items / trip" if unit.get("tool_id") == "cart" else "effect: -"
		city_item_info._refresh_size()
		city_item_info.show()
	city_item_info.category_label.text = "category: EQUIP (%s)" % str(unit.get("slot", "tool")).capitalize()
	var item_data: ItemData = ItemDatabase.get_item_data(str(unit.get("tool_id", "")))
	if item_data != null and bool(item_data.get_meta("weight_pending", false)):
		city_item_info.weight_label.text = "weight: -"
	city_item_info._refresh_size()
	var rect := city_storage_view.get_global_rect()
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := city_item_info.size
	city_item_info.global_position = Vector2(
		clampf(rect.end.x + 4, 4, maxf(4, viewport_size.x - panel_size.x - 4)),
		clampf(rect.position.y + (rect.size.y - panel_size.y) * 0.5, 4, maxf(4, viewport_size.y - panel_size.y - 4))
	).round()


func _make_tool_row(unit: Dictionary, worker_locked: bool, slot_occupied: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 20)
	row.add_theme_constant_override("separation", 2)
	var unit_id := str(unit.get("unit_id", ""))
	var unit_name := str(unit.get("name", "Unnamed tool"))
	var owner_name := str(unit.get("owner_name", ""))
	var equipped := bool(unit.get("equipped", false))
	var available := bool(unit.get("available", false))
	var can_unequip := bool(unit.get("can_unequip", true))
	var label_text := unit_name
	if not owner_name.is_empty():
		label_text += "\nOwner: %s" % owner_name
	if equipped:
		label_text += "\nEquipped"
	elif not available:
		label_text += "\nUnavailable"
	var label := _make_label(label_text, 6)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var action := _make_button("Unequip" if equipped else "Equip", 48, 16)
	action.set_meta("unit_id", unit_id)
	action.set_meta("slot", str(unit.get("slot", "")))
	action.disabled = worker_locked or (equipped and not can_unequip) or (not equipped and (not available or slot_occupied))
	if equipped:
		action.pressed.connect(_request_unequip.bind(unit_id))
	else:
		action.pressed.connect(_request_equip.bind(unit_id))
	row.add_child(action)
	return row


func _has_equipped_tool_in_slot(units: Array, slot: String) -> bool:
	for unit: Dictionary in units:
		if str(unit.get("slot", "")) == slot and bool(unit.get("equipped", false)):
			return true
	return false


func _render_tool_slots(worker_row: Dictionary, units: Array) -> void:
	var buttons: Dictionary = {"hands": tools_hands_button, "feet": tools_feet_button,
		"body": tools_accessory_button_1, "accessory": tools_accessory_button_2, "accessory_1": tools_extra_accessory_button, "tool": tools_tool_button}
	var has_cart := false
	for slot_id: String in buttons:
		var button: Button = buttons[slot_id]
		button.disabled = false
		button.icon = preload("res://assets/ui/ui_icon/plus_icon_3.png")
		for unit: Dictionary in units:
			if bool(unit.get("equipped", false)) and str(unit.get("slot", "")) == slot_id:
				button.icon = _tool_icon(unit, preload("res://assets/ui/ui_icon/cart_icon.png"))
				if unit.get("tool_id") == "cart":
					has_cart = true
	tools_cart_required_label.text = "Cart required" if str(worker_row.get("profession", "")).to_lower() == "hauler" and not has_cart else ""
	_refresh_tools_feedback_visibility()

func _tool_icon(unit: Dictionary, fallback: Texture2D) -> Texture2D:
	var item_data: ItemData = ItemDatabase.get_item_data(str(unit.get("tool_id", "")))
	if item_data != null and item_data.icon != null:
		return item_data.icon
	var icon_value: Variant = unit.get("icon", null)
	if icon_value is Texture2D:
		return icon_value
	if icon_value is String and not str(icon_value).is_empty():
		var loaded_icon: Variant = load(str(icon_value))
		if loaded_icon is Texture2D:
			return loaded_icon
	var tool_id := str(unit.get("tool_id", ""))
	if tool_id == "stone_hammer":
		return HAMMER_ICON
	return fallback


func _refresh_tools_preview(worker_row: Dictionary) -> void:
	_clear_tools_preview()
	var preview := BASE_WORKER_VISUAL_SCENE.instantiate() as Node2D
	if preview == null:
		return
	preview.name = "SelectedWorkerPreview"
	preview.set("idle_anim_speed", float(preview.get("idle_anim_speed")) / 3.0)
	preview.scale = Vector2(3, 3)
	tools_preview_anchor.add_child(preview)
	_tools_preview_visual = preview
	_position_tools_preview.call_deferred()
	var cart_equipped: bool = false
	for unit: Dictionary in _get_tool_rows(str(worker_row.get("id", ""))):
		if unit.get("equipped", false) and unit.get("tool_id", "") == "cart":
			cart_equipped = true
	preview.set_meta("cart_preview", cart_equipped)
	var profile_value: Variant = worker_row.get("visual_profile", {})
	var profile: Dictionary = profile_value if profile_value is Dictionary else {}
	preview.call(
		"play_visual",
		str(profile.get("skin_tone", "light")),
		"base",
		"idle_cart" if cart_equipped else "idle",
		"right",
		str(profile.get("accessory", "default")),
		str(profile.get("clothes_id", "default")),
		str(profile.get("hair_style", "default"))
	)


func _position_tools_preview() -> void:
	if is_instance_valid(_tools_preview_visual):
		_tools_preview_visual.position = Vector2(roundf(tools_preview_anchor.size.x / 2.0) - (12 if _tools_preview_visual.get_meta("cart_preview", false) else 0), roundf(tools_preview_anchor.size.y / 2.0) - 24)

func _clear_tools_preview() -> void:
	if is_instance_valid(_tools_preview_visual):
		_tools_preview_visual.queue_free()
		_tools_preview_visual = null


func _render_level(rows: Array) -> void:
	_clear_children(level_list)
	if rows.is_empty():
		level_list.add_child(_make_empty_label("No workers available."))
		return
	for row: Dictionary in rows:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var label := _make_label(
			"%s\n%s\nStar: %d | XP: %d | Contributions: %d"
			% [
				str(row.get("name", "Unnamed worker")),
				str(row.get("profession", "")),
				int(row.get("star", 0)),
				int(row.get("xp", 0)),
				int(row.get("contributions", 0))
			],
			6
		)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(label)
		level_list.add_child(card)


func _set_active_tab(tab: String) -> void:
	_active_tab = tab if tab in ["status", "tools", "level"] else "status"
	status_tab_button.set_pressed_no_signal(_active_tab == "status")
	tools_tab_button.set_pressed_no_signal(_active_tab == "tools")
	level_tab_button.set_pressed_no_signal(_active_tab == "level")
	status_page.visible = _active_tab == "status"
	tools_page.visible = _active_tab == "tools"
	level_page.visible = _active_tab == "level"
	if _active_tab != "tools":
		_close_tools_picker()
	_refresh_tools_feedback_visibility()


func _show_status_tab() -> void:
	_set_active_tab("status")


func _show_tools_tab() -> void:
	_set_active_tab("tools")


func _show_level_tab() -> void:
	_set_active_tab("level")


func _find_manage_button(worker_id: String) -> Button:
	for child: Node in status_list.get_children():
		var candidate := child.find_child("ManageButton", true, false) as Button
		if is_instance_valid(candidate) and str(candidate.get_meta("worker_id", "")) == worker_id:
			return candidate
	return null


func _position_popup(popup: Control, source_button: Button) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var popup_size: Vector2 = popup.get_combined_minimum_size()
	popup.size = popup_size
	var position := Vector2(
		maxf((viewport_size.x - popup_size.x) * 0.5, 2.0),
		maxf((viewport_size.y - popup_size.y) * 0.5, 2.0)
	)
	if is_instance_valid(source_button):
		var source_rect: Rect2 = source_button.get_global_rect()
		position = source_rect.position + Vector2(source_rect.size.x + 2.0, 0.0)
		if position.x + popup_size.x > viewport_size.x:
			position.x = source_rect.position.x - popup_size.x - 2.0
	var max_position := Vector2(
		maxf(viewport_size.x - popup_size.x - 2.0, 2.0),
		maxf(viewport_size.y - popup_size.y - 2.0, 2.0)
	)
	position.x = clampf(position.x, 2.0, max_position.x)
	position.y = clampf(position.y, 2.0, max_position.y)
	popup.position = position


func _show_manage(worker_id: String, source_button: Button = null) -> void:
	var row: Dictionary = _find_worker(_get_worker_rows(), worker_id)
	if row.is_empty():
		return
	_manage_worker_id = worker_id
	_manage_source_button = source_button if is_instance_valid(source_button) else _find_manage_button(worker_id)
	_update_manage_controls(row)
	details_window.hide()
	manage_window.size = manage_window.get_combined_minimum_size()
	_position_popup(manage_window, _manage_source_button)
	manage_window.show()
	_position_popup.call_deferred(manage_window, _manage_source_button)
	manage_fire_button.grab_focus()


func _update_manage_controls(row: Dictionary) -> void:
	var working := bool(row.get("working", false))
	var can_fire := bool(row.get("can_fire", row.get("can_remove", false)))
	manage_fire_button.disabled = working or not can_fire
	manage_goto_button.disabled = not bool(row.get("can_goto", false))


func _show_manage_details() -> void:
	_show_details(_manage_worker_id, "manage")


func _show_details(worker_id: String, return_tab: String = "") -> void:
	var row: Dictionary = _find_worker(_get_worker_rows(), worker_id)
	if row.is_empty():
		return
	_manage_worker_id = worker_id
	_details_return_tab = return_tab if return_tab in ["status", "tools", "level", "manage"] else _active_tab
	if _details_return_tab == "tools":
		_close_tools_picker()
	details_header_label.text = str(row.get("name", "Unnamed worker"))
	details_label.text = (
		"Level: %d\nWage: %s\nLocation: %s\nProductive days: %d"
		% [
			int(row.get("star", 0)),
			str(row.get("wage", "")),
			str(row.get("location", "")),
			int(row.get("productive_days", 0))
		]
	)
	manage_window.hide()
	details_window.size = details_window.get_combined_minimum_size()
	_position_popup(details_window, _manage_source_button)
	details_window.show()
	details_close_button.grab_focus()


func _close_details() -> void:
	if _manage_worker_id.is_empty():
		_close_manage()
		return
	if _details_return_tab == "manage":
		_show_manage(_manage_worker_id, _manage_source_button)
		return
	details_window.hide()
	_manage_source_button = null
	_manage_worker_id = ""
	_set_active_tab(_details_return_tab)


func _close_manage() -> void:
	details_window.hide()
	manage_window.hide()
	_manage_source_button = null


func _request_manage_fire() -> void:
	var row: Dictionary = _find_worker(_get_worker_rows(), _manage_worker_id)
	if row.is_empty() or manage_fire_button.disabled:
		return
	_request_remove(row)


func _request_manage_goto() -> void:
	if _manage_worker_id.is_empty() or manage_goto_button.disabled:
		return
	goto_requested.emit(_manage_worker_id)


func _select_worker_for_tools(worker_id: String) -> void:
	if worker_id.is_empty():
		return
	_selected_worker_id = worker_id
	var rows: Array = _get_worker_rows()
	_close_tools_picker()
	_render_tools_workers(rows)
	_render_tools_units(rows)
	_set_active_tab("tools")


func _show_hands_picker() -> void:
	_show_tool_picker("hands")


func _show_feet_picker() -> void:
	_show_tool_picker("feet")


func _show_tool_picker(slot: String) -> void:
	if _selected_worker_id.is_empty():
		return
	_active_tool_slot = slot
	window.hide()
	city_storage_view.show()
	city_storage_view.get_node("Margin/Content/Feedback").text = ""
	_render_tools_units(_get_worker_rows())

func _close_tools_picker() -> void:
	_close_city_action()
	city_item_info.clear_item()
	_active_tool_slot = ""
	city_storage_view.hide()
	window.show()
	_clear_children(city_storage_list)
	tools_preview_anchor.get_parent().show()
	if is_instance_valid(tools_picker_window):
		tools_picker_window.hide()
	if is_instance_valid(tools_unit_list):
		_clear_children(tools_unit_list)


func _request_equip(unit_id: String) -> void:
	if _selected_worker_id.is_empty() or unit_id.is_empty():
		return
	equip_requested.emit(_selected_worker_id, unit_id)


func _request_unequip(unit_id: String) -> void:
	if _selected_worker_id.is_empty() or unit_id.is_empty():
		return
	unequip_requested.emit(_selected_worker_id, unit_id)


func _request_remove(row: Dictionary) -> void:
	if _confirmation_overlay == null or _confirmation_overlay.visible:
		return
	var worker_id := str(row.get("id", ""))
	var working := bool(row.get("working", false))
	var can_fire := bool(row.get("can_fire", row.get("can_remove", false)))
	if worker_id.is_empty() or working or not can_fire:
		return
	_pending_remove_id = worker_id
	_pending_remove_row = row.duplicate()
	_confirm_label.text = _remove_confirmation_message(row)
	_confirmation_overlay.show()
	_confirm_no_button.grab_focus()


func _remove_confirmation_message(row: Dictionary) -> String:
	return fire_confirmation_text


func _build_confirmation() -> void:
	_confirmation_overlay = Control.new()
	_confirmation_overlay.name = "RemoveConfirmation"
	_confirmation_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirmation_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	$Root.add_child(_confirmation_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirmation_overlay.add_child(center)
	var panel: NinePatchRect = CONFIRM_SCENE.instantiate()
	center.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.custom_minimum_size = Vector2(180, 64)
	_confirm_label = panel.get_node("ConfirmMargin/ConfirmVBox/ConfirmLabel")
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.add_theme_font_size_override("font_size", 6)
	_confirm_no_button = panel.get_node("ConfirmMargin/ConfirmVBox/ConfirmButtons/KeepButton")
	_confirm_yes_button = panel.get_node("ConfirmMargin/ConfirmVBox/ConfirmButtons/DiscardButton")
	_confirm_no_button.text = "No"
	_confirm_yes_button.text = "Yes"
	_confirm_no_button.pressed.connect(_cancel_remove_confirmation)
	_confirm_yes_button.pressed.connect(_confirm_remove)
	_confirmation_overlay.hide()


func _cancel_remove_confirmation() -> void:
	_pending_remove_id = ""
	_pending_remove_row.clear()
	if _confirmation_overlay != null:
		_confirmation_overlay.hide()


func _confirm_remove() -> void:
	var worker_id := _pending_remove_id
	_cancel_remove_confirmation()
	if worker_id.is_empty():
		return
	remove_requested.emit(worker_id)


func _find_worker(rows: Array, worker_id: String) -> Dictionary:
	for row: Dictionary in rows:
		if str(row.get("id", "")) == worker_id:
			return row
	return {}


func _clear_children(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _configure_scrollbars() -> void:
	var scroll_containers: Array[ScrollContainer] = [
		status_list.get_parent() as ScrollContainer,
		tools_worker_list.get_parent() as ScrollContainer,
		tools_unit_list.get_parent() as ScrollContainer,
		level_list.get_parent() as ScrollContainer,
	]
	for scroll: ScrollContainer in scroll_containers:
		_narrow_scrollbar(scroll.get_v_scroll_bar(), true)
		_narrow_scrollbar(scroll.get_h_scroll_bar(), false)


func _narrow_scrollbar(scrollbar: ScrollBar, vertical: bool) -> void:
	if vertical:
		scrollbar.custom_minimum_size.x = 4.0
		scrollbar.add_theme_constant_override("scrollbar_width", 4)
		scrollbar.add_theme_constant_override("minimum_grabber_height", 4)
	else:
		scrollbar.custom_minimum_size.y = 4.0
		scrollbar.add_theme_constant_override("scrollbar_height", 4)
		scrollbar.add_theme_constant_override("minimum_grabber_width", 4)
	for style_name: String in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
		var existing_style: StyleBox = scrollbar.get_theme_stylebox(style_name)
		if existing_style == null:
			continue
		var local_style: StyleBox = existing_style.duplicate()
		if local_style is StyleBoxFlat:
			local_style.content_margin_left = 0.0
			local_style.content_margin_right = 0.0
			local_style.content_margin_top = 0.0
			local_style.content_margin_bottom = 0.0
		elif local_style is StyleBoxTexture:
			local_style.texture_margin_left = 0.0
			local_style.texture_margin_right = 0.0
			local_style.texture_margin_top = 0.0
			local_style.texture_margin_bottom = 0.0
		scrollbar.add_theme_stylebox_override(style_name, local_style)


func _make_empty_label(text: String) -> Label:
	var label := _make_label(text, 6)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HudLabelShortcut"
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _make_button(text: String, width: int, height: int) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = &"HudShortcutButton"
	button.add_theme_font_size_override("font_size", 6)
	if width > 0:
		button.custom_minimum_size.x = width
	if height > 0:
		button.custom_minimum_size.y = height
	return button


func _restore_pause() -> void:
	if _owns_pause:
		get_tree().paused = _previous_tree_paused
		_owns_pause = false
