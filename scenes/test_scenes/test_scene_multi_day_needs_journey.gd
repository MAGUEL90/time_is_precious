extends Node

## Controlled multi-day integration: actual city, Job Board, construction UI,
## clock and Continue. Wallet/materials, initial 10% Satisfaction, and later
## food/clothing/shelter are explicit fixtures; this is not a natural-start run.
const MENU: PackedScene = preload("res://scenes/ui/start_menu/start_menu.tscn")
const SHIFT_DRIVER = preload("res://scenes/test_scenes/workshop_shift_test_driver.gd")
const CHECKPOINT: String = "user://multi_day_needs_journey/checkpoint.json"
const EVIDENCE: String = "user://multi_day_needs_journey/evidence.json"
const FIRST: String = "initial_workshop_laborer"
const REPLACEMENT: String = "initial_worksite_hauler"
const TEST_XP: int = 17

var failures: int = 0
var phase: String = "write"
var launched: bool = false
var did_continue: bool = false
var city: Node
var player: Player
var runtime: Node
var visuals: Node2D
var plot: Node
var construction: Node
var store: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--needs-journey-phase="):
			phase = argument.trim_prefix("--needs-journey-phase=")
	_check(phase in ["write", "read", "verify"], "Choose write, read, or verify.")
	if phase == "write":
		for suffix: String in ["", ".bak", ".tmp", ".pending"]:
			_check(not FileAccess.file_exists(CHECKPOINT + suffix), "Write requires an empty isolated save slot.")
	else:
		_check(FileAccess.file_exists(CHECKPOINT) and FileAccess.file_exists(EVIDENCE), "Continue requires the preceding isolated phase.")
	if failures > 0:
		_finish()
		return
	var source_bytes: PackedByteArray = FileAccess.get_file_as_bytes(CHECKPOINT) if phase != "write" else PackedByteArray()
	get_tree().current_scene = null
	get_tree().paused = false
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = CHECKPOINT
	menu.session_started.connect(_on_session_started)
	get_tree().root.add_child(menu)
	if phase == "write":
		menu.new_game_button.pressed.emit()
	else:
		menu.continue_button.pressed.emit()
	for _frame: int in range(1200):
		if launched:
			break
		await get_tree().process_frame
	_check(launched and did_continue == (phase != "write"), "The real Start Menu completes New Game or Continue.")
	if not launched:
		_finish()
		return
	_bind_city()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	# The long skips target citizens' needs, not a synthetic player-survival run.
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	visuals.set_process(false)
	if phase != "write":
		_check(FileAccess.get_file_as_bytes(CHECKPOINT) == source_bytes, "Start Menu Continue leaves the checkpoint bytes unchanged.")
	match phase:
		"write": await _write_journey()
		"read": await _continue_journey(source_bytes)
		"verify": _verify_final_journey(source_bytes)
	_finish()

func _on_session_started(continued: bool) -> void:
	did_continue = continued
	launched = true

func _bind_city() -> void:
	city = get_tree().current_scene
	player = city.get_node("YSortWorld/Player") as Player
	runtime = city.get_node("YSortWorld/WorkerRuntime")
	visuals = runtime.get_node("WorkerVisuals") as Node2D
	plot = city.get_node("YSortWorld/WorkshopPlot2")
	construction = plot.construction
	store = WorkStateRuntime.get_node("CitySave")
	_check(store.disk.path == CHECKPOINT, "CitySave uses the isolated journey slot.")

func _write_journey() -> void:
	_check(TimeComponentManager.current_hour >= 8 and TimeComponentManager.current_hour < 15,
		"New Game starts inside both Job Board hours and the 07:00–15:00 shift.")
	_check(Inventory.items.is_empty() and WorkerDatabase.workers_by_id.is_empty(), "The actual New Game starts without wallet or hires.")
	# Explicit fixture funds and build materials; prices and contracts remain real.
	Inventory.add_item("shekel", 40)
	for item_id: String in construction.REQUIREMENTS:
		Inventory.add_item(item_id, int(construction.REQUIREMENTS[item_id]))
	if not await _hire_from_board([FIRST, REPLACEMENT] as Array[String], 9):
		return
	var first: WorkerData = WorkerDatabase.get_worker_data(FIRST)
	var other: WorkerData = WorkerDatabase.get_worker_data(REPLACEMENT)
	var citizen: CitizenData = CitizenManager.get_citizen(FIRST)
	if first == null or other == null or citizen == null:
		_check(false, "Both authored candidates have paid workers and the first citizen.")
		return
	_check(first.payroll_contract_days == 9 and other.payroll_contract_days == 9
		and not first.is_payroll_blocked() and not other.is_payroll_blocked(), "Both actual UI hires have active nine-day contracts.")
	# Set only the documented starting boundary, then let daily needs do all changes.
	citizen.satisfaction = 0.10
	first.profession_xp = TEST_XP
	var original_name: String = citizen.display_name
	var old_paid_until: int = first.payroll_paid_until_day
	var wallet_after_hire: int = int(Inventory.items.get("shekel", 0))
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	# Clothing and shelter have no normal supply path in this build. Seed them
	# explicitly, leaving food as the only missing basic need on both days.
	var residents: int = CitizenManager.get_all_residents().size()
	Inventory.add_item("simple_clothes", residents)
	var initial_clothes: Dictionary = storage.deposit_items_from_inventory({"simple_clothes": residents})
	_check(bool(initial_clothes.get("ok", false)) and CityStockManager.add_shelter_capacity(residents),
		"The fixture supplies clothing and shelter for all residents before food runs out.")
	_check(storage.get_food_supply_points() == 0, "The first two daily settlements start without city food.")
	if not await _start_plot_task(FIRST):
		return
	var arrived: bool = _drive_arrival(FIRST)
	_check(arrived, "The original builder physically reaches the clearing entry.")
	if not arrived:
		return
	_check(TimeComponentManager.advance_minutes(construction.CLEARING_MINUTES)
		and construction.phase == "empty", "The paid worker clears the site through normal shift time.")
	if construction.phase != "empty" or not await _start_plot_task(FIRST):
		return
	arrived = _drive_arrival(FIRST)
	_check(arrived, "The original builder physically reaches the construction entry.")
	if not arrived:
		return
	var full_work: int = construction._remaining_work_units()
	_check(TimeComponentManager.advance_minutes(30) and construction._remaining_work_units() == full_work - 30,
		"An arrived paid builder makes thirty actual construction minutes.")
	for item_id: String in construction.REQUIREMENTS:
		_check(int(Inventory.items.get(item_id, 0)) == 0, "The build consumes its fixture material exactly once: " + item_id)
	var paid_inventory: Dictionary = Inventory.items.duplicate(true)
	var until_close: int = 15 * 60 - _minute_of_day()
	_check(until_close >= 0 and TimeComponentManager.advance_minutes(until_close), "The first shift reaches 15:00.")
	var at_close: int = construction._remaining_work_units()
	_check(first.physical_approach.get("arrival_minute", -1) == WorkerData.PLOT_DEPARTURE_PENDING,
		"The original builder departs at the end of the real shift.")
	_check(TimeComponentManager.advance_minutes(9 * 60 - 1), "The real clock reaches 23:59 before the first settlement.")
	_check(_minute_of_day() == 23 * 60 + 59 and is_equal_approx(citizen.satisfaction, 0.10)
		and WorkerDatabase.get_worker_data(FIRST) == first and first.payroll_paid_until_day == old_paid_until
		and construction._remaining_work_units() == at_close and Inventory.items == paid_inventory,
		"At 23:59 the first shortage has not yet changed Satisfaction, employment, contract or progress.")
	_check(TimeComponentManager.advance_minutes(1), "The real clock reaches the first midnight.")
	_check(is_equal_approx(citizen.satisfaction, 0.05) and not citizen.food_fulfilled
		and citizen.clothing_fulfilled and citizen.shelter_fulfilled and construction._remaining_work_units() == at_close
		and WorkerDatabase.has_worker_data(FIRST), "Day one shortage lowers 10% to 5% without off-shift progress.")
	_check(TimeComponentManager.advance_minutes(7 * 60), "The clock reaches the next 07:00 shift.")
	arrived = _drive_arrival(FIRST)
	_check(arrived, "The original builder physically returns for the second shift.")
	if not arrived:
		return
	_check(TimeComponentManager.advance_minutes(8 * 60), "The second paid shift advances to 15:00.")
	var remaining: int = construction._remaining_work_units()
	_check(remaining == at_close - 8 * 60, "The second arrived shift adds exactly eight hours of work.")
	_check(TimeComponentManager.advance_minutes(9 * 60 - 1), "The clock reaches 23:59 before the second settlement.")
	_check(_minute_of_day() == 23 * 60 + 59 and is_equal_approx(citizen.satisfaction, 0.05)
		and WorkerDatabase.get_worker_data(FIRST) == first and first.payroll_paid_until_day == old_paid_until
		and construction._remaining_work_units() == remaining and Inventory.items == paid_inventory,
		"At 23:59 the second shortage has not yet resigned the worker or changed the project.")
	_check(TimeComponentManager.advance_minutes(1), "The clock reaches the second midnight.")
	var archived: WorkerData = WorkerDatabase.dismissed_workers.get(FIRST)
	_check(is_zero_approx(citizen.satisfaction) and not citizen.food_fulfilled
		and citizen.clothing_fulfilled and citizen.shelter_fulfilled and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and not WorkerDatabase.has_worker_data(FIRST) and archived != null, "Day two shortage lowers 5% to zero and resigns the builder.")
	_check(archived != null and archived.profession_xp == TEST_XP and archived.payroll_paid_until_day == -1
		and old_paid_until > TimeComponentManager.current_day and int(Inventory.items.get("shekel", 0)) == wallet_after_hire,
		"Resignation retains XP and forfeits the still-paid contract without a refund.")
	_check(construction.phase == "building" and construction.worker_ids.is_empty()
		and construction.get_replacement_slots() == 1 and construction._remaining_work_units() == remaining
		and Inventory.items == paid_inventory, "The unstaffed construction keeps its progress and paid materials.")
	if not store.save_checkpoint():
		_check(false, "The real city saves the interrupted construction: " + store.last_error)
		return
	_write_evidence({"stage": "interrupted", "name": original_name, "xp": TEST_XP,
		"old_paid_until": old_paid_until, "wallet": wallet_after_hire, "remaining": remaining,
		"inventory": paid_inventory})

func _continue_journey(source_bytes: PackedByteArray) -> void:
	var evidence: Dictionary = _read_evidence("interrupted")
	if evidence.is_empty():
		return
	var citizen: CitizenData = CitizenManager.get_citizen(FIRST)
	var archived: WorkerData = WorkerDatabase.dismissed_workers.get(FIRST)
	_check(citizen != null and archived != null and citizen.display_name == evidence.name
		and citizen.satisfaction == 0.0 and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and archived.profession_xp == int(evidence.xp) and not WorkerDatabase.has_worker_data(FIRST),
		"Menu Continue restores the same unemployed citizen and archived worker.")
	_check(construction.phase == "building" and construction.worker_ids.is_empty()
		and construction.get_replacement_slots() == 1 and construction._remaining_work_units() == int(evidence.remaining)
		and _same_counts(Inventory.items, evidence.inventory) and int(Inventory.items.get("shekel", 0)) == int(evidence.wallet),
		"Menu Continue restores the vacancy, paid materials, wallet and exact remaining work.")
	_check(store.load_checkpoint() and FileAccess.get_file_as_bytes(CHECKPOINT) == source_bytes
		and construction._remaining_work_units() == int(evidence.remaining), "A second Continue neither rewrites nor advances the interrupted project.")
	_check(TimeComponentManager.advance_minutes(7 * 60), "The next 07:00 shift starts with the vacancy intact.")
	if not await _replace_from_plot(REPLACEMENT):
		return
	var arrived: bool = _drive_arrival(REPLACEMENT)
	_check(arrived, "The paid replacement physically arrives at the plot.")
	if not arrived:
		return
	var before_replacement_work: int = construction._remaining_work_units()
	_check(TimeComponentManager.advance_minutes(30)
		and construction._remaining_work_units() == before_replacement_work - 30
		and _same_counts(Inventory.items, evidence.inventory), "The replacement advances the same paid project without another material charge.")
	# Food returns and clothes are replenished before the first set expires;
	# the explicitly supplied shelter remains in place for the whole journey.
	var residents: int = CitizenManager.get_all_residents().size()
	var food: int = residents * 11
	var clothes: int = residents
	Inventory.add_item("barley_bread", food)
	Inventory.add_item("simple_clothes", clothes)
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var deposit: Dictionary = storage.deposit_items_from_inventory({"barley_bread": food, "simple_clothes": clothes})
	_check(bool(deposit.get("ok", false)) and CityStockManager.has_shelter_capacity(residents),
		"The explicit fixture supplies food, replacement clothing, and shelter for all residents.")
	for day: int in range(1, 11):
		if not _advance_recovery_day(day):
			return
		citizen = CitizenManager.get_citizen(FIRST)
		_check(citizen != null and is_equal_approx(citizen.satisfaction, day * 0.05),
			"All fulfilled needs restore five percentage points on recovery day %d." % day)
		if citizen == null:
			return
		if day < 10:
			_check(citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
				and not CitizenManager.get_all_applicants().has(citizen), "The former worker cannot reapply before 50%%: day %d." % day)
		if day == 9:
			_check(TimeComponentManager.advance_minutes(8 * 60), "The Job Board opens after day nine.")
			await _check_board_excludes(FIRST)
		await get_tree().process_frame
	_check(is_equal_approx(citizen.satisfaction, 0.5)
		and citizen.employment_status == CitizenData.EmploymentStatus.APPLICANT,
		"The real tenth daily evaluation reapplies at exactly 50%.")
	_check(TimeComponentManager.advance_minutes(8 * 60), "The Job Board opens after recovery.")
	archived = WorkerDatabase.dismissed_workers.get(FIRST)
	var wallet_before: int = int(Inventory.items.get("shekel", 0))
	var price: int = WorkerDatabase.get_contract_price(citizen.profession, 9)
	if not await _hire_from_board([FIRST] as Array[String], 9):
		return
	var rehired: WorkerData = WorkerDatabase.get_worker_data(FIRST)
	_check(rehired != null and rehired == archived and rehired.profession_xp == int(evidence.xp)
		and citizen.citizen_id == FIRST and citizen.display_name == evidence.name,
		"Actual Job Board rehire retains the archived identity and fixture-seeded XP.")
	_check(rehired != null and rehired.payroll_contract_days == 9
		and rehired.payroll_paid_from_day == TimeComponentManager.current_day
		and rehired.payroll_paid_until_day == TimeComponentManager.current_day + 9
		and rehired.payroll_paid_until_day != int(evidence.old_paid_until)
		and int(Inventory.items.get("shekel", 0)) == wallet_before - price,
		"Rehire purchases a new nine-day contract once instead of reviving the forfeited one.")
	var replacement: WorkerData = WorkerDatabase.get_worker_data(REPLACEMENT)
	_check(construction.phase == "built" or (construction.phase == "building" and replacement != null
		and replacement.is_payroll_blocked()), "The replacement either finishes the project or pauses it at contract expiry.")
	if rehired == null or not store.save_checkpoint():
		_check(false, "The new paid contract saves: " + store.last_error)
		return
	_write_evidence({"stage": "rehired", "name": citizen.display_name, "xp": rehired.profession_xp,
		"wallet": int(Inventory.items.get("shekel", 0)), "paid_until": rehired.payroll_paid_until_day,
		"paid_start": rehired.payroll_paid_start_minute, "plot_phase": construction.phase,
		"remaining": construction._remaining_work_units()})

func _verify_final_journey(source_bytes: PackedByteArray) -> void:
	var evidence: Dictionary = _read_evidence("rehired")
	if evidence.is_empty():
		return
	var citizen: CitizenData = CitizenManager.get_citizen(FIRST)
	var worker: WorkerData = WorkerDatabase.get_worker_data(FIRST)
	_check(citizen != null and worker != null and citizen.citizen_id == FIRST
		and citizen.display_name == evidence.name and worker.profession_xp == int(evidence.xp)
		and citizen.employment_status == CitizenData.EmploymentStatus.HIRED
		and not WorkerDatabase.dismissed_workers.has(FIRST), "Fresh-process Continue preserves the rehired identity and XP.")
	_check(worker != null and worker.payroll_contract_days == 9 and worker.payroll_paid_until_day == int(evidence.paid_until)
		and worker.payroll_paid_start_minute == int(evidence.paid_start)
		and int(Inventory.items.get("shekel", 0)) == int(evidence.wallet), "Continue keeps the new prepaid contract without another debit.")
	var remaining: int = construction._remaining_work_units()
	var replacement: WorkerData = WorkerDatabase.get_worker_data(REPLACEMENT)
	var valid_project: bool = construction.phase == "built" and remaining == 0
	if construction.phase == "building":
		valid_project = remaining > 0 and construction.worker_ids.has(REPLACEMENT) \
			and replacement != null and replacement.is_payroll_blocked()
	_check(valid_project and construction.phase == evidence.plot_phase and remaining == int(evidence.remaining),
		"Continue keeps the completed or expired-contract project and its exact progress.")
	_check(store.load_checkpoint() and FileAccess.get_file_as_bytes(CHECKPOINT) == source_bytes
		and int(Inventory.items.get("shekel", 0)) == int(evidence.wallet), "Repeated final Continue preserves bytes and wallet.")

func _hire_from_board(ids: Array[String], days: int) -> bool:
	var board: JobBoard = city.get_node("YSortWorld/InitialWorksites/JobBoard") as JobBoard
	if not await _approach(board, board.get_node("InteractableComponent").global_position + Vector2(0, 8)):
		return false
	await _press_interact()
	var panel: JobBoardUI = board.job_board_ui
	_check(is_instance_valid(panel), "The authored Job Board opens through interaction.")
	if not is_instance_valid(panel):
		return false
	var selected: int = 0
	var expected_price: int = 0
	for card in panel.cards:
		if ids.has(card.citizen_id):
			var person: CitizenData = CitizenManager.get_citizen(card.citizen_id)
			expected_price += WorkerDatabase.get_contract_price(person.profession, days)
			card.selection_button.set_pressed(true)
			selected += 1
	_check(selected == ids.size(), "All requested eligible workers appear on the actual Job Board.")
	if selected != ids.size():
		panel.close_button.pressed.emit()
		await get_tree().process_frame
		return false
	panel.hire_button.pressed.emit()
	_check(panel.confirmation_open, "Hire opens the contract choice and confirmation.")
	for button: Button in panel.duration_buttons:
		if int(button.get_meta("contract_days")) == days:
			button.pressed.emit()
	var before: int = int(Inventory.items.get("shekel", 0))
	_check(panel.confirm_quote_amount_label.text == str(expected_price), "The actual confirmation quotes the requested duration.")
	panel.confirm_hire_button.pressed.emit()
	var hired: bool = true
	for id: String in ids:
		var worker: WorkerData = WorkerDatabase.get_worker_data(id)
		hired = hired and worker != null and worker.payroll_contract_days == days
	_check(hired and int(Inventory.items.get("shekel", 0)) == before - expected_price,
		"Confirm hires each worker with one wallet debit.")
	panel.close_button.pressed.emit()
	await get_tree().process_frame
	return hired

func _check_board_excludes(id: String) -> void:
	var board: JobBoard = city.get_node("YSortWorld/InitialWorksites/JobBoard") as JobBoard
	if not await _approach(board, board.get_node("InteractableComponent").global_position + Vector2(0, 8)):
		return
	await _press_interact()
	var panel: JobBoardUI = board.job_board_ui
	_check(is_instance_valid(panel), "The Job Board opens to check eligibility below 50%.")
	if not is_instance_valid(panel):
		return
	for card in panel.cards:
		_check(card.citizen_id != id, "The 45% former worker is not displayed as an applicant.")
	panel.close_button.pressed.emit()
	await get_tree().process_frame

func _start_plot_task(id: String) -> bool:
	if not await _open_plot():
		return false
	plot.menu.assign_workers_button.pressed.emit()
	await get_tree().process_frame
	if not await _choose_plot_worker(id):
		return false
	var button: Button = plot.menu.build_button
	_check(not button.disabled, "The selected paid worker enables the actual plot action.")
	if button.disabled:
		return false
	button.pressed.emit()
	await get_tree().process_frame
	var started: bool = construction.phase in ["clearing", "building"] and construction.worker_ids.has(id)
	_check(started, "The plot action actually starts the requested worker's clearing or construction.")
	return started

func _replace_from_plot(id: String) -> bool:
	if not await _open_plot():
		return false
	_check(plot.menu.replacement_button.visible, "The interrupted construction exposes its replacement action.")
	plot.menu.replacement_button.pressed.emit()
	await get_tree().process_frame
	var chosen: bool = await _choose_plot_worker(id)
	_check(chosen and construction.worker_ids.has(id), "The actual replacement selector reserves the paid worker.")
	return chosen and construction.worker_ids.has(id)

func _choose_plot_worker(id: String) -> bool:
	var assignment: WorkshopWorkerAssignmentUI = plot.menu._worker_assignment_menu
	_check(is_instance_valid(assignment), "The actual plot worker selector opens.")
	if not is_instance_valid(assignment):
		return false
	var slot: Button = assignment.slot_grid.get_child(0) as Button
	slot.pressed.emit()
	await get_tree().process_frame
	var option: Button
	for child: Node in assignment.worker_list.get_children():
		if child is Button and str(child.get_meta("worker_id", "")) == id:
			option = child as Button
			break
	_check(option != null and not option.disabled, "The requested paid worker is selectable.")
	if option == null or option.disabled:
		return false
	option.pressed.emit()
	await get_tree().process_frame
	_check(not assignment.next_button.disabled, "The selected worker enables Next.")
	assignment.next_button.pressed.emit()
	await get_tree().process_frame
	return true

func _open_plot() -> bool:
	if not await _approach(plot, plot.get_node("InteractableComponent").global_position + Vector2(0, 4)):
		return false
	await _press_interact()
	_check(is_instance_valid(plot.menu), "The authored construction plot opens through interaction.")
	return is_instance_valid(plot.menu)

func _approach(target: Node, point: Vector2) -> bool:
	# Player placement is a fixture shortcut; worker arrivals use the real route.
	player.global_position = point
	for _frame: int in range(3):
		await get_tree().physics_frame
	_check(player.current_interactable == target, "The fixture player is inside the authored interaction area: " + str(target.name))
	return player.current_interactable == target

func _press_interact() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = "interact"
	get_viewport().push_input(event)
	await get_tree().process_frame

func _drive_arrival(id: String) -> bool:
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if worker == null or worker.physical_approach.is_empty():
		return false
	var origin: Vector2 = worker.physical_approach.position
	var arrived_at_start: bool = bool(worker.physical_approach.get("arrived", false))
	var moved: bool = false
	for _frame: int in range(4000):
		if worker.physical_approach.get("arrived", false):
			break
		SHIFT_DRIVER.visual_frame(visuals, 0.1)
		moved = moved or worker.physical_approach.position.distance_to(origin) > 0.1
	return worker.physical_approach.get("arrived", false) \
		and worker.physical_approach.position.distance_to(worker.physical_approach.target) <= 0.1 \
		and (arrived_at_start or moved)

func _advance_recovery_day(day: int) -> bool:
	# Drive the real presence route for every paid construction shift. A coarse
	# clock skip by itself cannot make a worker depart and return to the plot.
	var minute: int = _minute_of_day()
	if minute < 7 * 60:
		var before_morning: int = construction._remaining_work_units()
		if not TimeComponentManager.advance_minutes(7 * 60 - minute):
			_check(false, "Recovery day %d reaches the 07:00 shift." % day)
			return false
		_check(construction._remaining_work_units() == before_morning,
			"No construction progresses before 07:00 on recovery day %d." % day)
		minute = _minute_of_day()
	var replacement: WorkerData = WorkerDatabase.get_worker_data(REPLACEMENT)
	var assigned: bool = construction.phase == "building" and construction.worker_ids.has(REPLACEMENT)
	var remaining: int = construction._remaining_work_units()
	var eligible: int = 0
	if assigned and replacement != null and not replacement.is_payroll_blocked() and minute < 15 * 60:
		if not _drive_arrival(REPLACEMENT):
			_check(false, "The replacement physically arrives on recovery day %d." % day)
			return false
		var now: int = TimeComponentManager.current_day * 1440 + minute
		var paid_end: int = (replacement.payroll_paid_until_day + 1) * 1440 + 7 * 60
		eligible = maxi(0, mini(now + 15 * 60 - minute, paid_end) - now)
	if minute < 15 * 60:
		if not TimeComponentManager.advance_minutes(15 * 60 - minute):
			_check(false, "Recovery day %d reaches the 15:00 shift end." % day)
			return false
	if assigned:
		_check(remaining - construction._remaining_work_units() == mini(remaining, eligible),
			"Replacement progress equals its arrived, paid shift minutes on recovery day %d." % day)
	if construction.phase == "building" and construction.worker_ids.has(REPLACEMENT):
		_check(_drive_departure(REPLACEMENT), "The replacement physically departs after recovery shift %d." % day)
	var overnight_remaining: int = construction._remaining_work_units()
	var recovering: CitizenData = CitizenManager.get_citizen(FIRST)
	if recovering == null:
		_check(false, "The former worker remains a resident during recovery.")
		return false
	var before_satisfaction: float = recovering.satisfaction
	var before_status: CitizenData.EmploymentStatus = recovering.employment_status
	var before_settlement: int = CitizenNeedsManager.last_processed_day
	if not TimeComponentManager.advance_minutes(1439 - _minute_of_day()):
		_check(false, "Recovery day %d reaches 23:59." % day)
		return false
	_check(is_equal_approx(recovering.satisfaction, before_satisfaction)
		and recovering.employment_status == before_status and CitizenNeedsManager.last_processed_day == before_settlement
		and construction._remaining_work_units() == overnight_remaining,
		"Recovery does not apply early at 23:59 on day %d." % day)
	if not TimeComponentManager.advance_minutes(1):
		_check(false, "Recovery day %d reaches midnight." % day)
		return false
	_check(construction._remaining_work_units() == overnight_remaining,
		"No construction progresses overnight after recovery shift %d." % day)
	return true

func _drive_departure(id: String) -> bool:
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if worker == null or worker.physical_approach.get("arrival_minute", -1) != WorkerData.PLOT_DEPARTURE_PENDING:
		return false
	var departure: Node2D = runtime.get_node("WorkerDeparture/NearSpawn") as Node2D
	for _frame: int in range(4000):
		if worker.physical_approach.position.distance_to(departure.global_position) <= 0.1:
			break
		SHIFT_DRIVER.visual_frame(visuals, 0.1)
	return worker.physical_approach.position.distance_to(departure.global_position) <= 0.1 \
		and worker.physical_approach.get("arrival_minute", -1) == WorkerData.PLOT_DEPARTURE_PENDING

func _same_counts(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for item_id: String in left:
		if not right.has(item_id) or int(left[item_id]) != int(right[item_id]):
			return false
	return true

func _minute_of_day() -> int:
	return TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _write_evidence(data: Dictionary) -> void:
	var file := FileAccess.open(EVIDENCE, FileAccess.WRITE)
	_check(file != null, "Journey evidence can be written in the isolated profile.")
	if file != null:
		file.store_string(JSON.stringify(data, "\t", true, true))
		file.close()

func _read_evidence(stage: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE))
	_check(data is Dictionary and data.get("stage") == stage, "The preceding phase produced the expected evidence: " + stage)
	return data if data is Dictionary and data.get("stage") == stage else {}

func _finish() -> void:
	print("MultiDayNeedsJourney ", phase, ": ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
