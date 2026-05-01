extends Node

const FOOD_SUPPLY_PER_CITIZEN_PER_DAY: int = 1
const CLOTHING_SUPPLY_PER_CITIZEN_PER_DAY: int = 1

var last_food_fulfilled_count: int = 0
var last_food_unfulfilled_count: int = 0
var last_clothing_fulfilled_count: int = 0
var last_clothing_unfulfilled_count: int = 0

func _ready() -> void:
	TimeComponentManager.new_day_started.connect(on_new_day_started)

func on_new_day_started(_day: int) -> void:
	process_daily_needs()

func process_daily_needs() -> void:
	process_daily_food_needs()
	process_daily_clothing_needs()

func process_daily_food_needs() -> void:
	last_food_fulfilled_count = 0
	last_food_unfulfilled_count = 0

	var citizens: Array = WorkerDatabase.get_all_workers()

	for citizen in citizens:
		if not (citizen is WorkerData):
			continue
		var citizen_worker: WorkerData = citizen as WorkerData
		var consume_result: bool = CityStockManager.consume_food_supply(FOOD_SUPPLY_PER_CITIZEN_PER_DAY)
		citizen_worker.food_fulfilled = consume_result

		if consume_result:
			last_food_fulfilled_count += 1
		else:
			last_food_unfulfilled_count += 1

func process_daily_clothing_needs() -> void:
	last_clothing_fulfilled_count = 0
	last_clothing_unfulfilled_count = 0

	var citizens: Array = WorkerDatabase.get_all_workers()

	for citizen in citizens:
		if not (citizen is WorkerData):
			continue

		var citizen_worker: WorkerData = citizen as WorkerData
		var consume_result: bool = CityStockManager.consume_clothing_supply(CLOTHING_SUPPLY_PER_CITIZEN_PER_DAY)

		citizen_worker.clothing_fulfilled = consume_result

		if consume_result:
			last_clothing_fulfilled_count += 1
		else:
			last_clothing_unfulfilled_count += 1

func get_citizen_count() -> int:
	var citizens: Array = WorkerDatabase.get_all_workers()

	return citizens.size()

func get_daily_food_supply_need() -> int:
	return get_citizen_count() * FOOD_SUPPLY_PER_CITIZEN_PER_DAY

func get_daily_clothing_supply_need() -> int:
	return get_citizen_count() * CLOTHING_SUPPLY_PER_CITIZEN_PER_DAY
