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
@onready var city_context_label: Label = $Root/Center/CityStorage/Margin/Content/ContextLabel
@onready var city_storage_list: GridContainer = $Root/Center/CityStorage/Margin/Content/BagGrid/Margin/MainVBox/Scroll/Grid
@onready var manage_window: NinePatchRect = $Root/ManageWindow
@onready var contract_window: NinePatchRect = $Root/ContractWindow
@onready var details_window: NinePatchRect = $Root/DetailsWindow
@onready var close_button: TextureButton = $Root/Center/Window/CloseButton
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
@onready var manage_contract_button: Button = $Root/ManageWindow/Margin/MainVBox/Actions/ContractButton
@onready var contract_current_label: Label = $Root/ContractWindow/Margin/MainVBox/CurrentContractLabel
@onready var contract_days_option: OptionButton = $Root/ContractWindow/Margin/MainVBox/ContractDays/DaysOption
@onready var renew_price_label: Label = $Root/ContractWindow/Margin/MainVBox/RenewPriceRow/RenewPriceLabel
@onready var renew_price_icon: TextureRect = $Root/ContractWindow/Margin/MainVBox/RenewPriceRow/ShekelIcon
@onready var contract_feedback_label: Label = $Root/ContractWindow/Margin/MainVBox/FeedbackLabel
@onready var contract_close_button: TextureButton = $Root/ContractWindow/CloseButton
@onready var manage_renew_button: Button = $Root/ContractWindow/Margin/MainVBox/ContractActions/RenewButton
@onready var details_header_label: Label = $Root/DetailsWindow/Margin/MainVBox/Header/TitleLabel
@onready var details_scroll: ScrollContainer = $Root/DetailsWindow/Margin/MainVBox/DetailsScroll
@onready var details_label: Label = $Root/DetailsWindow/Margin/MainVBox/DetailsScroll/DetailsLabel
@onready var details_close_button: TextureButton = $Root/DetailsWindow/CloseButton

const CONFIRM_SCENE: PackedScene = preload("res://scenes/ui/confirm_discard_panel/confirm_discard_panel.tscn")
const SEPARATOR_TEXTURE: Texture2D = preload("res://assets/ui/ui_icon/separator_icon_2.png")
const TOOL_CARD_SCENE: PackedScene = preload("res://scenes/test_scenes/ui_sandbox/worker_control/worker_tool_card.tscn")
const BASE_WORKER_VISUAL_SCENE: PackedScene = preload("res://scenes/worker_visual/base_worker_visual.tscn")
const WORKER_PORTRAIT_ICON: Texture2D = preload("res://assets/ui/ui_icon/worker_portrait_icon.png")
const STAR_ICON: Texture2D = preload("res://assets/ui/ui_icon/star_icon.png")
const HAMMER_ICON: Texture2D = preload("res://assets/items/stone_hammer.png")
const CONTRACT_ARROW_ICON: Texture2D = preload("res://assets/ui/ui_icon/right_arrow_icon.png")
const CONTRACT_CHECK_ICON: Texture2D = preload("res://assets/ui/ui_icon/checklist_icon.png")

const DEFAULT_FIRE_CONFIRMATION_TEXT: String = (
	"Fire this worker?\nTheir assignment will end.\nTools return to City Storage."
)

var _active_tab: String = "status"
var _selected_worker_id: String = ""
var _pending_remove_id: String = ""
var _pending_remove_row: Dictionary = {}
var _renew_feedback_text: String = ""
var _selected_contract_days: int = 3
var _displayed_contract_price: int = 0
var _renew_completed_for_selection: bool = false
var _renew_request_active: bool = false
var _manage_worker_id: String = ""
var _manage_source_button: Button
var _active_tool_slot: String = ""
var _tools_preview_visual: Node2D
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
var _needs_manager: Node
var _fire_hover_detector: Control
var _fire_block_feedback: Label
var _fire_block_reason: String = ""
var _fire_hover_pointer_inside: bool = false
var _fire_hover_ignore_until_exit: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	close_button.pressed.connect(close)
	city_storage_view.get_node("Margin/Content/Footer/Back").pressed.connect(_close_tools_picker)
	status_tab_button.pressed.connect(_show_status_tab)
	tools_tab_button.pressed.connect(_show_tools_tab)
	level_tab_button.pressed.connect(_show_level_tab)
	_build_confirmation()
	_build_fire_block_feedback()
	manage_fire_button.pressed.connect(_request_manage_fire)
	manage_goto_button.pressed.connect(_request_manage_goto)
	manage_details_button.pressed.connect(_show_manage_details)
	manage_contract_button.pressed.connect(_show_manage_contract)
	_configure_contract_days()
	contract_close_button.pressed.connect(_close_contract)
	manage_renew_button.pressed.connect(_request_manage_renew)
	details_close_button.pressed.connect(_close_details)
	_connect_needs_refresh_signal()
	tools_hands_button.pressed.connect(_show_hands_picker)
	city_storage_view.get_node("Close").pressed.connect(_close_tools_picker)
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
	contract_window.hide()
	details_window.hide()
	tools_picker_window.hide()
	_set_active_tab("status")


func _exit_tree() -> void:
	_disconnect_needs_refresh_signal()
	_restore_pause()


func _connect_needs_refresh_signal() -> void:
	_needs_manager = get_node_or_null("/root/CitizenNeedsManager")
	if not is_instance_valid(_needs_manager) or not _needs_manager.has_signal("needs_changed"):
		return
	if not _needs_manager.is_connected("needs_changed", _on_needs_changed):
		_needs_manager.connect("needs_changed", _on_needs_changed)


func _disconnect_needs_refresh_signal() -> void:
	if is_instance_valid(_needs_manager) and _needs_manager.has_signal("needs_changed") and _needs_manager.is_connected("needs_changed", _on_needs_changed):
		_needs_manager.disconnect("needs_changed", _on_needs_changed)
	_needs_manager = null


func _on_needs_changed(_day: Variant = null) -> void:
	if visible:
		refresh()


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
	if contract_window.visible and contract_days_option.get_popup().visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
			contract_days_option.get_popup().hide()
			contract_days_option.grab_focus()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("open_inventory") or event.is_action_pressed("open_work_progress") or event.is_action_pressed("show_player_status"):
			get_viewport().set_input_as_handled()
		return
	if manage_window.visible or contract_window.visible or details_window.visible:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var active_popup: Control = details_window if details_window.visible else contract_window if contract_window.visible else manage_window
			if not active_popup.get_global_rect().has_point(event.position):
				if contract_window.visible:
					_close_contract()
				else:
					_close_manage()
			return
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
			if contract_window.visible:
				_close_contract()
			else:
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
	_manage_worker_id = ""
	_close_manage()
	_close_tools_picker()
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
	_renew_feedback_text = ""
	_renew_completed_for_selection = false
	_renew_request_active = false
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
				_reposition_manage_after_layout()
			elif contract_window.visible:
				_update_contract_controls(managed_row)
				_reposition_contract_after_layout()
			elif details_window.visible:
				_render_details(managed_row)
				_position_popup(details_window, _manage_source_button)


func _reposition_manage_after_layout() -> void:
	# Refresh replaces the roster buttons; wait for their container geometry.
	await get_tree().process_frame
	if not visible or not manage_window.visible or _manage_worker_id.is_empty():
		return
	_manage_source_button = _find_manage_button(_manage_worker_id)
	_position_popup(manage_window, _manage_source_button)


func _reposition_contract_after_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not visible or not contract_window.visible or _manage_worker_id.is_empty():
		return
	_manage_source_button = _find_manage_button(_manage_worker_id)
	_position_popup(contract_window, _manage_source_button)


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
	if not tools_provider.is_valid():
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
	row_control.add_child(_make_star_rating(int(row.get("star", 0))))
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
	_clear_children(tools_unit_list)
	_clear_children(city_storage_list)
	var units: Array = _get_tool_rows(_selected_worker_id)
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
		_render_city_storage(units, true)
		return
	var worker_name := str(worker_row.get("name", "Unnamed worker"))
	tools_selected_label.text = worker_name
	var worker_locked := bool(worker_row.get("tools_locked", false))
	var lock_reason := str(worker_row.get("lock_reason", ""))
	tools_feedback_label.text = "Tools locked while working." if worker_locked else ""
	_render_tool_slots(worker_row, units)
	_refresh_tools_preview(worker_row)
	_render_city_storage(units, worker_locked)
	tools_picker_window.hide()


func _render_city_storage(units: Array, worker_locked: bool) -> void:
	if not city_storage_view.visible:
		return
	tools_picker_label.text = _active_tool_slot.capitalize()
	city_context_label.text = "%s / %s" % [tools_selected_label.text, _active_tool_slot.capitalize()]
	var category: int = city_storage_view.get_node("Margin/Content/Header/Categories").get_selected_category()
	var occupied := _has_equipped_tool_in_slot(units, _active_tool_slot)
	var equipment_category: bool = category == -1 or category == ItemEnums.ItemCategory.EQUIPMENT
	if equipment_category:
		for unit: Dictionary in units:
			_add_city_tool_cell(unit, worker_locked, occupied)
	var empty_message: String = ""
	if city_storage_list.get_child_count() == 0:
		empty_message = "No equipment in this category." if not equipment_category else "No equipment in City Storage."
	city_storage_view.get_node("Margin/Content/Feedback").text = empty_message
	for index in range(maxi(15 - city_storage_list.get_child_count(), 0)):
		var empty = preload("res://scenes/ui/item_slot/item_slot.tscn").instantiate()
		city_storage_list.add_child(empty)
		empty.set_empty()


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
		var contents := VBoxContainer.new()
		contents.add_theme_constant_override("separation", 2)
		card.add_child(contents)
		var heading := _make_label("%s\n%s" % [str(row.get("name", "Unnamed worker")), str(row.get("profession", ""))], 6)
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		contents.add_child(heading)
		var stats := HBoxContainer.new()
		stats.add_theme_constant_override("separation", 4)
		contents.add_child(stats)
		stats.add_child(_make_star_rating(int(row.get("star", 0))))
		stats.add_child(_make_label("XP: %d | Contributions: %d" % [int(row.get("xp", 0)), int(row.get("contributions", 0))], 6))
		level_list.add_child(card)


func _make_star_rating(stars: int) -> HBoxContainer:
	var rating := HBoxContainer.new()
	rating.name = "StarRating"
	rating.add_theme_constant_override("separation", 2)
	var icon := TextureRect.new()
	icon.texture = STAR_ICON
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.stretch_mode = TextureRect.STRETCH_KEEP
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rating.add_child(icon)
	var count := _make_label(str(stars), 6)
	count.name = "Count"
	rating.add_child(count)
	return rating


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
	if popup == manage_window or (popup == contract_window and popup.visible):
		popup_size = popup_size.max(popup.get_node("Margin").get_combined_minimum_size())
	if popup == contract_window:
		popup_size = popup_size.min(viewport_size - Vector2(4, 4))
	if popup == details_window:
		popup_size.x = clampf(popup_size.x, details_window.custom_minimum_size.x, viewport_size.x - 4.0)
		popup_size.y = clampf(popup_size.y, details_window.custom_minimum_size.y, viewport_size.y - 4.0)
	popup.size = popup_size
	var position := Vector2(
		maxf((viewport_size.x - popup_size.x) * 0.5, 2.0),
		maxf((viewport_size.y - popup_size.y) * 0.5, 2.0)
	)
	if popup != details_window and is_instance_valid(source_button):
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
	if popup == manage_window:
		_sync_fire_hover_detector()


func _show_manage(worker_id: String, source_button: Button = null) -> void:
	var row: Dictionary = _find_worker(_get_worker_rows(), worker_id)
	if row.is_empty():
		return
	_hide_fire_block_feedback()
	_renew_feedback_text = ""
	_manage_worker_id = worker_id
	_manage_source_button = source_button if is_instance_valid(source_button) else _find_manage_button(worker_id)
	_update_manage_controls(row)
	contract_window.hide()
	details_window.hide()
	manage_window.size = manage_window.get_combined_minimum_size()
	_position_popup(manage_window, _manage_source_button)
	manage_window.show()
	_position_popup.call_deferred(manage_window, _manage_source_button)
	_sync_fire_hover_detector()
	manage_fire_button.grab_focus()


func _update_manage_controls(row: Dictionary) -> void:
	_hide_fire_block_feedback(true)
	var working := bool(row.get("working", false))
	var can_fire := bool(row.get("can_fire", row.get("can_remove", false)))
	var fire_disabled: bool = working or not can_fire
	_fire_block_reason = _fire_feedback_for_row(row, fire_disabled)
	manage_fire_button.disabled = fire_disabled
	_sync_fire_hover_detector()
	manage_goto_button.disabled = not bool(row.get("can_goto", false))


func _configure_contract_days() -> void:
	contract_days_option.focus_previous = contract_days_option.get_path_to(contract_close_button)
	manage_renew_button.focus_previous = manage_renew_button.get_path_to(contract_days_option)
	manage_renew_button.focus_next = manage_renew_button.get_path_to(contract_close_button)
	contract_close_button.focus_next = contract_close_button.get_path_to(contract_days_option)
	var theme: Theme = $Root.theme
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		contract_days_option.add_theme_stylebox_override(state, theme.get_stylebox(state, "HudShortcutButton"))
	var popup_theme: Theme = theme.duplicate()
	popup_theme.default_font = theme.get_font("font", "HudShortcutButton")
	popup_theme.default_font_size = 6
	popup_theme.set_font("font", "PopupMenu", popup_theme.default_font)
	popup_theme.set_font_size("font_size", "PopupMenu", 6)
	popup_theme.set_color("font_color", "PopupMenu", theme.get_color("font_color", "HudShortcutButton"))
	popup_theme.set_color("font_hover_color", "PopupMenu", theme.get_color("font_hover_color", "HudShortcutButton"))
	popup_theme.set_stylebox("panel", "PopupMenu", theme.get_stylebox("normal", "HudShortcutButton"))
	popup_theme.set_stylebox("hover", "PopupMenu", theme.get_stylebox("hover", "HudShortcutButton"))
	popup_theme.set_constant("h_separation", "PopupMenu", 2)
	popup_theme.set_constant("v_separation", "PopupMenu", 2)
	var blank_check: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	blank_check.fill(Color.TRANSPARENT)
	popup_theme.set_icon("radio_checked", "PopupMenu", CONTRACT_CHECK_ICON)
	popup_theme.set_icon("radio_unchecked", "PopupMenu", ImageTexture.create_from_image(blank_check))
	contract_days_option.get_popup().theme = popup_theme
	var arrow: Image = CONTRACT_ARROW_ICON.get_image()
	arrow.rotate_90(CLOCKWISE)
	contract_days_option.add_theme_icon_override("arrow", ImageTexture.create_from_image(arrow))
	for days: int in WorkerDatabase.CONTRACT_DAYS:
		contract_days_option.add_item("%d days" % days, days)
	contract_days_option.item_selected.connect(_on_contract_day_index_selected)


func _on_contract_day_index_selected(index: int) -> void:
	_on_contract_days_selected(contract_days_option.get_item_id(index))


func _show_manage_contract() -> void:
	if _manage_worker_id.is_empty():
		return
	var row: Dictionary = _find_worker(_get_worker_rows(), _manage_worker_id)
	if row.is_empty():
		_close_manage()
		return
	_hide_fire_block_feedback()
	_selected_contract_days = WorkerDatabase.CONTRACT_DAYS[0] if not WorkerDatabase.CONTRACT_DAYS.is_empty() else 3
	_renew_feedback_text = ""
	_displayed_contract_price = 0
	_renew_completed_for_selection = false
	_renew_request_active = false
	_update_contract_day_selection()
	_update_contract_controls(row)
	manage_window.hide()
	details_window.hide()
	contract_window.size = contract_window.get_combined_minimum_size()
	_position_popup(contract_window, _manage_source_button)
	contract_window.show()
	_reposition_contract_after_layout()
	_sync_fire_hover_detector()
	contract_days_option.grab_focus()


func _update_contract_day_selection() -> void:
	var index: int = contract_days_option.get_item_index(_selected_contract_days)
	if index >= 0:
		contract_days_option.select(index)


func _on_contract_days_selected(days: int) -> void:
	if days not in WorkerDatabase.CONTRACT_DAYS or _manage_worker_id.is_empty():
		return
	if days != _selected_contract_days:
		_renew_completed_for_selection = false
		_renew_feedback_text = ""
	_selected_contract_days = days
	_update_contract_day_selection()
	var row: Dictionary = _find_worker(_get_worker_rows(), _manage_worker_id)
	if not row.is_empty():
		_update_contract_controls(row)


func _update_contract_controls(row: Dictionary) -> void:
	var price: int = _renewal_price(row, _selected_contract_days)
	_displayed_contract_price = price
	var worker: WorkerData = WorkerDatabase.get_worker_data(_manage_worker_id)
	contract_current_label.text = _current_contract_text(worker)
	renew_price_label.text = "Price: %d" % price if price > 0 else "Price unavailable"
	renew_price_icon.visible = price > 0
	contract_feedback_label.text = _renew_feedback_text
	contract_feedback_label.visible = not _renew_feedback_text.is_empty()
	manage_renew_button.disabled = price <= 0 or _renew_completed_for_selection or _renew_request_active
	var next_focus: Control = contract_close_button if manage_renew_button.disabled else manage_renew_button
	contract_days_option.focus_next = contract_days_option.get_path_to(next_focus)
	var previous_focus: Control = contract_days_option if manage_renew_button.disabled else manage_renew_button
	contract_close_button.focus_previous = contract_close_button.get_path_to(previous_focus)
	if contract_window.visible:
		_reposition_contract_after_layout()


func _current_contract_text(worker: WorkerData) -> String:
	if worker == null or worker.payroll_start_day < 0 or worker.payroll_paid_from_day < 0 \
			or worker.payroll_paid_until_day < worker.payroll_paid_from_day:
		return "Current contract ends:\n-"
	var end_minute: int = worker.get_paid_end_minute()
	var day: int = end_minute / 1440
	var minute_of_day: int = end_minute % 1440
	return "Current contract ends:\nDay %d, %02d:%02d" % [day, minute_of_day / 60, minute_of_day % 60]


func _renewal_price(row: Dictionary, days: int) -> int:
	var worker: WorkerData = WorkerDatabase.get_worker_data(_manage_worker_id)
	var profession: WorkerData.Profession = worker.profession if worker != null else _profession_from_row(row)
	return WorkerDatabase.get_contract_price(profession, days)


func _profession_from_row(row: Dictionary) -> WorkerData.Profession:
	match str(row.get("profession", "")).strip_edges().to_lower():
		"laborer":
			return WorkerData.Profession.LABORER
		"crafter":
			return WorkerData.Profession.CRAFTER
		"hauler":
			return WorkerData.Profession.HAULER
		"farmer":
			return WorkerData.Profession.FARMER
		"scavenger":
			return WorkerData.Profession.SCAVENGER
		_:
			return WorkerData.Profession.NONE


func _request_manage_renew() -> void:
	if not contract_window.visible or _manage_worker_id.is_empty() or _renew_request_active or _renew_completed_for_selection:
		return
	var row: Dictionary = _find_worker(_get_worker_rows(), _manage_worker_id)
	if row.is_empty():
		return
	var days: int = _selected_contract_days
	var price: int = _renewal_price(row, days)
	if price <= 0:
		_renew_feedback_text = "Contract price unavailable."
		_update_contract_controls(row)
		return
	if price != _displayed_contract_price:
		_renew_feedback_text = "Price updated; review and renew."
		_update_contract_controls(row)
		return
	_renew_request_active = true
	_update_contract_controls(row)
	var success: bool = WorkerDatabase.renew_contract(_manage_worker_id, days)
	_renew_request_active = false
	if success:
		_renew_completed_for_selection = true
		var worker: WorkerData = WorkerDatabase.get_worker_data(_manage_worker_id)
		_renew_feedback_text = "Renewed through Day %d." % worker.payroll_paid_until_day if worker != null else "Renewal paid."
	else:
		_renew_feedback_text = "Not enough funds." if not Inventory.has_item("shekel", price) else "Renewal failed; check contract."
	row = _find_worker(_get_worker_rows(), _manage_worker_id)
	if not row.is_empty():
		_update_contract_controls(row)


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
	_render_details(row, true)
	_hide_fire_block_feedback()
	manage_window.hide()
	contract_window.hide()
	_sync_fire_hover_detector()
	details_window.size = details_window.get_combined_minimum_size()
	_position_popup(details_window, _manage_source_button)
	details_window.show()
	details_close_button.grab_focus()


func _render_details(row: Dictionary, reset_scroll: bool = false) -> void:
	details_header_label.text = str(row.get("name", "Unnamed worker"))
	details_label.text = _format_details_text(row)
	var visuals: VBoxContainer = details_scroll.get_node("Visuals")
	visuals.get_node("Overview/Level").hide()
	var rating: HBoxContainer = visuals.get_node_or_null("Overview/StarRating")
	if rating == null:
		rating = _make_star_rating(0)
		visuals.get_node("Overview").add_child(rating)
		visuals.get_node("Overview").move_child(rating, 0)
	rating.get_node("Count").text = str(int(row.get("star", 0)))
	visuals.get_node("Overview/WageRow/Wage").text = str(row.get("wage", "")).replace(" Shekel", "")
	visuals.get_node("Location").text = "Location: %s" % str(row.get("location", ""))
	visuals.get_node("ProductiveDays").text = "Productive days: %d" % int(row.get("productive_days", 0))
	var needs_value: Variant = row.get("needs", {})
	var needs: Dictionary = needs_value if needs_value is Dictionary else {}
	var evaluated: bool = bool(needs.get("evaluated", false))
	visuals.get_node("NeedsHeading").text = "Daily needs"
	for need: String in ["Food", "Clothing", "Shelter"]:
		var card: VBoxContainer = visuals.get_node("Needs/" + need)
		var met: bool = bool(needs.get(need.to_lower(), false))
		var status: Label = card.get_node("Status")
		var check_icon: TextureRect = card.get_node_or_null("MetIcon")
		if check_icon == null:
			check_icon = TextureRect.new()
			check_icon.name = "MetIcon"
			var atlas := AtlasTexture.new()
			atlas.atlas = preload("res://assets/ui/ui_icon/icon_24.06.2026.png")
			atlas.region = Rect2(84, 68, 8, 8)
			check_icon.texture = atlas
			check_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			check_icon.custom_minimum_size = Vector2(8, 8)
			check_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			check_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(check_icon)
		status.visible = not (evaluated and met)
		check_icon.visible = evaluated and met
		status.text = ("Met" if met else "Missing") if evaluated else "-"
		status.modulate = (Color(0.7, 1.0, 0.6) if met else Color(1.0, 0.55, 0.45)) if evaluated else Color(0.85, 0.8, 0.65)
	for metric: String in ["Satisfaction", "Reliability"]:
		var key: String = metric.to_lower()
		var bar: TextureProgressBar = visuals.get_node(metric + "Bar")
		var label: Label = visuals.get_node(metric + "Label")
		bar.value = clampf(float(needs.get(key, 0.0)), 0.0, 1.0) * 100.0
		bar.tint_progress = Color(0.7, 1.0, 0.6) if key == "satisfaction" else Color(0.6, 0.85, 1.0)
		bar.visible = needs.has(key)
		label.text = ("%s: %d%%  %s" % [metric, roundi(bar.value), _format_daily_delta(needs.get(key + "_delta", 0.0)) if evaluated else ""]).strip_edges() if needs.has(key) else metric + ": -"
	if reset_scroll and is_instance_valid(details_scroll):
		details_scroll.scroll_vertical = 0


func _format_details_text(row: Dictionary) -> String:
	var lines: Array[String] = [
		"Level: %d" % int(row.get("star", 0)),
		"Wage: %s" % str(row.get("wage", "")),
		"Location: %s" % str(row.get("location", "")),
		"Productive days: %d" % int(row.get("productive_days", 0)),
	]
	var needs_value: Variant = row.get("needs", {})
	if not needs_value is Dictionary:
		lines.append("Daily needs: Not evaluated yet")
		lines.append("Satisfaction: Not evaluated yet")
		lines.append("Reliability: Not evaluated yet")
		return "\n".join(lines)

	var needs: Dictionary = needs_value
	if not bool(needs.get("evaluated", false)):
		lines.append("Daily needs: Not evaluated yet")
		lines.append(_format_current_metric("Satisfaction", needs, "satisfaction"))
		lines.append(_format_current_metric("Reliability", needs, "reliability"))
		return "\n".join(lines)

	var day: int = int(needs.get("day", -1))
	var day_text: String = "Day %d" % day if day >= 0 else "latest"
	lines.append("Daily needs (%s; last result):" % day_text)
	lines.append("Food: %s" % ("Met" if bool(needs.get("food", false)) else "Missing"))
	var clothing_text: String = "Met" if bool(needs.get("clothing", false)) else "Missing"
	var clothing_days_left: int = int(needs.get("clothing_days_left", -1))
	lines.append("Clothing: %s" % clothing_text)
	if clothing_days_left >= 0:
		lines.append("Clothing days remaining: %d" % clothing_days_left)
	lines.append("Shelter: %s" % ("Met" if bool(needs.get("shelter", false)) else "Missing"))
	var missing: Array = []
	var missing_value: Variant = needs.get("missing", [])
	if missing_value is Array:
		missing = missing_value
	var missing_names: PackedStringArray = []
	for missing_name: Variant in missing:
		missing_names.append(str(missing_name))
	if not missing_names.is_empty():
		lines.append("Reason: Missing %s." % ", ".join(missing_names))
	else:
		lines.append("Reason: All needs met.")
	lines.append("Satisfaction: %d%% (%s)" % [roundi(clampf(float(needs.get("satisfaction", 0.0)), 0.0, 1.0) * 100.0), _format_daily_delta(needs.get("satisfaction_delta", 0.0))])
	lines.append("Reliability: %d%% (%s)" % [roundi(clampf(float(needs.get("reliability", 0.0)), 0.0, 1.0) * 100.0), _format_daily_delta(needs.get("reliability_delta", 0.0))])
	return "\n".join(lines)


func _format_current_metric(label: String, summary: Dictionary, key: String) -> String:
	if not summary.has(key):
		return "%s: Not evaluated yet" % label
	return "%s: %d%% (current)" % [label, roundi(clampf(float(summary.get(key, 0.0)), 0.0, 1.0) * 100.0)]


func _format_daily_delta(value: Variant) -> String:
	var delta_percent: int = roundi(float(value) * 100.0)
	var sign: String = "+" if delta_percent >= 0 else ""
	return "%s%d%%" % [sign, delta_percent]


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
	_hide_fire_block_feedback()
	contract_days_option.get_popup().hide()
	details_window.hide()
	contract_window.hide()
	manage_window.hide()
	_sync_fire_hover_detector()
	_manage_source_button = null


func _close_contract() -> void:
	if not contract_window.visible:
		return
	contract_days_option.get_popup().hide()
	contract_window.hide()
	if _manage_worker_id.is_empty():
		_close_manage()
		return
	var row: Dictionary = _find_worker(_get_worker_rows(), _manage_worker_id)
	if row.is_empty():
		_close_manage()
		return
	_update_manage_controls(row)
	manage_window.size = manage_window.get_combined_minimum_size()
	_position_popup(manage_window, _manage_source_button)
	manage_window.show()
	_position_popup.call_deferred(manage_window, _manage_source_button)
	_sync_fire_hover_detector()
	manage_contract_button.grab_focus()


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
	_active_tool_slot = ""
	city_storage_view.hide()
	window.show()
	overlay.show()
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
	_hide_fire_block_feedback()
	_confirmation_overlay.show()
	_sync_fire_hover_detector()
	_confirm_no_button.grab_focus()


func _remove_confirmation_message(row: Dictionary) -> String:
	var payroll_warning: String = str(row.get("dismissal_payroll_warning", ""))
	return fire_confirmation_text + ("\n" + payroll_warning if not payroll_warning.is_empty() else "")


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
	panel.custom_minimum_size = Vector2(200, 96)
	_confirm_label = panel.get_node("ConfirmMargin/ConfirmVBox/ConfirmLabel")
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.add_theme_font_size_override("font_size", 6)
	_confirm_no_button = panel.get_node("ConfirmMargin/ConfirmVBox/ConfirmButtons/KeepButton")
	_confirm_yes_button = panel.get_node("ConfirmMargin/ConfirmVBox/ConfirmButtons/DiscardButton")
	_confirm_no_button.text = "No"
	_confirm_yes_button.text = "Yes"
	_confirm_no_button.pressed.connect(_cancel_remove_confirmation)
	_confirm_yes_button.pressed.connect(_confirm_pending_action)
	_confirmation_overlay.hide()


func _build_fire_block_feedback() -> void:
	_fire_hover_detector = Control.new()
	_fire_hover_detector.name = "FireHoverDetector"
	_fire_hover_detector.mouse_filter = Control.MOUSE_FILTER_STOP
	_fire_hover_detector.focus_mode = Control.FOCUS_NONE
	_fire_hover_detector.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_fire_hover_detector.z_index = 20
	_fire_hover_detector.hide()
	$Root.add_child(_fire_hover_detector)
	_fire_hover_detector.mouse_entered.connect(_on_fire_hover_entered)
	_fire_hover_detector.mouse_exited.connect(_on_fire_hover_exited)

	_fire_block_feedback = Label.new()
	_fire_block_feedback.name = "FireBlockFeedback"
	_fire_block_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fire_block_feedback.focus_mode = Control.FOCUS_NONE
	_fire_block_feedback.z_index = 21
	_fire_block_feedback.theme_type_variation = &"HudLabelShortcut"
	_fire_block_feedback.add_theme_font_size_override("font_size", 6)
	_fire_block_feedback.add_theme_color_override("font_color", tools_cart_required_label.get_theme_color("font_color"))
	_fire_block_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fire_block_feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fire_block_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fire_block_feedback.clip_text = false
	_fire_block_feedback.hide()
	$Root.add_child(_fire_block_feedback)


func _fire_feedback_for_row(row: Dictionary, disabled: bool) -> String:
	if not disabled:
		return ""
	var reason: String = str(row.get("fire_block_reason", "")).strip_edges()
	if not reason.is_empty():
		return reason
	if bool(row.get("working", false)):
		return "Working"
	return "Cannot fire"


func _hide_fire_block_feedback(wait_for_pointer_exit: bool = false) -> void:
	if is_instance_valid(_fire_block_feedback):
		_fire_block_feedback.hide()
	if not is_instance_valid(_fire_hover_detector):
		_fire_hover_pointer_inside = false
		_fire_hover_ignore_until_exit = false
		return
	if wait_for_pointer_exit and manage_window.visible:
		var fire_rect: Rect2 = manage_fire_button.get_global_rect()
		var pointer_inside: bool = _fire_hover_pointer_inside or fire_rect.has_point(get_viewport().get_mouse_position())
		_fire_hover_ignore_until_exit = pointer_inside
		_fire_hover_pointer_inside = pointer_inside
	else:
		_fire_hover_pointer_inside = false
		_fire_hover_ignore_until_exit = false


func _sync_fire_hover_detector() -> void:
	if not is_instance_valid(_fire_hover_detector):
		return
	var should_track: bool = manage_window.visible and not details_window.visible \
		and not (_confirmation_overlay != null and _confirmation_overlay.visible) \
		and manage_fire_button.disabled
	if not should_track:
		_fire_hover_detector.hide()
		_hide_fire_block_feedback()
		return
	var fire_rect: Rect2 = manage_fire_button.get_global_rect()
	_fire_hover_detector.position = fire_rect.position
	_fire_hover_detector.size = fire_rect.size
	_fire_hover_detector.show()


func _position_fire_block_feedback() -> void:
	if not is_instance_valid(_fire_block_feedback):
		return
	var popup_rect: Rect2 = manage_window.get_global_rect()
	var label_size := Vector2(maxf(popup_rect.size.x - 12.0, 0.0), 16.0)
	var fire_rect: Rect2 = manage_fire_button.get_global_rect()
	_fire_block_feedback.position = Vector2(
		popup_rect.position.x + 6.0,
		fire_rect.position.y - label_size.y - 1.0
	).round()
	_fire_block_feedback.size = label_size
	_fire_block_feedback.text = _fire_block_reason


func _on_fire_hover_entered() -> void:
	_fire_hover_pointer_inside = true
	if _fire_hover_ignore_until_exit or not manage_window.visible:
		return
	var row: Dictionary = _find_worker(_get_worker_rows(), _manage_worker_id)
	if row.is_empty():
		_close_manage()
		return
	var latest_working: bool = bool(row.get("working", false))
	var latest_can_fire: bool = bool(row.get("can_fire", row.get("can_remove", false)))
	var latest_disabled: bool = latest_working or not latest_can_fire
	var latest_reason: String = _fire_feedback_for_row(row, latest_disabled)
	if latest_disabled != manage_fire_button.disabled or latest_reason != _fire_block_reason:
		_update_manage_controls(row)
		return
	if not latest_disabled:
		_hide_fire_block_feedback()
		return
	_position_fire_block_feedback()
	_fire_block_feedback.show()


func _on_fire_hover_exited() -> void:
	_fire_hover_pointer_inside = false
	_fire_hover_ignore_until_exit = false
	if is_instance_valid(_fire_block_feedback):
		_fire_block_feedback.hide()


func _cancel_remove_confirmation() -> void:
	_pending_remove_id = ""
	_pending_remove_row.clear()
	if _confirmation_overlay != null:
		_confirmation_overlay.hide()
	_sync_fire_hover_detector()


func _confirm_pending_action() -> void:
	_confirm_remove()


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
		details_scroll,
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
