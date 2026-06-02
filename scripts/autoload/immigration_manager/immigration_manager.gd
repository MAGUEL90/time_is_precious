extends Node

signal immigration_requested(candidates: Array[CitizenData])

var pending_immigrants: Array[CitizenData] = []
var immigration_pressure: float = 0.0
var base_daily_chance: float = 0.04
var max_pressure_bonus: float = 0.25
var debug_immigration: bool = false
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	TimeComponentManager.new_day_started.connect(_on_new_day_started)

func _on_new_day_started(_day: int) -> void:
	call_deferred("evaluate_immigration")

func spawn_immigration(amount: int) -> void:
	if not pending_immigrants.is_empty():
		return
	
	for i in range(amount):
		var generated_citizen: CitizenData = CitizenGenerator.generate_citizen()
		generated_citizen.status = CitizenData.CitizenStatus.NONE
		pending_immigrants.append(generated_citizen)
	
	immigration_requested.emit(pending_immigrants.duplicate())


func accept_pending_immigrants() -> bool:
	if pending_immigrants.is_empty():
		return false
		
	for immigrant in pending_immigrants:
		immigrant.status = CitizenData.CitizenStatus.CITIZEN
		CitizenManager.add_citizen(immigrant)
	pending_immigrants.clear()
	return true

func reject_pending_immigrants() -> bool:
	if pending_immigrants.is_empty():
		return false
		
	pending_immigrants.clear()
	return true

func evaluate_immigration() -> void:
	var total_citizen: int = CitizenManager.get_all_citizens().size()
	
	if not pending_immigrants.is_empty():
		return
	
	var satisfaction_score: float = CitizenNeedsManager.get_average_satisfaction()
	var satisfaction_bonus: float = satisfaction_score * 0.10
	var needs_bonus: float = 0.0
	
	var ready_need_count: int = 0
	var standard_food_supply: bool = CityStockManager.has_food_supply(total_citizen)
	var standard_cloth_supply: bool = CityStockManager.has_clothing_supply(total_citizen)
	var standard_shelter_supply: bool = CityStockManager.has_shelter_capacity(total_citizen)
	
	if standard_food_supply:
		ready_need_count += 1
		needs_bonus += 0.03
	if standard_cloth_supply:
		ready_need_count += 1
		needs_bonus += 0.03
	if standard_shelter_supply:
		ready_need_count += 1
		needs_bonus += 0.04
	
	var pressure_gain: float = 0.0
	
	if ready_need_count == 1:
		pressure_gain = 0.003
	elif ready_need_count == 2:
		pressure_gain = 0.006
	elif ready_need_count == 3:
		pressure_gain = 0.01
	
	var population_penalty: float = total_citizen * 0.01
	var progress_bonus: float = _get_progress_bonus()
	
	var daily_chance: float = (base_daily_chance + satisfaction_bonus + needs_bonus + progress_bonus + immigration_pressure) - population_penalty
	daily_chance = clampf(daily_chance, 0.0, 0.65)

	if debug_immigration:
		print("immigration chance: ", daily_chance, " pressure: ", immigration_pressure)

	var immigration_roll: float = rng.randf()
	if immigration_roll < daily_chance:
		spawn_immigration(_roll_batch_size())
		immigration_pressure = 0
	else:
		immigration_pressure = min(immigration_pressure + pressure_gain, max_pressure_bonus)

func _roll_batch_size() -> int:
	var roll: float = rng.randf()
	if roll < 0.7:
		return 1
	elif roll < 0.95:
		return 2
	else:
		return 3

func _get_progress_bonus() -> float:
	return 0.0
	
