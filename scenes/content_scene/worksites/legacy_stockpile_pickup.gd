extends "res://pickup_item.gd"

## A former stockpile can contain more than the player's bag can carry. Keep
## the unclaimed portion in this same world pickup instead of recreating it.
const MAX_INVENTORY_COUNT: int = 9223372036854775807
var _taking: bool = false


func on_player_interact(player: Player) -> void:
	if is_collecting or _taking:
		return
	var taken: int = _quantity_that_fits()
	if taken <= 0:
		play_failed_pickup_shake()
		return

	var original: int = quantity
	var emptied: bool = taken == original
	_taking = true
	# Inventory emits items_changed synchronously. A nested save or scene
	# handoff must see the remainder, or no pile if this pickup is exhausted.
	quantity = original - taken
	if emptied:
		is_collecting = true
	var added: bool = _transfer_to_inventory(taken)
	if not is_instance_valid(self):
		return
	if not added:
		quantity = original
		is_collecting = false
		_taking = false
		return
	if not is_inside_tree() or is_queued_for_deletion():
		_taking = false
		if emptied and not is_queued_for_deletion():
			queue_free()
		return

	if emptied:
		# Match the standard pickup's collected signal, popup, animation and
		# cleanup. It is excluded from snapshots while the animation runs.
		quantity = taken
		_finish_full_pickup(player)
		if is_instance_valid(self):
			_taking = false
		return

	var quantity_label := get_node_or_null("QuantityLabel") as Label
	if quantity_label != null:
		quantity_label.text = "x%d" % quantity
	_show_partial_popup(player, taken)
	if not is_instance_valid(self):
		return
	if is_inside_tree() and is_player_in_interaction_range:
		_refresh_interaction_feedback()
	_taking = false


func _transfer_to_inventory(taken: int) -> bool:
	return Inventory.try_add_item(item_id, taken)


func _quantity_that_fits() -> int:
	if Inventory == null or quantity <= 0:
		return 0
	var item: ItemData = ItemDatabase.get_item_data(item_id)
	if item == null or not is_finite(item.weight) or item.weight < 0.0:
		return 0
	var count: int = int(Inventory.items.get(item_id, 0))
	if count < 0:
		return 0
	var remaining: float = Inventory.get_remaining_capacity()
	if not is_finite(remaining) or remaining < 0.0:
		return 0
	var fits: int = quantity
	if item.weight > 0.0 and not Inventory.has_capacity_for(item_id, quantity):
		if remaining < item.weight:
			return 0
		fits = mini(quantity, int(floor(remaining / item.weight)))
	# Inventory counts are signed integers; never wrap an existing stack.
	return mini(fits, MAX_INVENTORY_COUNT - count)


func _refresh_interaction_feedback() -> void:
	# A partly full bag can take some of this pile, even if it cannot take all.
	if _quantity_that_fits() <= 0:
		interactable_label_component.label.add_theme_color_override("font_color", INVENTORY_FULL_COLOR)
		interactable_label_component.set_text("Inventory Full")
		_restore_default_highlight()
		return
	interactable_label_component.label.remove_theme_color_override("font_color")
	interactable_label_component.set_text("E")
	_play_focus_highlight()


func _show_partial_popup(player: Player, taken: int) -> void:
	if not is_instance_valid(player) or not is_inside_tree() or not is_instance_valid(get_tree().current_scene):
		return
	var item_popup = ITEM_CHANGE_POPUP_SCENE.instantiate()
	get_tree().current_scene.add_child(item_popup)
	if not is_instance_valid(self) or not is_instance_valid(player) or not is_instance_valid(item_popup):
		if is_instance_valid(item_popup):
			item_popup.queue_free()
		return
	item_popup.global_position = player.global_position + Vector2(0, -28)
	item_popup.setup(item_id, taken, true)


func _finish_full_pickup(player: Player) -> void:
	collected.emit()
	if not is_instance_valid(self):
		return
	if not is_inside_tree():
		queue_free()
		return
	if is_queued_for_deletion():
		return
	if idle_tween and idle_tween.is_valid():
		idle_tween.kill()
	if highlight_tween and highlight_tween.is_valid():
		highlight_tween.kill()
	icon.position = icon_default_position
	collision_shape_2d.disabled = true
	interactable_label_component.hide()
	if is_instance_valid(player) and is_instance_valid(get_tree().current_scene):
		_spawn_pickup_popup(player)
		if not is_instance_valid(self) or not is_inside_tree() or is_queued_for_deletion():
			return
		if not is_instance_valid(player):
			queue_free()
			return
		collecting_tween = create_tween()
		collecting_tween.tween_property(self, "global_position", player.global_position, 0.1).set_ease(Tween.EASE_IN_OUT)
		collecting_tween.tween_property(self, "scale", Vector2.ZERO, 0.05)
		collecting_tween.tween_interval(0.2)
		collecting_tween.tween_callback(queue_free)
	else:
		queue_free()
