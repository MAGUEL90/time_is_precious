class_name InventoryUI extends CanvasLayer

func _ready() -> void:
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_inventory"):
		toggle_inventory()
	
	elif visible == true and event.is_action_pressed("ui_cancel"):
		closed_inventory()

func toggle_inventory() -> void:
	if visible:
		closed_inventory()
	else:
		open_inventory()

func open_inventory() -> void:
	get_tree().paused = true
	visible = true

func closed_inventory() -> void:
	get_tree().paused = false
	visible = false
