extends Node2D

# Test Setup

# Seed kondisi awal khusus scene test worker loop.
# Jumlah kecil: cukup untuk 3x job mudbrick (3+3+3 per job) dan beberapa hari kebutuhan.
func _ready() -> void:
	Inventory.add_item("clay_lump", 9)
	Inventory.add_item("straw_bundle", 9)
	Inventory.add_item("water_jar", 9)
	Inventory.add_item("shekel", 20)

	var city_storage: Node = WorkStateRuntime.get_node_or_null("CityToolStorage")
	if city_storage == null:
		city_storage = preload("res://scenes/storage_destination/city_tool_storage.gd").new()
		city_storage.name = "CityToolStorage"
		WorkStateRuntime.add_child(city_storage)
	city_storage.try_add_item("barley_bread", 20)
	CityStockManager.add_clothing_supply(20)
	CityStockManager.add_shelter_capacity(10)

	for _i in range(8):
		var resident: CitizenData = CitizenGenerator.generate_citizen()
		resident.population_status = CitizenData.PopulationStatus.RESIDENT
		CitizenManager.add_citizen(resident)
