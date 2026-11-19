extends "res://scenes/test_scenes/mvp_first_playthrough.gd"

## Holds a paid city hauler's real City Storage -> Annex cargo across daily
## needs settlement, then lets the one committed shipment finish resignation.
const WORKER_ID: String = "initial_city_storage_hauler"
const ITEM_ID: String = "wood_log"
const FIXTURE_DAY: int = 12
const SATISFACTION_PER_MINUTE: float = 0.05 / 1440.0

var transport: Node
var central: Node
var annex: Node
var needs_events: int = 0
var annex_receipts: int = 0
var resignation_ready_ids: Array[String] = []


func _run() -> void:
	get_tree().current_scene = null
	TimeComponentManager.set_process(false)
	var menu = MENU.instantiate()
	menu.session_started.connect(func(_from_save: bool):
		launched = true)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	await press(menu.new_game_button)
	for _frame: int in range(1200):
		if launched or stopped:
			break
		await get_tree().process_frame
	_expect(launched, "A fresh authored city opens without loading or writing a checkpoint.")
	if stopped:
		return
	bind_map()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	transport = WorkStateRuntime.get_node("CityStorageTransport")
	central = transport.get_storage("city")
	annex = transport.get_storage("annex")
	_expect(central == WorkStateRuntime.get_node("CityToolStorage")
		and runtime.has_node("CityStorageAnnex"),
		"Use the real city-owned Central Storage and Annex on the authored map.")
	if stopped:
		return

	# No city provisions exist in this fixture; the wood transfer is the only item.
	central.items.clear()
	central.food_portions.clear()
	annex.items.clear()
	annex.food_portions.clear()
	CityStockManager.food_supply = 0
	CityStockManager.clothing_supply = 0
	CityStockManager.shelter_capacity = 0
	CitizenNeedsManager.clothing_allocations.clear()
	CitizenNeedsManager.last_needs_results.erase(WORKER_ID)

	_place_fixture_clock(FIXTURE_DAY, 14, 54)
	var applicant: CitizenData = CitizenManager.get_citizen(WORKER_ID)
	var contract_price: int = WorkerDatabase.get_contract_price(applicant.profession, 3) if applicant != null else -1
	var wallet_before: int = int(Inventory.items.get("shekel", 0))
	_expect(applicant != null and contract_price > 0,
		"The authored city Hauler applicant and a valid paid contract are available.")
	if stopped:
		return
	Inventory.add_item("shekel", contract_price)
	var funded_wallet: int = int(Inventory.items.get("shekel", 0))
	var worker: WorkerData = WorkerDatabase.hire_applicant(WORKER_ID, 1, 3)
	_expect(worker != null and worker.profession == WorkerData.Profession.HAULER
		and worker.payroll_contract_days == 3 and not worker.is_payroll_blocked()
		and int(Inventory.items.get("shekel", 0)) == funded_wallet - contract_price,
		"Hire and pay the linked Hauler for a normal three-day contract.")
	if stopped:
		return
	_expect(central.allocate("initial_worksite_cart", WORKER_ID)
		and central.has_equipped(WORKER_ID, "cart"),
		"Equip the Hauler with the authored city Cart.")
	_expect(central.try_add_worksite_output(ITEM_ID, 3),
		"Seed exactly three city-owned logs through the production receipt API.")
	if stopped:
		return

	var citizen: CitizenData = worker.get_linked_citizen()
	_expect(citizen == applicant and citizen.employment_status == CitizenData.EmploymentStatus.HIRED,
		"The paid Hauler remains linked to the real resident citizen.")
	if stopped:
		return
	# The fixture day is already evaluated; its final unmet-need interval lands
	# exactly on zero at midnight under the approved per-minute rate.
	CitizenNeedsManager.last_processed_day = FIXTURE_DAY
	CitizenNeedsManager.last_food_processed_day = FIXTURE_DAY
	CitizenNeedsManager.last_clothing_processed_day = FIXTURE_DAY
	CitizenNeedsManager.food_coverage_until.erase(WORKER_ID)
	CitizenNeedsManager.clothing_allocations.erase(WORKER_ID)
	CitizenNeedsManager.last_needs_results.erase(WORKER_ID)
	citizen.food_fulfilled = false
	citizen.clothing_fulfilled = false
	citizen.shelter_fulfilled = false
	worker.food_fulfilled = false
	worker.clothing_fulfilled = false
	worker.shelter_fulfilled = false
	var minutes_until_midnight: int = 1440 - (now() % 1440)
	var initial_satisfaction: float = float(minutes_until_midnight - 0.5) * SATISFACTION_PER_MINUTE
	citizen.satisfaction = initial_satisfaction
	worker.satisfaction = initial_satisfaction
	CitizenNeedsManager.satisfaction_last_minute[WORKER_ID] = now()
	_expect(transport.start(WORKER_ID, "city", ITEM_ID, 3),
		"Start a real outbound three-log City Storage -> Annex shipment before shift end.")
	_expect(int(central.items.get(ITEM_ID, 0)) == 0
		and int(transport.route.get("quantity", 0)) == 3 and _city_total() == 3,
		"Pickup transfers the three logs into the in-flight route exactly once.")
	if stopped:
		return
	var original_polygons: Array[PackedVector2Array] = runtime.worksite_navigation.polygons.duplicate()
	var source_position: Vector2 = Vector2(transport.get_visual(float(now())).position)
	_expect(TimeComponentManager.advance_minutes(1), "Move the loaded Hauler one minute before blocking its route.")
	var position: Vector2 = Vector2(transport.get_visual(float(now())).position)
	var target: Vector2 = transport._leg_target(transport.route)
	_expect(position.distance_to(source_position) > 0.1 and position.distance_to(target) > 20.0,
		"The loaded Hauler has moved from Central Storage and still has room ahead for an obstacle.")
	if stopped:
		return
	_block_ahead(original_polygons, position, target)
	_expect(runtime.worksite_navigation.is_clear(position + transport.FEET_OFFSET)
		and not runtime.worksite_navigation.segment_clear(position + transport.FEET_OFFSET,
			position.move_toward(target, 10.0) + transport.FEET_OFFSET),
		"The obstacle blocks the next route segment while leaving the courier's current feet clear.")
	if stopped:
		return
	var paid_until: int = worker.payroll_paid_until_day
	var contract_days: int = worker.payroll_contract_days
	var conservation: Dictionary = {"ok": true, "observations": 0}
	var observe_conservation := func() -> void:
		conservation.observations = int(conservation.observations) + 1
		conservation.ok = bool(conservation.ok) and _city_total() == 3
	var count_receipt := func() -> void:
		annex_receipts += 1
	central.changed.connect(observe_conservation)
	annex.changed.connect(observe_conservation)
	transport.changed.connect(observe_conservation)
	annex.changed.connect(count_receipt)
	CitizenNeedsManager.needs_changed.connect(_on_needs_changed)
	transport.resignation_ready.connect(_on_resignation_ready)

	var minutes_to_midnight: int = 1440 - (now() % 1440)
	_expect(TimeComponentManager.advance_minutes(minutes_to_midnight - 1),
		"Advance the obstructed loaded route to 23:59 before the final midnight minute.")
	await _frames(2)
	_expect(now() == (FIXTURE_DAY + 1) * 1440 - 1 and citizen.satisfaction > 0.0
		and WorkerDatabase.has_worker_data(WORKER_ID) and not worker.resignation_pending
		and not bool(transport.route.get("resigning", false))
		and int(transport.route.get("quantity", 0)) == 3 and annex_receipts == 0
		and _city_total() == 3 and CitizenNeedsManager.last_processed_day == FIXTURE_DAY,
		"At 23:59 the resident remains positive and active while all three loaded logs stay conserved.")
	var needs_events_before_midnight: int = needs_events
	_expect(TimeComponentManager.advance_minutes(1), "Advance the final minute into midnight needs settlement.")
	await _frames(2)
	_expect(now() == (FIXTURE_DAY + 1) * 1440,
		"The clock crosses exactly from fixture day %d to day %d at 00:00." % [FIXTURE_DAY, FIXTURE_DAY + 1])
	var result: Dictionary = CitizenNeedsManager.last_needs_results.get(WORKER_ID, {})
	_expect(CitizenNeedsManager.last_processed_day == FIXTURE_DAY + 1
		and is_equal_approx(citizen.satisfaction, 0.0)
		and bool(result.get("evaluated", false))
		and int(result.get("day", -1)) == FIXTURE_DAY + 1
		and is_equal_approx(float(result.get("satisfaction_delta", 99.0)), 0.0),
		"The real midnight ledger records zero daily delta while the elapsed-minute interval reaches exact zero.")
	_expect(not bool(result.get("food", true)) and not bool(result.get("clothing", true))
		and not bool(result.get("shelter", true))
		and result.get("missing", []).size() == 3,
		"The resident has no food, clothing or shelter fulfillment for the tested day.")
	_expect(needs_events == needs_events_before_midnight + 1,
		"The midnight settlement emits exactly one daily needs event after the 23:59 snapshot.")
	_expect(WorkerDatabase.has_worker_data(WORKER_ID) and worker.resignation_pending
		and worker.is_reserved() and bool(transport.route.get("resigning", false))
		and int(transport.route.get("quantity", 0)) == 3
		and citizen.employment_status == CitizenData.EmploymentStatus.ASSIGNED,
		"Zero Satisfaction marks resignation pending while retaining the assigned courier and loaded cargo.")
	_expect(worker.payroll_paid_until_day == paid_until and worker.payroll_contract_days == contract_days
		and not worker.is_payroll_blocked() and central.has_equipped(WORKER_ID, "cart")
		and _city_total() == 3,
		"The active paid contract and allocated Cart remain until the cargo transaction completes.")
	if stopped:
		return

	var settlement_snapshot: Dictionary = result.duplicate(true)
	CitizenNeedsManager.process_daily_needs()
	transport.tick(now())
	transport.tick(now())
	_expect(needs_events == needs_events_before_midnight + 1
		and CitizenNeedsManager.last_needs_results.get(WORKER_ID, {}) == settlement_snapshot
		and is_equal_approx(citizen.satisfaction, 0.0)
		and int(transport.route.get("quantity", 0)) == 3 and annex_receipts == 0
		and _city_total() == 3,
		"Duplicate same-day needs and transport callbacks neither re-evaluate nor duplicate the pending load.")
	if stopped:
		return

	runtime.worksite_navigation.replace_polygons(original_polygons)
	await _finish_route()
	_expect(transport.route.is_empty() and annex_receipts == 1
		and int(central.items.get(ITEM_ID, 0)) == 0
		and int(annex.items.get(ITEM_ID, 0)) == 3
		and _city_total() == 3 and bool(conservation.ok)
		and int(conservation.observations) > 0,
		"The Annex receives exactly one committed load and every storage/route observer sees conserved stock.")
	_expect(resignation_ready_ids == [WORKER_ID]
		and not WorkerDatabase.has_worker_data(WORKER_ID)
		and WorkerDatabase.dismissed_workers.get(WORKER_ID) == worker
		and citizen.population_status == CitizenData.PopulationStatus.LEFT_CITY
		and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and worker.payroll_contract_days == 0 and worker.payroll_start_day == -1
		and not central.has_equipped(WORKER_ID, "cart"),
		"After receipt the resident is unemployed, the same WorkerData is dismissed, contract ends and Cart is released once.")
	if stopped:
		return
	transport.tick(now())
	transport.tick(now())
	_expect(transport.route.is_empty() and annex_receipts == 1
		and resignation_ready_ids == [WORKER_ID] and _city_total() == 3,
		"Later transport callbacks do not re-receive the shipment or repeat resignation.")
	if stopped:
		return
	print("CityTransportMidnightResignationTest: PASS")
	get_tree().quit(0)


func _place_fixture_clock(day: int, hour: int, minute: int) -> void:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = hour
	TimeComponentManager.current_minute = minute
	TimeComponentManager.emit_time_signal()


func _block_ahead(original: Array[PackedVector2Array], position: Vector2, target: Vector2) -> void:
	var center: Vector2 = position.move_toward(target, 10.0) + transport.FEET_OFFSET
	var blocked: Array[PackedVector2Array] = original.duplicate()
	blocked.append(PackedVector2Array([center + Vector2(-1, -1), center + Vector2(1, -1),
		center + Vector2(1, 1), center + Vector2(-1, 1)]))
	runtime.worksite_navigation.replace_polygons(blocked)


func _city_total() -> int:
	return int(central.items.get(ITEM_ID, 0)) + int(annex.items.get(ITEM_ID, 0)) \
		+ int(transport.route.get("quantity", 0))


func _finish_route() -> void:
	for minute: int in range(600):
		if transport.route.is_empty() or stopped:
			return
		_expect(TimeComponentManager.advance_minutes(1), "Advance one minute until the loaded city transfer settles.")
		if minute % 10 == 0:
			await _frames(1)
	_expect(transport.route.is_empty(), "The city transfer settles within the bounded route window.")


func _on_needs_changed() -> void:
	needs_events += 1


func _on_resignation_ready(worker_id: String) -> void:
	resignation_ready_ids.append(worker_id)
