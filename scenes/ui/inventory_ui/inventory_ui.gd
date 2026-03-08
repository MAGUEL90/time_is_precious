class_name InventoryUI extends CanvasLayer

func _ready() -> void:
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_inventory"):
		toggle_inventory()
	
	elif visible and event.is_action_pressed("ui_cancel"):
		close_inventory()

func toggle_inventory() -> void:
	if visible:
		close_inventory()
	else:
		open_inventory()

func open_inventory() -> void:
	get_tree().paused = true
	visible = true

func close_inventory() -> void:
	get_tree().paused = false
	visible = false
