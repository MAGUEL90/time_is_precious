extends Resource

## Raid balance is opt-in. Zero values mean not configured, never final balance.
## The first wall playtest is separate from enabling random raids.
@export var raids_enabled: bool = false
@export var instant_build_enabled: bool = false
@export var instant_repair_enabled: bool = false
@export var wall_max_hp: int = 50
@export var wall_defend: int = 0
@export var duration_seconds: float = 60.0
@export var hit_interval_seconds: float = 5.0
@export var attack_min: int = 0
@export var attack_max: int = 0
@export var interval_min_days: int = 0
@export var interval_max_days: int = 0
@export var warning_days: int = 1
@export var theft_capacity: int = 0
@export var reserve_per_stack: int = 1
@export_range(0.0, 1.0) var satisfaction_penalty: float = 0.0
@export var max_fleeing_residents: int = 0

func is_valid() -> bool:
	if wall_max_hp <= 0 or wall_defend < 0:
		return false
	if not is_finite(duration_seconds) or not is_finite(hit_interval_seconds) or duration_seconds <= 0.0 or hit_interval_seconds <= 0.0 or hit_interval_seconds > duration_seconds:
		return false
	if attack_min < 0 or attack_max < attack_min or theft_capacity < 0 or reserve_per_stack < 0 or max_fleeing_residents < 0:
		return false
	if not is_finite(satisfaction_penalty) or satisfaction_penalty < 0.0 or satisfaction_penalty > 1.0:
		return false
	if raids_enabled and (attack_min <= 0 or interval_min_days <= warning_days or interval_max_days < interval_min_days or warning_days < 1):
		return false
	return true
