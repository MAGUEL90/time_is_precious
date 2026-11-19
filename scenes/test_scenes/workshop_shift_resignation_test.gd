extends "res://scenes/test_scenes/test_scene_city_save_economy.gd"

const MINUTE_RATE: float = 0.05 / 1440.0
const SHIFT_CHECKPOINT: String = "user://workshop_shift_resignation_test/checkpoint.json"
const SHIFT_DRIVER = preload("res://scenes/test_scenes/workshop_shift_test_driver.gd")
const BUILDERS: Array[String] = ["shift_builder_1", "shift_builder_2", "shift_builder_3", "shift_builder_4", "shift_cleaner_1", "shift_cleaner_2", "shift_reentrant_builder", "shift_daily_builder_1", "shift_daily_builder_2"]

class BlockedNavigation extends RefCounted:
	var blocked: bool = true
	var calls: int = 0
	func route(from: Vector2, to: Vector2) -> PackedVector2Array:
		calls += 1
		return PackedVector2Array() if blocked else PackedVector2Array([from, to])
	func segment_clear(_from: Vector2, _to: Vector2) -> bool:
		return not blocked

func _run() -> void:
	if not _isolated_profile_is_safe():
		push_error("Refusing workshop-shift fixture outside the disposable QA profile.")
		get_tree().quit(2)
		return
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_reset_singletons_before_load()
	await load_content()
	for _frame: int in range(2):
		await get_tree().process_frame
	runtime = content.get_node("YSortWorld/WorkerRuntime")
	city_storage = WorkStateRuntime.get_node("CityToolStorage")
	wood_storage = runtime.get_node("CityStorageArea/DeliveryPoint")
	store = WorkStateRuntime.get_node("CitySave")
	store.disk.path = SHIFT_CHECKPOINT
	_prepare_city_state()
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	var visuals: Node2D = runtime.get_node("WorkerVisuals")
	visuals.set_process(false)
	for id: String in BUILDERS:
		var person := CitizenData.new()
		person.citizen_id = id
		person.display_name = id
		person.population_status = CitizenData.PopulationStatus.RESIDENT
		person.employment_status = CitizenData.EmploymentStatus.HIRED
		person.profession = WorkerData.Profession.LABORER
		person.satisfaction = 1.0
		person.visual_profile = VisualProfile.new()
		CitizenManager.add_citizen(person)
		var worker := WorkerData.new()
		worker.worker_id = id
		worker.display_name = id
		worker.profession = WorkerData.Profession.LABORER
		WorkerDatabase.workers_by_id[id] = worker
	var plot = content.get_node("YSortWorld/WorkshopPlot")
	var construction = plot.construction
	construction.phase = "empty"
	Inventory.add_bulk_item(construction.REQUIREMENTS)
	var initial_stock: Dictionary = Inventory.items.duplicate(true)
	var nested_clock_results: Array[bool] = []
	var nested_clock_probe: Callable = func() -> void:
		if construction.is_transaction_busy():
			nested_clock_results.append(TimeComponentManager.advance_minutes(1))
	var before_start_clock: int = _clock_minute()
	Inventory.items_changed.connect(nested_clock_probe)
	_expect(construction.start_build(BUILDERS.slice(0, 3)).success, "A three-person construction team starts.")
	Inventory.items_changed.disconnect(nested_clock_probe)
	_expect(not nested_clock_results.is_empty() and not nested_clock_results.has(true) and _clock_minute() == before_start_clock,
		"Inventory callbacks cannot advance the clock through a partial construction transaction.")
	var paid_stock: Dictionary = Inventory.items.duplicate(true)
	_expect(paid_stock != initial_stock and construction.worker_capacity == 3, "Inputs are charged once and the original team capacity is retained.")
	_drive_arrivals(visuals, BUILDERS.slice(0, 3))
	var absent: WorkerData = WorkerDatabase.get_worker_data(BUILDERS[2])
	absent.physical_approach.arrived = false
	absent.physical_approach.arrival_minute = -1
	TimeComponentManager.advance_minutes(1)
	_expect(construction.payroll_work_remainder == 2 and construction._remaining_work_units() == construction.work_total_units - 2,
		"Two arrived workers retain two fractional worker-minutes of a three-person team.")
	var remainder_before: int = construction._remaining_work_units()
	var wallet: int = int(Inventory.items.get("shekel", 0))
	var blocked_worker: WorkerData = WorkerDatabase.get_worker_data(BUILDERS[0])
	CitizenManager.get_citizen(BUILDERS[0]).satisfaction = 0.0
	blocked_worker.resignation_pending = true
	var blocked_approach: Dictionary = blocked_worker.physical_approach.duplicate(true)
	city_storage._transfer_in_progress = true
	_expect(not construction.resign_worker(BUILDERS[0]) and construction.worker_ids.size() == 3
		and construction._remaining_work_units() == remainder_before
		and blocked_worker.physical_approach == blocked_approach
		and CitizenManager.get_citizen(BUILDERS[0]).employment_status == CitizenData.EmploymentStatus.ASSIGNED,
		"A locked storage rolls back the builder's removal, route, assignment and fractional progress.")
	city_storage._transfer_in_progress = false
	for id: String in BUILDERS.slice(0, 3):
		CitizenManager.get_citizen(id).satisfaction = 0.0
		WorkerDatabase.get_worker_data(id).resignation_pending = true
		_expect(construction.resign_worker(id), "A zero-Satisfaction builder resigns transactionally: " + id)
		_expect(construction._remaining_work_units() == remainder_before, "Team rebasing preserves every worker-minute: " + id)
	_expect(construction.worker_ids.is_empty() and construction.get_replacement_slots() == 3
		and Inventory.items == paid_stock and int(Inventory.items.get("shekel", 0)) == wallet,
		"An empty team keeps materials and progress without a refund.")
	TimeComponentManager.advance_minutes(6 * 60 + 57)
	_expect(construction.phase == "building" and construction._remaining_work_units() == remainder_before,
		"Construction cannot complete while its team is empty.")
	_expect(store.save_checkpoint(), "An unstaffed construction checkpoint saves: " + store.last_error)
	_expect(store.load_checkpoint(), "Continue restores an unstaffed construction: " + store.last_error)
	construction = plot.construction
	_expect(construction.worker_ids.is_empty() and construction.get_replacement_slots() == 3
		and construction._remaining_work_units() == remainder_before, "Continue preserves vacancies and fractional progress.")
	var reentrant: Dictionary = {"called": false, "clock_blocked": false}
	var zero_on_replace: Callable = func() -> void:
		if not reentrant.called and construction.worker_ids.has(BUILDERS[6]):
			reentrant.called = true
			CitizenManager.get_citizen(BUILDERS[6]).satisfaction = 0.0
			WorkerDatabase.resign_idle_workers_at_zero()
			reentrant.clock_blocked = not TimeComponentManager.advance_minutes(1)
	construction.changed.connect(zero_on_replace)
	_expect(construction.add_replacement_workers([BUILDERS[6]] as Array[String]).success, "A replacement can be selected by an observer fixture.")
	construction.changed.disconnect(zero_on_replace)
	_expect(reentrant.called and reentrant.clock_blocked and not WorkerDatabase.has_worker_data(BUILDERS[6])
		and construction.worker_ids.is_empty() and construction._remaining_work_units() == remainder_before,
		"A zero-Satisfaction replacement is reconciled immediately after publication, before time can advance.")
	var menu = preload("res://scenes/ui/workshop_plot_ui/workshop_plot_ui.tscn").instantiate()
	add_child(menu)
	menu.replacement_requested.connect(func(ids: Array[String]) -> void: construction.add_replacement_workers(ids))
	menu.open_menu(construction)
	_expect(menu.replacement_button.visible, "The progress panel exposes assignment when vacancies exist.")
	menu.replacement_button.pressed.emit()
	var assignment = menu._worker_assignment_menu
	_expect(is_instance_valid(assignment) and assignment.max_worker_slots == 3, "The replacement selector exposes only the original vacancies.")
	if is_instance_valid(assignment):
		assignment._on_worker_selected(BUILDERS[3])
		assignment._on_next_pressed()
	_expect(construction.worker_ids == [BUILDERS[3]], "The replacement selector assigns the chosen available worker.")
	menu.close_menu()
	get_tree().paused = false
	_expect(Inventory.items == paid_stock, "Replacing a builder does not debit inputs or the wallet.")
	_drive_arrivals(visuals, [BUILDERS[3]] as Array[String])
	var remaining_at_1458: int = construction._remaining_work_units()
	TimeComponentManager.advance_minutes(2)
	var builder: WorkerData = WorkerDatabase.get_worker_data(BUILDERS[3])
	_expect(construction._remaining_work_units() == remaining_at_1458 - 2,
		"The arrived worker contributes through 15:00 exactly.")
	_expect(not builder.physical_approach.arrived and builder.physical_approach.arrival_minute == WorkerData.PLOT_DEPARTURE_PENDING,
		"At 15:00 the worker must depart and physically return next shift.")
	var presence: Script = load("res://scenes/workshop_plot/workshop_worker_presence.gd")
	var legacy := WorkerData.new()
	legacy.worker_id = "legacy_presence_probe"
	presence.end_shift_for_worker(legacy, "plot", construction.order_id + ":building", construction.order_id)
	var legacy_route: Dictionary = legacy.physical_approach.duplicate(true)
	presence.end_shift_for_worker(legacy, "plot", construction.order_id + ":building", construction.order_id)
	_expect(legacy.physical_approach == legacy_route and legacy_route.position == construction.worker_entry_position
		and legacy_route.target == construction.worker_entry_position and legacy_route.arrival_minute == WorkerData.PLOT_DEPARTURE_PENDING,
		"The shift helper initializes a legacy worker at the authored entrance and is idempotent.")
	var at_close: int = construction._remaining_work_units()
	TimeComponentManager.advance_minutes(16 * 60)
	_expect(construction._remaining_work_units() == at_close and not builder.physical_approach.arrived
		and builder.physical_approach.arrival_minute == WorkerData.PLOT_DEPARTURE_PENDING,
		"An overnight skip with no visual frames neither progresses nor forgets departure.")
	_expect(store.save_checkpoint(), "The pending-departure checkpoint saves: " + store.last_error)
	_expect(store.load_checkpoint(), "Continue restores a pending departure: " + store.last_error)
	builder = WorkerDatabase.get_worker_data(BUILDERS[3])
	construction = plot.construction
	_expect(builder.physical_approach.arrival_minute == WorkerData.PLOT_DEPARTURE_PENDING,
		"The outbound route phase survives the actual disk checkpoint.")
	visuals.plot_presence.update(visuals, 0.0)
	_expect(not builder.physical_approach.arrived and builder.physical_approach.arrival_minute == WorkerData.PLOT_DEPARTURE_PENDING,
		"The first morning frame cannot falsely mark arrival at the plot.")
	_test_route_obstruction(visuals, builder)
	TimeComponentManager.advance_minutes(1)
	_expect(construction._remaining_work_units() == at_close, "No work is credited before the worker returns.")
	_drive_arrivals(visuals, [BUILDERS[3]] as Array[String])
	_expect(builder.physical_approach.arrived, "The worker completes departure and returns to the plot.")
	TimeComponentManager.advance_minutes(1)
	_expect(construction._remaining_work_units() == at_close - 1, "Progress resumes only after physical return.")
	# Expired pay blocks even an arrived worker during the shift.
	builder.payroll_start_day = TimeComponentManager.current_day
	builder.payroll_paid_from_day = TimeComponentManager.current_day - 1
	builder.payroll_paid_until_day = TimeComponentManager.current_day - 1
	builder.payroll_period_rate = 1
	builder.payroll_contract_days = 3
	builder.payroll_paid_start_minute = (TimeComponentManager.current_day - 1) * 1440 + 420
	var before_unpaid: int = construction._remaining_work_units()
	TimeComponentManager.advance_minutes(2)
	_expect(construction._remaining_work_units() == before_unpaid, "Expired payroll blocks construction during an otherwise open shift.")
	# The second real plot exercises clearing, including no-team freeze and replacement.
	var second_plot = content.get_node("YSortWorld/WorkshopPlot2")
	var clearing = second_plot.construction
	_expect(clearing.start_clearing([BUILDERS[4]] as Array[String], false).success, "A worker starts clearing the other plot.")
	_drive_arrivals(visuals, [BUILDERS[4]] as Array[String])
	TimeComponentManager.advance_minutes(1)
	var clearing_left: int = clearing._remaining_work_units()
	CitizenManager.get_citizen(BUILDERS[4]).satisfaction = 0.0
	WorkerDatabase.get_worker_data(BUILDERS[4]).resignation_pending = true
	_expect(clearing.resign_worker(BUILDERS[4]) and clearing._remaining_work_units() == clearing_left,
		"A clearing worker's resignation preserves progress.")
	TimeComponentManager.advance_minutes(2)
	_expect(clearing.phase == "clearing" and clearing._remaining_work_units() == clearing_left,
		"Clearing freezes without a worker.")
	_expect(clearing.add_replacement_workers([BUILDERS[5]] as Array[String]).success, "A replacement resumes the existing clearing job.")
	_drive_arrivals(visuals, [BUILDERS[5]] as Array[String])
	TimeComponentManager.advance_minutes(clearing_left)
	_expect(clearing.phase == "empty", "The replacement completes the remaining clearing work exactly once.")
	clearing.phase = "uncleared"
	clearing.clearing_remaining = clearing.CLEARING_MINUTES
	var until_1459: int = 14 * 60 + 59 - TimeComponentManager.current_hour * 60 - TimeComponentManager.current_minute
	TimeComponentManager.advance_minutes(until_1459)
	_expect(clearing.start_clearing([BUILDERS[5]] as Array[String], false).success, "Worker clearing can begin near shift end.")
	_drive_arrivals(visuals, [BUILDERS[5]] as Array[String])
	TimeComponentManager.advance_minutes(1)
	_expect(clearing._remaining_work_units() == clearing.CLEARING_MINUTES - 1,
		"Clearing counts its final shift minute exactly.")
	TimeComponentManager.advance_minutes(16 * 60)
	_expect(clearing._remaining_work_units() == clearing.CLEARING_MINUTES - 1
		and WorkerDatabase.get_worker_data(BUILDERS[5]).physical_approach.arrival_minute == WorkerData.PLOT_DEPARTURE_PENDING,
		"NPC clearing freezes overnight and retains its outbound route.")
	_drive_arrivals(visuals, [BUILDERS[5]] as Array[String])
	TimeComponentManager.advance_minutes(clearing.CLEARING_MINUTES - 1)
	_expect(clearing.phase == "empty", "Clearing resumes after the worker's next physical arrival.")
	# A busy clock during manual clearing ends the loop and keeps the first
	# completed minute instead of spinning or resetting the clearing work.
	clearing.phase = "uncleared"
	clearing.clearing_remaining = clearing.CLEARING_MINUTES
	player.global_position = second_plot.get_node("InteractableComponent").global_position + Vector2(0, 4)
	for _frame: int in range(5):
		await get_tree().physics_frame
	_expect(second_plot.has_player_access(), "The player reaches the second plot's authored interaction area.")
	if second_plot.has_player_access():
		second_plot.on_player_interact(player)
		var clearing_menu = second_plot.menu
		_expect(is_instance_valid(clearing_menu) and get_tree().paused,
			"The real player interaction opens a valid paused clearing session.")
		if not is_instance_valid(clearing_menu) or not get_tree().paused:
			get_tree().quit(1)
			return
		var block_after_one_minute: Callable = func(_day: int, _hour: int, _minute: int, _weather: String) -> void:
			store._busy = true
		var completion: Dictionary = {"finished": false}
		var on_finished: Callable = func() -> void: completion.finished = true
		second_plot.clearing_finished.connect(on_finished, CONNECT_ONE_SHOT)
		TimeComponentManager.time_changed.connect(block_after_one_minute, CONNECT_ONE_SHOT)
		clearing_menu.clearing_requested.emit([] as Array[String], true)
		var deadline: int = Time.get_ticks_msec() + 10000
		while not completion.finished and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		_expect(completion.finished, "Manual clearing completes or interrupts within the bounded test deadline.")
		if second_plot.clearing_finished.is_connected(on_finished):
			second_plot.clearing_finished.disconnect(on_finished)
		if TimeComponentManager.time_changed.is_connected(block_after_one_minute):
			TimeComponentManager.time_changed.disconnect(block_after_one_minute)
		store._busy = false
		if not completion.finished:
			get_tree().quit(1)
			return
		_expect(clearing.phase == "uncleared" and clearing.clearing_remaining == clearing.CLEARING_MINUTES - 1,
			"A blocked clock interrupts manual clearing after its accrued minute without a no-progress loop.")
	# An owner can receive a coalesced clock notification. Even a jump spanning
	# an entire night must credit only the remainder of the first shift.
	TimeComponentManager.current_hour = 14
	TimeComponentManager.current_minute = 50
	var coarse = load("res://scenes/workshop_plot/workshop_construction_state.gd").new()
	coarse.order_id = "construction:shift_coarse_fixture"
	coarse.phase = "empty"
	WorkStateRuntime.add_child(coarse)
	Inventory.add_bulk_item(coarse.REQUIREMENTS)
	_expect(coarse.start_build([BUILDERS[5]] as Array[String]).success, "A separate construction starts for a coarse clock jump.")
	var coarse_worker: WorkerData = WorkerDatabase.get_worker_data(BUILDERS[5])
	coarse_worker.begin_physical_approach("plot", coarse.order_id + ":building", coarse.order_id, Vector2.ZERO, Vector2.ZERO)
	coarse_worker.mark_physical_arrival(coarse.order_id + ":building")
	var coarse_total: int = coarse._remaining_work_units()
	coarse._on_time_changed(TimeComponentManager.current_day + 1, 7, 5, "clear")
	_expect(coarse._remaining_work_units() == coarse_total - 10 and not coarse_worker.physical_approach.arrived
		and coarse_worker.physical_approach.arrival_minute == WorkerData.PLOT_DEPARTURE_PENDING,
		"A single multi-day notification credits only work through the first 15:00.")
	coarse.free()
	# Exercise the real daily needs event, not only direct zero/sweep calls.
	var daily_person: CitizenData = CitizenManager.get_citizen(BUILDERS[5])
	_seed_zero_crossing(BUILDERS[5], 9 * 60 + 10)
	_expect(clearing.start_clearing([BUILDERS[5]] as Array[String], false).success,
		"An unserved worker starts retained clearing work before the midnight zero crossing.")
	_drive_arrivals(visuals, [BUILDERS[5]] as Array[String])
	TimeComponentManager.advance_minutes(10)
	var before_daily: int = clearing._remaining_work_units()
	var stock_before_daily: Dictionary = Inventory.items.duplicate(true)
	TimeComponentManager.advance_minutes(9 * 60 - 1)
	_expect(daily_person.satisfaction > 0.0 and absf(daily_person.satisfaction - MINUTE_RATE * 0.5) < 0.000000001
		and WorkerDatabase.has_worker_data(BUILDERS[5]), "The clearing worker remains employed at positive Satisfaction just before midnight.")
	TimeComponentManager.advance_minutes(1)
	_expect(daily_person.satisfaction == 0.0 and daily_person.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and not WorkerDatabase.has_worker_data(BUILDERS[5]) and WorkerDatabase.dismissed_workers.has(BUILDERS[5]),
		"The actual zero-crossing minute at midnight resigns the clearing worker.")
	_expect(clearing.phase == "clearing" and clearing.worker_ids.is_empty() and clearing.get_replacement_slots() == 1
		and clearing._remaining_work_units() == before_daily and Inventory.items == stock_before_daily,
		"Midnight resignation preserves the clearing progress, vacancy and all inventory.")
	# Repeat the real midnight boundary for the explicit multi-worker building
	# case, where the surviving teammate remains reserved and materials stay paid.
	TimeComponentManager.advance_minutes(8 * 60)
	var team = load("res://scenes/workshop_plot/workshop_construction_state.gd").new()
	team.order_id = "construction:daily_team_fixture"
	team.phase = "empty"
	WorkStateRuntime.add_child(team)
	Inventory.add_bulk_item(team.REQUIREMENTS)
	var team_materials_before: Dictionary = Inventory.items.duplicate(true)
	_seed_zero_crossing(BUILDERS[7], 16 * 60)
	CitizenManager.get_citizen(BUILDERS[8]).satisfaction = 1.0
	for id: String in BUILDERS.slice(7, 9):
		var contracted: WorkerData = WorkerDatabase.get_worker_data(id)
		contracted.payroll_start_day = TimeComponentManager.current_day
		contracted.payroll_paid_from_day = TimeComponentManager.current_day
		contracted.payroll_paid_until_day = TimeComponentManager.current_day + 2
		contracted.payroll_period_rate = 1
		contracted.payroll_contract_days = 3
		contracted.payroll_paid_start_minute = _clock_minute()
		contracted.payroll_last_attempt_day = TimeComponentManager.current_day
	_expect(team.start_build([BUILDERS[7], BUILDERS[8]] as Array[String]).success,
		"Two builders start the multi-worker midnight construction fixture.")
	var team_materials_paid: Dictionary = Inventory.items.duplicate(true)
	for item_id: String in team.REQUIREMENTS:
		_expect(int(team_materials_paid.get(item_id, 0)) == int(team_materials_before.get(item_id, 0)) - int(team.REQUIREMENTS[item_id]),
			"Construction takes its upfront " + item_id + " exactly once.")
	for id: String in BUILDERS.slice(7, 9):
		var member: WorkerData = WorkerDatabase.get_worker_data(id)
		member.begin_physical_approach("plot", team.order_id + ":building", team.order_id, Vector2.ZERO, Vector2.ZERO)
		member.mark_physical_arrival(team.order_id + ":building")
	TimeComponentManager.advance_minutes(7 * 60)
	var team_work_before_midnight: int = team._remaining_work_units()
	TimeComponentManager.advance_minutes(9 * 60 - 1)
	var leaver: CitizenData = CitizenManager.get_citizen(BUILDERS[7])
	_expect(leaver.satisfaction > 0.0 and absf(leaver.satisfaction - MINUTE_RATE * 0.5) < 0.000000001
		and WorkerDatabase.has_worker_data(BUILDERS[7]), "The builder remains employed while Satisfaction is positive at 23:59.")
	TimeComponentManager.advance_minutes(1)
	_expect(not WorkerDatabase.has_worker_data(BUILDERS[7]) and WorkerDatabase.dismissed_workers.has(BUILDERS[7])
		and CitizenManager.get_citizen(BUILDERS[7]).employment_status == CitizenData.EmploymentStatus.UNEMPLOYED,
		"The real midnight zero crossing resigns the first builder.")
	var survivor: WorkerData = WorkerDatabase.get_worker_data(BUILDERS[8])
	_expect(team.phase == "building" and team.worker_ids == [BUILDERS[8]] and team.get_replacement_slots() == 1
		and survivor != null and survivor.current_order_id == team.order_id
		and CitizenManager.get_citizen(BUILDERS[8]).employment_status == CitizenData.EmploymentStatus.ASSIGNED
		and team._remaining_work_units() == team_work_before_midnight and Inventory.items == team_materials_paid,
		"The other builder remains assigned with all worker-minutes and prepaid materials preserved.")
	team.free()
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		if FileAccess.file_exists(SHIFT_CHECKPOINT + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SHIFT_CHECKPOINT + suffix))
	if is_instance_valid(content):
		content.queue_free()
		await get_tree().process_frame
	print("WorkshopShiftResignationTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _drive_arrivals(visuals: Node2D, ids: Array[String]) -> void:
	for _frame: int in range(4000):
		var all_arrived: bool = true
		for id: String in ids:
			var worker: WorkerData = WorkerDatabase.get_worker_data(id)
			if worker == null or not worker.physical_approach.get("arrived", false):
				all_arrived = false
		if all_arrived:
			return
		SHIFT_DRIVER.visual_frame(visuals, 0.1)
	_expect(false, "Assigned workers physically arrive: " + str(ids))

func _test_route_obstruction(visuals: Node2D, worker: WorkerData) -> void:
	var saved_navigation: RefCounted = runtime.worksite_navigation
	var navigation := BlockedNavigation.new()
	runtime.worksite_navigation = navigation
	visuals.plot_presence.states.clear()
	var start: Vector2 = worker.physical_approach.position
	visuals.plot_presence.update(visuals, 0.1)
	var attempts: int = navigation.calls
	for _frame: int in range(4):
		visuals.plot_presence.update(visuals, 0.1)
	_expect(attempts == 1 and navigation.calls == attempts and worker.physical_approach.position == start,
		"A blocked outbound route retries on a bounded cadence rather than every frame.")
	navigation.blocked = false
	visuals.plot_presence.update(visuals, 1.0)
	_expect(navigation.calls == attempts + 1 and worker.physical_approach.position != start,
		"A newly opened route retries and resumes the saved outbound position.")
	for _frame: int in range(4000):
		if worker.physical_approach.arrival_minute == -1:
			break
		visuals.plot_presence.update(visuals, 0.1)
	_expect(worker.physical_approach.arrival_minute == -1 and not worker.physical_approach.arrived,
		"The worker reaches the existing departure before beginning their return.")
	navigation.blocked = true
	visuals.plot_presence.update(visuals, 0.1)
	_expect(visuals.plot_presence.states.has(worker.worker_id), "A blocked inbound route is cached for retry.")
	runtime.worksite_navigation = saved_navigation
	runtime._refresh_navigation()
	_expect(not visuals.plot_presence.states.has(worker.worker_id), "A navigation refresh invalidates stale plot routes immediately.")

func _seed_zero_crossing(id: String, minutes: int) -> void:
	# Synthetic unmet-needs fixture. No elapsed time is fabricated by placing
	# its cursor at the current clock; subsequent ticks run the real integrator.
	city_storage.items.erase("barley_bread")
	city_storage.food_portions.clear()
	city_storage.items.erase("simple_clothes")
	CitizenNeedsManager.food_coverage_until.erase(id)
	CitizenNeedsManager.clothing_allocations.erase(id)
	CitizenNeedsManager.satisfaction_last_minute[id] = _clock_minute()
	CityStockManager.shelter_capacity = 0
	CitizenNeedsManager.process_daily_shelter_capacity_needs()
	var person: CitizenData = CitizenManager.get_citizen(id)
	person.food_fulfilled = false
	person.clothing_fulfilled = false
	person.satisfaction = MINUTE_RATE * (float(minutes) - 0.5)
	_expect(not person.shelter_fulfilled and city_storage.get_food_supply_points() == 0,
		"The zero-crossing fixture has no covered need or replenishing food: " + id)
