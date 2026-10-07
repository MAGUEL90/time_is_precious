extends Node

## Session ledger. Hosted under WorkStateRuntime, never by a map or report panel.
## No disk-save changes. Clock schedules raids; real gameplay seconds resolve hits.
signal changed

const CONFIG: Script = preload("res://scenes/raid/raid_config.gd")
@export var config: Resource = preload("res://scenes/raid/raid_config.gd").new()
var storage: Node
var phase: String = "unbuilt"
var wall_hp: int = 0
var wall_level: int = 0
var _latest_minute: int = -1
var _attack_at: int = -1
var _elapsed: float = 0.0
var _hits: int = 0
var _start_hp: int = 0
var _attack_strength: int = 0
var _report: Dictionary = {}
var _report_sequence: int = 0
var _valid: bool = false
var _resolving: bool = false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_valid = config != null and config.get_script() == CONFIG and config.is_valid()
	set_process(false)
	if not _valid:
		push_error("Raid: invalid configuration; raids and construction are disabled.")
		return
	_rng.randomize()
	TimeComponentManager.time_changed.connect(_on_time_changed)
	_latest_minute = _now()

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func build_wall() -> bool:
	if not _valid or not config.instant_build_enabled or _resolving or phase == "attacking" or wall_hp > 0:
		return false
	wall_level = 1
	wall_hp = config.wall_max_hp
	# Initial construction starts the grace period. Rebuilding cannot reroll a raid.
	if phase == "unbuilt":
		phase = "safe"
		if config.raids_enabled:
			_schedule_from(maxi(_latest_minute, _now()))
	changed.emit()
	return true

func can_repair_wall() -> bool:
	return _valid and config.instant_repair_enabled and not _resolving and phase != "attacking" and wall_level > 0 and wall_hp > 0 and wall_hp < config.wall_max_hp

func repair_wall() -> bool:
	if not can_repair_wall():
		return false
	wall_hp = config.wall_max_hp
	# Repair does not reroll the threat, erase the report or upgrade the wall.
	changed.emit()
	return true

func reset_debug_wall() -> bool:
	if not OS.is_debug_build() or not _valid or _resolving or phase == "attacking" or wall_level == 0 or wall_hp <= 0 or wall_hp >= config.wall_max_hp:
		return false
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return false
	wall_hp = config.wall_max_hp
	changed.emit()
	return true

## Explicit developer playtest. No time skips, city seeding or production profile edits.
func start_debug_raid(breaching: bool) -> bool:
	if not OS.is_debug_build() or not _valid or _resolving or phase == "attacking" or wall_level == 0 or wall_hp <= 0:
		return false
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return false
	phase = "warning"
	_start_attack(config.wall_defend + (5 if breaching else 3))
	return phase == "attacking"

func get_status() -> Dictionary:
	if not _valid:
		return {"phase": "unbuilt", "hp": 0, "max_hp": 0, "level": 0, "defend": 0,
			"raids_enabled": false, "seconds_left": 0.0, "status_text": "Wall configuration unavailable.",
			"can_build": false, "can_repair": false}
	var message: String = "Wall ruins. Build the level 1 wall first."
	match phase:
		"safe":
			message = "No signs of raiders." if config.raids_enabled else "Level 1 wall built."
		"warning":
			message = "Raider tracks nearby. Prepare the city!"
		"attacking":
			message = "Raiders are attacking the castle wall!"
		"recovery":
			message = "Raiders have withdrawn. The city has time to recover."
	return {"phase": phase, "hp": wall_hp, "max_hp": config.wall_max_hp,
		"level": wall_level, "defend": config.wall_defend, "raids_enabled": config.raids_enabled or phase == "attacking",
		"seconds_left": maxf(0.0, config.duration_seconds - _elapsed) if phase == "attacking" else 0.0,
		"status_text": message, "can_build": _valid and config.instant_build_enabled and wall_hp == 0 and phase != "attacking" and not _resolving,
		"can_repair": can_repair_wall()}

func get_last_report() -> Dictionary:
	# Callers may format/edit their copy without changing the authoritative result.
	return _report.duplicate(true)

func _schedule_from(minute: int) -> void:
	var delay_days: int = _rng.randi_range(config.interval_min_days, config.interval_max_days)
	_attack_at = minute + delay_days * 1440

func _on_time_changed(day: int, hour: int, minute: int, _weather: String) -> void:
	var now: int = day * 1440 + hour * 60 + minute
	if not _valid or now <= _latest_minute:
		return
	_latest_minute = now
	if _resolving or not config.raids_enabled or phase in ["unbuilt", "attacking"] or _attack_at < 0:
		return
	if phase in ["safe", "recovery"] and now >= _attack_at - config.warning_days * 1440:
		phase = "warning"
		# A sleep/debug jump over the warning must still leave time to prepare.
		_attack_at = maxi(_attack_at, now + config.warning_days * 1440)
		changed.emit()
	elif phase == "warning" and now >= _attack_at:
		_start_attack()

func _start_attack(override_strength: int = -1) -> void:
	if phase != "warning" or _resolving:
		return
	phase = "attacking"
	_elapsed = 0.0
	_hits = 0
	_start_hp = wall_hp
	_attack_strength = override_strength if override_strength >= 0 else _rng.randi_range(config.attack_min, config.attack_max)
	set_process(true)
	if wall_hp == 0:
		_finish_attack(true)
	else:
		changed.emit()

func _process(delta: float) -> void:
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return
	advance_attack(delta)

func advance_attack(seconds: float) -> void:
	if phase != "attacking" or _resolving or not is_finite(seconds) or seconds <= 0.0:
		return
	var previous_seconds: int = ceili(config.duration_seconds - _elapsed)
	var previous_hp: int = wall_hp
	_elapsed = minf(config.duration_seconds, _elapsed + seconds)
	# Resolve every elapsed hit, including the final hit at exactly 60 seconds.
	while phase == "attacking" and float(_hits + 1) * config.hit_interval_seconds <= _elapsed + 0.000001:
		_hits += 1
		wall_hp = maxi(0, wall_hp - maxi(0, _attack_strength - config.wall_defend))
		if wall_hp == 0:
			_finish_attack(true)
			return
	if _elapsed >= config.duration_seconds:
		_finish_attack(false)
	elif previous_hp != wall_hp or previous_seconds != ceili(config.duration_seconds - _elapsed):
		changed.emit()

func _finish_attack(breached: bool) -> void:
	if phase != "attacking" or _resolving:
		return
	_resolving = true
	set_process(false)
	# Latch the transition before stock/citizen signals can reenter this ledger.
	phase = "recovery"
	_report_sequence += 1
	var result: Dictionary = {"id": _report_sequence, "outcome": "breached" if breached else "repelled",
		"day": TimeComponentManager.current_day, "hits": _hits, "wall_damage": _start_hp - wall_hp,
		"stolen": {}, "buildings_destroyed": {}, "satisfaction_drop": 0.0, "citizens_fled": []}
	if breached:
		# Only a standing wall can be destroyed; an existing ruin is not counted twice.
		if _start_hp > 0:
			result.buildings_destroyed = {"Castle wall": 1}
		if is_instance_valid(storage) and storage.has_method("take_raid_loot"):
			result.stolen = storage.take_raid_loot(config.theft_capacity, config.reserve_per_stack)
		var damage: Dictionary = _apply_population_losses()
		result.satisfaction_drop = damage.satisfaction_drop
		result.citizens_fled = damage.citizens_fled
	_report = result
	if config.raids_enabled:
		_schedule_from(maxi(_latest_minute, _now()))
	else:
		_attack_at = -1
	_resolving = false
	changed.emit()

func _apply_population_losses() -> Dictionary:
	var residents: Array[CitizenData] = CitizenManager.get_all_residents()
	var total_drop: float = 0.0
	for citizen: CitizenData in residents:
		var before: float = citizen.satisfaction
		citizen.satisfaction = minf(before, maxf(0.01, before - config.satisfaction_penalty))
		total_drop += before - citizen.satisfaction
	residents.sort_custom(func(a: CitizenData, b: CitizenData):
		if not is_equal_approx(a.satisfaction, b.satisfaction):
			return a.satisfaction < b.satisfaction
		return a.citizen_id < b.citizen_id
	)
	var fled: Array[String] = []
	var limit: int = mini(config.max_fleeing_residents, maxi(0, residents.size() - 1))
	for citizen: CitizenData in residents:
		if fled.size() >= limit:
			break
		# MVP departure excludes employed/assigned citizens and keeps a resident.
		if citizen.employment_status not in [CitizenData.EmploymentStatus.UNEMPLOYED, CitizenData.EmploymentStatus.APPLICANT] or WorkerDatabase.has_worker_data(citizen.citizen_id):
			continue
		if CitizenManager.leave_city(citizen.citizen_id):
			fled.append(citizen.display_name if not citizen.display_name.is_empty() else citizen.citizen_id)
	return {"satisfaction_drop": total_drop / residents.size() if not residents.is_empty() else 0.0, "citizens_fled": fled}
