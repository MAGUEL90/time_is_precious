extends Resource

## Raid balance is opt-in. Zero values mean not configured, never final balance.
## The first wall playtest is separate from enabling random raids.
@export var raids_enabled: bool = false
@export var instant_build_enabled: bool = false
@export var instant_repair_enabled: bool = false
@export var timed_work_enabled: bool = false
@export var build_materials: Dictionary = {}
@export var repair_materials_per_step: Dictionary = {}
@export var repair_hp_per_step: int = 1
@export var build_minutes: int = 0
@export var repair_minutes: int = 0
@export var wall_max_hp: int = 50
@export var wall_defend: int = 0
@export var duration_seconds: float = 60.0
@export var hit_interval_seconds: float = 5.0
@export var attack_min: int = 0
@export var attack_max: int = 0
@export var interval_min_days: int = 0
@export var interval_max_days: int = 0
@export var warning_days: int = 1
@export var party_profile: Resource
@export var recovery_days: int = 0
@export var theft_capacity: int = 0
@export var reserve_per_stack: int = 1
@export_range(0.0, 1.0) var satisfaction_penalty: float = 0.0
@export var max_fleeing_residents: int = 0

func is_valid() -> bool:
	if repair_hp_per_step <= 0 or build_minutes < 0 or repair_minutes < 0:
		return false
	if timed_work_enabled and (build_minutes <= 0 or repair_minutes <= 0):
		return false
	for requirements: Dictionary in [build_materials, repair_materials_per_step]:
		for id: Variant in requirements:
			if not id is String or str(id).is_empty() or not requirements[id] is int or int(requirements[id]) <= 0:
				return false
	if wall_max_hp <= 0 or wall_defend < 0:
		return false
	if not is_finite(duration_seconds) or not is_finite(hit_interval_seconds) or duration_seconds <= 0.0 or hit_interval_seconds <= 0.0 or hit_interval_seconds > duration_seconds:
		return false
	if attack_min < 0 or attack_max < attack_min or theft_capacity < 0 or reserve_per_stack < 0 or max_fleeing_residents < 0:
		return false
	if not is_finite(satisfaction_penalty) or satisfaction_penalty < 0.0 or satisfaction_penalty > 1.0:
		return false
	if recovery_days < 0:
		return false
	if raids_enabled and party_profile != null:
		return party_profile.get_script() == load("res://scenes/raid/raid_party_config.gd") and party_profile.is_valid() and warning_days >= 1 and warning_days <= party_profile.travel_days
	if raids_enabled and (attack_min <= 0 or interval_min_days <= warning_days or interval_max_days < interval_min_days or warning_days < 1):
		return false
	return true
