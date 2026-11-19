extends Node

## Exercises real city runtime and checkpoint owners with isolated test data.
const CITY = preload("res://scenes/content_scene/content_scene.tscn")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const CLAY: StringName = &"ClaySiteA"
const STRAW: StringName = &"StrawSite"
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
	check(_isolated_profile_is_safe(), "Use distinct disposable XDG directories under the sibling citysave_suite_qa directory; no checkpoint operation is allowed otherwise.")
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
	# The authored main map retires Straw from the world but keeps its save
	# ledger. Do not let a runtime availability result define its own oracle.
	check(work.disabled_world_sites == [STRAW] and work.sites.has(STRAW),
		"The authored map disables only StrawSite and retains its compatibility ledger.")
	for site_id: Variant in work.sites:
		var deposit = work.sites[site_id]
		check(deposit.finite_resource and deposit.stock == expected_caps[deposit.item_id], "Each deposit starts with its provisional testing reserve (legacy straw stays compatible).")
		var ready_particles: CPUParticles2D = work.get_node("WorksiteMarkers/%s/ReadyParticles" % str(site_id)) as CPUParticles2D
		if StringName(site_id) != STRAW:
			check(work.is_world_site_available(StringName(site_id)) and ready_particles != null
				and ready_particles.visible and ready_particles.emitting,
				"%s starts ready with its particle cue." % str(site_id))
	_check_retained_straw_presentation("startup")
	var straw_record: Dictionary = store.snapshot._sites.capture(work).sites[str(STRAW)].duplicate(true)
	# A full reserve and a requested ready presentation must not re-enable a
	# retired source or mutate its persisted stock/deadline/offset record.
	work._set_site_depleted_presentation(STRAW, false)
	work.sync_resource_presentation()
	await get_tree().process_frame
	await get_tree().process_frame
	_check_retained_straw_presentation("ready refresh")
	check(store.snapshot._sites.capture(work).sites[str(STRAW)] == straw_record,
		"Refreshing retired Straw presentation preserves its complete saved site record.")
	var reed_marker: Node2D = work.get_node("WorksiteMarkers/ReedSite")
	var reed_icon: Sprite2D = reed_marker.get_node("ResourceIcon") as Sprite2D
	var reed_cut: Sprite2D = reed_marker.get_node("CuttedReed") as Sprite2D
	var reed_particles: CPUParticles2D = reed_marker.get_node("ReadyParticles") as CPUParticles2D
	var reed_collider: CollisionPolygon2D = reed_marker.get_node("ResourceBase/CollisionPolygon2D") as CollisionPolygon2D
	check(_sprite_opaque_bottom(reed_icon).distance_to(_sprite_opaque_bottom(reed_cut)) <= 0.01, "Cut reed art shares the live icon's opaque-bottom feet anchor.")
	work._set_site_depleted_presentation(&"ReedSite", true)
	check(not reed_icon.visible and reed_cut.visible and not reed_particles.visible and not reed_particles.emitting, "A depleted reed shows cut art and stops its ready particles.")
	work._set_site_depleted_presentation(&"ReedSite", false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not reed_collider.disabled and reed_icon.visible and not reed_cut.visible and reed_particles.visible and reed_particles.emitting, "Same-frame depletion then recovery leaves reed collision, art, and particles ready.")
	work._set_site_depleted_presentation(&"ReedSite", true)
	await get_tree().process_frame
	await get_tree().process_frame
	check(reed_collider.disabled and not reed_icon.visible and reed_cut.visible and not reed_particles.visible and not reed_particles.emitting, "A settled depleted reed has disabled collision, cut art, and no particles.")
	work._set_site_depleted_presentation(&"ReedSite", false)
	work._set_site_depleted_presentation(&"ReedSite", true)
	await get_tree().process_frame
	await get_tree().process_frame
	check(reed_collider.disabled and not reed_icon.visible and reed_cut.visible and not reed_particles.visible and not reed_particles.emitting, "Same-frame recovery then depletion leaves reed collision, art, and particles depleted.")
	work._set_site_depleted_presentation(&"ReedSite", false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not reed_collider.disabled and reed_icon.visible and not reed_cut.visible and reed_particles.visible and reed_particles.emitting, "A ready reed restores its collision, normal art, and readiness particles.")
	var wood_marker: Node2D = work.get_node("WorksiteMarkers/WoodSite")
	work._set_site_depleted_presentation(&"WoodSite", true)
	check(not wood_marker.get_node("WoodGrove/Tree0").visible and wood_marker.get_node("WoodGrove/Stump0").visible, "A depleted wood site shows stumps instead of trees.")
	work._set_site_depleted_presentation(&"WoodSite", false)
	check(wood_marker.get_node("WoodGrove/Tree0").visible and not wood_marker.get_node("WoodGrove/Stump0").visible, "A ready wood site restores its grove.")
	var reed_session = work.sites[&"ReedSite"]
	reed_session.participants.assign(["player"])
	reed_session.stock = 1
	var cancellation_started: bool = reed_session._begin(180, player, work._drop_output)
	check(cancellation_started, "The hourly plan begins for cancellation coverage.")
	if cancellation_started:
		# Model its final earned unit before settlement, then exercise the real
		# cancel() refund and stock_settled callback path.
		reed_session._result.units = 1
		reed_session.stock = 0
		work._sync_site_timer(&"ReedSite")
		check(not reed_icon.visible and reed_cut.visible and not reed_particles.visible, "An in-flight depletion switches reed art and stops particles.")
		reed_session.cancel()
		check(reed_session.stock == 1 and reed_session.respawn_started_at == -1 and reed_session.respawn_due_at == -1, "Cancelling restores the unsettled reed unit and clears its deadline.")
	check(reed_icon.visible and not reed_cut.visible and reed_particles.visible and reed_particles.emitting, "Cancellation leaves reed art and readiness particles ready.")
	reed_session.participants.clear()
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
	var authored_position: Vector2 = marker.position
	# A legacy save may already carry a valid nonzero offset. Refill must keep it.
	var legacy_offset: Vector2 = Vector2(48, 0)
	marker.position = authored_position + legacy_offset
	work._refresh_navigation()
	var original_position: Vector2 = marker.position
	check(work.resource_site_offset(CLAY) == legacy_offset and work.resource_offset_valid(legacy_offset, CLAY), "A previously saved nonzero site offset remains valid.")
	# Arrange a nearly exhausted deposit; the actual manual work loop owns output.
	session.stock = 3
	session.participants.assign(["player"])
	work._selected_site = marker
	var result: Dictionary = session.execute(180, player, work, work._drop_output)
	check(int(result.units) == 3 and int(result.to_bag) == 3 and session.stock == 0, "Manual gathering spends the last three units once into player inventory.")
	check(int(Inventory.items.get("clay_lump", 0)) == before_inventory + 3 and int(work.city_tools.items.get("clay_lump", 0)) == before_city, "Manual clay stays player-owned and does not enter City Storage.")
	check(marker.position == original_position, "A manual transaction cannot relocate its own site while settling.")
	check(not marker.get_node("ResourceIcon").visible and not marker.get_node("ReadyParticles").emitting, "A depleted clay site immediately hides its normal art and readiness particles.")
	get_tree().paused = true
	work.work_finished.emit()
	await get_tree().process_frame
	check(marker.position == original_position and session.stock == 0, "A paused game does not spawn a replacement deposit.")
	get_tree().paused = false
	work.work_finished.emit()
	var started_at: int = session.respawn_started_at
	var due_at: int = session.respawn_due_at
	check(due_at - started_at >= 2880 and due_at - started_at <= 4320, "The committed depletion chooses a delay of 2–3 game days.")
	var waiting_saved: bool = store.save_checkpoint()
	check(waiting_saved, "A waiting deposit can be saved: " + store.last_error)
	if not waiting_saved:
		_finish()
		return
	# Fixture models a later failed relocation before loading this older save.
	# The retry timestamp is transient and must not delay the restored timeline.
	work._last_relocation_attempt[CLAY] = due_at + 7 * 1440
	var waiting_loaded: bool = store.load_checkpoint()
	check(waiting_loaded and session.respawn_due_at == due_at, "Continue preserves the exact waiting deadline.")
	if not waiting_loaded:
		_finish()
		return
	_check_retained_straw_presentation("waiting checkpoint Continue")
	check(not work._last_relocation_attempt.has(CLAY), "Continue discards retry attempts from the later timeline.")
	check(TimeComponentManager.advance_minutes(due_at - work.daily.now() - 1), "Advance to the minute before the saved deadline.")
	await get_tree().process_frame
	check(marker.position == original_position and session.stock == 0, "No replacement appears before its deadline.")
	var base: CollisionPolygon2D = marker.get_node("ResourceBase/CollisionPolygon2D") as CollisionPolygon2D
	var occupancy_center: Vector2 = Vector2.ZERO
	for point: Vector2 in base.polygon:
		occupancy_center += base.to_global(point)
	occupancy_center /= base.polygon.size()
	var player_shape: CollisionShape2D = player.get_node("CollisionShape2D") as CollisionShape2D
	var player_shape_offset: Vector2 = player_shape.global_position - player.global_position
	player.global_position = occupancy_center - player_shape_offset
	check(TimeComponentManager.advance_minutes(1), "Advance to the deadline.")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	check(marker.position == original_position and session.stock == 0, "An occupied depleted site waits at its saved position past the deadline.")
	player.global_position = marker.global_position + Vector2(300, 300)
	work._queue_depleted_sites()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	check(marker.position == original_position and session.stock == 36, "Once clear, the site refills at the same saved location with full capacity.")
	check(marker.get_node("ResourceIcon").visible and marker.get_node("ReadyParticles").emitting, "The refilled clay site shows normal art and readiness particles.")
	await _capture("clay-site-after.png")
	var moved_position: Vector2 = marker.position
	var refilled_saved: bool = store.save_checkpoint()
	check(refilled_saved, "The refilled deposit saves: " + store.last_error)
	if not refilled_saved:
		_finish()
		return
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
	marker.position = authored_position
	work._refresh_navigation()
	var offset_loaded: bool = store.load_checkpoint()
	check(offset_loaded, "The previously offset deposit loads over a different live position: " + store.last_error)
	if not offset_loaded:
		_finish()
		return
	check(marker.position == moved_position and session.stock == 36 and int(Inventory.items.get("clay_lump", 0)) == before_inventory + 3, "Continue restores position, stock, and manual output exactly once.")
	var repeated_offset_loaded: bool = store.load_checkpoint()
	check(repeated_offset_loaded and FileAccess.get_file_as_bytes(store.disk.path) == saved_bytes, "Repeated Continue does not rewrite or duplicate the checkpoint.")
	if not repeated_offset_loaded:
		_finish()
		return

	_check_retained_straw_presentation("repeated checkpoint Continue")

	# A v4 worksite snapshot predates the current authored-site catalog. This
	# fixture intentionally lacks entries in the static legacy registry, so the
	# validator must reject it without changing live state or pending output.
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
	var legacy_prepared: bool = store.snapshot.prepare(doc, city)
	check(codec.error.is_empty() and not legacy_prepared, "A v4 worksite snapshot with a mismatched legacy catalog is safely rejected: " + store.snapshot.error)
	check(session.stock == 123 and marker.position == moved_position and int(work.daily.pending_output[CLAY].quantity) == 5, "Rejected legacy data leaves live reserve, fixed location, and pending city output unchanged.")
	check(work.get_node("GroundOutput").get_child_count() == ground_before, "Rejected legacy data does not create a player-owned ground pile.")
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
	var retained_target: Vector2 = worker.physical_approach.target
	_move_worker_and_player_clear(marker, worker, actor)
	check(await _advance_until_due(session), "The second deposit reaches its deadline on the real clock.")
	check(marker.position == last_site_position and session.stock == 36, "The second exhausted deposit refills at its fixed location.")
	check(not bool(worker.physical_approach.get("arrived", true)) and Vector2(worker.physical_approach.target).is_equal_approx(retained_target) and Vector2(worker.physical_approach.target).is_equal_approx(work.worker_destination(CLAY, WORKER_ID)), "The assigned worker keeps its existing approach target at the fixed site.")
	var final_position: Vector2 = marker.position
	var final_target: Vector2 = worker.physical_approach.target
	var worker_saved: bool = store.save_checkpoint()
	check(worker_saved, "A travelling worker and fixed deposit save: " + store.last_error)
	if not worker_saved:
		_finish()
		return
	marker.position = original_position
	work._refresh_navigation()
	var worker_loaded: bool = store.load_checkpoint()
	check(worker_loaded, "A fixed-site worker checkpoint loads over a different live offset: " + store.last_error)
	if not worker_loaded:
		_finish()
		return
	worker = WorkerDatabase.get_worker_data(WORKER_ID)
	check(marker.position == final_position and worker != null and Vector2(worker.physical_approach.target).is_equal_approx(final_target) and not worker.physical_approach.arrived, "Continue restores the fixed site and the same in-flight approach.")
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
	check(bool(worker.physical_approach.get("arrived", false)), "The continued worker reaches the same fixed deposit physically.")
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
	_move_worker_and_player_clear(marker, worker, actor)
	check(await _advance_until_due(session), "The deposit with retained output reaches its deadline.")
	check(marker.position == final_position and session.stock == 36 and int(work.daily.jobs[CLAY].units) == 1, "Fixed-site refill keeps the already-earned pending unit.")
	var receipt_saved: bool = store.save_checkpoint()
	check(receipt_saved, "A fixed site and refused city receipt save: " + store.last_error)
	if not receipt_saved:
		_finish()
		return
	var receipt_loaded: bool = store.load_checkpoint()
	check(receipt_loaded, "A fixed site and refused city receipt load: " + store.last_error)
	if not receipt_loaded:
		_finish()
		return
	check(int(work.daily.jobs[CLAY].units) == 1 and int(work.city_tools.items["clay_lump"]) == 9223372036854775807, "Continue restores pending output and full storage without duplication.")
	work.city_tools.items["clay_lump"] = before_overflow # Fixture frees the capacity again.
	check(TimeComponentManager.advance_minutes(1), "Retry the pending city receipt.")
	check(int(work.daily.jobs[CLAY].units) == 0 and int(work.city_tools.items["clay_lump"]) == before_overflow + 1, "Freed storage receives the retained unit exactly once.")
	check(TimeComponentManager.advance_minutes(1) and int(work.city_tools.items["clay_lump"]) == before_overflow + 1, "Repeated settlement does not duplicate the recovered unit.")
	var other_ids: Array[StringName] = []
	for key: Variant in work.sites:
		var candidate_id: StringName = StringName(key)
		if candidate_id != CLAY:
			other_ids.append(candidate_id)
	var old_positions: Dictionary = {}
	var initial_plot_relationships: Dictionary = {}
	var latest_due: int = 0
	for site_id: StringName in other_ids:
		var other_marker: Node2D = work.get_node("WorksiteMarkers/" + str(site_id))
		old_positions[site_id] = other_marker.position
		initial_plot_relationships[site_id] = _authored_plot_relationship(other_marker)
		work.sites[site_id].stock = 0
		work._sync_site_timer(site_id) # Explicit fixture depletion after the transaction.
		latest_due = maxi(latest_due, int(work.sites[site_id].respawn_due_at))
	check(TimeComponentManager.advance_minutes(latest_due - work.daily.now()), "Advance every other finite deposit to its deadline.")
	for frame: int in range(10):
		await get_tree().process_frame
	for site_id: StringName in other_ids:
		var other_marker: Node2D = work.get_node("WorksiteMarkers/" + str(site_id))
		var deposit = work.sites[site_id]
		check(other_marker.position == old_positions[site_id] and deposit.stock == expected_caps[deposit.item_id], "%s refills its full reserve at the same fixed location." % site_id)
		check(_authored_plot_relationship(other_marker) == initial_plot_relationships[site_id], "%s keeps its initial authored-placeholder relationship through refill." % site_id)
	# A live worker sprite at the site's physical base must delay an overdue refill.
	# Move the saved pose and player clear so only the visible actor exercises this guard.
	visuals = work.get_node("WorkerVisuals")
	var visuals_was_processing: bool = visuals.is_processing()
	visuals.set_process(false)
	worker = WorkerDatabase.get_worker_data(WORKER_ID)
	var assigned_job: Dictionary = work.daily.jobs.get(CLAY, {})
	var assigned_ids: Array = assigned_job.get("ids", [])
	check(worker != null and assigned_ids.has(WORKER_ID), "The overlap fixture retains its assigned worker after checkpoint load.")
	if worker == null or not assigned_ids.has(WORKER_ID):
		_finish()
		return
	actor = visuals.actors.get(WORKER_ID) as Node2D
	if not is_instance_valid(actor) or actor.is_queued_for_deletion():
		visuals.actors.erase(WORKER_ID)
		actor = visuals.ensure_actor(WORKER_ID, work.worker_spawn(CLAY, WORKER_ID))
	if not is_instance_valid(actor):
		check(false, "The assigned worker actor is available for the overlap fixture.")
		_finish()
		return
	var overlap_position: Vector2 = marker.position
	var overlap_base: CollisionPolygon2D = marker.get_node("ResourceBase/CollisionPolygon2D") as CollisionPolygon2D
	var overlap_center: Vector2 = Vector2.ZERO
	for point: Vector2 in overlap_base.polygon:
		overlap_center += overlap_base.to_global(point)
	overlap_center /= overlap_base.polygon.size()
	player.global_position = marker.global_position + Vector2(300, 300)
	worker.physical_approach.position = marker.global_position + Vector2(300, 300)
	for other_actor: Node2D in visuals.actors.values():
		if other_actor != actor and is_instance_valid(other_actor):
			other_actor.global_position = marker.global_position + Vector2(300, 300)
	actor.show()
	actor.global_position = overlap_center - Vector2(0, 16)
	check(actor.visible and visuals.actors.get(WORKER_ID) == actor, "The overlapping worker remains a visible live actor.")
	_make_site_overdue(CLAY)
	await _wait_resource_frames()
	check(not work._site_regrowth_clear(marker), "A visible worker actor at a depleted site's base blocks regrowth.")
	work._queue_depleted_sites()
	await _wait_resource_frames()
	check(marker.position == overlap_position and session.stock == 0, "An overdue deposit stays empty and fixed while a worker actor overlaps it.")
	actor.global_position = marker.global_position + Vector2(300, 300)
	work._queue_depleted_sites()
	await _wait_resource_frames()
	check(marker.position == overlap_position and session.stock == session.deposit_capacity and not overlap_base.disabled, "The same site refills at full capacity with collision restored after the visible worker clears it.")

	# A saved approach pose must also protect the site before its actor exists.
	# Remove the real actor, keep the worker assigned, and clear every other actor.
	var saved_pose_actor: Node2D = visuals.actors.get(WORKER_ID) as Node2D
	if saved_pose_actor != null:
		visuals.actors.erase(WORKER_ID)
		saved_pose_actor.queue_free()
	for other_actor: Node2D in visuals.actors.values():
		if is_instance_valid(other_actor):
			other_actor.global_position = marker.global_position + Vector2(300, 300)
	await get_tree().process_frame
	worker = WorkerDatabase.get_worker_data(WORKER_ID)
	worker.physical_approach.position = overlap_center
	_make_site_overdue(CLAY)
	await _wait_resource_frames()
	check(not visuals.actors.has(WORKER_ID) and not work._site_regrowth_clear(marker), "An assigned worker's saved physical pose blocks regrowth before its actor is created.")
	work._queue_depleted_sites()
	await _wait_resource_frames()
	check(marker.position == overlap_position and session.stock == 0, "An overdue deposit stays empty and fixed while only the worker's saved pose overlaps it.")
	worker.physical_approach.position = marker.global_position + Vector2(300, 300)
	work._queue_depleted_sites()
	await _wait_resource_frames()
	check(marker.position == overlap_position and session.stock == session.deposit_capacity and not overlap_base.disabled, "The same site refills at full capacity with collision restored after the saved worker pose clears.")
	visuals.set_process(visuals_was_processing)

	var colliderless_marker: Node2D = work.get_node("WorksiteMarkers/ClaySiteB")
	var colliderless_base: Node = colliderless_marker.get_node("ResourceBase")
	colliderless_base.queue_free()
	await get_tree().process_frame
	var colliderless_icon: Sprite2D = colliderless_marker.get_node("ResourceIcon") as Sprite2D
	var icon_bounds: Rect2 = colliderless_icon.global_transform * colliderless_icon.get_rect()
	var fallback_player_shape: CollisionShape2D = player.get_node("CollisionShape2D") as CollisionShape2D
	var fallback_player_shape_offset: Vector2 = fallback_player_shape.global_position - player.global_position
	player.global_position = icon_bounds.get_center() - fallback_player_shape_offset
	check(not work._site_regrowth_clear(colliderless_marker), "A colliderless site still defers while a player overlaps its art bounds.")
	player.global_position = icon_bounds.position + Vector2(-100, -100)
	check(work._site_regrowth_clear(colliderless_marker), "A colliderless site can recover after its art bounds clear.")
	_finish()

func _advance_until_due(session) -> bool:
	var remaining: int = session.respawn_due_at - work.daily.now()
	if remaining < 0 or not TimeComponentManager.advance_minutes(remaining):
		return false
	for frame: int in range(4):
		await get_tree().process_frame
	return true

func _make_site_overdue(site_id: StringName) -> void:
	var session = work.sites[site_id]
	var now: int = work.daily.now()
	session.stock = 0
	session.respawn_started_at = now - 2881
	session.respawn_due_at = now - 1
	work._set_site_depleted_presentation(site_id, true)

func _wait_resource_frames() -> void:
	for _frame: int in range(4):
		await get_tree().process_frame

func _authored_plot_relationship(marker: Node2D) -> Array[StringName]:
	var bounds := Rect2(marker.global_position - Vector2(20, 20), Vector2(40, 40))
	var relationship: Array[StringName] = []
	for child: Node in city.get_node("AuthoredMap/YSortWorld").get_children():
		if child is Sprite2D and str(child.name).begins_with("ToBeClean"):
			if bounds.intersects(child.global_transform * child.get_rect()):
				relationship.append(StringName(child.name))
	return relationship

func _sprite_opaque_bottom(sprite: Sprite2D) -> Vector2:
	var image: Image = sprite.texture.get_image()
	var used: Rect2i = image.get_used_rect()
	var offset: Vector2 = sprite.offset - Vector2(image.get_size()) * 0.5 if sprite.centered else sprite.offset
	return sprite.position + sprite.transform.basis_xform(Vector2(0, used.end.y + offset.y))

func _move_worker_and_player_clear(marker: Node2D, worker: WorkerData, actor: Node2D) -> void:
	var worker_feet: Vector2 = marker.global_position + Vector2(120, 0)
	var approach: Dictionary = worker.physical_approach
	worker.begin_physical_approach(str(approach.kind), str(approach.task), str(approach.owner), worker_feet, Vector2(approach.target))
	actor.global_position = worker_feet - Vector2(0, 16)
	player.global_position = marker.global_position + Vector2(300, 300)

func _check_retained_straw_presentation(context: String) -> void:
	var marker: Node2D = work.get_node("WorksiteMarkers/StrawSite")
	var particles: CPUParticles2D = marker.get_node("ReadyParticles")
	var collider: CollisionPolygon2D = marker.get_node("ResourceBase/CollisionPolygon2D")
	check(not work.is_world_site_available(STRAW) and not work.daily.is_site_available(STRAW),
		"Retired Straw stays unavailable for world interaction and new work: " + context)
	check(not marker.is_visible_in_tree() and not particles.visible and not particles.emitting,
		"Retired Straw has no visible marker or readiness emitter: " + context)
	check(collider.disabled, "Retired Straw has no invisible collision: " + context)
	check(work.sites[STRAW].finite_resource and work.sites[STRAW].stock == 72
		and work.sites[STRAW].deposit_capacity == 72,
		"Retired Straw retains its untouched compatibility reserve: " + context)

func _isolated_profile_is_safe() -> bool:
	var qa_root: String = ProjectSettings.globalize_path("res://../citysave_suite_qa").simplify_path()
	var homes: Array[String] = []
	for variable: String in ["XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		var home: String = OS.get_environment(variable).simplify_path()
		if home.is_empty() or not home.is_absolute_path() or not DirAccess.dir_exists_absolute(home) \
			or not home.begins_with(qa_root + "/") or homes.has(home):
			return false
		homes.append(home)
	return ProjectSettings.globalize_path("user://").simplify_path().begins_with(homes[0] + "/")

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
