extends Node

const CITY = preload("res://scenes/content_scene/content_scene.tscn")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const STRAW: StringName = &"StrawSite"
const WORKER_ID: String = "initial_workshop_laborer"
var failures: int = 0
var city: Node
var runtime: Node
var store: Node
var player: Player

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("LEGACY_WORLD_CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok:
		failures += 1
		push_error(message)

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _raw() -> Dictionary:
	var captured: Dictionary = store.snapshot.capture(city)
	return VALUES.new().decode(captured.get("state", {}))

func _payroll(worker: WorkerData) -> Dictionary:
	return {"start": worker.payroll_start_day, "from": worker.payroll_paid_from_day,
		"until": worker.payroll_paid_until_day, "rate": worker.payroll_period_rate,
		"days": worker.payroll_contract_days, "wage": worker.wage_shekel_per_day}

func _run() -> void:
	var root: String = OS.get_environment("XDG_DATA_HOME")
	check(root.is_absolute_path() and ProjectSettings.globalize_path("user://").begins_with(root.trim_suffix("/") + "/"), "Isolated save profile only")
	if failures:
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var minute_of_day: int = TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	if minute_of_day < 8 * 60:
		check(TimeComponentManager.advance_minutes(8 * 60 - minute_of_day), "Initialize all clock consumers through normal minute signals")
	city = CITY.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	for frame: int in range(6):
		await get_tree().process_frame
	runtime = city.get_node("YSortWorld/WorkerRuntime")
	player = city.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	store = WorkStateRuntime.get_node("CitySave")
	store.disk.path = "user://disabled_legacy_world/checkpoint.json"
	var marker: Marker2D = runtime.get_node("WorksiteMarkers/StrawSite")
	var catalog: Array = runtime.sites.keys()
	check(catalog.size() == 10 and runtime.sites.has(STRAW), "Retain original ten-site save catalog and Straw ledger")
	check(not marker.is_visible_in_tree(), "Straw marker, art, labels and particles are hidden")
	check(marker.get_node("ResourceBase/CollisionPolygon2D").disabled and not marker.get_node("ReadyParticles").emitting, "No invisible Straw collider or readiness emitter remains")
	player.global_position = marker.global_position
	check(runtime._nearest_interaction_site() != marker, "No world interaction at the retired Straw coordinate")
	runtime._open_site_panel(marker)
	check(not runtime.inspector.visible, "No Straw inspector opens through direct or Worker Hub navigation")
	check(not runtime.daily.toggle(STRAW, WORKER_ID) and not runtime.daily.start(STRAW, Callable()), "No new Straw selection or job can start")
	check(runtime.daily.is_site_available(&"ReedSite") and runtime.daily.is_site_available(&"WaterSite"), "Reed and Water remain available")
	check(store.save_checkpoint(), "Fresh disabled-world checkpoint saves: " + store.last_error)

	# Synthetic pre-disable assignment, using the actual hire/start API. Never a user's save.
	Inventory.max_load = 100000.0
	Inventory.add_item("shekel", 10)
	CityStockManager.add_shelter_capacity(10)
	CityStockManager.add_food_supply(50)
	CityStockManager.add_clothing_supply(50)
	var worker: WorkerData = WorkerDatabase.hire_applicant(WORKER_ID, 4)
	check(worker != null, "Create one paid synthetic worker")
	if worker == null:
		get_tree().quit(1)
		return
	worker.get_linked_citizen().satisfaction = 0.7
	CitizenNeedsManager.process_daily_needs()
	runtime.disabled_world_sites.clear()
	check(runtime.daily.toggle(STRAW, WORKER_ID) and runtime.daily.start(STRAW, runtime._deliver_daily_output.bind(marker)), "Seed a real existing Straw assignment")
	if not runtime.daily.jobs.has(STRAW):
		get_tree().quit(1)
		return
	worker.physical_approach.position = worker.physical_approach.target
	worker.physical_approach.arrived = true
	worker.physical_approach.arrival_minute = _now()
	check(TimeComponentManager.advance_minutes(5), "Accrue actual partial Straw progress before retirement")
	var progress_before: float = runtime.daily.jobs[STRAW].progress[WORKER_ID]
	check(progress_before > 0.0 and progress_before < runtime.sites[STRAW].minutes_per_unit, "Fixture contains a real incomplete item")
	# Reconstruct an already-existing legacy loaded Hauler, not a new gameplay option.
	var hauler_id: String = "initial_worksite_hauler"
	var hauler: WorkerData = WorkerDatabase.hire_applicant(hauler_id, 4)
	check(hauler != null, "Create a synthetic legacy Hauler")
	if hauler == null:
		get_tree().quit(1)
		return
	hauler.profession = WorkerData.Profession.HAULER
	hauler.get_linked_citizen().profession = WorkerData.Profession.HAULER
	hauler.get_linked_citizen().satisfaction = 0.7
	runtime.daily.allow_haulers = true
	check(runtime.city_tools.allocate("initial_worksite_cart", hauler_id), "Preserve a real allocated Hauler cart")
	# Modern City Storage correctly rejects Straw, so reconstruct the existing
	# supported legacy-final route schema rather than bypassing its gameplay guard.
	var existing_job: Dictionary = runtime.daily.jobs[STRAW]
	existing_job.ids.append(hauler_id)
	existing_job.progress[hauler_id] = 0.0
	existing_job.starts[hauler_id] = _now()
	existing_job.stats[hauler_id] = {"days": [], "output": 0}
	hauler.start_work(existing_job.order, "clay_daily")
	runtime.hauling.begin(hauler_id, STRAW, _now(), {"destination_path": NodePath("StrawStorage"), "destination_name": "Ground", "daily_target": 3})
	var route: Dictionary = runtime.hauling.routes[hauler_id]
	var target: Vector2 = runtime.to_global(runtime.LEGACY_STOCKPILES.STOCKPILES["StrawStorage"].position)
	route.legacy_final = true
	route.removing = true
	route.phase = "outbound"
	route.cargo.quantity = 3
	route.target = target
	route.arrival = _now() + runtime.hauling._travel_minutes(route.origin.distance_to(target))
	route.destination = preload("res://scenes/new_scenes/save_game/city_save_worksites.gd").LegacyFinalDestination.new(runtime, target)
	runtime.daily.allow_haulers = false
	check(route.cargo.quantity == 3 and route.phase == "outbound", "Synthetic historical final trip owns three previously harvested goods")
	check(store.save_checkpoint(), "Pre-disable assignment checkpoint saves: " + store.last_error)
	var old_checkpoint: PackedByteArray = FileAccess.get_file_as_bytes(store.disk.path)
	var stock_before: int = runtime.sites[STRAW].stock
	var payroll_before: Dictionary = _payroll(worker)
	var paid_end: int = worker.get_paid_end_minute()
	var treasury_before: int = CityStockManager.treasury_shekel
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	runtime.disabled_world_sites.assign([STRAW])
	check(store.load_checkpoint(), "Pre-disable snapshot loads with unchanged catalog: " + store.last_error)
	worker = WorkerDatabase.get_worker_data(WORKER_ID)
	check(FileAccess.get_file_as_bytes(store.disk.path) == old_checkpoint, "Loading does not rewrite the original fixture checkpoint")
	var saved_job: Dictionary = store.snapshot._sites.capture(runtime).jobs[str(STRAW)].duplicate(true)
	var approach_before: Dictionary = worker.physical_approach.duplicate(true)
	var stored_before: int = int(runtime.city_tools.items.get("straw_bundle", 0))
	var xp_before: int = worker.profession_xp
	check(TimeComponentManager.advance_minutes(60), "Advance one hour with retired Straw")
	runtime.get_node("WorkerVisuals")._process(0.05)
	check(runtime.sites[STRAW].stock == stock_before and runtime.daily.jobs[STRAW].progress[WORKER_ID] == progress_before
		and int(runtime.city_tools.items.get("straw_bundle", 0)) == stored_before and worker.profession_xp == xp_before,
		"No hidden harvesting, progress, stock consumption or gatherer XP")
	var legacy_units: int = 0
	for drop: Node in runtime.get_node("GroundOutput").get_children():
		if bool(drop.get_meta("legacy_stockpile", false)) and drop.item_id == "straw_bundle":
			legacy_units += int(drop.quantity)
	check(legacy_units == 3 and not runtime.hauling.routes.has(hauler_id) and not runtime.daily.jobs[STRAW].ids.has(hauler_id)
		and WorkerDatabase.get_worker_data(hauler_id) != null, "Prior final cargo reaches its existing ground endpoint once and completes its pre-existing release")
	check(worker.is_reserved() and runtime.daily.jobs[STRAW].ids.has(WORKER_ID)
		and worker.physical_approach == approach_before, "Assignment and exact approach record retained without invisible travel")
	check(_payroll(worker) == payroll_before and worker.get_paid_end_minute() == paid_end
		and CityStockManager.treasury_shekel == treasury_before and Inventory.items == inventory_before,
		"No payroll, expiry, wallet or inventory rewrite")
	check(runtime.daily.status(STRAW).contains("Contract time still runs"), "Paused assignment exposes the contract-time tradeoff")
	check(store.save_checkpoint(), "Paused assignment saves: " + store.last_error)
	var paused_bytes: PackedByteArray = FileAccess.get_file_as_bytes(store.disk.path)
	for attempt: int in range(2):
		check(store.load_checkpoint(), "Paused assignment reload %d: %s" % [attempt + 1, store.last_error])
		worker = WorkerDatabase.get_worker_data(WORKER_ID)
		check(runtime.sites[STRAW].stock == stock_before and runtime.daily.jobs[STRAW].progress[WORKER_ID] == progress_before
			and _payroll(worker) == payroll_before and worker.is_reserved() and FileAccess.get_file_as_bytes(store.disk.path) == paused_bytes,
			"Repeated load preserves assignment, progress, stock, payroll and file bytes")
	# Option B is evaluated only, not wired as an automatic gameplay decision.
	check(runtime.daily.request_resignation(WORKER_ID), "Evaluate existing release path without dismissing the worker")
	worker = WorkerDatabase.get_worker_data(WORKER_ID)
	check(worker != null and not worker.is_reserved() and not runtime.daily.jobs.has(STRAW)
		and runtime.daily.pending_progress.get(STRAW, []).has(progress_before) and _payroll(worker) == payroll_before,
		"Release option retains partial work and paid hire, freeing assignment only")
	check(store.save_checkpoint() and store.load_checkpoint(), "Released-option partial progress survives Save/Load: " + store.last_error)
	check(runtime.daily.pending_progress.get(STRAW, []).has(progress_before), "Retained partial progress stays recoverable, not discarded")

	var recipe: JobData = preload("res://resources/job_data/mudbrick_make.tres")
	var merchant: Resource = preload("res://resources/traveling_merchant/common_merchant.tres")
	check(recipe.inputs.get("straw_bundle") == 3, "Mudbrick still requires exactly three straw; recipe unchanged")
	print("LEGACY_WORLD_TRADEOFF ", JSON.stringify({"hold_assignment": true, "no_new_harvest": true,
		"contract_expiry_unchanged": paid_end, "paid_minutes_consumed_during_hold": 60,
		"release_option_preserves_partial": progress_before, "straw_recipe_requirement": recipe.inputs.get("straw_bundle")}))
	print("DisabledLegacyWorldTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
