class_name WorkerData
extends Resource

enum Profession {NONE, LABORER, CRAFTER, HAULER, FARMER, SCAVENGER}
enum WorkStatus {IDLE, WORKING, RESTING, WAITING_FOR_RESOURCES, TRAVELLING}

@export var worker_id: String = ""
@export var display_name: String = ""
@export var profession: Profession = Profession.LABORER
@export var profession_xp: int = 0
@export var current_order_id: String = ""
@export var current_job_id: String = ""
@export var current_work_status: WorkStatus = WorkStatus.IDLE
# Empty is the deliberate legacy interpretation. Nonempty values contain only
# bounded data in world FEET coordinates, never scene paths or executable values.
@export var physical_approach: Dictionary = {}
@export_range(1, 3) var profession_star: int = 1
@export_range(0.0, 2.0, 0.01) var efficiency: float = 1.0
@export_range(0.0, 1.0, 0.01) var reliability: float = 1.0
@export var wage_shekel_per_day: int = 0
# Last prepaid period and last morning attempt. -1 preserves legacy saves/fixtures.
@export var payroll_start_day: int = -1
@export var payroll_paid_from_day: int = -1
@export var payroll_paid_until_day: int = -1
@export var payroll_period_rate: int = 0
@export var payroll_last_attempt_day: int = -1
# Zero/-1 identify legacy seven-day records; new contracts start at exact purchase time.
@export var payroll_contract_days: int = 0
@export var payroll_paid_start_minute: int = -1
@export var food_fulfilled: bool = false
@export var clothing_fulfilled: bool = false
@export var shelter_fulfilled: bool = false
@export_range(0.0, 1.0, 0.01) var satisfaction: float = 0.5

# Citizen linking and shared-state resolution

func get_linked_citizen() -> CitizenData:
	var clean_worker_id: String = worker_id.strip_edges()

	if clean_worker_id.is_empty():
		return null

	return CitizenManager.get_citizen(clean_worker_id)

func has_linked_citizen() -> bool:
	return get_linked_citizen() != null

func get_resolved_display_name() -> String:
	var citizen_data: CitizenData = get_linked_citizen()

	if citizen_data != null:
		return citizen_data.display_name

	return display_name

# Needs and performance

func are_basic_needs_fulfilled() -> bool:
	var citizen_data: CitizenData = get_linked_citizen()

	if citizen_data != null:
		return citizen_data.are_basic_needs_fulfilled()

	return food_fulfilled and clothing_fulfilled and shelter_fulfilled

func get_resolved_satisfaction() -> float:
	var citizen_data: CitizenData = get_linked_citizen()

	if citizen_data != null:
		return citizen_data.satisfaction

	return satisfaction

func get_resolved_reliability() -> float:
	var citizen_data: CitizenData = get_linked_citizen()

	if citizen_data != null:
		return citizen_data.reliability

	return reliability

func get_satisfaction_work_multiplier() -> float:
	var resolved_satisfaction: float = get_resolved_satisfaction()

	if resolved_satisfaction >= 0.75:
		return 1.05
	elif resolved_satisfaction >= 0.4:
		return 1.0
	else:
		return 0.85

func get_reliability_success_chance() -> float:
	var resolved_reliability: float = get_resolved_reliability()

	if resolved_reliability >= 0.75:
		return 0.95
	elif resolved_reliability >= 0.4:
		return 0.85
	else:
		return 0.65

# Work lifecycle

func is_waiting_for_first_payment() -> bool:
	return payroll_start_day >= 0 and payroll_paid_from_day < 0

func is_payroll_due(day: int) -> bool:
	return payroll_start_day >= 0 and payroll_start_day <= day and (payroll_paid_from_day < 0 or day > payroll_paid_until_day)

func is_payroll_blocked() -> bool:
	if payroll_start_day < 0:
		return false
	var now: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	return payroll_paid_from_day < 0 or now < get_paid_start_minute() or now >= get_paid_end_minute()

func get_payroll_unpaid_minutes(from_minute: int, to_minute: int) -> int:
	var elapsed: int = maxi(0, to_minute - from_minute)
	if payroll_start_day < 0:
		return 0
	if payroll_paid_from_day < 0:
		return elapsed
	var paid_start: int = get_paid_start_minute()
	var paid_end: int = get_paid_end_minute()
	var paid: int = maxi(0, mini(to_minute, paid_end) - maxi(from_minute, paid_start))
	return elapsed - paid

func get_paid_start_minute() -> int:
	return payroll_paid_start_minute if payroll_paid_start_minute >= 0 else payroll_paid_from_day * 1440 + 480

func get_paid_end_minute() -> int:
	# Preserve already-paid legacy 08:00 contracts; new packages end at shift start.
	return (payroll_paid_until_day + 1) * 1440 + (420 if payroll_contract_days > 0 else 480)

func get_onboarding_status() -> String:
	if not is_payroll_blocked():
		return ""
	return "Contract unpaid — renew in Worker Hub" if is_waiting_for_first_payment() else "Contract expired — renew in Worker Hub"

func is_working() -> bool:
	return current_work_status == WorkStatus.WORKING

func is_reserved() -> bool:
	return not current_order_id.is_empty() or is_working()

func set_work_activity(order_id: String, activity: WorkStatus) -> void:
	if order_id == current_order_id and not order_id.is_empty():
		current_work_status = activity

func get_work_activity_text() -> String:
	if is_payroll_blocked():
		return get_onboarding_status()
	match current_work_status:
		WorkStatus.WORKING:
			return "Working"
		WorkStatus.RESTING:
			return "Resting"
		WorkStatus.WAITING_FOR_RESOURCES:
			return "Waiting for resources"
		WorkStatus.TRAVELLING:
			return "Travelling"
	return "Idle"

func start_work(order_id: String, job_id: String) -> void:
	physical_approach.clear()
	current_order_id = order_id
	current_job_id = job_id
	current_work_status = WorkStatus.WORKING

func finish_work(order_id: String) -> void:
	if order_id != current_order_id:
		return

	current_job_id = ""
	current_order_id = ""
	current_work_status = WorkStatus.IDLE
	physical_approach.clear()

func begin_physical_approach(kind: String, task: String, owner: String, position: Vector2, target: Vector2) -> void:
	physical_approach = {"kind": kind, "task": task, "owner": owner, "position": position,
		"target": target, "arrived": false, "arrival_minute": -1}
	current_work_status = WorkStatus.TRAVELLING

func matches_physical_approach(kind: String, task: String, owner: String) -> bool:
	return physical_approach_valid(physical_approach) and not physical_approach.is_empty() and physical_approach.kind == kind and physical_approach.task == task and physical_approach.owner == owner

func mark_physical_arrival(task: String) -> bool:
	if not physical_approach_valid(physical_approach) or physical_approach.is_empty() or physical_approach.task != task or is_payroll_blocked():
		return false
	if physical_approach.position.distance_to(physical_approach.target) > 0.1:
		return false
	if not physical_approach.arrived:
		physical_approach.arrived = true
		physical_approach.arrival_minute = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	current_work_status = WorkStatus.WORKING
	return true

func get_arrived_paid_minutes(from_minute: int, to_minute: int, kind: String, task: String, owner: String) -> int:
	var eligible_from: int = from_minute
	if not physical_approach.is_empty():
		if not matches_physical_approach(kind, task, owner) or not physical_approach.arrived:
			return 0
		eligible_from = maxi(eligible_from, int(physical_approach.arrival_minute))
	if eligible_from >= to_minute:
		return 0
	# Intersect paid and arrived intervals once; overlapping blocks cannot add up.
	return to_minute - eligible_from - get_payroll_unpaid_minutes(eligible_from, to_minute)

static func physical_approach_valid(value: Dictionary) -> bool:
	if value.is_empty():
		return true
	var spec: Dictionary = {"kind": TYPE_STRING, "task": TYPE_STRING, "owner": TYPE_STRING,
		"position": TYPE_VECTOR2, "target": TYPE_VECTOR2, "arrived": TYPE_BOOL, "arrival_minute": TYPE_INT}
	if value.size() != spec.size():
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or not spec.has(key) or typeof(value[key]) != spec[key]:
			return false
	if value.kind not in ["site", "plot"]:
		return false
	for key: String in ["task", "owner"]:
		var text_value: String = value[key]
		if text_value.is_empty() or text_value.length() > 256:
			return false
		for index: int in text_value.length():
			var code: int = text_value.unicode_at(index)
			if code < 32 or code > 126 or code in [47, 92]:
				return false
	for key: String in ["position", "target"]:
		var point: Vector2 = value[key]
		if not is_finite(point.x) or not is_finite(point.y) or point.length() > 1000000.0:
			return false
	if value.arrived:
		# Resource workers retain their native work/idle wander after entering.
		return value.arrival_minute >= 0 and value.arrival_minute <= 1000000000 and (value.kind == "site" or value.position.distance_to(value.target) <= 0.1)
	return value.arrival_minute == -1
