extends Node

const STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const SAVE_STATE: Script = preload("res://scenes/new_scenes/save_game/city_save_state.gd")

var failures: int = 0
var storage: Node
var leave_ids: Array[String] = []
var added_ids: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	storage = WorkStateRuntime.get_node_or_null("CityToolStorage")
	if storage == null:
		storage = STORAGE_SCRIPT.new()
		storage.name = "CityToolStorage"
		WorkStateRuntime.add_child(storage)
	_reset_fixture()
	_test_linked_pending_departure_survives_recovery()
	_test_legacy_zero_worker_promotes_then_leaves()
	_test_nonzero_voluntary_dismissal_stays_resident()
	print("ZeroSatisfactionDepartureTest: %s (%d checks failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _reset_fixture() -> void:
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	WorkerDatabase._payroll_settling = false
	WorkerDatabase._idle_resignation_sweep_active = false
	WorkerDatabase._idle_resignation_retry_queued = false
	WorkerDatabase._idle_resignation_retry_after_frame = false
	CitizenManager.citizens_by_id.clear()
	CitizenGenerator.counter_id = 3
	ImmigrationManager.pending_immigrants.clear()
	WorkManager.active_orders.clear()
	storage.set("_transfer_in_progress", false)
	storage.set("units", {})
	leave_ids.clear()
	added_ids.clear()


func _new_worker(id: String, pending: bool, satisfaction: float) -> WorkerData:
	var worker := WorkerData.new()
	worker.worker_id = id
	worker.display_name = "Worker " + id
	worker.profession = WorkerData.Profession.HAULER
	worker.satisfaction = satisfaction
	worker.resignation_pending = pending
	worker.current_work_status = WorkerData.WorkStatus.IDLE
	worker.payroll_start_day = 10
	worker.payroll_paid_from_day = 10
	worker.payroll_paid_until_day = 19
	worker.payroll_period_rate = 3
	worker.payroll_last_attempt_day = 10
	worker.payroll_contract_days = 9
	worker.payroll_paid_start_minute = 10 * 1440 + 480
	WorkerDatabase.workers_by_id[id] = worker
	return worker


func _new_citizen(id: String, satisfaction: float) -> CitizenData:
	var citizen := CitizenData.new()
	citizen.citizen_id = id
	citizen.display_name = "Resident " + id
	citizen.profession = WorkerData.Profession.HAULER
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.HIRED
	citizen.satisfaction = satisfaction
	CitizenManager.citizens_by_id[id] = citizen
	return citizen


func _set_equipment(worker_id: String) -> void:
	storage.set("units", {
		"%s_cart" % worker_id: {"tool_id": "cart", "name": "Cart", "worker_id": worker_id},
		"%s_glove" % worker_id: {"tool_id": "basic_glove", "name": "Glove", "worker_id": worker_id},
	})


func _listen_to_citizen_events() -> Array[Callable]:
	var on_left := func(citizen: CitizenData) -> void:
		leave_ids.append(citizen.citizen_id)
		_expect(not WorkerDatabase.has_worker_data(citizen.citizen_id)
			and WorkerDatabase.dismissed_workers.has(citizen.citizen_id)
			and WorkerDatabase._payroll_settling
			and bool(storage.get("_transfer_in_progress"))
			and not storage.has_equipped(citizen.citizen_id, "cart")
			and not storage.has_equipped(citizen.citizen_id, "basic_glove"),
			"Departure observers see the committed roster and released tools while transaction guards stay raised.")
		# A repeated notification must be refused after the population transition.
		_expect(not CitizenManager.leave_city(citizen.citizen_id), "A left resident cannot depart a second time.")
	var on_added := func(citizen: CitizenData) -> void:
		added_ids.append(citizen.citizen_id)
	CitizenManager.citizen_left.connect(on_left)
	CitizenManager.citizen_added.connect(on_added)
	return [on_left, on_added]


func _stop_listening(callbacks: Array[Callable]) -> void:
	CitizenManager.citizen_left.disconnect(callbacks[0])
	CitizenManager.citizen_added.disconnect(callbacks[1])


func _test_linked_pending_departure_survives_recovery() -> void:
	_reset_fixture()
	var worker := _new_worker("linked_pending", true, 0.05)
	var citizen := _new_citizen(worker.worker_id, 0.8)
	_set_equipment(worker.worker_id)
	var callbacks := _listen_to_citizen_events()
	_expect(WorkerDatabase.resign_idle_worker(worker.worker_id),
		"A latched zero-Satisfaction resignation completes after Satisfaction recovers.")
	_stop_listening(callbacks)
	_expect(citizen.population_status == CitizenData.PopulationStatus.LEFT_CITY
		and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED,
		"The same linked citizen leaves only after its worker is removed from employment.")
	_expect(not WorkerDatabase.has_worker_data(worker.worker_id)
		and WorkerDatabase.dismissed_workers.get(worker.worker_id) == worker
		and not storage.has_equipped(worker.worker_id, "cart")
		and not storage.has_equipped(worker.worker_id, "basic_glove"),
		"The worker is archived and every allocated tool is released before departure.")
	_expect(leave_ids == [worker.worker_id] and added_ids.is_empty(),
		"Linked departure emits exactly one leave event and no replacement-citizen event.")
	_expect(not worker.resignation_pending and _saved_people_validate(),
		"The completed departure is save-valid and does not retain a pending flag.")
	_expect(not WorkerDatabase.resign_idle_worker(worker.worker_id)
		and leave_ids == [worker.worker_id],
		"Repeating resignation cannot emit another departure.")


func _test_legacy_zero_worker_promotes_then_leaves() -> void:
	_reset_fixture()
	var worker := _new_worker("legacy_zero", false, 0.0)
	worker.food_fulfilled = true
	worker.clothing_fulfilled = false
	worker.shelter_fulfilled = true
	_set_equipment(worker.worker_id)
	var callbacks := _listen_to_citizen_events()
	_expect(WorkerDatabase.resign_idle_worker(worker.worker_id),
		"A zero-Satisfaction legacy worker can resign without a linked citizen.")
	_stop_listening(callbacks)
	var citizen: CitizenData = CitizenManager.get_citizen(worker.worker_id)
	_expect(citizen != null and citizen.population_status == CitizenData.PopulationStatus.LEFT_CITY
		and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and citizen.satisfaction == 0.0 and citizen.food_fulfilled
		and not citizen.clothing_fulfilled and citizen.shelter_fulfilled,
		"Legacy promotion preserves identity, Satisfaction and need state before departure.")
	_expect(not WorkerDatabase.has_worker_data(worker.worker_id)
		and WorkerDatabase.dismissed_workers.get(worker.worker_id) == worker
		and not storage.has_equipped(worker.worker_id, "cart")
		and not storage.has_equipped(worker.worker_id, "basic_glove"),
		"The legacy worker is archived and its equipment is released.")
	_expect(leave_ids == [worker.worker_id] and added_ids.is_empty(),
		"The promoted legacy identity emits one leave event without a transient resident-added event.")
	_expect(_saved_people_validate(), "A departed legacy identity passes current save validation.")


func _test_nonzero_voluntary_dismissal_stays_resident() -> void:
	_reset_fixture()
	var worker := _new_worker("voluntary_nonzero", false, 0.6)
	worker.resignation_pending = false
	var citizen := _new_citizen(worker.worker_id, 0.6)
	var callbacks := _listen_to_citizen_events()
	_expect(not WorkerDatabase.resign_idle_worker(worker.worker_id),
		"The zero-Satisfaction resignation helper refuses a nonzero, unlatched worker.")
	_expect(WorkerDatabase.dismiss_worker(worker.worker_id),
		"The existing voluntary dismissal path still accepts a nonzero idle worker.")
	_stop_listening(callbacks)
	_expect(citizen.population_status == CitizenData.PopulationStatus.RESIDENT
		and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and leave_ids.is_empty(),
		"A nonzero voluntary dismissal leaves the citizen in the city.")


func _saved_people_validate() -> bool:
	var state = SAVE_STATE.new()
	return bool(state._validate_people({
		"citizens": {"citizens_by_id": CitizenManager.citizens_by_id},
		"workers": {"workers_by_id": WorkerDatabase.workers_by_id,
			"dismissed_workers": WorkerDatabase.dismissed_workers},
		"city_storage": {"units": storage.get("units")},
	}))
