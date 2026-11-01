extends RefCounted

## Retained visual owner advances routes in city and home; construction supplies
## identities after the authored plot is freed. Only worker data is serialized.
const CONSTRUCTION = preload("res://scenes/workshop_plot/workshop_construction_state.gd")
const FEET: Vector2 = Vector2(0, 16)
const WALK_SPEED: float = 24.0
const ROUTE_RETRY_SECONDS: float = 1.0
const SHIFT_START: int = 7 * 60
const SHIFT_END: int = 15 * 60
# A departure must survive a time skip and save/Continue, even when no visual
# frame occurred between shifts. -1 remains the normal inbound approach.
const DEPARTING: int = WorkerData.PLOT_DEPARTURE_PENDING
var states: Dictionary = {}
var tracked: Dictionary = {}
var initial_sync: bool = true

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

func update(visuals: Node2D, delta: float) -> Array[String]:
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
		if worker.is_payroll_blocked() and not bool(task.shift_scheduled):
			worker.current_work_status = WorkerData.WorkStatus.RESTING
			actor.visible = not approach.arrived and visuals.get_parent().enable_worker_commute
			visuals._play(actor, "idle", "right")
			continue
		if int(approach.arrival_minute) == DEPARTING:
			worker.current_work_status = WorkerData.WorkStatus.RESTING
			var departure: Vector2 = _departure_position(visuals, task)
			var previous: Vector2 = approach.position
			if not visuals.get_tree().paused and not TimeComponentManager.is_paused and not SceneTransition.is_transitioning:
				_advance_toward(visuals, id, worker, task.key + ":departure", departure, maxf(delta, 0.0))
			actor.global_position = approach.position - FEET
			actor.visible = approach.position.distance_to(departure) > 0.1 and visuals.get_parent().enable_worker_commute
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
		if not visuals.get_tree().paused and not TimeComponentManager.is_paused and not SceneTransition.is_transitioning:
			_advance_toward(visuals, id, worker, task.key, approach.target, maxf(delta, 0.0))
		actor.global_position = approach.position - FEET
		var direction: String = "left" if approach.position.x < previous.x else "right"
		visuals._play(actor, "walk" if approach.position.distance_to(previous) > 0.001 else "idle", direction)
		if approach.position.distance_to(approach.target) <= 0.1 and worker.mark_physical_arrival(task.key):
			actor.hide()
			if live_plots.has(task.owner):
				live_plots[task.owner].mark_worker_arrived(id, task.key)
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

func _advance_toward(visuals: Node2D, id: String, worker: WorkerData, route_key: String, target: Vector2, delta: float) -> void:
	var approach: Dictionary = worker.physical_approach
	var navigation: RefCounted = visuals.get_parent().get("worksite_navigation")
	if states.has(id) and states[id].key == route_key and states[id].index >= states[id].route.size() and approach.position.distance_to(target) > 0.1:
		states[id].retry -= delta
		if states[id].retry > 0.0:
			return
		states.erase(id)
	if not states.has(id) or states[id].key != route_key:
		var route: PackedVector2Array = navigation.route(approach.position, target) if navigation != null else PackedVector2Array([target])
		states[id] = {"key": route_key, "route": route, "index": 0, "retry": ROUTE_RETRY_SECONDS}
	var state: Dictionary = states[id]
	var budget: float = WALK_SPEED * delta
	while state.index < state.route.size() and budget > 0.0:
		var waypoint: Vector2 = state.route[state.index]
		var step: Vector2 = approach.position.move_toward(waypoint, budget)
		if navigation != null and not navigation.segment_clear(approach.position, step):
			state.route = PackedVector2Array()
			state.index = 0
			state.retry = ROUTE_RETRY_SECONDS
			return
		budget -= approach.position.distance_to(step)
		approach.position = step
		if approach.position.distance_to(waypoint) <= 0.01:
			state.index += 1
		else:
			break
