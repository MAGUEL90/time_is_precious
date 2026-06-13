extends Node

const FOOD_SUPPLY_PER_CITIZEN_PER_DAY: int = 1
const CLOTHING_SUPPLY_PER_CITIZEN_PER_DAY: int = 1
const FOOD_SUPPLY_PER_WORKER_PER_DAY: int = 1
const CLOTHING_SUPPLY_PER_WORKER_PER_DAY: int = 1

var last_food_fulfilled_count: int = 0
var last_food_unfulfilled_count: int = 0
var last_clothing_fulfilled_count: int = 0
var last_clothing_unfulfilled_count: int = 0
var last_shelter_capacity_fulfilled_count: int = 0
var last_shelter_capacity_unfulfilled_count: int = 0

func _ready() -> void:
	TimeComponentManager.new_day_started.connect(on_new_day_started)

func on_new_day_started(_day: int) -> void:
	process_daily_needs()

func process_daily_needs() -> void:
	process_daily_food_needs()
	process_daily_clothing_needs()
	process_daily_shelter_capacity_needs()

	var citizens: Array = CitizenManager.get_all_citizens()
	for citizen in citizens:
		if not (citizen is CitizenData):
			continue
		if citizen.are_basic_needs_fulfilled():
			citizen.satisfaction = clampf(citizen.satisfaction + 0.05, 0.01, 0.99)
			citizen.reliability = clampf(citizen.reliability + 0.03, 0.01, 0.99)
		else:
			citizen.satisfaction = clampf(citizen.satisfaction - 0.10, 0.01, 0.99)
			citizen.reliability = clampf(citizen.reliability - 0.05, 0.01, 0.99)

	process_daily_worker_needs()

func process_daily_worker_needs() -> void:
	# Worker diproses setelah citizen agar citizen tetap dapat prioritas stok.
	# Sisa shelter dihitung dari kapasitas dikurangi yang sudah terpakai citizen.
	var remaining_shelter_capacity: int = CityStockManager.shelter_capacity - last_shelter_capacity_fulfilled_count

	for worker in WorkerDatabase.get_all_workers():
		if not (worker is WorkerData):
			continue

		var worker_data: WorkerData = worker as WorkerData
		worker_data.food_fulfilled = CityStockManager.consume_food_supply(FOOD_SUPPLY_PER_WORKER_PER_DAY)
		worker_data.clothing_fulfilled = CityStockManager.consume_clothing_supply(CLOTHING_SUPPLY_PER_WORKER_PER_DAY)

		if remaining_shelter_capacity > 0:
			remaining_shelter_capacity -= 1
			worker_data.shelter_fulfilled = true
		else:
			worker_data.shelter_fulfilled = false

		if worker_data.are_basic_needs_fulfilled():
			worker_data.satisfaction = clampf(worker_data.satisfaction + 0.05, 0.01, 0.99)
			worker_data.reliability = clampf(worker_data.reliability + 0.03, 0.01, 0.99)
		else:
			worker_data.satisfaction = clampf(worker_data.satisfaction - 0.10, 0.01, 0.99)
			worker_data.reliability = clampf(worker_data.reliability - 0.05, 0.01, 0.99)

func process_daily_food_needs() -> void:
	last_food_fulfilled_count = 0
	last_food_unfulfilled_count = 0

	var citizens: Array = CitizenManager.get_all_citizens()

	for citizen in citizens:
		if not (citizen is CitizenData):
			continue
		var citizen_data: CitizenData = citizen as CitizenData
		var consume_result: bool = CityStockManager.consume_food_supply(FOOD_SUPPLY_PER_CITIZEN_PER_DAY)
		citizen_data.food_fulfilled = consume_result

		if consume_result:
			last_food_fulfilled_count += 1
		else:
			last_food_unfulfilled_count += 1

func process_daily_clothing_needs() -> void:
	last_clothing_fulfilled_count = 0
	last_clothing_unfulfilled_count = 0

	var citizens: Array = CitizenManager.get_all_citizens()

	for citizen in citizens:
		if not (citizen is CitizenData):
			continue

		var citizen_data: CitizenData = citizen as CitizenData
		var consume_result: bool = CityStockManager.consume_clothing_supply(CLOTHING_SUPPLY_PER_CITIZEN_PER_DAY)

		citizen_data.clothing_fulfilled = consume_result

		if consume_result:
			last_clothing_fulfilled_count += 1
		else:
			last_clothing_unfulfilled_count += 1

func process_daily_shelter_capacity_needs() -> void:
	last_shelter_capacity_fulfilled_count = 0
	last_shelter_capacity_unfulfilled_count = 0
	
	var citizens: Array = CitizenManager.get_all_citizens()
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

func get_citizen_count() -> int:
	var citizens: Array = CitizenManager.get_all_citizens()

	return citizens.size()

func get_daily_food_supply_need() -> int:
	return get_citizen_count() * FOOD_SUPPLY_PER_CITIZEN_PER_DAY

func get_daily_clothing_supply_need() -> int:
	return get_citizen_count() * CLOTHING_SUPPLY_PER_CITIZEN_PER_DAY

func get_daily_shelter_capacity_need() -> int:
	return get_citizen_count()

func get_average_satisfaction() -> float:
	var citizens: Array = CitizenManager.get_all_citizens()
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
