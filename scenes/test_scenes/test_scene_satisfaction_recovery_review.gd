extends Node

## Multi-day physical-needs regression for the provisional 66% two-need target.
const CITY_TOOL_STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const JOB_BOARD_SCENE: PackedScene = preload("res://scenes/job_board/job_board.tscn")
const CITIZEN_ID: String = "satisfaction_recovery_review_resident"
const FOOD_ID: String = "barley_bread"
const CLOTHING_ID: String = "simple_clothes"
const FIXTURE_WALLET: int = 100
const TWO_NEED_TARGET: float = 0.66
const FULL_NEED_TARGET: float = 0.99

var failures: int = 0
var fixture_day: int = 0
var provider: Node
var provider_created: bool = false
var board: Node2D
var resident: CitizenData
var hired_worker: WorkerData
var contract_snapshot: Dictionary = {}

var original_citizens: Dictionary = {}
var original_workers: Dictionary = {}
var original_dismissed_workers: Dictionary = {}
var original_inventory: Dictionary = {}
var original_clock: Dictionary = {}
var original_shelter_capacity: int = 0
var original_payroll_settling: bool = false
var original_needs_state: Dictionary = {}
var original_provider_state: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	_snapshot_global_state()
	_prepare_fixture()
	await _test_shortage_crossing_and_hire()
	if hired_worker != null:
		_test_clothing_restock_and_recovery()
	_cleanup_fixture()

	if failures > 0:
		push_error("SatisfactionRecoveryReviewTest FAILED (%d failure(s))" % failures)
		get_tree().quit(1)
		return

	print("SatisfactionRecoveryReviewTest PASSED")
	get_tree().quit(0)


func _snapshot_global_state() -> void:
	original_citizens = CitizenManager.citizens_by_id.duplicate()
	original_workers = WorkerDatabase.workers_by_id.duplicate()
	original_dismissed_workers = WorkerDatabase.dismissed_workers.duplicate()
	original_inventory = Inventory.items.duplicate(true)
	original_clock = {
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"paused": TimeComponentManager.is_paused,
		"processing": TimeComponentManager.is_processing(),
		"tree_paused": get_tree().paused
	}
	original_shelter_capacity = CityStockManager.shelter_capacity
	original_payroll_settling = WorkerDatabase._payroll_settling
	for property_name: String in [
		"last_food_fulfilled_count", "last_food_unfulfilled_count",
		"last_clothing_fulfilled_count", "last_clothing_unfulfilled_count",
		"last_shelter_capacity_fulfilled_count", "last_shelter_capacity_unfulfilled_count",
		"last_processed_day", "last_food_processed_day", "last_clothing_processed_day",
		"_processing_daily_needs", "_processing_food", "_processing_clothing",
		"_daily_needs_retry_pending", "_daily_needs_retry_after_frame",
		"clothing_allocations", "last_needs_results"
	]:
		var value: Variant = CitizenNeedsManager.get(property_name)
		if value is Dictionary or value is Array:
			value = value.duplicate(true)
		original_needs_state[property_name] = value

	provider = get_node_or_null("/root/WorkStateRuntime/CityToolStorage")
	if is_instance_valid(provider):
		original_provider_state = _snapshot_provider(provider)


func _snapshot_provider(target: Node) -> Dictionary:
	var snapshot: Dictionary = {}
	for property_name: String in ["items", "food_portions", "units"]:
		var value: Variant = target.get(property_name)
		if value is Dictionary:
			snapshot[property_name] = value.duplicate(true)
	for property_name: String in ["_unit_sequence", "_transfer_in_progress"]:
		snapshot[property_name] = target.get(property_name)
	return snapshot


func _prepare_fixture() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	if not is_instance_valid(provider):
		provider = CITY_TOOL_STORAGE_SCRIPT.new()
		provider.name = "CityToolStorage"
		WorkStateRuntime.add_child(provider)
		provider_created = true

	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	WorkerDatabase._payroll_settling = false
	Inventory.items.clear()
	Inventory.items["shekel"] = FIXTURE_WALLET
	resident = CitizenData.new()
	resident.citizen_id = CITIZEN_ID
	resident.display_name = "Recovery Review Resident"
	resident.population_status = CitizenData.PopulationStatus.RESIDENT
	resident.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	resident.satisfaction = 0.42
	CitizenManager.add_citizen(resident)

	fixture_day = TimeComponentManager.current_day + 100
	TimeComponentManager.current_day = fixture_day
	TimeComponentManager.current_hour = 7
	TimeComponentManager.current_minute = 0
	CitizenNeedsManager.last_processed_day = fixture_day - 1
	CitizenNeedsManager.last_food_processed_day = fixture_day - 1
	CitizenNeedsManager.last_clothing_processed_day = fixture_day - 1
	CitizenNeedsManager.last_food_fulfilled_count = 0
	CitizenNeedsManager.last_food_unfulfilled_count = 0
	CitizenNeedsManager.last_clothing_fulfilled_count = 0
	CitizenNeedsManager.last_clothing_unfulfilled_count = 0
	CitizenNeedsManager.last_shelter_capacity_fulfilled_count = 0
	CitizenNeedsManager.last_shelter_capacity_unfulfilled_count = 0
	CitizenNeedsManager._processing_daily_needs = false
	CitizenNeedsManager._processing_food = false
	CitizenNeedsManager._processing_clothing = false
	CitizenNeedsManager._daily_needs_retry_pending = false
	CitizenNeedsManager._daily_needs_retry_after_frame = false
	CitizenNeedsManager.clothing_allocations.clear()
	CitizenNeedsManager.last_needs_results.clear()
	provider.set("items", {})
	provider.set("food_portions", {})
	provider.set("units", {})
	provider.set("_unit_sequence", 0)
	provider.set("_transfer_in_progress", false)
	CityStockManager.shelter_capacity = 1

	board = JOB_BOARD_SCENE.instantiate() as Node2D
	board.name = "SatisfactionRecoveryReviewJobBoard"
	add_child(board)
	_expect(_restock_food(), "The first evaluation receives one real bread ration.")
	_expect(int(provider.call("get_food_supply_points")) == 1
		and int(provider.call("get_clothing_item_count")) == 0
		and CityStockManager.shelter_capacity == 1,
		"The opening fixture has physical food and shelter, with exactly clothing missing.")
	_expect(CitizenNeedsManager.get_food_consumer_count() == 1,
		"The linked worker added later must not duplicate the resident's daily food allocation.")


func _test_shortage_crossing_and_hire() -> void:
	var before_evaluation: Dictionary = CitizenNeedsManager.get_person_needs_summary(CITIZEN_ID)
	_expect(not bool(before_evaluation.evaluated)
		and is_equal_approx(float(before_evaluation.condition_target), -1.0)
		and int(before_evaluation.food_stock) == 1
		and int(before_evaluation.clothing_stock) == 0
		and int(before_evaluation.shelter_capacity) == 1
		and int(provider.call("get_food_supply_points")) == 1,
		"Before settlement, the summary reports stock but leaves today's needs unknown and consumes nothing.")
	_expect(_settle_current_day(0.47),
		"The first real allocation fulfils food and shelter while clothing shortage sets the 66% target.")
	_expect(resident.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and CitizenManager.get_all_applicants().is_empty(),
		"At 47%, the resident is still below the actual applicant threshold.")

	_advance_day(8)
	_expect(_restock_food(), "Day two receives one physical bread ration.")
	var pre_threshold_evaluation: Dictionary = CitizenNeedsManager.get_person_needs_summary(CITIZEN_ID)
	_expect(not bool(pre_threshold_evaluation.evaluated)
		and int(pre_threshold_evaluation.food_stock) == 1
		and int(pre_threshold_evaluation.clothing_stock) == 0
		and is_equal_approx(float(pre_threshold_evaluation.satisfaction), 0.47),
		"The next day's pre-settlement view shows a bread restock, no clothing and unchanged Satisfaction.")
	_expect(_settle_current_day(0.52),
		"With clothing still missing, the second actual settlement moves 47% to 52% toward 66%.")
	_expect(resident.employment_status == CitizenData.EmploymentStatus.APPLICANT
		and CitizenManager.get_all_applicants().has(resident),
		"The daily evaluation naturally registers this resident after crossing the 50% threshold.")
	if resident.employment_status != CitizenData.EmploymentStatus.APPLICANT:
		return

	var price: int = WorkerDatabase.get_contract_price(WorkerData.Profession.LABORER, 9)
	_expect(price > 0 and int(Inventory.items.get("shekel", 0)) == FIXTURE_WALLET,
		"The explicit 100-Shekel fixture can cover the real nine-day Laborer quote.")
	if price <= 0:
		return
	var board_hire_succeeded: bool = await _hire_from_real_board(price)
	if not board_hire_succeeded:
		return
	contract_snapshot = _contract_snapshot(hired_worker)
	_assert_hired_worker(0.52, "Immediately after the actual hire during the clothing shortage")

	for expected_satisfaction: float in [0.57, 0.62, 0.66, 0.66]:
		_advance_day(8)
		_expect(_restock_food(), "Each shortage day receives one physical bread ration.")
		_expect(_settle_current_day(expected_satisfaction),
			"Food and shelter remain allocated while the actual clothing shortage persists.")
		_assert_hired_worker(expected_satisfaction,
			"After shortage settlement on day %d" % fixture_day)

	var stable_shortage: Dictionary = CitizenNeedsManager.get_person_needs_summary(CITIZEN_ID)
	_expect(not bool(stable_shortage.clothing)
		and bool(stable_shortage.food) and bool(stable_shortage.shelter)
		and is_equal_approx(float(stable_shortage.condition_target), TWO_NEED_TARGET)
		and is_equal_approx(float(stable_shortage.satisfaction), TWO_NEED_TARGET)
		and is_zero_approx(float(stable_shortage.satisfaction_delta))
		and str(stable_shortage.trend) == "stable",
		"The one-need shortage reaches and stabilizes exactly at 66% without overshoot.")


func _hire_from_real_board(expected_price: int) -> bool:
	_expect(WorkerDatabase.is_job_board_open()
		and TimeComponentManager.current_hour == 8
		and resident.satisfaction >= CitizenData.MIN_APPLICANT_SATISFACTION,
		"The real Job Board hire occurs at 08:00 after the 50% threshold settlement.")
	if not WorkerDatabase.is_job_board_open():
		return false

	board.call("on_player_interact", null)
	var panel: JobBoardUI = board.get("job_board_ui") as JobBoardUI
	_expect(is_instance_valid(panel) and bool(panel.get("visible")),
		"The authored JobBoard opens its real hiring UI during its service hours.")
	if not is_instance_valid(panel):
		return false
	var selected: bool = false
	for card in panel.get("cards"):
		if str(card.get("citizen_id")) == CITIZEN_ID:
			card.get("selection_button").set_pressed(true)
			selected = true
	var default_price: int = WorkerDatabase.get_contract_price(WorkerData.Profession.LABORER, 3)
	_expect(selected and str(panel.get("quote_amount_label").text) == str(default_price),
		"The real candidate card shows the default three-day quote before contract duration is changed.")
	if selected:
		panel.get("hire_button").pressed.emit()
		_expect(bool(panel.get("confirmation_open")),
			"The real Job Board opens contract confirmation for the selected resident.")
		for button: Button in panel.get("duration_buttons"):
			if int(button.get_meta("contract_days", -1)) == 9:
				button.pressed.emit()
		_expect(str(panel.get("confirm_quote_amount_label").text) == str(expected_price),
			"The confirmation preserves the concrete nine-day price before purchase.")
		panel.get("confirm_hire_button").pressed.emit()
		hired_worker = WorkerDatabase.get_worker_data(CITIZEN_ID)
		_expect(hired_worker != null
			and resident.employment_status == CitizenData.EmploymentStatus.HIRED
			and int(Inventory.items.get("shekel", 0)) == FIXTURE_WALLET - expected_price,
			"Confirming through the real Board hires one linked worker and debits the quote once.")
		if hired_worker != null:
			_expect(hired_worker.payroll_contract_days == 9
				and hired_worker.payroll_paid_from_day == fixture_day
				and hired_worker.payroll_paid_until_day == fixture_day + 9
				and hired_worker.payroll_paid_start_minute == fixture_day * 1440 + 8 * 60,
				"The paid worker receives an active nine-day contract starting at the 08:00 hire.")
			var hired_summary: Dictionary = CitizenNeedsManager.get_person_needs_summary(CITIZEN_ID)
			_expect(bool(hired_summary.food) and not bool(hired_summary.clothing)
				and bool(hired_summary.shelter)
				and is_equal_approx(float(hired_summary.condition_target), TWO_NEED_TARGET)
				and is_equal_approx(float(hired_summary.satisfaction), 0.52)
				and int(provider.call("get_clothing_item_count")) == 0,
				"The real hire occurs while clothing is still the sole unmet need and consumes no garment.")

	panel.get("close_button").pressed.emit()
	await get_tree().process_frame
	return hired_worker != null and resident.employment_status == CitizenData.EmploymentStatus.HIRED


func _test_clothing_restock_and_recovery() -> void:
	_expect(_restock_clothing(), "A real physical garment is restocked after the stable shortage evaluation.")
	var restocked_before_settlement: Dictionary = CitizenNeedsManager.get_person_needs_summary(CITIZEN_ID)
	_expect(not bool(restocked_before_settlement.clothing)
		and is_equal_approx(float(restocked_before_settlement.condition_target), TWO_NEED_TARGET)
		and is_equal_approx(float(restocked_before_settlement.satisfaction), TWO_NEED_TARGET)
		and int(restocked_before_settlement.clothing_stock) == 1
		and int(provider.call("get_clothing_item_count")) == 1
		and not CitizenNeedsManager.clothing_allocations.has(CITIZEN_ID),
		"Post-evaluation clothing restock does not retroactively change the shortage result or consume the garment.")
	_assert_hired_worker(TWO_NEED_TARGET,
		"After clothing is restocked but before the next settlement")

	_advance_day(8)
	_expect(_restock_food(), "The clothing recovery day also receives one physical bread ration.")
	var before_recovery_settlement: Dictionary = CitizenNeedsManager.get_person_needs_summary(CITIZEN_ID)
	_expect(not bool(before_recovery_settlement.evaluated)
		and int(before_recovery_settlement.food_stock) == 1
		and int(before_recovery_settlement.clothing_stock) == 1
		and int(provider.call("get_food_supply_points")) == 1
		and int(provider.call("get_clothing_item_count")) == 1
		and not CitizenNeedsManager.clothing_allocations.has(CITIZEN_ID),
		"Before recovery settlement, physical food and clothing remain in stock and no clothing allocation exists.")
	_expect(_settle_current_day(0.71),
		"Daily settlement consumes the bread and garment, assigns clothing and raises the target to 99%.")
	var recovery: Dictionary = CitizenNeedsManager.get_person_needs_summary(CITIZEN_ID)
	var allocation: Dictionary = CitizenNeedsManager.clothing_allocations.get(CITIZEN_ID, {})
	_expect(bool(recovery.food) and bool(recovery.clothing) and bool(recovery.shelter)
		and is_equal_approx(float(recovery.condition_target), FULL_NEED_TARGET)
		and is_equal_approx(float(recovery.satisfaction), 0.71)
		and is_equal_approx(float(recovery.satisfaction_delta), 0.05)
		and str(allocation.get("item_id", "")) == CLOTHING_ID
		and int(allocation.get("issued_day", -1)) == fixture_day
		and int(allocation.get("expires_day", -1)) == fixture_day + 6
		and int(provider.call("get_food_supply_points")) == 0
		and int(provider.call("get_clothing_item_count")) == 0,
		"Actual food and clothing allocations move the linked resident from the stable 66% target toward 99%.")
	_assert_hired_worker(0.71,
		"After clothing is physically allocated at daily settlement")

	_advance_day(8)
	_expect(_restock_food(), "The next recovery day receives one physical bread ration.")
	_expect(int(provider.call("get_clothing_item_count")) == 0
		and str(CitizenNeedsManager.clothing_allocations.get(CITIZEN_ID, {}).get("item_id", "")) == CLOTHING_ID,
		"A still-valid clothing allocation covers the next day without another physical garment.")
	_expect(_settle_current_day(0.76),
		"The clothing allocation keeps the 99% target while the second recovery step is bounded to five points.")
	_assert_hired_worker(0.76,
		"After the second full-need recovery settlement")


func _settle_current_day(expected_satisfaction: float) -> bool:
	var satisfaction_before: float = resident.satisfaction
	var food_before: int = int(provider.call("get_food_supply_points"))
	var clothing_before: int = int(provider.call("get_clothing_item_count"))
	CitizenNeedsManager.process_daily_needs()
	var summary: Dictionary = CitizenNeedsManager.get_person_needs_summary(CITIZEN_ID)
	var expected_target: float = FULL_NEED_TARGET if bool(summary.clothing) else TWO_NEED_TARGET
	var clothing_consumed: bool = bool(summary.clothing) and int(summary.clothing_days_left) == 7
	_expect(bool(summary.evaluated) and int(summary.day) == fixture_day
		and bool(summary.food) and bool(summary.shelter)
		and is_equal_approx(float(summary.condition_target), expected_target)
		and is_equal_approx(float(summary.satisfaction), expected_satisfaction)
		and is_equal_approx(float(summary.satisfaction_delta), expected_satisfaction - satisfaction_before)
		and float(summary.satisfaction) <= expected_target,
		"Daily evaluation on day %d uses the actual need target and never overshoots it." % fixture_day)
	_expect(food_before == 1 and int(provider.call("get_food_supply_points")) == 0
		and int(provider.call("get_clothing_item_count")) == maxi(0, clothing_before - int(clothing_consumed)),
		"Settlement consumes exactly one bread ration and consumes clothing only when it creates an allocation.")
	_expect(CitizenNeedsManager.last_food_fulfilled_count == 1
		and CitizenNeedsManager.last_food_unfulfilled_count == 0
		and CitizenNeedsManager.last_clothing_fulfilled_count == int(bool(summary.clothing))
		and CitizenNeedsManager.last_clothing_unfulfilled_count == int(not bool(summary.clothing))
		and CitizenNeedsManager.last_shelter_capacity_fulfilled_count == 1
		and CitizenNeedsManager.last_shelter_capacity_unfulfilled_count == 0,
		"Food, clothing allocations and one-place shelter counters match the only resident's actual outcomes.")
	if not bool(summary.clothing):
		_expect(not CitizenNeedsManager.clothing_allocations.has(CITIZEN_ID)
			and int(provider.call("get_clothing_item_count")) == 0,
			"A missing garment creates no allocation and leaves clothing unfulfilled.")
	return is_equal_approx(float(summary.satisfaction), expected_satisfaction)


func _assert_hired_worker(expected_satisfaction: float, phase: String) -> void:
	var current_citizen: CitizenData = CitizenManager.get_citizen(CITIZEN_ID)
	var current_worker: WorkerData = WorkerDatabase.get_worker_data(CITIZEN_ID)
	_expect(current_citizen == resident and current_citizen.citizen_id == CITIZEN_ID
		and current_citizen.employment_status == CitizenData.EmploymentStatus.HIRED
		and current_worker == hired_worker and current_worker.worker_id == CITIZEN_ID
		and current_worker.get_linked_citizen() == resident,
		"%s preserves the same linked citizen and worker identities and hired status." % phase)
	if current_citizen == null or current_worker == null:
		return
	_expect(is_equal_approx(current_citizen.satisfaction, expected_satisfaction)
		and is_equal_approx(current_worker.get_resolved_satisfaction(), expected_satisfaction)
		and _contract_snapshot(current_worker) == contract_snapshot
		and not current_worker.is_payroll_blocked(),
		"%s keeps the linked worker Satisfaction and paid contract unchanged." % phase)


func _contract_snapshot(worker: WorkerData) -> Dictionary:
	if worker == null:
		return {}
	return {
		"days": worker.payroll_contract_days,
		"start_day": worker.payroll_start_day,
		"paid_from_day": worker.payroll_paid_from_day,
		"paid_until_day": worker.payroll_paid_until_day,
		"paid_start_minute": worker.payroll_paid_start_minute,
		"period_rate": worker.payroll_period_rate,
		"last_attempt_day": worker.payroll_last_attempt_day
	}


func _restock_food() -> bool:
	return bool(provider.call("try_add_item", FOOD_ID, 1))


func _restock_clothing() -> bool:
	return bool(provider.call("try_add_item", CLOTHING_ID, 1))


func _advance_day(open_hour: int) -> void:
	fixture_day += 1
	TimeComponentManager.current_day = fixture_day
	TimeComponentManager.current_hour = open_hour
	TimeComponentManager.current_minute = 0


func _cleanup_fixture() -> void:
	if is_instance_valid(board):
		var panel: JobBoardUI = board.get("job_board_ui") as JobBoardUI
		if is_instance_valid(panel):
			panel.close()
		board.free()

	CitizenManager.citizens_by_id.assign(original_citizens)
	WorkerDatabase.workers_by_id.assign(original_workers)
	WorkerDatabase.dismissed_workers.assign(original_dismissed_workers)
	WorkerDatabase._payroll_settling = original_payroll_settling
	Inventory.items.assign(original_inventory)
	CityStockManager.shelter_capacity = original_shelter_capacity
	for property_name: String in original_needs_state:
		CitizenNeedsManager.set(property_name, original_needs_state[property_name])
	if provider_created:
		if is_instance_valid(provider):
			provider.free()
	else:
		_restore_provider(provider, original_provider_state)
	TimeComponentManager.current_day = int(original_clock.day)
	TimeComponentManager.current_hour = int(original_clock.hour)
	TimeComponentManager.current_minute = int(original_clock.minute)
	get_tree().paused = bool(original_clock.tree_paused)
	TimeComponentManager.is_paused = bool(original_clock.paused)
	TimeComponentManager.set_process(bool(original_clock.processing))


func _restore_provider(target: Node, snapshot: Dictionary) -> void:
	if not is_instance_valid(target):
		return
	for property_name: String in ["items", "food_portions", "units"]:
		if snapshot.has(property_name):
			target.set(property_name, snapshot[property_name].duplicate(true))
	for property_name: String in ["_unit_sequence", "_transfer_in_progress"]:
		if snapshot.has(property_name):
			target.set(property_name, snapshot[property_name])
