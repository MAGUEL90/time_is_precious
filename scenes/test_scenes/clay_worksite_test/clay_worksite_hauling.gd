extends RefCounted

## Scene-local transport for assigned Haulers.
##
## The module owns route state and cargo accounting only.  The caller owns
## storage, ground output and worker assignment.  All movement is derived from
## the supplied game-minute clock so a time skip cannot duplicate or lose a
## load.

signal delivered(id: String, quantity: int)

const CAPACITY: int = 3
const PHASE_IDLE: String = "idle"
const PHASE_OUTBOUND: String = "outbound"
const PHASE_RETURNING: String = "returning"

var routes: Dictionary = {}
var destination_provider: Callable
var assigned_destination_provider: Callable
var origin_provider: Callable
var take_output: Callable
var output_count: Callable
var return_output: Callable
var item_id: String = "clay_lump"
var speed: float = 10.0


func begin(id: String, site_id: StringName, now: int, plan: Dictionary = {}) -> void:
	if routes.has(id):
		return
	var origin: Vector2 = _origin(site_id, id)
	routes[id] = {
		"id": id,
		"site_id": site_id,
		"phase": PHASE_IDLE,
		"cargo": {"item_id": item_id, "quantity": 0},
		"origin": origin,
		"target": origin,
		"position": origin,
		"start": now,
		"arrival": now,
		"direction": "right",
		"destination": null,
		"destination_path": plan.get("destination_path", NodePath("")),
		"destination_name": str(plan.get("destination_name", "Storage")),
		"daily_target": int(plan.get("daily_target", 0)),
		"delivery_day": -1,
		"delivered_today": 0,
		"removing": false
	}


func tick(current: int, eligible: Callable, depleted: Callable) -> void:
	for id_variant in routes.keys().duplicate():
		var id: String = str(id_variant)
		if not routes.has(id):
			continue
		var route: Dictionary = routes[id]
		if route.phase == PHASE_IDLE:
			if bool(route.removing):
				routes.erase(id)
				continue
			if eligible.is_valid() and bool(eligible.call(id)):
				_begin_trip(route, id, current, depleted)
				# A zero-length route can complete deterministically in this tick.
				_process_due_route(route, id, current)
			continue
		_process_due_route(route, id, current)


func withdraw(id: String) -> bool:
	if not routes.has(id):
		return false
	var route: Dictionary = routes[id]
	route.removing = true
	if route.phase == PHASE_IDLE and _cargo_quantity(route) <= 0:
		routes.erase(id)
		return true
	return false


func finished(id: String) -> bool:
	return not routes.has(id)


func get_visual(id: String, time: float) -> Dictionary:
	if not routes.has(id):
		return {}
	var route: Dictionary = routes[id]
	var position: Vector2 = route.position
	var moving: bool = false
	if route.phase == PHASE_OUTBOUND:
		position = _position_at(route, time, route.origin, route.target)
		moving = time >= float(route.start) and time < float(route.arrival)
	elif route.phase == PHASE_RETURNING:
		position = _position_at(route, time, route.target, route.origin)
		moving = time >= float(route.start) and time < float(route.arrival)
	return {
		"position": position,
		"moving": moving,
		"direction": str(route.direction),
		"carrying": _cargo_quantity(route)
	}


func status(id: String) -> String:
	if not routes.has(id):
		return ""
	return str(routes[id].phase)

func delivered_on_day(id: String, day: int) -> int:
	if not routes.has(id) or int(routes[id].delivery_day) != day:
		return 0
	return int(routes[id].delivered_today)

func target_reached(id: String, day: int) -> bool:
	if not routes.has(id) or int(routes[id].daily_target) <= 0:
		return false
	return delivered_on_day(id, day) >= int(routes[id].daily_target)


func _begin_trip(route: Dictionary, id: String, current: int, depleted: Callable) -> void:
	if speed <= 0.0:
		return
	var site_id: StringName = route.site_id
	var load_limit: int = CAPACITY
	if int(route.daily_target) > 0:
		load_limit = mini(load_limit, int(route.daily_target) - delivered_on_day(id, current / 1440))
	if load_limit <= 0:
		return
	var available: int = _available_output(site_id)
	var quantity: int = mini(load_limit, available)
	if quantity <= 0:
		return
	var depleted_now: bool = depleted.is_valid() and bool(depleted.call(site_id))
	if available < load_limit and not depleted_now:
		return
	var destination = _destination(route)
	if not _valid_object(destination) or not destination.has_method("get_arrival_position"):
		return
	if not _destination_accepts(destination, quantity):
		return
	if not take_output.is_valid():
		return
	var taken: int = int(take_output.call(site_id, quantity))
	if taken <= 0:
		return
	# take_output is a bounded callback; keep the module invariant even if a
	# caller returns a stale amount after the availability check.
	taken = mini(taken, quantity)
	var origin: Vector2 = _origin(site_id, id)
	var target: Vector2 = _destination_position(destination)
	var duration: int = _travel_minutes(origin.distance_to(target))
	route.phase = PHASE_OUTBOUND
	route.cargo = {"item_id": item_id, "quantity": taken}
	route.origin = origin
	route.target = target
	route.position = origin
	route.start = current
	route.arrival = current + duration
	route.direction = _direction(origin, target, str(route.direction))
	route.destination = destination


func _process_due_route(route: Dictionary, id: String, current: int) -> void:
	# A clock skip may cross both legs. Consume each due phase at its scheduled
	# boundary instead of extending the trip from the observation time.
	for _transition in range(3):
		if route.phase == PHASE_OUTBOUND:
			if current < int(route.arrival):
				return
			route.position = route.target
			var destination = route.destination
			var quantity: int = _cargo_quantity(route)
			if _destination_delivers(destination, route.cargo, route.target):
				# Destination delivery is atomic. Clear local cargo only after
				# success so a failed unload can take the same load home.
				route.cargo.quantity = 0
				# Count receipt at the scheduled unloading time, never pickup or a
				# rejected attempt. A new day naturally starts with zero deliveries.
				var delivery_day: int = int(route.arrival) / 1440
				if int(route.delivery_day) != delivery_day:
					route.delivery_day = delivery_day
					route.delivered_today = 0
				route.delivered_today += quantity
				delivered.emit(id, quantity)
			_begin_return(route, int(route.arrival))
			continue
		if route.phase != PHASE_RETURNING:
			return
		if current < int(route.arrival):
			return
		route.position = route.origin
		var return_quantity: int = _cargo_quantity(route)
		if return_quantity > 0:
			if not _return_cargo(route.site_id, return_quantity):
				return
			route.cargo.quantity = 0
		if bool(route.removing):
			routes.erase(id)
		else:
			route.phase = PHASE_IDLE
			route.start = current
			route.arrival = current
		return


func _begin_return(route: Dictionary, start_time: int) -> void:
	var duration: int = _travel_minutes(route.origin.distance_to(route.target))
	route.phase = PHASE_RETURNING
	route.position = route.target
	route.start = start_time
	route.arrival = start_time + duration
	route.direction = _direction(route.target, route.origin, str(route.direction))


func _available_output(site_id: StringName) -> int:
	if not output_count.is_valid():
		return 0
	return maxi(int(output_count.call(site_id)), 0)


func _origin(site_id: StringName, id: String) -> Vector2:
	if origin_provider.is_valid():
		return origin_provider.call(site_id, id)
	return Vector2.ZERO


func _destination(route: Dictionary):
	if not NodePath(route.destination_path).is_empty():
		return assigned_destination_provider.call(route.destination_path) if assigned_destination_provider.is_valid() else null
	if destination_provider.is_valid():
		return destination_provider.call(route.site_id)
	return null


func _destination_position(destination) -> Vector2:
	if _valid_object(destination) and destination.has_method("get_arrival_position"):
		return destination.get_arrival_position()
	return Vector2.ZERO


func _destination_accepts(destination, quantity: int) -> bool:
	return _valid_object(destination) and destination.has_method("accepts_cargo") and bool(destination.accepts_cargo(item_id, quantity))


func _destination_delivers(destination, cargo: Dictionary, position: Vector2) -> bool:
	return _valid_object(destination) and destination.has_method("try_deliver_at_position") and bool(destination.try_deliver_at_position(position, cargo))


func _return_cargo(site_id: StringName, quantity: int) -> bool:
	return return_output.is_valid() and bool(return_output.call(site_id, quantity))


func _cargo_quantity(route: Dictionary) -> int:
	return maxi(int(route.cargo.get("quantity", 0)), 0)


func _travel_minutes(distance: float) -> int:
	if distance <= 0.0:
		return 0
	if speed <= 0.0:
		return 0
	return int(ceil(distance / speed))


func _position_at(route: Dictionary, time: float, start: Vector2, target: Vector2) -> Vector2:
	var duration: float = float(route.arrival) - float(route.start)
	if duration <= 0.0 or time >= float(route.arrival):
		return target
	if time <= float(route.start):
		return start
	return start.move_toward(target, maxf((time - float(route.start)) * speed, 0.0))


func _direction(from: Vector2, to: Vector2, fallback: String) -> String:
	if is_equal_approx(from.x, to.x):
		return fallback if fallback in ["left", "right"] else "right"
	return "left" if to.x < from.x else "right"


func _valid_object(value) -> bool:
	return value != null and value is Object and is_instance_valid(value)
