extends Node

## Exercises real city runtime and checkpoint owners with isolated test data.
const CITY = preload("res://scenes/content_scene/content_scene.tscn")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const CLAY: StringName = &"ClaySiteA"
const WORKER_ID: String = "initial_workshop_laborer"
var failures: int = 0
var city: Node2D
var work: Node
var store: Node
var player: Player

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var data_root: String = OS.get_environment("XDG_DATA_HOME")
	check(data_root.is_absolute_path() and ProjectSettings.globalize_path("user://").begins_with(data_root.trim_suffix("/") + "/"), "Use a disposable XDG_DATA_HOME.")
	if failures:
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	city = CITY.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	await get_tree().process_frame
	await get_tree().physics_frame
	work = city.get_node("YSortWorld/WorkerRuntime")
	player = city.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	Inventory.max_load = 100000.0
	store = WorkStateRuntime.get_node("CitySave")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://finite_sites_test"))
	store.disk.path = "user://finite_sites_test/checkpoint.json"
	var session = work.sites[CLAY]
	var marker: Node2D = work.get_node("WorksiteMarkers/ClaySiteA")
	var expected_caps: Dictionary = {"clay_lump": 36, "wood_log": 24, "reed_bundle": 40, "water_jar": 48, "straw_bundle": 72}
	for site_id: Variant in work.sites:
		var deposit = work.sites[site_id]
		check(deposit.finite_resource and deposit.stock == expected_caps[deposit.item_id], "Each deposit starts with its provisional testing reserve (legacy straw stays compatible).")
	work._open_site_panel(marker)
	await get_tree().process_frame
	check(not work.inspector.reserve_label.visible and session.finite_resource and session.stock == 36, "The inspector hides Remaining while the actual finite reserve stays intact.")
	await _capture("site-reserve.png")
	work._close_inspector()
	var storage_ui: CanvasLayer = preload("res://scenes/storage_destination/city_storage_access_ui.tscn").instantiate()
	city.add_child(storage_ui)
	storage_ui.open(work.city_tools, func() -> bool: return true, "city")
	await get_tree().process_frame
	check(is_instance_valid(storage_ui.haul_button) and storage_ui.haul_button.text == "Send", "The real City Storage footer offers Send.")
	await _capture("city-storage-send.png")
	storage_ui.haul_button.pressed.emit()
	await get_tree().process_frame
	check(is_instance_valid(storage_ui.haul_ui), "Send opens the existing storage-to-storage transport UI.")
	storage_ui.close()
	await get_tree().process_frame
	if not OS.get_environment("TIP_REVIEW_CAPTURE_DIR").is_empty() and DisplayServer.get_name() != "headless":
		var comparison_camera := Camera2D.new()
		city.add_child(comparison_camera)
		comparison_camera.global_position = marker.global_position
		comparison_camera.zoom = Vector2(1.4, 1.4)
		comparison_camera.make_current()
		for path: String in ["TopHUD", "BottomHUD", "TimeDebugOverlay"]:
			var hud: Node = city.get_node_or_null(path)
			if hud is CanvasLayer or hud is CanvasItem:
				hud.hide()
		await get_tree().process_frame
		await _capture("clay-site-before.png")
	var before_inventory: int = int(Inventory.items.get("clay_lump", 0))
	var before_city: int = int(work.city_tools.items.get("clay_lump", 0))
	var original_position: Vector2 = marker.position
	# Arrange a nearly exhausted deposit; the actual manual work loop owns output.
	session.stock = 3
	session.participants.assign(["player"])
	work._selected_site = marker
	var result: Dictionary = session.execute(180, player, work, work._drop_output)
	check(int(result.units) == 3 and int(result.to_bag) == 3 and session.stock == 0, "Manual gathering spends the last three units once into player inventory.")
	check(int(Inventory.items.get("clay_lump", 0)) == before_inventory + 3 and int(work.city_tools.items.get("clay_lump", 0)) == before_city, "Manual clay stays player-owned and does not enter City Storage.")
	check(marker.position == original_position, "A manual transaction cannot relocate its own site while settling.")
	get_tree().paused = true
	work.work_finished.emit()
	await get_tree().process_frame
	check(marker.position == original_position and session.stock == 0, "A paused game does not spawn a replacement deposit.")
	get_tree().paused = false
	work.work_finished.emit()
	var started_at: int = session.respawn_started_at
	var due_at: int = session.respawn_due_at
	check(due_at - started_at >= 2880 and due_at - started_at <= 4320, "The committed depletion chooses a delay of 2–3 game days.")
	check(store.save_checkpoint(), "A waiting deposit can be saved: " + store.last_error)
	# Fixture models a later failed relocation before loading this older save.
	# The retry timestamp is transient and must not delay the restored timeline.
	work._last_relocation_attempt[CLAY] = due_at + 7 * 1440
	check(store.load_checkpoint() and session.respawn_due_at == due_at, "Continue preserves the exact waiting deadline.")
	check(not work._last_relocation_attempt.has(CLAY), "Continue discards retry attempts from the later timeline.")
	check(TimeComponentManager.advance_minutes(due_at - work.daily.now() - 1), "Advance to the minute before the saved deadline.")
	await get_tree().process_frame
	check(marker.position == original_position and session.stock == 0, "No replacement appears before its deadline.")
	check(TimeComponentManager.advance_minutes(1), "Advance to the deadline.")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	check(marker.position != original_position and session.stock == 36, "The exhausted deposit is replaced at a temporary test point after the deadline.")
	check(_clear_of_authored_plots(marker), "The replacement does not cover any authored property plot.")
	await _capture("clay-site-after.png")
	var moved_position: Vector2 = marker.position
	check(store.save_checkpoint(), "The relocated deposit saves: " + store.last_error)
	var saved_bytes: PackedByteArray = FileAccess.get_file_as_bytes(store.disk.path)
	var bad_doc: Dictionary = store.snapshot.capture(city)
	var bad_codec = VALUES.new()
	var bad_raw: Dictionary = bad_codec.decode(bad_doc.state)
	bad_raw.worksites.sites.ClaySiteA.offset = Vector2(99999, 99999)
	bad_doc.state = bad_codec.encode(bad_raw)
	check(not store.snapshot.prepare(bad_doc, city) and marker.position == moved_position and session.stock == 36, "An invalid saved location is rejected before changing the live site.")
	bad_raw.worksites.sites.ClaySiteA = 42
	bad_doc.state = bad_codec.encode(bad_raw)
	check(not store.snapshot.prepare(bad_doc, city) and marker.position == moved_position and session.stock == 36, "A malformed stock record is rejected without mutating the live site.")
	session.stock = 19
	marker.position = original_position
	work._refresh_navigation()
	check(store.load_checkpoint(), "The relocated deposit loads over a different live position: " + store.last_error)
	check(marker.position == moved_position and session.stock == 36 and int(Inventory.items.get("clay_lump", 0)) == before_inventory + 3, "Continue restores position, stock, and manual output exactly once.")
	check(store.load_checkpoint() and FileAccess.get_file_as_bytes(store.disk.path) == saved_bytes, "Repeated Continue does not rewrite or duplicate the checkpoint.")

	# A v4 worksite snapshot predates location fields. Its pending output was
	# already city-owned; migration must retain it and never make a ground pile.
	work.daily.pending_output[CLAY] = {"quantity": 5, "drop": work._deliver_daily_output.bind(marker)}
	session.stock = 123
	var doc: Dictionary = store.snapshot.capture(city)
	var codec = VALUES.new()
	var raw: Dictionary = codec.decode(doc.state)
	raw.worksites.schema_version = 4
	for added: String in ["ClaySiteB", "ReedSiteB", "WoodSiteB", "WoodSiteC"]:
		raw.worksites.sites.erase(added)
	for site_id: String in raw.worksites.sites:
		raw.worksites.sites[site_id].erase("offset")
	doc.state = codec.encode(raw)
	var ground_before: int = work.get_node("GroundOutput").get_child_count()
	check(codec.error.is_empty() and store.snapshot.prepare(doc, city), "A synthetic previous-version worksite checkpoint migrates: " + store.snapshot.error)
	check(store.snapshot.prepared.worksites.pending_output.get("ClaySiteA", 0) == 5 and store.snapshot.prepared.worksites.sites.ClaySiteA.stock == 123, "v4 migration preserves pending city output and the exact remaining reserve.")
	store.snapshot.apply_prepared(city)
	check(session.stock == 123 and marker.position == original_position and int(work.daily.pending_output[CLAY].quantity) == 5, "Legacy stock restores at the authored position with no refill.")
	check(work.get_node("GroundOutput").get_child_count() == ground_before, "City-owned v4 pending output does not become player-owned ground output.")
	var city_before_retry: int = int(work.city_tools.items.get("clay_lump", 0))
	var until_midnight: int = 1440 - TimeComponentManager.current_hour * 60 - TimeComponentManager.current_minute
	check(TimeComponentManager.advance_minutes(until_midnight + 1), "Advance across midnight using the actual clock.")
	check(session.stock == 123 and int(work.city_tools.items.get("clay_lump", 0)) == city_before_retry + 5 and not work.daily.pending_output.has(CLAY), "Midnight does not refill a finite site and pending city output settles once.")

	# One employed worker and the player compete for the same last unit.
	var until_open: int = 8 * 60 - TimeComponentManager.current_hour * 60 - TimeComponentManager.current_minute
	check(TimeComponentManager.advance_minutes(until_open), "Reach a real Job Board opening.")
	# The timer test intentionally skips several days without supplying needs.
	# Restore only the fixture applicant so this independent worker test can run.
	var applicant: CitizenData = CitizenManager.get_citizen(WORKER_ID)
	applicant.satisfaction = 0.99
	applicant.employment_status = CitizenData.EmploymentStatus.APPLICANT
	Inventory.add_item("shekel", 9) # Fixture-only funds for a real nine-day contract.
	var worker: WorkerData = WorkerDatabase.hire_applicant(WORKER_ID, 1, 9)
	check(worker != null, "The real Laborer can be hired for the finite-site test.")
	if worker == null:
		_finish()
		return
	check(work.daily.toggle(CLAY, WORKER_ID) and work.daily.start(CLAY, work._deliver_daily_output.bind(marker)), "The paid worker starts a normal daily assignment.")
	var visuals: Node = work.get_node("WorkerVisuals")
	visuals.set_process(false)
	var actor: Node2D = visuals.ensure_actor(WORKER_ID, work.worker_spawn(CLAY, WORKER_ID))
	for _step: int in range(300):
		if worker.physical_approach.get("arrived", false):
			break
		visuals._physical_site_step(CLAY, WORKER_ID, actor, 0.15)
	check(bool(worker.physical_approach.get("arrived", false)), "The worker physically navigates to the old deposit.")
	if not worker.physical_approach.get("arrived", false):
		_finish()
		return
	session.stock = 1
	work.daily.jobs[CLAY].progress[WORKER_ID] = session.minutes_per_unit - 1.0
	var city_before_last: int = int(work.city_tools.items.get("clay_lump", 0))
	var player_before_last: int = int(Inventory.items.get("clay_lump", 0))
	var last_site_position: Vector2 = marker.position
	session.participants.assign(["player"])
	work._selected_site = marker
	var contested: Dictionary = session.execute(180, player, work, work._drop_output)
	check(session.stock == 0 and int(contested.units) == 0 and int(work.city_tools.items.get("clay_lump", 0)) == city_before_last + 1 and int(Inventory.items.get("clay_lump", 0)) == player_before_last, "One contested final unit is awarded once to the worker and City Storage.")
	check(marker.position == last_site_position, "No site moves while the player's work transaction is active.")
	work.work_finished.emit()
	check(await _advance_until_due(session), "The second deposit reaches its deadline on the real clock.")
	check(marker.position != last_site_position and session.stock == 36, "The second exhausted deposit relocates and receives a fresh reserve.")
	check(not bool(worker.physical_approach.get("arrived", true)) and Vector2(worker.physical_approach.target).is_equal_approx(work.worker_destination(CLAY, WORKER_ID)), "The assigned worker must travel to the replacement before working.")
	var final_position: Vector2 = marker.position
	var final_target: Vector2 = worker.physical_approach.target
	check(store.save_checkpoint(), "A travelling worker and relocated deposit save: " + store.last_error)
	marker.position = original_position
	work._refresh_navigation()
	check(store.load_checkpoint(), "A relocated worker checkpoint loads over the original live site: " + store.last_error)
	worker = WorkerDatabase.get_worker_data(WORKER_ID)
	check(marker.position == final_position and worker != null and Vector2(worker.physical_approach.target).is_equal_approx(final_target) and not worker.physical_approach.arrived, "Continue restores the new site and the same in-flight approach.")
	check(int(work.city_tools.items.get("clay_lump", 0)) == city_before_last + 1 and int(Inventory.items.get("clay_lump", 0)) == player_before_last, "Continue does not duplicate the contested unit.")
	var minute_of_day: int = work.daily.now() % 1440
	if minute_of_day < work.daily.SHIFT_START:
		check(TimeComponentManager.advance_minutes(work.daily.SHIFT_START - minute_of_day), "Reach the next shift before checking travel.")
	elif minute_of_day >= work.daily.SHIFT_END - 60:
		check(TimeComponentManager.advance_minutes(1440 - minute_of_day + work.daily.SHIFT_START), "Reach the following shift before checking travel.")
	await get_tree().process_frame
	await get_tree().process_frame
	visuals = work.get_node("WorkerVisuals")
	visuals.set_process(false)
	actor = visuals.ensure_actor(WORKER_ID, work.worker_spawn(CLAY, WORKER_ID))
	for _step: int in range(300):
		if worker.physical_approach.get("arrived", false):
			break
		visuals._physical_site_step(CLAY, WORKER_ID, actor, 0.15)
	check(bool(worker.physical_approach.get("arrived", false)), "The continued worker reaches the replacement deposit physically.")
	if not worker.physical_approach.get("arrived", false):
		_finish()
		return
	check(TimeComponentManager.advance_minutes(60), "Advance normal work before the next depleted deposit.")
	var before_overflow: int = int(work.city_tools.items.get("clay_lump", 0))
	work.city_tools.items["clay_lump"] = 9223372036854775807 # Fixture-only full destination.
	session.stock = 1
	work.daily.jobs[CLAY].progress[WORKER_ID] = session.minutes_per_unit - 1.0
	check(TimeComponentManager.advance_minutes(1), "The worker completes the last unit while City Storage is full.")
	check(session.stock == 0 and int(work.daily.jobs[CLAY].units) == 1 and int(work.city_tools.items["clay_lump"]) == 9223372036854775807, "A refused final receipt remains pending exactly once.")
	check(await _advance_until_due(session), "The deposit with retained output reaches its deadline.")
	check(session.stock == 36 and int(work.daily.jobs[CLAY].units) == 1, "Site relocation keeps the already-earned pending unit.")
	check(store.save_checkpoint() and store.load_checkpoint(), "A relocated site and refused city receipt survive Continue: " + store.last_error)
	check(int(work.daily.jobs[CLAY].units) == 1 and int(work.city_tools.items["clay_lump"]) == 9223372036854775807, "Continue restores pending output and full storage without duplication.")
	work.city_tools.items["clay_lump"] = before_overflow # Fixture frees the capacity again.
	check(TimeComponentManager.advance_minutes(1), "Retry the pending city receipt.")
	check(int(work.daily.jobs[CLAY].units) == 0 and int(work.city_tools.items["clay_lump"]) == before_overflow + 1, "Freed storage receives the retained unit exactly once.")
	check(TimeComponentManager.advance_minutes(1) and int(work.city_tools.items["clay_lump"]) == before_overflow + 1, "Repeated settlement does not duplicate the recovered unit.")
	var other_ids: Array[StringName] = [&"WoodSite", &"ReedSite", &"StrawSite", &"WaterSite"]
	var old_positions: Dictionary = {}
	var latest_due: int = 0
	for site_id: StringName in other_ids:
		var other_marker: Node2D = work.get_node("WorksiteMarkers/" + str(site_id))
		old_positions[site_id] = other_marker.position
		work.sites[site_id].stock = 0
		work._sync_site_timer(site_id) # Explicit fixture depletion after the transaction.
		latest_due = maxi(latest_due, int(work.sites[site_id].respawn_due_at))
	check(TimeComponentManager.advance_minutes(latest_due - work.daily.now()), "Advance all four other deposits to their deadlines.")
	for frame: int in range(10):
		await get_tree().process_frame
	for site_id: StringName in other_ids:
		var other_marker: Node2D = work.get_node("WorksiteMarkers/" + str(site_id))
		var deposit = work.sites[site_id]
		var restored_at_expected_position: bool = other_marker.position == old_positions[site_id] if site_id == &"WoodSite" else other_marker.position != old_positions[site_id]
		check(restored_at_expected_position and deposit.stock == expected_caps[deposit.item_id], "%s restores stock at its expected site." % site_id)
		check(_clear_of_authored_plots(other_marker), "%s does not cover an authored property plot." % site_id)
	_finish()

func _advance_until_due(session) -> bool:
	var remaining: int = session.respawn_due_at - work.daily.now()
	if remaining < 0 or not TimeComponentManager.advance_minutes(remaining):
		return false
	for frame: int in range(4):
		await get_tree().process_frame
	return true

func _clear_of_authored_plots(marker: Node2D) -> bool:
	var bounds := Rect2(marker.global_position - Vector2(20, 20), Vector2(40, 40))
	for child: Node in city.get_node("AuthoredMap/YSortWorld").get_children():
		if child is Sprite2D and str(child.name).begins_with("ToBeClean"):
			if bounds.intersects(child.global_transform * child.get_rect()):
				return false
	return true

func _finish() -> void:
	print("FiniteResourceSitesTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _capture(filename: String) -> void:
	var directory: String = OS.get_environment("TIP_REVIEW_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(directory.path_join(filename)) == OK, "Capture " + filename)
