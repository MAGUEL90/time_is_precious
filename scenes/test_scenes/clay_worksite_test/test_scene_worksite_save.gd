extends Node2D

## Run write, then read in separate processes sharing an isolated user:// folder.
const STORE = preload("res://scenes/test_scenes/clay_worksite_test/worksite_save_store.gd")
var setup
var fixture
var store
var registry: Dictionary
var failures: int = 0
var phase_completed: bool = false
var run_id: String = "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
const LABORER: String = "delivery_laborer"
const HAULER: String = "delivery_hauler"
const FIRED: String = "delivery_hauler_b"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	TimeComponentManager.is_paused = true
	setup = preload("res://scenes/test_scenes/clay_worksite_test/test_scene_hauler_delivery_setup.tscn").instantiate()
	add_child(setup)
	await get_tree().process_frame
	await get_tree().process_frame
	fixture = setup.fixture
	store = setup.save_store
	registry = {"storage_a": setup.destination_a, "storage_b": setup.destination_b}
	if OS.get_environment("TIP_TEST_SAVE_PHASE") == "write":
		await _write_phase()
	elif OS.get_environment("TIP_TEST_SAVE_PHASE") == "read":
		await _read_phase()
	else:
		_expect(false, "Set TIP_TEST_SAVE_PHASE=write or read; use isolated APPDATA.")
	_expect(phase_completed, "The complete phase reached its final checkpoint.")
	print("WorksiteSaveTest %s %s" % [OS.get_environment("TIP_TEST_SAVE_PHASE"), "PASSED" if failures == 0 else "FAILED"])
	get_tree().quit(0 if failures == 0 else 1)

func _write_phase() -> void:
	_expect(store.status == "Saved" and not store.blocked, "Missing save starts fresh and writes the initial snapshot.")
	fixture._close_inspector()
	Inventory.add_item("clay_lump", 2)
	setup.storage_b.try_add_item("clay_lump", 5)
	var citizen := CitizenData.new()
	citizen.citizen_id = LABORER
	citizen.display_name = "Arad"
	citizen.profession = WorkerData.Profession.LABORER
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.HIRED
	citizen.visual_profile = VisualProfile.new()
	citizen.visual_profile.hair_style = "default"
	citizen.visual_profile.clothes_id = "default"
	CitizenManager.citizens_by_id[LABORER] = citizen
	WorkerDatabase.dismissed_workers[FIRED].profession_xp = 4
	fixture.worker_management.productive_days[FIRED] = [0]
	fixture.worker_management.contributions[FIRED] = 4
	fixture.city_tools.add_tool_unit("save_glove", "basic_glove", "Basic Glove")
	fixture.city_tools.add_tool_unit("save_hammer", "stone_hammer", "Stone Hammer")
	fixture.worker_management.equip(LABORER, "save_glove")
	fixture.worker_management.equip(LABORER, "save_hammer")
	_expect(fixture.daily.toggle(&"ClaySiteA", LABORER), "Laborer selected.")
	_expect(fixture.daily.select_hauler(&"ClaySiteA", HAULER, fixture.get_path_to(setup.destination_b), "Storage B", 20), "Hauler assigned a single destination and target.")
	_expect(fixture.daily.start(&"ClaySiteA", fixture._drop_daily_output.bind(fixture.get_node("WorksiteMarkers/ClaySiteA"))), "Daily assignment committed.")
	TimeComponentManager.advance_minutes(1440 + 7 * 60 + 37 - fixture.daily.now())
	TimeComponentManager.current_weather = "cloudy"
	_expect(fixture.daily.jobs[&"ClaySiteA"].progress[LABORER] == 7, "Write checkpoint contains seven minutes of partial gathering.")
	_expect(fixture.hauling.routes[HAULER].phase == "outbound" and fixture.hauling.routes[HAULER].cargo.quantity == 3, "Write checkpoint is a live trip with three items.")
	# Exercise the actual timer, including while a menu pauses the tree.
	fixture._open_site_panel(fixture.get_node("WorksiteMarkers/ClaySiteA"))
	await get_tree().create_timer(0.7, true).timeout
	_expect(not store.blocked, "Autosave succeeds after gameplay changes: " + store.status)
	var disk = JSON.parse_string(FileAccess.get_file_as_string(store.path))
	_expect(disk is Dictionary and disk.clock.hour == 7 and disk.clock.minute == 37 and disk.routes[HAULER].cargo == 3, "Automatic save records the settled trip while the menu is open.")
	_expect(FileAccess.file_exists(store.path + ".bak"), "Subsequent autosave retains the previous valid snapshot.")
	print("Save restart checkpoint: " + ProjectSettings.globalize_path(store.path))
	phase_completed = true

func _read_phase() -> void:
	_expect(store.status == "Loaded" and not store.blocked, "New process automatically loads the interactive scene save: " + store.status)
	if store.blocked or not fixture.hauling.routes.has(HAULER):
		return
	store.enabled = false # The rest uses explicit checkpoints for isolated failure tests.
	_expect(TimeComponentManager.current_day == 1 and TimeComponentManager.current_hour == 7 and TimeComponentManager.current_minute == 37, "Restart restores exact game minute without offline advancement.")
	_expect(TimeComponentManager.current_weather == "cloudy" and TimeComponentManager.environment.color == TimeComponentManager._target_environment_color, "Cloudy weather and lighting restore even while the menu is paused.")
	_expect(fixture.daily.jobs[&"ClaySiteA"].ids == [LABORER, HAULER], "Committed assignment and worker slots survive restart.")
	_expect(fixture.daily.jobs[&"ClaySiteA"].progress[LABORER] == 7 and fixture.daily.minutes_by_worker[LABORER] == 37, "Fractional work and daily minutes survive restart.")
	_expect(WorkerDatabase.get_worker_data(LABORER).profession_xp == 3 and WorkerDatabase.get_worker_data(HAULER).profession_xp == 0, "XP reflects gathered items and only completed deliveries.")
	_expect(WorkerDatabase.get_worker_data(FIRED) == null and WorkerDatabase.dismissed_workers[FIRED].profession_xp == 4, "Dismissed worker stays dismissed and retains prior XP.")
	_expect(fixture.city_tools.has_equipped(LABORER, "basic_glove") and fixture.city_tools.has_equipped(LABORER, "stone_hammer") and fixture.city_tools.has_equipped(HAULER, "cart"), "Hands and Tool equipment owners survive restart.")
	_expect(CitizenManager.get_citizen(LABORER).employment_status == CitizenData.EmploymentStatus.HIRED, "Citizen employment link is restored.")
	_expect(fixture.hauling.routes[HAULER].destination == setup.destination_b and fixture.hauling.routes[HAULER].daily_target == 20, "Destination resolves to the new scene node using its stable ID.")
	_expect(fixture.sites[&"ClaySiteA"].stock == 69 and setup.storage_b.quantity == 5 and Inventory.items.get("clay_lump") == 2, "Natural stock, storage and picked-up inventory are retained.")
	var original: Dictionary = store.codec.capture(fixture, registry)
	var total: int = _total()
	for repeat: int in range(2):
		_expect(store.codec.restore(original, fixture, registry), "Repeated restore succeeds.")
		_expect(_total() == total and fixture.daily.progress_rows(&"ClaySiteA").size() == 2, "Repeated restore replaces records without adding workers/items.")
	# Verify arrival exactly once, then save/load the empty return leg.
	fixture._close_inspector()
	var arrival: int = int(fixture.hauling.routes[HAULER].arrival)
	TimeComponentManager.advance_minutes(arrival - fixture.daily.now())
	_expect(setup.storage_b.quantity == 8 and WorkerDatabase.get_worker_data(HAULER).profession_xp == 3, "Resumed cargo credits storage and XP exactly once on arrival.")
	_expect(fixture.hauling.routes[HAULER].phase == "returning" and fixture.hauling.routes[HAULER].cargo.quantity == 0, "Successful delivery starts an empty return leg.")
	var returning: Dictionary = store.codec.capture(fixture, registry)
	_expect(store.codec.restore(returning, fixture, registry), "Return leg restores.")
	TimeComponentManager.advance_minutes(int(fixture.hauling.routes[HAULER].arrival) - fixture.daily.now())
	_expect(setup.storage_b.quantity == 8 and WorkerDatabase.get_worker_data(HAULER).profession_xp == 3 and _total() == total, "Return after load neither redelivers nor loses resources.")
	_expect(fixture.worker_management.productive_days[HAULER].size() == 1 and fixture.worker_management.productive_days[LABORER].size() == 1, "Continued contributions count each productive day once.")
	TimeComponentManager.advance_minutes(15 * 60 - (fixture.daily.now() % 1440) + 60)
	_expect(fixture.hauling.delivered_on_day(HAULER, 1) == 20 and setup.storage_b.quantity == 25 and _total() == total, "Target still stops at exactly 20 received items after restart.")
	var complete: Dictionary = store.codec.capture(fixture, registry)
	_expect(store.codec.restore(complete, fixture, registry), "Completed target restores.")
	TimeComponentManager.advance_minutes((3 * 1440 + 7 * 60) - fixture.daily.now())
	_expect(fixture.daily.jobs.has(&"ClaySiteA") and not fixture.hauling.target_reached(HAULER, 3), "Standing assignment returns tomorrow with a fresh delivery quota.")
	_rejection_and_removal(original, total)
	_pickup_checkpoint(original)
	_invalid_files(original)
	_recovery(original)
	_expect(store.codec.restore(original, fixture, registry), "Restore visual checkpoint.")
	fixture._open_site_panel(fixture.get_node("WorksiteMarkers/ClaySiteA"))
	await get_tree().process_frame
	fixture.inspector.progress_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("worksite-save-restored-progress.png"))
	phase_completed = true

func _rejection_and_removal(original: Dictionary, total: int) -> void:
	_expect(store.codec.restore(original, fixture, registry), "Reset trip checkpoint.")
	setup.destination_b.accepting_deliveries = false
	fixture.daily.withdraw(&"ClaySiteA", HAULER)
	var pending: Dictionary = store.codec.capture(fixture, registry)
	_expect(store.codec.restore(pending, fixture, registry), "Pending removal with cargo restores.")
	TimeComponentManager.advance_minutes(int(fixture.hauling.routes[HAULER].arrival) - fixture.daily.now())
	_expect(fixture.hauling.routes[HAULER].cargo.quantity == 3 and WorkerDatabase.get_worker_data(HAULER).profession_xp == 0, "Rejected delivery returns its original cargo and awards no XP.")
	var rejected: Dictionary = store.codec.capture(fixture, registry)
	_expect(store.codec.restore(rejected, fixture, registry), "Rejected loaded return leg restores.")
	TimeComponentManager.advance_minutes(int(fixture.hauling.routes[HAULER].arrival) - fixture.daily.now())
	_expect(not fixture.hauling.routes.has(HAULER) and fixture.daily.jobs[&"ClaySiteA"].ids == [LABORER] and _total() == total, "Pending removal releases after returning cargo exactly once.")

func _pickup_checkpoint(original: Dictionary) -> void:
	_expect(store.codec.restore(original, fixture, registry), "Reset for pickup conservation.")
	fixture._drop_daily_output(10, fixture.get_node("WorksiteMarkers/ClaySiteA"))
	Inventory.max_load = Inventory.get_total_inventory_weight() + Inventory.get_item_total_weight("clay_lump", 2)
	var total: int = _total()
	var pile = fixture.get_node("GroundOutput").get_child(0)
	pile.on_player_interact(fixture.player)
	var snapshot: Dictionary = store.codec.capture(fixture, registry)
	_expect(pile.is_collecting and snapshot.ground.size() == 1 and snapshot.ground[0].quantity == 8, "Snapshot excludes the collecting animation and retains the partial-pickup remainder.")
	_expect(store.codec.restore(snapshot, fixture, registry) and _total() == total and Inventory.items.clay_lump == 4, "Pickup animation crossing a save cannot duplicate the inventory credit.")

func _invalid_files(original: Dictionary) -> void:
	_expect(store.codec.restore(original, fixture, registry), "Reset for validation tests.")
	var invalids: Array = ["{broken", "[]", '{"schema_version": [], "scenario": "clay_worksite_mvp"}', '{"schema_version": 1, "scenario": {}}']
	for version: int in [0, 2]:
		var altered: Dictionary = original.duplicate(true)
		altered.schema_version = version
		invalids.append(JSON.stringify(altered))
	var wrong_destination: Dictionary = original.duplicate(true)
	wrong_destination.routes[HAULER].destination_id = "missing_storage"
	invalids.append(JSON.stringify(wrong_destination))
	var shared_slot: Dictionary = original.duplicate(true)
	shared_slot.tools.test_cart_1.worker_id = HAULER
	invalids.append(JSON.stringify(shared_slot))
	var missing_worker: Dictionary = original.duplicate(true)
	missing_worker.workers.erase(HAULER)
	invalids.append(JSON.stringify(missing_worker))
	var wrong_cargo: Dictionary = original.duplicate(true)
	wrong_cargo.routes[HAULER].cargo = -3
	invalids.append(JSON.stringify(wrong_cargo))
	var wrong_type: Dictionary = original.duplicate(true)
	wrong_type.jobs.ClaySiteA.stats = [1]
	invalids.append(JSON.stringify(wrong_type))
	for index: int in range(invalids.size()):
		var probe = _probe("invalid_%d" % index)
		_write(probe.path, invalids[index])
		var before: String = JSON.stringify(store.codec.capture(fixture, registry))
		_expect(probe.load_now() == "invalid" and probe.blocked, "Invalid/unsupported save rejected: %d" % index)
		_expect(JSON.stringify(store.codec.capture(fixture, registry)) == before, "Failed load makes no partial mutations: %d" % index)
		_expect(not probe.save_now() and FileAccess.get_file_as_string(probe.path) == invalids[index], "Invalid/unsupported file preserved: %d" % index)
		probe.free()
	var registry_before: String = JSON.stringify(store.codec.capture(fixture, registry))
	_expect(not store.codec.restore(original, fixture, {"storage_a": setup.destination_a}), "Missing scene destination rejects the entire save.")
	_expect(JSON.stringify(store.codec.capture(fixture, registry)) == registry_before, "Registry mismatch leaves current state intact.")

func _recovery(original: Dictionary) -> void:
	_expect(store.codec.restore(original, fixture, registry), "Reset for disk recovery.")
	var probe = _probe("recovery")
	_expect(probe.save_now(), "First recovery snapshot written.")
	WorkerDatabase.get_worker_data(LABORER).profession_xp += 1
	_expect(probe.save_now() and FileAccess.file_exists(probe.path + ".bak"), "Backup retained on replacement.")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(probe.path), ProjectSettings.globalize_path(probe.path + ".interrupted"))
	probe.free()
	probe = _probe("recovery")
	_expect(probe.load_now() == "loaded" and not probe.blocked and WorkerDatabase.get_worker_data(LABORER).profession_xp == 3, "Interrupted rotation recovers the prior valid backup.")
	_expect(FileAccess.file_exists(probe.path) and FileAccess.file_exists(probe.path + ".bak"), "Recovery recreates primary and keeps backup.")
	WorkerDatabase.get_worker_data(LABORER).profession_xp += 1
	probe.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	var flushed = JSON.parse_string(FileAccess.get_file_as_string(probe.path))
	_expect(flushed.workers[LABORER].profession_xp == 4, "Normal close notification flushes a change before the autosave timer.")
	_write(probe.path, "externally changed")
	WorkerDatabase.get_worker_data(LABORER).profession_xp += 1
	_expect(not probe.save_now() and FileAccess.get_file_as_string(probe.path) == "externally changed", "Another session/external file change is preserved.")
	probe.free()

func _probe(label: String):
	var probe = STORE.new()
	probe.path = "user://save_qa/" + run_id + "/" + label + ".json"
	probe.fixture = fixture
	probe.destinations = registry
	probe.enabled = true
	return probe

func _write(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()

func _total() -> int:
	var total: int = setup.storage_a.quantity + setup.storage_b.quantity + Inventory.items.get("clay_lump", 0)
	for session in fixture.sites.values():
		total += session.stock
	for pile: PickUpItem in fixture.get_node("GroundOutput").get_children():
		if not pile.is_queued_for_deletion() and not pile.is_collecting:
			total += pile.quantity
	for route: Dictionary in fixture.hauling.routes.values():
		total += int(route.cargo.quantity)
	return total

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
