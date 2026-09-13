extends "res://pickup_item.gd"

# A merged daily pile can exceed bag capacity. Reuse the standard pickup feedback
# for the portion that fits and leave the remainder at its worksite.
var return_remainder: Callable

func on_player_interact(player: Player) -> void:
	if is_collecting:
		return
	var item: ItemData = ItemDatabase.get_item_data(item_id)
	var fits: int = quantity
	if item != null and item.weight > 0.0:
		fits = maxi(0, int(floor(Inventory.get_remaining_capacity() / item.weight)))
	if fits <= 0 or fits >= quantity:
		super.on_player_interact(player)
		return
	var original: int = quantity
	quantity = fits
	super.on_player_interact(player)
	if is_collecting:
		get_node("QuantityLabel").text = "x%d" % quantity
		return_remainder.call(original - fits)
	else:
		quantity = original
