extends Node

const FOOD_SUPPLY_PER_CITIZEN_PER_DAY: int = 1

func _ready() -> void:
	TimeComponentManager.new_day_started.connect(on_new_day_started)

func on_new_day_started(_day: int) -> void:
	process_daily_needs()

func process_daily_needs() -> void:
	process_daily_food_needs()

func process_daily_food_needs() -> void:
	var citizens: Array = WorkerDatabase.get_all_workers()
	
	for citizen in citizens:
		if not (citizen is WorkerData):
			continue
		var citizen_worker: WorkerData = citizen as WorkerData
		var consume_result: bool = CityStockManager.consume_food_supply(FOOD_SUPPLY_PER_CITIZEN_PER_DAY)
		citizen_worker.food_fulfilled = consume_result
