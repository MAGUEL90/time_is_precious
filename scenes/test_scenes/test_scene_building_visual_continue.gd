extends "res://scenes/test_scenes/test_scene_house_save_migration.gd"

## Disk-bound regression for the authored building views. Run with an isolated
## XDG_DATA_HOME: the unique test_root paths are never the player's save slot.
const SITE_ART: String = "res://assets/objects/buildings/house_construction_site.png"
const HOUSE_ART: String = "res://assets/objects/buildings/house_level_0.png"
const WORKSHOP_ART: String = "res://assets/objects/buildings/clay_workshop_0.png"
const OPEN_ART: String = "res://assets/ui/building/plot_level_0.png"
const SEGMENTS: Array[String] = ["Plot", "LeftWall", "LeftWallTop", "RightWall", "RightWallTop", "Table", "TableLegs"]

var visual_house: Node2D
var keeper: Node2D
var second_workshop: Node2D
var unfinished_path: String
var finished_path: String
var unfinished_files: Dictionary
var finished_files: Dictionary
var expected_city_items: Dictionary
var expected_workshop_items: Dictionary
var expected_inventory: Dictionary
var expected_job: Dictionary
var base_shelter: int


func _run() -> void:
	# Optional write/replay mode exercises the same two slots in a fresh Godot
	# process. Only use this mode with an isolated XDG_DATA_HOME.
	var replay_mode: String = OS.get_environment("TIP_BUILDING_VISUAL_SAVE_MODE")
	if replay_mode in ["write", "replay"]:
		test_root = "user://building_visual_continue_replay"
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_reset_singletons_before_load()
	await _load_root_city()
	visual_house = content.get_node("YSortWorld/CitizenHousePlot")
	keeper = content.get_node("YSortWorld/WorkshopPlot")
	second_workshop = content.get_node("YSortWorld/WorkshopPlot2")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	unfinished_path = test_root.path_join("unfinished.json")
	finished_path = test_root.path_join("finished.json")
	if replay_mode == "replay":
		await _fresh_process_replay()
		_finish_visual_test()
		return
	_prepare_city_state()
	if not _hire_and_assign_team():
		_finish_visual_test()
		return
	_settle_needs()
	WorkShopStorage.max_load = 200.0
	for item_id: String in ["clay_lump", "straw_bundle", "water_jar"]:
		WorkShopStorage.add_item(item_id, 6)
	base_shelter = CityStockManager.shelter_capacity
	expected_city_items = city_storage.items.duplicate(true)
	expected_workshop_items = WorkShopStorage.items.duplicate(true)
	expected_inventory = Inventory.items.duplicate(true)
	expected_job = store.snapshot._sites.capture(runtime).jobs[str(WOOD_SITE)].duplicate(true)

	# These are valid stable phase fixtures, not a simulated construction: no
	# workers, time, materials or shelter reward are consumed by staging them.
	_stage_phase("empty")
	await _visual_settle()
	if not _save_visual_slot(unfinished_path):
		_finish_visual_test()
		return
	unfinished_files = _house_files(unfinished_path)
	_stage_phase("built")
	# A previously completed house already owns its three shelter places.
	CityStockManager.shelter_capacity = base_shelter + 3
	await _visual_settle()
	if not _save_visual_slot(finished_path):
		_finish_visual_test()
		return
	finished_files = _house_files(finished_path)
	_assert_finished("Saved finished")

	# Continue can switch back again before deferred backend deletion runs.
	if not _load_visual_slot(unfinished_path) or not _load_visual_slot(finished_path):
		_finish_visual_test()
		return
	await _visual_settle(8)
	_assert_finished("Immediate finished → unfinished → finished")
	_assert_preserved(base_shelter + 3, "Immediate restored finished")
	await _test_retired_backend_interaction()

	if not _load_visual_slot(unfinished_path):
		_finish_visual_test()
		return
	await _visual_settle(6)
	_assert_unfinished()
	_assert_preserved(base_shelter, "Restored unfinished")
	for plot: Node2D in [visual_house, keeper, second_workshop]:
		await _test_unfinished_player_access(plot)

	for attempt: int in range(2):
		if not _load_visual_slot(finished_path):
			_finish_visual_test()
			return
		await _visual_settle(6)
		_assert_finished("Restored finished attempt %d" % attempt)
		_assert_preserved(base_shelter + 3, "Restored finished attempt %d" % attempt)
		_expect(_house_files(unfinished_path) == unfinished_files and _house_files(finished_path) == finished_files,
			"Continue does not rewrite either source or its recovery files.")

	for plot: Node2D in [keeper, second_workshop]:
		await _test_finished_player_access(plot)
		_test_production(plot)
	_expect(CityStockManager.shelter_capacity == base_shelter + 3,
		"Player interaction and production do not grant shelter a second time.")
	_expect(_house_files(unfinished_path) == unfinished_files and _house_files(finished_path) == finished_files,
		"The original checkpoints remain byte-for-byte unchanged after Continue and production.")
	_finish_visual_test()


func _fresh_process_replay() -> void:
	if not FileAccess.file_exists(unfinished_path) or not FileAccess.file_exists(finished_path):
		_expect(false, "Fresh-process replay requires both slots created by write mode in the same isolated XDG_DATA_HOME.")
		return
	unfinished_files = _house_files(unfinished_path)
	finished_files = _house_files(finished_path)
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(unfinished_path))
	if not document is Dictionary or not document.has("state"):
		_expect(false, "Fresh-process replay source is a readable city checkpoint.")
		return
	var values = MIGRATION_VALUES.new()
	var raw: Dictionary = values.decode(document.state)
	base_shelter = int(raw.stock.shelter_capacity)
	expected_city_items = raw.city_storage.items.duplicate(true)
	expected_workshop_items = raw.workshop_storage.items.duplicate(true)
	expected_inventory = raw.inventory.items.duplicate(true)
	expected_job = raw.worksites.jobs[str(WOOD_SITE)].duplicate(true)
	for phase: String in ["finished", "unfinished", "finished"]:
		if not _load_visual_slot(finished_path if phase == "finished" else unfinished_path):
			return
		await _visual_settle(6)
		if phase == "finished":
			_assert_finished("Fresh-process finished Continue")
			_assert_preserved(base_shelter + 3, "Fresh-process finished Continue")
		else:
			_assert_unfinished()
			_assert_preserved(base_shelter, "Fresh-process unfinished Continue")
		_expect(_house_files(unfinished_path) == unfinished_files and _house_files(finished_path) == finished_files,
			"Fresh-process Continue leaves both checkpoint and recovery files untouched.")


func _stage_phase(phase: String) -> void:
	for plot: Node2D in [visual_house, keeper, second_workshop]:
		var state: Node = plot.construction
		state.phase = phase
		state.clearing_remaining = 0
		state.clearing_by_player = false
		state.player_building = false
		state.worker_ids.clear()
		state.worker_capacity = 0
		state.work_total_units = 0
		state.started_at = 0
		state.completes_at = 0
		state._latest_time = _clock_minute()
		state.payroll_work_remainder = 0
		state.changed.emit()


func _save_visual_slot(path: String) -> bool:
	_select_house_path(path)
	var saved: bool = store.save_checkpoint()
	_expect(saved, "A real city checkpoint saves to the isolated test slot: " + store.last_error)
	return saved


func _load_visual_slot(path: String) -> bool:
	_select_house_path(path)
	var loaded: bool = store.load_checkpoint()
	_expect(loaded, "A real city checkpoint continues from the isolated test slot: " + store.last_error)
	return loaded


func _assert_unfinished() -> void:
	_expect(visual_house.construction.phase == "empty" and visual_house.get_node("SiteHouse").visible
		and not visual_house.get_node("FinishedHouse").visible
		and visual_house.get_node("SiteHouse").texture.resource_path == SITE_ART
		and visual_house.interaction_area.monitoring and visual_house.get_node("HouseBody/CollisionShape2D").disabled,
		"An unfinished house reloads with the original site art and available plot interaction.")
	for plot: Node2D in [keeper, second_workshop]:
		_expect(plot.construction.phase == "empty" and not plot.has_node("BuiltWorkshop")
			and plot.interaction_area.monitoring,
			"An unfinished workshop has no stale production backend and accepts plot interaction.")
		for path: String in SEGMENTS:
			var part: Sprite2D = plot.get_node(path)
			_expect(part.visible and part.texture.resource_path == OPEN_ART,
				"An unfinished workshop retains the original " + path + " art.")
	_expect(not keeper.get_node("FinishedBuilding").visible
		and not second_workshop.get_node("FinishedClayWorkshop").visible,
		"Neither unfinished workshop displays its finished sprite.")


func _assert_finished(context: String) -> void:
	_expect(visual_house.construction.phase == "built" and not visual_house.get_node("SiteHouse").visible
		and visual_house.get_node("FinishedHouse").visible
		and visual_house.get_node("FinishedHouse").texture.resource_path == HOUSE_ART
		and not visual_house.interaction_area.monitoring and not visual_house.get_node("HouseBody/CollisionShape2D").disabled,
		context + ": finished house artwork, collision and interaction are restored.")
	_expect(keeper.get_node("FinishedBuilding").visible
		and keeper.get_node("FinishedBuilding/Base").texture.resource_path == WORKSHOP_ART
		and not keeper.get_node("FinishedClayWorkshop").visible,
		context + ": the keeper's finished workshop uses the uploaded art once.")
	_expect(second_workshop.get_node("FinishedClayWorkshop").visible
		and second_workshop.get_node("FinishedClayWorkshop/Sprite2D").texture.resource_path == WORKSHOP_ART,
		context + ": the second finished workshop uses the uploaded art.")
	for plot: Node2D in [keeper, second_workshop]:
		var count: int = 0
		for child: Node in plot.get_children():
			if child is WorkShop and not child.is_queued_for_deletion():
				count += 1
				_expect(child.name == &"BuiltWorkshop" and child.get_job_data("mudbrick_make") != null
					and child.get_process_data("drying_mudbrick") != null,
					context + ": the production backend exposes the existing job and process.")
		_expect(plot.construction.phase == "built" and count == 1 and not plot.interaction_area.monitoring,
			context + ": exactly one live workshop backend owns interaction.")
		for path: String in SEGMENTS:
			_expect(not plot.get_node(path).visible, context + ": old " + path + " art is hidden.")


func _assert_preserved(capacity: int, context: String) -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(PRODUCTION_ID)
	var saved_job: Dictionary = store.snapshot._sites.capture(runtime).jobs.get(str(WOOD_SITE), {})
	_expect(CityStockManager.shelter_capacity == capacity and _same_snapshot(city_storage.items, expected_city_items)
		and _same_snapshot(WorkShopStorage.items, expected_workshop_items)
		and _same_snapshot(Inventory.items, expected_inventory) and _same_snapshot(saved_job, expected_job),
		context + ": exact shelter, materials, inventory and resource assignment survive.")
	_expect(worker != null and worker.worker_id == PRODUCTION_ID and worker.wage_shekel_per_day == 6
		and CitizenManager.get_citizen(PRODUCTION_ID) != null and city_storage.has_equipped(HAULER_ID, "cart")
		and city_storage.has_equipped(LABORER_ID, "basic_glove"),
		context + ": worker identity, contract and allocated tools survive.")


func _test_unfinished_player_access(plot: Node2D) -> void:
	player.global_position = plot.interaction_area.global_position + Vector2(0, 4)
	await _visual_settle()
	var selectable: bool = plot.has_player_access() and player.current_interactable == plot
	_expect(selectable, "The restored unfinished plot is selectable by the actual player.")
	if not selectable:
		return
	_press_interact()
	if plot == keeper:
		_expect(is_instance_valid(keeper.keeper_dialogue), "The unfinished keeper still opens its native dialogue.")
	else:
		_expect(is_instance_valid(plot.menu), "The unfinished plot opens its normal menu.")
	plot.close_menu()
	await _visual_settle()


func _test_retired_backend_interaction() -> void:
	for plot: Node2D in [keeper, second_workshop]:
		if not _load_visual_slot(finished_path):
			return
		await _visual_settle(6)
		var backend: WorkShop = plot.get_node_or_null("BuiltWorkshop") as WorkShop
		if backend == null:
			_expect(false, "The finished backend exists before testing occupied-range Continue.")
			continue
		player.global_position = backend.interactable_component.global_position + Vector2(0, 4)
		await _visual_settle()
		var was_inside: bool = player.current_interactable == backend and WorkShopStorage.player_is_in_claim_area
		_expect(was_inside, "The player is in this finished workshop's active interaction and claim range before Continue.")
		if not _load_visual_slot(unfinished_path):
			return
		_expect(not player.nearby_interactables.has(backend) and player.current_interactable != backend,
			"Continuing an unfinished checkpoint immediately detaches the previous workshop interaction.")
		await _visual_settle(6)
		_expect(not plot.has_node("BuiltWorkshop") and not WorkShopStorage.player_is_in_claim_area,
			"The retired workshop leaves no backend or stale claim-range access after Continue.")
		_assert_preserved(base_shelter, "Occupied-range unfinished Continue")


func _test_finished_player_access(plot: Node2D) -> void:
	var backend: WorkShop = plot.get_node_or_null("BuiltWorkshop") as WorkShop
	if backend == null:
		_expect(false, "A finished workshop backend must exist for player interaction.")
		return
	player.global_position = backend.interactable_component.global_position + Vector2(0, 4)
	await _visual_settle()
	var selectable: bool = player.current_interactable == backend
	_expect(selectable, "The restored finished workshop is selectable by the actual player.")
	if not selectable:
		return
	_press_interact()
	_expect(player.claim_menu_is_open and player.claim_menu_workshop == backend,
		"The restored finished workshop opens its normal player menu.")
	var menu_ui: WorkshopMenuUI
	for child: Node in content.get_children():
		if child is WorkshopMenuUI:
			menu_ui = child
	if menu_ui != null:
		menu_ui._on_close_button_pressed()
	else:
		_expect(false, "The finished-workshop menu exists and can be closed.")
	await _visual_settle()


func _press_interact() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	player._unhandled_input(event)


func _test_production(plot: Node2D) -> void:
	var backend: WorkShop = plot.get_node_or_null("BuiltWorkshop") as WorkShop
	if backend == null:
		_expect(false, "A finished backend must exist to start production.")
		return
	var ids: Array[String] = [PRODUCTION_ID]
	var lots_before: int = WorkShopStorage.output_lots.size()
	var fees_before: int = WorkShopStorage.unpaid_claims_ledger.size()
	var started: bool = backend.start_job_from_storage(backend.get_job_data("mudbrick_make"), ids)
	_expect(started, "The restored backend starts an existing paid-worker production job: " + backend.last_start_job_error)
	if not started:
		return
	var worker: WorkerData = WorkerDatabase.get_worker_data(PRODUCTION_ID)
	var order_id: String = worker.current_order_id
	_expect(not order_id.is_empty() and WorkManager.active_orders.has(order_id)
		and not worker.physical_approach.is_empty(), "The production order owns the worker and its plot approach.")
	if order_id.is_empty() or worker.physical_approach.is_empty():
		return
	worker.physical_approach.position = worker.physical_approach.target
	_expect(worker.mark_physical_arrival(order_id), "The assigned worker reaches the restored workshop.")
	TimeComponentManager.advance_minutes(30)
	_expect(not WorkManager.active_orders.has(order_id) and WorkShopStorage.output_lots.size() == lots_before + 1
		and WorkShopStorage.unpaid_claims_ledger.size() == fees_before + 1,
		"The restored workshop completes one job with exactly one output lot and fee.")


func _visual_settle(frames: int = 4) -> void:
	for _index: int in range(frames):
		await get_tree().physics_frame
		await get_tree().process_frame


func _finish_visual_test() -> void:
	get_tree().paused = false
	print("BuildingVisualContinueTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
