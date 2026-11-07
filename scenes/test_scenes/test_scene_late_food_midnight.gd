extends Node

const STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const RATE: float = 0.05 / 1440.0
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 20
	TimeComponentManager.current_hour = 0
	TimeComponentManager.current_minute = 0
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	CitizenNeedsManager.food_coverage_until.clear()
	CitizenNeedsManager.satisfaction_last_minute.clear()
	CitizenNeedsManager.clothing_allocations.clear()
	CitizenNeedsManager.last_needs_results.clear()
	CitizenNeedsManager.last_processed_day = 20
	CitizenNeedsManager.last_food_processed_day = 20
	CitizenNeedsManager.last_clothing_processed_day = 20
	CityStockManager.shelter_capacity = 0
	var storage: Node = WorkStateRuntime.get_node_or_null("CityToolStorage")
	if storage == null:
		storage = STORAGE_SCRIPT.new()
		storage.name = "CityToolStorage"
		WorkStateRuntime.add_child(storage)
	storage.items.clear()
	storage.food_portions.clear()
	var person := CitizenData.new()
	person.citizen_id = "late_midnight"
	person.display_name = "Late food"
	person.population_status = CitizenData.PopulationStatus.RESIDENT
	person.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	person.satisfaction = 0.3
	CitizenManager.add_citizen(person)
	await get_tree().process_frame
	_expect(TimeComponentManager.advance_minutes(1439), "Advance the first 23 hours and 59 minutes without food.")
	var before_delivery: float = person.satisfaction
	_expect(absf(before_delivery - (0.3 - 1439.0 * RATE)) < 0.000002, "The preceding shortage is accumulated by 23:59.")
	_expect(storage.try_add_worksite_output("barley_bread", 1), "Deliver one real ration at 23:59.")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(absf(person.satisfaction - before_delivery) < 0.0000001 and person.food_fulfilled
		and storage.get_food_supply_points() == 0, "Late delivery consumes one point but does not erase the previous shortage.")
	_expect(TimeComponentManager.advance_minutes(1), "Advance the one covered minute across midnight.")
	_expect(absf(person.satisfaction - (before_delivery + RATE)) < 0.000002,
		"Midnight applies only one covered minute, never a daily Satisfaction jump.")
	print("LateFoodMidnightTest: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
