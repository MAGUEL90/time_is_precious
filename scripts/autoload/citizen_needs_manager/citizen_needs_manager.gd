extends Node

signal needs_changed

const FOOD_SUPPLY_PER_CITIZEN_PER_DAY: int = 1
const FOOD_SUPPLY_PER_WORKER_PER_DAY: int = 1
const CLOTHING_LIFETIME_DAYS: int = 7
const MINUTES_PER_DAY: int = 1440
# Stabilize daily percentage-point arithmetic without rounding player data to whole percent.
const SATISFACTION_PRECISION: float = 0.000000001
# Provisional playtest values: each fulfilled need contributes equally to the
# condition value. Actual satisfaction moves at most five points per day.
const SATISFACTION_PER_FULFILLED_NEED: float = 0.33
const SATISFACTION_DAILY_STEP: float = 0.05

var last_food_fulfilled_count: int = 0
var last_food_unfulfilled_count: int = 0
var last_clothing_fulfilled_count: int = 0
var last_clothing_unfulfilled_count: int = 0
var last_shelter_capacity_fulfilled_count: int = 0
var last_shelter_capacity_unfulfilled_count: int = 0
var last_processed_day: int = -1
var last_food_processed_day: int = -1
var last_clothing_processed_day: int = -1
var clothing_allocations: Dictionary = {}
## A consumed ration covers this person until the absolute game minute expires.
var food_coverage_until: Dictionary = {}
## Absolute game minute through which gradual Satisfaction has already been applied.
var satisfaction_last_minute: Dictionary = {}
var last_needs_results: Dictionary = {}
var _processing_daily_needs: bool = false
var _processing_food: bool = false
var _processing_clothing: bool = false
var _daily_needs_retry_pending: bool = false
var _daily_needs_retry_after_frame: bool = false
var _food_recheck_pending: bool = false
var _satisfaction_retry_pending: bool = false
var _restore_roster_refresh_deferred: bool = false
var _restore_food_stock_points: int = -1

# Lifecycle and daily orchestration

func _ready() -> void:
	TimeComponentManager.new_day_started.connect(on_new_day_started)
	# time_changed is also a snapshot broadcast during Continue and does not
	# establish that a game minute elapsed. Only the minute signal does that.
	TimeComponentManager.minute_changed.connect(_on_minute_changed)
	call_deferred("_bind_live_sources")

func _checkpoint_busy() -> bool:
	var checkpoint: Node = get_node_or_null("/root/WorkStateRuntime/CitySave")
	return checkpoint != null and bool(checkpoint.get("_busy"))

func begin_checkpoint_restore() -> void:
	# A deferred notification belongs to the world that is about to be replaced.
	# Do not let it consume the newly restored checkpoint's stock afterwards.
	_food_recheck_pending = false
	# A zero-worker release can finish just after _busy drops. Its roster
	# notification is still part of restoration, not a new food delivery.
	_restore_roster_refresh_deferred = true
	_restore_food_stock_points = -1

func checkpoint_fields_restored() -> void:
	# Tool release can notify storage after a deferred zero-worker resignation.
	# It is not a food delivery if the restored food-point count is unchanged.
	var storage: Node = _get_city_food_storage()
	_restore_food_stock_points = int(storage.get_food_supply_points()) if is_instance_valid(storage) and storage.has_method("get_food_supply_points") else 0

func _on_minute_changed(_minute: int) -> void:
	if not _checkpoint_busy():
		_restore_roster_refresh_deferred = false
		# A synchronous owner may release a temporary midnight lock later in
		# new_day_started. Retry before this same minute is integrated so a bulk
		# skip does not silently move on to the next day with no daily ledger.
		if _daily_needs_retry_pending:
			process_daily_needs()
			if _daily_needs_retry_pending or _satisfaction_retry_pending:
				return
		_on_time_changed(TimeComponentManager.current_day, TimeComponentManager.current_hour, TimeComponentManager.current_minute, TimeComponentManager.current_weather)

func _bind_live_sources() -> void:
	if CitizenManager.has_signal("citizen_added") and not CitizenManager.citizen_added.is_connected(_on_citizen_added):
		CitizenManager.citizen_added.connect(_on_citizen_added)
	if CitizenManager.has_signal("citizen_left") and not CitizenManager.citizen_left.is_connected(_on_citizen_left):
		CitizenManager.citizen_left.connect(_on_citizen_left)
	var runtime: Node = get_node_or_null("/root/WorkStateRuntime")
	if runtime == null:
		return
	if not runtime.child_entered_tree.is_connected(_on_runtime_child_entered_tree):
		runtime.child_entered_tree.connect(_on_runtime_child_entered_tree)
	_connect_city_storage(runtime.get_node_or_null("CityToolStorage"))

func _on_runtime_child_entered_tree(child: Node) -> void:
	if child.name == "CityToolStorage":
		_connect_city_storage(child)

func _connect_city_storage(storage: Node) -> void:
	if is_instance_valid(storage) and storage.has_signal("changed") and not storage.is_connected("changed", _on_city_storage_changed):
		storage.connect("changed", _on_city_storage_changed)

func _on_city_storage_changed() -> void:
	# CityToolStorage emits while its transfer guard is held. Recheck after the
	# entire storage transaction has published and released that guard.
	if _checkpoint_busy():
		return
	if _restore_roster_refresh_deferred:
		var storage: Node = _get_city_food_storage()
		var points: int = int(storage.get_food_supply_points()) if is_instance_valid(storage) and storage.has_method("get_food_supply_points") else 0
		if points == _restore_food_stock_points:
			return
	_restore_roster_refresh_deferred = false
	if _food_recheck_pending:
		return
	_food_recheck_pending = true
	call_deferred("_run_food_recheck")

func _run_food_recheck() -> void:
	if not _food_recheck_pending:
		return
	_food_recheck_pending = false
	if _checkpoint_busy():
		return
	if _processing_daily_needs or _processing_food:
		_on_city_storage_changed()
		return
	_processing_daily_needs = true
	var now: int = _now_total_minutes()
	var changed: bool = _advance_satisfaction_to_minute(now)
	if _satisfaction_retry_pending:
		return
	_handle_zero_satisfaction_departures()
	changed = _refresh_live_service_flags(now) or changed
	process_daily_food_needs()
	changed = _refresh_live_service_flags(now) or changed
	_handle_zero_satisfaction_departures()
	_processing_daily_needs = false
	if changed:
		needs_changed.emit()

func _on_citizen_added(citizen: CitizenData) -> void:
	if citizen == null or _checkpoint_busy():
		return
	var now: int = _now_total_minutes()
	# A newcomer begins accruing at the arrival minute; the existing cohort first
	# settles through that same instant under its previous service state.
	if not _processing_daily_needs:
		_processing_daily_needs = true
		_advance_satisfaction_to_minute(now)
		if _satisfaction_retry_pending:
			return
		_processing_daily_needs = false
	var id: String = citizen.citizen_id.strip_edges()
	if not id.is_empty():
		satisfaction_last_minute[id] = now
	_refresh_after_roster_change()

func _on_citizen_left(citizen: CitizenData) -> void:
	if citizen == null:
		return
	if _checkpoint_busy():
		var departed_id: String = citizen.citizen_id.strip_edges()
		food_coverage_until.erase(departed_id)
		satisfaction_last_minute.erase(departed_id)
		clothing_allocations.erase(departed_id)
		return
	var now: int = _now_total_minutes()
	if not _processing_daily_needs:
		_processing_daily_needs = true
		_advance_satisfaction_to_minute(now)
		if _satisfaction_retry_pending:
			return
		_processing_daily_needs = false
	var id: String = citizen.citizen_id.strip_edges()
	if satisfaction_last_minute.has(id):
		var cursor: int = int(satisfaction_last_minute[id])
		if now > cursor:
			var before: float = _person_satisfaction(citizen)
			var after: float = _integrate_satisfaction(citizen, id, before, cursor, now)
			if _crosses_worker_boundary(citizen, id, before, after):
				WorkerDatabase.flush_before_daily_needs()
			_set_person_satisfaction(citizen, after)
	food_coverage_until.erase(id)
	satisfaction_last_minute.erase(id)
	clothing_allocations.erase(id)
	_refresh_after_roster_change()

func _refresh_after_roster_change() -> void:
	if _processing_daily_needs or _checkpoint_busy() or _restore_roster_refresh_deferred:
		return
	_processing_daily_needs = true
	var now: int = _now_total_minutes()
	var changed: bool = _refresh_live_service_flags(now)
	process_daily_food_needs()
	changed = _refresh_live_service_flags(now) or changed
	_handle_zero_satisfaction_departures()
	_processing_daily_needs = false
	if changed:
		needs_changed.emit()

func _on_time_changed(_day: int, _hour: int, _minute: int, _weather: String) -> void:
	if _processing_daily_needs or _satisfaction_retry_pending:
		return
	_processing_daily_needs = true
	var now: int = _now_total_minutes()
	var changed: bool = _advance_satisfaction_to_minute(now)
	if _satisfaction_retry_pending:
		return
	_handle_zero_satisfaction_departures()
	changed = _refresh_live_service_flags(now) or changed
	# A ration can be replenished immediately when its prior 24-hour entitlement
	# expires, including during an uninterrupted multi-day clock skip.
	process_daily_food_needs()
	changed = _refresh_live_service_flags(now) or changed
	_handle_zero_satisfaction_departures()
	_processing_daily_needs = false
	if changed:
		needs_changed.emit()

func _now_total_minutes() -> int:
	return TimeComponentManager.current_day * MINUTES_PER_DAY + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func on_new_day_started(_day: int) -> void:
	process_daily_needs()

func process_daily_needs() -> void:
	var day: int = TimeComponentManager.current_day
	if _processing_daily_needs or _processing_food or _processing_clothing or _satisfaction_retry_pending or day <= last_processed_day:
		return
	_processing_daily_needs = true
	if not WorkerDatabase.flush_before_daily_needs():
		# A nested delivery/payroll transaction owns the previous interval. Its
		# completion will retry the same daily calculation without double rations.
		_processing_daily_needs = false
		_daily_needs_retry_pending = true
		if not _daily_needs_retry_after_frame:
			_daily_needs_retry_after_frame = true
			get_tree().process_frame.connect(_retry_daily_needs_after_frame, CONNECT_ONE_SHOT)
		return
	_daily_needs_retry_pending = false
	var now: int = _now_total_minutes()
	# The prior minute belongs to the prior Satisfaction/service state. Flush it
	# before integration can cross a worker multiplier or zero boundary.
	_advance_satisfaction_to_minute(now, true)
	if _satisfaction_retry_pending:
		return
	# An older checkpoint may already contain a zero-Satisfaction person.
	_handle_zero_satisfaction_departures()
	last_needs_results.clear()
	process_daily_food_needs()
	process_daily_clothing_needs()
	process_daily_shelter_capacity_needs()
	_refresh_live_service_flags(now)

	process_daily_worker_needs()
	for recipient: Dictionary in _get_food_recipients():
		var person: Variant = recipient.person
		_apply_daily_effect_and_record(person, _get_person_id(person), day)

	CitizenManager.evaluate_daily_applications()
	last_processed_day = day
	_processing_daily_needs = false
	_handle_zero_satisfaction_departures()
	needs_changed.emit()


func _retry_daily_needs_after_frame() -> void:
	_daily_needs_retry_after_frame = false
	if _satisfaction_retry_pending:
		_satisfaction_retry_pending = false
		_processing_daily_needs = false
		_on_time_changed(TimeComponentManager.current_day, TimeComponentManager.current_hour, TimeComponentManager.current_minute, TimeComponentManager.current_weather)
		if TimeComponentManager.current_day > last_processed_day:
			process_daily_needs()
		return
	if _daily_needs_retry_pending:
		process_daily_needs()

# Need processing

func process_daily_worker_needs() -> void:
	# Residents receive capacity first; only unlinked workers use the remainder.
	var remaining_shelter_capacity: int = CityStockManager.shelter_capacity - last_shelter_capacity_fulfilled_count

	for worker in WorkerDatabase.get_all_workers():
		if not (worker is WorkerData):
			continue

		var worker_data: WorkerData = worker as WorkerData

		# Linked workers were already processed through their CitizenData.
		if worker_data.has_linked_citizen():
			continue

		if remaining_shelter_capacity > 0:
			remaining_shelter_capacity -= 1
			worker_data.shelter_fulfilled = true
		else:
			worker_data.shelter_fulfilled = false

func process_daily_food_needs() -> void:
	var day: int = TimeComponentManager.current_day
	if _processing_food:
		return
	_processing_food = true
	last_food_fulfilled_count = 0
	last_food_unfulfilled_count = 0
	var recipients: Array[Dictionary] = _get_food_recipients()
	var provider: Node = _get_city_food_storage()
	var available: int = int(provider.get_food_supply_points()) if is_instance_valid(provider) and provider.has_method("get_food_supply_points") else 0
	var points_to_consume: int = 0
	var planned_ids: Array[String] = []
	var now: int = _now_total_minutes()
	for recipient: Dictionary in recipients:
		var person: Variant = recipient.person
		var person_id: String = _get_person_id(person)
		var covered: bool = not person_id.is_empty() and int(food_coverage_until.get(person_id, -1)) > now
		if covered:
			continue
		var need: int = int(recipient.need)
		if available >= need:
			available -= need
			points_to_consume += need
			planned_ids.append(person_id)
	# One guarded city transaction for every newly covered person. A failed batch
	# publishes no partial food entitlement.
	var committed: bool = points_to_consume == 0
	if points_to_consume > 0 and is_instance_valid(provider):
		committed = bool(provider.consume_food_points(points_to_consume))
	if committed:
		for person_id: String in planned_ids:
			food_coverage_until[person_id] = now + MINUTES_PER_DAY
	for recipient: Dictionary in recipients:
		var person_id: String = _get_person_id(recipient.person)
		if not person_id.is_empty() and int(food_coverage_until.get(person_id, -1)) > now:
			last_food_fulfilled_count += 1
		else:
			last_food_unfulfilled_count += 1
	last_food_processed_day = day
	_processing_food = false

func _advance_satisfaction_to_minute(now: int, work_already_flushed: bool = false) -> bool:
	var recipients: Array[Dictionary] = _get_food_recipients()
	var plans: Array[Dictionary] = []
	var should_flush_work: bool = false
	for recipient: Dictionary in recipients:
		var person: Variant = recipient.person
		var id: String = _get_person_id(person)
		if id.is_empty():
			continue
		if not satisfaction_last_minute.has(id):
			satisfaction_last_minute[id] = now
			continue
		var cursor: int = int(satisfaction_last_minute[id])
		if cursor > now:
			cursor = now
		var before: float = _person_satisfaction(person)
		var after: float = _integrate_satisfaction(person, id, before, cursor, now)
		if after == before or now <= cursor:
			plans.append({"person": person, "id": id, "cursor": now, "value": before, "changed": false})
			continue
		if _crosses_worker_boundary(person, id, before, after):
			should_flush_work = true
		plans.append({"person": person, "id": id, "cursor": now, "value": after, "changed": true})
	if should_flush_work and not work_already_flushed and not WorkerDatabase.flush_before_daily_needs():
		_satisfaction_retry_pending = true
		_processing_daily_needs = false
		if not _daily_needs_retry_after_frame:
			_daily_needs_retry_after_frame = true
			get_tree().process_frame.connect(_retry_daily_needs_after_frame, CONNECT_ONE_SHOT)
		return false
	var changed: bool = false
	for plan: Dictionary in plans:
		var person: Variant = plan.person
		if bool(plan.changed):
			_set_person_satisfaction(person, float(plan.value))
			changed = true
		satisfaction_last_minute[str(plan.id)] = int(plan.cursor)
	return changed

func _integrate_satisfaction(person: Variant, person_id: String, initial: float, from_minute: int, to_minute: int) -> float:
	if to_minute <= from_minute:
		return initial
	var value: float = initial
	var cursor: int = from_minute
	while cursor < to_minute:
		var segment_end: int = to_minute
		var food_expiry: int = int(food_coverage_until.get(person_id, -1))
		if food_expiry > cursor and food_expiry < segment_end:
			segment_end = food_expiry
		var allocation_value: Variant = clothing_allocations.get(person_id, {})
		if allocation_value is Dictionary:
			var issued_value: Variant = allocation_value.get("issued_day", null)
			var expires_value: Variant = allocation_value.get("expires_day", null)
			if issued_value is int and expires_value is int:
				var issued_minute: int = int(issued_value) * MINUTES_PER_DAY
				var expires_minute: int = (int(expires_value) + 1) * MINUTES_PER_DAY
				if issued_minute > cursor and issued_minute < segment_end:
					segment_end = issued_minute
				if expires_minute > cursor and expires_minute < segment_end:
					segment_end = expires_minute
		var day: int = floori(float(cursor) / float(MINUTES_PER_DAY))
		var target: float = satisfaction_condition_value(
			_food_covered_at(person_id, cursor),
			not _get_valid_clothing_allocation(person_id, day).is_empty(),
			bool(person.shelter_fulfilled)
		)
		var elapsed: int = segment_end - cursor
		var movement: float = SATISFACTION_DAILY_STEP * float(elapsed) / float(MINUTES_PER_DAY)
		# Do not round each minute: equivalent elapsed intervals must produce the
		# same result regardless of frame/bulk subdivision. The target caps at .99,
		# while an existing 1.0 value decays at the ordinary daily rate.
		value = clampf(move_toward(value, target, movement), 0.0, 1.0)
		cursor = segment_end
	return value

func _food_covered_at(person_id: String, absolute_minute: int) -> bool:
	return int(food_coverage_until.get(person_id, -1)) > absolute_minute

func _person_satisfaction(person: Variant) -> float:
	return float(person.get_resolved_satisfaction()) if person is WorkerData else float(person.satisfaction)

func _set_person_satisfaction(person: Variant, value: float) -> void:
	if person is WorkerData:
		person.satisfaction = value
	else:
		person.satisfaction = value

func _crosses_worker_boundary(person: Variant, person_id: String, before: float, after: float) -> bool:
	var worker: WorkerData = person as WorkerData if person is WorkerData else WorkerDatabase.get_worker_data(person_id)
	if worker == null:
		return false
	return _work_satisfaction_band(before) != _work_satisfaction_band(after) or (before > 0.0 and after <= 0.0)

func _work_satisfaction_band(value: float) -> int:
	if value >= 0.75:
		return 2
	if value >= 0.4:
		return 1
	return 0

func _refresh_live_service_flags(now: int) -> bool:
	var changed: bool = false
	var recipients: Array[Dictionary] = _get_food_recipients()
	var active: Dictionary = {}
	var previous_shelter: Dictionary = {}
	var day: int = floori(float(now) / float(MINUTES_PER_DAY))
	for recipient: Dictionary in recipients:
		var person: Variant = recipient.person
		var id: String = _get_person_id(person)
		if id.is_empty():
			continue
		active[id] = true
		if not satisfaction_last_minute.has(id):
			satisfaction_last_minute[id] = now
		previous_shelter[id] = bool(person.shelter_fulfilled)
		var food: bool = _food_covered_at(id, now)
		var clothing: bool = not _get_valid_clothing_allocation(id, day).is_empty()
		if bool(person.food_fulfilled) != food:
			person.food_fulfilled = food
			changed = true
		if bool(person.clothing_fulfilled) != clothing:
			person.clothing_fulfilled = clothing
			changed = true
	for id_value: Variant in food_coverage_until.keys():
		if not active.has(id_value) or int(food_coverage_until[id_value]) <= now:
			food_coverage_until.erase(id_value)
	for id_value: Variant in satisfaction_last_minute.keys():
		if not active.has(id_value):
			satisfaction_last_minute.erase(id_value)
	for id_value: Variant in clothing_allocations.keys():
		if not active.has(id_value):
			clothing_allocations.erase(id_value)
	process_daily_shelter_capacity_needs()
	process_daily_worker_needs()
	for recipient: Dictionary in recipients:
		var person: Variant = recipient.person
		var id: String = _get_person_id(person)
		if previous_shelter.has(id) and bool(previous_shelter[id]) != bool(person.shelter_fulfilled):
			changed = true
	return changed

func _handle_zero_satisfaction_departures() -> void:
	# WorkerDatabase owns the safe cargo/assignment release path. Only after that
	# pass may an unlinked resident leave at zero Satisfaction.
	WorkerDatabase.resign_idle_workers_at_zero()
	for citizen: CitizenData in CitizenManager.get_all_residents().duplicate():
		if citizen.satisfaction <= 0.0 and not WorkerDatabase.has_worker_data(citizen.citizen_id):
			CitizenManager.leave_city(citizen.citizen_id)

func _get_city_food_storage() -> Node:
	# Summaries must not create a second provider or require the content scene to be open.
	return get_node_or_null("/root/WorkStateRuntime/CityToolStorage")

func _get_food_recipients() -> Array[Dictionary]:
	var recipients: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for citizen: CitizenData in CitizenManager.get_all_residents():
		var id: String = citizen.citizen_id.strip_edges()
		if id.is_empty() or seen_ids.has(id):
			continue
		seen_ids[id] = true
		recipients.append({"person": citizen, "need": FOOD_SUPPLY_PER_CITIZEN_PER_DAY})
	for worker: WorkerData in WorkerDatabase.get_all_workers():
		if worker == null or worker.has_linked_citizen():
			continue
		var id: String = worker.worker_id.strip_edges()
		if id.is_empty() or seen_ids.has(id):
			continue
		seen_ids[id] = true
		recipients.append({"person": worker, "need": FOOD_SUPPLY_PER_WORKER_PER_DAY})
	return recipients

func get_food_consumer_count() -> int:
	return _get_food_recipients().size()

func get_food_supply_summary(provider: Node = null) -> Dictionary:
	if provider == null:
		provider = _get_city_food_storage()
	var points: int = 0
	var portions: int = 0
	if is_instance_valid(provider) and provider.has_method("get_food_supply_points"):
		points = int(provider.get_food_supply_points())
		portions = int(provider.get_food_portion_points())
	var recipients: Array[Dictionary] = _get_food_recipients()
	var daily_need: int = 0
	for recipient: Dictionary in recipients:
		daily_need += int(recipient.need)
	@warning_ignore("integer_division")
	var full_days: int = points / daily_need if daily_need > 0 else -1
	return {
		"points": points,
		"daily_need": daily_need,
		"consumer_count": recipients.size(),
		"days_remaining": full_days,
		"portion_points": portions
	}

func process_daily_clothing_needs() -> void:
	var day: int = TimeComponentManager.current_day
	if _processing_clothing or day <= last_clothing_processed_day:
		return
	_processing_clothing = true
	last_clothing_fulfilled_count = 0
	last_clothing_unfulfilled_count = 0
	var recipients: Array[Dictionary] = _get_food_recipients()
	var active_ids: Dictionary = {}
	var replacement_ids: Array[String] = []
	for recipient: Dictionary in recipients:
		var person: Variant = recipient.person
		var person_id: String = _get_person_id(person)
		if person_id.is_empty():
			continue
		active_ids[person_id] = true
		if _get_valid_clothing_allocation(person_id, day).is_empty():
			replacement_ids.append(person_id)

	var provider: Node = _get_city_clothing_storage()
	var taken: Array[String] = []
	if not replacement_ids.is_empty() and provider != null and provider.has_method("take_clothing_items"):
		taken = provider.take_clothing_items(replacement_ids.size())
	var taken_index: int = 0
	for recipient: Dictionary in recipients:
		var person: Variant = recipient.person
		var person_id: String = _get_person_id(person)
		if person_id.is_empty():
			continue
		var allocation: Dictionary = _get_valid_clothing_allocation(person_id, day)
		if allocation.is_empty() and taken_index < taken.size():
			var item_id: String = str(taken[taken_index])
			taken_index += 1
			allocation = {
				"item_id": item_id,
				"issued_day": day,
				"expires_day": day + CLOTHING_LIFETIME_DAYS - 1
			}
			clothing_allocations[person_id] = allocation

		var fulfilled: bool = not allocation.is_empty()
		person.clothing_fulfilled = fulfilled
		if fulfilled:
			last_clothing_fulfilled_count += 1
		else:
			last_clothing_unfulfilled_count += 1
		if not fulfilled:
			clothing_allocations.erase(person_id)

	for allocation_id: String in clothing_allocations.keys():
		if not active_ids.has(allocation_id):
			clothing_allocations.erase(allocation_id)
	last_clothing_processed_day = day
	_processing_clothing = false

func _get_city_clothing_storage() -> Node:
	return get_node_or_null("/root/WorkStateRuntime/CityToolStorage")

func get_clothing_supply_summary(provider: Node = null) -> Dictionary:
	if provider == null:
		provider = _get_city_clothing_storage()
	var stock_items: int = 0
	if is_instance_valid(provider) and provider.has_method("get_clothing_item_count"):
		stock_items = maxi(0, int(provider.get_clothing_item_count()))
	var recipients: Array[Dictionary] = _get_food_recipients()
	var day: int = TimeComponentManager.current_day
	var covered_count: int = 0
	for recipient: Dictionary in recipients:
		var person_id: String = _get_person_id(recipient.person)
		if not person_id.is_empty() and not _get_valid_clothing_allocation(person_id, day).is_empty():
			covered_count += 1
	var replacement_need: int = recipients.size() - covered_count
	return {
		"stock_items": stock_items,
		"consumer_count": recipients.size(),
		"covered_count": covered_count,
		"current_valid_allocations": covered_count,
		"replacement_need": replacement_need,
		"can_cover_all": recipients.size() > 0 and stock_items >= replacement_need
	}

func get_worker_needs_summary(worker: WorkerData) -> Dictionary:
	var empty: Dictionary = _empty_needs_summary()
	if worker == null:
		return empty
	var resolved_citizen: CitizenData = worker.get_linked_citizen()
	var person_id: String = resolved_citizen.citizen_id if resolved_citizen != null else worker.worker_id.strip_edges()
	return get_person_needs_summary(person_id) if not person_id.is_empty() else empty

## A read-only individual view of actual current services. Shared reserves
## are reported separately and never treated as consumption.
func get_person_needs_summary(person_id: String) -> Dictionary:
	var id: String = person_id.strip_edges()
	if id.is_empty():
		return {}
	var citizen: CitizenData = CitizenManager.get_citizen(id)
	if citizen != null and citizen.population_status != CitizenData.PopulationStatus.RESIDENT:
		citizen = null
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if citizen == null and worker == null:
		return {}
	var person: Variant = citizen if citizen != null else worker
	var current_satisfaction: float = _person_satisfaction(person)
	var display_name: String = citizen.display_name if citizen != null else worker.get_resolved_display_name()
	var result: Dictionary = _empty_needs_summary()
	var saved: Variant = last_needs_results.get(id)
	if saved is Dictionary and bool(saved.get("evaluated", false)) and int(saved.get("day", -1)) == TimeComponentManager.current_day:
		result = saved.duplicate(true)
	result["name"] = display_name
	result["evaluated"] = true
	result["satisfaction"] = current_satisfaction
	result["food"] = bool(person.food_fulfilled)
	result["clothing"] = bool(person.clothing_fulfilled)
	result["shelter"] = bool(person.shelter_fulfilled)
	var allocation: Dictionary = _get_valid_clothing_allocation(id, TimeComponentManager.current_day)
	result["clothing_days_left"] = maxi(0, int(allocation.expires_day) - TimeComponentManager.current_day + 1) if not allocation.is_empty() else 0
	var missing: Array[String] = []
	if not bool(result.food):
		missing.append("Food")
	if not bool(result.clothing):
		missing.append("Clothing")
	if not bool(result.shelter):
		missing.append("Shelter")
	result["missing"] = missing
	var target: float = satisfaction_condition_value(bool(result.food), bool(result.clothing), bool(result.shelter))
	result["condition_target"] = target
	result["trend"] = _satisfaction_trend(current_satisfaction, target)
	var provider: Node = _get_city_food_storage()
	result["food_stock"] = maxi(0, int(provider.get_food_supply_points())) if is_instance_valid(provider) and provider.has_method("get_food_supply_points") else 0
	result["clothing_stock"] = maxi(0, int(provider.get_clothing_item_count())) if is_instance_valid(provider) and provider.has_method("get_clothing_item_count") else 0
	result["shelter_capacity"] = maxi(0, CityStockManager.shelter_capacity)
	return result

func satisfaction_condition_value(food: bool, clothing: bool, shelter: bool) -> float:
	var fulfilled_count: int = int(food) + int(clothing) + int(shelter)
	return snappedf(float(fulfilled_count) * SATISFACTION_PER_FULFILLED_NEED, SATISFACTION_PRECISION)

func _satisfaction_trend(current: float, target: float) -> String:
	if target < 0.0:
		return "unknown"
	if current < target - SATISFACTION_PRECISION:
		return "up"
	if current > target + SATISFACTION_PRECISION:
		return "down"
	return "stable"

func _empty_needs_summary() -> Dictionary:
	return {
		"evaluated": false,
		"day": -1,
		"food": false,
		"clothing": false,
		"shelter": false,
		"clothing_days_left": 0,
		"satisfaction": 0.0,
		"satisfaction_delta": 0.0,
		"missing": []
	}

func _get_person_id(person: Variant) -> String:
	if person is CitizenData:
		return person.citizen_id.strip_edges()
	if person is WorkerData:
		return person.worker_id.strip_edges()
	return ""

func _get_valid_clothing_allocation(person_id: String, day: int) -> Dictionary:
	if not clothing_allocations.has(person_id):
		return {}
	var allocation_value: Variant = clothing_allocations[person_id]
	if not allocation_value is Dictionary:
		return {}
	var allocation: Dictionary = allocation_value
	var item_id: String = str(allocation.get("item_id", ""))
	var issued_day: Variant = allocation.get("issued_day", null)
	var expires_day: Variant = allocation.get("expires_day", null)
	if item_id.is_empty() or not issued_day is int or not expires_day is int:
		return {}
	if int(issued_day) > day or int(expires_day) < day or int(expires_day) < int(issued_day):
		return {}
	return allocation

func _apply_daily_effect_and_record(person: Variant, person_id: String, day: int) -> void:
	if person_id.is_empty():
		return
	# Daily needs still publish a once-per-day ledger; Satisfaction itself is
	# integrated by elapsed game minutes and is never stepped here.
	var current_satisfaction: float = _person_satisfaction(person)
	var allocation: Dictionary = _get_valid_clothing_allocation(person_id, day)
	var missing: Array[String] = []
	if not bool(person.food_fulfilled):
		missing.append("Food")
	if allocation.is_empty() or not bool(person.clothing_fulfilled):
		missing.append("Clothing")
	if not bool(person.shelter_fulfilled):
		missing.append("Shelter")
	var clothing_days_left: int = 0
	if not allocation.is_empty():
		clothing_days_left = int(allocation.expires_day) - day + 1
	last_needs_results[person_id] = {
		"evaluated": true,
		"day": day,
		"food": bool(person.food_fulfilled),
		"clothing": bool(person.clothing_fulfilled),
		"shelter": bool(person.shelter_fulfilled),
		"clothing_days_left": maxi(0, clothing_days_left),
		"satisfaction": current_satisfaction,
		"satisfaction_delta": 0.0,
		"missing": missing
	}

func process_daily_shelter_capacity_needs() -> void:
	last_shelter_capacity_fulfilled_count = 0
	last_shelter_capacity_unfulfilled_count = 0

	var citizens: Array = CitizenManager.get_all_residents()
	var remaining_capacity: int = CityStockManager.shelter_capacity

	for citizen in citizens:
		if not (citizen is CitizenData):
			continue

		var citizen_data: CitizenData = citizen as CitizenData

		if remaining_capacity <= 0:
			last_shelter_capacity_unfulfilled_count += 1
			citizen_data.shelter_fulfilled = false
		else:
			last_shelter_capacity_fulfilled_count += 1
			remaining_capacity -= 1
			citizen_data.shelter_fulfilled = true

# Population summaries

func get_citizen_count() -> int:
	var citizens: Array = CitizenManager.get_all_residents()

	return citizens.size()

func get_daily_food_supply_need() -> int:
	var required: int = 0
	for recipient: Dictionary in _get_food_recipients():
		required += int(recipient.need)
	return required

func get_daily_clothing_supply_need() -> int:
	return int(get_clothing_supply_summary().replacement_need)

func get_daily_shelter_capacity_need() -> int:
	return get_citizen_count()

func get_average_satisfaction() -> float:
	var citizens: Array = CitizenManager.get_all_residents()
	var total_satisfaction: float = 0.0
	var valid_citizen: int = 0
	for citizen in citizens:
		if not (citizen is CitizenData):
			continue

		var citizen_data: CitizenData = citizen as CitizenData

		valid_citizen += 1
		total_satisfaction += citizen_data.satisfaction

	if valid_citizen == 0:
		return 0.0
	else:
		return total_satisfaction / valid_citizen
