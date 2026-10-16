extends Node

const STATE = preload("res://scenes/raid/raid_state.gd")
const CONFIG = preload("res://scenes/raid/raid_config.gd")
const STORAGE = preload("res://scenes/storage_destination/city_tool_storage.gd")
var failures: int = 0
var fixtures: Array[Node] = []

func _ready() -> void:
	call_deferred("_run")

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func make_raid(hp: int, stock: Dictionary, capacity: float = 10.0) -> Node:
	var storage = STORAGE.new()
	add_child(storage)
	storage.items = stock.duplicate(true)
	fixtures.append(storage)
	var state = STATE.new()
	state.config = CONFIG.new()
	state.config.wall_max_hp = maxi(50, hp)
	state.config.instant_build_enabled = true
	state.config.ranked_looting_enabled = true
	state.config.loot_capacity_weight = capacity
	state.config.loot_seconds_per_item = 1.0
	state.storage = storage
	add_child(state)
	fixtures.append(state)
	state.wall_level = 1
	state.wall_hp = hp
	state.phase = "warning"
	state._start_attack(5)
	state.set_process(false)
	return state

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var late = make_raid(50, {"egg": 100})
	late.advance_attack(49.0)
	expect(late.phase == "attacking" and late.storage.items.egg == 100, "Standing wall prevents theft.")
	late.advance_attack(1.0)
	expect(late.phase == "looting" and late._elapsed == 50.0 and late.storage.items.egg == 100,
		"A breach opens only the remaining ten seconds; it does not steal immediately.")
	expect(not late.build_wall() and not late.get_work_quote().can_start and not late.start_debug_raid(true),
		"Rebuilding and new raids cannot replace an active looting phase.")
	TimeComponentManager.is_paused = true
	late._process(3.0)
	expect(late._elapsed == 50.0, "Clock pause freezes looting.")
	TimeComponentManager.is_paused = false
	get_tree().paused = true
	late._process(3.0)
	expect(late._elapsed == 50.0, "Tree pause freezes looting.")
	get_tree().paused = false
	late.advance_attack(1.0)
	expect(late.storage.items.egg == 99 and late.get_status().stolen_so_far == {"egg": 1},
		"One elapsed loot second removes exactly one whole unit.")
	late.advance_attack(9.0)
	var report: Dictionary = late.get_last_report()
	expect(report.stolen == {"egg": 10} and report.looting_seconds == 10.0
		and report.breach_seconds == 50.0 and report.retreat_reason == "time_up",
		"A late breach permits ten thefts and reports actual time and items.")
	var bulk = make_raid(50, {"egg": 100})
	bulk.advance_attack(60.0)
	expect(bulk.get_last_report().stolen == report.stolen and bulk._elapsed == late._elapsed,
		"One large frame and incremental frames produce the same breach and loot window.")
	var early = make_raid(20, {"egg": 100})
	early.advance_attack(60.0)
	expect(early.get_last_report().stolen == {"egg": 40}, "An early breach leaves forty loot seconds.")
	var last_hit = make_raid(60, {"egg": 100})
	last_hit.advance_attack(60.0)
	expect(last_hit.phase == "recovery" and last_hit.get_last_report().stolen.is_empty(),
		"A breach on the final hit has no extra looting time.")
	var no_wall = make_raid(0, {"egg": 100})
	expect(no_wall.phase == "looting", "An already ruined wall lets raiders begin looting at arrival.")
	no_wall.advance_attack(60.0)
	expect(no_wall.get_last_report().stolen == {"egg": 60}
		and no_wall.get_last_report().buildings_destroyed.is_empty(), "Ruins give a full loot window without another destroyed wall.")
	var capacity = make_raid(0, {"stone": 100}, 2.0)
	capacity.advance_attack(60.0)
	expect(capacity.get_last_report().stolen == {"stone": 2} and capacity._elapsed == 2.0
		and capacity.get_last_report().retreat_reason == "capacity_full", "Full cargo causes early retreat.")
	var empty = make_raid(0, {})
	expect(empty.phase == "recovery" and empty._elapsed == 0.0,
		"An empty storage ends looting immediately without fabricated losses.")
	var shortage = make_raid(0, {"egg": 1})
	shortage.advance_attack(60.0)
	expect(shortage.storage.items.is_empty() and shortage.get_last_report().stolen == {"egg": 1}
		and shortage._elapsed == 1.0, "No protected reserve: the last available item can be stolen.")
	var overweight = make_raid(0, {"wood_log": 10}, 1.0)
	expect(overweight.phase == "recovery" and overweight.storage.items.wood_log == 10,
		"Raiders retreat if no item fits rather than exceeding capacity.")
	var zero_weight = make_raid(0, {"shekel": 1000})
	zero_weight.advance_attack(60.0)
	expect(zero_weight.get_last_report().stolen == {"shekel": 60},
		"Zero-weight items still cost time; one tick cannot drain the whole stack.")
	var reentrant = make_raid(0, {"egg": 100})
	reentrant.storage.changed.connect(func(): reentrant.advance_attack(60.0))
	reentrant.advance_attack(1.0)
	expect(reentrant.storage.items.egg == 99 and reentrant._elapsed == 1.0,
		"Storage callbacks cannot reenter the raid clock to steal extra items.")
	var snapshot: Dictionary = reentrant.storage.items.duplicate(true)
	reentrant.advance_attack(NAN)
	reentrant.advance_attack(-1.0)
	expect(reentrant.storage.items == snapshot, "Invalid elapsed times cannot change stock.")
	var citizen := CitizenData.new()
	citizen.citizen_id = "looting_test_resident"
	citizen.display_name = "Test resident"
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.satisfaction = 0.5
	CitizenManager.add_citizen(citizen)
	var penalty = make_raid(5, {"egg": 1})
	penalty.config.satisfaction_penalty = 0.05
	penalty.advance_attack(5.0)
	expect(is_equal_approx(citizen.satisfaction, 0.45), "Satisfaction drops at the breach, before looting finishes.")
	penalty.advance_attack(1.0)
	expect(is_equal_approx(citizen.satisfaction, 0.45), "A breached raid applies satisfaction loss once on resolution.")
	var penalty_report: Dictionary = penalty.get_last_report()
	penalty.advance_attack(60.0)
	penalty._finish_attack(true)
	expect(is_equal_approx(citizen.satisfaction, 0.45) and penalty.get_last_report() == penalty_report,
		"Repeated resolution cannot duplicate losses or reports.")
	for fixture: Node in fixtures:
		fixture.free()
	print("RaidLootingTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
