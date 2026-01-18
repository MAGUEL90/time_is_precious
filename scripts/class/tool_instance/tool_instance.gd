class_name ToolInstance extends Node


var tool_id: String = ""
var durability: int = 0
var durability_max: int = 1


func consume(amount: int) -> int:
	if amount <= 0:
		return 0
	
	durability = max(durability- amount, 0) # durability tidak boleh negatif
	return amount

func is_broken() -> bool:
	return durability <= 0 # tool rusak kalau durability 0

# INI HINT, BARIS KE BERAPA AKU ?
