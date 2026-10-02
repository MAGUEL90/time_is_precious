extends Node

const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const SOURCES: Dictionary = {
	"ClaySiteA": "clay_lump",
	"WoodSite": "wood_log",
	"ReedSite": "reed_bundle",
	"StrawSite": "straw_bundle",
	"WaterSite": "water_jar"
}
var failures: int = 0
var content: Node
var player: Player
var worksites: Node2D

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _settle() -> void:
	for _frame: int in range(5):
		await get_tree().physics_frame
	await get_tree().process_frame

func _press_e() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventAction.new()
	event.action = "interact"
	get_viewport().push_input(event)
	await get_tree().process_frame

func _at_site(site: Marker2D) -> void:
	player.global_position = site.global_position + Vector2(0, 8)
	await _settle()
	await _press_e()

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.environment.color = Color.WHITE
	content = CONTENT.instantiate()
	add_child(content)
	player = content.get_node("YSortWorld/Player")
	worksites = content.get_node("YSortWorld/Worksites")
	await _settle()
	_expect(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(), "Map startup must not seed materials or hire workers.")
	_expect(worksites.sites.size() == SOURCES.size(), "Current authored map exposes the five approved resource sites.")
	_expect(worksites.player == player and worksites.inventory_ui == content.get_node("InventoryUI"), "Resource map reuses the authored Player and Inventory UI.")
	_expect(content.find_children("Player", "", true, false).size() == 1, "Resource integration must not add a second player.")
	_expect(content.find_children("JobBoard", "", true, false).size() == 1, "Resource integration must retain one existing Job Board.")
	await _capture_overview()
	for site_id: String in SOURCES:
		var site: Marker2D = worksites.get_node("WorksiteMarkers/" + site_id)
		var session = worksites.sites[StringName(site_id)]
		_expect(session.item_id == SOURCES[site_id], "Site output identity is configured correctly: " + site_id)
		# Real E routing must reach the intended source despite nearby stockpiles.
		var before: int = _now()
		await _at_site(site)
		_expect(worksites.inspector.visible and worksites._selected_site == site, "E opens the intended current-map worksite: " + site_id)
		if not worksites.inspector.visible:
			_finish()
			return
		_expect(get_tree().paused and not player.can_move, "Worksite inspection retains modal movement/time guards.")
		worksites.inspector.close_button.pressed.emit()
		_expect(_now() == before and Inventory.items.is_empty(), "Inspection cancellation does not charge time or create materials.")
		await _at_site(site)
		worksites.inspector.hourly_button.pressed.emit()
		worksites.inspector.next_button.pressed.emit()
		await _capture("main-map-" + site_id + "-inspector.png")
		var expected: int = mini(floori(180.0 / session.minutes_per_unit), session.stock)
		worksites.inspector.start_button.pressed.emit()
		worksites.inspector.start_button.pressed.emit()
		await worksites.work_finished
		var ground: int = 0
		for drop: Node in worksites.get_node("GroundOutput").get_children():
			_expect(drop.item_id == SOURCES[site_id], "Manual overflow retains the selected source identity.")
			ground += drop.quantity
			# Test-owned output is cleared between independent source checks.
			drop.free()
		_expect(_now() == before + 180, "Current-map hourly work charges exactly three hours once.")
		_expect(int(Inventory.items.get(SOURCES[site_id], 0)) + ground == expected, "Current-map inventory plus overflow conserves earned material: " + site_id)
		_expect(player.can_move and not get_tree().paused, "Work completion restores map controls.")
		Inventory.items.clear()
		Inventory.items_changed.emit()
		# Exercise the existing atomic endpoint and actual authored E withdrawal.
		var destination: StorageDestination = worksites._storage_destination(StringName(site_id))
		_expect(destination != null and worksites._hauler_storage_reason(destination, StringName(site_id)).is_empty(), "Source has a matching delivery destination: " + site_id)
		if destination == null:
			continue
		var storage: Node = destination.get_storage()
		_expect(storage.try_add_item(SOURCES[site_id], 3), "Matching storage accepts cargo.")
		_expect(not storage.try_add_item("sun_dried_mudbrick", 1), "Raw stockpile preserves its existing item filter.")
		player.global_position = destination.global_position + Vector2(0, 5)
		await _settle()
		_expect(player.current_interactable == destination, "Nearby sources do not steal E from storage.")
		var normal_capacity: float = Inventory.max_load
		Inventory.max_load = 0.0
		await _press_e()
		_expect(storage.quantity == 3 and Inventory.items.is_empty(), "Full bag cannot remove stored materials.")
		Inventory.max_load = normal_capacity
		await _press_e()
		await _press_e()
		_expect(storage.quantity == 0 and int(Inventory.items.get(SOURCES[site_id], 0)) == 3, "E withdrawal is capacity-safe and cannot duplicate stock.")
		Inventory.items.clear()
		Inventory.items_changed.emit()
	# Existing Job Board remains reachable after worksite integration.
	var board: JobBoard = content.get_node("YSortWorld/InitialWorksites/JobBoard")
	player.global_position = board.global_position + Vector2(0, 12)
	await _settle()
	await _press_e()
	_expect(is_instance_valid(board.job_board_ui), "Job Board still owns its E interaction.")
	if is_instance_valid(board.job_board_ui):
		board.job_board_ui.close_button.pressed.emit()
	# Reopening the map uses the same runtime applicant and city tool provider.
	var provider: Node = worksites.city_tools
	var applicant_id: String = content.get_node("YSortWorld/InitialWorksites").APPLICANT_ID
	var applicant: CitizenData = CitizenManager.get_citizen(applicant_id)
	content.free()
	content = CONTENT.instantiate()
	add_child(content)
	player = content.get_node("YSortWorld/Player")
	worksites = content.get_node("YSortWorld/Worksites")
	await _settle()
	_expect(worksites.city_tools == provider and CitizenManager.get_citizen(applicant_id) == applicant, "Map reload does not duplicate runtime providers or the initial applicant.")
	_expect(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(), "Reload must not auto-grant items or hire fixture workers.")
	await _run_daily_routes()
	_finish()

func _run_daily_routes() -> void:
	# Workers/carts below belong only to this test, after clean startup was checked.
	worksites.enable_worker_commute = false
	for site_id: String in SOURCES:
		var destination: StorageDestination = worksites._storage_destination(StringName(site_id))
		for role: String in ["laborer", "hauler"]:
			var worker := WorkerData.new()
			worker.worker_id = "map_test_" + site_id + "_" + role
			worker.display_name = worker.worker_id
			worker.profession = WorkerData.Profession.LABORER if role == "laborer" else WorkerData.Profession.HAULER
			WorkerDatabase.workers_by_id[worker.worker_id] = worker
			if role == "hauler":
				worksites.city_tools.add_tool_unit(worker.worker_id + "_cart", "cart", "Test cart")
				worksites.worker_management.equip(worker.worker_id, worker.worker_id + "_cart")
				_expect(worksites.daily.select_hauler(StringName(site_id), worker.worker_id, worksites.get_path_to(destination), destination.display_name, 3), "Current-map Hauler accepts a cart and matching route.")
			else:
				_expect(worksites.daily.toggle(StringName(site_id), worker.worker_id), "Current-map Laborer can join the Daily team.")
		_expect(worksites.daily.start(StringName(site_id), worksites._drop_daily_output.bind(worksites.get_node("WorksiteMarkers/" + site_id))), "Current-map Daily assignment starts: " + site_id)
	var deadline: int = (TimeComponentManager.current_day + 1) * 1440 + 420 + 180
	TimeComponentManager.advance_minutes(deadline - _now())
	for site_id: String in SOURCES:
		var session = worksites.sites[StringName(site_id)]
		var storage: Node = worksites._storage_destination(StringName(site_id)).get_storage()
		var expected: int = floori(180.0 / session.minutes_per_unit)
		var worker_id: String = "map_test_" + site_id + "_laborer"
		_expect(worksites.daily.jobs[StringName(site_id)].stats[worker_id].output == expected, "Daily work retains the existing source rate.")
		_expect(storage.quantity == 3, "Current-map Hauler delivers to the authored stockpile: " + site_id)
		_expect(worksites._daily_output_count(StringName(site_id)) + storage.quantity == expected, "Daily ground output and deliveries are conserved per resource.")
		for stack: Node in worksites.get_node("GroundOutput").get_children():
			if stack.get_meta("daily_site", "") == site_id:
				_expect(stack.item_id == SOURCES[site_id], "Simultaneous hauling must retain each resource identity.")

func _capture_overview() -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(0, -204)
	camera.zoom = Vector2(0.75, 0.75)
	add_child(camera)
	camera.make_current()
	await _settle()
	await _capture("main-map-worksites-overview.png")
	camera.free()
	player.get_node("Camera2D").make_current()
	var authored_position: Vector2 = player.global_position
	player.global_position = worksites.global_position + Vector2(0, 8)
	await _settle()
	await _capture("main-map-worksites-player-view.png")
	player.global_position = authored_position
	await _settle()

func _capture(filename: String) -> void:
	var directory: String = OS.get_environment("TIP_MAP_WORKSITES_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join(filename))

func _finish() -> void:
	get_tree().paused = false
	print("MainMapWorksitesTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
