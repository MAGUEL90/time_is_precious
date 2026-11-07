extends Node

## Internal review sandbox. This is not the playable city's respawn system.
## Every save path below is dedicated to the lab and never the user's slot.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const PLAN = preload("res://scenes/content_scene/worksites/timed_deposit_plan.gd")
const LAB_UI = preload("res://scenes/test_scenes/resource_respawn_lab_ui.gd")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const SNAPSHOT = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const SAVE_FILE = preload("res://scenes/new_scenes/save_game/city_save_file.gd")
const DEBUG_SAVE_PATH: String = "user://debug_resource_respawn_lab/checkpoint.json"
const DEBUG_AUTO_PATH: String = "user://debug_resource_respawn_lab/city_autosave.json"
const TEST_CAPACITY: int = 6 # Deliberately arbitrary fixture data, not game balance.
const TEST_WORKER_ID: String = "initial_workshop_laborer"
const TEST_SITES: Dictionary = {
	"ClaySiteA": {"label": "Clay"},
	"WoodSite": {"label": "Wood"},
	"ReedSite": {"label": "Reed"},
	"WaterSite": {"label": "Water"},
}

var city: Node2D
var work: Node
var ui: CanvasLayer
var snapshot = SNAPSHOT.new()
var debug_disk = SAVE_FILE.new()
var plans: Dictionary = {}
var selected_site: String = "ClaySiteA"
var rng := RandomNumberGenerator.new()
var ready_for_test: bool = false
var busy: bool = false
var last_message: String = ""

func _ready() -> void:
	if not OS.is_debug_build():
		push_error("The resource respawn lab requires a debug build.")
		get_tree().quit(1)
		return
	_setup.call_deferred()

func _setup() -> void:
	# Use the real game clock. The debug completion button itself does not
	# advance the calendar or silently charge needs and contracts.
	TimeComponentManager.is_paused = false
	TimeComponentManager.set_process(true)
	city = CITY.instantiate()
	add_child(city)
	await get_tree().process_frame
	await get_tree().process_frame
	work = city.get_node("YSortWorld/WorkerRuntime")
	# Disable the old immediate-respawn policy in this lab only. The session
	# itself remains finite; timers below are explicitly driven by lab buttons.
	work.finite_resource_sites = false
	var city_store: Node = WorkStateRuntime.get_node("CitySave")
	city_store.disk.path = DEBUG_AUTO_PATH
	city_store.refresh_checkpoint_slot()
	debug_disk.path = DEBUG_SAVE_PATH
	rng.randomize()
	for id: String in TEST_SITES:
		var session = work.sites[StringName(id)]
		session.deposit_capacity = TEST_CAPACITY
		session.stock = TEST_CAPACITY
		var plan = PLAN.new()
		if not plan.initialize_stock(TEST_CAPACITY, TEST_CAPACITY):
			push_error("Could not initialize the isolated debug deposit: " + plan.last_error)
			get_tree().quit(1)
			return
		plans[id] = plan
	# The lab owns these timers; the original immediate-respawn callback above
	# is disabled. Sync completed worker output after the normal settlement.
	work.daily.settlement_finished.connect(_sync_plans_after_daily)
	TimeComponentManager.minute_changed.connect(_on_lab_minute)
	ui = CanvasLayer.new()
	ui.set_script(LAB_UI)
	add_child(ui)
	var entries: Array[Dictionary] = []
	for id: String in TEST_SITES:
		entries.append({"id": id, "label": TEST_SITES[id].label})
	ui.set_sites(entries)
	ui.site_selected.connect(_on_site_selected)
	ui.add_worker_requested.connect(_add_test_worker)
	ui.deplete_requested.connect(_deplete_selected)
	ui.finish_requested.connect(_finish_selected)
	ui.save_requested.connect(_save_debug)
	ui.continue_requested.connect(_continue_debug)
	ready_for_test = true
	_show("Finish Timer skips only this lab timer; game time is not advanced.")

func _exit_tree() -> void:
	if TimeComponentManager.minute_changed.is_connected(_on_lab_minute):
		TimeComponentManager.minute_changed.disconnect(_on_lab_minute)

func _sync_plans_after_daily() -> void:
	if not ready_for_test or busy:
		return
	for id: String in TEST_SITES:
		var remaining: int = int(work.sites[StringName(id)].stock)
		var plan = plans[id]
		if remaining == 0 and not plan.is_respawn_pending():
			if not plan.record_depletion_after_commit(work.daily.now(), rng):
				push_error("Could not record a debug depletion: " + plan.last_error)
			else:
				_sync_session_timer(id)
		elif remaining > 0 and remaining < plan.get_stock() and not plan.is_respawn_pending():
			if not plan.update_remaining_stock_after_commit(remaining, TEST_CAPACITY):
				push_error("Could not record debug stock: " + plan.last_error)

func _on_lab_minute(_minute: int) -> void:
	if not ready_for_test or busy:
		return
	# On a normal due minute the same explicit test-point checks apply. If a
	# point is unavailable, leave the deposit empty and try on a later minute.
	for id: String in TEST_SITES:
		var plan = plans[id]
		if plan.is_respawn_pending() and work.daily.now() >= plan.get_respawn_due_minute():
			_finish_site(id, false)
	_render_state()

func _on_site_selected(id: String) -> void:
	if TEST_SITES.has(id):
		selected_site = id
		_show("")

func _add_test_worker() -> bool:
	if not ready_for_test or busy:
		return false
	var id := StringName(selected_site)
	var worker: WorkerData = WorkerDatabase.get_worker_data(TEST_WORKER_ID)
	if worker == null:
		Inventory.add_item("shekel", 3) # Explicit fixture-only contract funding.
		worker = WorkerDatabase.hire_applicant(TEST_WORKER_ID)
	if worker == null:
		_show("Test worker could not be hired. Restart the lab during Job Board hours.")
		return false
	if work.daily.jobs.has(id) and work.daily.jobs[id].ids.has(TEST_WORKER_ID):
		_show("Test worker is already assigned to this site.")
		return true
	if not work.daily.toggle(id, TEST_WORKER_ID):
		_show("Test worker is busy. Restart the lab to choose another site.")
		return false
	var marker: Node2D = work.get_node("WorksiteMarkers/" + selected_site)
	if not work.daily.start(id, work._deliver_daily_output.bind(marker)):
		_show("Could not start the test worker assignment.")
		return false
	_show("A paid fixture worker is assigned and will walk to the site.")
	return true

func _deplete_selected() -> bool:
	if not ready_for_test or busy:
		return false
	var id := StringName(selected_site)
	var session = work.sites[id]
	var plan = plans[selected_site]
	if plan.is_respawn_pending() or int(session.stock) <= 0:
		_show("This test deposit is already empty.")
		return false
	if session.working or work._working or work.daily.is_settlement_busy():
		_show("Wait until the current work transaction finishes.")
		return false
	# This debug command discards fixture stock; it never credits that stock to
	# either inventory and does not change any normal game's resource balance.
	if not plan.record_depletion_after_commit(work.daily.now(), rng):
		_show("Could not start the debug timer: " + plan.last_error)
		return false
	session.stock = 0
	_sync_session_timer(selected_site)
	work._set_site_depleted_presentation(id, true)
	work.daily._sync_activities()
	_show("Fixture stock was emptied; the timer is running in the debug state.")
	return true

func _finish_selected() -> bool:
	if not ready_for_test or busy:
		return false
	return _finish_site(selected_site, true)

func _finish_site(site_id: String, force_debug: bool) -> bool:
	var id := StringName(site_id)
	var plan = plans[site_id]
	if not plan.is_respawn_pending():
		if force_debug:
			_show("Empty this test deposit first.")
		return false
	var marker: Node2D = work.get_node("WorksiteMarkers/" + site_id)
	var current_offset: Vector2 = work.resource_site_offset(id)
	var target_offset := Vector2.INF
	var is_wood: bool = work.sites[id].item_id == "wood_log"
	if is_wood:
		if work._wood_regrowth_clear(marker):
			target_offset = current_offset
	else:
		# Other resources retain the explicit temporary placement policy.
		for point: Vector2 in work.TEMP_RELOCATION_POINTS:
			var offset: Vector2 = point - Vector2(work._site_origins[id])
			if offset == current_offset:
				continue
			var candidate: Vector2 = marker.get_parent().to_global(Vector2(work._site_origins[id]) + offset)
			if work._resource_candidate_clear(city, marker, candidate):
				target_offset = offset
				break
	if not target_offset.is_finite():
		if force_debug:
			_show("The site is not safe; move the player or worker and retry.")
		return false
	# Pass the saved due minute to the prototype, rather than advancing the real
	# clock. This deliberately bypasses waiting only inside this debug scene.
	var effective_minute: int = plan.get_respawn_due_minute() if force_debug else work.daily.now()
	if not plan.try_refill(effective_minute, true, TEST_CAPACITY):
		_show("The debug timer could not finish: " + plan.last_error)
		return false
	marker.position = Vector2(work._site_origins[id]) + target_offset
	work.sites[id].stock = plan.get_stock()
	_sync_session_timer(site_id)
	work._set_site_depleted_presentation(id, false)
	if is_wood:
		_show("Timer completed. Wood regrew at the same site.")
	else:
		work.worker_journeys.clear()
		work._refresh_navigation()
		if work.daily.jobs.has(id):
			var ids: Array[String] = []
			ids.assign(work.daily.jobs[id].ids)
			work._begin_site_assignments(id, ids)
		_show("Timer completed. Assigned workers walk to the temporary test point.")
	return true

func _sync_session_timer(site_id: String) -> void:
	var session = work.sites[StringName(site_id)]
	var plan = plans[site_id]
	session.respawn_started_at = plan.get_depleted_at_minute()
	session.respawn_due_at = plan.get_respawn_due_minute()

func _lab_payload() -> Dictionary:
	var city_document: Dictionary = snapshot.capture(city)
	if city_document.is_empty():
		last_message = snapshot.error
		return {}
	var saved_plans: Dictionary = {}
	for id: String in TEST_SITES:
		saved_plans[id] = plans[id].to_save_value()
		if saved_plans[id].is_empty():
			last_message = plans[id].last_error
			return {}
	return {"city": city_document, "plans": saved_plans, "selected_site": selected_site,
		"rng_seed": rng.seed, "rng_state": rng.state}

func _stage_debug(document: Dictionary) -> Dictionary:
	if document.size() != 2 or document.get("format") != "resource_respawn_lab_v1" or not document.has("payload"):
		return {}
	var values = VALUES.new()
	var raw: Variant = values.decode(document.payload)
	if not values.error.is_empty() or not raw is Dictionary or raw.size() != 5:
		return {}
	if not raw.get("city") is Dictionary or not raw.get("plans") is Dictionary \
		or not raw.get("selected_site") is String or not TEST_SITES.has(raw.selected_site) \
		or not raw.get("rng_seed") is int or not raw.get("rng_state") is int \
		or raw.plans.size() != TEST_SITES.size():
		return {}
	if not snapshot.prepare(raw.city, city):
		return {}
	var saved_clock: Dictionary = snapshot.prepared.clock
	var saved_minute: int = int(saved_clock.current_day) * 1440 + int(saved_clock.current_hour) * 60 + int(saved_clock.current_minute)
	var staged_plans: Dictionary = {}
	for id: String in TEST_SITES:
		if not raw.plans.has(id) or not snapshot.prepared.worksites.sites.has(id):
			return {}
		var plan = PLAN.new()
		if not plan.restore_from_save_value(raw.plans[id], TEST_CAPACITY, saved_minute) \
			or plan.get_stock() != int(snapshot.prepared.worksites.sites[id].stock):
			return {}
		if plan.is_respawn_pending():
			var site: Dictionary = snapshot.prepared.worksites.sites[id]
			if int(site.get("respawn_started_at", -1)) != plan.get_depleted_at_minute() \
				or int(site.get("respawn_due_at", -1)) != plan.get_respawn_due_minute():
				return {}
		staged_plans[id] = plan
	return {"plans": staged_plans, "selected_site": raw.selected_site,
		"rng_seed": raw.rng_seed, "rng_state": raw.rng_state}

func _valid_debug(document: Dictionary) -> bool:
	return not _stage_debug(document).is_empty()

func _save_debug() -> bool:
	if not ready_for_test or busy:
		return false
	var payload: Dictionary = _lab_payload()
	if payload.is_empty():
		_show("Cannot capture the test state: " + last_message)
		return false
	var values = VALUES.new()
	var document: Dictionary = {"format": "resource_respawn_lab_v1", "payload": values.encode(payload)}
	if not values.error.is_empty():
		_show("Cannot encode the test state: " + values.error)
		return false
	# A dedicated disk helper uses the project's existing safe-write protocol.
	debug_disk.read_snapshot(_valid_debug)
	if debug_disk.error not in ["", "missing"] or not debug_disk.write_snapshot(document, _valid_debug):
		_show("Cannot save the debug slot: " + debug_disk.error)
		return false
	_show("Saved to the isolated debug slot, not the player's save.")
	return true

func _continue_debug() -> bool:
	if not ready_for_test or busy:
		return false
	var document: Dictionary = debug_disk.read_snapshot(_valid_debug)
	if document.is_empty():
		_show("Cannot load the debug slot: " + debug_disk.error)
		return false
	var staged: Dictionary = _stage_debug(document)
	if staged.is_empty():
		_show("The debug state is invalid; nothing was restored.")
		return false
	snapshot.apply_prepared(city)
	plans = staged.plans
	for id: String in TEST_SITES:
		work._set_site_depleted_presentation(StringName(id), plans[id].is_respawn_pending())
	selected_site = staged.selected_site
	rng.seed = staged.rng_seed
	rng.state = staged.rng_state
	ui.select_site(selected_site)
	_show("Restored the debug slot and its original timer; game save untouched.")
	return true

func _show(message: String) -> void:
	last_message = message
	_render_state()

func _render_state() -> void:
	if not is_instance_valid(ui) or not plans.has(selected_site):
		return
	var plan = plans[selected_site]
	var text: String = "%s · test stock %d/%d" % [TEST_SITES[selected_site].label, plan.get_stock(), TEST_CAPACITY]
	if plan.is_respawn_pending():
		var remaining: int = maxi(0, plan.get_respawn_due_minute() - work.daily.now())
		text += "\nRemaining: %d days %02d h %02d min (game)" % [remaining / 1440, (remaining % 1440) / 60, remaining % 60]
	else:
		text += "\nNo timer pending."
	if not last_message.is_empty():
		text += "\n" + last_message
	ui.show_state(text)
