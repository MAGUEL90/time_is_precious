class_name InventoryUI extends CanvasLayer

signal consume_item_success(item_id,
							item_display_name,
							item_fatigue_reduction,
							item_hunger_reduction,
							item_old_quantity,
							item_predict_new_quantity,
							player_position,
							slot_ref_global_rect)

const DEFAULT_SLOT_ICON: Texture2D = preload("res://assets/ui/default_icon.png")
const ITEM_ACTION_CONFIM_PANEL_SCENE: PackedScene = preload("res://scenes/ui/item_action_confirm_panel/item_action_confirm_panel.tscn")
const PICKUP_ITEM_SCENE: PackedScene = preload("res://scenes/pickup_item/pickup_item.tscn")
const CATEGORY_ALL: int = -1
const ITEMS_PER_PAGE: int = 16
const ITEM_INFO_PANEL_SIZE: Vector2 = Vector2(276, 88)
const ITEM_INFO_PANEL_WINDOW_OFFSET_Y: float = 124.0
const ITEM_INFO_PANEL_FIRST_ROW_OFFSET_Y: float = 82.0
const ITEM_INFO_PANEL_GAP: float = 8.0
const OPTION_PANEL_GAP: float = 4.0
const OPTION_PANEL_Y_OFFSET: float = -4.0
const ACTION_FEEDBACK_DURATION: float = 3.0
const INVENTORY_SCREEN_MARGIN: float = 8.0

@onready var inventory_container: Control = $Root/Center
@onready var inventory_window: Control = $Root/Center/Window
@onready var grid: GridContainer = $Root/Center/Window/Margin/MainVBox/Body/RightPanel/BagPanel/BagGrid/Margin/MainVBox/Scroll/Grid
@onready var worker_list: VBoxContainer = $Root/Center/Window/Margin/MainVBox/Body/RightPanel/WorkerPanel/MarginContainer/VBoxContainer/WorkerList
@onready var category_selector: InventoryCategorySelector = $Root/Center/Window/Margin/MainVBox/HeaderRow/InventoryCategorySelector
@onready var page_selector: InventoryPageSelector = $Root/Center/Window/Margin/MainVBox/InventoryPageSelector
@onready var item_info_panel: Control = $Root/ItemInfoPanelRoot
@onready var item_info_name_label: Label = $Root/ItemInfoPanelRoot/MarginContainer/LabelContainer/NameLabel
@onready var item_info_category_label: Label = $Root/ItemInfoPanelRoot/MarginContainer/LabelContainer/CategoryWeightContainer/CategoryLabel
@onready var item_info_weight_label: Label = $Root/ItemInfoPanelRoot/MarginContainer/LabelContainer/CategoryWeightContainer/WeightLabel
@onready var item_info_description_label: Label = $Root/ItemInfoPanelRoot/MarginContainer/LabelContainer/DescriptionLabel
@onready var close_button: Button = $Root/Center/Window/Margin/MainVBox/HeaderRow/HeaderRightActions/MarginContainer/CloseButton
@onready var action_feedback_label: Label = $Root/Center/Window/Margin/MainVBox/ActionFeedbackLabel

var player_ref: Player
var current_category: int = CATEGORY_ALL
var current_page: int = 0
var active_option_item_id: String
var active_option_slot: ItemSlot
var active_option_panel: OptionPanel
var active_action_confirm_panel: ItemActionConfirmPanel
var action_feedback_token: int = 0
var is_inventory_action_busy: bool = false
var active_drag_data: Dictionary = {}

# Setup / Lifecycle

func _ready() -> void:
	player_ref = get_tree().get_first_node_in_group("player")

	visible = false
	item_info_panel.custom_minimum_size = ITEM_INFO_PANEL_SIZE
	item_info_panel.size = ITEM_INFO_PANEL_SIZE
	item_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_info_panel.visible = false
	action_feedback_label.modulate.a = 0.0

	if Inventory != null and Inventory.has_signal("items_changed") and not Inventory.items_changed.is_connected(_on_inventory_items_changed):
		Inventory.items_changed.connect(_on_inventory_items_changed)

	category_selector.category_changed.connect(_on_category_changed)
	page_selector.page_changed.connect(_on_page_changed)
	close_button.pressed.connect(close_inventory)
	current_category = category_selector.get_selected_category()
	_refresh_inventory_grid()

func _exit_tree() -> void:
	if Inventory != null and Inventory.has_signal("items_changed") and Inventory.items_changed.is_connected(_on_inventory_items_changed):
		Inventory.items_changed.disconnect(_on_inventory_items_changed)

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if active_action_confirm_panel != null and is_instance_valid(active_action_confirm_panel):
				_close_item_action_confirm_panel()
				get_viewport().set_input_as_handled()
			elif active_option_panel != null and is_instance_valid(active_option_panel):
				_close_option_panel()
				get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_inventory"):
		_clear_inventory_feedback()
		toggle_inventory()

	elif visible and event.is_action_pressed("ui_cancel"):
		close_inventory()

func _on_inventory_items_changed() -> void:
	_refresh_inventory_grid()

# Inventory visibility

func toggle_inventory() -> void:
	if visible:
		close_inventory()
	else:
		open_inventory()

func open_inventory() -> void:
	get_tree().paused = true
	visible = true
	_position_inventory_near_player()
	_refresh_player_status()
	_refresh_inventory_grid()
	_refresh_worker_list()
	call_deferred("_position_item_info_panel")

func _position_inventory_near_player() -> void:
	if player_ref == null or inventory_container == null:
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var player_screen_position: Vector2 = get_viewport().get_canvas_transform() * player_ref.global_position
	var inventory_size: Vector2 = inventory_container.size * inventory_container.scale
	var target_x: float = INVENTORY_SCREEN_MARGIN

	if player_screen_position.x < viewport_size.x * 0.5:
		target_x = viewport_size.x - inventory_size.x - INVENTORY_SCREEN_MARGIN

	var target_y: float = (viewport_size.y - inventory_size.y) * 0.5

	target_x = clampf(target_x, INVENTORY_SCREEN_MARGIN, viewport_size.x - inventory_size.x - INVENTORY_SCREEN_MARGIN)
	target_y = clampf(target_y, INVENTORY_SCREEN_MARGIN, viewport_size.y - inventory_size.y - INVENTORY_SCREEN_MARGIN)

	inventory_container.global_position = Vector2(target_x, target_y)

func close_inventory() -> void:
	_close_inventory_floating_panels()

	get_tree().paused = false
	item_info_panel.visible = false
	visible = false

# Grid refresh

func _refresh_inventory_grid():
	var filtered_items: Array[String] = []

	if grid == null:
		return

	_close_inventory_floating_panels()
	item_info_panel.visible = false

	for child in grid.get_children():
		child.queue_free()

	var all_items: Dictionary = Inventory.items

	for item_id: String in all_items.keys():
		var qty: int = int(all_items[item_id])
		if qty <= 0:
			continue

		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		if item_data == null:
			continue

		if current_category != CATEGORY_ALL and item_data.category != current_category:
			continue

		filtered_items.append(item_id)

	var total_pages: int = maxi(ceil(float(filtered_items.size()) / ITEMS_PER_PAGE), 1)
	current_page = clampi(current_page, 0, total_pages - 1)
	page_selector.set_page_data(current_page, total_pages)

	var start_index: int = current_page * ITEMS_PER_PAGE
	var end_index: int = mini(start_index + ITEMS_PER_PAGE, filtered_items.size())

	for i in range(start_index, end_index):
		var item_id: String = filtered_items[i]
		var qty: int = int(all_items[item_id])

		var slot_scene: PackedScene = preload("res://scenes/ui/item_slot/item_slot.tscn")
		var slot: Node = slot_scene.instantiate()
		grid.add_child(slot)

		if slot.has_method("set_item"):
			slot.call("set_item", item_id, qty, _get_item_icon(item_id))

		if slot.has_signal("slot_clicked"):
			slot.slot_clicked.connect(_on_item_slot_clicked)

		if slot.has_signal("slot_deposit_requested"):
			slot.slot_deposit_requested.connect(_on_slot_deposit_requested)

		if slot.has_signal("slot_hovered"):
			slot.slot_hovered.connect(_on_item_slot_hovered)

		if slot.has_signal("slot_unhovered"):
			slot.slot_unhovered.connect(_on_item_slot_unhovered)

		if slot.has_signal("slot_drag_started"):
			slot.slot_drag_started.connect(_on_slot_drag_started)

func _get_item_icon(item_id: String) -> Texture2D:
	if ItemDatabase != null:
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		if item_data and item_data.icon:
			return item_data.icon
		return DEFAULT_SLOT_ICON
	return DEFAULT_SLOT_ICON

# Slot selection

func _on_item_slot_clicked(item_id: String, _quantity: int, slot_ref: ItemSlot) -> void:
	if is_inventory_action_busy:
		return

	if active_action_confirm_panel != null and is_instance_valid(active_action_confirm_panel):
		return

	if active_option_panel != null and is_instance_valid(active_option_panel):
		active_option_panel.queue_free()
		active_option_panel = null

	_close_option_panel()

	var option_panel_path: PackedScene = preload("res://scenes/ui/option_panel/option_panel.tscn")
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)

	active_option_panel = option_panel_path.instantiate()
	active_option_panel.use_requested.connect(_on_option_use_requested)
	active_option_panel.send_requested.connect(_on_option_send_requested)
	active_option_panel.drop_requested.connect(_on_option_drop_requested)

	_set_slots_hover_locked(true)
	add_child(active_option_panel)

	active_option_panel.set_actions_enabled(
		_can_use_item(item_data),
		_can_send_item(item_data),
		Inventory.has_item(item_id, 1)
	)

	active_option_slot = slot_ref
	active_option_item_id = item_id
	active_option_slot.set_selected(true)

	_show_item_info(item_id, slot_ref)
	_position_option_panel_near_slot(slot_ref)

# Option callbacks

func _on_option_use_requested() -> void:
	_open_item_action_confirm_panel("use")

func _on_option_send_requested() -> void:
	_open_item_action_confirm_panel("send")

func _on_option_drop_requested() -> void:
	_open_item_action_confirm_panel("drop")

# Slot hover

func _on_item_slot_hovered(item_id: String, _quantity: int, slot_ref: ItemSlot) -> void:
	if is_inventory_action_busy:
		return

	if active_action_confirm_panel != null and is_instance_valid(active_action_confirm_panel):
		return

	if active_option_panel != null and is_instance_valid(active_option_panel):
		return

	_show_item_info(item_id, slot_ref)

func _on_item_slot_unhovered(_slot_ref: ItemSlot) -> void:
	if active_option_panel != null and is_instance_valid(active_option_panel):
		return

	item_info_panel.visible = false

func _on_slot_drag_started(data: Dictionary) -> void:
	active_drag_data = data

# Drag drop flow

func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END:
		return

	if active_drag_data.is_empty():
		return

	var slot_ref: ItemSlot = active_drag_data.get("slot_ref", null) as ItemSlot
	if slot_ref != null and is_instance_valid(slot_ref):
		slot_ref.set_drag_source_active(false)

	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	var dropped_inside_inventory: bool = inventory_window.get_global_rect().has_point(mouse_position)

	if not dropped_inside_inventory:
		_open_drag_drop_confirm_panel(active_drag_data)

	active_drag_data.clear()

func _open_drag_drop_confirm_panel(data: Dictionary) -> void:
	var item_id: String = str(data.get("item_id", ""))
	if item_id.is_empty():
		return

	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if item_data == null:
		return

	var item_quantity: int = int(Inventory.items.get(item_id, 0))
	if item_quantity <= 0:
		return

	_close_inventory_floating_panels()
	active_option_item_id = item_id
	active_option_slot = data.get("slot_ref", null) as ItemSlot

	active_action_confirm_panel = ITEM_ACTION_CONFIM_PANEL_SCENE.instantiate()
	active_action_confirm_panel.confirmed.connect(_on_item_action_confirmed)
	active_action_confirm_panel.canceled.connect(_close_item_action_confirm_panel)
	add_child(active_action_confirm_panel)

	active_action_confirm_panel.setup("drop", item_id, item_data, item_quantity)

	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	active_action_confirm_panel.global_position = mouse_position.round()
	_set_slots_interaction_locked(true)

# Item info default position

func _position_item_info_panel() -> void:
	if inventory_window == null or item_info_panel == null:
		return

	item_info_panel.custom_minimum_size = ITEM_INFO_PANEL_SIZE
	item_info_panel.size = ITEM_INFO_PANEL_SIZE

	var window_rect: Rect2 = inventory_window.get_global_rect()
	var panel_position: Vector2 = Vector2(
		window_rect.position.x + (window_rect.size.x - ITEM_INFO_PANEL_SIZE.x) * 0.5,
		window_rect.position.y + ITEM_INFO_PANEL_WINDOW_OFFSET_Y
	)
	item_info_panel.global_position = panel_position.round()

# Slot direct deposit

func _on_slot_deposit_requested(item_id: String, _quantity: int, _slot_ref: ItemSlot) -> void:
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if item_data == null:
		return

	if item_data.food_supply_value <= 0 and item_data.clothing_supply_value <= 0:
		return

	if item_data.food_supply_value > 0:
		if CityStockManager.deposit_food_item(item_id, 1, Inventory):
			_refresh_inventory_grid()

	if item_data.clothing_supply_value > 0:
		if CityStockManager.deposit_clothing_item(item_id, 1, Inventory):
			_refresh_inventory_grid()

# Player / worker preview

func _refresh_player_status() -> void:
	if player_ref == null:
		return

func _refresh_worker_list() -> void:
	var workers: Array = WorkerDatabase.get_all_workers()
	for child in worker_list.get_children():
		child.queue_free()

	for worker in workers:
		if not (worker is WorkerData):
			continue
		var worker_data: WorkerData = worker as WorkerData
		var label: Label = Label.new()
		label.text = "%s - %s: %s★\nStatus: %s\nSAT %d%% | REL %d%%\nNeeds F: %s C: %s S: %s\n" % [
			worker_data.display_name,_get_worker_profession_name(worker_data.profession), worker_data.profession_star,
			_get_worker_work_status_text(worker_data),
			roundi(worker_data.satisfaction * 100.0), roundi(worker_data.reliability * 100.0),
			_get_need_text(worker_data.food_fulfilled), _get_need_text(worker_data.clothing_fulfilled), _get_need_text(worker_data.shelter_fulfilled)
		]
		worker_list.add_child(label)

func _get_worker_profession_name(profession: WorkerData.Profession) -> String:
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

func _get_worker_work_status_text(worker_data: WorkerData) -> String:
	if worker_data.current_work_status == WorkerData.WorkStatus.WORKING:
		if worker_data.current_job_id.is_empty():
			return "Working"
		else:
			return "Working - " + worker_data.current_job_id
	else:
		return "Idle"

func _get_need_text(is_fulfilled: bool) -> String:
	return "OK" if is_fulfilled else "NO"

# Display helpers

func _get_item_category_text(category: ItemEnums.ItemCategory) -> String:
	match category:
		ItemEnums.ItemCategory.RESOURCE:
			return "RESOURCE"
		ItemEnums.ItemCategory.CONSUMABLE:
			return "FOOD"
		ItemEnums.ItemCategory.EQUIPMENT:
			return "EQUIP"
		ItemEnums.ItemCategory.PLACEABLE:
			return "Build"
		ItemEnums.ItemCategory.KEY_ITEM:
			return "QUEST"
		_:
			return "UNKNOWN"

# Category / page callbacks

func _on_category_changed(category: int) -> void:
	current_category = category
	current_page = 0
	_refresh_inventory_grid()

func _on_page_changed(page: int) -> void:
	current_page = page
	_refresh_inventory_grid()

# Option panel flow

func _close_option_panel() -> void:
	if active_option_panel != null and is_instance_valid(active_option_panel):
		active_option_panel.queue_free()
	active_option_panel = null

	_clear_active_option_slot()
	_set_slots_hover_locked(false)
	_set_slots_interaction_locked(false)
	item_info_panel.visible = false

func _position_option_panel_near_slot(slot_ref: ItemSlot) -> void:
	if active_option_panel == null or not is_instance_valid(active_option_panel):
		return

	var slot_rect: Rect2 = slot_ref.get_global_rect()
	var window_rect: Rect2 = inventory_window.get_global_rect()
	var panel_size: Vector2 = active_option_panel.get_combined_minimum_size() * active_option_panel.scale

	var min_x: float = window_rect.position.x + OPTION_PANEL_GAP
	var min_y: float = window_rect.position.y + OPTION_PANEL_GAP
	var max_x: float = window_rect.position.x + window_rect.size.x - panel_size.x - OPTION_PANEL_GAP
	var max_y: float = window_rect.position.y + window_rect.size.y - panel_size.y - OPTION_PANEL_GAP

	max_x = max(max_x, min_x)
	max_y = max(max_y, min_y)

	var panel_position: Vector2 = Vector2(
		slot_rect.position.x + slot_rect.size.x + OPTION_PANEL_GAP,
		slot_rect.position.y + (slot_rect.size.y - panel_size.y) * 0.5 + OPTION_PANEL_Y_OFFSET
	)

	if panel_position.x > max_x:
		panel_position.x = slot_rect.position.x - panel_size.x - OPTION_PANEL_GAP

	panel_position.x = clampf(panel_position.x, min_x, max_x)
	panel_position.y = clampf(panel_position.y, min_y, max_y)

	active_option_panel.global_position = panel_position.round()
	_set_slots_interaction_locked(true, active_option_slot)

func _clear_active_option_slot() -> void:
	if active_option_slot != null and is_instance_valid(active_option_slot):
		active_option_slot.set_selected(false)

	active_option_slot = null
	active_option_item_id = ""

# Item info panel

func _show_item_info(item_id: String, slot_ref: ItemSlot = null) -> void:
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if item_data == null:
		return

	item_info_name_label.text = item_data.display_name
	item_info_category_label.text = "category: %s" % _get_item_category_text(item_data.category)
	item_info_weight_label.text = "weight: %.2f" % item_data.weight
	item_info_description_label.text = item_data.description if not item_data.description.is_empty() else "-"

	if slot_ref != null:
		_position_item_info_panel_near_slot(slot_ref)
	else:
		_position_item_info_panel()
	item_info_panel.visible = true

func _position_item_info_panel_near_slot(slot_ref: ItemSlot) -> void:
	if inventory_window == null or item_info_panel == null:
		return

	item_info_panel.custom_minimum_size = ITEM_INFO_PANEL_SIZE
	item_info_panel.size = ITEM_INFO_PANEL_SIZE

	var slot_rect: Rect2 = slot_ref.get_global_rect()
	var window_rect: Rect2 = inventory_window.get_global_rect()
	var panel_size: Vector2 = ITEM_INFO_PANEL_SIZE
	var slot_index: int = slot_ref.get_index()
	var grid_columns: int = max(grid.columns, 1)
	@warning_ignore("integer_division")
	var slot_row: int = slot_index / grid_columns

	var min_x: float = window_rect.position.x + ITEM_INFO_PANEL_GAP
	var min_y: float = window_rect.position.y + ITEM_INFO_PANEL_GAP
	var max_x: float = window_rect.position.x + window_rect.size.x - panel_size.x - ITEM_INFO_PANEL_GAP
	var max_y: float = window_rect.position.y + window_rect.size.y - panel_size.y - ITEM_INFO_PANEL_GAP

	max_x = max(max_x, min_x)
	max_y = max(max_y, min_y)

	var panel_y: float = slot_rect.position.y + slot_rect.size.y + ITEM_INFO_PANEL_GAP

	if slot_row == 0:
		var second_row_index: int = grid_columns

		if second_row_index < grid.get_child_count() and grid.get_child(second_row_index) is Control:
			var second_row_slot: Control = grid.get_child(second_row_index) as Control
			var second_row_rect: Rect2 = second_row_slot.get_global_rect()
			panel_y = second_row_rect.position.y + second_row_rect.size.y + ITEM_INFO_PANEL_GAP
		else:
			panel_y = slot_rect.position.y + (slot_rect.size.y * 2.0) + ITEM_INFO_PANEL_GAP

	var panel_position: Vector2 = Vector2(
		window_rect.position.x + (window_rect.size.x - panel_size.x) * 0.5,
		panel_y
	)

	if panel_position.y > max_y:
		panel_position.y = slot_rect.position.y - panel_size.y - ITEM_INFO_PANEL_GAP

	panel_position.x = clampf(panel_position.x, min_x, max_x)
	panel_position.y = clampf(panel_position.y, min_y, max_y)

	item_info_panel.global_position = panel_position.round()

# Slot lock helpers

func _set_slots_hover_locked(value: bool) -> void:
	for child in grid.get_children():
		if child is ItemSlot:
			child.set_hover_locked(value)

func _set_slots_interaction_locked(value: bool, except_slot: ItemSlot = null) -> void:
	for child in grid.get_children():
		if child is ItemSlot:
			var slot: ItemSlot = child as ItemSlot
			if except_slot != null and slot == except_slot:
				slot.set_interaction_locked(false)
			else:
				slot.set_interaction_locked(value)

# Action availability

func _can_use_item(item_data: ItemData) -> bool:
	if item_data == null:
		return false

	if item_data.category != ItemEnums.ItemCategory.CONSUMABLE:
		return false

	return item_data.fatigue_reduction > 0.0 or item_data.hunger_reduction > 0.0

func _can_send_item(item_data: ItemData) -> bool:
	if item_data == null:
		return false

	return item_data.food_supply_value > 0 or item_data.clothing_supply_value > 0

# Action confirm panel

func _open_item_action_confirm_panel(action: String) -> void:
	if active_option_item_id.is_empty():
		return

	var item_data: ItemData = ItemDatabase.get_item_data(active_option_item_id)
	if item_data == null:
		return

	var item_quantity: int = int(Inventory.items.get(active_option_item_id, 0))
	if item_quantity <= 0:
		return

	if active_action_confirm_panel != null and is_instance_valid(active_action_confirm_panel):
		active_action_confirm_panel.queue_free()

	active_action_confirm_panel = ITEM_ACTION_CONFIM_PANEL_SCENE.instantiate()
	active_action_confirm_panel.confirmed.connect(_on_item_action_confirmed)
	active_action_confirm_panel.canceled.connect(_close_item_action_confirm_panel)
	add_child(active_action_confirm_panel)

	active_action_confirm_panel.setup(action, active_option_item_id, item_data, item_quantity)
	active_action_confirm_panel.global_position = active_option_panel.global_position
	_set_slots_interaction_locked(true)

func _close_item_action_confirm_panel() -> void:
	if active_action_confirm_panel != null and is_instance_valid(active_action_confirm_panel):
		active_action_confirm_panel.queue_free()
	active_action_confirm_panel = null

	if active_option_panel != null and is_instance_valid(active_option_panel):
		_set_slots_interaction_locked(true, active_option_slot)
	else:
		_set_slots_interaction_locked(false)

func _on_item_action_confirmed(action: String, item_id: String, quantity: int) -> void:
	if is_inventory_action_busy:
		return

	match action:
		"use":
			_execute_use_item(item_id, quantity)
		"send":
			_execute_send_item(item_id, quantity)
		"drop":
			_execute_drop_item(item_id, quantity)

	_close_inventory_floating_panels()

func _close_inventory_floating_panels() -> void:
	_close_item_action_confirm_panel()
	_close_option_panel()
	_set_slots_interaction_locked(false)

# Item actions

func _execute_send_item(item_id: String, quantity: int) -> void:
	if item_id.is_empty():
		return

	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if item_data == null:
		return

	if not _can_send_item(item_data):
		_show_inventory_feedback("Cannot send %s" % item_data.display_name, true)
		return

	var send_quantity: int = max(quantity, 1)
	if not Inventory.has_item(item_id, send_quantity):
		return

	var old_quantity: int = int(Inventory.items.get(item_id, 0))
	var predicted_quantity: int = max(old_quantity - send_quantity, 0)
	var slot_ref: ItemSlot = active_option_slot if active_option_slot != null and is_instance_valid(active_option_slot) else null

	_set_inventory_action_busy(true)
	await _play_slot_action_feedback(slot_ref, predicted_quantity)
	_set_inventory_action_busy(false)

	var did_send: bool = false
	if item_data.food_supply_value > 0:
		did_send = CityStockManager.deposit_food_item(item_id, send_quantity, Inventory)
	elif item_data.clothing_supply_value > 0:
		did_send = CityStockManager.deposit_clothing_item(item_id, send_quantity, Inventory)

	if did_send:
		_show_inventory_feedback("Sent %s x%d to city stock" % [item_data.display_name, send_quantity])
		_refresh_inventory_grid()
	else:
		_show_inventory_feedback("Could not send %s" % item_data.display_name, true)

func _execute_drop_item(item_id: String, quantity: int) -> void:
	if item_id.is_empty():
		return

	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if item_data == null:
		return

	var drop_quantity: int = max(quantity, 1)

	if not Inventory.has_item(item_id, drop_quantity):
		_show_inventory_feedback("Not enough %s" % item_data.display_name, true)
		return

	var old_quantity: int = int(Inventory.items.get(item_id, 0))
	var predicted_quantity: int = max(old_quantity - drop_quantity, 0)
	var slot_ref: ItemSlot = active_option_slot if active_option_slot != null and is_instance_valid(active_option_slot) else null

	_set_inventory_action_busy(true)
	await _play_slot_action_feedback(slot_ref, predicted_quantity)
	_set_inventory_action_busy(false)

	if _spawn_dropped_pickup_item(item_id, drop_quantity):
		if Inventory.remove_item(item_id, drop_quantity):
			_show_inventory_feedback("Dropped %s x%d" % [item_data.display_name, drop_quantity])
			_refresh_inventory_grid()
		else:
			_show_inventory_feedback("Could not drop %s" % item_data.display_name)

func _spawn_dropped_pickup_item(item_id: String, quantity: int) -> bool:
	if player_ref == null:
		return false

	var drop_parent: Node = player_ref.get_parent()
	if drop_parent == null:
		return false

	var pickup: PickUpItem = PICKUP_ITEM_SCENE.instantiate()
	pickup.item_id = item_id
	pickup.quantity = quantity

	drop_parent.add_child(pickup)
	pickup.global_position = player_ref.global_position + _get_drop_offset()
	pickup.play_drop_spawn_feedback()
	return true

func _get_drop_offset() -> Vector2:
	var random_y: float = randf_range(6.0, 12.0)

	if player_ref.player_sprite_direction == Vector2.LEFT:
		return Vector2(randf_range(-10.0, -5.0), random_y)

	if player_ref.player_sprite_direction == Vector2.RIGHT:
		return Vector2(randf_range(5.0, 10.0), random_y)

	return Vector2(randf_range(-4.0, 4.0), random_y)

func _execute_use_item(item_id: String, quantity: int) -> void:
	if item_id.is_empty() or player_ref == null:
		return

	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if item_data == null:
		return

	if not _can_use_item(item_data):
		_show_inventory_feedback("Cannot use %s" % item_data.display_name, true)
		return

	var available_quantity: int = int(Inventory.items.get(item_id, 0))
	var requested_quantity: int = min(max(quantity, 1), available_quantity)
	if requested_quantity <= 0:
		return

	var used_quantity: int = 0
	var total_fatigue_reduction: float = 0.0
	var total_hunger_reduction: float = 0.0

	for i in range(requested_quantity):
		var changed: bool = false
		var before_fatigue: float = player_ref.fatigue
		if player_ref.reduce_fatigue(item_data.fatigue_reduction):
			var fatigue_delta: float = max(before_fatigue - player_ref.fatigue, 0.0)
			if fatigue_delta > 0.0:
				changed = true
				total_fatigue_reduction += fatigue_delta

		var before_hunger: float = player_ref.hunger
		if player_ref.reduce_hunger(item_data.hunger_reduction):
			var hunger_delta: float = max(before_hunger - player_ref.hunger, 0.0)
			if hunger_delta > 0.0:
				changed = true
				total_hunger_reduction += hunger_delta

		if not changed:
			break

		used_quantity += 1

	if used_quantity <= 0:
		_show_inventory_feedback("No effect from %s" % item_data.display_name, true)
		return

	var old_quantity: int = available_quantity
	var predict_new_quantity: int = max(old_quantity - used_quantity, 0)
	var slot_ref: ItemSlot = active_option_slot if active_option_slot != null and is_instance_valid(active_option_slot) else null
	var slot_rect: Rect2 = slot_ref.get_global_rect() if slot_ref != null and is_instance_valid(slot_ref) else Rect2()

	consume_item_success.emit(
		item_data.id,
		item_data.display_name,
		total_fatigue_reduction,
		total_hunger_reduction,
		old_quantity,
		predict_new_quantity,
		player_ref.global_position,
		slot_rect
	)

	_set_inventory_action_busy(true)
	await _play_slot_action_feedback(slot_ref, predict_new_quantity)
	_set_inventory_action_busy(false)

	if Inventory.remove_item(item_data.id, used_quantity):
		var effects: Array[String] = []

		var hunger_percent: int = int(round(total_hunger_reduction * 100.0))
		if hunger_percent > 0:
			effects.append("Hunger -%d%%" % hunger_percent)

		var fatigue_percent: int = int(round(total_fatigue_reduction * 100.0))
		if fatigue_percent > 0:
			effects.append("Fatigue -%d%%" % fatigue_percent)

		var message: String = "Used %s x%d" % [item_data.display_name, used_quantity]

		if not effects.is_empty():
			message += ": " + ", ".join(effects)

		if used_quantity < requested_quantity:
			message += ". No further effect."

		_show_inventory_feedback(message)
		_refresh_player_status()
		_refresh_inventory_grid()

# Inventory feedback

func _show_inventory_feedback(message: String, is_error: bool = false) -> void:
	action_feedback_token += 1
	var current_token: int = action_feedback_token

	action_feedback_label.text = message

	if is_error:
		action_feedback_label.add_theme_color_override("font_color", Color(0.75, 0.22, 0.18, 1.0))
	else:
		action_feedback_label.add_theme_color_override("font_color", Color(0.33, 0.23, 0.15, 1.0))

	action_feedback_label.modulate = Color(1.0, 1.0, 1.0, 1.0)

	await get_tree().create_timer(ACTION_FEEDBACK_DURATION, true).timeout

	if current_token != action_feedback_token:
		return

	action_feedback_label.modulate.a = 0.0

func _clear_inventory_feedback() -> void:
	action_feedback_token += 1
	action_feedback_label.text = ""
	action_feedback_label.modulate = Color(1.0, 1.0, 1.0, 0.0)

# Slot action animation / busy state

func _play_slot_action_feedback(slot_ref: ItemSlot, predicted_quantity: int) -> void:
	var will_be_empty: bool = predicted_quantity <= 0
	if slot_ref == null or not is_instance_valid(slot_ref):
		return

	var original_mouse_filter: int = slot_ref.mouse_filter
	var original_icon_scale: Vector2 = slot_ref.asset_icon.scale
	var original_icon_modulate: Color = slot_ref.asset_icon.self_modulate
	var original_qty_modulate: Color = slot_ref.asset_qty.modulate
	var original_slot_scale: Vector2 = slot_ref.scale
	var original_slot_pivot: Vector2 = slot_ref.pivot_offset

	slot_ref.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_ref.asset_qty.text = str(max(predicted_quantity, 0))
	slot_ref.asset_icon.pivot_offset = slot_ref.asset_icon.size * 0.5

	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(slot_ref.asset_icon, "scale", original_icon_scale * 1.12, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot_ref.asset_icon, "self_modulate", Color(1.35, 1.35, 1.35, 1.0), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot_ref.asset_qty, "modulate:a", 0.15, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.chain()
	tween.tween_property(slot_ref.asset_icon, "scale", original_icon_scale, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot_ref.asset_icon, "self_modulate", original_icon_modulate, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot_ref.asset_qty, "modulate:a", 1.0, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain()
	tween.tween_property(slot_ref.asset_qty, "modulate:a", 0.15, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.chain()
	tween.tween_property(slot_ref.asset_qty, "modulate", original_qty_modulate, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await tween.finished

	if will_be_empty:
		slot_ref.pivot_offset = slot_ref.size * 0.5

		var exit_tween: Tween = create_tween()
		exit_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		exit_tween.set_parallel(true)
		exit_tween.tween_property(slot_ref, "modulate:a", 0.0, 0.12)
		exit_tween.tween_property(slot_ref, "scale", Vector2(0.92, 0.92), 0.12)
		await exit_tween.finished

	if slot_ref != null and is_instance_valid(slot_ref):
		slot_ref.asset_icon.scale = original_icon_scale
		slot_ref.asset_icon.self_modulate = original_icon_modulate
		slot_ref.asset_qty.modulate = original_qty_modulate
		slot_ref.mouse_filter = original_mouse_filter
		slot_ref.scale = original_slot_scale
		slot_ref.pivot_offset = original_slot_pivot

func _set_inventory_action_busy(value: bool) -> void:
	is_inventory_action_busy = value

	if active_action_confirm_panel != null and is_instance_valid(active_action_confirm_panel):
		active_action_confirm_panel.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_ALWAYS

	for child in grid.get_children():
		if child is ItemSlot:
			var slot: ItemSlot = child as ItemSlot
			slot.disabled = value
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
