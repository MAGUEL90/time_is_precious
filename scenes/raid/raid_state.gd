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
var _departure_at: int = -1
var _elapsed: float = 0.0
var _hits: int = 0
var _start_hp: int = 0
var _attack_strength: int = 0
var _report: Dictionary = {}
var _report_sequence: int = 0
var _valid: bool = false
var _resolving: bool = false
var _work_kind: String = ""
var _work_remaining: int = 0
var _work_total: int = 0
var _work_restore_hp: int = 0
var _work_paid: Dictionary = {}
var _starting_work: bool = false
var _refund_pending: bool = false
var last_work_message: String = ""
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
	if config != null and config.timed_work_enabled:
		return _start_timed_work("build")
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
	return _valid and (config.instant_repair_enabled or config.timed_work_enabled) and _work_kind.is_empty() and not _starting_work and not _resolving and phase != "attacking" and wall_level > 0 and wall_hp > 0 and wall_hp < config.wall_max_hp

func repair_wall() -> bool:
	if config != null and config.timed_work_enabled:
		return _start_timed_work("repair")
	if not can_repair_wall():
		return false
	wall_hp = config.wall_max_hp
	# Repair does not reroll the threat, erase the report or upgrade the wall.
	changed.emit()
	return true

func reset_debug_wall() -> bool:
	if not OS.is_debug_build() or not _valid or _resolving or _starting_work or phase == "attacking" or wall_level == 0 or wall_hp <= 0 or wall_hp >= config.wall_max_hp:
		return false
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning or not _work_kind.is_empty():
		return false
	wall_hp = config.wall_max_hp
	changed.emit()
	return true

## Debug journey uses the same normal-party clock and detection rules as gameplay.
func can_dispatch_debug_party() -> bool:
	if not OS.is_debug_build() or not _valid or _resolving or _starting_work or phase == "attacking" or wall_hp <= 0:
		return false
	if not config.raids_enabled or config.party_profile == null:
		return false
	var now: int = maxi(_latest_minute, _now())
	return _attack_at < 0 or _departure_at > now

func dispatch_debug_party() -> bool:
	if not can_dispatch_debug_party() or get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return false
	_departure_at = maxi(_latest_minute, _now())
	_attack_at = _departure_at + config.party_profile.travel_days * 1440
	phase = "safe"
	changed.emit()
	return true

## Instant combat fixture for automated tests only; not exposed in the Debug UI.
func start_debug_raid(breaching: bool) -> bool:
	if not OS.is_debug_build() or not _valid or _resolving or _starting_work or phase == "attacking" or wall_level == 0 or wall_hp <= 0:
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
		"status_text": message, "can_build": _valid and (config.instant_build_enabled or config.timed_work_enabled) and _work_kind.is_empty() and not _starting_work and wall_hp == 0 and phase != "attacking" and not _resolving,
		"can_repair": can_repair_wall(), "work_kind": _work_kind, "work_remaining": _work_remaining,
		"work_total": _work_total, "work_message": last_work_message,
		"travel_total_minutes": config.party_profile.travel_days * 1440 if config.party_profile != null and phase in ["warning", "attacking"] else 0,
		"arrival_minutes_remaining": maxi(0, _attack_at - maxi(_latest_minute, _now())) if phase == "warning" else 0}

func get_work_quote() -> Dictionary:
	var kind: String = "build" if wall_hp == 0 else "repair"
	var cost: Dictionary = {}
	var minutes: int = 0
	var reason: String = ""
	if not _valid:
		reason = "Wall work is unavailable."
	elif not _work_kind.is_empty():
		reason = "Wall work is already in progress."
	elif _starting_work or _resolving or phase == "attacking":
		reason = "Repairs must wait until the raiders leave."
	elif wall_hp >= config.wall_max_hp:
		reason = "The wall is in good condition. No repairs are needed."
	elif config.timed_work_enabled:
		minutes = config.build_minutes if kind == "build" else config.repair_minutes
		if kind == "build":
			cost = config.build_materials.duplicate(true)
		else:
			var steps: int = ceili(float(config.wall_max_hp - wall_hp) / config.repair_hp_per_step)
			for id: String in config.repair_materials_per_step:
				cost[id] = int(config.repair_materials_per_step[id]) * steps
		if not cost.is_empty() and (not is_instance_valid(storage) or not storage.can_consume_materials(cost)):
			reason = "Not enough materials in City Storage."
	elif not (config.instant_build_enabled if kind == "build" else config.instant_repair_enabled):
		reason = "Wall work is unavailable."
	return {"kind": kind, "materials": cost, "duration_minutes": minutes,
		"can_start": reason.is_empty(), "reason": reason}

func request_wall_work(quoted: Dictionary) -> bool:
	var current: Dictionary = get_work_quote()
	if not current.can_start or quoted.get("kind") != current.kind or quoted.get("materials") != current.materials or quoted.get("duration_minutes") != current.duration_minutes:
		last_work_message = "Wall conditions or supplies changed. Speak to Iddin-Sin again."
		changed.emit()
		return false
	return build_wall() if current.kind == "build" else repair_wall()

func _start_timed_work(kind: String) -> bool:
	var quote: Dictionary = get_work_quote()
	if not quote.can_start or quote.kind != kind:
		return false
	_starting_work = true
	var cost: Dictionary = quote.materials.duplicate(true)
	if not cost.is_empty() and not storage.consume_materials(cost):
		_starting_work = false
		return false
	_work_kind = kind
	_work_remaining = int(quote.duration_minutes)
	_work_total = _work_remaining
	_work_restore_hp = config.wall_max_hp - wall_hp
	_work_paid = cost
	_latest_minute = maxi(_latest_minute, _now())
	_starting_work = false
	last_work_message = "Wall construction started." if kind == "build" else "Wall repairs started."
	changed.emit()
	return true

func _advance_wall_work(minutes: int, until_minute: int = -1) -> bool:
	if _work_kind.is_empty() or _starting_work or _resolving or phase == "attacking":
		return false
	if _refund_pending:
		_refund_interrupted_repair()
		return true
	var completed_at: int = (until_minute if until_minute >= 0 else _latest_minute) - maxi(0, minutes - _work_remaining)
	_work_remaining = maxi(0, _work_remaining - minutes)
	if _work_remaining > 0:
		return true
	var kind: String = _work_kind
	_work_kind = ""
	_work_paid.clear()
	if kind == "build":
		wall_level = 1
		wall_hp = config.wall_max_hp
		if phase == "unbuilt":
			phase = "safe"
			if config.raids_enabled:
				_schedule_from(completed_at)
	else:
		wall_hp = mini(config.wall_max_hp, wall_hp + _work_restore_hp)
	last_work_message = "Wall construction complete." if kind == "build" else "Wall repairs complete."
	return true

func _refund_interrupted_repair() -> void:
	if not _work_paid.is_empty() and (not is_instance_valid(storage) or not storage.refund_materials(_work_paid)):
		_refund_pending = true
		last_work_message = "Repairs stopped. Materials are waiting to return to City Storage."
		return
	_refund_pending = false
	_work_kind = ""
	_work_remaining = 0
	_work_paid.clear()
	last_work_message = "Wall breached. Repairs cancelled; materials returned to City Storage."

func get_last_report() -> Dictionary:
	# Callers may format/edit their copy without changing the authoritative result.
	return _report.duplicate(true)

func _schedule_from(minute: int) -> void:
	if config.party_profile != null:
		_departure_at = minute + (config.recovery_days * 1440 if _report_sequence > 0 else 0)
		_attack_at = _departure_at + config.party_profile.travel_days * 1440
		return
	var delay_days: int = _rng.randi_range(config.interval_min_days, config.interval_max_days)
	_attack_at = minute + delay_days * 1440

func _on_time_changed(day: int, hour: int, minute: int, _weather: String) -> void:
	var now: int = day * 1440 + hour * 60 + minute
	if not _valid or now <= _latest_minute:
		return
	var work_until: int = now
	if config.party_profile != null and _attack_at >= 0 and phase != "attacking":
		work_until = mini(now, maxi(_latest_minute, _attack_at))
	var work_minutes: int = work_until - _latest_minute
	_latest_minute = now
	var work_changed: bool = _advance_wall_work(work_minutes, work_until)
	if work_changed:
		changed.emit()
	if _resolving or _starting_work or not config.raids_enabled or phase in ["unbuilt", "attacking"] or _attack_at < 0:
		return
	if config.party_profile != null:
		if phase in ["safe", "recovery"] and now >= _attack_at - config.warning_days * 1440:
			phase = "warning"
			changed.emit()
		if phase == "warning" and now >= _attack_at:
			_start_attack()
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
	var min_strength: int = config.party_profile.attack_min if config.party_profile != null else config.attack_min
	var max_strength: int = config.party_profile.attack_max if config.party_profile != null else config.attack_max
	_attack_strength = override_strength if override_strength >= 0 else _rng.randi_range(min_strength, max_strength)
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
	if breached and _work_kind == "repair":
		_refund_interrupted_repair()
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
