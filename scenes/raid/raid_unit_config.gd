extends Resource

## Per-member values; the expedition freezes a copy when the party departs.
@export var id: StringName
@export var display_name: String
@export var icon: Texture2D
@export var attack: int = 0
@export var travel_days: int = 0

func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() and attack > 0 and travel_days > 0
