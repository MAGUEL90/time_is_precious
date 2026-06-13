extends Node2D

# Seed kondisi awal khusus scene test worker loop.
# Jumlah kecil: cukup untuk 3x job mudbrick (3+3+3 per job) dan beberapa hari kebutuhan.
func _ready() -> void:
	Inventory.add_item("clay_lump", 9)
	Inventory.add_item("straw_bundle", 9)
	Inventory.add_item("water_jar", 9)
	Inventory.add_item("shekel", 20)

	CityStockManager.add_food_supply(20)
	CityStockManager.add_clothing_supply(20)
	CityStockManager.add_shelter_capacity(10)
