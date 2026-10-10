extends Node

const RAID_CONFIG_SCRIPT: Script = preload("res://scenes/raid/raid_config.gd")
const RAID_STATE_SCRIPT: Script = preload("res://scenes/raid/raid_state.gd")
const MINUTES_PER_DAY: int = 1440
const SAMPLE_COUNT: int = 2500

var failures: int = 0
var states: Array[Node] = []
var clock_processing_before: bool = true
var clock_paused_before: bool = false
var tree_paused_before: bool = false

func _ready() -> void:
	clock_processing_before = TimeComponentManager.is_processing()
	clock_paused_before = TimeComponentManager.is_paused
	tree_paused_before = get_tree().paused
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)

func _run() -> void:
	_test_approved_profile_and_sampling()
	_test_validation_and_legacy_fallback()
	_test_departure_snapshot_and_combat()
	for state: Node in states:
		if is_instance_valid(state):
			state.free()
	get_tree().paused = tree_paused_before
	TimeComponentManager.is_paused = clock_paused_before
	TimeComponentManager.set_process(clock_processing_before)
	print("RaidCompositionRegressionTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _test_approved_profile_and_sampling() -> void:
	var profile: Resource = _load_mixed_profile()
	_expect(bool(profile.get("composition_enabled")) and profile.is_valid(),
		"The live party profile enables a valid mixed composition.")
	var expected_stages: Dictionary = {
		&"early": {"min_count": 3, "max_count": 5, "min_strength": 5, "max_strength": 7, "heavy_chance": 0.1, "max_heavy": 1},
		&"developing": {"min_count": 4, "max_count": 7, "min_strength": 8, "max_strength": 11, "heavy_chance": 0.25, "max_heavy": 2},
		&"advanced": {"min_count": 6, "max_count": 10, "min_strength": 12, "max_strength": 16, "heavy_chance": 0.45, "max_heavy": 3}
	}
	var unit_stats: Dictionary = {"light": [1, 2], "normal": [2, 3], "heavy": [4, 4]}
	for unit: Resource in profile.get("unit_types"):
		var unit_id: String = str(unit.get("id"))
		_expect(unit_stats.has(unit_id)
			and int(unit.get("attack")) == unit_stats.get(unit_id, [0, 0])[0]
			and int(unit.get("travel_days")) == unit_stats.get(unit_id, [0, 0])[1],
			"The approved %s unit keeps its configured attack and travel values." % unit_id)
	_expect(profile.get("unit_types").size() == 3,
		"The approved profile has light, normal, and heavy raider types.")

	var seen_travel_days: Dictionary = {}
	for stage_id: StringName in expected_stages:
		var expected: Dictionary = expected_stages[stage_id]
		var stage: Resource = profile.call("get_stage", stage_id) as Resource
		_expect(is_instance_valid(stage), "The approved %s stage exists." % str(stage_id))
		if not is_instance_valid(stage):
			continue
		for key: String in expected:
			_expect(is_equal_approx(float(stage.get(key)), float(expected[key])),
				"The %s stage keeps its approved %s value." % [str(stage_id), key])

		var rng := RandomNumberGenerator.new()
		var heavy_parties: int = 0
		var invalid_parties: int = 0
		for sample_index: int in range(SAMPLE_COUNT):
			rng.seed = 12000 + sample_index
			var party: Dictionary = profile.call("roll_party", rng, stage_id)
			if not _assert_generated_party(party, expected, unit_stats):
				invalid_parties += 1
			if _party_has_unit(party, "heavy"):
				heavy_parties += 1
			for row: Dictionary in party.get("units", []):
				seen_travel_days[int(row.get("travel_days", 0))] = true
		_expect(invalid_parties == 0,
			"Every sampled %s party stays within its count/strength bounds and derives its own stats." % str(stage_id))
		var observed_heavy_rate: float = float(heavy_parties) / float(SAMPLE_COUNT)
		var allowed_deviation: float = 0.025 if stage_id == &"early" else 0.03
		_expect(absf(observed_heavy_rate - float(expected.heavy_chance)) <= allowed_deviation,
			"Sampled %s heavy presence (%0.3f) stays near its approved per-party probability %0.2f." % [str(stage_id), observed_heavy_rate, float(expected.heavy_chance)])
	_expect(seen_travel_days.has(2) and seen_travel_days.has(3) and seen_travel_days.has(4),
		"Generated parties include the light, normal, and heavy travel speeds across the approved stages.")

	var first_rng := RandomNumberGenerator.new()
	first_rng.seed = 987654
	var repeat_rng := RandomNumberGenerator.new()
	repeat_rng.seed = 987654
	var first_roll: Dictionary = profile.call("roll_party", first_rng, &"developing")
	var repeated_roll: Dictionary = profile.call("roll_party", repeat_rng, &"developing")
	_expect(first_roll == repeated_roll,
		"The same profile, stage, and random seed produce the same complete party snapshot.")

func _assert_generated_party(party: Dictionary, bounds: Dictionary, unit_stats: Dictionary) -> bool:
	var valid: bool = not party.is_empty()
	var total_count: int = 0
	var derived_attack: int = 0
	var slowest_days: int = 0
	var heavy_count: int = 0
	for row: Dictionary in party.get("units", []):
		var unit_id: String = str(row.get("id", ""))
		var count: int = int(row.get("count", 0))
		valid = valid and count > 0 and unit_stats.has(unit_id)
		if not unit_stats.has(unit_id):
			continue
		var stats: Array = unit_stats[unit_id]
		var attack: int = int(stats[0])
		var travel_days: int = int(stats[1])
		valid = valid and int(row.get("attack", -1)) == attack
		valid = valid and int(row.get("travel_days", -1)) == travel_days
		total_count += count
		derived_attack += count * attack
		slowest_days = maxi(slowest_days, travel_days)
		if unit_id == "heavy":
			heavy_count += count
	valid = valid and total_count >= int(bounds.min_count) and total_count <= int(bounds.max_count)
	valid = valid and derived_attack >= int(bounds.min_strength) and derived_attack <= int(bounds.max_strength)
	valid = valid and total_count == int(party.get("total_count", -1))
	valid = valid and derived_attack == int(party.get("attack_strength", -1))
	valid = valid and slowest_days * MINUTES_PER_DAY == int(party.get("travel_total_minutes", -1))
	valid = valid and heavy_count <= int(bounds.max_heavy)
	return valid

func _party_has_unit(party: Dictionary, unit_id: String) -> bool:
	for row: Dictionary in party.get("units", []):
		if str(row.get("id", "")) == unit_id:
			return int(row.get("count", 0)) > 0
	return false

func _test_validation_and_legacy_fallback() -> void:
	var malformed: Resource = _load_mixed_profile()
	var malformed_units: Array = malformed.get("unit_types")
	var invalid_unit: Resource = malformed_units[0].duplicate(true)
	invalid_unit.set("attack", 0)
	malformed_units[0] = invalid_unit
	malformed.set("unit_types", malformed_units)
	_expect(not malformed.is_valid(),
		"Composition validation rejects a unit with a nonpositive attack value.")
	var malformed_config: Resource = _new_config(malformed)
	_expect(not malformed_config.is_valid(),
		"Raid configuration validation also rejects malformed composition data.")

	var impossible: Resource = _load_mixed_profile()
	var stages: Array = impossible.get("composition_stages")
	var impossible_early: Resource = stages[0].duplicate(true)
	impossible_early.set("min_count", 1)
	impossible_early.set("max_count", 1)
	impossible_early.set("min_strength", 1)
	impossible_early.set("max_strength", 1)
	impossible_early.set("heavy_chance", 1.0)
	impossible_early.set("max_heavy", 1)
	stages[0] = impossible_early
	impossible.set("composition_stages", stages)
	_expect(not impossible.is_valid(),
		"Composition validation rejects a guaranteed-heavy stage with no possible heavy candidate.")
	var impossible_rng := RandomNumberGenerator.new()
	impossible_rng.seed = 1
	_expect((impossible.call("roll_party", impossible_rng, &"early") as Dictionary).is_empty(),
		"An impossible stage fails closed without displaying an empty party as valid.")

	var legacy: Resource = load("res://scenes/raid/normal_raider_party.tres").duplicate(true)
	_expect(legacy.is_valid() and not bool(legacy.get("composition_enabled"))
		and (legacy.call("roll_party", RandomNumberGenerator.new(), &"early") as Dictionary).is_empty(),
		"The retained legacy fixed-party profile remains valid and opts out of composition rolls.")

	var live_config: Resource = load("res://scenes/raid/wall_playtest.tres")
	_expect(live_config.is_valid() and int(live_config.get("recovery_days")) == 3
		and is_equal_approx(float(live_config.get("duration_seconds")), 60.0)
		and is_equal_approx(float(live_config.get("hit_interval_seconds")), 5.0)
		and is_equal_approx(float(live_config.get("loot_capacity_weight")), 10.0)
		and is_equal_approx(float(live_config.get("loot_seconds_per_item")), 1.0),
		"The mixed party profile leaves recovery, hit timing, raid duration, and loot capacity/rate unchanged.")

func _new_config(profile: Resource) -> Resource:
	var config: Resource = RAID_CONFIG_SCRIPT.new()
	config.set("raids_enabled", true)
	config.set("instant_build_enabled", true)
	config.set("instant_repair_enabled", true)
	config.set("warning_days", 1)
	config.set("party_profile", profile)
	config.set("recovery_days", 3)
	config.set("wall_max_hp", 50)
	config.set("wall_defend", 2)
	config.set("duration_seconds", 60.0)
	config.set("hit_interval_seconds", 5.0)
	return config

func _load_mixed_profile() -> Resource:
	# Load after script initialization because this project's compiled Resource
	# preloads can expose incomplete exported values in headless runs.
	return load("res://scenes/raid/mixed_raider_party.tres").duplicate(true)

func _new_composition_state(seed: int) -> Node:
	var state: Node = RAID_STATE_SCRIPT.new()
	state.set("config", _new_config(_load_mixed_profile()))
	add_child(state)
	states.append(state)
	var rng: RandomNumberGenerator = state.get("_rng")
	rng.seed = seed
	_expect(bool(state.call("build_wall")), "A test wall builds and schedules its first mixed party.")
	return state

func _test_departure_snapshot_and_combat() -> void:
	var state: Node = _new_composition_state(42042)
	var party_before: Dictionary = state.get("_party").duplicate(true)
	var sequence_before: int = int(state.get("_expedition_sequence"))
	var departure: int = int(state.get("_departure_at"))
	var arrival: int = int(state.get("_attack_at"))
	_expect(str(state.get("_composition_stage")) == "early"
		and sequence_before == 1 and not party_before.is_empty()
		and arrival == departure + int(party_before.get("travel_total_minutes", 0)),
		"The default early party is frozen exactly at departure and fixes arrival from its slowest unit.")
	var hidden_status: Dictionary = state.call("get_status")
	_expect(hidden_status.phase == "safe" and hidden_status.travel_total_minutes == 0
		and not hidden_status.has("units") and not hidden_status.has("total_count")
		and (state.call("inspect_raiders") as Dictionary).is_empty(),
		"Before detection or a watchtower, status and Inspect reveal no party composition.")
	state.set("watchtower_built", true)
	_expect((state.call("inspect_raiders") as Dictionary).is_empty(),
		"A watchtower cannot inspect a party before the warning phase.")
	state.set("watchtower_built", false)

	var changed_future_stage: bool = bool(state.call("set_city_threat_stage", &"advanced"))
	var after_stage_change: Dictionary = state.get("_party").duplicate(true)
	state.set("wall_hp", 41)
	_expect(changed_future_stage and after_stage_change == party_before
		and state.get("_party") == party_before and int(state.get("_attack_at")) == arrival,
		"Changing the stage or wall after departure leaves the travelling snapshot and ETA fixed.")
	_expect(not bool(state.call("set_city_threat_stage", &"unlisted")),
		"An unknown city threat stage is rejected.")

	# The warning opens at the configured detection lead, but remains unknown until
	# the explicit watchtower Inspect action is available.
	_notify_state_at(state, arrival - MINUTES_PER_DAY)
	_expect(str(state.get("phase")) == "warning"
		and (state.call("inspect_raiders") as Dictionary).is_empty(),
		"A warning without a watchtower does not expose raider composition.")
	state.set("watchtower_built", true)
	var inspection: Dictionary = state.call("inspect_raiders")
	var expected_party: Dictionary = state.get("_party")
	_expect(inspection.id == sequence_before and inspection.phase == "warning"
		and int(inspection.arrival_minutes_remaining) == MINUTES_PER_DAY
		and inspection.units == expected_party.units
		and inspection.total_count == expected_party.total_count
		and inspection.attack_strength == expected_party.attack_strength
		and inspection.travel_total_minutes == expected_party.travel_total_minutes,
		"Detected Inspect exposes the departure snapshot, frozen ETA, and derived totals.")
	inspection.units[0].count = 999
	inspection.units.append({"id": "forged", "count": 1})
	inspection.attack_strength = 999
	_expect(state.get("_party") == expected_party,
		"Mutating an Inspect result cannot modify authoritative party data.")

	var status_during_warning: Dictionary = state.call("get_status")
	_expect(not status_during_warning.has("units") and not status_during_warning.has("total_count"),
		"Status exposes warning timing without leaking the explicit Inspect party list.")
	_notify_state_at(state, arrival)
	_expect(str(state.get("phase")) == "attacking"
		and int(state.get("_attack_strength")) == int(expected_party.attack_strength),
		"Arrival starts combat using the exact frozen party strength without a new attack roll.")
	var wall_before_hit: int = int(state.get("wall_hp"))
	var defend: int = int(state.call("get_wall_defend"))
	var damage: int = maxi(0, int(expected_party.attack_strength) - defend)
	state.call("advance_attack", 5.0)
	_expect(int(state.get("wall_hp")) == maxi(0, wall_before_hit - damage)
		and int(state.get("_hits")) == 1
		and int(state.get("_attack_strength")) == int(expected_party.attack_strength),
		"Each combat hit applies the frozen attack minus normal wall Defend and never rerolls strength.")
	state.call("advance_attack", 55.0)
	_expect(str(state.get("phase")) == "recovery" and int(state.get("_report_sequence")) == 1,
		"The frozen mixed-party attack resolves through the unchanged timed raid loop.")
	var wall_restored: bool = bool(state.call("build_wall")) if int(state.get("wall_hp")) == 0 else bool(state.call("repair_wall"))
	_expect(wall_restored and int(state.get("wall_hp")) == int(state.call("get_wall_max_hp")),
		"The follow-up cooldown fixture restores a standing wall before its next party arrives.")
	var recovery_departure: int = arrival + 3 * MINUTES_PER_DAY
	_expect(int(state.get("_departure_at")) == recovery_departure
		and int(state.get("_attack_at")) == -1 and (state.get("_party") as Dictionary).is_empty()
		and (state.call("inspect_raiders") as Dictionary).is_empty(),
		"Recovery has a scheduled cooldown but no party or arrival estimate before the next departure.")
	var recovery_status: Dictionary = state.call("get_status")
	_expect(int(recovery_status.get("travel_total_minutes", 0)) == 0
		and int(recovery_status.get("arrival_minutes_remaining", 0)) == 0,
		"Status keeps the next expedition ETA unknown during cooldown.")

	var sequence_after_first: int = int(state.get("_expedition_sequence"))
	_notify_state_at(state, recovery_departure - 1)
	_expect(int(state.get("_expedition_sequence")) == sequence_after_first
		and (state.get("_party") as Dictionary).is_empty()
		and int(state.get("_attack_at")) == -1,
		"Repeated and pre-departure clock ticks do not generate the next party early.")
	var large_jump: int = recovery_departure + 4 * MINUTES_PER_DAY + 100
	_notify_state_at(state, large_jump)
	var second_party: Dictionary = state.get("_party").duplicate(true)
	var second_arrival: int = int(state.get("_attack_at"))
	_expect(sequence_after_first == 1 and int(state.get("_expedition_sequence")) == 2
		and int(state.get("_departure_at")) == recovery_departure
		and str(second_party.get("stage_id", "")) == "advanced"
		and second_arrival == recovery_departure + int(second_party.get("travel_total_minutes", 0))
		and second_arrival < large_jump and str(state.get("phase")) == "attacking"
		and int(state.get("_attack_strength")) == int(second_party.get("attack_strength", -1)),
		"A jump across next departure and arrival creates one advanced party at the scheduled cooldown end without shifting its arrival.")
	var second_party_snapshot: Dictionary = state.get("_party").duplicate(true)
	_notify_state_at(state, large_jump)
	_notify_state_at(state, large_jump - MINUTES_PER_DAY)
	_expect(int(state.get("_expedition_sequence")) == 2 and state.get("_party") == second_party_snapshot,
		"Repeated or rewound time cannot reroll a departed mixed party.")

func _notify_state_at(state: Node, total_minutes: int) -> void:
	var day: int = floori(float(total_minutes) / float(MINUTES_PER_DAY))
	var minute_of_day: int = posmod(total_minutes, MINUTES_PER_DAY)
	state.call("_on_time_changed", day, minute_of_day / 60, minute_of_day % 60, "clear")
