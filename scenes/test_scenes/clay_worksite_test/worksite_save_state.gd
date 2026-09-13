extends RefCounted

## Version 1 of the isolated clay-worksite prototype save, not a global game save.
## Runtime callbacks, node paths, resources and UI drafts never enter the file.
const VERSION: int = 1
const SCENARIO: String = "clay_worksite_mvp"
const WORKER_FIELDS: Dictionary = {
	"worker_id": "id", "display_name": "text", "profession": [0, 5],
	"profession_xp": "count", "profession_star": [1, 3],
	"efficiency": [0.0, 2.0], "reliability": [0.0, 1.0],
	"wage_shekel_per_day": "count", "food_fulfilled": "bool",
	"clothing_fulfilled": "bool", "shelter_fulfilled": "bool", "satisfaction": [0.0, 1.0]
}
const CITIZEN_FIELDS: Dictionary = {
	"citizen_id": "id", "display_name": "text", "satisfaction": [0.0, 1.0],
	"reliability": [0.0, 1.0], "food_fulfilled": "bool", "clothing_fulfilled": "bool",
	"shelter_fulfilled": "bool", "experience": [0.0, 1000000000.0],
	"population_status": [0, 3], "employment_status": [0, 3], "profession": [0, 5]
}
const PROFILE_FIELDS: Dictionary = {
	"skin_tone": "id", "expression": "id", "hair_style": "id", "clothes_id": "id", "accessory": "id"
}
const ROUTE_FIELDS: Dictionary = {
	"site_id": "id", "phase": "text", "cargo": [0, 3], "origin": "vector", "target": "vector",
	"position": "vector", "start": "count", "arrival": "count", "direction": "text",
	"destination_id": "id", "daily_target": [1, 9999999], "delivery_day": "day",
	"delivered_today": "count", "removing": "bool"
}
var error: String = ""

func capture(fixture: Node, destinations: Dictionary) -> Dictionary:
	var daily = fixture.daily
	var data: Dictionary = {
		"schema_version": VERSION, "scenario": SCENARIO,
		"clock": {"day": TimeComponentManager.current_day, "hour": TimeComponentManager.current_hour,
			"minute": TimeComponentManager.current_minute, "weather": TimeComponentManager.current_weather},
		"workers": {}, "dismissed": {}, "citizens": {}, "tools": fixture.city_tools.units.duplicate(true),
		"storages": {}, "sites": {}, "jobs": {}, "routes": {}, "journeys": {},
		"ledger": {"day": daily.ledger_day, "last_tick": daily.last_tick, "stock_day": daily.last_stock_day,
			"minutes": daily.minutes_by_worker.duplicate(true), "rng_seed": str(daily.rng.seed), "rng_state": str(daily.rng.state)},
		"productive_days": fixture.worker_management.productive_days.duplicate(true),
		"contributions": fixture.worker_management.contributions.duplicate(true),
		"journey_day": fixture.journey_cache_day, "ground": [],
		"inventory": Inventory.items.duplicate(), "inventory_capacity": Inventory.max_load,
		"player_position": _vector(fixture.player.position)
	}
	for id: String in WorkerDatabase.workers_by_id:
		data.workers[id] = _fields(WorkerDatabase.workers_by_id[id], WORKER_FIELDS)
	for id: String in WorkerDatabase.dismissed_workers:
		data.dismissed[id] = _fields(WorkerDatabase.dismissed_workers[id], WORKER_FIELDS)
	for id: String in CitizenManager.citizens_by_id:
		var citizen: CitizenData = CitizenManager.citizens_by_id[id]
		data.citizens[id] = _fields(citizen, CITIZEN_FIELDS)
		data.citizens[id].profile = _fields(citizen.visual_profile, PROFILE_FIELDS) if citizen.visual_profile != null else {}
	for id: String in destinations:
		var endpoint = destinations[id]
		var storage = endpoint.get_storage()
		data.storages[id] = {"quantity": storage.quantity, "capacity": storage.capacity, "accepting": endpoint.accepting_deliveries}
	for site_id in fixture.sites:
		data.sites[str(site_id)] = {"stock": fixture.sites[site_id].stock}
	for site_id in daily.jobs:
		var job: Dictionary = daily.jobs[site_id]
		data.jobs[str(site_id)] = {"ids": job.ids.duplicate(), "units": job.units,
			"progress": job.progress.duplicate(), "starts": job.starts.duplicate(), "stats": job.stats.duplicate(true)}
	for id: String in fixture.hauling.routes:
		var route: Dictionary = fixture.hauling.routes[id]
		var endpoint = fixture._assigned_storage_destination(route.destination_path)
		var saved: Dictionary = {}
		for field: String in ROUTE_FIELDS:
			if field not in ["cargo", "destination_id", "origin", "target", "position"]:
				saved[field] = route[field]
		saved.site_id = str(route.site_id)
		saved.cargo = int(route.cargo.quantity)
		saved.destination_id = _destination_id(endpoint, destinations)
		for field: String in ["origin", "target", "position"]:
			saved[field] = _vector(route[field])
		data.routes[id] = saved
	for key: String in fixture.worker_journeys:
		var journey: Dictionary = fixture.worker_journeys[key]
		data.journeys[key] = {"origin": _vector(journey.origin), "target": _vector(journey.target),
			"start": journey.start, "arrival": journey.arrival}
	for pile: PickUpItem in fixture.get_node("GroundOutput").get_children():
		# Inventory is credited before is_collecting becomes true. Do not save
		# its lingering pickup animation as another copy of those same items.
		if not pile.is_queued_for_deletion() and not pile.is_collecting:
			data.ground.append({"item_id": pile.item_id, "quantity": pile.quantity,
				"position": _vector(pile.position), "site_id": str(pile.get_meta("daily_site", ""))})
	return data

func restore(data: Variant, fixture: Node, destinations: Dictionary) -> bool:
	if not validate(data, fixture, destinations):
		return false
	# Everything below is built from a fully validated snapshot; no gameplay
	# award/allocate/deliver events run during restoration.
	var workers: Dictionary[String, WorkerData] = {}
	var dismissed: Dictionary[String, WorkerData] = {}
	var citizens: Dictionary[String, CitizenData] = {}
	for id: String in data.workers:
		workers[id] = _worker(data.workers[id])
	for id: String in data.dismissed:
		dismissed[id] = _worker(data.dismissed[id])
	for id: String in data.citizens:
		var citizen := CitizenData.new()
		_assign_fields(citizen, data.citizens[id], CITIZEN_FIELDS)
		if not data.citizens[id].profile.is_empty():
			citizen.visual_profile = VisualProfile.new()
			_assign_fields(citizen.visual_profile, data.citizens[id].profile, PROFILE_FIELDS)
		citizens[id] = citizen
	var daily = fixture.daily
	var jobs: Dictionary = {}
	var routes: Dictionary = {}
	for site_id: String in data.jobs:
		var job: Dictionary = data.jobs[site_id].duplicate(true)
		job.units = int(job.units)
		job.progress = _int_values(job.progress)
		job.starts = _int_values(job.starts)
		for id: String in job.stats:
			job.stats[id].output = int(job.stats[id].output)
			job.stats[id].days = _int_days(job.stats[id].days)
		job.order = "daily_saved_" + site_id
		job.drop = fixture._drop_daily_output.bind(fixture.get_node("WorksiteMarkers/" + site_id))
		jobs[StringName(site_id)] = job
		for id: String in job.ids:
			workers[id].start_work(job.order, "clay_daily")
	for id: String in data.routes:
		var route: Dictionary = data.routes[id].duplicate(true)
		var endpoint = destinations[route.destination_id]
		for field: String in ["start", "arrival", "daily_target", "delivery_day", "delivered_today"]:
			route[field] = int(route[field])
		route.id = id
		route.site_id = StringName(route.site_id)
		route.cargo = {"item_id": "clay_lump", "quantity": int(route.cargo)}
		for field: String in ["origin", "target", "position"]:
			route[field] = _position(route[field])
		route.destination = endpoint if route.phase != "idle" else null
		route.destination_path = fixture.get_path_to(endpoint)
		route.destination_name = endpoint.display_name
		route.erase("destination_id")
		routes[id] = route
	WorkerDatabase.workers_by_id = workers
	WorkerDatabase.dismissed_workers = dismissed
	CitizenManager.citizens_by_id = citizens
	daily.jobs = jobs
	fixture.hauling.routes = routes
	daily.hauler_setups.clear()
	for site_id in fixture.sites:
		fixture.sites[site_id].stock = int(data.sites[str(site_id)].stock)
		fixture.sites[site_id].participants.clear()
		daily.selected[site_id] = []
	daily.ledger_day = int(data.ledger.day)
	daily.last_tick = int(data.ledger.last_tick)
	daily.last_stock_day = int(data.ledger.stock_day)
	daily.minutes_by_worker = _int_values(data.ledger.minutes)
	daily.rng.seed = int(data.ledger.rng_seed)
	daily.rng.state = int(data.ledger.rng_state)
	fixture.worker_management.productive_days.clear()
	for id: String in data.productive_days:
		fixture.worker_management.productive_days[id] = _int_days(data.productive_days[id])
	fixture.worker_management.contributions = _int_values(data.contributions)
	fixture.city_tools.units = data.tools.duplicate(true)
	fixture.worker_journeys.clear()
	fixture.journey_cache_day = int(data.journey_day)
	for key: String in data.journeys:
		var journey: Dictionary = data.journeys[key].duplicate()
		journey.origin = _position(journey.origin)
		journey.target = _position(journey.target)
		fixture.worker_journeys[key] = journey
	for pile: Node in fixture.get_node("GroundOutput").get_children():
		pile.free()
	for saved: Dictionary in data.ground:
		var callback: Callable = Callable()
		if not saved.site_id.is_empty():
			callback = fixture._drop_daily_output.bind(fixture.get_node("WorksiteMarkers/" + saved.site_id))
		fixture._drop_output_at(int(saved.quantity), _position(saved.position), callback)
		if not saved.site_id.is_empty():
			fixture.get_node("GroundOutput").get_child(-1).set_meta("daily_site", saved.site_id)
	Inventory.items.clear()
	for id: String in data.inventory:
		Inventory.items[id] = int(data.inventory[id])
	Inventory.max_load = float(data.inventory_capacity)
	fixture.player.position = _position(data.player_position)
	fixture.player.velocity = Vector2.ZERO
	fixture.player.current_interactable = null
	var visuals = fixture.get_node("WorkerVisuals")
	for actor: Node in visuals.actors.values():
		actor.free()
	visuals.actors.clear()
	visuals.roaming.clear()
	visuals.work_cycles.clear()
	visuals.last_minute = -1
	visuals.fraction = 0.0
	TimeComponentManager.current_day = int(data.clock.day)
	TimeComponentManager.current_hour = int(data.clock.hour)
	TimeComponentManager.current_minute = int(data.clock.minute)
	TimeComponentManager.current_weather = data.clock.weather
	TimeComponentManager._timer = 0.0
	# Refresh the existing environment calculation without replaying shift/day
	# gameplay signals. A paused menu must already show the restored lighting.
	var signals_were_blocked: bool = TimeComponentManager.is_blocking_signals()
	TimeComponentManager.set_block_signals(true)
	TimeComponentManager.day_cycle()
	TimeComponentManager.set_block_signals(signals_were_blocked)
	TimeComponentManager.environment.color = TimeComponentManager._target_environment_color
	daily._sync_activities()
	for id: String in destinations:
		var endpoint = destinations[id]
		var storage = endpoint.get_storage()
		storage.capacity = int(data.storages[id].capacity)
		storage.quantity = int(data.storages[id].quantity)
		endpoint.accepting_deliveries = data.storages[id].accepting
		storage.changed.emit()
	Inventory.items_changed.emit()
	fixture.city_tools.changed.emit()
	TimeComponentManager.time_changed.emit(int(data.clock.day), int(data.clock.hour), int(data.clock.minute), data.clock.weather)
	return true

func validate(data: Variant, fixture: Node, destinations: Dictionary) -> bool:
	error = ""
	if not data is Dictionary or not _check(data.get("schema_version"), [VERSION, VERSION]) or not _check(data.get("scenario"), "text") or data.scenario != SCENARIO:
		return _fail("Unsupported save version or scenario.")
	var root_fields: Dictionary = {"schema_version": "count", "scenario": "text", "clock": "map",
		"workers": "map", "dismissed": "map", "citizens": "map", "tools": "map", "storages": "map",
		"sites": "map", "jobs": "map", "routes": "map", "journeys": "map", "ledger": "map",
		"productive_days": "map", "contributions": "map", "journey_day": "day", "ground": "list",
		"inventory": "map", "inventory_capacity": [0.0, 1000000.0], "player_position": "vector"}
	if not _record(data, root_fields, "save") or not _record(data.clock, {"day": "count", "hour": [0, 23], "minute": [0, 59], "weather": "text"}, "clock"):
		return false
	if data.clock.weather not in ["clear", "cloudy", "rainy", "storm"]:
		return _fail("Unknown weather.")
	var day: int = int(data.clock.day)
	var now: int = day * 1440 + int(data.clock.hour) * 60 + int(data.clock.minute)
	var known: Dictionary = {}
	for group: String in ["workers", "dismissed"]:
		for id in data[group]:
			if not _check(id, "id") or known.has(id) or not _record(data[group][id], WORKER_FIELDS, group):
				return _fail("Invalid or duplicate worker: " + str(id))
			if data[group][id].worker_id != id:
				return _fail("Worker ID mismatch.")
			known[id] = data[group][id]
	for id in data.citizens:
		var fields: Dictionary = CITIZEN_FIELDS.duplicate()
		fields.profile = "map"
		if not _check(id, "id") or not _record(data.citizens[id], fields, "citizen"):
			return false
		var citizen: Dictionary = data.citizens[id]
		if citizen.citizen_id != id or (not citizen.profile.is_empty() and not _record(citizen.profile, PROFILE_FIELDS, "profile")):
			return _fail("Invalid citizen identity/profile.")
		if data.workers.has(id) and (citizen.population_status != CitizenData.PopulationStatus.RESIDENT or citizen.employment_status != CitizenData.EmploymentStatus.HIRED):
			return _fail("Worker employment does not match the prototype roster.")
		if data.dismissed.has(id) and citizen.employment_status in [CitizenData.EmploymentStatus.HIRED, CitizenData.EmploymentStatus.ASSIGNED]:
			return _fail("Dismissed worker is still employed.")
	if not _same_keys(data.sites, fixture.sites) or not _same_keys(data.storages, destinations):
		return _fail("Worksite/storage registry differs from this save.")
	for id: String in data.sites:
		if not _record(data.sites[id], {"stock": "count"}, "site"):
			return false
	for id: String in data.storages:
		if not _record(data.storages[id], {"quantity": "count", "capacity": "count", "accepting": "bool"}, "storage"):
			return false
		if data.storages[id].quantity > data.storages[id].capacity:
			return _fail("Storage exceeds capacity.")
	var occupied: Dictionary = {}
	var carts: Dictionary = {}
	for id in data.tools:
		if not _check(id, "id") or not _record(data.tools[id], {"name": "text", "tool_id": "id", "worker_id": "text"}, "tool"):
			return false
		var unit: Dictionary = data.tools[id]
		if unit.tool_id not in ["cart", "stone_hammer", "basic_glove"]:
			return _fail("Unknown tool type.")
		if not unit.worker_id.is_empty():
			var slot: String = fixture.worker_management.tool_slot(unit.tool_id)
			var key: String = unit.worker_id + ":" + slot
			if not data.workers.has(unit.worker_id) or occupied.has(key):
				return _fail("Tool owner unavailable or equipment slot duplicated.")
			occupied[key] = true
			if unit.tool_id == "cart":
				carts[unit.worker_id] = true
	var assignments: Dictionary = {}
	for site_id in data.jobs:
		if not data.sites.has(site_id) or not _record(data.jobs[site_id], {"ids": "list", "units": "count", "progress": "map", "starts": "map", "stats": "map"}, "job"):
			return _fail("Invalid job/worksite.")
		var job: Dictionary = data.jobs[site_id]
		if job.ids.is_empty() or job.ids.size() > 2 or job.starts.size() != job.ids.size() or job.stats.size() != job.ids.size():
			return _fail("Invalid worker slots or job records.")
		for id in job.ids:
			if not _check(id, "id") or not data.workers.has(id) or assignments.has(id):
				return _fail("Assigned worker missing or duplicated.")
			assignments[id] = site_id
			if not _check(job.starts.get(id), "count") or int(job.starts[id]) % 1440 != 420 or int(job.starts[id]) > (day + 1) * 1440 + 420:
				return _fail("Invalid assignment start.")
			if not _record(job.stats.get(id), {"days": "days", "output": "count"}, "job stats") or not _valid_days(job.stats[id].days, day):
				return _fail("Invalid productive days.")
			if data.workers[id].profession == WorkerData.Profession.HAULER and (not data.routes.has(id) or not carts.has(id)):
				return _fail("Assigned Hauler has no route or exclusive cart.")
		for id in job.progress:
			if not job.ids.has(id) or not _check(job.progress[id], [0, 9]):
				return _fail("Invalid partial gathering progress.")
	for id in data.routes:
		if not assignments.has(id) or data.workers[id].profession != WorkerData.Profession.HAULER or not _record(data.routes[id], ROUTE_FIELDS, "route"):
			return _fail("Invalid Hauler route.")
		var route: Dictionary = data.routes[id]
		if route.site_id != assignments[id] or not destinations.has(route.destination_id):
			return _fail("Hauler destination/worksite is unavailable.")
		if route.phase not in ["idle", "outbound", "returning"] or route.direction not in ["left", "right"] or route.arrival < route.start or route.start > now:
			return _fail("Invalid Hauler travel state.")
		if (route.phase == "idle" and route.cargo != 0) or (route.phase == "outbound" and route.cargo == 0):
			return _fail("Cargo disagrees with route phase.")
		if route.delivery_day > day or route.delivered_today > route.daily_target:
			return _fail("Invalid daily delivery accounting.")
		if route.phase != "idle" and not _position(route.target).is_equal_approx(destinations[route.destination_id].get_arrival_position()):
			return _fail("In-flight destination position changed.")
	if not _record(data.ledger, {"day": "day", "last_tick": "count", "stock_day": "count", "minutes": "map", "rng_seed": "int64", "rng_state": "int64"}, "ledger"):
		return false
	if data.ledger.last_tick != now or data.ledger.stock_day != day or data.ledger.day > day:
		return _fail("Clock and work ledger disagree.")
	for id in data.ledger.minutes:
		if not known.has(id) or not _check(data.ledger.minutes[id], [0, 480]):
			return _fail("Invalid daily minutes.")
	if not _same_keys(data.productive_days, data.contributions):
		return _fail("Contribution/day records disagree.")
	for id in data.productive_days:
		if not known.has(id) or not _valid_days(data.productive_days[id], day) or not _check(data.contributions[id], "count"):
			return _fail("Invalid worker contribution history.")
		if data.contributions[id] > known[id].profession_xp:
			return _fail("Contribution count exceeds earned XP.")
	for key in data.journeys:
		if not key is String or key.length() > 512 or not _record(data.journeys[key], {"origin": "vector", "target": "vector", "start": [-1000000.0, 1000000000.0], "arrival": "count"}, "journey"):
			return false
		if data.journeys[key].start > data.journeys[key].arrival:
			return _fail("Invalid commute time.")
	if data.journey_day > day:
		return _fail("Invalid commute cache day.")
	for pile in data.ground:
		if not _record(pile, {"item_id": "id", "quantity": [1, 1000000000], "position": "vector", "site_id": "text"}, "ground pile"):
			return false
		if pile.item_id != "clay_lump" or (not pile.site_id.is_empty() and not data.sites.has(pile.site_id)):
			return _fail("Unknown ground output/worksite.")
	for id in data.inventory:
		if not _check(id, "id") or ItemDatabase.get_item_data(id) == null or not _check(data.inventory[id], [1, 1000000000]):
			return _fail("Unknown inventory item or invalid quantity.")
	return true

func _record(value: Variant, fields: Dictionary, label: String) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return _fail("Invalid " + label + " fields.")
	for field: String in fields:
		if not _check(value.get(field), fields[field]):
			return _fail("Invalid " + label + "." + field)
	return true

func _check(value: Variant, rule: Variant) -> bool:
	if rule is Array:
		return (value is int or value is float) and is_finite(float(value)) and value >= rule[0] and value <= rule[1] and (rule[0] is float or float(value) == floor(float(value)))
	match rule:
		"count": return _check(value, [0, 1000000000])
		"day": return _check(value, [-1, 1000000])
		"bool": return value is bool
		"text": return value is String and value.length() <= 512
		"id": return value is String and not value.is_empty() and value.length() <= 128 and ("id_" + value.replace("-", "_")).is_valid_identifier()
		"int64": return value is String and value.is_valid_int() and str(int(value)) == value
		"map": return value is Dictionary and value.size() <= 10000
		"list": return value is Array and value.size() <= 10000
		"days": return _valid_days(value, 1000000)
		"vector": return value is Array and value.size() == 2 and _check(value[0], [-1000000.0, 1000000.0]) and _check(value[1], [-1000000.0, 1000000.0])
	return false

func _valid_days(value: Variant, maximum: int) -> bool:
	if not value is Array or value.size() > 10000:
		return false
	var unique: Dictionary = {}
	for day in value:
		if not _check(day, [0, maximum]) or unique.has(int(day)):
			return false
		unique[int(day)] = true
	return true

func _same_keys(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key in left:
		if not right.has(key):
			return false
	return true

func _fail(message: String) -> bool:
	if error.is_empty():
		error = message
	return false

func _fields(source: Object, fields: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for field: String in fields:
		result[field] = source.get(field)
	return result

func _assign_fields(target: Object, data: Dictionary, fields: Dictionary) -> void:
	for field: String in fields:
		var rule: Variant = fields[field]
		var integer_field: bool = (rule is String and rule == "count") or (rule is Array and rule[0] is int)
		target.set(field, int(data[field]) if integer_field else data[field])

func _worker(data: Dictionary) -> WorkerData:
	var worker := WorkerData.new()
	_assign_fields(worker, data, WORKER_FIELDS)
	return worker

func _int_values(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in source:
		result[key] = int(source[key])
	return result

func _int_days(source: Array) -> Array:
	var result: Array = []
	for day in source:
		result.append(int(day))
	return result

func _vector(value: Vector2) -> Array:
	return [value.x, value.y]

func _position(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func _destination_id(endpoint: Node, destinations: Dictionary) -> String:
	for id: String in destinations:
		if destinations[id] == endpoint:
			return id
	return ""
