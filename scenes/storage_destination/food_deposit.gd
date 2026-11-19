extends "res://scenes/storage_destination/city_storage_area.gd"

## This map entrance only exposes ready food from the player's bag.
func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player = body
		storage = WorkStateRuntime.get_node_or_null("CityToolStorage")
	super._on_body_entered(body)

func on_player_interact(interacting_player: Player) -> void:
	if interacting_player != player or not has_player_access() or is_instance_valid(menu):
		return
	if not player.can_move or get_tree().paused or player.current_interactable != self:
		return
	var transfer: ItemTransferUI = preload("res://scenes/ui/item_transfer_ui/item_transfer_ui.tscn").instantiate()
	menu = transfer
	add_child(transfer)
	player.set_movement_locked(&"food_deposit", true)
	interactable_label_component.hide()
	transfer.allowed_category = ItemEnums.ItemCategory.CONSUMABLE
	transfer.transfer_confirmed.connect(_deposit.bind(transfer))
	transfer.transfer_back_requested.connect(close_menu)
	transfer.transfer_cancelled.connect(close_menu)
	transfer.open_transfer("Deposit food for residents", _available_food(), "Deposit")
	get_viewport().set_input_as_handled()

func _available_food() -> Dictionary:
	var food: Dictionary = {}
	for row: Dictionary in storage.get_depositable_items(true):
		food[row.item_id] = row.quantity
	return food

func _deposit(items: Dictionary, source: ItemTransferUI) -> void:
	if source != menu:
		return
	if not has_player_access():
		close_menu()
		return
	var food: Dictionary = _available_food()
	if not food.has_all(items.keys()):
		source.refresh_items(food, "Choose food from your bag.")
		return
	var result: Dictionary = storage.deposit_items_from_inventory(items)
	if is_instance_valid(menu) and menu == source:
		source.refresh_items(_available_food(), str(result.message))

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(menu) and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_menu()

func close_menu() -> void:
	if not is_instance_valid(menu):
		return
	menu.hide()
	menu.queue_free()
	menu = null
	get_tree().paused = false
	if is_instance_valid(player):
		player.set_movement_locked(&"food_deposit", false)
		if player.current_interactable == self and has_player_access():
			interactable_label_component.show()
