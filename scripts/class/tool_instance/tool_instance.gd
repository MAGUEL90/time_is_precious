class_name ToolInstance extends Node


var tool_id: String = ""
var durability: int = 0
var durability_max: int = 1


func consume(amount: int) -> int:
	return amount

func is_broken() -> bool:
	return false

# INI HINT, BARIS KE BERAPA AKU
