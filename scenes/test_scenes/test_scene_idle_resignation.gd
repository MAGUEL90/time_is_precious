extends Node

const STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const WORKSHOP_SCENE: PackedScene = preload("res://scenes/workshop/workshop.tscn")
const SAVE_STATE: Script = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const WALLET: int = 40

var failures: int = 0
var storage: Node
var watched_id: String = ""
var watched_worker: WorkerData
var storage_callbacks: int = 0
var payroll_callbacks: int = 0
var citizen_callbacks: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	storage = WorkStateRuntime.get_node_or_null("CityToolStorage")
	if storage == null:
		storage = STORAGE_SCRIPT.new()
		storage.name = "CityToolStorage"
		WorkStateRuntime.add_child(storage)
	_test_linked_resignation_and_rehire()
	_test_legacy_resignation_and_generator()
	_test_daily_idle_resignation_and_recovery()
	await _test_deferred_and_reentrant_sweep()
	_test_rejections_leave_state_unchanged()
	_test_legacy_workshop_assignment()
	_test_pending_immigrant_collision()
	print("IdleResignationTest: %s (%d checks failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _reset_fixture() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 50
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	WorkerDatabase._payroll_settling = false
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	WorkerDatabase.onboarding_period_rates = {WorkerData.Profession.LABORER: 2}
	CitizenManager.citizens_by_id.clear()
	CitizenGenerator.counter_id = 3
	ImmigrationManager.pending_immigrants.clear()
	CitizenNeedsManager.clothing_allocations.clear()
	CitizenNeedsManager.last_needs_results.clear()
	WorkManager.active_orders.clear()
	Inventory.items.clear()
	Inventory.items["shekel"] = WALLET
	storage.set("_transfer_in_progress", false)
	storage.set("units", {})
	storage_callbacks = 0
	payroll_callbacks = 0
	citizen_callbacks = 0

func _seed_worker(id: String, linked: bool) -> WorkerData:
	var worker := WorkerData.new()
	worker.worker_id = id
	worker.display_name = "Worker " + id
	worker.profession = WorkerData.Profession.LABORER
	worker.profession_xp = 17
	worker.profession_star = 2
	worker.wage_shekel_per_day = 7
	worker.satisfaction = 0.4 if linked else 0.0
	worker.food_fulfilled = true
	worker.clothing_fulfilled = false
	worker.shelter_fulfilled = true
	worker.payroll_start_day = 50
	worker.payroll_paid_from_day = 50
	worker.payroll_paid_until_day = 59
	worker.payroll_period_rate = 6
	worker.payroll_last_attempt_day = 50
	worker.payroll_contract_days = 9
	worker.payroll_paid_start_minute = 50 * 1440 + 600
	WorkerDatabase.workers_by_id[id] = worker
	if linked:
		var citizen := CitizenData.new()
		citizen.citizen_id = id
		citizen.display_name = "Resident " + id
		citizen.profession = WorkerData.Profession.LABORER
		citizen.population_status = CitizenData.PopulationStatus.RESIDENT
		citizen.employment_status = CitizenData.EmploymentStatus.HIRED
		citizen.satisfaction = 0.0
		citizen.food_fulfilled = true
		citizen.clothing_fulfilled = false
		citizen.shelter_fulfilled = true
		CitizenManager.add_citizen(citizen)
	var other := WorkerData.new()
	other.worker_id = "other"
	WorkerDatabase.workers_by_id["other"] = other
	storage.set("units", {
		"cart": {"tool_id": "cart", "name": "Cart", "worker_id": id},
		"glove": {"tool_id": "basic_glove", "name": "Glove", "worker_id": id},
		"free": {"tool_id": "stone_hammer", "name": "Free", "worker_id": ""},
		"other": {"tool_id": "stone_hammer", "name": "Other", "worker_id": "other"},
	})
	CitizenNeedsManager.clothing_allocations[id] = {"item_id": "simple_clothes", "issued_day": 48, "expires_day": 54}
	CitizenNeedsManager.last_needs_results[id] = {"day": 50, "satisfaction": 0.0}
	return worker

func _watch(id: String, worker: WorkerData) -> void:
	watched_id = id
	watched_worker = worker
	storage.connect("changed", _on_storage_changed)
	WorkerDatabase.payroll_changed.connect(_on_payroll_changed)
	CitizenManager.citizen_added.connect(_on_citizen_added)

func _unwatch() -> void:
	storage.disconnect("changed", _on_storage_changed)
	WorkerDatabase.payroll_changed.disconnect(_on_payroll_changed)
	CitizenManager.citizen_added.disconnect(_on_citizen_added)

func _on_storage_changed() -> void:
	storage_callbacks += 1
	_expect_committed_state()

func _on_payroll_changed() -> void:
	payroll_callbacks += 1
	_expect_committed_state()

func _on_citizen_added(citizen: CitizenData) -> void:
	citizen_callbacks += 1
	_expect(citizen == CitizenManager.get_citizen(watched_id), "The added citizen is the committed linked identity.")
	_expect_committed_state()

func _expect_committed_state() -> void:
	var citizen: CitizenData = CitizenManager.get_citizen(watched_id)
	var units: Dictionary = storage.get("units")
	_expect(WorkerDatabase._payroll_settling and bool(storage.get("_transfer_in_progress")),
		"Payroll and storage stay guarded during every notification.")
	_expect(not WorkerDatabase.has_worker_data(watched_id)
		and WorkerDatabase.dismissed_workers.get(watched_id) == watched_worker
		and citizen != null and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and units.cart.worker_id == "" and units.glove.worker_id == ""
		and units.other.worker_id == "other" and Inventory.items.get("shekel", 0) == WALLET,
		"Observers see the complete roster, tools and unchanged wallet together.")
	_expect(not WorkerDatabase.resign_idle_worker(watched_id)
		and not storage.call("allocate", "free", watched_id),
		"Reentrant resignation and equipment allocation cannot enter the transaction.")

func _assert_archived(worker: WorkerData, id: String) -> void:
	_expect(WorkerDatabase.dismissed_workers.get(id) == worker and not WorkerDatabase.has_worker_data(id),
		"The original WorkerData is retained only in the archive.")
	_expect(worker.profession_xp == 17 and worker.profession_star == 2 and worker.wage_shekel_per_day == 7,
		"Resignation preserves earned worker data and wage.")
	_expect(worker.payroll_start_day == -1 and worker.payroll_paid_from_day == -1
		and worker.payroll_paid_until_day == -1 and worker.payroll_period_rate == 0
		and worker.payroll_last_attempt_day == -1 and worker.payroll_contract_days == 0
		and worker.payroll_paid_start_minute == -1,
		"The prepaid period is cleared to the valid legacy sentinel state.")
	_expect(CitizenNeedsManager.clothing_allocations[id].expires_day == 54
		and CitizenNeedsManager.last_needs_results[id].satisfaction == 0.0,
		"Existing clothing and daily-needs history remain attached to the same ID.")
	var state = SAVE_STATE.new()
	var people: Dictionary = {"citizens": {"citizens_by_id": CitizenManager.citizens_by_id},
		"workers": {"workers_by_id": WorkerDatabase.workers_by_id, "dismissed_workers": WorkerDatabase.dismissed_workers},
		"city_storage": {"units": storage.get("units")}}
	_expect(state._validate_people(people), "The archived roster and released tools pass existing save validation.")

func _test_linked_resignation_and_rehire() -> void:
	_reset_fixture()
	var worker: WorkerData = _seed_worker("linked", true)
	var citizen: CitizenData = CitizenManager.get_citizen("linked")
	_watch("linked", worker)
	var resigned: bool = WorkerDatabase.resign_idle_worker("linked")
	_unwatch()
	_expect(resigned and CitizenManager.get_citizen("linked") == citizen,
		"A linked idle worker resigns without replacing the citizen identity.")
	_expect(storage_callbacks == 1 and payroll_callbacks == 1 and citizen_callbacks == 0,
		"Linked resignation emits one storage and payroll update, with no citizen-added event.")
	_expect(not WorkerDatabase._payroll_settling and not bool(storage.get("_transfer_in_progress")),
		"Both transaction guards are released after callbacks.")
	_assert_archived(worker, "linked")
	_expect(not WorkerDatabase.resign_idle_worker("linked") and Inventory.items.get("shekel", 0) == WALLET,
		"Repeating resignation has no effect and gives no refund.")
	_expect(CitizenManager.evaluate_daily_applications() == 0, "A zero-Satisfaction resident cannot reapply.")
	citizen.satisfaction = CitizenData.MIN_APPLICANT_SATISFACTION
	_expect(CitizenManager.evaluate_daily_applications() == 1, "At 50%, the resident can apply normally.")
	var rehired: WorkerData = WorkerDatabase.hire_applicant("linked")
	_expect(rehired == worker and Inventory.items.get("shekel", 0) == WALLET - 2,
		"Rehire uses the retained worker and charges a fresh contract.")
	if rehired != null:
		_expect(rehired.profession_xp == 17 and rehired.payroll_paid_from_day == 50
			and rehired.payroll_paid_until_day == 53 and rehired.payroll_contract_days == 3,
			"The new contract does not reactivate the forfeited period.")

func _test_legacy_resignation_and_generator() -> void:
	_reset_fixture()
	var worker: WorkerData = _seed_worker("citizen_042", false)
	_watch("citizen_042", worker)
	var resigned: bool = WorkerDatabase.resign_idle_worker("citizen_042")
	_unwatch()
	var citizen: CitizenData = CitizenManager.get_citizen("citizen_042")
	_expect(resigned and citizen != null and citizen.population_status == CitizenData.PopulationStatus.RESIDENT
		and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED,
		"An unlinked legacy worker becomes an unemployed resident with the same ID.")
	if citizen != null:
		_expect(citizen.display_name == worker.display_name and citizen.profession == worker.profession
			and citizen.satisfaction == 0.0 and citizen.food_fulfilled and not citizen.clothing_fulfilled and citizen.shelter_fulfilled,
			"The new citizen preserves the legacy identity, profession, Satisfaction and need flags.")
	_expect(citizen_callbacks == 1 and storage_callbacks == 1 and payroll_callbacks == 1,
		"Legacy promotion announces one fully committed citizen and one update per owner.")
	_expect(CitizenGenerator.counter_id == 42 and CitizenGenerator.generate_citizen().citizen_id == "citizen_043",
		"Canonical generated legacy IDs cannot be issued again by the citizen generator.")
	_assert_archived(worker, "citizen_042")
	if citizen != null:
		citizen.satisfaction = 0.499999
		_expect(CitizenManager.evaluate_daily_applications() == 0,
			"The legacy resident remains unemployed below 50%.")
		citizen.satisfaction = CitizenData.MIN_APPLICANT_SATISFACTION
		_expect(CitizenManager.evaluate_daily_applications() == 1,
			"The legacy resident can reapply at the existing 50% threshold.")
		var rehired: WorkerData = WorkerDatabase.hire_applicant(citizen.citizen_id)
		_expect(rehired == worker and Inventory.items.get("shekel", 0) == WALLET - 2,
			"Legacy rehire restores earned worker data and purchases a new contract.")

func _test_daily_idle_resignation_and_recovery() -> void:
	_reset_fixture()
	var worker: WorkerData = _seed_worker("daily", true)
	var citizen: CitizenData = CitizenManager.get_citizen("daily")
	# The unrelated worker from _seed_worker is not part of this scenario.
	WorkerDatabase.workers_by_id.erase("other")
	storage.units.erase("other")
	citizen.satisfaction = 0.05
	# With condition-based Satisfaction, reach zero through an actual 0% target:
	# no food, no current garment allocation, and no shelter for this day.
	CityStockManager.shelter_capacity = 0
	storage.items.clear()
	storage.food_portions.clear()
	CitizenNeedsManager.clothing_allocations.clear()
	CitizenNeedsManager.last_processed_day = 49
	CitizenNeedsManager.last_food_processed_day = 49
	CitizenNeedsManager.last_clothing_processed_day = 49
	CitizenNeedsManager._processing_daily_needs = false
	CitizenNeedsManager._processing_food = false
	CitizenNeedsManager._processing_clothing = false
	CitizenNeedsManager.process_daily_needs()
	_expect(citizen.satisfaction == 0.0 and not citizen.food_fulfilled
		and not citizen.clothing_fulfilled and not citizen.shelter_fulfilled
		and not WorkerDatabase.has_worker_data("daily")
		and CitizenManager.get_citizen("daily") == citizen
		and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED,
		"The daily shortage resigns an idle worker exactly when Satisfaction reaches zero.")
	_expect(WorkerDatabase.dismissed_workers.get("daily") == worker
		and storage.units.cart.worker_id == "" and storage.units.glove.worker_id == ""
		and Inventory.items.get("shekel", 0) == WALLET,
		"Daily resignation retains history, returns tools and gives no contract refund.")
	CitizenNeedsManager.process_daily_needs()
	_expect(citizen.satisfaction == 0.0 and WorkerDatabase.dismissed_workers.get("daily") == worker,
		"Repeating the same daily callback does not repeat or undo the resignation.")
	storage.items = {"barley_bread": 10, "simple_clothes": 2}
	CityStockManager.shelter_capacity = 1
	for day: int in range(51, 61):
		TimeComponentManager.current_day = day
		CitizenNeedsManager.process_daily_needs()
		if day < 60:
			_expect(citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED,
				"An idle resignee does not reapply before 50% Satisfaction.")
	_expect(citizen.satisfaction >= 0.5 and citizen.employment_status == CitizenData.EmploymentStatus.APPLICANT,
		"Ten fully supplied days return the former worker to the normal Job Board at 50%.")
	_expect(WorkerDatabase.hire_applicant("daily") == worker and Inventory.items.get("shekel", 0) == WALLET - 2,
		"The recovered worker requires and receives a newly paid contract.")


func _test_deferred_and_reentrant_sweep() -> void:
	_reset_fixture()
	var worker: WorkerData = _seed_worker("locked", true)
	storage.set("_transfer_in_progress", true)
	WorkerDatabase.resign_idle_workers_at_zero()
	_expect(WorkerDatabase.get_worker_data("locked") == worker,
		"A locked storage transaction retains ownership until the safe retry.")
	# A lock retained across frames must not recursively fill Godot's deferred
	# call queue. Keep it held through several real frame notifications.
	for _frame: int in range(3):
		await get_tree().process_frame
	_expect(WorkerDatabase.get_worker_data("locked") == worker,
		"A multi-frame lock does not remove the worker or spin deferred retries.")
	storage.set("_transfer_in_progress", false)
	for _frame: int in range(3):
		await get_tree().process_frame
	_expect(not WorkerDatabase.has_worker_data("locked") and WorkerDatabase.dismissed_workers.get("locked") == worker,
		"The deferred retry resigns the worker after the storage transaction.")

	_reset_fixture()
	var first: WorkerData = _seed_worker("first", true)
	var other: WorkerData = WorkerDatabase.get_worker_data("other")
	var other_citizen := CitizenData.new()
	other_citizen.citizen_id = "other"
	other_citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	other_citizen.employment_status = CitizenData.EmploymentStatus.HIRED
	other_citizen.satisfaction = 0.1
	CitizenManager.add_citizen(other_citizen)
	# Visit 'other' first, then make it reach zero during the first resignation.
	WorkerDatabase.workers_by_id.erase("first")
	WorkerDatabase.workers_by_id["first"] = first
	var reenter := func() -> void:
		if not WorkerDatabase.has_worker_data("first") and WorkerDatabase.has_worker_data("other"):
			other_citizen.satisfaction = 0.0
			WorkerDatabase.resign_idle_workers_at_zero()
	WorkerDatabase.payroll_changed.connect(reenter)
	WorkerDatabase.resign_idle_workers_at_zero()
	await get_tree().process_frame
	WorkerDatabase.payroll_changed.disconnect(reenter)
	_expect(WorkerDatabase.dismissed_workers.get("first") == first
		and WorkerDatabase.dismissed_workers.get("other") == other,
		"A reentrant zero-Satisfaction update is retried after the active sweep.")


func _test_rejections_leave_state_unchanged() -> void:
	_reset_fixture()
	var worker: WorkerData = _seed_worker("blocked", true)
	var citizen: CitizenData = CitizenManager.get_citizen("blocked")
	var original_units: Dictionary = storage.get("units").duplicate(true)
	citizen.satisfaction = 0.01
	_expect(not WorkerDatabase.resign_idle_worker("blocked"), "A worker above zero does not resign.")
	citizen.satisfaction = 0.0
	storage.set("_transfer_in_progress", true)
	_expect(not WorkerDatabase.resign_idle_worker("blocked"), "Locked storage refuses resignation.")
	storage.set("_transfer_in_progress", false)
	WorkerDatabase._payroll_settling = true
	_expect(not WorkerDatabase.resign_idle_worker("blocked"), "An existing payroll transaction refuses resignation.")
	WorkerDatabase._payroll_settling = false
	citizen.employment_status = CitizenData.EmploymentStatus.ASSIGNED
	_expect(not WorkerDatabase.resign_idle_worker("blocked"), "An assigned citizen cannot use the idle helper.")
	citizen.employment_status = CitizenData.EmploymentStatus.HIRED
	worker.current_work_status = WorkerData.WorkStatus.TRAVELLING
	_expect(not WorkerDatabase.resign_idle_worker("blocked"), "A travelling worker cannot use the idle helper.")
	worker.current_work_status = WorkerData.WorkStatus.IDLE
	worker.current_order_id = "reserved"
	_expect(not WorkerDatabase.resign_idle_worker("blocked"), "A reserved worker cannot use the idle helper.")
	worker.current_order_id = ""
	worker.current_job_id = "unfinished"
	_expect(not WorkerDatabase.resign_idle_worker("blocked"), "An unfinished worker job cannot use the idle helper.")
	worker.current_job_id = ""
	var order := WorkOrder.new()
	order.worker_id = worker.worker_id
	WorkManager.active_orders["active"] = order
	_expect(not WorkerDatabase.resign_idle_worker("blocked"), "A worker with a live work order cannot use the idle helper.")
	WorkManager.active_orders.erase("active")
	var workshop: WorkShop = WORKSHOP_SCENE.instantiate() as WorkShop
	add_child(workshop)
	workshop.assigned_worker_ids.append("blocked")
	_expect(not WorkerDatabase.resign_idle_worker("blocked"), "A live workshop selection cannot use the idle helper.")
	remove_child(workshop)
	workshop.free()
	_expect(WorkerDatabase.get_worker_data("blocked") == worker and not WorkerDatabase.dismissed_workers.has("blocked")
		and citizen.employment_status == CitizenData.EmploymentStatus.HIRED
		and storage.get("units") == original_units and worker.payroll_paid_until_day == 59
		and Inventory.items.get("shekel", 0) == WALLET,
		"All rejected attempts leave roster, identity, tools, contract and wallet untouched.")

func _test_pending_immigrant_collision() -> void:
	_reset_fixture()
	var worker: WorkerData = _seed_worker("citizen_042", false)
	var pending := CitizenData.new()
	pending.citizen_id = "citizen_042"
	ImmigrationManager.pending_immigrants.append(pending)
	var original_units: Dictionary = storage.get("units").duplicate(true)
	_expect(not WorkerDatabase.resign_idle_worker("citizen_042")
		and WorkerDatabase.get_worker_data("citizen_042") == worker
		and CitizenManager.get_citizen("citizen_042") == null
		and CitizenGenerator.counter_id == 3 and storage.get("units") == original_units
		and Inventory.items.get("shekel", 0) == WALLET,
		"A pending immigrant with the same ID blocks promotion without merging or mutation.")

func _test_legacy_workshop_assignment() -> void:
	_reset_fixture()
	var worker: WorkerData = _seed_worker("legacy_selected", false)
	var original_units: Dictionary = storage.get("units").duplicate(true)
	var workshop: WorkShop = WORKSHOP_SCENE.instantiate() as WorkShop
	add_child(workshop)
	workshop.assigned_worker_ids.append(worker.worker_id)
	_expect(not WorkerDatabase.resign_idle_worker(worker.worker_id)
		and WorkerDatabase.get_worker_data(worker.worker_id) == worker
		and CitizenManager.get_citizen(worker.worker_id) == null
		and storage.get("units") == original_units,
		"An unlinked legacy worker in a live workshop selection is not considered idle.")
	remove_child(workshop)
	workshop.free()
