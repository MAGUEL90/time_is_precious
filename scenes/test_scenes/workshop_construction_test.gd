extends Node

const CONSTRUCTION_SCRIPT: Script = preload("res://scenes/workshop_plot/workshop_construction_state.gd")
const CONTENT_SCENE: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
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
var _rollback_watch: bool = false
var _externally_removed_item_id: String = ""
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
	var before_partial_failure: Dictionary = Inventory.items.duplicate()
	_rollback_watch = true
	_externally_removed_item_id = ""
	Inventory.items_changed.connect(_remove_unconsumed_material_during_start)
	var partial_result: Dictionary = state.start_build([first_id] as Array[String])
	if Inventory.items_changed.is_connected(_remove_unconsumed_material_during_start):
		Inventory.items_changed.disconnect(_remove_unconsumed_material_during_start)
	_rollback_watch = false
	var external_change_expected: Dictionary = before_partial_failure.duplicate()
	external_change_expected.erase(_externally_removed_item_id)
	_expect(not bool(partial_result.get("success", false)), "Construction must roll back when an item disappears during multi-item consumption.")
	_expect(not _externally_removed_item_id.is_empty(), "The partial-consumption fixture must remove one still-unconsumed requirement.")
	_expect(Inventory.items == external_change_expected, "Rollback must refund construction-consumed inputs while preserving the external material removal.")
	_expect(state.phase == "empty" and not available_worker.is_reserved(), "Failed partial consumption must leave construction empty and release its builder.")
	_expect(available_citizen.employment_status == CitizenData.EmploymentStatus.HIRED, "Failed partial consumption must restore linked citizen employment.")
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
			_advance_state_to(state, state.completes_at - 1)
			_expect(state.phase == "building", "Construction must not complete one minute early.")
			_expect(int(state.get_preview([] as Array[String]).remaining_minutes) == 1, "One minute before completion must report exactly one minute remaining.")
			var changes_before_finish: int = _change_count
			_advance_state_to(state, state.completes_at)
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
	var selected: Array[String] = [TEST_WORKER_IDS[0], TEST_WORKER_IDS[1]]
	_fixture_state.start_clearing([TEST_WORKER_IDS[0]] as Array[String], false)
	_advance_state_to(_fixture_state, _fixture_state.completes_at)
	var result: Dictionary = _fixture_state.start_build(selected)
	_expect(bool(result.success), "The real plot's runtime state must accept the fixture construction team.")
	if not bool(result.success):
		await _free_content()
		return
	_advance_state_to(_fixture_state, _fixture_state.started_at + 900)
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
	_advance_state_to(retained_state, retained_state.completes_at)
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

func _attempt_reentrant_start() -> void:
	if not _reentrant_watch or _reentrant_attempted:
		return
	_reentrant_attempted = true
	_reentrant_result = _reentrant_state.call("start_build", _reentrant_worker_ids)

func _remove_unconsumed_material_during_start() -> void:
	if not _rollback_watch:
		return
	_rollback_watch = false
	for item_id: String in REQUIREMENTS:
		var quantity: int = int(REQUIREMENTS[item_id])
		if Inventory.has_item(item_id, quantity):
			_externally_removed_item_id = item_id
			Inventory.remove_item(item_id, quantity)
			return

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
