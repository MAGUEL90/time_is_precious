extends Node

const CONSTRUCTION_SCRIPT: Script = preload("res://scenes/workshop_plot/workshop_construction_state.gd")
const CONTENT_SCENE: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const SHIFT_DRIVER = preload("res://scenes/test_scenes/workshop_shift_test_driver.gd")
const REQUIREMENTS: Dictionary = {"wood_log": 6, "clay_lump": 12, "reed_bundle": 8}
const SOLO_MINUTES: int = 4320
const TEST_WORKER_IDS: Array[String] = [
	"construction_fixture_one",
	"construction_fixture_two",
	"construction_fixture_three",
]

var failures: int = 0
var _completed_sections: int = 0
var _saved_inventory: Dictionary = {}
var _saved_workshop_items: Dictionary = {}
var _saved_workshop_capacity: float = 0.0
var _saved_workers: Dictionary = {}
var _saved_dismissed_workers: Dictionary = {}
var _saved_citizens: Dictionary = {}
var _saved_time_paused: bool = false
var _saved_work_manager_error: String = ""
var _saved_construction_state: Node
var _fixture_state: Variant
var _content: Node
var _reentrant_watch: bool = false
var _reentrant_attempted: bool = false
var _reentrant_state: Variant
var _reentrant_worker_ids: Array[String] = []
var _reentrant_result: Dictionary = {}
var _reentrant_state_was_staged: bool = false
var _reentrant_worker_reserved: bool = false
var _reentrant_unassign_result: bool = true
var _reentrant_dismiss_result: bool = true
var _reentrant_inventory_remove_result: bool = true
var _reentrant_time_advanced: bool = true
var _save_busy_reason_during_payment: String = ""
var _change_count: int = 0

func _ready() -> void:
	call_deferred("_run")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.is_paused = true
	if _saved_construction_state != null:
		_expect(false, "Run WorkshopConstructionTest in a fresh session with no prior construction state.")
	else:
		_install_fixture_workers()
		_test_rejections_are_transactional()
		_test_team_durations_and_completion()
		await _test_map_reload_and_built_workshop_access()
	_expect(_completed_sections == 3, "All three construction regression sections must finish.")
	await _restore_globals()
	print("WorkshopConstructionTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _snapshot_globals() -> void:
	_saved_inventory = Inventory.items.duplicate()
	_saved_workshop_items = WorkShopStorage.items.duplicate()
	_saved_workshop_capacity = WorkShopStorage.max_load
	_saved_workers = WorkerDatabase.workers_by_id.duplicate()
	_saved_dismissed_workers = WorkerDatabase.dismissed_workers.duplicate()
	_saved_citizens = CitizenManager.citizens_by_id.duplicate()
	_saved_time_paused = TimeComponentManager.is_paused
	_saved_work_manager_error = WorkManager.last_start_job_error
	_saved_construction_state = WorkStateRuntime.get_node_or_null("MainWorkshopConstruction")

func _install_fixture_workers() -> void:
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	CitizenManager.citizens_by_id.clear()
	for worker_id: String in TEST_WORKER_IDS:
		var citizen := CitizenData.new()
		citizen.citizen_id = worker_id
		citizen.display_name = worker_id
		citizen.population_status = CitizenData.PopulationStatus.RESIDENT
		citizen.employment_status = CitizenData.EmploymentStatus.HIRED
		citizen.profession = WorkerData.Profession.LABORER
		CitizenManager.citizens_by_id[worker_id] = citizen

		var worker := WorkerData.new()
		worker.worker_id = worker_id
		worker.display_name = worker_id
		worker.profession = WorkerData.Profession.LABORER
		WorkerDatabase.workers_by_id[worker_id] = worker

func _set_fixture_materials() -> void:
	Inventory.items.clear()
	Inventory.add_bulk_item(REQUIREMENTS)

func _new_state() -> Node:
	var state: Node = CONSTRUCTION_SCRIPT.new()
	state.phase = "empty" # This fixture isolates construction after clearing.
	add_child(state)
	return state

func _test_rejections_are_transactional() -> void:
	var state: Variant = _new_state()
	_set_fixture_materials()
	var initial_inventory: Dictionary = Inventory.items.duplicate()
	var first_id: String = TEST_WORKER_IDS[0]
	var first_worker: WorkerData = WorkerDatabase.get_worker_data(first_id)
	var first_citizen: CitizenData = CitizenManager.get_citizen(first_id)

	_expect(state.get_worker_options().size() == TEST_WORKER_IDS.size(), "The fixture roster must expose its three test workers.")
	_expect(not bool(state.get_preview([] as Array[String]).can_start), "Construction without a selected worker must be rejected.")
	_expect(not bool(state.start_build([first_id, first_id] as Array[String]).success), "Duplicate worker IDs must be rejected.")
	_expect(not bool(state.start_build(["construction_missing_worker"] as Array[String]).success), "Unknown workers must be rejected.")
	_expect(Inventory.items == initial_inventory, "Invalid worker selections must not consume materials.")
	_expect(first_worker.current_work_status == WorkerData.WorkStatus.IDLE and first_citizen.employment_status == CitizenData.EmploymentStatus.HIRED, "Invalid selections must leave worker and citizen state unchanged.")

	first_worker.start_work("fixture:busy", "fixture_job")
	_expect(not bool(state.start_build([first_id] as Array[String]).success), "A working worker must be rejected.")
	first_worker.finish_work("fixture:busy")
	first_worker.current_work_status = WorkerData.WorkStatus.TRAVELLING
	_expect(not bool(state.start_build([first_id] as Array[String]).success), "A travelling worker must be rejected.")
	first_worker.current_work_status = WorkerData.WorkStatus.IDLE
	first_citizen.employment_status = CitizenData.EmploymentStatus.ASSIGNED
	_expect(not bool(state.start_build([first_id] as Array[String]).success), "A citizen already assigned to a workplace must be rejected.")
	first_citizen.employment_status = CitizenData.EmploymentStatus.HIRED
	_expect(Inventory.items == initial_inventory, "Busy, travelling, and assigned workers must not consume materials.")

	WorkerDatabase.workers_by_id.clear()
	_expect(state.get_worker_options().is_empty(), "An empty worker roster must remain empty in the construction selector.")
	_expect(not bool(state.start_build([first_id] as Array[String]).success), "Construction must reject a worker removed from the roster.")
	_install_fixture_workers()

	Inventory.items.clear()
	var empty_inventory: Dictionary = Inventory.items.duplicate()
	_expect(not bool(state.start_build([first_id] as Array[String]).success), "Missing materials must prevent construction from starting.")
	_expect(Inventory.items == empty_inventory, "Missing materials must not mutate inventory.")
	var available_worker: WorkerData = WorkerDatabase.get_worker_data(first_id)
	var available_citizen: CitizenData = CitizenManager.get_citizen(first_id)
	_expect(not available_worker.is_reserved() and available_citizen.employment_status == CitizenData.EmploymentStatus.HIRED, "Missing materials must not reserve workers or assign linked citizens.")

	_set_fixture_materials()
	Inventory.items["construction_invalid_fixture"] = 1
	var malformed_inventory: Dictionary = Inventory.items.duplicate()
	var denied_payment: Dictionary = state.start_build([first_id] as Array[String])
	_expect(not bool(denied_payment.get("success", false)), "Invalid Inventory state must fail the complete payment preflight.")
	_expect(Inventory.items == malformed_inventory, "Denied bulk payment must leave every Inventory entry untouched.")
	_expect(state.phase == "empty" and not available_worker.is_reserved() and not state.is_transaction_busy(),
		"Denied payment must leave construction empty, release no worker reservation and clear its transaction guard.")
	_expect(available_citizen.employment_status == CitizenData.EmploymentStatus.HIRED, "Denied payment must leave linked citizen employment unchanged.")
	Inventory.items.erase("construction_invalid_fixture")
	state.free()
	_fixture_state = null
	_completed_sections += 1

func _test_team_durations_and_completion() -> void:
	var mudbrick_job: JobData = preload("res://resources/job_data/mudbrick_make.tres")
	for count: int in [1, 2, 3]:
		_install_fixture_workers()
		_set_fixture_materials()
		var state: Variant = _new_state()
		_change_count = 0
		state.changed.connect(_on_state_changed)
		var selected: Array[String] = []
		for index: int in range(count):
			selected.append(TEST_WORKER_IDS[index])
		var before_cost: Dictionary = Inventory.items.duplicate()
		var expected_duration: int = int(ceil(float(SOLO_MINUTES) / float(count)))
		_expect(int(state.get_preview(selected).duration_minutes) == expected_duration, "%d-worker preview must use the approved divided duration." % count)

		if count == 1:
			_reentrant_watch = true
			_reentrant_attempted = false
			_reentrant_result.clear()
			_reentrant_state = state
			_reentrant_worker_ids = selected.duplicate()
			Inventory.items_changed.connect(_attempt_reentrant_start)

		var result: Dictionary = state.start_build(selected)
		if count == 1:
			Inventory.items_changed.disconnect(_attempt_reentrant_start)
			_reentrant_watch = false
			_expect(_reentrant_attempted and not bool(_reentrant_result.get("success", false)), "A reentrant start during inventory mutation must be rejected.")
			_expect(_reentrant_state_was_staged and _reentrant_worker_reserved,
				"Inventory observers must see the complete building state and reserved worker before payment notification.")
			_expect(not _reentrant_unassign_result and not _reentrant_dismiss_result,
				"Worker assignment and dismissal changes must be rejected while construction payment is publishing.")
			_expect(not _reentrant_inventory_remove_result and not _reentrant_time_advanced,
				"Inventory mutation and clock advancement must be rejected during the bulk payment callback.")
		_expect(bool(result.success), "%d-worker construction must start." % count)
		_expect(state.phase == "building" and state.worker_ids == selected, "Construction must lock the selected team in building phase.")
		_expect(state.completes_at - state.started_at == expected_duration, "Construction deadline must match the previewed duration.")
		_expect(Inventory.items == _inventory_after_cost(before_cost), "Starting construction must consume each required item exactly once.")
		for worker_id: String in selected:
			var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
			var citizen: CitizenData = CitizenManager.get_citizen(worker_id)
			_expect(worker.current_order_id == "construction:main_workshop" and worker.is_reserved(), "Construction must reserve each selected worker.")
			_expect(citizen.employment_status == CitizenData.EmploymentStatus.ASSIGNED, "Construction must assign each linked citizen.")

		var after_start: Dictionary = Inventory.items.duplicate()
		_expect(not bool(state.start_build(selected).success), "A second start after construction begins must be rejected.")
		_expect(Inventory.items == after_start, "A repeated start must not consume a second material batch.")
		if count == 1:
			var selected_worker_id: String = selected[0]
			_expect(not WorkerDatabase.dismiss_worker(selected_worker_id), "WorkerDatabase must refuse dismissal while construction reserves a worker.")
			_expect(WorkManager._resolve_worker_id(WorkOrder.Worker_Type.NPC, selected_worker_id, mudbrick_job).is_empty(), "WorkManager must not admit a construction worker into another job.")
			var other_id: String = TEST_WORKER_IDS[1]
			_expect(not bool(state.start_build([other_id] as Array[String]).success), "The selected team must remain locked during construction.")
			_expect(Inventory.items == after_start, "A team-change attempt must not consume additional materials.")

			var start_time: int = state.started_at
			_advance_worker_minutes(state, expected_duration - 1)
			_expect(state.phase == "building", "Construction must not complete one minute early.")
			_expect(int(state.get_preview([] as Array[String]).remaining_minutes) == 1, "One minute before completion must report exactly one minute remaining.")
			var changes_before_finish: int = _change_count
			_advance_worker_minutes(state, 1)
			_expect(state.phase == "built", "Construction must complete at its exact deadline.")
			_expect(_change_count == changes_before_finish + 1, "The completion transition must emit one state change.")
			_expect(not WorkerDatabase.get_worker_data(selected_worker_id).is_reserved(), "Completion must release the worker reservation.")
			_expect(CitizenManager.get_citizen(selected_worker_id).employment_status == CitizenData.EmploymentStatus.HIRED, "Completion must restore the linked citizen to hired status.")
			var changes_after_finish: int = _change_count
			_advance_state_to(state, state.completes_at)
			_advance_state_to(state, start_time)
			_expect(state.phase == "built" and _change_count == changes_after_finish, "Repeated and backwards timestamps must not repeat completion effects.")
		else:
			state.free()
			for worker_id: String in selected:
				_expect(not WorkerDatabase.get_worker_data(worker_id).is_reserved(), "Test teardown must release a still-building worker.")
				_expect(CitizenManager.get_citizen(worker_id).employment_status == CitizenData.EmploymentStatus.HIRED, "Test teardown must restore linked citizen assignment.")
		if count == 1:
			state.free()
		_fixture_state = null
	_completed_sections += 1

func _test_map_reload_and_built_workshop_access() -> void:
	_install_fixture_workers()
	_set_fixture_materials()
	_content = CONTENT_SCENE.instantiate()
	add_child(_content)
	await get_tree().process_frame
	await get_tree().process_frame
	var plot = _content.get_node_or_null("YSortWorld/WorkshopPlot")
	_fixture_state = WorkStateRuntime.get_node_or_null("MainWorkshopConstruction")
	_expect(plot != null and _fixture_state != null, "The real content map must create its runtime construction state.")
	if plot == null or _fixture_state == null:
		await _free_content()
		return
	_expect(plot.construction == _fixture_state, "The real plot must use the WorkStateRuntime construction node.")
	var visuals: Node2D = _content.get_node("YSortWorld/WorkerRuntime/WorkerVisuals")
	visuals.set_process(false)
	var selected: Array[String] = [TEST_WORKER_IDS[0], TEST_WORKER_IDS[1]]
	var clearing: Dictionary = _fixture_state.start_clearing([TEST_WORKER_IDS[0]] as Array[String], false)
	_expect(bool(clearing.success), "The real plot must start clearing with its fixture worker.")
	if not bool(clearing.success):
		await _free_content()
		return
	var clearing_worker: WorkerData = WorkerDatabase.get_worker_data(TEST_WORKER_IDS[0])
	_expect(clearing_worker.matches_physical_approach("plot", _fixture_state.order_id + ":clearing", _fixture_state.order_id)
		and not clearing_worker.physical_approach.arrived, "Clearing starts with a pending physical route to the plot.")
	_drive_plot_arrivals(visuals, [TEST_WORKER_IDS[0]] as Array[String], "clearing", _fixture_state.order_id)
	_advance_worker_minutes(_fixture_state, _fixture_state.CLEARING_MINUTES, visuals)
	_expect(_fixture_state.phase == "empty" and not clearing_worker.is_reserved(),
		"Arrived clearing finishes and releases its worker before construction.")
	_save_busy_reason_during_payment = ""
	var was_clock_paused: bool = TimeComponentManager.is_paused
	TimeComponentManager.is_paused = false
	Inventory.items_changed.connect(_observe_save_busy_during_payment)
	var result: Dictionary = _fixture_state.start_build(selected)
	if Inventory.items_changed.is_connected(_observe_save_busy_during_payment):
		Inventory.items_changed.disconnect(_observe_save_busy_during_payment)
	TimeComponentManager.is_paused = was_clock_paused
	_expect(_save_busy_reason_during_payment.begins_with("Wait for the current transaction"),
		"A save snapshot must refuse reentry while construction payment is publishing.")
	_expect(bool(result.success), "The real plot's runtime state must accept the fixture construction team.")
	if not bool(result.success):
		await _free_content()
		return
	var second_worker: WorkerData = WorkerDatabase.get_worker_data(TEST_WORKER_IDS[1])
	_expect(second_worker.matches_physical_approach("plot", _fixture_state.order_id + ":building", _fixture_state.order_id)
		and not second_worker.physical_approach.arrived,
		"The newly assigned second builder must travel to the plot before contributing.")
	_drive_plot_arrivals(visuals, selected, "building", _fixture_state.order_id)
	_advance_worker_minutes(_fixture_state, 900, visuals)
	var retained_state: Variant = _fixture_state
	var retained_remaining: int = int(_fixture_state.get_preview([] as Array[String]).remaining_minutes)
	var retained_progress: float = float(_fixture_state.get_preview([] as Array[String]).progress_ratio)
	await _free_content()
	_expect(is_instance_valid(retained_state) and WorkStateRuntime.get_node_or_null("MainWorkshopConstruction") == retained_state, "Removing the content map must preserve construction state under WorkStateRuntime.")
	_expect(int(retained_state.get_preview([] as Array[String]).remaining_minutes) == retained_remaining, "Removing the map must preserve construction time remaining.")

	_content = CONTENT_SCENE.instantiate()
	add_child(_content)
	await get_tree().process_frame
	await get_tree().process_frame
	var reloaded_plot = _content.get_node_or_null("YSortWorld/WorkshopPlot")
	_expect(reloaded_plot != null and reloaded_plot.construction == retained_state, "Recreating the map must reuse the same construction state node.")
	if reloaded_plot == null:
		await _free_content()
		return
	_expect(is_equal_approx(float(reloaded_plot.construction.get_preview([] as Array[String]).progress_ratio), retained_progress), "Recreated plot must show the same construction progress.")
	_expect(str(reloaded_plot.get_node("Label").text).begins_with("Building"), "Recreated plot must render its in-progress state.")
	var reloaded_visuals: Node2D = _content.get_node("YSortWorld/WorkerRuntime/WorkerVisuals")
	reloaded_visuals.set_process(false)
	_advance_worker_minutes(retained_state, int(retained_state.get_preview([] as Array[String]).remaining_minutes), reloaded_visuals)
	await get_tree().process_frame
	var built_workshop: WorkShop = reloaded_plot.get_node_or_null("BuiltWorkshop") as WorkShop
	_expect(retained_state.phase == "built" and built_workshop != null, "Completion on the real map must spawn the existing Workshop scene as BuiltWorkshop.")
	if built_workshop != null:
		var player: Player = _content.get_node("YSortWorld/Player") as Player
		player.global_position = reloaded_plot.get_node("InteractableComponent").global_position + Vector2(0, 4)
		player.nearby_interactables.clear()
		player._on_interactable_activated(built_workshop)
		_expect(player.current_interactable == built_workshop, "The built Workshop must be selectable by the real Player interaction path.")
		await _press("interact")
		_expect(player.claim_menu_is_open and player.claim_menu_workshop == built_workshop, "Pressing E on the built Workshop must open its existing workshop menu.")
		var menu: Node = find_child("WorkshopMenuUI", true, false)
		if is_instance_valid(menu):
			menu.call("_on_close_button_pressed")
			await get_tree().process_frame
	_fixture_state = retained_state
	await _free_content()
	_completed_sections += 1

func _inventory_after_cost(before: Dictionary) -> Dictionary:
	var expected: Dictionary = before.duplicate()
	for item_id: String in REQUIREMENTS:
		var remaining: int = int(expected.get(item_id, 0)) - int(REQUIREMENTS[item_id])
		if remaining > 0:
			expected[item_id] = remaining
		else:
			expected.erase(item_id)
	return expected

func _advance_state_to(state: Variant, total_minutes: int) -> void:
	var day: int = int(total_minutes / 1440)
	var within_day: int = total_minutes % 1440
	state.call("_on_time_changed", day, int(within_day / 60), within_day % 60, "clear")

func _advance_worker_minutes(state: Variant, amount: int, visuals: Node2D = null) -> void:
	while amount > 0 and state.phase in ["building", "clearing"]:
		var now: int = state._latest_time
		var minute: int = now % 1440
		if minute < state.SHIFT_START or minute >= state.SHIFT_END:
			var next_start: int = now - minute + state.SHIFT_START + (1440 if minute >= state.SHIFT_END else 0)
			_set_clock_for_fixture(next_start)
			_advance_state_to(state, next_start)
			if visuals != null:
				_drive_plot_arrivals(visuals, state.worker_ids, state.phase, state.order_id)
			continue
		var step: int = mini(amount, state.SHIFT_END - minute)
		_set_clock_for_fixture(now + step)
		_advance_state_to(state, now + step)
		amount -= step

func _set_clock_for_fixture(total_minutes: int) -> void:
	TimeComponentManager.current_day = int(total_minutes / 1440)
	TimeComponentManager.current_hour = int((total_minutes % 1440) / 60)
	TimeComponentManager.current_minute = total_minutes % 60

func _drive_plot_arrivals(visuals: Node2D, worker_ids: Array[String], phase: String, order_id: String) -> void:
	var was_paused: bool = TimeComponentManager.is_paused
	TimeComponentManager.is_paused = false
	var task_key: String = order_id + ":" + phase
	for _frame: int in range(4000):
		var all_arrived: bool = true
		for worker_id: String in worker_ids:
			var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
			if worker == null or not worker.matches_physical_approach("plot", task_key, order_id) or not worker.physical_approach.get("arrived", false):
				all_arrived = false
				break
		if all_arrived:
			break
		SHIFT_DRIVER.visual_frame(visuals, 0.1)
	TimeComponentManager.is_paused = was_paused
	for worker_id: String in worker_ids:
		var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
		_expect(worker != null and worker.matches_physical_approach("plot", task_key, order_id)
			and worker.physical_approach.get("arrived", false),
			"Builder " + worker_id + " physically reaches the plot before " + phase + " time counts.")

func _attempt_reentrant_start() -> void:
	if not _reentrant_watch or _reentrant_attempted:
		return
	_reentrant_attempted = true
	_reentrant_state_was_staged = _reentrant_state.phase == "building" and _reentrant_state.worker_ids == _reentrant_worker_ids
	var worker: WorkerData = WorkerDatabase.get_worker_data(_reentrant_worker_ids[0]) if not _reentrant_worker_ids.is_empty() else null
	_reentrant_worker_reserved = worker != null and worker.is_reserved()
	if worker != null:
		_reentrant_unassign_result = WorkerDatabase.unassign_worker(worker.worker_id)
		_reentrant_dismiss_result = WorkerDatabase.dismiss_worker(worker.worker_id)
	_reentrant_inventory_remove_result = Inventory.remove_item("wood_log", 1)
	_reentrant_time_advanced = TimeComponentManager.advance_one_minute()
	_reentrant_result = _reentrant_state.call("start_build", _reentrant_worker_ids)


func _observe_save_busy_during_payment() -> void:
	if is_instance_valid(_content):
		var city_save: Node = WorkStateRuntime.get_node_or_null("CitySave")
		if city_save != null:
			var snapshot: Variant = city_save.get("snapshot")
			if snapshot != null:
				_save_busy_reason_during_payment = str(snapshot.call("busy_reason", _content))

func _on_state_changed() -> void:
	_change_count += 1

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	get_viewport().push_input(event)
	await get_tree().process_frame

func _free_content() -> void:
	if is_instance_valid(_content):
		_content.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	_content = null

func _restore_globals() -> void:
	get_tree().paused = false
	if is_instance_valid(_content):
		await _free_content()
	if is_instance_valid(_fixture_state) and _fixture_state != _saved_construction_state:
		_fixture_state.free()
	_fixture_state = null
	Inventory.items.clear()
	for item_id: String in _saved_inventory:
		Inventory.items[item_id] = int(_saved_inventory[item_id])
	WorkShopStorage.items.clear()
	for item_id: String in _saved_workshop_items:
		WorkShopStorage.items[item_id] = int(_saved_workshop_items[item_id])
	WorkShopStorage.max_load = _saved_workshop_capacity
	WorkerDatabase.workers_by_id.clear()
	for worker_id: String in _saved_workers:
		WorkerDatabase.workers_by_id[worker_id] = _saved_workers[worker_id]
	WorkerDatabase.dismissed_workers.clear()
	for worker_id: String in _saved_dismissed_workers:
		WorkerDatabase.dismissed_workers[worker_id] = _saved_dismissed_workers[worker_id]
	CitizenManager.citizens_by_id.clear()
	for citizen_id: String in _saved_citizens:
		CitizenManager.citizens_by_id[citizen_id] = _saved_citizens[citizen_id]
	WorkManager.last_start_job_error = _saved_work_manager_error
	TimeComponentManager.is_paused = _saved_time_paused
