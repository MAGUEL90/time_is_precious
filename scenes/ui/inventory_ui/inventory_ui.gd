class_name InventoryUI extends CanvasLayer

const DEFAULT_SLOT_ICON: Texture2D = preload("res://assets/ui/default_icon.png")
const ITEM_ICON_BY_ID: Dictionary[String, Texture2D] = {
	"clay_lump": preload("res://assets/items/clay_lump.png"),
	"shekel": preload("res://assets/items/shekel.png"),
	"straw_bundle": preload("res://assets/items/straw_bundle.png"),
	"sun_dried_mudbrick": preload("res://assets/items/sun_dried_mudbrick.png"),
	"water_jar": preload("res://assets/items/water_jar.png"),
	"wet_mudbrick": preload("res://assets/items/wet_mudbrick.png")
}

@onready var grid: GridContainer = $Root/Center/Window/Margin/MainVBox/Body/RightPanel/BagPanel/BagGrid/Margin/MainVBox/Scroll/Grid
@onready var info_label: Label = $Root/Center/Window/Margin/MainVBox/Body/RightPanel/BagPanel/BagGrid/Margin/MainVBox/Header/InfoLabel


func _ready() -> void:
	visible = false
	if Inventory != null and Inventory.has_signal("items_changed") and not Inventory.items_changed.is_connected(_on_inventory_items_changed):
		Inventory.items_changed.connect(_on_inventory_items_changed)
	_refresh_inventory_grid()

func exit_tree() -> void:
	if Inventory != null and Inventory.has_signal("items_changed") and not Inventory.items_changed.is_connected(_on_inventory_items_changed):
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
		used_slots += 1
		
	if info_label != null:
		info_label.text = "%d/%d" % [used_slots, 40]

func _get_item_icon(item_id: String) -> Texture2D:
	return ITEM_ICON_BY_ID.get(item_id, DEFAULT_SLOT_ICON)
