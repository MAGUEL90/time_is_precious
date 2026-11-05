extends Node

const PLAN_SCRIPT: Script = preload("res://scenes/content_scene/worksites/timed_deposit_plan.gd")
const CITY_SAVE_VALUES: Script = preload("res://scenes/new_scenes/save_game/city_save_values.gd")

var failures: int = 0


func _ready() -> void:
	_run()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var low_seed: int = _find_seed_for_delay(PLAN_SCRIPT.MIN_RESPAWN_DELAY_MINUTES)
	var high_seed: int = _find_seed_for_delay(PLAN_SCRIPT.MAX_RESPAWN_DELAY_MINUTES)
	_check(low_seed >= 0, "A caller-owned RNG can select the inclusive 2880-minute lower edge.")
	_check(high_seed >= 0, "A caller-owned RNG can select the inclusive 4320-minute upper edge.")
	if low_seed >= 0:
		var low_plan = PLAN_SCRIPT.new()
		var low_rng := RandomNumberGenerator.new()
		low_rng.seed = low_seed
		_check(low_plan.initialize_stock(8, 8), "A plan initializes from caller-supplied stock and capacity.")
		_check(low_plan.record_depletion_after_commit(1000, low_rng), "Committed depletion records successfully.")
		_check(low_plan.get_respawn_due_minute() - low_plan.get_depleted_at_minute() == 2880,
			"The lower delay edge is exactly 2880 minutes.")
	if high_seed >= 0:
		var high_plan = PLAN_SCRIPT.new()
		var high_rng := RandomNumberGenerator.new()
		high_rng.seed = high_seed
		_check(high_plan.initialize_stock(8, 8), "A second plan initializes with its own caller capacity.")
		_check(high_plan.record_depletion_after_commit(2000, high_rng), "A second committed depletion records successfully.")
		_check(high_plan.get_respawn_due_minute() - high_plan.get_depleted_at_minute() == 4320,
			"The upper delay edge is exactly 4320 minutes.")

	_test_wait_and_refill()
	_test_save_restore_and_validation()
	_test_legacy_migration()
	print("TimedDepositPlanTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _find_seed_for_delay(target_delay: int) -> int:
	for seed_value: int in range(100000):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		if probe.randi_range(PLAN_SCRIPT.MIN_RESPAWN_DELAY_MINUTES, PLAN_SCRIPT.MAX_RESPAWN_DELAY_MINUTES) == target_delay:
			return seed_value
	return -1


func _test_wait_and_refill() -> void:
	var plan = PLAN_SCRIPT.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 123456
	_check(plan.initialize_stock(40, 40), "Initial stock uses the caller's full capacity.")
	_check(plan.update_remaining_stock_after_commit(17, 40), "Committed partial output updates only the remaining stock.")
	_check(plan.get_stock() == 17, "Partial output remains conserved in the plan.")
	_check(plan.record_depletion_after_commit(5000, rng), "A fully committed depletion schedules one respawn.")
	var due: int = plan.get_respawn_due_minute()
	var rng_after_first_schedule: int = rng.state
	_check(plan.get_stock() == 0 and plan.is_respawn_pending(), "A depleted plan has zero stock and a pending timer.")
	_check(plan.record_depletion_after_commit(9000, rng), "Repeated depletion notification is accepted idempotently.")
	_check(plan.get_respawn_due_minute() == due and rng.state == rng_after_first_schedule,
		"Repeated depletion does not reroll or consume caller RNG.")
	_check(not plan.try_refill(due - 1, true, 23), "A paused or early clock cannot refill before due time.")
	_check(plan.get_stock() == 0, "Stock remains empty while waiting before due time.")
	_check(not plan.try_refill(due, false, 23), "Due time alone cannot refill without caller location confirmation.")
	_check(plan.get_stock() == 0 and plan.is_respawn_pending(), "Missing location confirmation leaves the due deposit pending.")
	_check(plan.try_refill(due, true, 23), "A confirmed location refills at the exact due minute.")
	_check(plan.get_stock() == 23 and not plan.is_respawn_pending(), "Refill uses the capacity passed by its caller.")
	_check(not plan.try_refill(due + 10000, true, 91), "Repeated calls cannot refill a completed cycle twice.")
	_check(plan.get_stock() == 23, "A completed refill conserves its caller-selected output amount.")

	var skipped_plan = PLAN_SCRIPT.new()
	var skipped_rng := RandomNumberGenerator.new()
	skipped_rng.seed = 654321
	_check(skipped_plan.initialize_stock(4, 12), "A deposit can start below caller-supplied capacity.")
	_check(skipped_plan.record_depletion_after_commit(700, skipped_rng), "A time-skip fixture schedules its depletion.")
	_check(skipped_plan.try_refill(skipped_plan.get_respawn_due_minute() + 1440, true, 12),
		"A time skip past the deadline refills once as soon as location is confirmed.")
	_check(skipped_plan.get_stock() == 12, "Time-skip refill uses the supplied capacity.")


func _test_save_restore_and_validation() -> void:
	var plan = PLAN_SCRIPT.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	_check(plan.initialize_stock(31, 31), "Save fixture initializes.")
	_check(plan.record_depletion_after_commit(12000, rng), "Save fixture schedules a committed depletion.")
	var due_before_save: int = plan.get_respawn_due_minute()
	var codec = CITY_SAVE_VALUES.new()
	var encoded: Variant = codec.encode(plan.to_save_value())
	_check(codec.error.is_empty(), "Timed deposit state encodes through CitySaveValues.")
	var decoded: Variant = codec.decode(JSON.parse_string(JSON.stringify(encoded, "", true, true)))
	_check(codec.error.is_empty() and decoded is Dictionary, "CitySaveValues JSON roundtrip decodes timed deposit state.")
	if decoded is Dictionary:
		var restored = PLAN_SCRIPT.new()
		_check(restored.restore_from_save_value(decoded, 50), "Decoded pending state restores using caller capacity.")
		_check(restored.get_stock() == 0 and restored.get_respawn_due_minute() == due_before_save,
			"Continue restores the original depletion and deadline without rerolling.")
		var before_repeat: Dictionary = restored.to_save_value()
		_check(restored.restore_from_save_value(decoded, 50), "Repeated restore accepts the same validated checkpoint.")
		_check(restored.to_save_value() == before_repeat and restored.get_respawn_due_minute() == due_before_save,
			"Repeated restore is stable and preserves the saved deadline.")
		_check(restored.try_refill(due_before_save, true, 50), "Restored pending state refills at its original deadline.")
		var completed_snapshot: Dictionary = restored.to_save_value()
		var completed_copy = PLAN_SCRIPT.new()
		_check(completed_copy.restore_from_save_value(completed_snapshot, 50), "Completed refill state survives CitySaveValues-compatible restore.")
		_check(not completed_copy.try_refill(due_before_save + 5000, true, 50) and completed_copy.get_stock() == 50,
			"Restoring after refill does not apply the completed cycle twice.")

	var invalid_plan = PLAN_SCRIPT.new()
	var invalid_rng := RandomNumberGenerator.new()
	invalid_rng.seed = 987
	_check(invalid_plan.initialize_stock(10, 10), "Invalid-input fixture initializes.")
	var untouched_before: Dictionary = invalid_plan.to_save_value()
	var rng_state_before: int = invalid_rng.state
	_check(not invalid_plan.record_depletion_after_commit(-1, invalid_rng), "Negative game time is rejected.")
	_check(invalid_plan.to_save_value() == untouched_before and invalid_rng.state == rng_state_before,
		"Invalid depletion input changes neither plan state nor caller RNG.")
	_check(invalid_plan.record_depletion_after_commit(300, invalid_rng), "A valid depletion follows the rejected call.")
	var pending_before: Dictionary = invalid_plan.to_save_value()
	var corrupt_snapshot: Dictionary = pending_before.duplicate(true)
	corrupt_snapshot["respawn_due_minute"] = int(corrupt_snapshot["depleted_at_minute"]) + 1
	_check(not invalid_plan.restore_from_save_value(corrupt_snapshot, 10), "An out-of-range saved delay is rejected.")
	_check(invalid_plan.to_save_value() == pending_before, "Invalid restore is atomic and leaves prior state intact.")
	_check(not invalid_plan.restore_from_save_value(pending_before, 10, 299), "A checkpoint rejects depletion recorded in the future.")
	_check(invalid_plan.to_save_value() == pending_before, "A future-depletion rejection leaves the old state intact.")
	_check(not invalid_plan.try_refill(invalid_plan.get_respawn_due_minute(), true, 0), "Zero capacity is rejected.")
	_check(invalid_plan.to_save_value() == pending_before, "Invalid refill input leaves the pending timer untouched.")


func _test_legacy_migration() -> void:
	var positive_legacy = PLAN_SCRIPT.new()
	_check(positive_legacy.restore_from_save_value({"stock": 12}, 24),
		"Legacy positive stock restores without a checkpoint timestamp.")
	_check(positive_legacy.get_stock() == 12 and not positive_legacy.is_respawn_pending(),
		"Legacy positive stock is preserved unchanged with no timer.")
	var oversized_legacy = PLAN_SCRIPT.new()
	_check(oversized_legacy.restore_from_save_value({"stock": 240}, 36),
		"Legacy stock restores even when the caller's current capacity is lower.")
	_check(oversized_legacy.get_stock() == 240,
		"Legacy stock 240 is preserved exactly when today's capacity is 36.")
	_check(oversized_legacy.update_remaining_stock_after_commit(239, 36) and oversized_legacy.get_stock() == 239,
		"Committed stock can decline gradually while above a reduced current capacity.")
	var oversized_current = PLAN_SCRIPT.new()
	_check(oversized_current.restore_from_save_value({
		"schema_version": PLAN_SCRIPT.SNAPSHOT_VERSION,
		"stock": 240,
		"depleted_at_minute": null,
		"respawn_due_minute": null,
	}, 36), "Current positive stock also restores above the supplied capacity.")
	_check(oversized_current.get_stock() == 240,
		"Current saved stock is preserved without clamping to today's capacity.")

	var zero_legacy = PLAN_SCRIPT.new()
	seed(555)
	var expected_global_random: int = randi()
	seed(555)
	_check(zero_legacy.restore_from_save_value({"stock": 0}, 24, 8000),
		"Legacy zero stock migrates from the supplied checkpoint minute.")
	var actual_global_random: int = randi()
	_check(actual_global_random == expected_global_random, "Legacy validation does not advance the global RNG.")
	_check(zero_legacy.get_stock() == 0 and zero_legacy.is_respawn_pending(),
		"Legacy zero stock remains unavailable while its deterministic timer runs.")
	_check(zero_legacy.get_depleted_at_minute() == 8000 and zero_legacy.get_respawn_due_minute() == 12320,
		"Legacy zero stock gets a deterministic conservative 4320-minute migration delay.")
	var zero_codec = CITY_SAVE_VALUES.new()
	var zero_decoded: Variant = zero_codec.decode(JSON.parse_string(JSON.stringify(zero_codec.encode(zero_legacy.to_save_value()), "", true, true)))
	var zero_restored = PLAN_SCRIPT.new()
	_check(zero_codec.error.is_empty() and zero_restored.restore_from_save_value(zero_decoded, 24),
		"Migrated legacy output survives native CitySaveValues serialization and restore.")
	_check(zero_restored.get_respawn_due_minute() == 12320,
		"The migrated output retains its deadline through serialization.")
	_check(not zero_restored.try_refill(12319, true, 24) and zero_restored.get_stock() == 0,
		"Migrated legacy zero stock stays conserved until its deadline.")
