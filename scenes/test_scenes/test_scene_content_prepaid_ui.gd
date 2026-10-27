extends Node

## Isolated fixture only: explicit prices/funds exercise production UI bindings.
const BOARD: PackedScene = preload("res://scenes/ui/job_board_ui/job_board_ui.tscn")
var failures: int = 0
var board: JobBoardUI
var callbacks: int = 0
var observed_ids := PackedStringArray()
var expected_wallet: int = 0
var expected_workers: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _seed(id: String, profession: WorkerData.Profession, satisfaction: float) -> CitizenData:
	var citizen := CitizenData.new()
	citizen.citizen_id = id
	citizen.display_name = "Fixture " + id
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.APPLICANT
	citizen.profession = profession
	citizen.satisfaction = satisfaction
	CitizenManager.add_citizen(citizen)
	return citizen

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.current_day = 100
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_minute = 0
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	WorkerDatabase.onboarding_period_rates = {WorkerData.Profession.LABORER: 2, WorkerData.Profession.HAULER: 3}
	Inventory.items.clear()
	_seed("first", WorkerData.Profession.LABORER, 0.62)
	_seed("second", WorkerData.Profession.HAULER, 0.87)
	for i: int in range(5):
		_seed("scroll_%d" % i, WorkerData.Profession.LABORER, 0.5)
	board = BOARD.instantiate()
	add_child(board)
	board.open()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(board.cards.size() == 7 and board.applicant_list.item_count == 7, "All available applicants have cards and native list entries.")
	_expect(WorkerDatabase.workers_by_id.is_empty() and Inventory.items.is_empty(), "Opening the board does not hire or charge.")
	_expect(board.cards[0].name_label.text == "Fixture first" and board.cards[0].satisfaction_bar.value == 62, "Cards display actual names and satisfaction values.")
	_expect(board.cards[0].portrait.size == Vector2(32, 32), "Portrait control retains native 32x32 size.")
	await _capture("job-board-initial")
	for option: int in range(3):
		board.contract_days_option.select(option)
		board.contract_days_option.item_selected.emit(option)
		var days: int = WorkerDatabase.CONTRACT_DAYS[option]
		_expect(board.cards[0].wage_label.text == "%d / %dd" % [2 * (option + 1), days], "Laborer card shows the selected package price.")
		_expect(board.cards[1].wage_label.text == "%d / %dd" % [3 * (option + 1), days], "Hauler card shows its own profession package price.")
		_expect(board.quote_label.text.contains("%d-day prepaid: %d" % [days, 2 * (option + 1)]), "Native quote follows 3/6/9 duration selection.")
	board.cards[1].selection_button.set_pressed(true)
	_expect(board.applicant_list.get_selected_items() == PackedInt32Array([0, 1]), "Checkboxes select independently.")
	_expect(board.quote_label.text.contains("2 workers | 9-day prepaid: 15"), "Batch quote totals the selected packages.")
	await _capture("job-board-selected-nine-day-batch")
	board.cards[0].selection_button.set_pressed(false)
	_expect(board.applicant_list.get_selected_items() == PackedInt32Array([1]), "Toggling one preserves the other.")
	board.cards[1].selection_button.set_pressed(false)
	_expect(board.applicant_list.get_selected_items().is_empty() and board.hire_button.disabled, "Toggling off clears selection and disables Hire.")
	board.cards[0].selection_button.set_pressed(true)
	board.cards[1].selection_button.set_pressed(true)
	Inventory.items["shekel"] = 14
	board._on_hire_button_pressed()
	_expect(WorkerDatabase.workers_by_id.is_empty() and Inventory.items.get("shekel", 0) == 14, "Insufficient batch funds hire none and charge nothing.")
	await _capture("job-board-insufficient-batch")
	Inventory.items["shekel"] = 15
	observed_ids = PackedStringArray(["first", "second"])
	expected_wallet = 0
	expected_workers = 2
	Inventory.items_changed.connect(_observe_batch)
	WorkerDatabase.payroll_changed.connect(_observe_batch)
	board._on_hire_button_pressed()
	Inventory.items_changed.disconnect(_observe_batch)
	WorkerDatabase.payroll_changed.disconnect(_observe_batch)
	_expect(callbacks == 2, "UI batch notifies once per signal with reentrant clicks blocked.")
	var hired: WorkerData = WorkerDatabase.get_worker_data("first")
	_expect(hired != null and hired.payroll_contract_days == 9 and hired.payroll_paid_until_day == 109, "Exact funds hire the selected nine-day native contract.")
	_expect(int(Inventory.items.get("shekel", 0)) == 0 and WorkerDatabase.workers_by_id.size() == 2, "One Hire buys both contracts atomically.")
	Inventory.items["shekel"] = 100
	board._on_hire_button_pressed()
	_expect(int(Inventory.items.get("shekel", 0)) == 100 and WorkerDatabase.workers_by_id.size() == 2, "Repeated click with fresh funds cannot buy an unselected new batch.")
	board.candidate_scroll.scroll_vertical = 80
	var saved_scroll: int = board.candidate_scroll.scroll_vertical
	board._poll_applicants()
	_expect(saved_scroll > 0 and board.candidate_scroll.scroll_vertical == saved_scroll and board.candidate_scroll.clip_contents, "Polling preserves manual scroll and cards remain clipped.")
	TimeComponentManager.current_hour = 17
	board._refresh_quote()
	_expect(board.hire_button.disabled and board.feedback_label.text == "Closed | Opens 08:00", "The native 17:00 closure is visible.")
	board.close_button.pressed.emit()
	_expect(not board.visible and not get_tree().paused and board.refresh_timer.is_stopped(), "Top Close closes and resumes gameplay.")
	board.open()
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	board._unhandled_input(cancel)
	_expect(not board.visible and not get_tree().paused, "Escape closes after reopening.")
	CitizenManager.citizens_by_id.clear()
	board.open()
	_expect(board.empty_state_panel.visible and board.hire_button.disabled, "Empty state disables Hire.")
	board.close()
	_test_atomic_backend()
	print("ContentPrepaidUITest: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)

func _capture(label: String) -> void:
	var directory: String = OS.get_environment("TIP_MVP_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	_expect(error == OK, "Capture directory can be created.")
	if error != OK:
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var logical: Image = get_viewport().get_texture().get_image()
	_expect(logical.get_size() == Vector2i(400, 225), "GL capture uses the native logical viewport.")
	if logical.get_size() != Vector2i(400, 225):
		logical.resize(400, 225, Image.INTERPOLATE_NEAREST)
	_expect(logical.save_png(directory.path_join(label + "-400x225.png")) == OK, "Save logical capture " + label)
	logical.resize(1200, 675, Image.INTERPOLATE_NEAREST)
	_expect(logical.save_png(directory.path_join(label + "-1200x675.png")) == OK, "Save nearest-scaled capture " + label)

func _reset_backend() -> void:
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	WorkerDatabase._payroll_settling = false
	WorkerDatabase.onboarding_period_rates = {WorkerData.Profession.LABORER: 2, WorkerData.Profession.HAULER: 3}
	Inventory.items.clear()
	TimeComponentManager.current_day = 100
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_minute = 15

func _observe_batch() -> void:
	callbacks += 1
	_expect(WorkerDatabase.workers_by_id.size() == expected_workers and int(Inventory.items.get("shekel", 0)) == expected_wallet, "Observers see all memberships and total debit together.")
	for id: String in observed_ids:
		_expect(WorkerDatabase.get_worker_data(id) != null and CitizenManager.get_citizen(id).employment_status == CitizenData.EmploymentStatus.HIRED, "Every candidate is hired before notifications.")
	_expect(WorkerDatabase.hire_applicants(PackedStringArray(["other"]), 1, 3).is_empty(), "Reentrant batch hire is rejected.")
	_expect(WorkerDatabase.hire_applicant("other", 1, 3) == null, "Reentrant single hire is rejected.")
	_expect(not WorkerDatabase.renew_contract(observed_ids[0], 3), "Reentrant renewal is rejected.")
	if board._hiring:
		board._on_hire_button_pressed()

func _test_atomic_backend() -> void:
	for days: int in WorkerDatabase.CONTRACT_DAYS:
		_reset_backend()
		_seed("a", WorkerData.Profession.LABORER, 0.5)
		_seed("b", WorkerData.Profession.HAULER, 0.5)
		_seed("other", WorkerData.Profession.LABORER, 0.5)
		Inventory.items["shekel"] = 5 * (days / 3) + 50
		observed_ids = PackedStringArray(["a", "b"])
		expected_wallet = 50
		expected_workers = 2
		callbacks = 0
		Inventory.items_changed.connect(_observe_batch)
		WorkerDatabase.payroll_changed.connect(_observe_batch)
		var hired: Array[WorkerData] = WorkerDatabase.hire_applicants(observed_ids, 1, days)
		Inventory.items_changed.disconnect(_observe_batch)
		WorkerDatabase.payroll_changed.disconnect(_observe_batch)
		_expect(hired.size() == 2 and callbacks == 2 and not WorkerDatabase._payroll_settling, "Batch sends one notification per signal and releases its guard.")
		for worker: WorkerData in hired:
			_expect(worker.payroll_contract_days == days and worker.payroll_paid_until_day == 100 + days and worker.payroll_paid_start_minute == 100 * 1440 + 495, "Batch preserves duration, expiry and exact purchase minute.")
		_expect(WorkerDatabase.hire_applicants(observed_ids, 1, days).is_empty() and Inventory.items.get("shekel", 0) == 50, "Repeated completed batch does not charge again.")
	_reset_backend()
	var a: CitizenData = _seed("a", WorkerData.Profession.LABORER, 0.5)
	var b: CitizenData = _seed("b", WorkerData.Profession.HAULER, 0.5)
	Inventory.items["shekel"] = 100
	for ids: PackedStringArray in [PackedStringArray(), PackedStringArray(["a", "a"]), PackedStringArray(["a", " a "]), PackedStringArray(["a", "missing"])]:
		_expect(WorkerDatabase.hire_applicants(ids).is_empty(), "Empty, duplicate, alias-duplicate and missing IDs reject the complete batch.")
	for invalid_days: int in [0, -3, 4, 9223372036854775807]:
		_expect(WorkerDatabase.hire_applicants(PackedStringArray(["a", "b"]), 1, invalid_days).is_empty(), "Invalid durations reject without mutation.")
	b.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	_expect(WorkerDatabase.hire_applicants(PackedStringArray(["a", "b"])).is_empty(), "Unavailable member cancels the whole batch.")
	b.employment_status = CitizenData.EmploymentStatus.APPLICANT
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.HAULER] = -1
	_expect(WorkerDatabase.hire_applicants(PackedStringArray(["a", "b"])).is_empty(), "Unpriced profession cancels the whole batch.")
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.HAULER] = 3
	TimeComponentManager.current_hour = 17
	_expect(WorkerDatabase.hire_applicants(PackedStringArray(["a", "b"])).is_empty(), "Closed board rejects the entire batch.")
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_day = WorkerDatabase.MAX_CONTRACT_DAY - 2
	_expect(WorkerDatabase.hire_applicants(PackedStringArray(["a", "b"])).is_empty(), "Day limit rejects before mutation.")
	TimeComponentManager.current_day = 100
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 3000000000000000000
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.HAULER] = 3000000000000000000
	Inventory.items["shekel"] = 9223372036854775807
	_expect(WorkerDatabase.hire_applicants(PackedStringArray(["a", "b"]), 1, 9).is_empty(), "Aggregate overflow rejects the entire batch.")
	_expect(WorkerDatabase.workers_by_id.is_empty() and a.employment_status == CitizenData.EmploymentStatus.APPLICANT and Inventory.items.get("shekel", 0) == 9223372036854775807, "Invalid batches leave membership and wallet untouched.")
	_reset_backend()
	_seed("a", WorkerData.Profession.LABORER, 0.5)
	_seed("b", WorkerData.Profession.HAULER, 0.5)
	var retained := WorkerData.new()
	retained.worker_id = "a"
	retained.profession_xp = 72
	retained.profession_star = 2
	WorkerDatabase.dismissed_workers["a"] = retained
	Inventory.items["shekel"] = 5
	var rehired: Array[WorkerData] = WorkerDatabase.hire_applicants(PackedStringArray(["a", "b"]))
	_expect(rehired.size() == 2 and rehired[0] == retained and retained.profession_xp == 72 and retained.profession_star == 2, "Atomic rehire preserves the worker resource and earned profession progress.")
	_expect(Inventory.items.get("shekel", 0) == 0 and not WorkerDatabase.dismissed_workers.has("a"), "Exact funds consume only the total and remove retained dismissed membership.")
