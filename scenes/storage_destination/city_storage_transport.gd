extends Node

## One-shot, city-owned hauling between the central store and its annex.
## The route is the only owner of an item after source pickup and before receipt.
signal changed
signal resignation_ready(worker_id: String)

const CITY_ID: String = "city"
const ANNEX_ID: String = "annex"
const CAPACITY: int = 3
const SHIFT_START: int = 7 * 60
const SHIFT_END: int = 15 * 60
const WALK_SPEED: float = 10.0
const FEET_OFFSET: Vector2 = Vector2(0.0, 16.0)
const WORK_ORDER_ID: String = "city_storage_transport"
const WORK_JOB_ID: String = "city_storage_transport"
const MAX_MINUTE: int = 1000000000
const MAX_INT_VALUE: int = 9223372036854775807

var route: Dictionary = {}
var last_tick: int = -1
var worker_ids: Array[String] = []

var _central_storage: Node
var _central_position: Vector2 = Vector2.ZERO
var _annex_position: Vector2 = Vector2.ZERO
var _transaction_busy: bool = false

func _enter_tree() -> void:
	add_to_group("city_storage_transport")
	if not TimeComponentManager.time_changed.is_connected(_on_time_changed):
		TimeComponentManager.time_changed.connect(_on_time_changed)
	if not WorkerDatabase.payroll_changed.is_connected(_on_payroll_changed):
		WorkerDatabase.payroll_changed.connect(_on_payroll_changed)

func _ready() -> void:
	if last_tick < 0:
		last_tick = _now()

func _exit_tree() -> void:
	if TimeComponentManager.time_changed.is_connected(_on_time_changed):
		TimeComponentManager.time_changed.disconnect(_on_time_changed)
	if WorkerDatabase.payroll_changed.is_connected(_on_payroll_changed):
		WorkerDatabase.payroll_changed.disconnect(_on_payroll_changed)

## Rebinding a recreated city scene preserves the annex's city stock and any
## loaded route. The Annex storage node is owned by this persistent manager.
func configure(central_storage: Node, central_position: Vector2, annex_position: Vector2) -> void:
	if is_instance_valid(central_storage):
		_central_storage = central_storage
	# DeliveryPoint marks feet. Existing worker visuals place the actor root
	# sixteen pixels above that point and collision checks restore the feet offset.
	_central_position = central_position - FEET_OFFSET
	_annex_position = annex_position - FEET_OFFSET
	if last_tick < 0:
		last_tick = _now()
	if not route.is_empty():
		_rebind_route_worker()

func get_storage(id: String) -> Node:
	if id == CITY_ID:
		return _central_storage if is_instance_valid(_central_storage) else null
	if id == ANNEX_ID:
		return get_node_or_null("Annex")
	return null

func eligible_workers() -> Array:
	var result: Array = []
	if _transaction_busy or not route.is_empty() or not _within_pickup_shift(_now()):
		return result
	for worker: WorkerData in WorkerDatabase.get_all_workers():
		if _is_eligible_worker(worker):
			result.append(worker)
	result.sort_custom(func(a: WorkerData, b: WorkerData) -> bool:
		return a.get_resolved_display_name().naturalnocasecmp_to(b.get_resolved_display_name()) < 0
	)
	return result

func available_items(id: String) -> Dictionary:
	var storage: Node = get_storage(id)
	var result: Dictionary = {}
	if not _is_storage(storage):
		return result
	var stacks: Variant = storage.get("items")
	if not stacks is Dictionary:
		return result
	var item_ids: Array[String] = []
	for item_id_value: Variant in stacks.keys():
		if not item_id_value is String:
			continue
		var item_id: String = item_id_value
		if not _is_transfer_item(item_id):
			continue
		var quantity: int = int(storage.call("get_city_transfer_available", item_id))
		if quantity > 0:
			item_ids.append(item_id)
	item_ids.sort()
	for item_id: String in item_ids:
		result[item_id] = int(storage.call("get_city_transfer_available", item_id))
	return result

func start(worker_id: String, source: String, item_id: String, quantity: int) -> bool:
	if _transaction_busy or not route.is_empty() or not _within_pickup_shift(_now()):
		return false
	if quantity <= 0 or quantity > CAPACITY or source not in [CITY_ID, ANNEX_ID] or not _is_transfer_item(item_id):
		return false
	var destination: String = ANNEX_ID if source == CITY_ID else CITY_ID
	var source_storage: Node = get_storage(source)
	var destination_storage: Node = get_storage(destination)
	if not _is_storage(source_storage) or not _is_storage(destination_storage):
		return false
	if not bool(source_storage.call("can_take_city_transfer", item_id, quantity)):
		return false
	if not bool(destination_storage.call("can_receive_city_transfer", item_id, quantity)):
		return false
	var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
	if not _is_eligible_worker(worker):
		return false
	if worker.profession == WorkerData.Profession.HAULER \
		and (worker.profession_xp < 0 or worker.profession_xp > MAX_INT_VALUE - quantity):
		return false
	if not WorkerDatabase.assign_worker(worker_id):
		return false

	var current: int = _now()
	last_tick = current
	var source_position: Vector2 = _position_for(source)
	var destination_position: Vector2 = _position_for(destination)
	if not _path_is_clear(source_position, destination_position):
		WorkerDatabase.unassign_worker(worker_id)
		return false
	var leg_minutes: int = _travel_minutes(source_position.distance_to(destination_position))
	worker.start_work(WORK_ORDER_ID, WORK_JOB_ID)
	worker.current_work_status = WorkerData.WorkStatus.TRAVELLING
	route = {
		"worker_id": worker_id,
		"item_id": item_id,
		"quantity": quantity,
		"source": source,
		"destination": destination,
		"phase": "outbound",
		"start": current,
		"arrival": current + leg_minutes,
		"resigning": false,
		"leg_origin": source_position
	}
	worker_ids = [worker_id]
	_transaction_busy = true
	var taken: bool = bool(source_storage.call("take_city_transfer", item_id, quantity))
	if not taken:
		_clear_route_and_release(false)
		_transaction_busy = false
		WorkerDatabase.on_work_owner_transaction_finished()
		return false
	changed.emit()
	_transaction_busy = false
	return true

func cancel() -> bool:
	if _transaction_busy or route.is_empty():
		return false
	_transaction_busy = true
	var current: int = _now()
	var cargo: int = int(route.get("quantity", 0))
	if cargo <= 0:
		_clear_route_and_release(false)
	elif str(route.get("phase", "")) == "outbound":
		var visual: Dictionary = _get_visual(current)
		var position: Vector2 = Vector2(visual.get("position", _position_for(str(route.destination))))
		route["phase"] = "returning"
		route["leg_origin"] = position
		route["start"] = current
		route["arrival"] = current + _travel_minutes(position.distance_to(_position_for(str(route.source))))
		_set_worker_activity(WorkerData.WorkStatus.TRAVELLING)
	else:
		# A loaded return already has the correct owner and direction.
		if int(route.get("arrival", current)) <= current:
			_process_arrival(current)
	if not route.is_empty():
		changed.emit()
	_transaction_busy = false
	if route.is_empty():
		WorkerDatabase.on_work_owner_transaction_finished()
	return true

func resign_worker(worker_id: String) -> bool:
	if not has_worker(worker_id):
		return true
	if bool(route.get("resigning", false)):
		return true
	if _transaction_busy:
		route["resigning"] = true
		return false
	_transaction_busy = true
	route["resigning"] = true
	if int(route.get("quantity", 0)) <= 0:
		_clear_route_and_release(true)
		_transaction_busy = false
		WorkerDatabase.on_work_owner_transaction_finished()
		return true
	changed.emit()
	_transaction_busy = false
	# Keep the existing reservation until this load is either accepted or
	# returned. Notifying the resignation sweep here would reenter this method.
	return true

func has_worker(id: String) -> bool:
	return worker_ids.has(id)

func is_transaction_busy() -> bool:
	return _transaction_busy

func rebind_after_restore() -> void:
	worker_ids.clear()
	if route.is_empty():
		return
	if not validate_restore(route, last_tick):
		push_error("CityStorageTransport: restored route is invalid.")
		return
	_rebind_route_worker()

## Validate the value-only route shape. CitySave separately checks the worker,
## citizen and allocated-cart snapshots before applying any restored state.
func validate_restore(saved_route: Dictionary, saved_last_tick: int) -> bool:
	if saved_last_tick < 0 or saved_last_tick > MAX_MINUTE:
		return false
	if saved_route.is_empty():
		return true
	if saved_route.size() != 10:
		return false
	for key: String in ["worker_id", "item_id", "source", "destination", "phase"]:
		if not saved_route.has(key) or typeof(saved_route[key]) != TYPE_STRING:
			return false
	for key: String in ["quantity", "start", "arrival"]:
		if not saved_route.has(key) or typeof(saved_route[key]) != TYPE_INT:
			return false
	if not saved_route.has("resigning") or typeof(saved_route.resigning) != TYPE_BOOL:
		return false
	if not saved_route.has("leg_origin") or typeof(saved_route.leg_origin) != TYPE_VECTOR2:
		return false
	var worker_id: String = str(saved_route.worker_id)
	var item_id: String = str(saved_route.item_id)
	var source: String = str(saved_route.source)
	var destination: String = str(saved_route.destination)
	var phase: String = str(saved_route.phase)
	var quantity: int = int(saved_route.quantity)
	var start_minute: int = int(saved_route.start)
	var arrival_minute: int = int(saved_route.arrival)
	var point: Vector2 = saved_route.leg_origin
	if worker_id.is_empty() or worker_id != worker_id.strip_edges() or not _is_transfer_item(item_id):
		return false
	if source not in [CITY_ID, ANNEX_ID] or destination not in [CITY_ID, ANNEX_ID] or source == destination:
		return false
	if phase not in ["outbound", "returning"] or quantity < 0 or quantity > CAPACITY:
		return false
	if phase == "outbound" and quantity <= 0:
		return false
	if start_minute < 0 or start_minute > saved_last_tick or arrival_minute < start_minute or arrival_minute > MAX_MINUTE:
		return false
	if not is_finite(point.x) or not is_finite(point.y) or point.length() > 1000000.0:
		return false
	var source_point: Vector2 = _position_for(source)
	var destination_point: Vector2 = _position_for(destination)
	if point.distance_to(Geometry2D.get_closest_point_to_segment(point, source_point, destination_point)) > 0.1:
		return false
	return true

func get_visual(absolute_minute: float) -> Dictionary:
	if route.is_empty():
		return {}
	return _get_visual(absolute_minute)

func _on_time_changed(day: int, hour: int, minute: int, _weather: String) -> void:
	tick(day * 1440 + hour * 60 + minute)

func _on_payroll_changed() -> void:
	if route.is_empty():
		return
	_sync_worker_activity(_now())
	changed.emit()

func tick(current: int) -> void:
	if _transaction_busy:
		return
	if route.is_empty():
		# Clock snapshots and test fixtures can jump or reset the clock while no
		# cargo exists. Keep the save cursor in sync without iterating empty time.
		last_tick = current
		return
	if current <= last_tick:
		return
	var had_route: bool = not route.is_empty()
	_transaction_busy = true
	while last_tick < current:
		var previous: int = last_tick
		last_tick += 1
		if route.is_empty():
			last_tick = current
			break
		var worker: WorkerData = WorkerDatabase.get_worker_data(str(route.get("worker_id", "")))
		if worker != null and not bool(route.get("resigning", false)) \
			and worker.get_payroll_unpaid_minutes(previous, last_tick) > 0:
			route.start = int(route.start) + 1
			route.arrival = int(route.arrival) + 1
			_set_worker_activity(WorkerData.WorkStatus.RESTING)
			continue
		if not _pause_if_blocked(last_tick):
			continue
		_sync_worker_activity(last_tick)
		if last_tick >= int(route.arrival):
			_process_arrival(last_tick)
	_transaction_busy = false
	if had_route:
		changed.emit()
		if route.is_empty():
			WorkerDatabase.on_work_owner_transaction_finished()

func _process_arrival(current: int) -> void:
	if route.is_empty():
		return
	var phase: String = str(route.get("phase", ""))
	var quantity: int = int(route.get("quantity", 0))
	var resigning: bool = bool(route.get("resigning", false))
	if phase == "outbound":
		var destination_storage: Node = get_storage(str(route.destination))
		var worker: WorkerData = WorkerDatabase.get_worker_data(str(route.worker_id))
		if quantity <= 0 or worker == null or not _is_storage(destination_storage):
			return
		if worker.profession == WorkerData.Profession.HAULER \
			and (worker.profession_xp < 0 or worker.profession_xp > MAX_INT_VALUE - quantity):
			return
		if not destination_storage.call("can_receive_city_transfer", str(route.item_id), quantity):
			if resigning:
				_begin_return_from_endpoint(current)
			return
		# Publish zero cargo before the destination emits changed. If its observers
		# reenter this manager, the route already reflects the committed ownership.
		route.quantity = 0
		route.phase = "returning"
		route.leg_origin = _position_for(str(route.destination))
		route.start = current
		route.arrival = current + _travel_minutes(
			Vector2(route.leg_origin).distance_to(_position_for(str(route.source))))
		_transaction_busy = true
		var received: bool = bool(destination_storage.call("receive_city_transfer", str(route.item_id), quantity))
		if not received:
			route.quantity = quantity
			route.phase = "outbound"
			route.leg_origin = _position_for(str(route.source))
			route.start = current
			route.arrival = current
		else:
			if worker.profession == WorkerData.Profession.HAULER:
				worker.profession_xp += quantity
			if resigning:
				_clear_route_and_release(true)
		return
	if phase == "returning" and quantity > 0:
		var source_storage: Node = get_storage(str(route.source))
		if not _is_storage(source_storage) or not source_storage.call("can_receive_city_transfer", str(route.item_id), quantity):
			return
		route.quantity = 0
		_transaction_busy = true
		var returned: bool = bool(source_storage.call("receive_city_transfer", str(route.item_id), quantity))
		if not returned:
			route.quantity = quantity
			return
		_clear_route_and_release(resigning)
		return
	if phase == "returning" and quantity == 0:
		_clear_route_and_release(resigning)

func _begin_return_from_endpoint(current: int) -> void:
	if route.is_empty():
		return
	var endpoint_position: Vector2 = _position_for(str(route.destination))
	route.phase = "returning"
	route.leg_origin = endpoint_position
	route.start = current
	route.arrival = current + _travel_minutes(endpoint_position.distance_to(_position_for(str(route.source))))
	_set_worker_activity(WorkerData.WorkStatus.TRAVELLING)

func _pause_if_blocked(minute: int) -> bool:
	var phase: String = str(route.get("phase", ""))
	if phase not in ["outbound", "returning"]:
		return false
	var visual: Dictionary = _get_visual(minute)
	var origin: Vector2 = Vector2(route.get("leg_origin", _position_for(str(route.source))))
	var target: Vector2 = _leg_target(route)
	var position: Vector2 = Vector2(visual.get("position", origin))
	if not _navigation_available() or bool(visual.get("blocked", false)):
		route.start = minute
		route.arrival = minute + _travel_minutes(origin.distance_to(target))
		_set_worker_activity(WorkerData.WorkStatus.RESTING)
		return false
	# Anchor each elapsed minute at the last collision-clear point. If new map
	# geometry blocks the next segment, the next tick can wait there safely.
	route.leg_origin = position
	route.start = minute
	route.arrival = minute + _travel_minutes(position.distance_to(target))
	return true

func _get_visual(absolute_minute: float) -> Dictionary:
	if route.is_empty():
		return {}
	var worker_id: String = str(route.get("worker_id", ""))
	var from_minute: int = int(floor(absolute_minute))
	var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
	if worker != null and not bool(route.get("resigning", false)) \
		and worker.get_payroll_unpaid_minutes(from_minute, from_minute + 1) > 0:
		absolute_minute = float(from_minute)
	var start_minute: float = float(route.get("start", absolute_minute))
	var arrival_minute: float = float(route.get("arrival", start_minute))
	var from: Vector2 = Vector2(route.get("leg_origin", _position_for(str(route.get("source", CITY_ID)))))
	var to: Vector2 = _leg_target(route)
	var duration: float = maxf(arrival_minute - start_minute, 0.0)
	var progress: float = 1.0 if duration <= 0.0 and absolute_minute >= arrival_minute else 0.0
	if duration > 0.0:
		progress = clampf((absolute_minute - start_minute) / duration, 0.0, 1.0)
	var position: Vector2 = from.lerp(to, progress)
	var moving: bool = absolute_minute >= start_minute and absolute_minute < arrival_minute
	var blocked: bool = not _navigation_available() or not _path_is_clear(from, position)
	if progress >= 1.0 and not _point_is_clear(to):
		blocked = true
	if blocked:
		moving = false
		position = from
	return {
		"position": position,
		"moving": moving,
		"blocked": blocked,
		"direction": "left" if to.x < from.x else "right",
		"carrying": int(route.get("quantity", 0)),
		"item_id": str(route.get("item_id", ""))
	}

func _leg_target(value: Dictionary) -> Vector2:
	if str(value.get("phase", "")) == "outbound":
		return _position_for(str(value.get("destination", ANNEX_ID)))
	return _position_for(str(value.get("source", CITY_ID)))

func _clear_route_and_release(resignation_complete: bool) -> void:
	var worker_id: String = str(route.get("worker_id", ""))
	var worker: WorkerData = WorkerDatabase.get_worker_data(worker_id)
	route.clear()
	worker_ids.clear()
	if worker != null and worker.current_order_id == WORK_ORDER_ID:
		worker.finish_work(WORK_ORDER_ID)
		WorkerDatabase.unassign_worker(worker_id)
	changed.emit()
	if resignation_complete and worker != null:
		resignation_ready.emit(worker_id)

func _rebind_route_worker() -> void:
	worker_ids.clear()
	if route.is_empty():
		return
	var worker_id: String = str(route.get("worker_id", ""))
	if not worker_id.is_empty():
		worker_ids.append(worker_id)

func _is_eligible_worker(worker: WorkerData) -> bool:
	if worker == null or worker.worker_id.is_empty():
		return false
	if worker.profession not in [WorkerData.Profession.LABORER, WorkerData.Profession.HAULER]:
		return false
	if worker.is_reserved() or worker.current_work_status != WorkerData.WorkStatus.IDLE \
		or not worker.current_job_id.is_empty() or not worker.physical_approach.is_empty():
		return false
	if worker.resignation_pending or worker.is_payroll_blocked() or worker.get_resolved_satisfaction() <= 0.0:
		return false
	var citizen: CitizenData = worker.get_linked_citizen()
	if citizen != null and (citizen.employment_status != CitizenData.EmploymentStatus.HIRED or not citizen.can_be_assigned()):
		return false
	if WorkerDatabase.has_method("_has_workshop_assignment") and bool(WorkerDatabase.call("_has_workshop_assignment", worker.worker_id)):
		return false
	var city: Node = get_storage(CITY_ID)
	var annex: Node = get_storage(ANNEX_ID)
	return (_is_storage(city) and bool(city.call("has_equipped", worker.worker_id, "cart"))) \
		or (_is_storage(annex) and bool(annex.call("has_equipped", worker.worker_id, "cart")))

func _is_transfer_item(item_id: String) -> bool:
	if item_id.is_empty() or item_id == "shekel":
		return false
	var city: Node = get_storage(CITY_ID)
	var annex: Node = get_storage(ANNEX_ID)
	if _is_storage(city) and city.has_method("_is_city_transfer_item"):
		return bool(city.call("_is_city_transfer_item", item_id))
	if _is_storage(annex) and annex.has_method("_is_city_transfer_item"):
		return bool(annex.call("_is_city_transfer_item", item_id))
	var item_data: ItemData = ItemDatabase.get_item_data(item_id)
	return item_data != null and item_data.category != ItemEnums.ItemCategory.EQUIPMENT

func _is_storage(storage: Node) -> bool:
	return is_instance_valid(storage) and storage.has_method("get_city_transfer_available") \
		and storage.has_method("can_take_city_transfer") and storage.has_method("take_city_transfer") \
		and storage.has_method("can_receive_city_transfer") and storage.has_method("receive_city_transfer")

func _position_for(id: String) -> Vector2:
	return _annex_position if id == ANNEX_ID else _central_position

func _within_pickup_shift(minute: int) -> bool:
	var time_of_day: int = minute % 1440
	return time_of_day >= SHIFT_START and time_of_day < SHIFT_END

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _travel_minutes(distance: float) -> int:
	return maxi(1, ceili(distance / WALK_SPEED)) if distance > 0.0 else 0

func _current_navigation() -> Object:
	var current_scene: Node = get_tree().current_scene if is_inside_tree() else null
	if current_scene != null:
		var runtime: Node = current_scene.find_child("WorkerRuntime", true, false)
		if runtime != null:
			var navigation: Variant = runtime.get("worksite_navigation")
			if navigation is Object and navigation.has_method("segment_clear"):
				return navigation
	var city_save: Node = WorkStateRuntime.get_node_or_null("CitySave")
	if city_save != null and is_instance_valid(city_save.get("parked_worksite")):
		var parked: Node = city_save.get("parked_worksite")
		var navigation: Variant = parked.get("worksite_navigation")
		if navigation is Object and navigation.has_method("segment_clear"):
			return navigation
	return null

func _path_is_clear(from: Vector2, to: Vector2) -> bool:
	var navigation: Object = _current_navigation()
	if navigation == null:
		return false
	return bool(navigation.call("segment_clear", from + FEET_OFFSET, to + FEET_OFFSET))

func _point_is_clear(point: Vector2) -> bool:
	var navigation: Object = _current_navigation()
	if navigation == null or not navigation.has_method("is_clear"):
		return false
	return bool(navigation.call("is_clear", point + FEET_OFFSET))

func _navigation_available() -> bool:
	return _current_navigation() != null

func _sync_worker_activity(current: int) -> void:
	if route.is_empty():
		return
	var worker: WorkerData = WorkerDatabase.get_worker_data(str(route.get("worker_id", "")))
	if worker == null:
		return
	if worker.is_payroll_blocked() and not bool(route.get("resigning", false)):
		worker.current_work_status = WorkerData.WorkStatus.RESTING
		return
	var visual: Dictionary = _get_visual(current)
	worker.current_work_status = WorkerData.WorkStatus.TRAVELLING if bool(visual.get("moving", false)) else WorkerData.WorkStatus.RESTING

func _set_worker_activity(status: WorkerData.WorkStatus) -> void:
	if route.is_empty():
		return
	var worker: WorkerData = WorkerDatabase.get_worker_data(str(route.get("worker_id", "")))
	if worker != null:
		worker.current_work_status = status
