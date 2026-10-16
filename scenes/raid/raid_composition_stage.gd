extends Resource

## Count and strength bounds are independent. Heavy chance is per party, not per slot.
@export var id: StringName
@export var display_name: String
@export var min_count: int = 0
@export var max_count: int = 0
@export var min_strength: int = 0
@export var max_strength: int = 0
@export_range(0.0, 1.0) var heavy_chance: float = 0.0
@export var max_heavy: int = 0

func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() and min_count > 0 \
		and max_count >= min_count and min_strength > 0 and max_strength >= min_strength \
		and is_finite(heavy_chance) and heavy_chance >= 0.0 and heavy_chance <= 1.0 \
		and max_heavy >= 0 and max_heavy <= max_count and (heavy_chance == 0.0 or max_heavy > 0)
