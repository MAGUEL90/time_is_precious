extends Node

const CITY_TOOL_STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const READY_BREAD: String = "barley_bread"
const SIMPLE_CLOTHES: String = "simple_clothes"
const CLAY_WORN_WRAP: String = "clay_worn_wrap"
const PLAIN_LINEN_WRAP: String = "plain_linen_wrap"

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
	_test_provider_contract_and_atomicity()
	_test_summary_is_read_only_without_provider()
	_test_clothing_lifecycle_and_satisfaction()
	_test_day_eight_renewal_with_stock()
	_test_shortage_and_legacy_counter_is_ignored()
	_test_linked_worker_and_legacy_worker_are_unique_recipients()
	_test_clothing_supply_summary_shortage_and_restock()
	_restore_global_state()

	if failures > 0:
		push_error("CityClothingNeedsTest FAILED (%d failure(s))" % failures)
		get_tree().quit(1)
		return

	print("CityClothingNeedsTest PASSED")
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
	for property_name: String in [
		"last_food_fulfilled_count", "last_food_unfulfilled_count",
		"last_clothing_fulfilled_count", "last_clothing_unfulfilled_count",
		"last_shelter_capacity_fulfilled_count", "last_shelter_capacity_unfulfilled_count",
		"last_processed_day", "last_food_processed_day", "last_clothing_processed_day",
		"_processing_daily_needs", "_processing_food", "_processing_clothing",
		"clothing_allocations", "last_needs_results"
	]:
		if _has_property(CitizenNeedsManager, property_name):
			var value: Variant = CitizenNeedsManager.get(property_name)
			if value is Dictionary or value is Array:
				value = value.duplicate(true)
			original_needs_state[property_name] = value

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
		provider.has_method("get_clothing_item_count")
			and provider.has_method("take_clothing_items"),
		"CityToolStorage must expose the physical clothing provider contract."
	)
	_expect(provider.get("items") is Dictionary, "CityToolStorage must expose counted physical items.")


func _snapshot_provider(target: Node) -> Dictionary:
	var snapshot: Dictionary = {}
	for property_name: String in ["food_portions", "items", "units"]:
		var value: Variant = target.get(property_name)
		if value is Dictionary:
			snapshot[property_name] = value.duplicate(true)
	for property_name: String in ["_unit_sequence", "_transfer_in_progress"]:
		if _has_property(target, property_name):
			snapshot[property_name] = target.get(property_name)
	return snapshot


func _restore_provider(target: Node, snapshot: Dictionary) -> void:
	if not is_instance_valid(target):
		return
	for property_name: String in ["food_portions", "items", "units"]:
		if snapshot.has(property_name) and target.get(property_name) is Dictionary:
			target.set(property_name, snapshot[property_name].duplicate(true))
	for property_name: String in ["_unit_sequence", "_transfer_in_progress"]:
		if snapshot.has(property_name) and _has_property(target, property_name):
			target.set(property_name, snapshot[property_name])


func _test_provider_contract_and_atomicity() -> void:
	_clear_people()
	_set_items({
		SIMPLE_CLOTHES: 1,
		CLAY_WORN_WRAP: 1,
		PLAIN_LINEN_WRAP: 1,
		READY_BREAD: 2
	})
	var before_inventory: Dictionary = Inventory.items.duplicate(true)
	var before_units: Dictionary = provider.get("units").duplicate(true)
	var before_portions: Dictionary = provider.get("food_portions").duplicate(true)
	var before_legacy_clothing: int = CityStockManager.clothing_supply

	_expect(int(provider.get_clothing_item_count()) == 3, "Clothing count must include only positive physical clothing units.")
	_expect(provider.take_clothing_items(0).is_empty(), "Nonpositive clothing requests must return no units.")
	_expect(provider.take_clothing_items(-1).is_empty(), "Negative clothing requests must return no units.")
	_expect(int(provider.get_clothing_item_count()) == 3, "Rejected clothing requests must not mutate physical stock.")
	var valid_items: Dictionary = provider.get("items").duplicate(true)
	provider.set("items", {SIMPLE_CLOTHES: -1})
	_expect(provider.take_clothing_items(1).is_empty(), "Invalid negative physical stock must return no units.")
	_expect(provider.get_clothing_item_count() == 0, "Invalid physical stock must report no usable clothing.")
	provider.set("items", valid_items)

	var changed_count: Array[int] = [0]
	var reentrant_result: Array = []
	var changed_callback := func() -> void:
		changed_count[0] += 1
		reentrant_result.append_array(provider.take_clothing_items(1))
	provider.changed.connect(changed_callback)
	var taken: Array = provider.take_clothing_items(2)
	provider.changed.disconnect(changed_callback)

	_expect(taken == [CLAY_WORN_WRAP, PLAIN_LINEN_WRAP], "Clothing units must be selected in deterministic item-id order.")
	_expect(reentrant_result.is_empty(), "Reentrant clothing requests must return no units during the guarded commit.")
	_expect(changed_count[0] == 1, "A clothing transaction must emit the storage change signal exactly once.")
	_expect(int(provider.get_clothing_item_count()) == 1, "Taking clothing must consume only the requested available units.")
	_expect(provider.get("items").get(SIMPLE_CLOTHES, 0) == 1, "The untouched clothing unit must remain in city stock.")
	_expect(Inventory.items == before_inventory, "Physical clothing consumption must not mutate personal inventory.")
	_expect(provider.get("units") == before_units, "Physical clothing consumption must not mutate worker tool units.")
	_expect(provider.get("food_portions") == before_portions, "Physical clothing consumption must not mutate food portions.")
	_expect(CityStockManager.clothing_supply == before_legacy_clothing, "Physical clothing must ignore the legacy abstract clothing counter.")
	var final_taken: Array = provider.take_clothing_items(99)
	_expect(final_taken == [SIMPLE_CLOTHES], "A request above available stock must take only the remaining physical units.")
	_expect(provider.get_clothing_item_count() == 0, "Taking above available stock must stop at zero without underflow.")


func _test_summary_is_read_only_without_provider() -> void:
	_clear_people()
	_set_items({SIMPLE_CLOTHES: 1})
	var existing_provider: Node = provider
	var parent: Node = existing_provider.get_parent()
	if is_instance_valid(parent):
		parent.remove_child(existing_provider)
		detached_original_provider = true

	var before_children: int = WorkStateRuntime.get_child_count()
	var summary: Dictionary = CitizenNeedsManager.get_clothing_supply_summary()
	_expect(int(summary.get("stock_items", -1)) == 0, "A missing provider summary must report zero physical clothing stock.")
	_expect(WorkStateRuntime.get_child_count() == before_children, "A missing provider summary must not create a CityToolStorage node.")
	_expect(WorkStateRuntime.get_node_or_null("CityToolStorage") == null, "A missing provider summary must remain read-only.")

	if detached_original_provider and is_instance_valid(parent):
		parent.add_child(existing_provider)
		detached_original_provider = false


func _test_clothing_lifecycle_and_satisfaction() -> void:
	_clear_people()
	var resident: CitizenData = _make_resident("clothing_lifecycle_resident")
	var linked_worker: WorkerData = _make_worker(resident.citizen_id)
	CitizenManager.add_citizen(resident)
	WorkerDatabase.workers_by_id[linked_worker.worker_id] = linked_worker

	var base_day: int = TimeComponentManager.current_day + 100
	_set_new_fixture_day(base_day)
	CityStockManager.clothing_supply = 99
	CityStockManager.shelter_capacity = 1
	_set_items({SIMPLE_CLOTHES: 1, READY_BREAD: 9})

	var needs_signal_count: Array[int] = [0]
	var needs_callback := func() -> void:
		needs_signal_count[0] += 1
		CitizenNeedsManager.process_daily_needs()
	_expect(CitizenNeedsManager.has_signal("needs_changed"), "Daily needs must expose a completed-evaluation signal.")
	CitizenNeedsManager.connect("needs_changed", needs_callback)
	var satisfaction_before: float = resident.satisfaction
	var reliability_before: float = resident.reliability
	CitizenNeedsManager.process_daily_needs()
	CitizenNeedsManager.disconnect("needs_changed", needs_callback)
	var stock_after_first_evaluation: int = int(provider.get_clothing_item_count())
	CitizenNeedsManager.process_daily_needs()

	_expect(resident.food_fulfilled and resident.clothing_fulfilled and resident.shelter_fulfilled, "A stocked day must fulfill all three resident needs.")
	_expect(is_equal_approx(resident.satisfaction, satisfaction_before + 0.05), "A fully covered day must increase satisfaction by 0.05.")
	_expect(is_equal_approx(resident.reliability, reliability_before + 0.03), "A fully covered day must increase reliability by 0.03.")
	_expect(needs_signal_count[0] == 1, "Duplicate and reentrant daily-needs calls must emit one completed-evaluation signal.")
	_expect(int(provider.get_clothing_item_count()) == stock_after_first_evaluation, "Duplicate daily-needs calls must not consume another clothing unit.")
	_expect(provider.get("items").get(SIMPLE_CLOTHES, 0) == 0, "The first clothing need must consume one physical garment.")
	_expect(CityStockManager.clothing_supply == 99, "The daily clothing allocation must ignore abstract clothing stock.")
	_expect(_allocation_for(resident.citizen_id).get("issued_day", -1) == base_day, "Clothing must record the issue day.")
	_expect(_allocation_for(resident.citizen_id).get("expires_day", -1) == base_day + 6, "Clothing must remain valid through issue day plus six.")

	var first_summary: Dictionary = CitizenNeedsManager.get_clothing_supply_summary(provider)
	_expect(
		first_summary.has_all(["stock_items", "consumer_count", "covered_count", "replacement_need", "can_cover_all"]),
		"Clothing supply summary must expose stock, coverage, replacement, and capacity fields."
	)
	_expect(
		int(first_summary.get("consumer_count", -1)) == 1
			and int(first_summary.get("covered_count", -1)) == 1,
		"Clothing supply summary must count the unique resident recipient."
	)
	var initial_worker_summary: Dictionary = CitizenNeedsManager.get_worker_needs_summary(linked_worker)
	_assert_worker_summary(initial_worker_summary, base_day, true, true, true, 7)

	var clothing_item_id: String = str(_allocation_for(resident.citizen_id).get("item_id", ""))
	for offset: int in range(1, 7):
		_set_new_day(base_day + offset)
		var before_stock: int = int(provider.get_clothing_item_count())
		CitizenNeedsManager.process_daily_needs()
		_expect(resident.clothing_fulfilled, "Issued clothing must stay valid on day %d." % (base_day + offset))
		_expect(int(provider.get_clothing_item_count()) == before_stock, "Valid clothing must not consume a new item on day %d." % (base_day + offset))
		_expect(str(_allocation_for(resident.citizen_id).get("item_id", "")) == clothing_item_id, "Valid clothing must retain its original physical item.")

	_set_new_day(base_day + 7)
	var satisfaction_before_expiry: float = resident.satisfaction
	var reliability_before_expiry: float = resident.reliability
	CitizenNeedsManager.process_daily_needs()
	_expect(not resident.clothing_fulfilled, "Expired clothing must fail when no replacement is available.")
	_expect(provider.get_clothing_item_count() == 0, "Clothing expiry must not create phantom stock or negative stock.")
	_expect(is_equal_approx(resident.satisfaction, satisfaction_before_expiry - 0.05), "Clothing shortage must reduce satisfaction by five percentage points.")
	_expect(is_equal_approx(resident.reliability, reliability_before_expiry - 0.05), "Clothing shortage must apply the approved reliability decrease.")
	var expired_summary: Dictionary = CitizenNeedsManager.get_clothing_supply_summary(provider)
	_expect(int(expired_summary.get("replacement_need", 0)) >= 1, "An expired garment must create replacement need.")
	_expect(not bool(expired_summary.get("can_cover_all", true)), "No physical stock must not claim full clothing coverage.")
	var expired_worker_summary: Dictionary = CitizenNeedsManager.get_worker_needs_summary(linked_worker)
	_assert_worker_summary(expired_worker_summary, base_day + 7, true, false, true, -1)
	_expect(is_equal_approx(float(expired_worker_summary.satisfaction_delta), -0.05), "Worker Details must receive the five-point shortage result.")

	_set_items({SIMPLE_CLOTHES: 1, READY_BREAD: 1})
	_set_new_day(base_day + 8)
	var satisfaction_before_recovery: float = resident.satisfaction
	var reliability_before_recovery: float = resident.reliability
	CitizenNeedsManager.process_daily_needs()
	_expect(resident.clothing_fulfilled, "A physical clothing deposit must recover coverage on the next day.")
	_expect(provider.get_clothing_item_count() == 0, "Recovery must consume exactly the deposited physical garment.")
	_expect(is_equal_approx(resident.satisfaction, satisfaction_before_recovery + 0.05), "Recovered clothing with food and shelter must restore the positive satisfaction delta.")
	_expect(is_equal_approx(resident.satisfaction, satisfaction_before_expiry), "One fully supplied day must recover one day's satisfaction loss away from the limits.")
	_expect(is_equal_approx(resident.reliability, reliability_before_recovery + 0.03), "Recovered clothing with food and shelter must restore the positive reliability delta.")

	_set_items({})
	_set_new_day(base_day + 9)
	var satisfaction_before_food_failure: float = resident.satisfaction
	CitizenNeedsManager.process_daily_needs()
	_expect(not resident.food_fulfilled and resident.clothing_fulfilled and resident.shelter_fulfilled, "Food failure must be evaluated independently while clothing remains valid.")
	_expect(is_equal_approx(resident.satisfaction, satisfaction_before_food_failure - 0.05), "Food shortage must reduce satisfaction by five percentage points.")

	_set_items({READY_BREAD: 1})
	CityStockManager.shelter_capacity = 0
	_set_new_day(base_day + 10)
	var satisfaction_before_shelter_failure: float = resident.satisfaction
	CitizenNeedsManager.process_daily_needs()
	_expect(resident.food_fulfilled and resident.clothing_fulfilled and not resident.shelter_fulfilled, "Shelter failure must be evaluated independently while clothing remains valid.")
	_expect(is_equal_approx(resident.satisfaction, satisfaction_before_shelter_failure - 0.05), "Shelter shortage must reduce satisfaction by five percentage points.")

	CityStockManager.shelter_capacity = 1
	_set_items({READY_BREAD: 1})
	_set_new_day(base_day + 11)
	resident.satisfaction = 0.99
	resident.reliability = 0.99
	CitizenNeedsManager.process_daily_needs()
	_expect(is_equal_approx(resident.satisfaction, 0.99), "Positive satisfaction deltas must clamp at 0.99.")
	_expect(is_equal_approx(resident.reliability, 0.99), "Positive reliability deltas must clamp at 0.99.")
	var capped: Dictionary = CitizenNeedsManager.get_worker_needs_summary(linked_worker)
	_expect(is_zero_approx(float(capped.satisfaction_delta)) and is_zero_approx(float(capped.reliability_delta)),
		"A result already at the upper limit must report the actual zero bonus.")

	_set_items({})
	_set_new_day(base_day + 12)
	resident.satisfaction = 0.01
	resident.reliability = 0.01
	CitizenNeedsManager.process_daily_needs()
	_expect(is_equal_approx(resident.satisfaction, 0.01), "Negative satisfaction deltas must clamp at 0.01.")
	_expect(is_equal_approx(resident.reliability, 0.01), "Negative reliability deltas must clamp at 0.01.")
	capped = CitizenNeedsManager.get_worker_needs_summary(linked_worker)
	_expect(is_zero_approx(float(capped.satisfaction_delta)) and is_zero_approx(float(capped.reliability_delta)),
		"A result already at the lower limit must report the actual zero penalty.")


func _test_shortage_and_legacy_counter_is_ignored() -> void:
	_clear_people()
	var first: CitizenData = _make_resident("clothing_shortage_a")
	var second: CitizenData = _make_resident("clothing_shortage_b")
	CitizenManager.add_citizen(first)
	CitizenManager.add_citizen(second)
	var base_day: int = TimeComponentManager.current_day + 100
	_set_new_fixture_day(base_day)
	CityStockManager.clothing_supply = 42
	CityStockManager.shelter_capacity = 2
	_set_items({SIMPLE_CLOTHES: 1, READY_BREAD: 2})
	CitizenNeedsManager.process_daily_needs()

	_expect(first.clothing_fulfilled and not second.clothing_fulfilled, "Clothing shortage must preserve resident insertion priority without phantom garments.")
	_expect(CitizenNeedsManager.last_clothing_fulfilled_count == 1, "Clothing shortage must count exactly one fulfilled recipient.")
	_expect(CitizenNeedsManager.last_clothing_unfulfilled_count == 1, "Clothing shortage must count exactly one unfulfilled recipient.")
	_expect(provider.get_clothing_item_count() == 0, "Clothing shortage must not drive physical stock below zero.")
	_expect(not _has_allocation(second.citizen_id), "An unfulfilled recipient must not receive a phantom clothing allocation.")
	_expect(CityStockManager.clothing_supply == 42, "The old abstract clothing counter must remain unchanged during shortage.")

	var summary: Dictionary = CitizenNeedsManager.get_clothing_supply_summary(provider)
	_expect(int(summary.get("consumer_count", -1)) == 2, "Clothing summary must include both unique residents during shortage.")
	_expect(int(summary.get("covered_count", -1)) == 1, "Clothing summary must report the one covered recipient.")
	_expect(not bool(summary.get("can_cover_all", true)), "Clothing summary must reject full coverage when physical stock is short.")


func _test_day_eight_renewal_with_stock() -> void:
	_clear_people()
	var resident: CitizenData = _make_resident("clothing_day_eight_renewal")
	CitizenManager.add_citizen(resident)
	var base_day: int = TimeComponentManager.current_day + 100
	_set_new_fixture_day(base_day)
	CityStockManager.clothing_supply = 64
	CityStockManager.shelter_capacity = 1
	_set_items({SIMPLE_CLOTHES: 1, READY_BREAD: 8})
	CitizenNeedsManager.process_daily_needs()
	_expect(resident.clothing_fulfilled, "A stocked issue day must provide the initial clothing allocation.")

	for offset: int in range(1, 7):
		_set_new_day(base_day + offset)
		CitizenNeedsManager.process_daily_needs()
		_expect(resident.clothing_fulfilled, "The initial garment must remain valid through renewal day minus one.")

	_set_items({SIMPLE_CLOTHES: 1, READY_BREAD: 1})
	var provider_reentry_hits: Array[int] = [0]
	var provider_callback := func() -> void:
		provider_reentry_hits[0] += 1
		CitizenNeedsManager.process_daily_needs()
	provider.changed.connect(provider_callback)
	_set_new_day(base_day + 7)
	CitizenNeedsManager.process_daily_needs()
	provider.changed.disconnect(provider_callback)

	_expect(provider_reentry_hits[0] > 0, "A provider change during day-eight issue must exercise the daily-needs reentry guard.")
	_expect(resident.clothing_fulfilled, "Exactly one replacement garment must renew clothing on day eight.")
	_expect(provider.get_clothing_item_count() == 0, "Day-eight renewal must consume exactly the one replacement garment.")
	_expect(_allocation_for(resident.citizen_id).get("issued_day", -1) == base_day + 7, "Day-eight renewal must issue a new physical garment on the replacement day.")
	_expect(_allocation_for(resident.citizen_id).get("expires_day", -1) == base_day + 13, "Day-eight renewal must grant the next seven-day validity window.")
	_expect(int(CitizenNeedsManager.get_clothing_supply_summary(provider).get("covered_count", -1)) == 1, "Day-eight renewal must leave the recipient covered.")


func _test_linked_worker_and_legacy_worker_are_unique_recipients() -> void:
	_clear_people()
	var resident: CitizenData = _make_resident("clothing_linked_resident")
	var linked_worker: WorkerData = _make_worker(resident.citizen_id)
	var legacy_worker: WorkerData = _make_worker("clothing_legacy_worker")
	linked_worker.satisfaction = 0.10
	linked_worker.reliability = 0.20
	legacy_worker.satisfaction = 0.40
	legacy_worker.reliability = 0.50
	CitizenManager.add_citizen(resident)
	WorkerDatabase.workers_by_id[linked_worker.worker_id] = linked_worker
	WorkerDatabase.workers_by_id[legacy_worker.worker_id] = legacy_worker
	var base_day: int = TimeComponentManager.current_day + 100
	_set_new_fixture_day(base_day)
	CityStockManager.clothing_supply = 77
	CityStockManager.shelter_capacity = 2
	_set_items({SIMPLE_CLOTHES: 2, READY_BREAD: 2})

	var summary_before: Dictionary = CitizenNeedsManager.get_clothing_supply_summary(provider)
	CitizenNeedsManager.process_daily_needs()
	var summary_after: Dictionary = CitizenNeedsManager.get_clothing_supply_summary(provider)

	_expect(int(summary_before.get("consumer_count", -1)) == 2, "Unique clothing consumers must include the resident and one legacy worker.")
	_expect(CitizenNeedsManager.get_food_consumer_count() == 2, "Clothing recipients must match the existing unique food recipient set.")
	_expect(int(summary_after.get("consumer_count", -1)) == 2, "Linked workers must not create a second clothing consumer.")
	_expect(CitizenNeedsManager.last_clothing_fulfilled_count == 2 and CitizenNeedsManager.last_clothing_unfulfilled_count == 0, "Physical clothing must be allocated once to the linked resident and legacy worker.")
	_expect(resident.clothing_fulfilled and legacy_worker.clothing_fulfilled, "Linked residents and legacy workers must both receive clothing when stock covers both.")
	_expect(provider.get_clothing_item_count() == 0, "Unique clothing allocation must consume exactly two physical garments.")
	_expect(is_equal_approx(linked_worker.satisfaction, 0.10), "A linked worker must not receive a second satisfaction evaluation through WorkerData.")
	_expect(is_equal_approx(linked_worker.reliability, 0.20), "A linked worker must not receive a second reliability evaluation through WorkerData.")
	_expect(CityStockManager.clothing_supply == 77, "Linked and legacy clothing allocation must ignore abstract clothing stock.")
	_expect(CitizenNeedsManager.get("last_needs_results").size() == 2, "Needs results must contain one completed result per unique recipient.")

	_set_items({})
	CityStockManager.shelter_capacity = 0
	_set_new_day(base_day + 7)
	var resident_before_shortage: float = resident.satisfaction
	var legacy_before_shortage: float = legacy_worker.satisfaction
	CitizenNeedsManager.process_daily_needs()
	CitizenNeedsManager.process_daily_needs()
	var linked_result: Dictionary = CitizenNeedsManager.get_worker_needs_summary(linked_worker)
	var legacy_result: Dictionary = CitizenNeedsManager.get_worker_needs_summary(legacy_worker)
	_expect(linked_result.missing.size() == 3 and legacy_result.missing.size() == 3, "Empty city stock and no shelter must leave all three needs missing for both recipients.")
	_expect(is_equal_approx(linked_worker.get_resolved_satisfaction(), resident_before_shortage - 0.05), "A linked worker with three missing needs receives one five-point daily penalty, even after a repeated callback.")
	_expect(is_equal_approx(legacy_worker.satisfaction, legacy_before_shortage - 0.05), "An unlinked worker with three missing needs receives the same single five-point daily penalty.")
	_expect(is_equal_approx(float(linked_result.satisfaction_delta), -0.05) and is_equal_approx(float(legacy_result.satisfaction_delta), -0.05), "Both worker summaries must expose the single five-point shortage result.")


func _test_clothing_supply_summary_shortage_and_restock() -> void:
	_clear_people()
	Inventory.items.clear()
	var residents: Array[CitizenData] = []
	for index: int in range(8):
		var resident: CitizenData = _make_resident("clothing_summary_resident_%d" % (index + 1))
		CitizenManager.add_citizen(resident)
		residents.append(resident)
		if index < 3 or index == 7:
			var linked_worker: WorkerData = _make_worker(resident.citizen_id)
			WorkerDatabase.workers_by_id[linked_worker.worker_id] = linked_worker

	var base_day: int = TimeComponentManager.current_day + 100
	_set_new_fixture_day(base_day)
	CityStockManager.clothing_supply = 0
	CityStockManager.shelter_capacity = 8
	_set_items({SIMPLE_CLOTHES: 7, READY_BREAD: 16})

	var initial_satisfaction: Array[float] = []
	var initial_reliability: Array[float] = []
	for resident: CitizenData in residents:
		initial_satisfaction.append(resident.satisfaction)
		initial_reliability.append(resident.reliability)

	CitizenNeedsManager.process_daily_needs()
	var first_summary: Dictionary = CitizenNeedsManager.get_clothing_supply_summary(provider)
	_expect(CitizenNeedsManager.last_clothing_fulfilled_count == 7, "The first daily evaluation must cover seven clothing recipients.")
	_expect(CitizenNeedsManager.last_clothing_unfulfilled_count == 1, "The first daily evaluation must leave one clothing recipient missing.")
	_expect(provider.get_clothing_item_count() == 0, "The first daily evaluation must consume all seven physical garments.")
	_expect(
		int(first_summary.get("stock_items", -1)) == 0
			and int(first_summary.get("consumer_count", -1)) == 8
			and int(first_summary.get("covered_count", -1)) == 7
			and int(first_summary.get("replacement_need", -1)) == 1
			and not bool(first_summary.get("can_cover_all", true)),
		"The first clothing summary must report eight unique consumers, seven covered, and one replacement needed."
	)
	for index: int in range(7):
		var resident: CitizenData = residents[index]
		_expect(resident.clothing_fulfilled, "The first seven residents must receive physical clothing.")
		_expect(is_equal_approx(resident.satisfaction, initial_satisfaction[index] + 0.05), "A covered resident must receive the positive satisfaction delta.")
		_expect(is_equal_approx(resident.reliability, initial_reliability[index] + 0.03), "A covered resident must receive the positive reliability delta.")
	_expect(not residents[7].clothing_fulfilled, "The eighth resident must remain uncovered while physical clothing is short.")
	_expect(is_equal_approx(residents[7].satisfaction, initial_satisfaction[7] - 0.05), "The uncovered resident must receive the shortage satisfaction delta.")
	_expect(is_equal_approx(residents[7].reliability, initial_reliability[7] - 0.05), "The uncovered resident must receive the shortage reliability delta.")
	_expect(CitizenNeedsManager.get("last_needs_results").size() == 8, "Linked workers must not create duplicate daily-needs results.")
	_expect(WorkerDatabase.workers_by_id.size() == 4, "The fixture must retain exactly its four linked worker records.")

	var original_issue_days: Dictionary = {}
	for index: int in range(7):
		var resident_id: String = residents[index].citizen_id
		original_issue_days[resident_id] = _allocation_for(resident_id).get("issued_day", -1)
		_expect(int(original_issue_days[resident_id]) == base_day, "The first seven garments must be issued on the shortage day.")

	Inventory.add_item(SIMPLE_CLOTHES, 1)
	var deposit_result: Dictionary = provider.deposit_items_from_inventory({SIMPLE_CLOTHES: 1})
	_expect(bool(deposit_result.get("ok", false)), "Exactly one simple_clothes must be deposited through the City Storage provider.")
	_expect(Inventory.items.get(SIMPLE_CLOTHES, 0) == 0, "The deposited garment must leave personal Inventory.")
	_expect(provider.get("items").get(SIMPLE_CLOTHES, 0) == 1, "The deposited garment must become one physical City Storage item.")
	_expect(provider.get_clothing_item_count() == 1, "City Storage must expose exactly one replacement garment before the next day.")

	var before_summary_inventory: Dictionary = Inventory.items.duplicate(true)
	var before_summary_items: Dictionary = provider.get("items").duplicate(true)
	var before_summary_allocations: Dictionary = CitizenNeedsManager.get("clothing_allocations").duplicate(true)
	var before_summary_results: Dictionary = CitizenNeedsManager.get("last_needs_results").duplicate(true)
	var before_summary_last_processed: int = CitizenNeedsManager.last_processed_day
	var before_summary_last_clothing_processed: int = CitizenNeedsManager.last_clothing_processed_day
	var before_summary_satisfaction: Array[float] = []
	var before_summary_reliability: Array[float] = []
	for resident: CitizenData in residents:
		before_summary_satisfaction.append(resident.satisfaction)
		before_summary_reliability.append(resident.reliability)

	var summary_before_next_day: Dictionary = CitizenNeedsManager.get_clothing_supply_summary(provider)
	var summary_before_next_day_without_argument: Dictionary = CitizenNeedsManager.get_clothing_supply_summary()
	_expect(int(summary_before_next_day.get("consumer_count", -1)) == 8 and int(summary_before_next_day.get("covered_count", -1)) == 7, "The pre-next-day summary must still show seven of eight actual allocations.")
	_expect(int(summary_before_next_day.get("stock_items", -1)) == 1 and int(summary_before_next_day.get("replacement_need", -1)) == 1, "The pre-next-day summary must show one available replacement garment and one outstanding need.")
	_expect(bool(summary_before_next_day.get("can_cover_all", false)), "One deposited garment must make the remaining clothing need coverable.")
	_expect(summary_before_next_day_without_argument == summary_before_next_day, "The default-provider summary must match the explicit-provider summary.")
	_expect(provider.get_clothing_item_count() == 1, "Summary reads must not consume the deposited garment.")
	_expect(provider.get("items") == before_summary_items, "Summary reads must not mutate City Storage items.")
	_expect(Inventory.items == before_summary_inventory, "Summary reads must not mutate personal Inventory.")
	_expect(CitizenNeedsManager.get("clothing_allocations") == before_summary_allocations, "Summary reads must not allocate clothing.")
	_expect(CitizenNeedsManager.get("last_needs_results") == before_summary_results, "Summary reads must not evaluate daily needs.")
	_expect(CitizenNeedsManager.last_processed_day == before_summary_last_processed, "Summary reads must not advance daily-needs processing.")
	_expect(CitizenNeedsManager.last_clothing_processed_day == before_summary_last_clothing_processed, "Summary reads must not advance clothing processing.")
	for index: int in range(residents.size()):
		_expect(residents[index].clothing_fulfilled == (index < 7), "Summary reads must preserve actual current-day clothing coverage.")
		_expect(is_equal_approx(residents[index].satisfaction, before_summary_satisfaction[index]), "Summary reads must not change satisfaction.")
		_expect(is_equal_approx(residents[index].reliability, before_summary_reliability[index]), "Summary reads must not change reliability.")

	_set_new_day(base_day + 1)
	CitizenNeedsManager.process_daily_needs()
	var next_summary: Dictionary = CitizenNeedsManager.get_clothing_supply_summary(provider)
	_expect(CitizenNeedsManager.last_clothing_fulfilled_count == 8 and CitizenNeedsManager.last_clothing_unfulfilled_count == 0, "The next daily evaluation must cover all eight clothing recipients.")
	_expect(provider.get_clothing_item_count() == 0, "The next daily evaluation must consume exactly the deposited replacement garment.")
	_expect(int(next_summary.get("consumer_count", -1)) == 8 and int(next_summary.get("covered_count", -1)) == 8, "The next-day clothing summary must report all eight recipients covered.")
	_expect(int(next_summary.get("stock_items", -1)) == 0 and int(next_summary.get("replacement_need", -1)) == 0, "The next-day clothing summary must report no remaining stock or replacement need.")
	_expect(CitizenNeedsManager.get("clothing_allocations").size() == 8, "The next daily evaluation must retain one allocation per unique resident.")
	for index: int in range(7):
		var resident_id: String = residents[index].citizen_id
		_expect(int(_allocation_for(resident_id).get("issued_day", -1)) == int(original_issue_days[resident_id]), "Previously covered residents must retain their original clothing issue dates.")
	_expect(is_equal_approx(residents[7].satisfaction, initial_satisfaction[7]), "The previously uncovered resident must recover the shortage satisfaction loss on the next day.")
	_expect(is_equal_approx(residents[7].reliability, initial_reliability[7] - 0.02), "The previously uncovered resident must receive the net reliability recovery on the next day.")
	var eighth_worker: WorkerData = WorkerDatabase.get_worker_data(residents[7].citizen_id)
	var eighth_summary: Dictionary = CitizenNeedsManager.get_worker_needs_summary(eighth_worker)
	_assert_worker_summary(eighth_summary, base_day + 1, true, true, true, 7)
	_expect(is_equal_approx(float(eighth_summary.get("satisfaction_delta", 0.0)), 0.05), "The recovered eighth resident must receive a positive satisfaction delta.")
	_expect(is_equal_approx(float(eighth_summary.get("reliability_delta", 0.0)), 0.03), "The recovered eighth resident must receive a positive reliability delta.")
	_expect(WorkerDatabase.workers_by_id.size() == 4, "Daily-needs processing must not create duplicate workers.")
	_expect(provider.get("items").get(SIMPLE_CLOTHES, 0) == 0, "Daily-needs processing must not leave extra clothing garments.")


func _assert_worker_summary(
	summary: Dictionary,
	day: int,
	food: bool,
	clothing: bool,
	shelter: bool,
	expected_days_left: int
) -> void:
	for key: String in [
		"evaluated", "day", "food", "clothing", "shelter", "clothing_days_left",
		"satisfaction", "reliability", "satisfaction_delta", "reliability_delta", "missing"
	]:
		_expect(summary.has(key), "Worker needs summary must expose the '%s' field." % key)
	_expect(bool(summary.get("evaluated", false)), "Worker needs summary must identify a completed evaluation.")
	_expect(int(summary.get("day", -1)) == day, "Worker needs summary must report the evaluated day.")
	_expect(bool(summary.get("food", false)) == food, "Worker needs summary food state must match the evaluated recipient.")
	_expect(bool(summary.get("clothing", false)) == clothing, "Worker needs summary clothing state must match the evaluated recipient.")
	_expect(bool(summary.get("shelter", false)) == shelter, "Worker needs summary shelter state must match the evaluated recipient.")
	if expected_days_left >= 0:
		_expect(int(summary.get("clothing_days_left", -1)) == expected_days_left, "Worker needs summary must report remaining clothing validity days.")
	else:
		_expect(int(summary.get("clothing_days_left", 0)) <= 0, "Expired clothing must report no remaining validity days.")
	var missing: Variant = summary.get("missing", [])
	if missing is Array:
		_expect((missing as Array).is_empty() == (food and clothing and shelter), "Worker needs summary missing list must match the three need states.")


func _allocation_for(recipient_id: String) -> Dictionary:
	var allocations: Variant = CitizenNeedsManager.get("clothing_allocations")
	if allocations is Dictionary and allocations.has(recipient_id) and allocations[recipient_id] is Dictionary:
		return allocations[recipient_id]
	return {}


func _has_allocation(recipient_id: String) -> bool:
	return not _allocation_for(recipient_id).is_empty()


func _set_items(next_items: Dictionary) -> void:
	if provider.get("items") is Dictionary:
		provider.set("items", next_items.duplicate(true))
	if provider.get("food_portions") is Dictionary:
		provider.set("food_portions", {})


func _set_new_fixture_day(day: int) -> void:
	_clear_need_tracking(day)
	TimeComponentManager.current_day = day


func _set_new_day(day: int) -> void:
	TimeComponentManager.current_day = day
	_set_if_property(CitizenNeedsManager, "_processing_daily_needs", false)
	_set_if_property(CitizenNeedsManager, "_processing_food", false)
	_set_if_property(CitizenNeedsManager, "_processing_clothing", false)


func _clear_need_tracking(day: int) -> void:
	_set_if_property(CitizenNeedsManager, "last_processed_day", day - 1)
	_set_if_property(CitizenNeedsManager, "last_food_processed_day", day - 1)
	_set_if_property(CitizenNeedsManager, "last_clothing_processed_day", day - 1)
	_set_if_property(CitizenNeedsManager, "_processing_daily_needs", false)
	_set_if_property(CitizenNeedsManager, "_processing_food", false)
	_set_if_property(CitizenNeedsManager, "_processing_clothing", false)
	_set_if_property(CitizenNeedsManager, "clothing_allocations", {})
	_set_if_property(CitizenNeedsManager, "last_needs_results", {})


func _clear_people() -> void:
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()


func _make_resident(citizen_id: String) -> CitizenData:
	var citizen: CitizenData = CitizenData.new()
	citizen.citizen_id = citizen_id
	citizen.display_name = citizen_id
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.HIRED
	citizen.satisfaction = 0.50
	citizen.reliability = 0.50
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
		if _has_property(CitizenNeedsManager, property_name):
			CitizenNeedsManager.set(property_name, original_needs_state[property_name])

	if created_provider:
		if is_instance_valid(provider):
			provider.queue_free()
	else:
		_restore_provider(provider, original_provider_state)


func _set_if_property(target: Object, property_name: String, value: Variant) -> void:
	if _has_property(target, property_name):
		target.set(property_name, value)


func _has_property(target: Object, property_name: String) -> bool:
	for property_info: Dictionary in target.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
