extends Resource

## A party's travel time belongs to the expedition, not to detection.
const UNIT_SCRIPT: Script = preload("res://scenes/raid/raid_unit_config.gd")
const STAGE_SCRIPT: Script = preload("res://scenes/raid/raid_composition_stage.gd")
@export var display_name: String = "Normal raiders"
@export var travel_days: int = 3
@export var attack_min: int = 0
@export var attack_max: int = 0
@export var composition_enabled: bool = false
@export var unit_types: Array[Resource] = []
@export var composition_stages: Array[Resource] = []

func is_valid() -> bool:
	if not composition_enabled:
		return travel_days > 0 and attack_min > 0 and attack_max >= attack_min
	if unit_types.is_empty() or composition_stages.is_empty():
		return false
	var ids: Array[StringName] = []
	for unit: Resource in unit_types:
		if unit == null or unit.get_script() != UNIT_SCRIPT or not unit.is_valid() or ids.has(unit.id):
			return false
		ids.append(unit.id)
	ids.clear()
	for stage: Resource in composition_stages:
		if stage == null or stage.get_script() != STAGE_SCRIPT or not stage.is_valid() or ids.has(stage.id):
			return false
		ids.append(stage.id)
		var pools: Dictionary = _composition_pools(stage)
		if (stage.heavy_chance < 1.0 and pools.ordinary.is_empty()) or (stage.heavy_chance > 0.0 and pools.heavy.is_empty()):
			return false
	return true

func get_min_travel_days() -> int:
	if not composition_enabled:
		return travel_days
	var minimum: int = 0
	for unit: Resource in unit_types:
		if unit != null:
			minimum = unit.travel_days if minimum == 0 else mini(minimum, unit.travel_days)
	return minimum

func get_stage(stage_id: StringName) -> Resource:
	for stage: Resource in composition_stages:
		if stage.id == stage_id:
			return stage
	return null

func roll_party(rng: RandomNumberGenerator, stage_id: StringName) -> Dictionary:
	if not composition_enabled:
		return {}
	var stage: Resource = get_stage(stage_id)
	if stage == null:
		return {}
	var pools: Dictionary = _composition_pools(stage)
	var include_heavy: bool = rng.randf() < stage.heavy_chance
	var candidates: Array = pools.heavy if include_heavy else pools.ordinary
	if candidates.is_empty():
		return {}
	var counts: Array = candidates[rng.randi_range(0, candidates.size() - 1)]
	var units: Array[Dictionary] = []
	var strength: int = 0
	var count: int = 0
	var days: int = 0
	for index: int in range(unit_types.size()):
		var amount: int = counts[index]
		if amount == 0:
			continue
		var unit: Resource = unit_types[index]
		units.append({"id": str(unit.id), "display_name": unit.display_name, "count": amount,
			"attack": unit.attack, "travel_days": unit.travel_days, "icon": unit.icon})
		strength += amount * unit.attack
		count += amount
		days = maxi(days, unit.travel_days)
	return {"type": display_name, "stage_id": str(stage.id), "units": units,
		"total_count": count, "attack_strength": strength, "travel_total_minutes": days * 1440}

func _composition_pools(stage: Resource) -> Dictionary:
	var pools: Dictionary = {"ordinary": [], "heavy": []}
	_collect_compositions(stage, 0, [], 0, 0, false, pools)
	return pools

func _collect_compositions(stage: Resource, index: int, counts: Array[int], total: int, strength: int, has_heavy: bool, pools: Dictionary) -> void:
	if index == unit_types.size():
		if total >= stage.min_count and strength >= stage.min_strength:
			pools["heavy" if has_heavy else "ordinary"].append(counts.duplicate())
		return
	var unit: Resource = unit_types[index]
	var limit: int = mini(stage.max_count - total, (stage.max_strength - strength) / unit.attack)
	if unit.id == &"heavy":
		limit = mini(limit, stage.max_heavy)
	for amount: int in range(limit + 1):
		counts.append(amount)
		_collect_compositions(stage, index + 1, counts, total + amount, strength + amount * unit.attack,
			has_heavy or (unit.id == &"heavy" and amount > 0), pools)
		counts.pop_back()
