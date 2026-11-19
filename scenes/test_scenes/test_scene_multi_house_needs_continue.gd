extends "res://scenes/test_scenes/test_scene_house_save_migration.gd"

## End-to-end on a test-only city projection with two independently built
## houses and seven paid Laborers. Funds, materials and supplies are grants.
const EXTRA_HOUSE: PackedScene = preload("res://scenes/citizen_house_plot/citizen_house_plot.tscn")
const EXTRA_ID: String = "citizen_house_2"
var second: Node

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_reset_singletons_before_load()
	await _load_root_city()
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	house_state = content.get_node("YSortWorld/CitizenHousePlot").construction
	_attach_second_house()
	_select_house_path(test_root.path_join("two_houses.json"))
	Inventory.max_load = 1000.0
	Inventory.add_item("wood_log", 8)
	Inventory.add_item("clay_lump", 16)
	Inventory.add_item("reed_bundle", 12)
	_expect(CityStockManager.shelter_capacity == 0, "The isolated New Game starts without shelter.")
	if not _complete_house(house_state):
		_finish_multi_needs()
		return
	_expect(CityStockManager.shelter_capacity == 3 and second.phase == "uncleared", "The first real house contributes exactly three places.")
	if not _complete_house(second):
		_finish_multi_needs()
		return
	_expect(CityStockManager.shelter_capacity == 6, "The two completed houses contribute exactly six places.")
	for iteration: int in range(3):
		house_state.changed.emit()
		second.changed.emit()
	_expect(CityStockManager.shelter_capacity == 6, "Repeated completion signals do not grant extra shelter.")
	_expect(store.save_checkpoint(), "Both completed houses save: " + store.last_error)
	for iteration: int in range(2):
		_expect(store.load_checkpoint() and house_state.phase == "built" and second.phase == "built"
			and CityStockManager.shelter_capacity == 6, "Repeated Continue retains both houses and six places.")
	if not await _test_two_houses_from_home():
		_finish_multi_needs()
		return
	# Replace the original applicants with seven explicitly registered and paid
	# test Laborers so every consumer below is a real linked hired worker.
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	Inventory.add_item("shekel", 30)
	var ids: Array[String] = []
	for index: int in range(7):
		var id: String = "housing_need_worker_%d" % index
		var citizen := CitizenData.new()
		citizen.citizen_id = id
		citizen.display_name = id
		citizen.population_status = CitizenData.PopulationStatus.RESIDENT
		citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
		citizen.satisfaction = 0.8
		CitizenManager.add_citizen(citizen)
		_expect(CitizenManager.register_applicant(id, WorkerData.Profession.LABORER), "The fixture Laborer can apply.")
		_expect(WorkerDatabase.hire_applicant(id, 1, 9) != null, "The fixture Laborer has a paid contract.")
		ids.append(id)
	_expect(CitizenManager.get_all_residents().size() == 7 and WorkerDatabase.get_all_workers().size() == 7, "Exactly seven citizens are also workers.")
	Inventory.add_item("barley_bread", 14)
	Inventory.add_item("simple_clothes", 7)
	var city_tools: Node = WorkStateRuntime.get_node("CityToolStorage")
	var supplied: Dictionary = city_tools.deposit_items_from_inventory({"barley_bread": 14, "simple_clothes": 7})
	_expect(bool(supplied.get("ok", false)), "Test food and clothing enter the real City Storage.")
	var day: int = TimeComponentManager.current_day
	var to_midnight: int = 1440 - TimeComponentManager.current_hour * 60 - TimeComponentManager.current_minute
	_expect(TimeComponentManager.advance_minutes(to_midnight), "The actual game clock reaches the daily needs pass.")
	_expect(TimeComponentManager.current_day == day + 1 and CityStockManager.shelter_capacity == 6
		and CitizenNeedsManager.last_shelter_capacity_fulfilled_count == 6
		and CitizenNeedsManager.last_shelter_capacity_unfulfilled_count == 1,
		"Seven linked workers consume six house places once, leaving exactly one short.")
	for index: int in range(ids.size()):
		var citizen: CitizenData = CitizenManager.get_citizen(ids[index])
		var worker: WorkerData = WorkerDatabase.get_worker_data(ids[index])
		var has_shelter: bool = index < 6
		_expect(citizen != null and worker != null and worker.get_linked_citizen() == citizen
			and citizen.shelter_fulfilled == has_shelter and citizen.food_fulfilled and citizen.clothing_fulfilled
			and is_equal_approx(citizen.satisfaction, 0.85 if has_shelter else 0.75),
			"Each worker receives the correct individual needs and Satisfaction result.")
	_expect(store.save_checkpoint(), "The housing shortage and both completed houses save: " + store.last_error)
	for iteration: int in range(2):
		_expect(store.load_checkpoint() and CityStockManager.shelter_capacity == 6
			and CitizenNeedsManager.last_shelter_capacity_fulfilled_count == 6
			and CitizenNeedsManager.last_shelter_capacity_unfulfilled_count == 1
			and house_state.phase == "built" and second.phase == "built",
			"Continue keeps shelter capacity and the recorded shortage without duplication.")
	_finish_multi_needs()

func _complete_house(state: Node) -> bool:
	if not bool(state.start_clearing([] as Array[String], true).get("success", false)):
		_expect(false, "Player starts the house's cleaning.")
		return false
	if not TimeComponentManager.advance_minutes(state.CLEARING_MINUTES) or state.phase != "empty":
		_expect(false, "Cleaning completes through the real clock.")
		return false
	if not bool(state.start_build([] as Array[String], true).get("success", false)):
		_expect(false, "Player starts the house using its own materials.")
		return false
	while state.phase == "building":
		var minutes: int = mini(180, state._remaining_work_units())
		if minutes <= 0 or not TimeComponentManager.advance_minutes(minutes):
			_expect(false, "A bounded player work session advances.")
			return false
		if state.phase == "building":
			state.interrupt_player_work()
			if not bool(state.resume_player_work().get("success", false)):
				_expect(false, "The next bounded player session resumes without new materials.")
				return false
	return state.phase == "built"

func _attach_second_house() -> void:
	# The second view is a test-only projection; the authored map is untouched.
	var extra = EXTRA_HOUSE.instantiate()
	extra.name = "FixtureSecondHouse"
	extra.plot_id = EXTRA_ID
	extra.position = Vector2(-500, -500)
	content.get_node("YSortWorld").add_child(extra)
	second = extra.construction

func _test_two_houses_from_home() -> bool:
	var original_first: Node = house_state
	var original_second: Node = second
	content.get_node("YSortWorld/HomeDoor")._on_body_entered(player)
	if not await _wait_scene(store.snapshot.HOME_PATH):
		return false
	_expect(store.city_plots.size() == 4 and original_first.is_citizen_house() and original_second.is_citizen_house()
		and original_first.phase == "built" and original_second.phase == "built" and CityStockManager.shelter_capacity == 6,
		"Both independent houses retain their kind and shelter after entering the player's home.")
	_expect(store.save_checkpoint(), "Both houses save from home: " + store.last_error)
	var saved_files: Dictionary = _house_files(store.disk.path)
	for iteration: int in range(2):
		if not await _return_house_to_city():
			return false
		house_state = content.get_node("YSortWorld/CitizenHousePlot").construction
		_attach_second_house()
		_expect(house_state == original_first and second == original_second and second.is_citizen_house(),
			"The reattached test view resolves the original second-house state.")
		if not store.load_checkpoint():
			_expect(false, "The two-house home checkpoint loads: " + store.last_error)
			return false
		if not await _wait_house_load():
			return false
		_expect(original_first.phase == "built" and original_second.phase == "built"
			and CityStockManager.shelter_capacity == 6 and _house_files(store.disk.path) == saved_files,
			"Home Continue preserves each house and six shelter places without rewriting the checkpoint.")
	if not await _return_house_to_city():
		return false
	house_state = content.get_node("YSortWorld/CitizenHousePlot").construction
	_attach_second_house()
	return true

func _finish_multi_needs() -> void:
	print("MultiHouseNeedsContinueTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
