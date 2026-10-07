extends Node

const RAID_CONFIG_SCRIPT: Script = preload("res://scenes/raid/raid_config.gd")
const RAID_STATE_SCRIPT: Script = preload("res://scenes/raid/raid_state.gd")
const CITIZEN_ACTOR_SCENE: PackedScene = preload("res://scenes/citizen_actor/citizen_actor.tscn")
const TEST_WORKER_ID: String = "raid_recovery_worker"
const TEST_LAST_RESIDENT_ID: String = "raid_last_unemployed_resident"
const TEST_ACTOR_LEAVER_ID: String = "raid_actor_leaver"
const TEST_ACTOR_WORKER_ID: String = "raid_actor_worker"

var failures: int = 0
var states: Array[Node] = []
var original_clock_processing: bool = true
var original_clock_paused: bool = false
var original_tree_paused: bool = false

func _ready() -> void:
	original_clock_processing = TimeComponentManager.is_processing()
	original_clock_paused = TimeComponentManager.is_paused
	original_tree_paused = get_tree().paused
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_run.call_deferred()

func _run() -> void:
	_test_debug_raid_guards()
	_test_debug_wall_reset()
	_test_light_raid_and_repair()
	_test_attack_strength_is_rolled_once()
	_test_heavy_breach_rebuild_and_last_resident()
	_test_single_unemployed_resident_reserve()
	await _test_citizen_departure_signal()
	_cleanup_fixture_citizens()
	for state: Node in states:
		if is_instance_valid(state):
			state.free()
	get_tree().paused = original_tree_paused
	TimeComponentManager.is_paused = original_clock_paused
	TimeComponentManager.set_process(original_clock_processing)
	print("RaidRecoveryRegressionTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _test_debug_raid_guards() -> void:
	var unbuilt_state: Node = _new_state(_fixture_config())
	_expect(unbuilt_state.call("start_debug_raid", false) == false
		and unbuilt_state.call("reset_debug_wall") == false
		and str(unbuilt_state.get("phase")) == "unbuilt",
		"Debug raid and wall reset are refused before the wall is built.")
	_expect(unbuilt_state.call("build_wall") == true,
		"The debug guard fixture can build its wall.")
	unbuilt_state.set("wall_hp", 40)
	get_tree().paused = true
	_expect(unbuilt_state.call("start_debug_raid", false) == false
		and unbuilt_state.call("reset_debug_wall") == false
		and str(unbuilt_state.get("phase")) == "safe",
		"Debug raids and wall resets are refused while the scene tree is paused.")
	get_tree().paused = false
	TimeComponentManager.is_paused = true
	_expect(unbuilt_state.call("start_debug_raid", false) == false
		and unbuilt_state.call("reset_debug_wall") == false,
		"Debug raids and wall resets are refused while the game clock is paused.")
	TimeComponentManager.is_paused = false
	unbuilt_state.set("wall_hp", 0)
	_expect(unbuilt_state.call("start_debug_raid", false) == false
		and unbuilt_state.call("reset_debug_wall") == false
		and str(unbuilt_state.get("phase")) == "safe",
		"Debug raids and wall resets are refused when the built wall has no HP.")
	unbuilt_state.free()

	var attacking_state: Node = _new_state(_fixture_config())
	_expect(attacking_state.call("build_wall") == true,
		"The active-raid guard fixture can build its wall.")
	attacking_state.set("wall_hp", 40)
	_expect(attacking_state.call("start_debug_raid", false) == true
		and str(attacking_state.get("phase")) == "attacking",
		"A debug light raid starts against a built, damaged wall.")
	attacking_state.set_process(false)
	attacking_state.call("advance_attack", 5.0)
	var hp_during_attack: int = int(attacking_state.get("wall_hp"))
	_expect(hp_during_attack == 37,
		"The debug light raid applies its synthetic three damage after one hit.")
	_expect(attacking_state.call("start_debug_raid", true) == false,
		"A second debug raid is refused while one is already attacking.")
	_expect(attacking_state.call("can_repair_wall") == false
		and attacking_state.call("repair_wall") == false
		and attacking_state.call("reset_debug_wall") == false
		and int(attacking_state.get("wall_hp")) == hp_during_attack,
		"Normal and debug repair are refused during an attack and cannot heal its damage.")

func _test_debug_wall_reset() -> void:
	var state: Node = _new_state(_fixture_config(false))
	_expect(state.call("build_wall") == true, "The debug reset fixture builds its wall.")
	var scheduled_attack: int = int(state.get("_attack_at"))
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var clock_before: Array[int] = _clock_snapshot()
	state.set("wall_hp", 21)
	_expect(state.call("can_repair_wall") == false and state.call("repair_wall") == false,
		"The production instant-repair option stays disabled in this debug reset fixture.")
	_expect(state.call("reset_debug_wall") == true and int(state.get("wall_hp")) == 50,
		"An explicit debug reset restores a damaged wall even when instant repair is disabled.")
	_expect(int(state.get("_attack_at")) == scheduled_attack
		and Inventory.items == inventory_before and _clock_snapshot() == clock_before,
		"Debug reset preserves the raid schedule and consumes no inventory or game time.")

func _test_light_raid_and_repair() -> void:
	var state: Node = _new_state(_fixture_config())
	_expect(state.call("build_wall") == true, "The light-raid fixture builds a level 1 wall.")
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var clock_before: Array[int] = _clock_snapshot()
	_expect(state.call("start_debug_raid", false) == true,
		"The debug light raid starts with its fixed synthetic strength.")
	state.set_process(false)
	_expect(int(state.get("_attack_strength")) == 5,
		"The light fixture attack is wall defense plus three synthetic damage.")
	state.call("advance_attack", 60.0)
	var report_before_repair: Dictionary = state.call("get_last_report")
	var scheduled_attack: int = int(state.get("_attack_at"))
	_expect(int(state.get("wall_hp")) == 14 and int(report_before_repair.get("hits", 0)) == 12
		and str(report_before_repair.get("outcome", "")) == "repelled",
		"Twelve light debug hits leave 14 of 50 HP and produce a repelled report.")
	_expect(state.call("can_repair_wall") == true and state.call("repair_wall") == true
		and int(state.get("wall_hp")) == 50,
		"An enabled instant repair restores the damaged level 1 wall to 50 HP.")
	_expect(int(state.get("wall_level")) == 1
		and int(state.get("_attack_at")) == scheduled_attack
		and state.call("get_last_report") == report_before_repair,
		"Repair preserves wall level, the next raid schedule, and the previous report.")
	_expect(state.call("can_repair_wall") == false and state.call("repair_wall") == false
		and state.call("reset_debug_wall") == false and int(state.get("wall_hp")) == 50,
		"A repeated repair at full HP fails without changing the wall.")
	_expect(Inventory.items == inventory_before and _clock_snapshot() == clock_before,
		"Instant repair consumes no player inventory and advances no game time.")

func _test_attack_strength_is_rolled_once() -> void:
	var state: Node = _new_state(_fixture_config(true, 4))
	_expect(state.call("build_wall") == true, "The normal-attack fixture builds its wall.")
	var rng: RandomNumberGenerator = state.get("_rng")
	rng.seed = 12345
	state.set("phase", "warning")
	state.call("_start_attack")
	state.set_process(false)
	var rolled_strength: int = int(state.get("_attack_strength"))
	var damage_per_hit: int = rolled_strength - 4
	_expect(rolled_strength >= 5 and rolled_strength <= 7,
		"A scheduled synthetic raid rolls one attack strength in its configured range.")
	for hit_index: int in range(1, 13):
		state.call("advance_attack", 5.0)
		_expect(int(state.get("wall_hp")) == 50 - hit_index * damage_per_hit,
			"Normal raid damage on hit %d uses the strength rolled at raid start." % hit_index)
	var report: Dictionary = state.call("get_last_report")
	_expect(int(report.get("hits", 0)) == 12
		and int(report.get("wall_damage", -1)) == damage_per_hit * 12,
		"The report totals twelve hits at one fixed attack strength.")

func _test_heavy_breach_rebuild_and_last_resident() -> void:
	var worker: CitizenData = _add_citizen(TEST_WORKER_ID, "Raid Worker", 0.7,
		CitizenData.EmploymentStatus.ASSIGNED)
	var worker_data: WorkerData = WorkerData.new()
	worker_data.worker_id = TEST_WORKER_ID
	WorkerDatabase.workers_by_id[TEST_WORKER_ID] = worker_data

	var state: Node = _new_state(_fixture_config())
	state.set("storage", null)
	var schedule_start: int = _now_minute()
	_expect(state.call("build_wall") == true, "The heavy-breach fixture builds its wall.")
	var first_schedule: int = int(state.get("_attack_at"))
	_expect(first_schedule >= schedule_start + 3 * 1440
		and first_schedule <= schedule_start + 5 * 1440,
		"The synthetic first schedule stays within the configured three-to-five-day test range.")
	_expect(state.call("start_debug_raid", true) == true,
		"The debug heavy raid starts with its fixed synthetic strength.")
	state.set_process(false)
	_expect(int(state.get("_attack_strength")) == 7,
		"The heavy fixture attack is wall defense plus five synthetic damage.")
	state.call("advance_attack", 49.999)
	_expect(int(state.get("_hits")) == 9 and int(state.get("wall_hp")) == 5,
		"Nine heavy hits leave five HP just before the tenth hit interval.")
	state.call("advance_attack", 0.001)
	var breached_report: Dictionary = state.call("get_last_report")
	_expect(int(state.get("wall_hp")) == 0 and int(breached_report.get("hits", 0)) == 10
		and int(breached_report.get("wall_damage", 0)) == 50
		and str(breached_report.get("outcome", "")) == "breached",
		"The tenth heavy hit at 50 seconds breaches the wall at exactly zero HP.")
	_expect(worker.population_status == CitizenData.PopulationStatus.RESIDENT
		and worker.employment_status == CitizenData.EmploymentStatus.ASSIGNED
		and breached_report.get("citizens_fled", []).is_empty()
		and CitizenManager.get_all_residents().size() == 1,
		"A breach protects the employed worker who is the city's only resident.")
	var next_schedule: int = int(state.get("_attack_at"))
	_expect(next_schedule >= _now_minute() + 3 * 1440
		and next_schedule <= _now_minute() + 5 * 1440,
		"The completed debug raid schedules a future attack using the configured synthetic interval.")
	_expect(state.call("build_wall") == true and int(state.get("wall_hp")) == 50
		and int(state.get("wall_level")) == 1,
		"A breached level 1 wall can be rebuilt to 50 HP without gaining levels.")
	_expect(int(state.get("_attack_at")) == next_schedule
		and state.call("get_last_report") == breached_report
		and int(state.get("_report_sequence")) == 1,
		"Rebuilding preserves the next scheduled raid and the breach report without rerolling.")
	_expect(state.call("can_repair_wall") == false and state.call("repair_wall") == false,
		"A fully rebuilt wall cannot receive extra repair HP.")
	_expect(state.call("start_debug_raid", false) == true,
		"A rebuilt wall can start its next explicit debug raid.")
	state.set_process(false)
	_expect(int(state.get("_report_sequence")) == 1 and int(state.get("wall_hp")) == 50,
		"Starting another raid does not reset the wall or resolve a report early.")
	CitizenManager.citizens_by_id.erase(TEST_WORKER_ID)
	WorkerDatabase.workers_by_id.erase(TEST_WORKER_ID)

func _test_single_unemployed_resident_reserve() -> void:
	var resident: CitizenData = _add_citizen(TEST_LAST_RESIDENT_ID, "Last Resident", 0.6)
	var state: Node = _new_state(_fixture_config())
	_expect(state.call("build_wall") == true, "The final-resident fixture builds its wall.")
	_expect(state.call("start_debug_raid", true) == true,
		"The final-resident fixture starts a deterministic heavy breach.")
	state.set_process(false)
	state.call("advance_attack", 50.0)
	var report: Dictionary = state.call("get_last_report")
	_expect(int(state.get("wall_hp")) == 0 and int(report.get("hits", 0)) == 10,
		"The final-resident fixture reaches a confirmed breach.")
	_expect(resident.population_status == CitizenData.PopulationStatus.RESIDENT
		and resident.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and report.get("citizens_fled", []).is_empty()
		and CitizenManager.get_all_residents().size() == 1,
		"A single unemployed resident is protected from being the final departure during a breach.")
	CitizenManager.citizens_by_id.erase(TEST_LAST_RESIDENT_ID)

func _test_citizen_departure_signal() -> void:
	var leaver: CitizenData = _add_citizen(TEST_ACTOR_LEAVER_ID, "Raid Leaver", 0.4)
	var worker: CitizenData = _add_citizen(TEST_ACTOR_WORKER_ID, "Raid Actor Worker", 0.5,
		CitizenData.EmploymentStatus.HIRED)
	var worker_data: WorkerData = WorkerData.new()
	worker_data.worker_id = TEST_ACTOR_WORKER_ID
	WorkerDatabase.workers_by_id[TEST_ACTOR_WORKER_ID] = worker_data
	var leaver_actor: Node2D = _attach_actor(leaver)
	var worker_actor: Node2D = _attach_actor(worker)
	await get_tree().process_frame
	_expect(is_instance_valid(leaver_actor) and is_instance_valid(worker_actor),
		"Citizen actors remain present before a departure signal.")
	_expect(CitizenManager.leave_city(TEST_ACTOR_WORKER_ID) == false
		and worker.population_status == CitizenData.PopulationStatus.RESIDENT,
		"CitizenManager refuses to remove a worker with WorkerDatabase data.")
	_expect(CitizenManager.leave_city(TEST_ACTOR_LEAVER_ID) == true,
		"CitizenManager removes an eligible nonworker and emits the departure signal.")
	await get_tree().process_frame
	_expect(not is_instance_valid(leaver_actor) and is_instance_valid(worker_actor),
		"The matching CitizenActor frees itself while the protected worker actor stays present.")
	_expect(CitizenManager.leave_city(TEST_ACTOR_LEAVER_ID) == false
		and leaver.population_status == CitizenData.PopulationStatus.LEFT_CITY,
		"A repeated departure request fails after the resident has left.")
	_expect(CitizenManager.get_all_residents().size() == 1
		and worker.population_status == CitizenData.PopulationStatus.RESIDENT,
		"The worker remains as the final resident after the other actor leaves.")
	worker_actor.free()

func _fixture_config(instant_repair_enabled: bool = true, wall_defend: int = 2) -> Resource:
	# Values here make a deterministic regression fixture, not a balance profile.
	var config: Resource = RAID_CONFIG_SCRIPT.new()
	config.set("raids_enabled", true)
	config.set("instant_build_enabled", true)
	config.set("instant_repair_enabled", instant_repair_enabled)
	config.set("wall_max_hp", 50) # Approved first wall playtest value.
	config.set("wall_defend", wall_defend) # Synthetic fixture defense.
	config.set("duration_seconds", 60.0) # Approved maximum raid duration.
	config.set("hit_interval_seconds", 5.0) # Approved hit interval.
	config.set("attack_min", 5) # Synthetic scheduled raid range.
	config.set("attack_max", 7)
	config.set("interval_min_days", 3) # Synthetic schedule range.
	config.set("interval_max_days", 5)
	config.set("warning_days", 1) # Synthetic warning lead.
	config.set("max_fleeing_residents", 2) # Synthetic population fixture.
	config.set("satisfaction_penalty", 0.1) # Synthetic population fixture.
	return config

func _new_state(config: Resource) -> Node:
	var state: Node = RAID_STATE_SCRIPT.new()
	state.set("config", config)
	add_child(state)
	states.append(state)
	return state

func _add_citizen(
	citizen_id: String,
	display_name: String,
	satisfaction: float,
	employment: CitizenData.EmploymentStatus = CitizenData.EmploymentStatus.UNEMPLOYED
) -> CitizenData:
	var citizen: CitizenData = CitizenData.new()
	citizen.citizen_id = citizen_id
	citizen.display_name = display_name
	citizen.satisfaction = satisfaction
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = employment
	CitizenManager.add_citizen(citizen)
	return citizen

func _attach_actor(citizen: CitizenData) -> Node2D:
	var actor: Node2D = CITIZEN_ACTOR_SCENE.instantiate()
	actor.set("movement_mode", 0)
	actor.call("setup", citizen)
	add_child(actor)
	return actor

func _now_minute() -> int:
	return TimeComponentManager.current_day * 1440 \
		+ TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _clock_snapshot() -> Array[int]:
	return [TimeComponentManager.current_day, TimeComponentManager.current_hour,
		TimeComponentManager.current_minute]

func _cleanup_fixture_citizens() -> void:
	for citizen_id: String in [TEST_WORKER_ID, TEST_LAST_RESIDENT_ID,
		TEST_ACTOR_LEAVER_ID, TEST_ACTOR_WORKER_ID]:
		CitizenManager.citizens_by_id.erase(citizen_id)
		WorkerDatabase.workers_by_id.erase(citizen_id)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
