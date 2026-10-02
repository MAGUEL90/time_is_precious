extends Node

## F6-only acquisition fixture for trying the real content Inventory -> City Storage flow.
## Production content grants no tools; cart/glove weight and acquisition rules remain TBD.

func _ready() -> void:
	Inventory.add_item("cart", 2)
	Inventory.add_item("basic_glove", 1)
	Inventory.add_item("stone_hammer", 1)
	Inventory.add_item("clay_lump", 3)
	Inventory.add_item("barley_bread", 2)
	Inventory.add_item("simple_clothes", 1)
	Inventory.add_item("shekel", 5)
	Inventory.add_item("gold_nugget", 1)
	Inventory.add_item("barley_grain_sack", 1)
	var content := preload("res://scenes/test_scenes/fixtures/content_worksites_map.tscn").instantiate()
	add_child(content)
	_open_supply.call_deferred(content)

func _open_supply(content: Node) -> void:
	var area: Area2D = content.get_node("YSortWorld/Worksites/CityStorageArea")
	var player: Player = content.get_node("YSortWorld/Player")
	player.global_position = area.global_position + Vector2(0, 28)
