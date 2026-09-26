extends Node

signal needs_changed

const FOOD_SUPPLY_PER_CITIZEN_PER_DAY: int = 1
const FOOD_SUPPLY_PER_WORKER_PER_DAY: int = 1
const CLOTHING_LIFETIME_DAYS: int = 7

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
var last_needs_results: Dictionary = {}
var _processing_daily_needs: bool = false
var _processing_food: bool = false
var _processing_clothing: bool = false

# Lifecycle and daily orchestration

func _ready() -> void:
	TimeComponentManager.new_day_started.connect(on_new_day_started)

func on_new_day_started(_day: int) -> void:
	process_daily_needs()

func process_daily_needs() -> void:
	var day: int = TimeComponentManager.current_day
	if _processing_daily_needs or _processing_food or _processing_clothing or day <= last_processed_day:
		return
	_processing_daily_needs = true
	last_needs_results.clear()
	process_daily_food_needs()
	process_daily_clothing_needs()
	process_daily_shelter_capacity_needs()

	var citizens: Array = CitizenManager.get_all_residents()
	for citizen in citizens:
		if not (citizen is CitizenData):
			continue
		_apply_daily_effect_and_record(citizen, citizen.citizen_id, day)

	process_daily_worker_needs()
	CitizenManager.evaluate_daily_applications()
	last_processed_day = day
	_processing_daily_needs = false
	needs_changed.emit()

# Need processing

func process_daily_worker_needs() -> void:
	# Citizens consume supplies first; workers can only use what remains.
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

		_apply_daily_effect_and_record(worker_data, worker_data.worker_id, TimeComponentManager.current_day)

func process_daily_food_needs() -> void:
	var day: int = TimeComponentManager.current_day
	if _processing_food or day <= last_food_processed_day:
		return
	_processing_food = true
	last_food_fulfilled_count = 0
	last_food_unfulfilled_count = 0
	var recipients: Array[Dictionary] = _get_food_recipients()
	var provider: Node = _get_city_food_storage()
	var available: int = int(provider.get_food_supply_points()) if provider != null else 0
	var points_to_consume: int = 0
	var served: Array[bool] = []
	for recipient: Dictionary in recipients:
		var fulfilled: bool = available >= int(recipient.need)
		served.append(fulfilled)
		if fulfilled:
			available -= int(recipient.need)
			points_to_consume += int(recipient.need)
	# One guarded city transaction for the whole ration, with no Inventory staging.
	var committed: bool = points_to_consume == 0
	if points_to_consume > 0 and provider != null:
		committed = bool(provider.consume_food_points(points_to_consume))
	for index: int in range(recipients.size()):
		var fulfilled: bool = committed and served[index]
		recipients[index].person.food_fulfilled = fulfilled
		if fulfilled:
			last_food_fulfilled_count += 1
		else:
			last_food_unfulfilled_count += 1
	last_food_processed_day = day
	_processing_food = false

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
	empty["satisfaction"] = worker.get_resolved_satisfaction()
	empty["reliability"] = worker.get_resolved_reliability()
	var resolved_citizen: CitizenData = worker.get_linked_citizen()
	var person_id: String = resolved_citizen.citizen_id if resolved_citizen != null else worker.worker_id.strip_edges()
	if person_id.is_empty() or not last_needs_results.has(person_id):
		return empty
	var result: Dictionary = last_needs_results[person_id]
	if int(result.get("day", -1)) != TimeComponentManager.current_day:
		return empty
	return result.duplicate(true)

func _empty_needs_summary() -> Dictionary:
	return {
		"evaluated": false,
		"day": -1,
		"food": false,
		"clothing": false,
		"shelter": false,
		"clothing_days_left": 0,
		"satisfaction": 0.0,
		"reliability": 0.0,
		"satisfaction_delta": 0.0,
		"reliability_delta": 0.0,
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
	var satisfaction_before: float = float(person.satisfaction)
	var reliability_before: float = float(person.reliability)
	var fulfilled: bool = person.are_basic_needs_fulfilled()
	if fulfilled:
		person.satisfaction = clampf(person.satisfaction + 0.05, 0.01, 0.99)
		person.reliability = clampf(person.reliability + 0.03, 0.01, 0.99)
	else:
		person.satisfaction = clampf(person.satisfaction - 0.05, 0.01, 0.99)
		person.reliability = clampf(person.reliability - 0.05, 0.01, 0.99)
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
		"satisfaction": float(person.satisfaction),
		"reliability": float(person.reliability),
		"satisfaction_delta": float(person.satisfaction) - satisfaction_before,
		"reliability_delta": float(person.reliability) - reliability_before,
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
