extends Node

## Session ledger. Hosted under WorkStateRuntime, never by a map or report panel.
## No disk-save changes. Clock schedules raids; real gameplay seconds resolve hits.
signal changed
signal wall_breached(raid_id: int)

const CONFIG: Script = preload("res://scenes/raid/raid_config.gd")
@export var config: Resource = preload("res://scenes/raid/raid_config.gd").new()
var storage: Node
var phase: String = "unbuilt"
var wall_hp: int = 0
var wall_level: int = 0
var watchtower_built: bool = false
var _work_base_max_hp: int = 0
var _latest_minute: int = -1
var _attack_at: int = -1
var _departure_at: int = -1
var _party: Dictionary = {}
var _expedition_sequence: int = 0
var _composition_stage: StringName
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
var _advancing: bool = false
var _breach_at: float = -1.0
var _next_loot_at: float = 0.0
var _loot_weight: float = 0.0
var _stolen: Dictionary = {}
var _retreat_reason: String = ""
var _breach_losses: Dictionary = {}

func is_raid_active() -> bool:
	return phase in ["attacking", "looting"]


func _ready() -> void:
	_valid = config != null and config.get_script() == CONFIG and config.is_valid()
	set_process(false)
	if not _valid:
		push_error("Raid: invalid configuration; raids and construction are disabled.")
		return
	_rng.randomize()
	if _uses_composition():
		_composition_stage = config.party_profile.composition_stages[0].id
	TimeComponentManager.time_changed.connect(_on_time_changed)
	_latest_minute = _now()

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func build_wall() -> bool:
	if config != null and config.timed_work_enabled:
		return _start_timed_work("build")
	if not _valid or not config.instant_build_enabled or _resolving or is_raid_active() or wall_hp > 0:
		return false
	wall_level = maxi(1, wall_level)
	wall_hp = get_wall_max_hp()
	# Initial construction starts the grace period. Rebuilding cannot reroll a raid.
	if phase == "unbuilt":
		phase = "safe"
		if config.raids_enabled:
			_schedule_from(maxi(_latest_minute, _now()))
	changed.emit()
	return true

func can_repair_wall() -> bool:
	return _valid and (config.instant_repair_enabled or config.timed_work_enabled) and _work_kind.is_empty() and not _starting_work and not _resolving and not is_raid_active() and wall_level > 0 and wall_hp > 0 and wall_hp < get_wall_max_hp()

func repair_wall() -> bool:
	if config != null and config.timed_work_enabled:
		return _start_timed_work("repair")
	if not can_repair_wall():
		return false
	wall_hp = get_wall_max_hp()
	# Repair does not reroll the threat, erase the report or upgrade the wall.
	changed.emit()
	return true

func reset_debug_wall() -> bool:
	if not OS.is_debug_build() or not _valid or _resolving or _starting_work or is_raid_active() or wall_level == 0 or wall_hp <= 0 or wall_hp >= get_wall_max_hp():
		return false
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning or not _work_kind.is_empty():
		return false
	wall_hp = get_wall_max_hp()
	changed.emit()
	return true

## Debug journey uses the same composition, clock and detection rules as gameplay.
func can_dispatch_debug_party() -> bool:
	if not OS.is_debug_build() or not _valid or _resolving or _starting_work or is_raid_active() or wall_hp <= 0:
		return false
	if not config.raids_enabled or config.party_profile == null:
		return false
	var now: int = maxi(_latest_minute, _now())
	return _attack_at < 0 or _departure_at > now

func dispatch_debug_party() -> bool:
	if not can_dispatch_debug_party() or get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return false
	_departure_at = maxi(_latest_minute, _now())
	if _uses_composition():
		_party.clear()
		_attack_at = -1
		_depart_if_due(_departure_at)
	else:
		_attack_at = _departure_at + config.party_profile.travel_days * 1440
	phase = "safe"
	_update_detection(_departure_at)
	changed.emit()
	return true

## Instant combat fixture for automated tests only; not exposed in the Debug UI.
func start_debug_raid(breaching: bool) -> bool:
	if not OS.is_debug_build() or not _valid or _resolving or _starting_work or is_raid_active() or wall_level == 0 or wall_hp <= 0:
		return false
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return false
	phase = "warning"
	_start_attack(get_wall_defend() + (5 if breaching else 3))
	return is_raid_active()

func get_wall_max_hp() -> int:
	return config.level_2_max_hp if wall_level >= 2 else config.wall_max_hp

func get_wall_defend() -> int:
	return config.level_2_defend if wall_level >= 2 else config.wall_defend

func get_warning_days() -> int:
	return config.watchtower_warning_days if watchtower_built else config.warning_days

func can_inspect_raiders() -> bool:
	return _valid and watchtower_built and config.party_profile != null and phase in ["warning", "attacking", "looting"] and (not _uses_composition() or not _party.is_empty())

func inspect_raiders() -> Dictionary:
	if not can_inspect_raiders():
		return {}
	var inspection: Dictionary = _party.duplicate(true) if _uses_composition() else {"type": config.party_profile.display_name}
	inspection.id = _expedition_sequence if _uses_composition() else _report_sequence + 1
	inspection.phase = phase
	inspection.arrival_minutes_remaining = maxi(0, _attack_at - maxi(_latest_minute, _now())) if phase == "warning" else 0
	inspection.travel_total_minutes = _get_travel_minutes()
	return inspection

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
		"looting":
			message = "The wall is breached. Raiders are looting City Storage!"
		"recovery":
			message = "Raiders have withdrawn. The city has time to recover."
	return {"phase": phase, "hp": wall_hp, "max_hp": get_wall_max_hp(),
		"level": wall_level, "defend": get_wall_defend(), "raids_enabled": config.raids_enabled or is_raid_active(),
		"seconds_left": maxf(0.0, config.duration_seconds - _elapsed) if is_raid_active() else 0.0,
		"status_text": message, "can_build": _valid and (config.instant_build_enabled or config.timed_work_enabled) and _work_kind.is_empty() and not _starting_work and wall_hp == 0 and not is_raid_active() and not _resolving,
		"watchtower_built": watchtower_built, "warning_days": get_warning_days(),
		"can_inspect": can_inspect_raiders(), "raider_type": config.party_profile.display_name if can_inspect_raiders() else "Unknown",
		"can_repair": can_repair_wall(), "work_kind": _work_kind, "work_remaining": _work_remaining,
		"work_total": _work_total, "work_message": last_work_message,
		"stolen_so_far": _stolen.duplicate(true), "loot_weight": _loot_weight,
		"storage_item_count": _storage_item_count(),
		"loot_capacity_weight": config.loot_capacity_weight,
		"loot_seconds_remaining": maxf(0.0, config.duration_seconds - _elapsed) if phase == "looting" else 0.0,
		"travel_total_minutes": _get_travel_minutes() if phase in ["warning", "attacking", "looting"] else 0,
		"arrival_minutes_remaining": maxi(0, _attack_at - maxi(_latest_minute, _now())) if phase == "warning" else 0}

func _storage_item_count() -> int:
	if not is_instance_valid(storage) or not storage.has_method("get_raid_loot_stock_count"):
		return 0
	return storage.get_raid_loot_stock_count(config.loot_capacity_weight)

func get_work_quote(requested_kind: String = "") -> Dictionary:
	var kind: String = requested_kind if not requested_kind.is_empty() else ("build" if wall_hp == 0 else "repair")
	var quote: Dictionary = {"kind": kind, "materials": {}, "duration_minutes": 0,
		"can_start": false, "reason": "", "source_level": wall_level, "source_hp": wall_hp}
	if not _valid or kind not in ["build", "repair", "upgrade", "watchtower"]:
		quote.reason = "Wall work is unavailable."
	elif not _work_kind.is_empty():
		quote.reason = "Wall work is already in progress."
	elif _starting_work or _resolving or is_raid_active():
		quote.reason = "Work must wait until the raiders leave."
	elif kind in ["upgrade", "watchtower"]:
		if not config.defense_improvements_enabled:
			quote.reason = "Improvements are unavailable."
		elif wall_hp <= 0:
			quote.reason = "Rebuild the wall first."
		elif kind == "upgrade" and wall_level >= 2:
			quote.reason = "The wall is already level 2."
		elif kind == "upgrade" and wall_hp < get_wall_max_hp():
			quote.reason = "Repair the wall before upgrading."
		elif kind == "watchtower" and watchtower_built:
			quote.reason = "The watchtower is already built."
		else:
			quote.materials = (config.upgrade_materials if kind == "upgrade" else config.watchtower_materials).duplicate(true)
			quote.duration_minutes = config.upgrade_minutes if kind == "upgrade" else config.watchtower_minutes
			if kind == "upgrade":
				quote.target_level = 2
				quote.target_hp = config.level_2_max_hp
				quote.target_defend = config.level_2_defend
			else:
				quote.warning_days = config.watchtower_warning_days
	elif (kind == "build" and wall_hp > 0) or (kind == "repair" and (wall_hp <= 0 or wall_hp >= get_wall_max_hp())):
		quote.reason = "The wall is in good condition. No repairs are needed." if wall_hp > 0 else "Rebuild the wall first."
	elif config.timed_work_enabled:
		quote.duration_minutes = config.build_minutes if kind == "build" else config.repair_minutes
		if kind == "build":
			quote.materials = config.build_materials.duplicate(true)
		else:
			var steps: int = ceili(float(get_wall_max_hp() - wall_hp) / config.repair_hp_per_step)
			for id: String in config.repair_materials_per_step:
				quote.materials[id] = int(config.repair_materials_per_step[id]) * steps
	elif not (config.instant_build_enabled if kind == "build" else config.instant_repair_enabled):
		quote.reason = "Wall work is unavailable."
	if str(quote.reason).is_empty() and not quote.materials.is_empty() and (not is_instance_valid(storage) or not storage.can_consume_materials(quote.materials)):
		quote.reason = "Not enough materials in City Storage."
	quote.can_start = str(quote.reason).is_empty()
	return quote

func request_wall_work(quoted: Dictionary) -> bool:
	var kind: String = str(quoted.get("kind", ""))
	var current: Dictionary = get_work_quote(kind)
	if kind.is_empty() or not current.can_start or quoted != current:
		last_work_message = "Wall conditions or supplies changed. Speak to Iddin-Sin again."
		changed.emit()
		return false
	if kind in ["upgrade", "watchtower"]:
		return _start_timed_work(kind)
	return build_wall() if kind == "build" else repair_wall()

func _start_timed_work(kind: String) -> bool:
	var quote: Dictionary = get_work_quote(kind)
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
	_work_restore_hp = get_wall_max_hp() - wall_hp
	_work_base_max_hp = get_wall_max_hp()
	_work_paid = cost
	_latest_minute = maxi(_latest_minute, _now())
	_starting_work = false
	last_work_message = {"build": "Wall construction started.", "repair": "Wall repairs started.", "upgrade": "Wall upgrade started.", "watchtower": "Watchtower construction started."}[kind]
	changed.emit()
	return true

func _advance_wall_work(minutes: int, until_minute: int = -1) -> bool:
	if _work_kind.is_empty() or _starting_work or _resolving or is_raid_active():
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
		wall_level = maxi(1, wall_level)
		wall_hp = get_wall_max_hp()
		if phase == "unbuilt":
			phase = "safe"
			if config.raids_enabled:
				_schedule_from(completed_at)
	elif kind == "upgrade":
		wall_level = 2
		# Preserve any damage suffered while this project was paused by a raid.
		wall_hp = mini(get_wall_max_hp(), wall_hp + get_wall_max_hp() - _work_base_max_hp)
	elif kind == "watchtower":
		watchtower_built = true
	else:
		wall_hp = mini(get_wall_max_hp(), wall_hp + _work_restore_hp)
	last_work_message = {"build": "Wall construction complete.", "repair": "Wall repairs complete.", "upgrade": "Wall upgrade complete.", "watchtower": "Watchtower construction complete."}[kind]
	return true

func _refund_interrupted_repair() -> void:
	if not _work_paid.is_empty() and (not is_instance_valid(storage) or not storage.refund_materials(_work_paid)):
		_refund_pending = true
		last_work_message = "Work stopped. Materials are waiting to return to City Storage."
		return
	_refund_pending = false
	_work_kind = ""
	_work_remaining = 0
	_work_paid.clear()
	last_work_message = "Wall breached. Work cancelled; materials returned to City Storage."

func get_last_report() -> Dictionary:
	# Callers may format/edit their copy without changing the authoritative result.
	return _report.duplicate(true)

func _uses_composition() -> bool:
	return config != null and config.party_profile != null and config.party_profile.composition_enabled

func _get_travel_minutes() -> int:
	if _uses_composition():
		return int(_party.get("travel_total_minutes", 0))
	return config.party_profile.travel_days * 1440 if config.party_profile != null else 0

## Future city progression calls this only when its own approved stage changes.
## Changing the stage never changes a party that has already departed.
func set_city_threat_stage(stage_id: StringName) -> bool:
	if not _valid or not _uses_composition() or config.party_profile.get_stage(stage_id) == null:
		return false
	_composition_stage = stage_id
	changed.emit()
	return true

func set_debug_threat_stage(stage_id: StringName) -> bool:
	if not OS.is_debug_build() or get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return false
	return set_city_threat_stage(stage_id)

func _schedule_from(minute: int) -> void:
	if config.party_profile != null:
		_departure_at = minute + (config.recovery_days * 1440 if _report_sequence > 0 else 0)
		if _uses_composition():
			_party.clear()
			_attack_at = -1
			_depart_if_due(maxi(_latest_minute, _now()))
		else:
			_attack_at = _departure_at + config.party_profile.travel_days * 1440
		return
	var delay_days: int = _rng.randi_range(config.interval_min_days, config.interval_max_days)
	_attack_at = minute + delay_days * 1440

func _depart_if_due(now: int) -> void:
	if not _uses_composition() or _departure_at < 0 or now < _departure_at or not _party.is_empty():
		return
	_party = config.party_profile.roll_party(_rng, _composition_stage)
	if _party.is_empty():
		push_error("Raid: the selected stage cannot generate a valid party.")
		return
	_expedition_sequence += 1
	_party.id = _expedition_sequence
	_attack_at = _departure_at + int(_party.travel_total_minutes)

func _update_detection(now: int) -> void:
	if phase in ["safe", "recovery"] and _attack_at >= 0 and now >= _attack_at - get_warning_days() * 1440:
		phase = "warning"
		changed.emit()

func _on_time_changed(day: int, hour: int, minute: int, _weather: String) -> void:
	var now: int = day * 1440 + hour * 60 + minute
	if not _valid or now <= _latest_minute:
		return
	_depart_if_due(now)
	var work_until: int = now
	if config.party_profile != null and _attack_at >= 0 and not is_raid_active():
		work_until = mini(now, maxi(_latest_minute, _attack_at))
	var work_minutes: int = work_until - _latest_minute
	_latest_minute = now
	var work_changed: bool = _advance_wall_work(work_minutes, work_until)
	if work_changed:
		changed.emit()
	if _resolving or _starting_work or not config.raids_enabled or phase in ["unbuilt", "attacking", "looting"] or _attack_at < 0:
		return
	if config.party_profile != null:
		_update_detection(now)
		if phase == "warning" and now >= _attack_at:
			_start_attack()
		return
	if phase in ["safe", "recovery"] and now >= _attack_at - get_warning_days() * 1440:
		phase = "warning"
		# A sleep/debug jump over the warning must still leave time to prepare.
		_attack_at = maxi(_attack_at, now + get_warning_days() * 1440)
		changed.emit()
	elif phase == "warning" and now >= _attack_at:
		_start_attack()

func _start_attack(override_strength: int = -1) -> void:
	if phase != "warning" or _resolving or (_uses_composition() and _party.is_empty() and override_strength < 0):
		return
	phase = "attacking"
	_elapsed = 0.0
	_hits = 0
	_breach_at = -1.0
	_next_loot_at = 0.0
	_loot_weight = 0.0
	_stolen.clear()
	_breach_losses.clear()
	_retreat_reason = ""
	_start_hp = wall_hp
	var min_strength: int = config.party_profile.attack_min if config.party_profile != null else config.attack_min
	var max_strength: int = config.party_profile.attack_max if config.party_profile != null else config.attack_max
	_attack_strength = override_strength if override_strength >= 0 else (int(_party.attack_strength) if _uses_composition() else _rng.randi_range(min_strength, max_strength))
	set_process(true)
	if wall_hp == 0:
		_begin_looting()
	else:
		changed.emit()

func _process(delta: float) -> void:
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return
	advance_attack(delta)

func advance_attack(seconds: float) -> void:
	if not is_raid_active() or _advancing or _resolving or not is_finite(seconds) or seconds <= 0.0:
		return
	_advancing = true
	_advance_raid_time(seconds)
	_advancing = false

func _advance_raid_time(seconds: float) -> void:
	var target: float = minf(config.duration_seconds, _elapsed + seconds)
	var previous_seconds: int = ceili(config.duration_seconds - _elapsed)
	var previous_hp: int = wall_hp
	# Advance to each hit, so an early breach in a large frame retains its true loot window.
	while phase == "attacking" and float(_hits + 1) * config.hit_interval_seconds <= target + 0.000001:
		_elapsed = minf(target, float(_hits + 1) * config.hit_interval_seconds)
		_hits += 1
		wall_hp = maxi(0, wall_hp - maxi(0, _attack_strength - get_wall_defend()))
		if wall_hp == 0:
			_begin_looting()
	if phase == "looting":
		_advance_looting(target)
	elif phase == "attacking":
		_elapsed = target
		if _elapsed >= config.duration_seconds:
			_retreat_reason = "wall_held"
			_finish_attack(false)
		elif previous_hp != wall_hp or previous_seconds != ceili(config.duration_seconds - _elapsed):
			changed.emit()

func _begin_looting() -> void:
	_breach_at = _elapsed
	if _start_hp > 0:
		wall_breached.emit(_report_sequence + 1)
	if not config.ranked_looting_enabled:
		_finish_attack(true)
		return
	phase = "looting"
	_resolving = true
	_breach_losses = _apply_population_losses()
	_resolving = false
	if _work_kind in ["repair", "upgrade", "watchtower"]:
		_refund_interrupted_repair()
	_next_loot_at = _elapsed + config.loot_seconds_per_item
	if _elapsed >= config.duration_seconds:
		_retreat_reason = "time_up"
		_finish_attack(true)
	elif not _has_carryable_loot():
		_retreat_reason = "no_carryable_loot"
		_finish_attack(true)
	else:
		changed.emit()

func _has_carryable_loot() -> bool:
	return is_instance_valid(storage) and storage.has_method("peek_raid_loot") and not storage.peek_raid_loot(maxf(0.0, config.loot_capacity_weight - _loot_weight), config.loot_preference).is_empty()

func _advance_looting(target: float) -> void:
	while phase == "looting" and _next_loot_at <= target + 0.000001:
		_elapsed = minf(target, _next_loot_at)
		_next_loot_at += config.loot_seconds_per_item
		var receipt: Dictionary = storage.take_ranked_raid_item(maxf(0.0, config.loot_capacity_weight - _loot_weight), config.loot_preference) if is_instance_valid(storage) else {}
		if receipt.is_empty():
			_retreat_reason = "no_carryable_loot"
			_finish_attack(true)
			return
		var id: String = str(receipt.item_id)
		_stolen[id] = int(_stolen.get(id, 0)) + 1
		_loot_weight += float(receipt.weight)
		if _loot_weight >= config.loot_capacity_weight - 0.000001:
			_retreat_reason = "capacity_full"
			_finish_attack(true)
			return
		if not _has_carryable_loot():
			_retreat_reason = "no_carryable_loot"
			_finish_attack(true)
			return
	if phase != "looting":
		return
	_elapsed = target
	if _elapsed >= config.duration_seconds:
		_retreat_reason = "time_up"
		_finish_attack(true)
	else:
		changed.emit()

func _finish_attack(breached: bool) -> void:
	if not is_raid_active() or _resolving:
		return
	_resolving = true
	set_process(false)
	# Latch the transition before stock/citizen signals can reenter this ledger.
	phase = "recovery"
	_report_sequence += 1
	var result: Dictionary = {"id": _report_sequence, "outcome": "breached" if breached else "repelled",
		"day": TimeComponentManager.current_day, "hits": _hits, "wall_damage": _start_hp - wall_hp,
		"stolen": _stolen.duplicate(true) if config.ranked_looting_enabled else {}, "buildings_destroyed": {}, "satisfaction_drop": 0.0, "citizens_fled": [],
		"breach_seconds": _breach_at, "looting_seconds": maxf(0.0, _elapsed - _breach_at) if _breach_at >= 0.0 else 0.0,
		"loot_weight": _loot_weight, "loot_capacity_weight": config.loot_capacity_weight,
		"loot_preference": config.loot_preference, "retreat_reason": _retreat_reason}
	if breached:
		# Only a standing wall can be destroyed; an existing ruin is not counted twice.
		if _start_hp > 0:
			result.buildings_destroyed = {"Castle wall": 1}
		if not config.ranked_looting_enabled and is_instance_valid(storage) and storage.has_method("take_raid_loot"):
			result.stolen = storage.take_raid_loot(config.theft_capacity, config.reserve_per_stack)
		var damage: Dictionary = _breach_losses if config.ranked_looting_enabled else _apply_population_losses()
		result.satisfaction_drop = damage.satisfaction_drop
		result.residents_affected = damage.residents_affected
		result.citizens_fled = damage.citizens_fled
	if breached and _work_kind in ["repair", "upgrade", "watchtower"]:
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
	return {"residents_affected": residents.size(), "satisfaction_drop": total_drop / residents.size() if not residents.is_empty() else 0.0, "citizens_fled": fled}
