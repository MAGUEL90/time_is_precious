extends Resource

## A party's travel time belongs to the expedition, not to detection.
@export var display_name: String = "Normal raiders"
@export var travel_days: int = 3
@export var attack_min: int = 0
@export var attack_max: int = 0

func is_valid() -> bool:
	return travel_days > 0 and attack_min > 0 and attack_max >= attack_min
