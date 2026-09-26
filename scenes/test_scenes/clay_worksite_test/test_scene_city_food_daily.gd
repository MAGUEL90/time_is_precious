extends Node

const CITY_TOOL_STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const READY_BREAD: String = "barley_bread"
const READY_CHICKEN: String = "roasted_drumstick"
const RAW_GRAIN: String = "barley_grain_sack"
const RAW_EGG: String = "egg"
const RAW_MEAT: String = "butchers_cut"

var failures: int = 0
var provider: Node
var created_provider: bool = false
var detached_original_provider: bool = false
var original_citizens: Dictionary = {}
var original_workers: Dictionary = {}
var original_dismissed_workers: Dictionary = {}
var original_inventory: Dictionary = {}
var original_city_stock: Dictionary = {}
var original_clock: Dictionary = {}
var original_needs_state: Dictionary = {}
var original_provider_state: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_snapshot_global_state()
	_prepare_provider()
	_test_summary_without_provider_is_read_only()
	_test_zero_consumers_summary()
	_test_consumer_identity_and_priority()
	_test_ready_food_conservation_and_remainder()
	_test_shortage_accounting()
	_test_duplicate_day_and_reentrant_callback()
	await _test_multi_day_time_skip()
	_test_summary_refreshes_after_stock_addition()
	_restore_global_state()

	if failures > 0:
		push_error("CityFoodDailyTest FAILED (%d failure(s))" % failures)
		get_tree().quit(1)
		return

	print("CityFoodDailyTest PASSED")
	get_tree().quit(0)


func _snapshot_global_state() -> void:
	original_citizens = CitizenManager.citizens_by_id.duplicate(true)
	original_workers = WorkerDatabase.workers_by_id.duplicate(true)
	original_dismissed_workers = WorkerDatabase.dismissed_workers.duplicate(true)
	original_inventory = Inventory.items.duplicate(true)
	original_city_stock = {
		"food_supply": CityStockManager.food_supply,
		"clothing_supply": CityStockManager.clothing_supply,
		"treasury_shekel": CityStockManager.treasury_shekel,
		"shelter_capacity": CityStockManager.shelter_capacity
	}
	original_clock = {
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"weather": TimeComponentManager.current_weather,
		"paused": TimeComponentManager.is_paused,
		"tree_paused": get_tree().paused
	}
	original_needs_state = {
		"last_food_fulfilled_count": CitizenNeedsManager.last_food_fulfilled_count,
		"last_food_unfulfilled_count": CitizenNeedsManager.last_food_unfulfilled_count,
		"last_clothing_fulfilled_count": CitizenNeedsManager.last_clothing_fulfilled_count,
		"last_clothing_unfulfilled_count": CitizenNeedsManager.last_clothing_unfulfilled_count,
		"last_shelter_capacity_fulfilled_count": CitizenNeedsManager.last_shelter_capacity_fulfilled_count,
		"last_shelter_capacity_unfulfilled_count": CitizenNeedsManager.last_shelter_capacity_unfulfilled_count,
		"last_processed_day": CitizenNeedsManager.last_processed_day,
		"last_food_processed_day": CitizenNeedsManager.last_food_processed_day,
		"last_clothing_processed_day": CitizenNeedsManager.last_clothing_processed_day,
		"_processing_clothing": CitizenNeedsManager._processing_clothing,
		"clothing_allocations": CitizenNeedsManager.clothing_allocations.duplicate(true),
		"last_needs_results": CitizenNeedsManager.last_needs_results.duplicate(true)
	}

	provider = get_node_or_null("/root/WorkStateRuntime/CityToolStorage")
	if is_instance_valid(provider):
		original_provider_state = _snapshot_provider(provider)


func _prepare_provider() -> void:
	if not is_instance_valid(provider):
		provider = CITY_TOOL_STORAGE_SCRIPT.new()
		provider.name = "CityToolStorage"
		WorkStateRuntime.add_child(provider)
		created_provider = true

	_expect(
		provider.has_method("get_food_supply_points")
			and provider.has_method("get_food_portion_points")
			and provider.has_method("consume_food_points"),
		"CityToolStorage must expose the physical food provider contract."
	)
	if provider.get("items") is Dictionary:
		provider.set("items", {})
	if provider.get("food_portions") is Dictionary:
		provider.set("food_portions", {})


func _snapshot_provider(target: Node) -> Dictionary:
	var snapshot: Dictionary = {}
	for property_name: String in ["food_portions", "items", "units"]:
		var value: Variant = target.get(property_name)
		if value is Dictionary:
			snapshot[property_name] = value.duplicate(true)
	var sequence: Variant = target.get("_unit_sequence")
	if sequence is int:
		snapshot["_unit_sequence"] = int(sequence)
	return snapshot


func _restore_provider(target: Node, snapshot: Dictionary) -> void:
	if not is_instance_valid(target):
		return
	for property_name: String in ["food_portions", "items", "units"]:
		if snapshot.has(property_name) and target.get(property_name) is Dictionary:
			target.set(property_name, snapshot[property_name].duplicate(true))
	if snapshot.has("_unit_sequence") and target.get("_unit_sequence") is int:
		target.set("_unit_sequence", int(snapshot["_unit_sequence"]))


func _test_summary_without_provider_is_read_only() -> void:
	_clear_people()
	_set_food({READY_BREAD: 4})
	var existing_provider: Node = provider
	if is_instance_valid(existing_provider) and existing_provider.get_parent() != null:
		existing_provider.get_parent().remove_child(existing_provider)
		detached_original_provider = true

	var before_children: int = WorkStateRuntime.get_child_count()
	var summary: Dictionary = CitizenNeedsManager.get_food_supply_summary()
	_expect(summary.points == 0 and summary.portion_points == 0, "Missing provider summary must report zero physical food.")
	_expect(WorkStateRuntime.get_child_count() == before_children, "Missing provider summary must not create a CityToolStorage node.")
	_expect(WorkStateRuntime.get_node_or_null("CityToolStorage") == null, "Missing provider summary must remain read-only.")

	if detached_original_provider:
		WorkStateRuntime.add_child(existing_provider)
		detached_original_provider = false


func _test_zero_consumers_summary() -> void:
	_clear_people()
	_set_food({READY_BREAD: 4, READY_CHICKEN: 2})
	var summary: Dictionary = CitizenNeedsManager.get_food_supply_summary(provider)
	_expect(CitizenNeedsManager.get_food_consumer_count() == 0, "No residents or legacy workers must yield zero food consumers.")
	_expect(summary.consumer_count == 0 and summary.daily_need == 0 and summary.days_remaining == -1, "Zero consumers must report no daily need without a finite days estimate.")


func _test_consumer_identity_and_priority() -> void:
	_clear_people()
	var resident: CitizenData = _make_resident("food_resident")
	var linked_worker: WorkerData = _make_worker("food_resident")
	var dismissed_worker: WorkerData = _make_worker("dismissed_food_worker")
	var legacy_worker: WorkerData = _make_worker("legacy_food_worker")
	var legacy_alias_worker: WorkerData = _make_worker("legacy_food_worker")
	CitizenManager.add_citizen(resident)
	WorkerDatabase.workers_by_id[linked_worker.worker_id] = linked_worker
	WorkerDatabase.dismissed_workers[dismissed_worker.worker_id] = dismissed_worker
	WorkerDatabase.workers_by_id[legacy_worker.worker_id] = legacy_worker
	WorkerDatabase.workers_by_id["legacy_food_alias_key"] = legacy_alias_worker

	var summary: Dictionary = CitizenNeedsManager.get_food_supply_summary(provider)
	_expect(CitizenNeedsManager.get_citizen_count() == 1, "Resident-only citizen count must exclude legacy workers.")
	_expect(CitizenNeedsManager.get_food_consumer_count() == 2, "Linked workers, dismissed workers, and duplicate legacy worker IDs must not add duplicate food consumers; one legacy worker must count.")
	_expect(summary.consumer_count == 2 and summary.daily_need == 2, "Food summary must include one resident and one unlinked legacy worker.")

	_set_food({READY_BREAD: 1, READY_CHICKEN: 1})
	_set_day_for_food(TimeComponentManager.current_day + 1)
	CitizenNeedsManager.process_daily_food_needs()
	_expect(resident.food_fulfilled, "Residents must receive food before unlinked legacy workers.")
	_expect(legacy_worker.food_fulfilled, "The second physical point must serve the unlinked legacy worker.")
	_expect(not dismissed_worker.food_fulfilled, "Dismissed workers must not receive a daily city-food allocation.")
	_expect(CitizenNeedsManager.last_food_fulfilled_count == 2 and CitizenNeedsManager.last_food_unfulfilled_count == 0, "Food counters must cover the deduplicated recipient set.")


func _test_ready_food_conservation_and_remainder() -> void:
	_clear_people()
	var resident: CitizenData = _make_resident("conservation_resident")
	CitizenManager.add_citizen(resident)
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var old_counter: int = CityStockManager.food_supply
	_set_food({READY_BREAD: 1, READY_CHICKEN: 1, RAW_GRAIN: 5, RAW_EGG: 1, RAW_MEAT: 2})
	var before: Dictionary = CitizenNeedsManager.get_food_supply_summary(provider)
	_expect(before.points == 3 and before.portion_points == 0, "Only ready-to-eat physical stock must contribute supply points; whole items have no retained portion yet.")
	_expect(before.days_remaining == 3, "One resident must see three ready food points as three days remaining.")

	_set_day_for_food(TimeComponentManager.current_day + 1)
	CitizenNeedsManager.process_daily_food_needs()
	var after_first: Dictionary = CitizenNeedsManager.get_food_supply_summary(provider)
	_expect(after_first.points == 2 and after_first.portion_points == 0, "Daily food consumption must conserve item points and whole ready-food stock.")
	_expect(provider.get("items").get(READY_CHICKEN, 0) == 1, "Low-point food must be consumed before the two-point chicken item.")
	_expect(CitizenNeedsManager.last_food_fulfilled_count == 1 and CitizenNeedsManager.last_food_unfulfilled_count == 0, "A one-point daily need must be fulfilled from physical food.")
	_expect(Inventory.items == inventory_before, "Physical city food consumption must not mutate personal Inventory.")
	_expect(CityStockManager.food_supply == old_counter, "Physical city food consumption must leave the old CityStockManager food counter unchanged.")

	_clear_people()
	var chicken_resident: CitizenData = _make_resident("chicken_remainder_resident")
	CitizenManager.add_citizen(chicken_resident)
	_set_food({READY_CHICKEN: 1})
	_set_day_for_food(TimeComponentManager.current_day + 1)
	CitizenNeedsManager.process_daily_food_needs()
	_expect(provider.get("food_portions").get(READY_CHICKEN, 0) == 1, "The first one-point day must preserve the chicken remainder.")
	_expect(CitizenNeedsManager.get_food_supply_summary(provider).days_remaining == 1, "The persisted one-point remainder must report exactly one day remaining.")
	_set_day_for_food(TimeComponentManager.current_day + 1)
	CitizenNeedsManager.process_daily_food_needs()
	_expect(not provider.get("food_portions").has(READY_CHICKEN), "The second one-point day must consume the persisted remainder.")
	_expect(CitizenNeedsManager.get_food_supply_summary(provider).points == 0, "Two one-point days must consume a two-point chicken portion exactly.")


func _test_shortage_accounting() -> void:
	_clear_people()
	var first: CitizenData = _make_resident("shortage_resident_a")
	var second: CitizenData = _make_resident("shortage_resident_b")
	var third: CitizenData = _make_resident("shortage_resident_c")
	CitizenManager.add_citizen(first)
	CitizenManager.add_citizen(second)
	CitizenManager.add_citizen(third)
	var legacy: WorkerData = _make_worker("shortage_legacy")
	WorkerDatabase.workers_by_id[legacy.worker_id] = legacy
	_set_food({READY_BREAD: 1})
	_set_day_for_food(TimeComponentManager.current_day + 1)
	CitizenNeedsManager.process_daily_food_needs()
	_expect(first.food_fulfilled and not second.food_fulfilled and not third.food_fulfilled, "Shortage allocation must preserve resident insertion priority.")
	_expect(not legacy.food_fulfilled, "A shortage must retain resident priority over unlinked legacy workers.")
	_expect(CitizenNeedsManager.last_food_fulfilled_count == 1 and CitizenNeedsManager.last_food_unfulfilled_count == 3, "Shortage counters must cover every recipient exactly once.")
	_expect(CitizenNeedsManager.get_food_supply_summary(provider).points == 0, "Shortage processing must consume only the one point actually provided.")


func _test_duplicate_day_and_reentrant_callback() -> void:
	_clear_people()
	var resident: CitizenData = _make_resident("duplicate_day_resident")
	CitizenManager.add_citizen(resident)
	CityStockManager.clothing_supply = 1
	CityStockManager.shelter_capacity = 1
	_set_food({READY_CHICKEN: 1})
	var reentrant_hits: Array[int] = [0]
	var reentrant_callback := func():
		reentrant_hits[0] += 1
		CitizenNeedsManager.process_daily_needs()
	if provider.has_signal("changed"):
		provider.connect("changed", reentrant_callback)
	_set_day_for_food(TimeComponentManager.current_day + 1)
	CitizenNeedsManager.process_daily_needs()
	var after_first: int = _provider_points()
	var satisfaction_after_first: float = resident.satisfaction
	var reliability_after_first: float = resident.reliability
	CitizenNeedsManager.process_daily_food_needs()
	CitizenNeedsManager.process_daily_needs()
	CitizenNeedsManager.on_new_day_started(TimeComponentManager.current_day)
	var after_duplicate: int = _provider_points()
	if provider.has_signal("changed"):
		provider.disconnect("changed", reentrant_callback)
	_expect(after_first == 1 and after_duplicate == 1, "Duplicate same-day food and full-needs calls must not consume twice.")
	_expect(CitizenNeedsManager.last_food_fulfilled_count == 1 and resident.food_fulfilled, "Duplicate-day calls must preserve the first allocation result.")
	_expect(is_equal_approx(resident.satisfaction, satisfaction_after_first) and is_equal_approx(resident.reliability, reliability_after_first), "Duplicate-day callbacks must not reapply satisfaction or reliability effects.")
	_expect(reentrant_hits[0] > 0, "The provider transaction must exercise the reentrant callback guard.")


func _test_multi_day_time_skip() -> void:
	_clear_people()
	var resident: CitizenData = _make_resident("time_skip_resident")
	CitizenManager.add_citizen(resident)
	_set_food({READY_BREAD: 3})
	TimeComponentManager.current_hour = 0
	TimeComponentManager.current_minute = 0
	TimeComponentManager.current_day += 1
	CitizenNeedsManager.last_processed_day = TimeComponentManager.current_day - 1
	CitizenNeedsManager.last_food_processed_day = TimeComponentManager.current_day - 1
	TimeComponentManager.advance_minutes(2 * TimeComponentManager.hour_per_day * TimeComponentManager.minute_per_hour)
	await get_tree().process_frame
	_expect(CitizenNeedsManager.get_food_supply_summary(provider).points == 1, "Actual time advancement over two days must process food once per crossed day.")
	_expect(CitizenNeedsManager.last_food_processed_day == TimeComponentManager.current_day, "Multi-day time advancement must leave the food guard at the current day.")


func _test_summary_refreshes_after_stock_addition() -> void:
	_clear_people()
	var resident: CitizenData = _make_resident("summary_refresh_resident")
	CitizenManager.add_citizen(resident)
	_set_food({READY_BREAD: 1})
	var before: Dictionary = CitizenNeedsManager.get_food_supply_summary(provider)
	var items: Dictionary = provider.get("items").duplicate(true)
	items[READY_CHICKEN] = 1
	provider.set("items", items)
	var after: Dictionary = CitizenNeedsManager.get_food_supply_summary(provider)
	_expect(before.points == 1 and after.points == 3, "A fresh food summary must update after physical stock is added.")
	_expect(after.days_remaining == 3 and after.portion_points == 0, "UI summary data must reflect the added physical points and current portion remainder.")


func _set_food(whole_items: Dictionary) -> void:
	if provider.get("items") is Dictionary:
		provider.set("items", whole_items.duplicate(true))
	if provider.get("food_portions") is Dictionary:
		provider.set("food_portions", {})


func _provider_points() -> int:
	if not is_instance_valid(provider) or not provider.has_method("get_food_supply_points"):
		return -1
	return int(provider.call("get_food_supply_points"))


func _set_day_for_food(day: int) -> void:
	TimeComponentManager.current_day = day
	CitizenNeedsManager.last_processed_day = day - 1
	CitizenNeedsManager.last_food_processed_day = day - 1
	CitizenNeedsManager._processing_daily_needs = false
	CitizenNeedsManager._processing_food = false


func _clear_people() -> void:
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()


func _make_resident(citizen_id: String) -> CitizenData:
	var citizen: CitizenData = CitizenData.new()
	citizen.citizen_id = citizen_id
	citizen.display_name = citizen_id
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	return citizen


func _make_worker(worker_id: String) -> WorkerData:
	var worker: WorkerData = WorkerData.new()
	worker.worker_id = worker_id
	worker.display_name = worker_id
	return worker


func _restore_global_state() -> void:
	CitizenManager.citizens_by_id = original_citizens.duplicate(true)
	WorkerDatabase.workers_by_id = original_workers.duplicate(true)
	WorkerDatabase.dismissed_workers = original_dismissed_workers.duplicate(true)
	Inventory.items = original_inventory.duplicate(true)
	CityStockManager.food_supply = int(original_city_stock.food_supply)
	CityStockManager.clothing_supply = int(original_city_stock.clothing_supply)
	CityStockManager.treasury_shekel = int(original_city_stock.treasury_shekel)
	CityStockManager.shelter_capacity = int(original_city_stock.shelter_capacity)
	TimeComponentManager.current_day = int(original_clock.day)
	TimeComponentManager.current_hour = int(original_clock.hour)
	TimeComponentManager.current_minute = int(original_clock.minute)
	TimeComponentManager.current_weather = str(original_clock.weather)
	TimeComponentManager.is_paused = bool(original_clock.paused)
	get_tree().paused = bool(original_clock.tree_paused)
	for property_name: String in original_needs_state.keys():
		CitizenNeedsManager.set(property_name, original_needs_state[property_name])

	if created_provider:
		if is_instance_valid(provider):
			provider.queue_free()
	else:
		_restore_provider(provider, original_provider_state)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
