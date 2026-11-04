extends RefCounted

## Retained visual owner advances routes in city and home; construction supplies
## identities after the authored plot is freed. Only worker data is serialized.
const CONSTRUCTION = preload("res://scenes/workshop_plot/workshop_construction_state.gd")
const FEET: Vector2 = Vector2(0, 16)
const WALK_SPEED: float = 24.0
const ROUTE_RETRY_SECONDS: float = 1.0
# Shared across all plot workers and all explicit minute advances in the same
# rendered frame. A debug day is 1,440 separate advances, not one batch call.
const ROUTE_FRAME_BUDGET_USEC: int = 20000
const ROUTE_FRAME_BUDGET_OPERATIONS: int = 40000
const SHIFT_START: int = 7 * 60
const SHIFT_END: int = 15 * 60
# A departure must survive a time skip and save/Continue, even when no visual
# frame occurred between shifts. -1 remains the normal inbound approach.
const DEPARTING: int = WorkerData.PLOT_DEPARTURE_PENDING
var states: Dictionary = {}
var tracked: Dictionary = {}
var initial_sync: bool = true
var route_budget_frame: int = -1
var route_budget_usec: int = 0
var route_budget_operations: int = 0
var route_worker_budget: Dictionary = {}
var route_active_count: int = 1

static func is_shift_time(total_minutes: int) -> bool:
	var minute_of_day: int = total_minutes % 1440
	return minute_of_day >= SHIFT_START and minute_of_day < SHIFT_END


## Called after settling the old shift. The task and target do not change.
## A legacy empty approach represents a worker already inside the plot.
static func end_shift_for_worker(worker: WorkerData, kind: String, task: String, owner: String) -> void:
	if worker == null or kind != "plot":
		return
	if worker.physical_approach.is_empty():
		for construction: Node in WorkStateRuntime.get_children():
			if construction.get_script() == CONSTRUCTION and construction.order_id == owner:
				worker.begin_physical_approach(kind, task, owner, construction.worker_entry_position, construction.worker_entry_position)
				break
	if not worker.matches_physical_approach(kind, task, owner):
		return
	worker.physical_approach.arrived = false
	worker.physical_approach.arrival_minute = DEPARTING
	worker.current_work_status = WorkerData.WorkStatus.RESTING

func update(visuals: Node2D, delta: float, simulated_arrival_minute: int = -1, geometry_current: bool = true) -> Array[String]:
	var simulating: bool = simulated_arrival_minute >= 0
	var active: Dictionary = {}
	var live_plots: Dictionary = {}
	for plot: Node in visuals.get_tree().get_nodes_in_group("workshop_plots"):
		live_plots[plot.construction.order_id] = plot
	for construction: Node in WorkStateRuntime.get_children():
		if construction.get_script() != CONSTRUCTION:
			continue
		if construction.phase in ["clearing", "building"]:
			for id: String in construction.worker_ids:
				active[id] = {"owner": construction.order_id, "key": construction.order_id + ":" + construction.phase, "entry": construction.worker_entry_position, "shift_scheduled": true}
		for order: WorkOrder in WorkManager.active_orders.values():
			if order.worker_kind == WorkOrder.Worker_Type.NPC and order.current_status == WorkOrder.Status.RUNNING and str(order.get_meta("visual_plot_id", "")) == construction.order_id:
				active[order.worker_id] = {"owner": construction.order_id, "key": order.order_id, "entry": construction.worker_entry_position, "shift_scheduled": WorkManager.is_shaping_order(order)}
	route_active_count = maxi(1, active.size())
	var retained: Array[String] = []
	for id: String in active:
		var task: Dictionary = active[id]
		var worker: WorkerData = WorkerDatabase.get_worker_data(id)
		if worker == null:
			continue
		var actor: Node2D = visuals.ensure_actor(id, task.entry + Vector2(0, 8))
		if actor == null:
			continue
		retained.append(id)
		tracked[id] = true
		visuals.roaming.erase(id)
		visuals.work_cycles.erase(id)
		if actor.has_node("CargoLabel"):
			actor.get_node("CargoLabel").text = ""
		var now: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
		var on_shift: bool = not bool(task.shift_scheduled) or is_shift_time(now)
		if bool(task.shift_scheduled) and (not on_shift or worker.is_payroll_blocked()):
			end_shift_for_worker(worker, "plot", task.key, task.owner)
		# Legacy saves had no contradictory physical pose. Preserve their prior
		# initial-sync-inside interpretation; native assignments are nonempty.
		if worker.physical_approach.is_empty():
			actor.global_position = task.entry - FEET
			actor.hide()
			worker.current_work_status = WorkerData.WorkStatus.WORKING if on_shift and not worker.is_payroll_blocked() else WorkerData.WorkStatus.RESTING
			if on_shift and not worker.is_payroll_blocked() and live_plots.has(task.owner):
				live_plots[task.owner].mark_worker_arrived(id, task.key)
			continue
		if not worker.matches_physical_approach("plot", task.key, task.owner):
			actor.hide()
			continue
		var approach: Dictionary = worker.physical_approach
		actor.global_position = approach.position - FEET
		if not geometry_current:
			# A completed plot may have changed collision since this route was built.
			# Keep the recorded position until the owning city refreshes geometry.
			actor.visible = not approach.arrived and visuals.get_parent().enable_worker_commute
			continue
		if worker.is_payroll_blocked() and not bool(task.shift_scheduled):
			worker.current_work_status = WorkerData.WorkStatus.RESTING
			actor.visible = not approach.arrived and visuals.get_parent().enable_worker_commute
			visuals._play(actor, "idle", "right")
			continue
		if int(approach.arrival_minute) == DEPARTING:
			worker.current_work_status = WorkerData.WorkStatus.RESTING
			var departure: Vector2 = _departure_position(visuals, task)
			var previous: Vector2 = approach.position
			if simulating or (not visuals.get_tree().paused and not TimeComponentManager.is_paused and not SceneTransition.is_transitioning):
				_advance_toward(visuals, id, worker, task.key + ":departure", departure, maxf(delta, 0.0))
			actor.global_position = approach.position - FEET
			var citizen: CitizenData = CitizenManager.get_citizen(id)
			var remains_in_city: bool = is_instance_valid(visuals.resident_spawn) and citizen != null and citizen.population_status == CitizenData.PopulationStatus.RESIDENT
			actor.visible = visuals.get_parent().enable_worker_commute and (approach.position.distance_to(departure) > 0.1 or remains_in_city)
			var direction: String = "left" if approach.position.x < previous.x else "right"
			visuals._play(actor, "walk" if approach.position.distance_to(previous) > 0.001 else "idle", direction)
			# Keep the outbound sentinel until the next paid shift so repeated
			# 15:00 notifications cannot restart an already completed departure.
			if on_shift and not worker.is_payroll_blocked() and approach.position.distance_to(departure) <= 0.1:
				approach.arrival_minute = -1
			continue
		if approach.arrived:
			worker.current_work_status = WorkerData.WorkStatus.WORKING
			actor.hide()
			if live_plots.has(task.owner):
				live_plots[task.owner].mark_worker_arrived(id, task.key)
			continue
		worker.current_work_status = WorkerData.WorkStatus.TRAVELLING
		actor.visible = visuals.get_parent().enable_worker_commute
		var previous: Vector2 = approach.position
		if simulating or (not visuals.get_tree().paused and not TimeComponentManager.is_paused and not SceneTransition.is_transitioning):
			_advance_toward(visuals, id, worker, task.key, approach.target, maxf(delta, 0.0))
		actor.global_position = approach.position - FEET
		var direction: String = "left" if approach.position.x < previous.x else "right"
		visuals._play(actor, "walk" if approach.position.distance_to(previous) > 0.001 else "idle", direction)
		var verified_route: bool = states.has(id) and states[id].get("key") == task.key and states[id].get("status") == "found"
		if verified_route and approach.position.distance_to(approach.target) <= 0.1 and worker.mark_physical_arrival(task.key, simulated_arrival_minute):
			actor.hide()
			if live_plots.has(task.owner):
				live_plots[task.owner].mark_worker_arrived(id, task.key)
				if not simulating:
					live_plots[task.owner].show_worker_dust()
	for id: String in tracked.keys():
		if not active.has(id):
			if visuals.actors.has(id):
				visuals.actors[id].visible = visuals.get_parent().enable_worker_commute and WorkerDatabase.has_worker_data(id)
				visuals.roaming.erase(id)
			states.erase(id)
			tracked.erase(id)
	initial_sync = false
	return retained

func _departure_position(visuals: Node2D, task: Dictionary) -> Vector2:
	var departure: Node2D = visuals.get_parent().get_node_or_null("WorkerDeparture/NearSpawn") as Node2D
	return departure.global_position if departure != null else task.entry + Vector2(0, 24)

func _reset_route_budget(frame: int) -> void:
	route_budget_frame = frame
	route_budget_usec = ROUTE_FRAME_BUDGET_USEC
	route_budget_operations = ROUTE_FRAME_BUDGET_OPERATIONS
	route_worker_budget.clear()

func _advance_toward(visuals: Node2D, id: String, worker: WorkerData, route_key: String, target: Vector2, delta: float) -> void:
	var approach: Dictionary = worker.physical_approach
	var navigation: RefCounted = visuals.get_parent().get("worksite_navigation")
	var bounded: bool = navigation != null and navigation.has_method("begin_bounded_route")
	var nav_id: int = navigation.get_instance_id() if navigation != null else 0
	var revision: int = int(navigation.revision) if bounded else 0
	if states.has(id):
		var old: Dictionary = states[id]
		if old.get("key") != route_key or old.get("target") != target or old.get("nav_id") != nav_id or old.get("revision") != revision:
			states.erase(id)
		elif old.get("status") in ["pending", "unreachable", "limit"] and old.get("origin") != approach.position:
			states.erase(id)
	if not states.has(id):
		states[id] = {"key": route_key, "target": target, "origin": approach.position, "nav_id": nav_id,
			"revision": revision, "route": PackedVector2Array(), "index": 0, "retry": ROUTE_RETRY_SECONDS,
			"status": "pending", "search": navigation.begin_bounded_route(approach.position, target) if bounded else null}
	var state: Dictionary = states[id]
	if state.status == "retry":
		state.retry -= delta
		if state.retry > 0.0:
			return
		state.retry = ROUTE_RETRY_SECONDS
		state.status = "pending"
	if state.status == "pending" and bounded:
		var frame: int = Engine.get_process_frames()
		if route_budget_frame != frame:
			_reset_route_budget(frame)
		if route_budget_usec <= 0 or route_budget_operations <= 0:
			return
		if not route_worker_budget.has(id):
			route_worker_budget[id] = {"usec": maxi(1, ROUTE_FRAME_BUDGET_USEC / route_active_count),
				"operations": maxi(1, ROUTE_FRAME_BUDGET_OPERATIONS / route_active_count)}
		var share: Dictionary = route_worker_budget[id]
		if share.usec <= 0 or share.operations <= 0:
			return
		var started: int = Time.get_ticks_usec()
		var used: int = state.search.step(mini(route_budget_operations, int(share.operations)),
			started + mini(route_budget_usec, int(share.usec)))
		var elapsed: int = maxi(1, Time.get_ticks_usec() - started)
		route_budget_usec -= elapsed
		route_budget_operations -= used
		share.usec -= elapsed
		share.operations -= used
		state.status = state.search.status
		if state.status == "found":
			state.route = state.search.path
			state.search = null
	if state.status == "pending" and not bounded:
		# Compatibility for lightweight presentation fixtures without a planner.
		state.route = navigation.route(approach.position, target) if navigation != null else PackedVector2Array([target])
		state.status = "found" if not state.route.is_empty() else "retry"
	if state.status != "found":
		return
	var budget: float = WALK_SPEED * delta
	while state.index < state.route.size() and budget > 0.0:
		var waypoint: Vector2 = state.route[state.index]
		var step: Vector2 = approach.position.move_toward(waypoint, budget)
		if navigation != null and not navigation.segment_clear(approach.position, step):
			# Geometry changed between planning and movement; do not advance on
			# an unverified segment. The next frame plans from this same point.
			states.erase(id)
			return
		budget -= approach.position.distance_to(step)
		approach.position = step
		if approach.position.distance_to(waypoint) <= 0.01:
			state.index += 1
		else:
			break
