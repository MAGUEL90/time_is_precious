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
	_test_ten_day_satisfaction_boundaries()
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
		"clothing_allocations", "last_needs_results", "food_coverage_until",
		"satisfaction_last_minute"
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
	# The revised condition scale is 0/33/66/99% for zero through three
	# fulfilled needs; actual satisfaction moves at most five points per day.
	_expect(is_zero_approx(CitizenNeedsManager.satisfaction_condition_value(false, false, false)),
		"No fulfilled needs must produce a 0% condition target.")
	_expect(is_equal_approx(CitizenNeedsManager.satisfaction_condition_value(true, false, false), 0.33),
		"One fulfilled need must produce a 33% condition target.")
	_expect(is_equal_approx(CitizenNeedsManager.satisfaction_condition_value(true, true, false), 0.66),
		"Two fulfilled needs must produce a 66% condition target.")
	_expect(is_equal_approx(CitizenNeedsManager.satisfaction_condition_value(true, true, true), 0.99),
		"Three fulfilled needs must produce a 99% condition target.")
	var resident: CitizenData = _make_resident("clothing_lifecycle_resident")
	var linked_worker: WorkerData = _make_worker(resident.citizen_id)
	CitizenManager.add_citizen(resident)
	WorkerDatabase.workers_by_id[linked_worker.worker_id] = linked_worker
	var unevaluated_summary: Dictionary = CitizenNeedsManager.get_worker_needs_summary(linked_worker)
	_expect(bool(unevaluated_summary.evaluated) and is_equal_approx(float(unevaluated_summary.satisfaction), resident.satisfaction),
		"A read-only worker summary must show the linked resident's current satisfaction before the first daily ledger.")
	_assert_summary_without_reliability(unevaluated_summary)
	_assert_summary_without_reliability(CitizenNeedsManager.get_worker_needs_summary(null))

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
	CitizenNeedsManager.process_daily_needs()
	CitizenNeedsManager.disconnect("needs_changed", needs_callback)
	var stock_after_first_evaluation: int = int(provider.get_clothing_item_count())
	CitizenNeedsManager.process_daily_needs()

	_expect(resident.food_fulfilled and resident.clothing_fulfilled and resident.shelter_fulfilled, "A stocked day must fulfill all three resident needs.")
	_expect(is_equal_approx(resident.satisfaction, satisfaction_before), "A daily needs evaluation at the same clock minute must not instantly change satisfaction.")
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
		_advance_to_day(base_day + offset)
		var before_stock: int = int(provider.get_clothing_item_count())
		CitizenNeedsManager.process_daily_needs()
		_expect(resident.clothing_fulfilled, "Issued clothing must stay valid on day %d." % (base_day + offset))
		_expect(int(provider.get_clothing_item_count()) == before_stock, "Valid clothing must not consume a new item on day %d." % (base_day + offset))
		_expect(str(_allocation_for(resident.citizen_id).get("item_id", "")) == clothing_item_id, "Valid clothing must retain its original physical item.")
		if offset == 1:
			_expect(is_equal_approx(resident.satisfaction, satisfaction_before + 0.05), "One real covered day must move satisfaction upward by five points.")

	_advance_to_day(base_day + 7)
	var satisfaction_before_expiry: float = resident.satisfaction
	_expect(is_equal_approx(satisfaction_before_expiry, 0.85),
		"Seven elapsed fully supplied days move satisfaction from 50% to 85%, still above the 66% two-need target.")
	CitizenNeedsManager.process_daily_needs()
	_expect(not resident.clothing_fulfilled, "Expired clothing must fail when no replacement is available.")
	_expect(provider.get_clothing_item_count() == 0, "Clothing expiry must not create phantom stock or negative stock.")
	_expect(is_equal_approx(resident.satisfaction, satisfaction_before_expiry),
		"A clothing-expiry evaluation itself must not apply an instant satisfaction penalty.")
	var expired_summary: Dictionary = CitizenNeedsManager.get_clothing_supply_summary(provider)
	_expect(int(expired_summary.get("replacement_need", 0)) >= 1, "An expired garment must create replacement need.")
	_expect(not bool(expired_summary.get("can_cover_all", true)), "No physical stock must not claim full clothing coverage.")
	var expired_worker_summary: Dictionary = CitizenNeedsManager.get_worker_needs_summary(linked_worker)
	_assert_worker_summary(expired_worker_summary, base_day + 7, true, false, true, -1)
	_expect(is_zero_approx(float(expired_worker_summary.satisfaction_delta)), "Worker Details must report no instant satisfaction delta for a needs evaluation.")

	_set_items({SIMPLE_CLOTHES: 1, READY_BREAD: 1})
	_set_new_day(base_day + 8)
	var satisfaction_before_recovery: float = resident.satisfaction
	CitizenNeedsManager.process_daily_needs()
	_expect(resident.clothing_fulfilled, "A physical clothing deposit must recover coverage on the next day.")
	_expect(provider.get_clothing_item_count() == 0, "Recovery must consume exactly the deposited physical garment.")
	_expect(is_equal_approx(resident.satisfaction, satisfaction_before_recovery), "A recovered clothing allocation must not instantly change satisfaction.")
	_expect(is_equal_approx(satisfaction_before_recovery, satisfaction_before_expiry), "Restocking and evaluating needs without elapsed time must preserve satisfaction.")

	_set_items({})
	_set_new_day(base_day + 9)
	var satisfaction_before_food_failure: float = resident.satisfaction
	CitizenNeedsManager.process_daily_needs()
	_expect(not resident.food_fulfilled and resident.clothing_fulfilled and resident.shelter_fulfilled, "Food failure must be evaluated independently while clothing remains valid.")
	_expect(is_equal_approx(resident.satisfaction, satisfaction_before_food_failure),
		"A food-shortage evaluation without elapsed time must not change satisfaction.")

	_set_items({READY_BREAD: 1})
	CityStockManager.shelter_capacity = 0
	_set_new_day(base_day + 10)
	var satisfaction_before_shelter_failure: float = resident.satisfaction
	CitizenNeedsManager.process_daily_needs()
	_expect(resident.food_fulfilled and resident.clothing_fulfilled and not resident.shelter_fulfilled, "Shelter failure must be evaluated independently while clothing remains valid.")
	_expect(is_equal_approx(resident.satisfaction, satisfaction_before_shelter_failure),
		"A shelter-shortage evaluation without elapsed time must not change satisfaction.")

	CityStockManager.shelter_capacity = 1
	_set_items({READY_BREAD: 1})
	_set_new_day(base_day + 11)
	resident.satisfaction = 0.99
	CitizenNeedsManager.process_daily_needs()
	_expect(is_equal_approx(resident.satisfaction, 0.99), "Positive satisfaction deltas must clamp at 0.99.")
	var capped: Dictionary = CitizenNeedsManager.get_worker_needs_summary(linked_worker)
	_expect(is_zero_approx(float(capped.satisfaction_delta)),
		"A result already at the upper limit must report the actual zero bonus.")

	_set_items({})
	_set_new_day(base_day + 12)
	# Zero is a stable lower bound only when all needs are unmet (target 0%).
	CityStockManager.shelter_capacity = 0
	_set_if_property(CitizenNeedsManager, "clothing_allocations", {})
	CitizenNeedsManager.process_daily_needs()
	_expect(not resident.food_fulfilled and not resident.clothing_fulfilled and not resident.shelter_fulfilled,
		"The lower-bound fixture must leave all three needs unmet.")
	# Keep this linked fixture present long enough to inspect its saved daily row;
	# the real zero-departure path is covered by the elapsed-time boundary test.
	resident.satisfaction = 0.0
	_expect(is_zero_approx(resident.satisfaction), "Zero satisfaction must remain at zero when all three needs are unmet.")
	capped = CitizenNeedsManager.get_worker_needs_summary(linked_worker)
	_expect(is_zero_approx(float(capped.satisfaction_delta)),
		"At the zero condition target, the lower-bound result must report no actual satisfaction change.")


func _test_ten_day_satisfaction_boundaries() -> void:
	_clear_people()
	var resident: CitizenData = _make_resident("ten_day_needs_boundary")
	resident.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	CitizenManager.add_citizen(resident)
	var zero_worker: WorkerData = _make_worker("ten_day_zero_worker")
	zero_worker.satisfaction = 0.5
	zero_worker.current_work_status = WorkerData.WorkStatus.IDLE
	WorkerDatabase.workers_by_id[zero_worker.worker_id] = zero_worker
	# With the 33% per-need model, an unmet need alone no longer guarantees a
	# decrease. Make all three needs unavailable and move the actual game clock.
	CityStockManager.shelter_capacity = 0
	_set_items({})
	var base_day: int = TimeComponentManager.current_day + 100
	_set_new_fixture_day(base_day)
	CitizenNeedsManager.process_daily_needs()
	for offset: int in range(1, 10):
		_advance_to_day(base_day + offset)
		var once: float = resident.satisfaction
		var worker_once: float = zero_worker.satisfaction
		CitizenNeedsManager.process_daily_needs()
		CitizenNeedsManager.process_daily_needs()
		_expect(is_equal_approx(resident.satisfaction, once) and is_equal_approx(zero_worker.satisfaction, worker_once),
			"Repeated same-minute daily evaluation does not duplicate an elapsed-time result.")
		_expect(not resident.food_fulfilled and not resident.clothing_fulfilled and not resident.shelter_fulfilled,
			"Every elapsed day in the zero-target fixture must leave all three needs unmet.")
		_expect(is_equal_approx(resident.satisfaction, 0.5 - float(offset) * 0.05)
			and is_equal_approx(zero_worker.satisfaction, 0.5 - float(offset) * 0.05),
			"Each real 24-hour interval moves the resident and legacy worker five points toward the 0% target.")
	_advance_to_day(base_day + 10)
	_expect(is_zero_approx(resident.satisfaction) and is_zero_approx(zero_worker.satisfaction),
		"Ten real days moving down by five points toward a 0% condition target take 50% exactly to zero.")
	var resigned_citizen: CitizenData = CitizenManager.get_citizen(zero_worker.worker_id)
	_expect(
		WorkerDatabase.get_worker_data(zero_worker.worker_id) == null
			and WorkerDatabase.dismissed_workers.has(zero_worker.worker_id)
			and resigned_citizen != null
			and resigned_citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
			and resigned_citizen.population_status == CitizenData.PopulationStatus.LEFT_CITY
			and resident.population_status == CitizenData.PopulationStatus.LEFT_CITY,
		"The idle legacy worker and civilian both leave after reaching zero."
	)
	_expect(CitizenManager.get_all_applicants().is_empty(), "Residents at zero must remain below the existing applicant threshold.")
	# A citizen who reaches exact zero leaves by design. Use a separate nonzero
	# cohort to retain the existing applicant-threshold recovery assertion.
	_clear_people()
	var recovering_resident: CitizenData = _make_resident("ten_day_recovery_resident")
	recovering_resident.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	recovering_resident.satisfaction = 0.01
	var recovering_legacy: CitizenData = _make_resident("ten_day_recovery_legacy")
	recovering_legacy.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	recovering_legacy.satisfaction = 0.01
	CitizenManager.add_citizen(recovering_resident)
	CitizenManager.add_citizen(recovering_legacy)
	var recovery_day: int = base_day + 10
	_set_new_fixture_day(recovery_day)
	CityStockManager.shelter_capacity = 2
	_set_items({SIMPLE_CLOTHES: 4, READY_BREAD: 22})
	CitizenNeedsManager.process_daily_needs()
	for offset: int in range(1, 11):
		_advance_to_day(recovery_day + offset)
		CitizenNeedsManager.process_daily_needs()
		CitizenNeedsManager.process_daily_needs()
		_expect(is_equal_approx(recovering_resident.satisfaction, 0.01 + float(offset) * 0.05)
			and is_equal_approx(recovering_legacy.satisfaction, 0.01 + float(offset) * 0.05),
			"Elapsed supplied time moves both recovery residents five points per day toward 99%.")
		if offset < 10:
			_expect(recovering_resident.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
				and recovering_legacy.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED,
				"Residents below 50% have not applied yet.")
	_expect(
		recovering_resident.satisfaction >= CitizenData.MIN_APPLICANT_SATISFACTION
			and recovering_resident.employment_status == CitizenData.EmploymentStatus.APPLICANT
			and recovering_legacy.satisfaction >= CitizenData.MIN_APPLICANT_SATISFACTION
			and recovering_legacy.employment_status == CitizenData.EmploymentStatus.APPLICANT,
		"Ten fully supplied elapsed days recover both residents from 1% to the existing applicant threshold."
	)


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
	legacy_worker.satisfaction = 0.40
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
	_expect(is_equal_approx(linked_worker.get_resolved_satisfaction(), resident_before_shortage), "A linked worker's repeated same-minute shortage evaluation must not change the linked resident's satisfaction.")
	_expect(is_equal_approx(legacy_worker.satisfaction, legacy_before_shortage), "An unlinked worker's repeated same-minute shortage evaluation must not change satisfaction.")
	_expect(is_zero_approx(float(linked_result.satisfaction_delta)) and is_zero_approx(float(legacy_result.satisfaction_delta)), "Both worker summaries must report no instant satisfaction delta for a same-minute evaluation.")


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
	for resident: CitizenData in residents:
		initial_satisfaction.append(resident.satisfaction)

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
		_expect(is_equal_approx(resident.satisfaction, initial_satisfaction[index]), "A covered resident's instantaneous needs evaluation must not award satisfaction.")
	_expect(not residents[7].clothing_fulfilled, "The eighth resident must remain uncovered while physical clothing is short.")
	_expect(is_equal_approx(residents[7].satisfaction, initial_satisfaction[7]),
		"With food and shelter fulfilled, the uncovered resident does not move until elapsed time passes.")
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
	for resident: CitizenData in residents:
		before_summary_satisfaction.append(resident.satisfaction)

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

	_advance_to_day(base_day + 1)
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
	_expect(is_equal_approx(residents[7].satisfaction, initial_satisfaction[7] + 0.05),
		"One elapsed day moves the previously uncovered resident upward toward the 66% two-need target.")
	var eighth_worker: WorkerData = WorkerDatabase.get_worker_data(residents[7].citizen_id)
	var eighth_summary: Dictionary = CitizenNeedsManager.get_worker_needs_summary(eighth_worker)
	_assert_worker_summary(eighth_summary, base_day + 1, true, true, true, 7)
	_expect(is_zero_approx(float(eighth_summary.get("satisfaction_delta", 0.0))), "The recovered eighth resident's daily needs record must not claim an instant satisfaction delta.")
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
		"satisfaction", "satisfaction_delta", "missing"
	]:
		_expect(summary.has(key), "Worker needs summary must expose the '%s' field." % key)
	_assert_summary_without_reliability(summary)
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


func _assert_summary_without_reliability(summary: Dictionary) -> void:
	_expect(not summary.has("reliability") and not summary.has("reliability_delta"),
		"Worker needs summaries must not expose Reliability fields.")


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
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = 0
	TimeComponentManager.current_minute = 0
	_clear_need_tracking(day)
	_set_if_property(CitizenNeedsManager, "food_coverage_until", {})
	_rebase_satisfaction_cursors()


func _set_new_day(day: int) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = 0
	TimeComponentManager.current_minute = 0
	_set_if_property(CitizenNeedsManager, "_processing_daily_needs", false)
	_set_if_property(CitizenNeedsManager, "_processing_food", false)
	_set_if_property(CitizenNeedsManager, "_processing_clothing", false)
	# These manual clock moves arrange independent allocation fixtures. Rebase
	# the cursor so a later callback does not treat the jump as lived time.
	_rebase_satisfaction_cursors()


func _advance_to_day(day: int) -> void:
	var target_minute: int = day * 1440
	var current_minute: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	var elapsed: int = target_minute - current_minute
	if elapsed <= 0:
		return
	_expect(TimeComponentManager.advance_minutes(elapsed), "The isolated test clock must advance through real game minutes.")


func _rebase_satisfaction_cursors() -> void:
	var now: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	var cursors: Dictionary = {}
	for recipient: Dictionary in CitizenNeedsManager._get_food_recipients():
		var person: Variant = recipient.get("person")
		var person_id: String = str(CitizenNeedsManager._get_person_id(person))
		if not person_id.is_empty():
			cursors[person_id] = now
	_set_if_property(CitizenNeedsManager, "satisfaction_last_minute", cursors)


func _clear_need_tracking(day: int) -> void:
	_set_if_property(CitizenNeedsManager, "last_processed_day", day - 1)
	_set_if_property(CitizenNeedsManager, "last_food_processed_day", day - 1)
	_set_if_property(CitizenNeedsManager, "last_clothing_processed_day", day - 1)
	_set_if_property(CitizenNeedsManager, "_processing_daily_needs", false)
	_set_if_property(CitizenNeedsManager, "_processing_food", false)
	_set_if_property(CitizenNeedsManager, "_processing_clothing", false)
	_set_if_property(CitizenNeedsManager, "clothing_allocations", {})
	_set_if_property(CitizenNeedsManager, "last_needs_results", {})
	_set_if_property(CitizenNeedsManager, "food_coverage_until", {})
	_set_if_property(CitizenNeedsManager, "satisfaction_last_minute", {})


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
