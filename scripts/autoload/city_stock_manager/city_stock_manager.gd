extends Node

const MAX_STOCK: int = 9999
const MAX_SHEKEL: int = 9999

var food_supply: int
var clothing_supply: int
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

	add_food_supply(item_data.food_supply_value * amount)
	return true


func add_food_supply(amount: int) -> bool:
	if amount <= 0:
		return false
	
	food_supply = clampi(food_supply + amount, 0, MAX_STOCK)
	return true

func consume_food_supply(amount: int) -> bool:
	if not has_food_supply(amount):
		return false
	
	food_supply -= amount
	return true

func has_food_supply(amount: int) -> bool:
	if amount <= 0:
		return false
	if food_supply >= amount:
		return true
	
	return false

func add_clothing_supply(amount: int) -> bool:
	if amount <= 0:
		return false
	
	clothing_supply = clampi(clothing_supply + amount, 0, MAX_STOCK)
	return true

func consume_clothing_supply(amount: int) -> bool:
	if not has_clothing_supply(amount):
		return false
	
	clothing_supply -= amount
	return true

func has_clothing_supply(amount: int) -> bool:
	if amount <= 0:
		return false
	if clothing_supply >= amount:
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
