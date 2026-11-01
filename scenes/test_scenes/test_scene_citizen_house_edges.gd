extends Node

## Isolated construction-owner edge cases. Run with an isolated XDG_DATA_HOME.
## The full map and physical commute have separate integration coverage.
const CONSTRUCTION: Script = preload("res://scenes/workshop_plot/workshop_construction_state.gd")
const SAVE_STATE: Script = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const HOUSE_ORDER: String = "construction:citizen_house_1"
const HOUSE_COST: Dictionary = {"wood_log": 4, "clay_lump": 8, "reed_bundle": 6}
const HOUSE_WORK: int = 2880
const SHIFT_START: int = 7 * 60

class PlotFixture extends Node:
	var construction: Node

var failures: int = 0
var worker_ids: Array[String] = []
var saved_inventory: Dictionary = {}
var saved_workers: Dictionary = {}
var saved_dismissed: Dictionary = {}
var saved_citizens: Dictionary = {}
var saved_shelter: int = 0
var saved_clock: Dictionary = {}
var live_states: Array[Node] = []
var inventory_callback_armed: bool = false
var inventory_callback_count: int = 0
var inventory_callback_clock_advanced: bool = false
var completion_state: Node
var completion_notifications: int = 0
var completion_capacity: int = -1
var completion_clock_advanced: bool = false


func _ready() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	_snapshot()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_install_paid_workers()
	_test_seven_worker_rounding()
	_test_start_capacity_limits()
	_test_capacity_change_during_start()
	_test_capacity_change_before_completion()
	_restore()
	print("CitizenHouseEdgesTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _snapshot() -> void:
	saved_inventory = Inventory.items.duplicate(true)
	saved_workers = WorkerDatabase.workers_by_id.duplicate()
	saved_dismissed = WorkerDatabase.dismissed_workers.duplicate()
	saved_citizens = CitizenManager.citizens_by_id.duplicate()
	saved_shelter = CityStockManager.shelter_capacity
	saved_clock = {"day": TimeComponentManager.current_day, "hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute, "weather": TimeComponentManager.current_weather,
		"paused": TimeComponentManager.is_paused, "processing": TimeComponentManager.is_processing(),
		"tree_paused": get_tree().paused}


func _restore() -> void:
	if Inventory.items_changed.is_connected(_on_inventory_changed):
		Inventory.items_changed.disconnect(_on_inventory_changed)
	for state: Node in live_states:
		if is_instance_valid(state):
			state.free()
	live_states.clear()
	Inventory.items.assign(saved_inventory)
	WorkerDatabase.workers_by_id.assign(saved_workers)
	WorkerDatabase.dismissed_workers.assign(saved_dismissed)
	CitizenManager.citizens_by_id.assign(saved_citizens)
	CityStockManager.shelter_capacity = saved_shelter
	TimeComponentManager.current_day = int(saved_clock.day)
	TimeComponentManager.current_hour = int(saved_clock.hour)
	TimeComponentManager.current_minute = int(saved_clock.minute)
	TimeComponentManager.current_weather = str(saved_clock.weather)
	TimeComponentManager.is_paused = bool(saved_clock.paused)
	TimeComponentManager.set_process(bool(saved_clock.processing))
	get_tree().paused = bool(saved_clock.tree_paused)


func _install_paid_workers() -> void:
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	CitizenManager.citizens_by_id.clear()
	worker_ids.clear()
	for index: int in range(7):
		var id: String = "house_edges_%d" % index
		worker_ids.append(id)
		var citizen := CitizenData.new()
		citizen.citizen_id = id
		citizen.display_name = id
		citizen.population_status = CitizenData.PopulationStatus.RESIDENT
		citizen.employment_status = CitizenData.EmploymentStatus.HIRED
		citizen.profession = WorkerData.Profession.LABORER
		citizen.satisfaction = 0.8
		CitizenManager.citizens_by_id[id] = citizen
		var worker := WorkerData.new()
		worker.worker_id = id
		worker.display_name = id
		worker.profession = WorkerData.Profession.LABORER
		worker.payroll_start_day = 0
		worker.payroll_paid_from_day = 0
		worker.payroll_paid_until_day = 8
		worker.payroll_contract_days = 9
		worker.payroll_paid_start_minute = SHIFT_START
		WorkerDatabase.workers_by_id[id] = worker


func _set_clock(total: int) -> void:
	TimeComponentManager.current_day = total / 1440
	TimeComponentManager.current_hour = (total % 1440) / 60
	TimeComponentManager.current_minute = total % 60
	TimeComponentManager.current_weather = "clear"


func _tick(state: Node, total: int) -> void:
	_set_clock(total)
	state.call("_on_time_changed", TimeComponentManager.current_day,
		TimeComponentManager.current_hour, TimeComponentManager.current_minute, "clear")


func _new_state() -> Node:
	_set_clock(SHIFT_START)
	var state: Node = CONSTRUCTION.new()
	state.name = "HouseEdgesConstruction"
	state.set("order_id", HOUSE_ORDER)
	state.set("phase", "empty")
	WorkStateRuntime.add_child(state)
	live_states.append(state)
	return state


func _dispose_state(state: Node) -> void:
	live_states.erase(state)
	state.free()


func _set_materials() -> void:
	Inventory.items.clear()
	Inventory.items["wood_log"] = 9
	Inventory.items["clay_lump"] = 13
	Inventory.items["reed_bundle"] = 11
	Inventory.items["shekel"] = 4


func _after_cost(before: Dictionary) -> Dictionary:
	var result: Dictionary = before.duplicate(true)
	for id: String in HOUSE_COST:
		result[id] = int(result[id]) - int(HOUSE_COST[id])
	return result


func _expect_team_idle() -> void:
	for id: String in worker_ids:
		var worker: WorkerData = WorkerDatabase.get_worker_data(id)
		var citizen: CitizenData = CitizenManager.get_citizen(id)
		_expect(worker != null and not worker.is_reserved() and worker.current_job_id.is_empty()
			and citizen != null and citizen.employment_status == CitizenData.EmploymentStatus.HIRED,
			"No failed/completed transaction may leave worker %s assigned." % id)


func _validate_work_snapshot(state: Node, label: String) -> void:
	# Only the plot/work portion is staged here; this uses the production validator
	# and catches invalid team remainder, remaining work, or worker job labels.
	var plot := PlotFixture.new()
	plot.construction = state
	add_child(plot)
	plot.add_to_group("workshop_plots")
	var snapshot: Variant = SAVE_STATE.new()
	var raw: Dictionary = {
		"plots": {str(state.name): snapshot.fields(state, snapshot.PLOT_FIELDS)},
		"workers": {"workers_by_id": WorkerDatabase.workers_by_id, "dismissed_workers": WorkerDatabase.dismissed_workers},
		"work": {"active_orders": {}, "service_fee_by_order": {}, "service_fee_currency_by_order": {}},
		"order_plots": {}, "work_sources": {}, "work_outputs": {},
		"facilities": {"facility_levels": {}}, "process": {"stations": {}}
	}
	var valid: bool = snapshot._validate_work(raw, self, snapshot.VERSION)
	_expect(valid, label + " must pass the real save-work validator: " + str(snapshot.error))
	plot.free()


func _test_seven_worker_rounding() -> void:
	CityStockManager.shelter_capacity = 10
	_set_materials()
	var before: Dictionary = Inventory.items.duplicate(true)
	var state: Variant = _new_state()
	var quote: Dictionary = state.get_preview(worker_ids)
	_expect(bool(quote.get("can_start", false)) and int(quote.get("duration_minutes", 0)) == 412,
		"Seven paid workers quote ceil(2880 / 7) = 412 minutes.")
	var result: Dictionary = state.start_build(worker_ids)
	_expect(bool(result.get("success", false)), "Seven-worker house construction starts.")
	if not bool(result.get("success", false)):
		_dispose_state(state)
		return
	_expect(state.work_total_units == HOUSE_WORK and state._remaining_work_units() == HOUSE_WORK
		and state.payroll_work_remainder == 4 and Inventory.items == _after_cost(before),
		"The seven-worker start retains exactly 2880 work units and consumes the cost once.")
	_validate_work_snapshot(state, "Seven-worker initial state")
	_tick(state, SHIFT_START + 411)
	_expect(state.phase == "building" and state._remaining_work_units() == 3
		and state.payroll_work_remainder == 4 and CityStockManager.shelter_capacity == 10,
		"Seven workers contribute exactly 2877 units in 411 paid minutes.")
	_validate_work_snapshot(state, "Seven-worker fractional final minute")
	# Make four workers still travel. Exactly three remaining workers then
	# contribute the final three units, without relying on a rounded-up total.
	for index: int in range(3, 7):
		var worker: WorkerData = WorkerDatabase.get_worker_data(worker_ids[index])
		worker.begin_physical_approach("plot", HOUSE_ORDER + ":building", HOUSE_ORDER, Vector2(0, 5), Vector2.ZERO)
	_tick(state, SHIFT_START + 412)
	_expect(state.phase == "built" and CityStockManager.shelter_capacity == 13
		and Inventory.items == _after_cost(before),
		"Exactly three final worker-minutes complete the house and add exactly three shelter.")
	_expect_team_idle()
	_dispose_state(state)


func _test_start_capacity_limits() -> void:
	var state: Variant = _new_state()
	for capacity: int in [CityStockManager.MAX_SHELTER_CAPACITY - 2, CityStockManager.MAX_SHELTER_CAPACITY, CityStockManager.MAX_SHELTER_CAPACITY + 17]:
		CityStockManager.shelter_capacity = capacity
		_set_materials()
		var before: Dictionary = Inventory.items.duplicate(true)
		var result: Dictionary = state.start_build([worker_ids[0]] as Array[String])
		_expect(not bool(result.get("success", true)) and state.phase == "empty"
			and CityStockManager.shelter_capacity == capacity and Inventory.items == before,
			"Capacity %d rejects the entire start without loss or clamping." % capacity)
		_expect_team_idle()
	CityStockManager.shelter_capacity = CityStockManager.MAX_SHELTER_CAPACITY - 3
	_set_materials()
	_expect(bool(state.start_build([worker_ids[0]] as Array[String]).get("success", false)),
		"Starting is allowed when exactly three shelter places remain.")
	_dispose_state(state)
	_expect_team_idle()


func _on_inventory_changed() -> void:
	if not inventory_callback_armed:
		return
	inventory_callback_armed = false
	inventory_callback_count += 1
	CityStockManager.shelter_capacity = CityStockManager.MAX_SHELTER_CAPACITY - 2
	inventory_callback_clock_advanced = TimeComponentManager.advance_minutes(1)


func _test_capacity_change_during_start() -> void:
	CityStockManager.shelter_capacity = 0
	_set_materials()
	var before: Dictionary = Inventory.items.duplicate(true)
	var state: Variant = _new_state()
	inventory_callback_count = 0
	inventory_callback_clock_advanced = false
	inventory_callback_armed = true
	Inventory.items_changed.connect(_on_inventory_changed)
	var result: Dictionary = state.start_build([worker_ids[0]] as Array[String])
	Inventory.items_changed.disconnect(_on_inventory_changed)
	inventory_callback_armed = false
	_expect(inventory_callback_count == 1 and not inventory_callback_clock_advanced,
		"The material-removal callback fires once and cannot advance the clock during the transaction.")
	_expect(not bool(result.get("success", true)) and state.phase == "empty" and Inventory.items == before
		and CityStockManager.shelter_capacity == CityStockManager.MAX_SHELTER_CAPACITY - 2,
		"A callback filling shelter aborts the start, refunds every input, and preserves its external change.")
	_expect_team_idle()
	_dispose_state(state)


func _on_completion_changed() -> void:
	if not is_instance_valid(completion_state) or completion_state.get("phase") != "built":
		return
	completion_notifications += 1
	completion_capacity = CityStockManager.shelter_capacity
	completion_clock_advanced = TimeComponentManager.advance_minutes(1)
	completion_state.call("_on_time_changed", TimeComponentManager.current_day,
		TimeComponentManager.current_hour, TimeComponentManager.current_minute, "clear")


func _test_capacity_change_before_completion() -> void:
	CityStockManager.shelter_capacity = 0
	_set_materials()
	var before: Dictionary = Inventory.items.duplicate(true)
	var state: Variant = _new_state()
	var result: Dictionary = state.start_build(worker_ids)
	_expect(bool(result.get("success", false)), "A seven-worker house starts before capacity fills.")
	if not bool(result.get("success", false)):
		_dispose_state(state)
		return
	_tick(state, SHIFT_START + 411)
	_expect(state._remaining_work_units() == 3, "The capacity fixture reaches three remaining worker-minutes.")
	var over_capacity: int = CityStockManager.MAX_SHELTER_CAPACITY + 17
	CityStockManager.shelter_capacity = over_capacity
	_tick(state, SHIFT_START + 412)
	_expect(state.phase == "building" and state._remaining_work_units() == 1
		and bool(state.get_preview([] as Array[String]).get("shelter_blocked", false))
		and CityStockManager.shelter_capacity == over_capacity,
		"An over-cap value is never clamped downward; one unfinished minute and all progress remain.")
	_validate_work_snapshot(state, "Shelter-blocked one-unit state")
	for total: int in [SHIFT_START + 412, SHIFT_START + 413, SHIFT_START + 414]:
		_tick(state, total)
		_expect(state.phase == "building" and state._remaining_work_units() == 1
			and CityStockManager.shelter_capacity == over_capacity,
			"Repeated clock callbacks cannot finish or change an over-cap shelter value.")
	CityStockManager.shelter_capacity = CityStockManager.MAX_SHELTER_CAPACITY - 2
	_tick(state, SHIFT_START + 415)
	_expect(state.phase == "building" and state._remaining_work_units() == 1
		and CityStockManager.shelter_capacity == CityStockManager.MAX_SHELTER_CAPACITY - 2,
		"Two free shelter places cannot trigger a partial three-place grant.")
	# Even once room exists, only an arrived, paid worker may finish the job.
	for id: String in worker_ids:
		var worker: WorkerData = WorkerDatabase.get_worker_data(id)
		worker.begin_physical_approach("plot", HOUSE_ORDER + ":building", HOUSE_ORDER, Vector2(0, 5), Vector2.ZERO)
	CityStockManager.shelter_capacity = CityStockManager.MAX_SHELTER_CAPACITY - 3
	_tick(state, SHIFT_START + 416)
	_expect(state.phase == "building" and state._remaining_work_units() == 1,
		"Capacity becoming available does not replace the required physical arrival.")
	var arrived: WorkerData = WorkerDatabase.get_worker_data(worker_ids[0])
	arrived.physical_approach.position = Vector2.ZERO
	_expect(arrived.mark_physical_arrival(HOUSE_ORDER + ":building"), "The paid replacement physically arrives.")
	completion_state = state
	completion_notifications = 0
	completion_capacity = -1
	completion_clock_advanced = false
	state.changed.connect(_on_completion_changed)
	_tick(state, SHIFT_START + 417)
	_expect(state.phase == "built" and CityStockManager.shelter_capacity == CityStockManager.MAX_SHELTER_CAPACITY
		and completion_notifications == 1 and completion_capacity == CityStockManager.MAX_SHELTER_CAPACITY
		and not completion_clock_advanced and Inventory.items == _after_cost(before),
		"One paid arrived minute grants all three once before notification; reentrant clock advance is blocked.")
	_tick(state, SHIFT_START + 417)
	_tick(state, SHIFT_START + 418)
	_expect(completion_notifications == 1 and CityStockManager.shelter_capacity == CityStockManager.MAX_SHELTER_CAPACITY,
		"Repeated completion-time and later callbacks cannot grant shelter twice.")
	_expect_team_idle()
	completion_state = null
	_dispose_state(state)
