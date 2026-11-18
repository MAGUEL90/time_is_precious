class_name InventoryUI extends CanvasLayer

signal consume_item_success(
	item_id,
	item_display_name,
	item_fatigue_reduction,
	item_hunger_reduction,
	item_old_quantity,
	item_predict_new_quantity,
	player_position,
	slot_ref_global_rect
)

const DEFAULT_SLOT_ICON: Texture2D = preload("res://assets/ui/default_icon.png")
const ITEM_ACTION_CONFIRM_PANEL_SCENE: PackedScene = preload("res://scenes/ui/item_action_confirm_panel/item_action_confirm_panel.tscn")
const PICKUP_ITEM_SCENE: PackedScene = preload("res://scenes/pickup_item/pickup_item.tscn")
const SATISFACTION_DISPLAY: Script = preload("res://scenes/ui/satisfaction_display.gd")
const ITEM_SCROLLBAR_THEME: Theme = preload("res://resources/ui_gameplay_theme/ui_gameplay_theme.tres")
const ITEM_SCROLLBAR_TEXTURE: Texture2D = preload("res://assets/ui/ui_icon/vertical_scrollbar.png")
const CATEGORY_ALL: int = -1
const MIN_VISIBLE_SLOTS: int = 12
const ITEM_GRID_FRAME_WIDTH: float = 124.0 # Four slots, spacing, scrollbar and grid margins.
const ITEM_VIEW_HEIGHT: float = 76.0 # Three 24px rows and two 2px gaps.
const ITEM_SCROLLBAR_WIDTH: float = 8.0
const OPTION_PANEL_GAP: float = 4.0
const OPTION_PANEL_Y_OFFSET: float = -4.0
const ACTION_FEEDBACK_DURATION: float = 1.5
const INVENTORY_SCREEN_MARGIN: float = 4.0
const INVENTORY_LEFT_MARGIN: float = 12.0
const INVENTORY_PLAYER_CLEARANCE: float = 12.0

@onready var inventory_container: Control = $Root/Center
@onready var inventory_window: Control = $Root/Center/Window
@onready var grid: GridContainer = $Root/Center/Window/Margin/MainVBox/Body/RightPanel/BagPanel/BagGrid/Margin/MainVBox/Scroll/Grid
@onready var item_scroll: ScrollContainer = $Root/Center/Window/Margin/MainVBox/Body/RightPanel/BagPanel/BagGrid/Margin/MainVBox/Scroll
@onready var bag_grid: Control = $Root/Center/Window/Margin/MainVBox/Body/RightPanel/BagPanel/BagGrid
@onready var worker_list: VBoxContainer = $Root/Center/Window/Margin/MainVBox/Body/RightPanel/WorkerPanel/MarginContainer/VBoxContainer/WorkerList
@onready var category_selector: InventoryCategorySelector = $Root/Center/Window/Margin/MainVBox/HeaderRow/InventoryCategorySelector
@onready var close_button: Button = $Root/Center/Window/Margin/MainVBox/HeaderRow/HeaderRightActions/MarginContainer/CloseButton
@onready var shekel_amount: Label = $Root/Center/Window/Margin/MainVBox/WalletMargin/WalletRow/ShekelAmount
@onready var action_feedback_label: Label = $Root/Center/Window/Margin/MainVBox/FeedbackArea/ActionFeedbackLabel
@onready var item_info_panel: ItemInfoPanel = $Root/ItemInfoPanelRoot

var player_ref: Player
var current_category: int = CATEGORY_ALL
var active_option_item_id: String
var active_option_slot: ItemSlot
var active_option_panel: OptionPanel
var active_action_confirm_panel: ItemActionConfirmPanel
var action_feedback_tween: Tween
var feedback_base_font_size: int
var is_inventory_action_busy: bool = false
var active_drag_data: Dictionary = {}
var _tree_paused_before_open: bool = false
var _has_pause_state_snapshot: bool = false

# Lifecycle and input

func _ready() -> void:
	player_ref = get_tree().get_first_node_in_group("player")

	visible = false
	_configure_currency_and_feedback()
	action_feedback_label.modulate.a = 0.0
	feedback_base_font_size = action_feedback_label.get_theme_font_size("font_size")
	# Reserve a stable four-pixel gap and the native-width scrollbar.
	bag_grid.custom_minimum_size.x = ITEM_GRID_FRAME_WIDTH
	bag_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	item_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	item_scroll.custom_minimum_size.y = ITEM_VIEW_HEIGHT
	item_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var scrollbar: VScrollBar = item_scroll.get_v_scroll_bar()
	scrollbar.theme = ITEM_SCROLLBAR_THEME
	scrollbar.custom_minimum_size.x = ITEM_SCROLLBAR_WIDTH
	_configure_inventory_scrollbar(scrollbar)
	scrollbar.value_changed.connect(_on_item_scroll_changed)

	if Inventory != null and Inventory.has_signal("items_changed") and not Inventory.items_changed.is_connected(_on_inventory_items_changed):
		Inventory.items_changed.connect(_on_inventory_items_changed)

	category_selector.category_changed.connect(_on_category_changed)
	close_button.pressed.connect(close_inventory)
	current_category = category_selector.get_selected_category()
	_refresh_inventory_grid()

func _configure_currency_and_feedback() -> void:
	var contents: VBoxContainer = $Root/Center/Window/Margin/MainVBox
	var wallet: MarginContainer = contents.get_node("WalletMargin") as MarginContainer
	contents.move_child(wallet, contents.get_node("Body").get_index() + 1)
	var row: HBoxContainer = wallet.get_node("WalletRow") as HBoxContainer
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var shekel_icon: TextureRect = row.get_node("ShekelIcon") as TextureRect
	var shekel_entry := HBoxContainer.new()
	shekel_entry.name = "Shekel"
	shekel_entry.add_theme_constant_override("separation", 2)
	shekel_entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shekel_entry.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(shekel_entry)
	shekel_icon.reparent(shekel_entry)
	shekel_amount.reparent(shekel_entry)
	shekel_amount.custom_minimum_size.x = 6.0
	shekel_amount.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	shekel_amount.clip_text = true
	shekel_amount.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	shekel_amount.add_theme_color_override("font_color", Color.WHITE)
	for entry_data: Array in [
		["Copper", preload("res://resources/ui_icons/small_copper.tres")],
		["Gold", preload("res://resources/ui_icons/small_gold.tres")],
	]:
		var entry := HBoxContainer.new()
		entry.name = entry_data[0]
		entry.add_theme_constant_override("separation", 2)
		entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(entry)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture = entry_data[1]
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(icon)
		var amount := Label.new()
		amount.name = "Amount"
		amount.text = "0"
		amount.accessibility_name = "%s: 0, placeholder" % entry.name
		amount.theme_type_variation = &"InventoryTextSmall"
		amount.add_theme_font_size_override("font_size", 6)
		amount.add_theme_color_override("font_color", Color.WHITE)
		amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(amount)
	row.move_child(row.get_node("Copper"), 0)
	var feedback_area: Control = contents.get_node("FeedbackArea") as Control
	action_feedback_label.reparent($Root)
	action_feedback_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	action_feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_feedback_label.z_index = 20
	action_feedback_label.add_theme_color_override("font_shadow_color", Color(0.12, 0.08, 0.05, 0.85))
	action_feedback_label.add_theme_constant_override("shadow_offset_x", 1)
	action_feedback_label.add_theme_constant_override("shadow_offset_y", 1)
	feedback_area.hide()

func _configure_inventory_scrollbar(scrollbar: VScrollBar) -> void:
	# Keep the existing artwork fixed as the rail; its bright section becomes the moving thumb.
	var rail_image: Image = ITEM_SCROLLBAR_TEXTURE.get_image()
	var rail_color: Color = rail_image.get_pixel(3, 7)
	for y in range(3, 7):
		for x in range(3, 5):
			rail_image.set_pixel(x, y, rail_color)
	var rail := StyleBoxTexture.new()
	rail.texture = ImageTexture.create_from_image(rail_image)
	rail.texture_margin_left = 2.0
	rail.texture_margin_right = 2.0
	rail.texture_margin_top = 3.0
	rail.texture_margin_bottom = 3.0
	scrollbar.add_theme_stylebox_override("scroll", rail)
	scrollbar.add_theme_stylebox_override("scroll_focus", rail)
	var highlight := AtlasTexture.new()
	highlight.atlas = ITEM_SCROLLBAR_TEXTURE
	highlight.region = Rect2(3, 3, 2, 1)
	var thumb := StyleBoxTexture.new()
	thumb.texture = highlight
	thumb.expand_margin_left = -3.0
	thumb.expand_margin_right = -3.0
	thumb.expand_margin_top = -3.0
	thumb.expand_margin_bottom = -3.0
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		scrollbar.add_theme_stylebox_override(state, thumb)

func _exit_tree() -> void:
	if Inventory != null and Inventory.has_signal("items_changed") and Inventory.items_changed.is_connected(_on_inventory_items_changed):
		Inventory.items_changed.disconnect(_on_inventory_items_changed)
	_restore_tree_pause_state()

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
		if not visible and get_tree().paused:
			get_viewport().set_input_as_handled()
			return

		_clear_inventory_feedback()
		toggle_inventory()

	elif visible and event.is_action_pressed("ui_cancel"):
		close_inventory()
		get_viewport().set_input_as_handled()

func _on_inventory_items_changed() -> void:
	_refresh_inventory_grid()

# Inventory visibility

func toggle_inventory() -> void:
	if visible:
		close_inventory()
	else:
		open_inventory()

func open_inventory() -> void:
	if not visible:
		_tree_paused_before_open = get_tree().paused
		_has_pause_state_snapshot = true

	get_tree().paused = true
	visible = true
	_position_inventory_near_player()
	_refresh_player_status()
	_refresh_inventory_grid()
	_refresh_worker_list()

func _position_inventory_near_player() -> void:
	if inventory_container == null:
		return

	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var viewport_size: Vector2 = viewport_rect.size
	var inventory_size: Vector2 = inventory_container.size * inventory_container.scale
	if not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player") as Player
	var screen_bounds: Rect2 = viewport_rect
	if is_instance_valid(player_ref):
		var scene_root: Node = player_ref.get_parent().get_parent()
		var boundary: Node = scene_root.get_node_or_null("MapBoundary")
		if boundary != null and boundary.has_method("get_world_rect") and not bool(boundary.get("_nightmare_active")):
			# Include the authored outer wall; the surrounding black is not play area.
			var world_bounds: Rect2 = boundary.call("get_world_rect")
			var scene_bounds: Rect2 = get_viewport().get_canvas_transform() * world_bounds.grow(16.0)
			var intersection: Rect2 = viewport_rect.intersection(scene_bounds)
			if intersection.size.x >= inventory_size.x and intersection.size.y >= inventory_size.y:
				screen_bounds = intersection
	var left_edge: float = screen_bounds.position.x + INVENTORY_SCREEN_MARGIN
	var right_edge: float = maxf(left_edge, screen_bounds.end.x - inventory_size.x - INVENTORY_SCREEN_MARGIN)
	var target_x: float = minf(screen_bounds.position.x + INVENTORY_LEFT_MARGIN, right_edge)
	if is_instance_valid(player_ref):
		# Canvas transform accounts for camera position and its viewport limits.
		var player_screen_x: float = player_ref.get_global_transform_with_canvas().origin.x
		if player_screen_x < screen_bounds.get_center().x:
			target_x = clampf(maxf(screen_bounds.end.x - INVENTORY_LEFT_MARGIN - inventory_size.x, player_screen_x + INVENTORY_PLAYER_CLEARANCE), left_edge, right_edge)
		else:
			target_x = clampf(minf(screen_bounds.position.x + INVENTORY_LEFT_MARGIN, player_screen_x - INVENTORY_PLAYER_CLEARANCE - inventory_size.x), left_edge, right_edge)
	var target_y: float = (viewport_size.y - inventory_size.y) * 0.5

	target_y = clampf(
		target_y,
		INVENTORY_SCREEN_MARGIN,
		viewport_size.y - inventory_size.y - INVENTORY_SCREEN_MARGIN
	)

	inventory_container.global_position = Vector2(target_x, target_y).round()

func close_inventory() -> void:
	_close_inventory_floating_panels()
	_clear_inventory_feedback()

	visible = false
	_restore_tree_pause_state()

func _restore_tree_pause_state() -> void:
	if not _has_pause_state_snapshot:
		return

	get_tree().paused = _tree_paused_before_open
	_has_pause_state_snapshot = false

# Inventory grid

func _refresh_inventory_grid() -> void:
	shekel_amount.text = str(int(Inventory.items.get("shekel", 0)))
	shekel_amount.accessibility_name = "Shekel: " + shekel_amount.text
	shekel_amount.custom_minimum_size.x = clampf(shekel_amount.get_theme_font("font").get_string_size(shekel_amount.text, HORIZONTAL_ALIGNMENT_LEFT, -1, shekel_amount.get_theme_font_size("font_size")).x, 6.0, 40.0)
	var filtered_items: Array[String] = []

	if grid == null:
		return

	_close_inventory_floating_panels()

	for child in grid.get_children():
		grid.remove_child(child)
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

	var slot_scene: PackedScene = preload("res://scenes/ui/item_slot/item_slot.tscn")

	for item_id: String in filtered_items:
		var qty: int = int(all_items[item_id])

		var slot: Node = slot_scene.instantiate()
		grid.add_child(slot)

		if slot.has_method("set_item"):
			slot.call("set_item", item_id, qty, _get_item_icon(item_id))

		if slot.has_signal("slot_clicked"):
			slot.slot_clicked.connect(_on_item_slot_clicked)

		if slot.has_signal("slot_hovered"):
			slot.slot_hovered.connect(_on_item_slot_hovered)

		if slot.has_signal("slot_unhovered"):
			slot.slot_unhovered.connect(_on_item_slot_unhovered)

		if slot.has_signal("slot_drag_started"):
			slot.slot_drag_started.connect(_on_slot_drag_started)

	var slot_count: int = maxi(MIN_VISIBLE_SLOTS, ceili(float(filtered_items.size()) / grid.columns) * grid.columns)
	var empty_slot_count: int = slot_count - filtered_items.size()

	for _i in range(empty_slot_count):
		var empty_slot: ItemSlot = slot_scene.instantiate() as ItemSlot
		grid.add_child(empty_slot)
		empty_slot.set_empty()

func _get_item_icon(item_id: String) -> Texture2D:
	if ItemDatabase != null:
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		if item_data and item_data.icon:
			return item_data.icon
		return DEFAULT_SLOT_ICON
	return DEFAULT_SLOT_ICON

# Slot selection and option opening

func _on_item_slot_clicked(item_id: String, _quantity: int, slot_ref: ItemSlot) -> void:
	if is_inventory_action_busy:
		return

	if active_action_confirm_panel != null and is_instance_valid(active_action_confirm_panel):
		return

	if active_option_panel != null and is_instance_valid(active_option_panel):
		active_option_panel.queue_free()
		active_option_panel = null

	_close_option_panel()

	var option_panel_path: PackedScene = preload("res://scenes/ui/option_panel/inventory_option_panel.tscn")
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)

	active_option_panel = option_panel_path.instantiate()
	active_option_panel.use_requested.connect(_on_option_use_requested)
	active_option_panel.drop_requested.connect(_on_option_drop_requested)
	var send_action_wrapper: Control = active_option_panel.get_node_or_null(
		^"OptionBackgroundTexture/OptionContainer/SendButtonTexture"
	) as Control
	if send_action_wrapper != null:
		send_action_wrapper.hide()

	_set_slots_hover_locked(true)
	add_child(active_option_panel)

	active_option_panel.set_actions_enabled(
		_can_use_item(item_data),
		false,
		Inventory.has_item(item_id, 1)
	)

	active_option_slot = slot_ref
	active_option_item_id = item_id
	active_option_slot.set_selected(true)

	_position_option_panel_near_slot(slot_ref)

# Option menu callbacks

func _on_option_use_requested() -> void:
	_open_item_action_confirm_panel("use")

func _on_option_drop_requested() -> void:
	_open_item_action_confirm_panel("drop")

# Slot hover

func _on_item_slot_hovered(item_id: String, _quantity: int, _slot_ref: ItemSlot) -> void:
	if is_inventory_action_busy or not active_drag_data.is_empty():
		return
	if is_instance_valid(active_action_confirm_panel) or is_instance_valid(active_option_panel):
		return
	if item_info_panel.display_item(item_id):
		item_info_panel.position_lower_center(get_viewport().get_visible_rect().end.y)

func _on_item_slot_unhovered(_slot_ref: ItemSlot) -> void:
	item_info_panel.clear_item()

# Drag and drop

func _on_slot_drag_started(data: Dictionary) -> void:
	item_info_panel.clear_item()
	active_drag_data = data

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
		_open_drag_drop_confirm_panel(active_drag_data, mouse_position)

	active_drag_data.clear()

func _open_drag_drop_confirm_panel(data: Dictionary, drop_position: Vector2) -> void:
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

	active_action_confirm_panel = ITEM_ACTION_CONFIRM_PANEL_SCENE.instantiate()
	active_action_confirm_panel.confirmed.connect(_on_item_action_confirmed)
	active_action_confirm_panel.canceled.connect(_close_item_action_confirm_panel)
	add_child(active_action_confirm_panel)

	active_action_confirm_panel.setup("drop", item_id, item_data, item_quantity)
	_position_action_confirm_panel(drop_position)
	_set_slots_interaction_locked(true)

# Player and worker summary

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
		var needs: Dictionary = CitizenNeedsManager.get_worker_needs_summary(worker_data)
		var evaluated: bool = bool(needs.get("evaluated", false))
		var label: Label = Label.new()
		label.text = "%s - %s: %s★\nStatus: %s\nSAT %d%%\nDaily F: %s C: %s S: %s\n" % [
			worker_data.get_resolved_display_name(), _get_worker_profession_name(worker_data.profession), worker_data.profession_star,
			_get_worker_work_status_text(worker_data),
			SATISFACTION_DISPLAY.to_percent(worker_data.get_resolved_satisfaction()),
			_get_need_text(bool(needs.get("food", false))) if evaluated else "?",
			_get_need_text(bool(needs.get("clothing", false))) if evaluated else "?",
			_get_need_text(bool(needs.get("shelter", false))) if evaluated else "?"
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
	var activity: String = worker_data.get_work_activity_text()
	if worker_data.is_reserved() and not worker_data.current_job_id.is_empty():
		return activity + " - " + worker_data.current_job_id
	return activity

func _get_need_text(is_fulfilled: bool) -> String:
	return "OK" if is_fulfilled else "NO"

# Category and scroll navigation

func _on_category_changed(category: int) -> void:
	current_category = category
	item_scroll.scroll_vertical = 0
	_refresh_inventory_grid()

func _on_item_scroll_changed(_value: float) -> void:
	item_info_panel.clear_item()
	if is_instance_valid(active_option_panel) or is_instance_valid(active_action_confirm_panel):
		_close_inventory_floating_panels()

# Option panel

func _close_option_panel() -> void:
	item_info_panel.clear_item()
	if active_option_panel != null and is_instance_valid(active_option_panel):
		active_option_panel.queue_free()
	active_option_panel = null

	_clear_active_option_slot()
	_set_slots_hover_locked(false)
	_set_slots_interaction_locked(false)

func _position_option_panel_near_slot(slot_ref: ItemSlot) -> void:
	if active_option_panel == null or not is_instance_valid(active_option_panel):
		return

	var slot_rect: Rect2 = slot_ref.get_global_rect()
	var window_rect: Rect2 = inventory_window.get_global_rect()
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var panel_size: Vector2 = active_option_panel.get_combined_minimum_size() * active_option_panel.scale

	var min_y: float = viewport_rect.position.y + INVENTORY_SCREEN_MARGIN
	var max_y: float = maxf(min_y, viewport_rect.end.y - panel_size.y - INVENTORY_SCREEN_MARGIN)
	var panel_position: Vector2 = Vector2(
		window_rect.end.x + OPTION_PANEL_GAP,
		slot_rect.position.y + (slot_rect.size.y - panel_size.y) * 0.5 + OPTION_PANEL_Y_OFFSET
	)

	var left_position: float = window_rect.position.x - panel_size.x - OPTION_PANEL_GAP
	if (panel_position.x + panel_size.x > viewport_rect.end.x - INVENTORY_SCREEN_MARGIN
			and left_position >= viewport_rect.position.x + INVENTORY_SCREEN_MARGIN):
		panel_position.x = left_position

	panel_position.y = clampf(panel_position.y, min_y, max_y)

	active_option_panel.global_position = panel_position.round()
	_set_slots_interaction_locked(true, active_option_slot)

func _clear_active_option_slot() -> void:
	if active_option_slot != null and is_instance_valid(active_option_slot):
		active_option_slot.set_selected(false)

	active_option_slot = null
	active_option_item_id = ""

# Slot locking

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

	if _is_belly_full():
		return false

	return item_data.fatigue_reduction > 0.0 or item_data.hunger_reduction > 0.0

func _is_belly_full() -> bool:
	return player_ref != null and player_ref.hunger <= player_ref.min_hunger

# Action confirmation

func _open_item_action_confirm_panel(action: String) -> void:
	if active_option_item_id.is_empty():
		return

	var item_data: ItemData = ItemDatabase.get_item_data(active_option_item_id)
	if item_data == null:
		return

	var item_quantity: int = int(Inventory.items.get(active_option_item_id, 0))
	if item_quantity <= 0:
		return
	var panel_position: Vector2 = active_option_panel.global_position

	if active_action_confirm_panel != null and is_instance_valid(active_action_confirm_panel):
		active_action_confirm_panel.queue_free()

	active_action_confirm_panel = ITEM_ACTION_CONFIRM_PANEL_SCENE.instantiate()
	active_action_confirm_panel.confirmed.connect(_on_item_action_confirmed)
	active_action_confirm_panel.canceled.connect(_close_item_action_confirm_panel)
	add_child(active_action_confirm_panel)

	active_option_panel.hide()
	active_action_confirm_panel.setup(action, active_option_item_id, item_data, item_quantity)
	_position_action_confirm_panel(panel_position)
	_set_slots_interaction_locked(true)

func _position_action_confirm_panel(requested_position: Vector2) -> void:
	if not is_instance_valid(active_action_confirm_panel):
		return

	var viewport_bounds: Rect2 = get_viewport().get_visible_rect()
	var margin: float = INVENTORY_SCREEN_MARGIN
	var panel_size: Vector2 = active_action_confirm_panel.size
	var min_position: Vector2 = viewport_bounds.position + Vector2.ONE * margin
	var max_position: Vector2 = viewport_bounds.end - panel_size - Vector2.ONE * margin
	max_position.x = maxf(min_position.x, max_position.x)
	max_position.y = maxf(min_position.y, max_position.y)

	var target: Vector2 = Vector2(
		clampf(requested_position.x, min_position.x, max_position.x),
		clampf(requested_position.y, min_position.y, max_position.y)
	).round()
	var inventory_rect: Rect2 = inventory_window.get_global_rect()
	if Rect2(target, panel_size).intersects(inventory_rect):
		var left_x: float = inventory_rect.position.x - OPTION_PANEL_GAP - panel_size.x
		var right_x: float = inventory_rect.end.x + OPTION_PANEL_GAP
		var prefer_left: bool = requested_position.x < inventory_rect.get_center().x
		if prefer_left and left_x >= min_position.x:
			target.x = left_x
		elif not prefer_left and right_x <= max_position.x:
			target.x = right_x
		elif left_x >= min_position.x:
			target.x = left_x
		elif right_x <= max_position.x:
			target.x = right_x
	active_action_confirm_panel.global_position = target.round()

func _close_item_action_confirm_panel() -> void:
	if active_action_confirm_panel != null and is_instance_valid(active_action_confirm_panel):
		active_action_confirm_panel.queue_free()
	active_action_confirm_panel = null

	if active_option_panel != null and is_instance_valid(active_option_panel):
		active_option_panel.show()
		_set_slots_interaction_locked(true, active_option_slot)
	else:
		_set_slots_interaction_locked(false)

func _on_item_action_confirmed(action: String, item_id: String, quantity: int) -> void:
	if is_inventory_action_busy:
		return
	if action != "use" and action != "drop":
		_close_inventory_floating_panels()
		return

	match action:
		"use":
			_execute_use_item(item_id, quantity)
		"drop":
			_execute_drop_item(item_id, quantity)

	_close_inventory_floating_panels()

# Floating panel cleanup

func _close_inventory_floating_panels() -> void:
	item_info_panel.clear_item()
	_close_item_action_confirm_panel()
	_close_option_panel()
	_set_slots_interaction_locked(false)

# Item actions

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
			_show_inventory_feedback("Could not drop %s" % item_data.display_name, true)

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

	if item_data.category == ItemEnums.ItemCategory.CONSUMABLE and _is_belly_full():
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
		if _is_belly_full():
			break
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
	_cancel_inventory_feedback_timer()
	var panel_rect: Rect2 = inventory_window.get_global_rect()
	action_feedback_label.size = Vector2(maxf(1.0, panel_rect.size.x - 32.0), 16.0)
	action_feedback_label.global_position = (panel_rect.get_center() - action_feedback_label.size * 0.5).round()
	var origin: Vector2 = action_feedback_label.position
	var pages: Array[String] = _split_feedback_pages(message)
	_set_feedback_page(pages[0])

	if is_error:
		action_feedback_label.add_theme_color_override("font_color", Color(0.90, 0.38, 0.32, 1.0))
	else:
		action_feedback_label.add_theme_color_override("font_color", Color(0.28, 0.68, 0.31, 1.0))

	action_feedback_label.modulate = Color(1.0, 1.0, 1.0, 0.0)

	# Bound to this UI: scene changes or replacement messages cancel the pending hide.
	action_feedback_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	action_feedback_tween.tween_property(action_feedback_label, "modulate:a", 1.0, 0.10)
	if is_error:
		for offset: float in [2.0, -2.0, 1.0, 0.0]:
			action_feedback_tween.tween_property(action_feedback_label, "position:x", origin.x + offset, 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		action_feedback_tween.tween_property(action_feedback_label, "position:y", origin.y - 3.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		action_feedback_tween.tween_property(action_feedback_label, "position:y", origin.y, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for index in range(pages.size()):
		if index > 0:
			action_feedback_tween.tween_callback(_set_feedback_page.bind(pages[index]))
		action_feedback_tween.tween_interval(ACTION_FEEDBACK_DURATION)
	action_feedback_tween.tween_property(action_feedback_label, "modulate:a", 0.0, 0.20)

func _split_feedback_pages(message: String) -> Array[String]:
	var pages: Array[String] = []
	var remaining: String = message.strip_edges()
	var font: Font = action_feedback_label.get_theme_font("font")
	var font_size: int = feedback_base_font_size
	var width: float = maxf(action_feedback_label.size.x, 1.0)
	while not remaining.is_empty():
		var count: int = 0
		while count < remaining.length() and remaining[count] != "\n":
			if font.get_string_size(remaining.left(count + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
				break
			count += 1
		if count == remaining.length():
			pages.append(remaining)
			break
		if count < remaining.length() and remaining[count] != "\n" and remaining[count] != " ":
			var last_space: int = remaining.left(count).rfind(" ")
			if last_space > 0:
				count = last_space
			else:
				# Keep an unusually long word intact and fit it on its own page.
				var next_space: int = remaining.find(" ", count)
				var next_line: int = remaining.find("\n", count)
				count = remaining.length()
				if next_space >= 0:
					count = mini(count, next_space)
				if next_line >= 0:
					count = mini(count, next_line)
		if count == 0:
			count = 1
		pages.append(remaining.left(count).strip_edges())
		remaining = remaining.substr(count).strip_edges()
	if pages.is_empty():
		pages.append("")
	return pages

func _set_feedback_page(page: String) -> void:
	var font: Font = action_feedback_label.get_theme_font("font")
	var font_size: int = feedback_base_font_size
	while font_size > 1 and font.get_string_size(page, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > action_feedback_label.size.x:
		font_size -= 1
	action_feedback_label.add_theme_font_size_override("font_size", font_size)
	action_feedback_label.text = page

func _cancel_inventory_feedback_timer() -> void:
	if action_feedback_tween != null and action_feedback_tween.is_valid():
		action_feedback_tween.kill()
	action_feedback_tween = null

func _clear_inventory_feedback() -> void:
	_cancel_inventory_feedback_timer()
	action_feedback_label.text = ""
	action_feedback_label.modulate = Color(1.0, 1.0, 1.0, 0.0)

# Slot action feedback and busy state

func _play_slot_action_feedback(slot_ref: ItemSlot, predicted_quantity: int) -> void:
	var will_be_empty: bool = predicted_quantity <= 0
	if slot_ref == null or not is_instance_valid(slot_ref):
		return

	var original_mouse_filter: int = slot_ref.mouse_filter
	var original_icon_modulate: Color = slot_ref.asset_icon.self_modulate
	var original_qty_modulate: Color = slot_ref.asset_qty.modulate
	var original_slot_modulate: Color = slot_ref.modulate

	slot_ref.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_ref.asset_qty.text = str(max(predicted_quantity, 0))

	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(slot_ref.asset_icon, "self_modulate", Color(1.35, 1.35, 1.35, 1.0), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot_ref.asset_qty, "modulate:a", 0.15, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.chain()
	tween.tween_property(slot_ref.asset_icon, "self_modulate", original_icon_modulate, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot_ref.asset_qty, "modulate:a", 1.0, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain()
	tween.tween_property(slot_ref.asset_qty, "modulate:a", 0.15, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.chain()
	tween.tween_property(slot_ref.asset_qty, "modulate", original_qty_modulate, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await tween.finished

	if will_be_empty:
		var exit_tween: Tween = create_tween()
		exit_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		exit_tween.set_parallel(true)
		exit_tween.tween_property(slot_ref, "modulate:a", 0.0, 0.12)
		await exit_tween.finished

	if slot_ref != null and is_instance_valid(slot_ref):
		slot_ref.asset_icon.self_modulate = original_icon_modulate
		slot_ref.asset_qty.modulate = original_qty_modulate
		slot_ref.mouse_filter = original_mouse_filter
		slot_ref.modulate = original_slot_modulate

func _set_inventory_action_busy(value: bool) -> void:
	is_inventory_action_busy = value

	if active_action_confirm_panel != null and is_instance_valid(active_action_confirm_panel):
		active_action_confirm_panel.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_ALWAYS

	for child in grid.get_children():
		if child is ItemSlot:
			var slot: ItemSlot = child as ItemSlot
			slot.disabled = value
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
