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
@export var defense_improvements_enabled: bool = false
@export var level_2_max_hp: int = 0
@export var level_2_defend: int = 0
@export var upgrade_materials: Dictionary = {}
@export var upgrade_minutes: int = 0
@export var watchtower_materials: Dictionary = {}
@export var watchtower_minutes: int = 0
@export var watchtower_warning_days: int = 0
@export var duration_seconds: float = 60.0
@export var hit_interval_seconds: float = 5.0
@export var attack_min: int = 0
@export var attack_max: int = 0
@export var interval_min_days: int = 0
@export var interval_max_days: int = 0
@export var warning_days: int = 1
@export var party_profile: Resource
@export var recovery_days: int = 0
## Ranked looting is separate from the legacy unit-count fixture.
@export var ranked_looting_enabled: bool = false
@export var loot_capacity_weight: float = 0.0
@export var loot_seconds_per_item: float = 1.0
@export_enum("balanced", "food", "valuables") var loot_preference: String = "balanced"
@export var theft_capacity: int = 0
@export var reserve_per_stack: int = 1
@export_range(0.0, 1.0) var satisfaction_penalty: float = 0.0
@export var max_fleeing_residents: int = 0

func is_valid() -> bool:
	if party_profile != null and (party_profile.get_script() != load("res://scenes/raid/raid_party_config.gd") or not party_profile.is_valid()):
		return false
	if defense_improvements_enabled:
		if not timed_work_enabled or level_2_max_hp <= wall_max_hp or level_2_defend <= wall_defend:
			return false
		if upgrade_minutes <= 0 or watchtower_minutes <= 0 or watchtower_warning_days <= warning_days:
			return false
		if party_profile != null and watchtower_warning_days > party_profile.get_min_travel_days():
			return false
	if not is_finite(loot_capacity_weight) or loot_capacity_weight < 0.0 or not is_finite(loot_seconds_per_item) or loot_seconds_per_item <= 0.0:
		return false
	if loot_preference not in ["balanced", "food", "valuables"] or (ranked_looting_enabled and loot_capacity_weight <= 0.0):
		return false
	if repair_hp_per_step <= 0 or build_minutes < 0 or repair_minutes < 0:
		return false
	if timed_work_enabled and (build_minutes <= 0 or repair_minutes <= 0):
		return false
	for requirements: Dictionary in [build_materials, repair_materials_per_step, upgrade_materials, watchtower_materials]:
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
		return warning_days >= 1 and warning_days <= party_profile.get_min_travel_days()
	if raids_enabled and (attack_min <= 0 or interval_min_days <= warning_days or interval_max_days < interval_min_days or warning_days < 1):
		return false
	return true
