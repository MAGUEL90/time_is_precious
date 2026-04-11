class_name InventoryUI extends CanvasLayer

signal consume_item_success(item_id,
							item_display_name,
							item_fatigue_reduction,
							item_old_quantity,
							item_predict_new_quantity,
							player_position,
							slot_ref_global_rect)

const DEFAULT_SLOT_ICON: Texture2D = preload("res://assets/ui/default_icon.png")

@onready var grid: GridContainer = $Root/Center/Window/Margin/MainVBox/Body/RightPanel/BagPanel/BagGrid/Margin/MainVBox/Scroll/Grid
@onready var info_label: Label = $Root/Center/Window/Margin/MainVBox/Body/RightPanel/BagPanel/BagGrid/Margin/MainVBox/Header/InfoLabel

var player: Player
var source_slot: Vector2

func _ready() -> void:
	
	player = get_tree().get_first_node_in_group("player")
	
	visible = false
	if Inventory != null and Inventory.has_signal("items_changed") and not Inventory.items_changed.is_connected(_on_inventory_items_changed):
		Inventory.items_changed.connect(_on_inventory_items_changed)
	_refresh_inventory_grid()

func _exit_tree() -> void:
	if Inventory != null and Inventory.has_signal("items_changed") and Inventory.items_changed.is_connected(_on_inventory_items_changed):
		Inventory.items_changed.disconnect(_on_inventory_items_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_inventory"):
		toggle_inventory()
	
	elif visible and event.is_action_pressed("ui_cancel"):
		close_inventory()

func _on_inventory_items_changed() -> void:
	_refresh_inventory_grid()

func toggle_inventory() -> void:
	if visible:
		close_inventory()
	else:
		open_inventory()

func open_inventory() -> void:
	get_tree().paused = true
	visible = true
	_refresh_inventory_grid()

func close_inventory() -> void:
	get_tree().paused = false
	visible = false

func _refresh_inventory_grid():
	if grid == null: return
	
	for child in grid.get_children():
		child.queue_free()
	
	var all_items: Dictionary = Inventory.items
	var used_slots: int = 0
	
	for item_id: String in all_items.keys():
		var qty: int = int(all_items[item_id])
		if qty <= 0:
			continue
	
		var slot_scene: PackedScene = preload("res://scenes/ui/item_slot/item_slot.tscn")
		var slot: Node = slot_scene.instantiate()

		grid.add_child(slot)
		
		if slot.has_method("set_item"):
			slot.call("set_item", item_id, qty, _get_item_icon(item_id))
		
		if slot.has_signal("slot_clicked"):
			slot.slot_clicked.connect(_on_item_slot_slot_clicked)
		used_slots += 1
		
	if info_label != null:
		var current_load: float = Inventory.get_total_inventory_weight()
		info_label.text = "Current / Max Capacity: %.1f / %.1f | Slot: %d" % [current_load, Inventory.max_load, used_slots]

func _get_item_icon(item_id: String) -> Texture2D:
	
	if ItemDatabase != null:
		var item_data: ItemData = ItemDatabase.get_item_data(item_id)
		if item_data and item_data.icon:
			return item_data.icon
		return DEFAULT_SLOT_ICON
	return DEFAULT_SLOT_ICON

func _on_item_slot_slot_clicked(item_id: String, quantity: int, slot_ref: ItemSlot) -> void:
	var item_data: ItemData = Inventory.get_item_data(item_id)
	if item_data != null:
		if item_data.category == ItemEnums.ItemCategory.CONSUMABLE:
			if item_data.fatigue_reduction > 0.0:
				if player != null:
					if player.reduce_fatigue(item_data.fatigue_reduction) == true:
						var old_quantity: int = quantity
						var predict_new_quantity: int = max(old_quantity - 1, 0)
						consume_item_success.emit(
							item_data.id,
							item_data.display_name,
							item_data.fatigue_reduction,
							old_quantity,
							predict_new_quantity,
							player.global_position,
							slot_ref.get_global_rect()
						)
						
						var impact_tween = _play_slot_consume_effect(slot_ref)
						
						if impact_tween: 
							_play_slot_quantity_preview(slot_ref, predict_new_quantity)
							slot_ref.disabled = true
							
						await impact_tween.finished
						Inventory.remove_item(item_data.id, 1)


func _play_slot_consume_effect(slot_ref: ItemSlot) -> Tween:
	var tween: Tween = create_tween()
	slot_ref.asset_icon.pivot_offset = slot_ref.asset_icon.size * 0.5
	tween.tween_property(slot_ref.asset_icon, "self_modulate", Color(1.4,1.4,1.4,1.0), 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.set_parallel()
	tween.tween_property(slot_ref.asset_icon, "scale", Vector2(1.1, 1.1),0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween

func _play_slot_quantity_preview(slot_ref: ItemSlot, new_predict_quantity: int) -> void:
	slot_ref.asset_qty.text = str(new_predict_quantity)
	
	if new_predict_quantity <= 0:
		slot_ref.asset_qty.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		slot_ref.self_modulate = Color(1.4,1.4,1.4,1.0)
	else:
		slot_ref.asset_qty.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

	
	
	
	
	
	
	
	
	
	
