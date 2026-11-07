extends "res://scenes/test_scenes/test_scene_city_transport_flow.gd"

## Persist a real loaded City Storage shipment after its worker reaches zero,
## then continue the same shipment and depart only after its one receipt.
const DEPARTURE_ITEM: String = "wood_log"
const FIXTURE_SATISFACTION: float = 0.01

var departure_left_ids: Array[String] = []
var departure_receipts: int = 0


func _write_flow() -> void:
	Inventory.add_item("shekel", 10)
	var day: int = TimeComponentManager.current_day
	# Set the clock before lowering the fixture's Satisfaction so the worker can
	# start a paid route without accruing any pre-route unmet-need interval.
	TimeComponentManager.current_hour = 14
	TimeComponentManager.current_minute = 54
	TimeComponentManager.emit_time_signal()
	var worker: WorkerData = WorkerDatabase.hire_applicant(worker_id, 1, 3)
	_expect(worker != null and worker.profession == WorkerData.Profession.HAULER
		and not worker.is_payroll_blocked(), "Hire the authored Hauler on a new paid contract.")
	if stopped or worker == null:
		return
	var citizen: CitizenData = worker.get_linked_citizen()
	_expect(citizen != null and central.allocate("initial_worksite_cart", worker_id)
		and central.has_equipped(worker_id, "cart"),
		"The real linked Hauler owns the authored city Cart.")
	if stopped or citizen == null:
		return
	central.items.clear()
	central.food_portions.clear()
	annex.items.clear()
	annex.food_portions.clear()
	CityStockManager.shelter_capacity = 0
	CitizenNeedsManager.last_processed_day = day
	CitizenNeedsManager.last_food_processed_day = day
	CitizenNeedsManager.last_clothing_processed_day = day
	citizen.satisfaction = FIXTURE_SATISFACTION
	worker.satisfaction = FIXTURE_SATISFACTION
	_expect(central.try_add_worksite_output(DEPARTURE_ITEM, 3),
		"Seed exactly three city-owned logs through the receipt API.")
	if stopped:
		return
	_expect(transport.start(worker_id, "city", DEPARTURE_ITEM, 3),
		"Start a real Central Storage to Annex Hauler shipment before shift end.")
	_expect(int(transport.route.get("quantity", 0)) == 3
		and int(central.items.get(DEPARTURE_ITEM, 0)) == 0,
		"The route owns the three loaded logs exactly once.")
	if stopped:
		return
	_expect(TimeComponentManager.advance_minutes(1), "Move the loaded Hauler before holding the route.")
	var position: Vector2 = Vector2(transport.get_visual(float(now())).position)
	var target: Vector2 = transport._leg_target(transport.route)
	var center: Vector2 = position.move_toward(target, 10.0) + transport.FEET_OFFSET
	var polygons: Array[PackedVector2Array] = runtime.worksite_navigation.polygons.duplicate()
	polygons.append(PackedVector2Array([center + Vector2(-1, -1), center + Vector2(1, -1),
		center + Vector2(1, 1), center + Vector2(-1, 1)]))
	runtime.worksite_navigation.replace_polygons(polygons)
	_expect(TimeComponentManager.advance_minutes(1440 - (now() % 1440)),
		"Advance through midnight while the loaded route is blocked safely.")
	await _frames(2)
	_expect(citizen.satisfaction == 0.0 and worker.resignation_pending
		and bool(transport.route.get("resigning", false))
		and int(transport.route.get("quantity", 0)) == 3
		and citizen.population_status == CitizenData.PopulationStatus.RESIDENT,
		"Daily needs reach exact zero, latch resignation, and retain the resident and loaded cargo.")
	_expect(central.items.get(DEPARTURE_ITEM, 0) == 0
		and int(annex.items.get(DEPARTURE_ITEM, 0)) == 0,
		"No destination receipt occurs before the pending shipment is saved.")
	_expect(store.save_checkpoint(), "Save the loaded pending departure: " + store.last_error)


func _read_flow() -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
	var citizen: CitizenData = CitizenManager.get_citizen(worker_id)
	_expect(worker != null and citizen != null and worker.resignation_pending
		and bool(transport.route.get("resigning", false))
		and int(transport.route.get("quantity", -1)) == 3
		and citizen.population_status == CitizenData.PopulationStatus.RESIDENT,
		"Continue restores the same pending worker, resident and loaded cargo.")
	if stopped or worker == null or citizen == null:
		return
	var on_left := func(departed: CitizenData) -> void:
		departure_left_ids.append(departed.citizen_id)
	var on_receipt := func() -> void:
		if int(annex.items.get(DEPARTURE_ITEM, 0)) == 3:
			departure_receipts += 1
	CitizenManager.citizen_left.connect(on_left)
	annex.changed.connect(on_receipt)
	# Satisfaction recovery after Continue must not clear resignation_pending.
	citizen.satisfaction = 0.8
	WorkerDatabase.resign_idle_workers_at_zero()
	transport.tick(now())
	transport.tick(now())
	_expect(worker.resignation_pending and WorkerDatabase.has_worker_data(worker_id)
		and int(transport.route.get("quantity", 0)) == 3 and departure_receipts == 0,
		"Recovered Satisfaction and repeated callbacks cannot cancel or duplicate the pending load.")
	if stopped:
		return
	await _finish_route()
	_expect(transport.route.is_empty() and departure_receipts == 1
		and int(central.items.get(DEPARTURE_ITEM, 0)) == 0
		and int(annex.items.get(DEPARTURE_ITEM, 0)) == 3,
		"Continue completes the original three-log delivery with one receipt.")
	_expect(citizen.population_status == CitizenData.PopulationStatus.LEFT_CITY
		and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and not WorkerDatabase.has_worker_data(worker_id)
		and WorkerDatabase.dismissed_workers.get(worker_id) == worker
		and not central.has_equipped(worker_id, "cart")
		and departure_left_ids == [worker_id],
		"After receipt the same citizen leaves once, the worker is archived, and the Cart is released.")
	transport.tick(now())
	transport.tick(now())
	WorkerDatabase.resign_idle_workers_at_zero()
	transport.tick(now())
	_expect(departure_receipts == 1 and departure_left_ids == [worker_id]
		and int(annex.items.get(DEPARTURE_ITEM, 0)) == 3,
		"Repeated route and resignation callbacks cannot re-receive cargo or repeat departure.")
	CitizenManager.citizen_left.disconnect(on_left)
	annex.changed.disconnect(on_receipt)
	_expect(store.save_checkpoint(), "Save the completed departure: " + store.last_error)
	var completed_bytes: PackedByteArray = FileAccess.get_file_as_bytes(SAVE_PATH)
	_expect(store.load_checkpoint() and FileAccess.get_file_as_bytes(SAVE_PATH) == completed_bytes
		and CitizenManager.get_citizen(worker_id).population_status == CitizenData.PopulationStatus.LEFT_CITY
		and WorkerDatabase.dismissed_workers.has(worker_id),
		"A second Continue preserves the departed citizen without reapplying delivery or resignation.")
