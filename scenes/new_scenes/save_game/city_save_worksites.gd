extends RefCounted

## Scene-local snapshot adapter for the authored main-city worksite map.
## IDs in this block are checked against the current authored map before they
## are used to bind callbacks or endpoints. No saved path is loaded directly.
const SCHEMA_VERSION: int = 1
const MAX_COUNT: int = 1000000000
const MAX_DAY: int = 694444 # floor(MAX_COUNT / 1440)
const MAX_POSITION: float = 1000000.0

var error: String = ""


func capture(worksite: Node) -> Dictionary:
	error = ""
	if not _has_worksite_context(worksite):
		_fail("The current worksite map is unavailable.")
		return {}
	if bool(worksite.get("_working")):
		_fail("Manual work is still active.")
		return {}
	for session in worksite.sites.values():
		if bool(session.working):
			_fail("Manual work is still active.")
			return {}

	var sites: Dictionary = {}
	for site_key: Variant in worksite.sites:
		var site_id: String = str(site_key)
		var session = worksite.sites[site_key]
		if not _valid_id(site_id) or sites.has(site_id) or not _valid_item_id(str(session.item_id)):
			_fail("The worksite registry contains an unsupported site or item.")
			return {}
		sites[site_id] = {"stock": int(session.stock)}

	var endpoints: Dictionary = _authored_endpoints(worksite)
	var storages: Dictionary = _capture_storages(worksite, endpoints)
	if not error.is_empty():
		return {}
	var jobs: Dictionary = _capture_jobs(worksite)
	if not error.is_empty():
		return {}
	var routes: Dictionary = _capture_routes(worksite, endpoints)
	if not error.is_empty():
		return {}
	var ground: Array = _capture_ground(worksite)
	if not error.is_empty():
		return {}
	var journeys: Dictionary = _capture_journeys(worksite)
	if not error.is_empty():
		return {}
	var daily = worksite.daily
	var data: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"sites": sites,
		"storages": storages,
		"jobs": jobs,
		"ledger": {
			"day": int(daily.ledger_day),
			"last_tick": int(daily.last_tick),
			"stock_day": int(daily.last_stock_day),
			"minutes": daily.minutes_by_worker.duplicate(true),
			"rng_seed": int(daily.rng.seed),
			"rng_state": int(daily.rng.state),
		},
		"contributions": worksite.worker_management.contributions.duplicate(true),
		"productive_days": worksite.worker_management.productive_days.duplicate(true),
		"routes": routes,
		"ground": ground,
		"worker_journeys": journeys,
		"journey_cache_day": int(worksite.journey_cache_day),
	}
	return data


func validate(data: Dictionary, worksite: Node, workers: Dictionary, dismissed_workers: Dictionary = {}) -> bool:
	error = ""
	if not _has_worksite_context(worksite):
		return _fail("The current worksite map is unavailable.")
	if not _has_exact_keys(data, [
		"schema_version", "sites", "storages", "jobs", "ledger", "contributions",
		"productive_days", "routes", "ground", "worker_journeys", "journey_cache_day",
	]):
		return _fail("Invalid worksite snapshot fields.")
	if typeof(data.schema_version) != TYPE_INT or int(data.schema_version) != SCHEMA_VERSION:
		return _fail("Unsupported worksite snapshot version.")
	for field: String in ["sites", "storages", "jobs", "ledger", "contributions", "productive_days", "routes", "worker_journeys"]:
		if typeof(data[field]) != TYPE_DICTIONARY:
			return _fail("Invalid worksite snapshot map: " + field)
	if typeof(data.ground) != TYPE_ARRAY or data.ground.size() > 10000:
		return _fail("Invalid worksite ground output list.")
	if not _is_count(data.journey_cache_day, -1, MAX_DAY):
		return _fail("Invalid worksite commute cache day.")

	var site_ids: Dictionary = _site_registry(worksite)
	if not _same_keys(data.sites, site_ids):
		return _fail("Worksite registry differs from the saved city.")
	for site_id: String in data.sites:
		if not _has_exact_keys(data.sites[site_id], ["stock"]):
			return _fail("Invalid worksite stock record.")
		if not _is_count(data.sites[site_id].stock, 0, MAX_COUNT):
			return _fail("Invalid worksite stock quantity.")

	var endpoints: Dictionary = _authored_endpoints(worksite)
	if not _same_keys(data.storages, endpoints):
		return _fail("Authored storage registry differs from the saved city.")
	if not _validate_storages(data.storages, worksite, endpoints):
		return false

	var all_workers: Dictionary = {}
	if not _merge_worker_rosters(all_workers, workers):
		return false
	if not _merge_worker_rosters(all_workers, dismissed_workers):
		return false
	if not _validate_ledger(data.ledger, all_workers, worksite):
		return false
	if int(data.journey_cache_day) > int(data.ledger.stock_day):
		return _fail("Commute cache day is newer than the worksite ledger.")
	if not _validate_jobs(data.jobs, worksite, workers, data.routes, site_ids, int(data.ledger.stock_day)):
		return false
	if not _validate_worker_history(data.contributions, data.productive_days, all_workers, int(data.ledger.stock_day)):
		return false
	if not _validate_routes(data.routes, data.jobs, workers, worksite, endpoints, site_ids, int(data.ledger.last_tick)):
		return false
	if not _validate_ground(data.ground, worksite, site_ids):
		return false
	if not _validate_journeys(data.worker_journeys, all_workers, site_ids, int(data.journey_cache_day)):
		return false
	return true


## Called only after the city snapshot and its decoded worker rosters validate.
## Root restore owns Inventory, WorkerDatabase, CitizenManager and CityToolStorage.
func restore(data: Dictionary, worksite: Node) -> void:
	error = ""
	if not _has_worksite_context(worksite):
		_fail("The current worksite map is unavailable.")
		return
	var endpoints: Dictionary = _authored_endpoints(worksite)
	var _site_ids: Dictionary = _site_registry(worksite)

	# Resolve every callback and endpoint into fresh runtime dictionaries before
	# changing the live worksite state.
	var restored_jobs: Dictionary = {}
	for site_id: String in data.jobs:
		var saved_job: Dictionary = data.jobs[site_id]
		var job: Dictionary = {
			"ids": saved_job.ids.duplicate(),
			"order": str(saved_job.order),
			"drop": Callable(worksite, "_drop_daily_output").bind(_site_marker(worksite, site_id)),
			"units": int(saved_job.units),
			"progress": saved_job.progress.duplicate(true),
			"starts": saved_job.starts.duplicate(true),
			"stats": saved_job.stats.duplicate(true),
		}
		restored_jobs[StringName(site_id)] = job

	var restored_routes: Dictionary = {}
	for worker_id: String in data.routes:
		var saved_route: Dictionary = data.routes[worker_id]
		var endpoint: StorageDestination = endpoints[str(saved_route.destination_id)]
		var route: Dictionary = {
			"id": worker_id,
			"site_id": StringName(saved_route.site_id),
			"phase": str(saved_route.phase),
			"cargo": saved_route.cargo.duplicate(true),
			"origin": saved_route.origin,
			"target": saved_route.target,
			"position": saved_route.position,
			"start": int(saved_route.start),
			"arrival": int(saved_route.arrival),
			"direction": str(saved_route.direction),
			"destination": endpoint if saved_route.phase != "idle" else null,
			"destination_path": worksite.get_path_to(endpoint),
			"destination_name": endpoint.display_name,
			"daily_target": int(saved_route.daily_target),
			"delivery_day": int(saved_route.delivery_day),
			"delivered_today": int(saved_route.delivered_today),
			"removing": bool(saved_route.removing),
		}
		restored_routes[worker_id] = route

	var restored_journeys: Dictionary = {}
	for key: String in data.worker_journeys:
		restored_journeys[key] = data.worker_journeys[key].duplicate(true)
	# Route identity is transient; reconnect it to the restored assignment stats.
	for site_id: StringName in restored_jobs:
		for worker_id: String in restored_jobs[site_id].ids:
			var key: String = "%s:%s:%d" % [site_id, worker_id, int(data.journey_cache_day)]
			if restored_journeys.has(key):
				restored_journeys[key]["assignment"] = restored_jobs[site_id].stats[worker_id]

	var daily = worksite.daily
	for site_id: String in data.sites:
		worksite.sites[StringName(site_id)].stock = int(data.sites[site_id].stock)
	for endpoint_id: String in data.storages:
		var endpoint: StorageDestination = endpoints[endpoint_id]
		endpoint.accepting_deliveries = bool(data.storages[endpoint_id].accepting)
		if not bool(data.storages[endpoint_id].shared):
			var storage: Node = endpoint.get_storage()
			storage.capacity = int(data.storages[endpoint_id].capacity)
			storage.quantity = int(data.storages[endpoint_id].quantity)
			if storage.has_signal("changed"):
				storage.emit_signal("changed")

	# Draft selections and plans are transient inspector UI state. Active jobs
	# and routes are restored from their validated persistent records above.
	daily.selected.clear()
	for site_key: Variant in worksite.sites:
		daily.selected[site_key] = []
	daily.hauler_setups.clear()
	daily.jobs = restored_jobs
	daily.minutes_by_worker = data.ledger.minutes.duplicate(true)
	daily.ledger_day = int(data.ledger.day)
	daily.last_tick = int(data.ledger.last_tick)
	daily.last_stock_day = int(data.ledger.stock_day)
	daily.rng.seed = int(data.ledger.rng_seed)
	daily.rng.state = int(data.ledger.rng_state)
	worksite.hauling.routes = restored_routes
	worksite.worker_management.contributions = data.contributions.duplicate(true)
	worksite.worker_management.productive_days = data.productive_days.duplicate(true)
	worksite.worker_journeys = restored_journeys
	worksite.journey_cache_day = int(data.journey_cache_day)

	var ground_output: Node = worksite.get_node("GroundOutput")
	for pile: Node in ground_output.get_children():
		pile.free()
	for saved_pile: Dictionary in data.ground:
		var callback: Callable = Callable()
		if not str(saved_pile.site_id).is_empty():
			callback = Callable(worksite, "_drop_daily_output").bind(_site_marker(worksite, str(saved_pile.site_id)))
		if not bool(worksite.call("_drop_output_at", int(saved_pile.quantity), saved_pile.position, callback, str(saved_pile.item_id))):
			_fail("Validated ground output could not be restored.")
			return
		var restored_pile: Node = ground_output.get_child(-1)
		if not str(saved_pile.site_id).is_empty():
			restored_pile.set_meta("daily_site", str(saved_pile.site_id))

	var visuals: Node = worksite.get_node_or_null("WorkerVisuals")
	if visuals != null:
		for actor: Node in visuals.actors.values():
			actor.free()
		visuals.actors.clear()
		visuals.work_cycles.clear()
		visuals.roaming.clear()
		visuals.site_paths.clear()
		visuals.plot_presence.states.clear()
		visuals.plot_presence.initial_sync = true
		visuals.last_minute = -1
		visuals.fraction = 0.0

	daily._sync_activities()


func _capture_jobs(worksite: Node) -> Dictionary:
	var result: Dictionary = {}
	for site_key: Variant in worksite.daily.jobs:
		var site_id: String = str(site_key)
		var job: Dictionary = worksite.daily.jobs[site_key]
		var stats: Dictionary = {}
		for worker_id_value: Variant in job.get("stats", {}).keys():
			var worker_id: String = str(worker_id_value)
			var stat: Dictionary = job.stats[worker_id_value]
			stats[worker_id] = {"days": stat.days.duplicate(true), "output": int(stat.output)}
		result[site_id] = {
			"ids": job.get("ids", []).duplicate(),
			"order": str(job.get("order", "")),
			"units": int(job.get("units", 0)),
			"progress": job.get("progress", {}).duplicate(true),
			"starts": job.get("starts", {}).duplicate(true),
			"stats": stats,
		}
	return result


func _capture_routes(worksite: Node, endpoints: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for worker_id_value: Variant in worksite.hauling.routes:
		var worker_id: String = str(worker_id_value)
		var route: Dictionary = worksite.hauling.routes[worker_id_value]
		var destination_id: String = str(NodePath(route.get("destination_path", NodePath(""))))
		if not endpoints.has(destination_id):
			_fail("A Hauler uses a destination outside the authored storage choices.")
			return {}
		result[worker_id] = {
			"site_id": str(route.get("site_id", "")),
			"phase": str(route.get("phase", "")),
			"cargo": route.get("cargo", {}).duplicate(true),
			"origin": route.get("origin", Vector2.ZERO),
			"target": route.get("target", Vector2.ZERO),
			"position": route.get("position", Vector2.ZERO),
			"start": int(route.get("start", -1)),
			"arrival": int(route.get("arrival", -1)),
			"direction": str(route.get("direction", "")),
			"destination_id": destination_id,
			"daily_target": int(route.get("daily_target", 0)),
			"delivery_day": int(route.get("delivery_day", -1)),
			"delivered_today": int(route.get("delivered_today", 0)),
			"removing": bool(route.get("removing", false)),
		}
	return result


func _capture_ground(worksite: Node) -> Array:
	var result: Array = []
	for pile: Node in worksite.get_node("GroundOutput").get_children():
		if not pile is PickUpItem or pile.is_queued_for_deletion() or pile.is_collecting:
			continue
		result.append({
			"item_id": str(pile.item_id),
			"quantity": int(pile.quantity),
			"position": pile.position,
			"site_id": str(pile.get_meta("daily_site", "")),
		})
	return result


func _capture_journeys(worksite: Node) -> Dictionary:
	var result: Dictionary = {}
	for key_value: Variant in worksite.worker_journeys:
		var key: String = str(key_value)
		var journey: Dictionary = worksite.worker_journeys[key_value]
		result[key] = {
			"origin": journey.get("origin", Vector2.ZERO),
			"target": journey.get("target", Vector2.ZERO),
			"start": journey.get("start", -1.0),
			"arrival": int(journey.get("arrival", -1)),
		}
	return result


func _capture_storages(worksite: Node, endpoints: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for endpoint_id: String in endpoints:
		var endpoint: StorageDestination = endpoints[endpoint_id]
		var storage: Node = endpoint.get_storage()
		if storage == null or not is_instance_valid(storage):
			_fail("An authored storage endpoint is unavailable.")
			return {}
		if storage == worksite.city_tools:
			result[endpoint_id] = {"shared": true, "accepting": bool(endpoint.accepting_deliveries)}
			continue
		if not _has_property(storage, "quantity") or not _has_property(storage, "capacity"):
			_fail("An authored storage endpoint has no supported stock record.")
			return {}
		result[endpoint_id] = {
			"shared": false,
			"quantity": int(storage.get("quantity")),
			"capacity": int(storage.get("capacity")),
			"accepting": bool(endpoint.accepting_deliveries),
		}
	return result


func _authored_endpoints(worksite: Node) -> Dictionary:
	var result: Dictionary = {}
	if not is_instance_valid(worksite) or not worksite.is_inside_tree():
		return result
	for endpoint: Node in worksite.get_tree().get_nodes_in_group("storage_destinations"):
		if not endpoint is StorageDestination or not worksite.is_ancestor_of(endpoint) or endpoint.is_queued_for_deletion():
			continue
		# The group contains the StorageDestination nodes authored into this map
		# and its map-local storage subscenes. A saved key is only an ID for one
		# of these already-present nodes; it is never passed to get_node().
		var endpoint_id: String = str(worksite.get_path_to(endpoint))
		if not endpoint_id.is_empty() and endpoint_id != ".":
			result[endpoint_id] = endpoint
	return result


func _site_registry(worksite: Node) -> Dictionary:
	var result: Dictionary = {}
	for site_key: Variant in worksite.sites:
		var site_id: String = str(site_key)
		var marker: Node = _site_marker(worksite, site_id)
		if marker != null:
			result[site_id] = marker
	return result


func _site_marker(worksite: Node, site_id: String) -> Node:
	var markers: Node = worksite.get_node_or_null("WorksiteMarkers")
	if markers == null:
		return null
	for marker: Node in markers.get_children():
		if str(marker.name) == site_id:
			return marker
	return null


func _validate_storages(data: Dictionary, worksite: Node, endpoints: Dictionary) -> bool:
	for endpoint_id: String in data:
		var record_value: Variant = data[endpoint_id]
		if typeof(record_value) != TYPE_DICTIONARY:
			return _fail("Invalid authored storage endpoint record.")
		var record: Dictionary = record_value
		var endpoint: StorageDestination = endpoints[endpoint_id]
		var storage: Node = endpoint.get_storage()
		if storage == null or not is_instance_valid(storage):
			return _fail("An authored storage endpoint is unavailable.")
		if storage == worksite.city_tools:
			if not _has_exact_keys(record, ["shared", "accepting"]) or typeof(record.shared) != TYPE_BOOL or not record.shared or typeof(record.accepting) != TYPE_BOOL:
				return _fail("Invalid shared City Storage endpoint record.")
		else:
			if not _has_exact_keys(record, ["shared", "quantity", "capacity", "accepting"]) or typeof(record.shared) != TYPE_BOOL or record.shared:
				return _fail("Invalid authored storage endpoint record.")
			if not _is_count(record.quantity, 0, MAX_COUNT) or not _is_count(record.capacity, 1, MAX_COUNT) or record.quantity > record.capacity:
				return _fail("Invalid authored storage stock or capacity.")
			if not _has_property(storage, "quantity") or not _has_property(storage, "capacity"):
				return _fail("Authored storage no longer supports a stock record.")
		if typeof(record.accepting) != TYPE_BOOL:
			return _fail("Invalid authored storage delivery state.")
	return true


func _validate_jobs(data: Dictionary, worksite: Node, workers: Dictionary, routes: Dictionary, site_ids: Dictionary, saved_day: int) -> bool:
	var assigned: Dictionary = {}
	for site_id_value: Variant in data:
		var site_id: String = str(site_id_value)
		if not site_ids.has(site_id) or typeof(site_id_value) != TYPE_STRING:
			return _fail("A daily job refers to an unknown worksite.")
		var job_value: Variant = data[site_id_value]
		if typeof(job_value) != TYPE_DICTIONARY:
			return _fail("Invalid daily job record.")
		var job: Dictionary = job_value
		if not _has_exact_keys(job, ["ids", "order", "units", "progress", "starts", "stats"]):
			return _fail("Invalid daily job record.")
		if typeof(job.ids) != TYPE_ARRAY or job.ids.is_empty() or job.ids.size() > 2:
			return _fail("Invalid daily job worker slots.")
		if typeof(job.order) != TYPE_STRING or job.order.is_empty() or job.order.length() > 512:
			return _fail("Invalid daily work order ID.")
		if not _is_count(job.units, 0, MAX_COUNT) or typeof(job.progress) != TYPE_DICTIONARY or typeof(job.starts) != TYPE_DICTIONARY or typeof(job.stats) != TYPE_DICTIONARY:
			return _fail("Invalid daily job values.")
		if job.starts.size() != job.ids.size() or job.stats.size() != job.ids.size():
			return _fail("Daily job worker records do not match its assignments.")
		var session = worksite.sites[StringName(site_id)]
		var seen_ids: Dictionary = {}
		for worker_id_value: Variant in job.ids:
			if typeof(worker_id_value) != TYPE_STRING or not _valid_id(worker_id_value) or seen_ids.has(worker_id_value):
				return _fail("Invalid or duplicate daily worker ID.")
			var worker_id: String = worker_id_value
			var worker: Variant = workers.get(worker_id)
			if not worker is WorkerData or worker.worker_id != worker_id or assigned.has(worker_id):
				return _fail("Daily job worker is missing or assigned more than once.")
			if worker.current_order_id != job.order or worker.current_job_id != "clay_daily":
				return _fail("Daily job and worker order state disagree.")
			seen_ids[worker_id] = true
			assigned[worker_id] = site_id
			if not job.starts.has(worker_id) or not _is_count(job.starts[worker_id], 0, MAX_COUNT) or int(job.starts[worker_id]) % 1440 < int(worksite.daily.SHIFT_START) or int(job.starts[worker_id]) % 1440 >= int(worksite.daily.SHIFT_END):
				return _fail("Invalid daily assignment start time.")
			if int(job.starts[worker_id]) > (saved_day + 1) * 1440 + int(worksite.daily.SHIFT_START):
				return _fail("Daily assignment starts after the next workday.")
			if not job.stats.has(worker_id) or not _has_exact_keys(job.stats[worker_id], ["days", "output"]):
				return _fail("Invalid daily worker statistics.")
			var stat: Dictionary = job.stats[worker_id]
			if not _is_count(stat.output, 0, MAX_COUNT) or not _valid_days(stat.days, saved_day):
				return _fail("Invalid daily worker output history.")
			if stat.output > worker.profession_xp:
				return _fail("Daily output exceeds the worker's recorded experience.")
			if worker.profession == WorkerData.Profession.HAULER and not routes.has(worker_id):
				return _fail("Assigned Hauler has no saved route.")
		for worker_id_value: Variant in job.starts:
			if typeof(worker_id_value) != TYPE_STRING or not seen_ids.has(worker_id_value):
				return _fail("Daily job start map has an unknown worker.")
		for worker_id_value: Variant in job.stats:
			if typeof(worker_id_value) != TYPE_STRING or not seen_ids.has(worker_id_value):
				return _fail("Daily job statistics have an unknown worker.")
		for worker_id_value: Variant in job.progress:
			if typeof(worker_id_value) != TYPE_STRING or not seen_ids.has(worker_id_value):
				return _fail("Daily job progress has an unknown worker.")
			var progress: Variant = job.progress[worker_id_value]
			if not _is_finite_number(progress) or float(progress) < 0.0 or float(progress) >= float(session.minutes_per_unit):
				return _fail("Invalid partial gathering progress.")
	return true


func _validate_ledger(ledger: Dictionary, workers: Dictionary, worksite: Node) -> bool:
	if not _has_exact_keys(ledger, ["day", "last_tick", "stock_day", "minutes", "rng_seed", "rng_state"]):
		return _fail("Invalid worksite daily ledger fields.")
	if not _is_count(ledger.day, -1, MAX_DAY) or not _is_count(ledger.stock_day, 0, MAX_DAY):
		return _fail("Invalid worksite ledger day.")
	if not _is_count(ledger.last_tick, 0, MAX_COUNT) or floori(float(ledger.last_tick) / 1440.0) != int(ledger.stock_day):
		return _fail("Worksite ledger time and stock day disagree.")
	var expected_ledger_day: int = -1 if int(ledger.last_tick) == 0 else int((int(ledger.last_tick) - 1) / 1440)
	if int(ledger.day) != -1 and int(ledger.day) != expected_ledger_day:
		return _fail("Worksite daily worker ledger disagrees with its tick time.")
	if typeof(ledger.minutes) != TYPE_DICTIONARY or typeof(ledger.rng_seed) != TYPE_INT or typeof(ledger.rng_state) != TYPE_INT:
		return _fail("Invalid worksite random or minute ledger state.")
	for worker_id_value: Variant in ledger.minutes:
		if typeof(worker_id_value) != TYPE_STRING or not workers.has(worker_id_value) or not _is_count(ledger.minutes[worker_id_value], 0, int(worksite.daily.DAILY_LIMIT)):
			return _fail("Invalid per-worker daily minutes.")
	if int(ledger.day) == -1 and not ledger.minutes.is_empty():
		return _fail("Initial worksite ledger must not include daily worker minutes.")
	return true


func _validate_worker_history(contributions: Dictionary, productive_days: Dictionary, workers: Dictionary, saved_day: int) -> bool:
	if not _same_keys(contributions, productive_days):
		return _fail("Worker contribution and productive-day histories disagree.")
	for worker_id_value: Variant in contributions:
		if typeof(worker_id_value) != TYPE_STRING or not _valid_id(worker_id_value) or not workers.has(worker_id_value):
			return _fail("Contribution history refers to an unknown worker.")
		var worker: WorkerData = workers[worker_id_value]
		if not _is_count(contributions[worker_id_value], 0, MAX_COUNT) or not _valid_days(productive_days[worker_id_value], saved_day):
			return _fail("Invalid worker contribution history.")
		if int(contributions[worker_id_value]) > worker.profession_xp:
			return _fail("Worker contribution history exceeds recorded experience.")
	return true


func _validate_routes(data: Dictionary, jobs: Dictionary, workers: Dictionary, worksite: Node, endpoints: Dictionary, site_ids: Dictionary, saved_time: int) -> bool:
	var assigned: Dictionary = {}
	for site_id_value: Variant in jobs:
		var site_id: String = str(site_id_value)
		for worker_id_value: Variant in jobs[site_id_value].ids:
			assigned[str(worker_id_value)] = site_id
	for worker_id_value: Variant in data:
		if typeof(worker_id_value) != TYPE_STRING or not _valid_id(worker_id_value):
			return _fail("Invalid Hauler route ID.")
		var worker_id: String = worker_id_value
		if not assigned.has(worker_id) or not workers.has(worker_id):
			return _fail("Hauler route refers to an unassigned worker.")
		var worker: Variant = workers[worker_id]
		if not worker is WorkerData or worker.profession != WorkerData.Profession.HAULER:
			return _fail("A saved route belongs to a non-Hauler.")
		var route_value: Variant = data[worker_id]
		if typeof(route_value) != TYPE_DICTIONARY:
			return _fail("Invalid Hauler route fields.")
		var route: Dictionary = route_value
		if not _has_exact_keys(route, [
			"site_id", "phase", "cargo", "origin", "target", "position", "start", "arrival",
			"direction", "destination_id", "daily_target", "delivery_day", "delivered_today", "removing",
		]):
			return _fail("Invalid Hauler route fields.")
		if typeof(route.site_id) != TYPE_STRING or route.site_id != assigned[worker_id] or not site_ids.has(route.site_id):
			return _fail("Hauler route worksite does not match its assignment.")
		var session = worksite.sites[StringName(route.site_id)]
		if typeof(route.phase) != TYPE_STRING or not ["idle", "outbound", "returning"].has(route.phase):
			return _fail("Unknown Hauler route phase.")
		if not _has_exact_keys(route.cargo, ["item_id", "quantity"]):
			return _fail("Invalid Hauler cargo.")
		if not _valid_item_id(route.cargo.item_id) or route.cargo.item_id != session.item_id or not _is_count(route.cargo.quantity, 0, int(worksite.hauling.CAPACITY)):
			return _fail("Hauler cargo item or quantity is invalid.")
		if route.phase == "idle" and int(route.cargo.quantity) != 0:
			return _fail("An idle Hauler cannot carry cargo.")
		if route.phase == "outbound" and int(route.cargo.quantity) <= 0:
			return _fail("An outbound Hauler must carry cargo.")
		if not _is_vector(route.origin) or not _is_vector(route.target) or not _is_vector(route.position):
			return _fail("Invalid Hauler route positions.")
		if not _is_count(route.start, 0, MAX_COUNT) or not _is_count(route.arrival, 0, MAX_COUNT) or int(route.arrival) < int(route.start) or int(route.start) > saved_time:
			return _fail("Invalid Hauler route times.")
		if typeof(route.direction) != TYPE_STRING or not ["left", "right"].has(route.direction):
			return _fail("Invalid Hauler route direction.")
		if typeof(route.destination_id) != TYPE_STRING or not endpoints.has(route.destination_id):
			return _fail("Hauler destination is not an authored storage choice.")
		var saved_day: int = floori(float(saved_time) / 1440.0)
		if not _is_count(route.daily_target, 1, 9999999) or not _is_count(route.delivery_day, -1, saved_day) or not _is_count(route.delivered_today, 0, int(route.daily_target)):
			return _fail("Invalid Hauler delivery progress.")
		if int(route.delivery_day) == -1 and int(route.delivered_today) != 0:
			return _fail("Hauler delivery count has no delivery day.")
		if typeof(route.removing) != TYPE_BOOL:
			return _fail("Invalid Hauler removal state.")
		var endpoint: StorageDestination = endpoints[route.destination_id]
		if route.phase != "idle" and not route.target.is_equal_approx(endpoint.get_arrival_position()):
			return _fail("Hauler destination position no longer matches the authored endpoint.")
	for worker_id: String in assigned:
		var worker: WorkerData = workers.get(worker_id)
		if worker != null and worker.profession == WorkerData.Profession.HAULER and not data.has(worker_id):
			return _fail("An assigned Hauler route is missing.")
	return true


func _validate_ground(piles: Array, worksite: Node, site_ids: Dictionary) -> bool:
	for pile: Variant in piles:
		if not _has_exact_keys(pile, ["item_id", "quantity", "position", "site_id"]):
			return _fail("Invalid ground output record.")
		if not _valid_item_id(pile.item_id) or not _is_count(pile.quantity, 1, MAX_COUNT) or not _is_vector(pile.position):
			return _fail("Unknown ground output item or invalid stack values.")
		if typeof(pile.site_id) != TYPE_STRING:
			return _fail("Invalid ground output worksite.")
		if not pile.site_id.is_empty():
			if not site_ids.has(pile.site_id) or str(worksite.sites[StringName(pile.site_id)].item_id) != pile.item_id:
				return _fail("Ground output refers to an unknown worksite or resource.")
	return true


func _validate_journeys(journeys: Dictionary, workers: Dictionary, site_ids: Dictionary, cache_day: int) -> bool:
	if cache_day < 0 and not journeys.is_empty():
		return _fail("Worker commute cache has entries without a cache day.")
	for key_value: Variant in journeys:
		if typeof(key_value) != TYPE_STRING or key_value.length() > 512:
			return _fail("Invalid worker commute key.")
		var key: String = key_value
		if not _journey_key_is_known(key, workers, site_ids, cache_day):
			return _fail("Worker commute refers to an unknown site or worker.")
		var journey_value: Variant = journeys[key_value]
		if typeof(journey_value) != TYPE_DICTIONARY:
			return _fail("Invalid worker commute record.")
		var journey: Dictionary = journey_value
		if not _has_exact_keys(journey, ["origin", "target", "start", "arrival"]):
			return _fail("Invalid worker commute record.")
		if not _is_vector(journey.origin) or not _is_vector(journey.target) or not _is_finite_number(journey.start) or float(journey.start) < 0.0 or float(journey.start) > float(MAX_COUNT):
			return _fail("Invalid worker commute positions or departure time.")
		if not _is_count(journey.arrival, 0, MAX_COUNT) or float(journey.arrival) < float(journey.start) or int(journey.arrival) < cache_day * 1440 + 420:
			return _fail("Invalid worker commute arrival time.")
	return true


func _journey_key_is_known(key: String, workers: Dictionary, site_ids: Dictionary, day: int) -> bool:
	for site_id: String in site_ids:
		for worker_id: String in workers:
			var prefix: String = site_id + ":" + worker_id + ":"
			if not key.begins_with(prefix):
				continue
			var day_text: String = key.substr(prefix.length())
			if not day_text.is_valid_int() or str(int(day_text)) != day_text:
				continue
			if int(day_text) == day:
				return true
	return false


func _merge_worker_rosters(target: Dictionary, source: Dictionary) -> bool:
	for worker_id_value: Variant in source:
		if typeof(worker_id_value) != TYPE_STRING or not _valid_id(worker_id_value):
			return _fail("Invalid worker roster key in worksite validation.")
		var worker: Variant = source[worker_id_value]
		if not worker is WorkerData or worker.worker_id != worker_id_value or target.has(worker_id_value):
			return _fail("Invalid or duplicate worker in worksite validation roster.")
		target[worker_id_value] = worker
	return true


func _has_worksite_context(worksite: Node) -> bool:
	if not is_instance_valid(worksite) or not worksite.is_inside_tree():
		return false
	for property_name: String in ["sites", "daily", "hauling", "worker_management", "worker_journeys", "journey_cache_day", "city_tools"]:
		if not _has_property(worksite, property_name):
			return false
	return worksite.sites is Dictionary and worksite.daily != null and worksite.hauling != null and worksite.worker_management != null and worksite.has_node("WorksiteMarkers") and worksite.has_node("GroundOutput")


func _has_property(object: Object, property_name: String) -> bool:
	if object == null or not is_instance_valid(object):
		return false
	for property: Dictionary in object.get_property_list():
		if str(property.name) == property_name:
			return true
	return false


func _has_exact_keys(value: Variant, expected: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != expected.size():
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or not expected.has(key):
			return false
	return true


func _same_keys(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key: Variant in left:
		if typeof(key) != TYPE_STRING or not right.has(key):
			return false
	return true


func _is_count(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= maximum


func _is_finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))


func _is_vector(value: Variant) -> bool:
	return typeof(value) == TYPE_VECTOR2 and is_finite(value.x) and is_finite(value.y) and absf(value.x) <= MAX_POSITION and absf(value.y) <= MAX_POSITION


func _valid_days(value: Variant, maximum: int) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() > 10000:
		return false
	var seen: Dictionary = {}
	for day_value: Variant in value:
		if not _is_count(day_value, 0, maximum) or seen.has(day_value):
			return false
		seen[day_value] = true
	return true


func _valid_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 128:
		return false
	return ("id_" + value.replace("-", "_")).is_valid_identifier()


func _valid_item_id(value: Variant) -> bool:
	if not _valid_id(value):
		return false
	var item: ItemData = ItemDatabase.get_item_data(value)
	return item != null and item.id == value


func _fail(message: String) -> bool:
	if error.is_empty():
		error = message
	return false
