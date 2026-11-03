extends Node

## Focused runtime test: authored views own independent house states. The
## checkpoint migration and actual player UI are covered by separate fixtures.
const HOUSE: PackedScene = preload("res://scenes/citizen_house_plot/citizen_house_plot.tscn")
const WORKSHOP: PackedScene = preload("res://scenes/workshop_plot/workshop_plot.tscn")
const CONSTRUCTION: Script = preload("res://scenes/workshop_plot/workshop_construction_state.gd")
const HOUSE_COST: Dictionary = {"wood_log": 4, "clay_lump": 8, "reed_bundle": 6}
const WORKSHOP_COST: Dictionary = {"wood_log": 6, "clay_lump": 12, "reed_bundle": 8}
const WORKER_ID: String = "multi_house_runtime_workshop_worker"

var failures: int = 0
var house_a: Node2D
var house_b: Node2D
var workshop: Node2D
var states: Array[Node] = []
var saved_inventory: Dictionary
var saved_workers: Dictionary
var saved_shelter: int
var saved_workshop_capacity: float
var saved_clock: Dictionary


func _ready() -> void:
	_run.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	saved_inventory = Inventory.items.duplicate(true)
	saved_workers = WorkerDatabase.workers_by_id.duplicate()
	saved_shelter = CityStockManager.shelter_capacity
	saved_workshop_capacity = WorkShopStorage.max_load
	saved_clock = {"day": TimeComponentManager.current_day, "hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute, "paused": TimeComponentManager.is_paused,
		"processing": TimeComponentManager.is_processing(), "tree_paused": get_tree().paused}
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 7
	TimeComponentManager.current_minute = 0
	get_tree().paused = false

	house_a = HOUSE.instantiate()
	house_a.plot_id = "multi_house_runtime_a"
	add_child(house_a)
	house_b = HOUSE.instantiate()
	house_b.plot_id = "multi_house_runtime_b"
	add_child(house_b)
	# A view explicitly marked as a workshop stays a workshop even with the old
	# house's ID; a standalone legacy state still recognizes that old order ID.
	workshop = WORKSHOP.instantiate()
	workshop.plot_id = "citizen_house_1"
	add_child(workshop)
	var a: Node = house_a.construction
	var b: Node = house_b.construction
	var w: Node = workshop.construction
	_expect(a != null and b != null and w != null, "All three authored views bind construction owners.")
	if a == null or b == null or w == null:
		_finish()
		return
	states.assign([a, b, w])
	_expect(a != b and a != w and b != w and a.order_id != b.order_id,
		"Different plot IDs have independent owners and work orders.")
	_expect(a.is_citizen_house() and b.is_citizen_house() and not w.is_citizen_house(),
		"The authored subclass, rather than the ID spelling, selects the building kind.")
	_expect(a.get_requirements() == HOUSE_COST and b.get_requirements() == HOUSE_COST
		and a.get_solo_minutes() == 2880 and b.get_solo_minutes() == 2880
		and a._worker_job_label(false) == "Build House" and b._worker_job_label(true) == "Clear House Site",
		"Both houses use the same material, duration and worker-label rules.")
	_expect(w.get_requirements() == WORKSHOP_COST and w.get_solo_minutes() == 4320
		and w._worker_job_label(false) == "Build Workshop",
		"The workshop keeps its original recipe, duration and label.")
	var legacy: Node = CONSTRUCTION.new()
	legacy.order_id = "construction:citizen_house_1"
	_expect(legacy.is_citizen_house() and legacy.get_requirements() == HOUSE_COST,
		"An unbound legacy construction state still recognizes the original house order.")
	legacy.free()

	var other_view := Node2D.new()
	add_child(other_view)
	_expect(not a.bind_plot_view(other_view, true), "A second live view cannot claim an existing plot ID.")
	a.unbind_plot_view(other_view)
	_expect(not a.bind_plot_view(other_view, true), "A non-owner cannot release the live plot binding.")
	other_view.free()
	# The warning from this deliberately duplicated authored identity is expected.
	var duplicate: Node2D = HOUSE.instantiate()
	duplicate.plot_id = house_a.plot_id
	add_child(duplicate)
	_expect(duplicate.construction == null and not duplicate.visible
		and not duplicate.is_in_group("workshop_plots") and duplicate.process_mode == Node.PROCESS_MODE_DISABLED
		and house_a.construction == a and a.is_citizen_house(),
		"A duplicate authored view is disabled without replacing the live house owner.")
	duplicate.free()
	remove_child(house_a)
	_expect(a.is_citizen_house() and not a.changed.is_connected(Callable(house_a, "_sync_construction")),
		"Detaching the city view retains the house kind and disconnects the old projection.")
	var fresh: Node2D = HOUSE.instantiate()
	fresh.plot_id = "multi_house_runtime_a"
	add_child(fresh)
	_expect(fresh.construction == a and a.is_citizen_house(), "A fresh city view reuses its retained house owner.")
	fresh.free()
	add_child(house_a)
	_expect(house_a.construction == a and a.changed.is_connected(Callable(house_a, "_sync_construction")),
		"The same detached view can reattach and observe its retained owner.")
	a.changed.emit()
	await get_tree().process_frame

	_expect(a.phase == "uncleared" and b.phase == "uncleared"
		and a.get_clearing_preview([] as Array[String], true).duration_minutes == 180
		and b.get_clearing_preview([] as Array[String], true).duration_minutes == 180,
		"Both houses start as independently clearable three-hour sites.")
	var clear_a: Dictionary = a.start_clearing([] as Array[String], true)
	_expect(bool(clear_a.get("success", false)) and a.clearing_by_player and b.phase == "uncleared",
		"The player starts clearing the first house without changing the second.")
	_tick(a, 180)
	_expect(a.phase == "empty" and b.phase == "uncleared", "Only the first site finishes clearing.")
	var clear_b: Dictionary = b.start_clearing([] as Array[String], true)
	_expect(bool(clear_b.get("success", false)) and b.clearing_by_player,
		"The player can clear the second house under the same rules.")
	_tick(b, 180)
	_expect(b.phase == "empty", "The second site finishes clearing independently.")
	CityStockManager.shelter_capacity = CityStockManager.MAX_SHELTER_CAPACITY - 6
	Inventory.items.assign({"wood_log": 8, "clay_lump": 16, "reed_bundle": 12})
	var first: Dictionary = a.start_build([] as Array[String], true)
	_expect(bool(first.get("success", false)) and a.player_building and a.work_total_units == 2880
		and b.phase == "empty", "Player construction starts only the selected house.")
	_expect(int(Inventory.items.get("wood_log", 0)) == 4 and int(Inventory.items.get("clay_lump", 0)) == 8
		and int(Inventory.items.get("reed_bundle", 0)) == 6, "The first house consumes its material cost once.")
	_tick(a, 2880)
	_expect(a.phase == "built" and b.phase == "empty"
		and CityStockManager.shelter_capacity == CityStockManager.MAX_SHELTER_CAPACITY - 3,
		"The first house alone adds three shelter places on completion.")
	for _index in range(3):
		a.changed.emit()
		_tick(a, 1)
	_expect(CityStockManager.shelter_capacity == CityStockManager.MAX_SHELTER_CAPACITY - 3,
		"Repeated completion callbacks cannot award the first house twice.")

	var remaining_materials: Dictionary = Inventory.items.duplicate(true)
	CityStockManager.shelter_capacity = CityStockManager.MAX_SHELTER_CAPACITY - 2
	var blocked: Dictionary = b.start_build([] as Array[String], true)
	_expect(not bool(blocked.get("success", true)) and b.phase == "empty" and Inventory.items == remaining_materials,
		"The second house cannot start when all three shelter places will not fit.")
	CityStockManager.shelter_capacity = CityStockManager.MAX_SHELTER_CAPACITY - 3
	var second: Dictionary = b.start_build([] as Array[String], true)
	_expect(bool(second.get("success", false)) and b.player_building and b.work_total_units == 2880,
		"The second house independently starts at the exact capacity threshold.")
	_expect(int(Inventory.items.get("wood_log", 0)) == 0 and int(Inventory.items.get("clay_lump", 0)) == 0
		and int(Inventory.items.get("reed_bundle", 0)) == 0, "The second house consumes its own cost once.")
	CityStockManager.shelter_capacity = CityStockManager.MAX_SHELTER_CAPACITY - 2
	_tick(b, 2880)
	_expect(b.phase == "building" and b._remaining_work_units() == 1
		and CityStockManager.shelter_capacity == CityStockManager.MAX_SHELTER_CAPACITY - 2,
		"A capacity change before completion preserves the last minute and awards nothing.")
	_tick(b, 1)
	_expect(b.phase == "building" and b._remaining_work_units() == 1,
		"Repeated callbacks while capacity is full retain the same remaining work.")
	CityStockManager.shelter_capacity = CityStockManager.MAX_SHELTER_CAPACITY - 3
	_tick(b, 1)
	for _index in range(3):
		b.changed.emit()
		_tick(b, 1)
	_expect(b.phase == "built" and CityStockManager.shelter_capacity == CityStockManager.MAX_SHELTER_CAPACITY
		and not house_a.has_node("BuiltWorkshop") and not house_b.has_node("BuiltWorkshop"),
		"The second house awards three places exactly once and neither creates a workshop.")

	_test_workshop_completion(w)
	_finish()


func _tick(state: Node, elapsed: int) -> void:
	var total: int = state._latest_time + elapsed
	state._on_time_changed(int(total / 1440), int((total % 1440) / 60), total % 60, "clear")


func _test_workshop_completion(state: Node) -> void:
	var worker := WorkerData.new()
	worker.worker_id = WORKER_ID
	worker.profession = WorkerData.Profession.LABORER
	WorkerDatabase.workers_by_id[WORKER_ID] = worker
	state.phase = "empty"
	Inventory.items.assign(WORKSHOP_COST)
	var capacity_before: int = CityStockManager.shelter_capacity
	_expect(not bool(state.start_build([] as Array[String], true).get("success", true)),
		"A workshop does not gain the house-only player building action.")
	var result: Dictionary = state.start_build([WORKER_ID] as Array[String])
	_expect(bool(result.get("success", false)) and worker.current_job_id == "Build Workshop",
		"The same legacy-spelled ID can start a normal workshop with a worker.")
	if not bool(result.get("success", false)):
		return
	worker.physical_approach.position = worker.physical_approach.target
	_expect(worker.mark_physical_arrival(state.order_id + ":building"), "The workshop builder arrives at its plot.")
	# Stage only the final minute; the existing workshop tests exercise its full shift duration.
	state.completes_at = state._latest_time + 1
	_tick(state, 1)
	_expect(state.phase == "built" and workshop.has_node("BuiltWorkshop")
		and CityStockManager.shelter_capacity == capacity_before,
		"Completing the workshop retains production access and never awards house shelter.")


func _finish() -> void:
	for view: Node in [house_a, house_b, workshop]:
		if is_instance_valid(view):
			view.free()
	for state: Node in states:
		if is_instance_valid(state):
			state.free()
	Inventory.items.assign(saved_inventory)
	WorkerDatabase.workers_by_id.assign(saved_workers)
	CityStockManager.shelter_capacity = saved_shelter
	WorkShopStorage.max_load = saved_workshop_capacity
	TimeComponentManager.current_day = int(saved_clock.day)
	TimeComponentManager.current_hour = int(saved_clock.hour)
	TimeComponentManager.current_minute = int(saved_clock.minute)
	TimeComponentManager.is_paused = bool(saved_clock.paused)
	TimeComponentManager.set_process(bool(saved_clock.processing))
	get_tree().paused = bool(saved_clock.tree_paused)
	print("MultiHouseRuntimeTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
