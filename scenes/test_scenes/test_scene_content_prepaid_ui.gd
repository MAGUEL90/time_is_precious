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
	var long_name: String = "A Very Long Worker Name Preserved In The Save"
	var long_candidate: CitizenData
	for i: int in range(5):
		var candidate: CitizenData = _seed("scroll_%d" % i, WorkerData.Profession.LABORER, 0.5)
		if i == 0:
			candidate.display_name = long_name
			long_candidate = candidate
	board = BOARD.instantiate()
	add_child(board)
	board.open()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(board.cards.size() == 7 and board.applicant_list.item_count == 7, "All available applicants have cards and native list entries.")
	_expect(WorkerDatabase.workers_by_id.is_empty() and Inventory.items.is_empty(), "Opening the board does not hire or charge.")
	_expect(board.cards[0].name_label.text == "Fixture first" and board.cards[0].satisfaction_bar.value == 62, "Cards display actual names and satisfaction values.")
	_expect(board.cards[0].portrait.size == Vector2(32, 32), "Portrait control retains native 32x32 size.")
	_expect(board.feedback_label.text.is_empty(), "Remaining-time feedback is absent on open.")
	_expect(not board.wallet_label.text.contains("Shekel") and not board.wallet_label.text.contains("Hours"), "Wallet and hours text do not appear in the menu.")
	_expect(board.cards[2].name_label.text != long_name and board.cards[2].name_label.tooltip_text == long_name and long_candidate.display_name == long_name, "Only the long displayed name is shortened; identity and tooltip retain the original.")
	_expect(board.cards[2].name_label.get_global_rect().end.x <= board.cards[2].role_label.get_global_rect().position.x, "Long display name does not overlap the role.")
	await _capture("job-board-initial")
	board.hire_button.pressed.emit()
	_expect(board.confirmation_open and board.confirmation_layer.visible, "Hire opens the duration and confirmation panel.")
	_expect(WorkerDatabase.workers_by_id.is_empty() and Inventory.items.is_empty(), "Opening the confirmation panel does not hire or charge.")
	_expect(board.duration_buttons.size() == 3, "Only 3, 6, and 9-day buttons are offered.")
	await get_tree().process_frame
	_expect(board.selected_names_container.get_child_count() == 1, "Selected name appears in the confirmation panel.")
	_expect(board.selected_names_container.get_global_rect().position.x < board.duration_button_container.get_global_rect().position.x, "Names are to the left of duration buttons.")
	_expect(board.duration_buttons[0].has_focus(), "The selected duration has keyboard focus on opening.")
	for step: int in range(8):
		var focus_event := InputEventAction.new()
		focus_event.action = "ui_focus_next"
		focus_event.pressed = true
		get_viewport().push_input(focus_event)
		focus_event = InputEventAction.new()
		focus_event.action = "ui_focus_next"
		get_viewport().push_input(focus_event)
		await get_tree().process_frame
		var focus: Control = get_viewport().gui_get_focus_owner()
		_expect(focus != null and board.confirmation_panel.is_ancestor_of(focus), "Keyboard focus stays within the open confirmation panel.")
	await _capture("job-board-confirm-single")
	for option: int in range(3):
		var days: int = WorkerDatabase.CONTRACT_DAYS[option]
		_expect(int(board.duration_buttons[option].get_meta("contract_days")) == days, "A duration button maps to the existing allowed duration.")
		board.duration_buttons[option].pressed.emit()
		_expect(board.cards[0].wage_label.text == str(2 * (option + 1)), "Laborer card shows its price without trailing duration text.")
		_expect(board.cards[1].wage_label.text == str(3 * (option + 1)), "Hauler card shows its own profession price.")
		_expect(board.confirm_quote_amount_label.text == str(2 * (option + 1)) and board.confirm_quote_icon.visible, "The quoted price and coin are visible before confirmation.")
		_expect(WorkerDatabase.workers_by_id.is_empty() and Inventory.items.is_empty(), "Choosing a duration does not hire or charge.")
	board.cancel_hire_button.pressed.emit()
	_expect(not board.confirmation_open and board.visible and WorkerDatabase.workers_by_id.is_empty(), "Cancel returns to the board without a hire.")
	board.cards[1].selection_button.set_pressed(true)
	_expect(board.applicant_list.get_selected_items() == PackedInt32Array([0, 1]), "Checkboxes select independently.")
	board.hire_button.pressed.emit()
	_expect(board.confirm_quote_amount_label.text == "15" and board.selected_names_container.get_child_count() == 2, "Nine-day batch quote totals the selected candidates.")
	await _capture("job-board-confirm-batch")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	board._unhandled_input(cancel)
	_expect(not board.confirmation_open and board.visible and Inventory.items.is_empty(), "Escape backs out of the panel without charging.")
	board.hire_button.pressed.emit()
	Inventory.items["shekel"] = 100
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 3
	board.confirm_hire_button.pressed.emit()
	_expect(board.confirmation_open and board.confirm_quote_amount_label.text == "18" and Inventory.items.get("shekel", 0) == 100 and WorkerDatabase.workers_by_id.is_empty(), "A changed quote requires a fresh confirmation without charging.")
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 2
	board.confirm_hire_button.pressed.emit()
	_expect(board.confirmation_open and board.confirm_quote_amount_label.text == "15" and Inventory.items.get("shekel", 0) == 100, "A second changed quote also requires review.")
	Inventory.items["shekel"] = 14
	board.confirm_hire_button.pressed.emit()
	_expect(board.confirmation_open and WorkerDatabase.workers_by_id.is_empty() and Inventory.items.get("shekel", 0) == 14, "Insufficient batch funds hire none and charge nothing.")
	_expect(not board.confirmation_feedback_label.text.is_empty(), "An unsuccessful hire supplies contextual feedback.")
	await _capture("job-board-insufficient-batch")
	Inventory.items["shekel"] = 15
	observed_ids = PackedStringArray(["first", "second"])
	expected_wallet = 0
	expected_workers = 2
	Inventory.items_changed.connect(_observe_batch)
	WorkerDatabase.payroll_changed.connect(_observe_batch)
	board.confirm_hire_button.pressed.emit()
	Inventory.items_changed.disconnect(_observe_batch)
	WorkerDatabase.payroll_changed.disconnect(_observe_batch)
	_expect(callbacks == 2, "UI batch notifies once per signal with reentrant clicks blocked.")
	var hired: WorkerData = WorkerDatabase.get_worker_data("first")
	_expect(hired != null and hired.payroll_contract_days == 9 and hired.payroll_paid_until_day == 109, "Exact funds hire the selected nine-day native contract.")
	_expect(int(Inventory.items.get("shekel", 0)) == 0 and WorkerDatabase.workers_by_id.size() == 2, "Final confirmation buys both contracts atomically once.")
	Inventory.items["shekel"] = 100
	board.confirm_hire_button.pressed.emit()
	_expect(int(Inventory.items.get("shekel", 0)) == 100 and WorkerDatabase.workers_by_id.size() == 2, "Stale repeated confirmation cannot buy another batch.")
	board._refresh_applicants(false)
	await get_tree().process_frame
	for index: int in range(board.applicants.size()):
		if board.applicants[index].citizen_id == "scroll_0":
			board.applicant_list.deselect_all()
			board.applicant_list.select(index)
			board.candidate_scroll.ensure_control_visible(board.cards[index])
			break
	board._refresh_quote()
	board.hire_button.pressed.emit()
	await get_tree().process_frame
	var displayed_name: Label = board.selected_names_container.get_child(0)
	_expect(displayed_name.text != long_name and displayed_name.tooltip_text == long_name, "Confirmation shortens long names only for display.")
	await _capture("job-board-confirm-long-name")
	board.cancel_hire_button.pressed.emit()
	var connections: int = board.confirm_hire_button.pressed.get_connections().size()
	for cycle: int in range(4):
		board.hire_button.pressed.emit()
		_expect(board.confirmation_open, "Confirmation reopens on cycle %d." % cycle)
		board.cancel_hire_button.pressed.emit()
	_expect(board.confirm_hire_button.pressed.get_connections().size() == connections and Inventory.items.get("shekel", 0) == 100, "Repeated open and cancel neither duplicates signals nor charges.")
	board.candidate_scroll.scroll_vertical = 80
	var saved_scroll: int = board.candidate_scroll.scroll_vertical
	board._poll_applicants()
	_expect(saved_scroll > 0 and board.candidate_scroll.scroll_vertical == saved_scroll and board.candidate_scroll.clip_contents, "Polling preserves manual scroll and clips cards.")
	TimeComponentManager.current_hour = 17
	board._refresh_quote()
	_expect(board.hire_button.disabled and not board.feedback_label.text.contains("08:00"), "Closing time disables hiring without displaying menu hours.")
	board.close_button.pressed.emit()
	_expect(not board.visible and not get_tree().paused and board.refresh_timer.is_stopped(), "Top Close closes and resumes gameplay.")
	board.open()
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
		board._confirm_hire()

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
