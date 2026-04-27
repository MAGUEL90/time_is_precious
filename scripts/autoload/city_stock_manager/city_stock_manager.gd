extends Node

const MAX_STOCK: int = 9999
const MAX_SHEKEL: int = 9999

var food_stock: int
var clothing_stock: int
var treasury_shekel: int

func deposit_food_item(item_id: String, amount: int, inventory: Inventory) -> bool:
	if inventory == null:
		return false

	if amount <= 0:
		return false

	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	if item_data == null or item_data.food_supply_value <= 0:
		return false

	if not inventory.has_item(item_id, amount):
		return false

	if not inventory.remove_item(item_id, amount):
		return false

	add_food(item_data.food_supply_value * amount)
	return true


func add_food(amount: int) -> bool:
	if amount <= 0:
		return false
	
	food_stock = clampi(food_stock + amount, 0, MAX_STOCK)
	return true

func consume_food(amount: int) -> bool:
	if not has_food(amount):
		return false
	
	food_stock -= amount
	return true

func has_food(amount: int) -> bool:
	if amount <= 0:
		return false
	if food_stock >= amount:
		return true
	
	return false

func add_clothing(amount: int) -> bool:
	if amount <= 0:
		return false
	
	clothing_stock = clampi(clothing_stock + amount, 0, MAX_STOCK)
	return true

func consume_clothing(amount: int) -> bool:
	if not has_clothing(amount):
		return false
	
	clothing_stock -= amount
	return true

func has_clothing(amount: int) -> bool:
	if amount <= 0:
		return false
	if clothing_stock >= amount:
		return true
	
	return false

func add_shekel(amount: int) -> bool:
	if amount <= 0:
		return false
	
	treasury_shekel = clampi(treasury_shekel + amount, 0, MAX_SHEKEL)
	return true

func spend_shekel(amount: int) -> bool:
	if not has_shekel(amount):
		return false
	
	treasury_shekel -= amount
	return true

func has_shekel(amount: int) -> bool:
	if amount <= 0:
		return false
	if treasury_shekel >= amount:
		return true
	
	return false
