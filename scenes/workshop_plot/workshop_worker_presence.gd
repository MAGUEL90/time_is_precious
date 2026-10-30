extends RefCounted

## Retained visual owner advances routes in city and home; construction supplies
## identities after the authored plot is freed. Only worker data is serialized.
const CONSTRUCTION = preload("res://scenes/workshop_plot/workshop_construction_state.gd")
const FEET: Vector2 = Vector2(0, 16)
const WALK_SPEED: float = 24.0
var states: Dictionary = {}
var tracked: Dictionary = {}
var initial_sync: bool = true

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
				active[id] = {"owner": construction.order_id, "key": construction.order_id + ":" + construction.phase, "entry": construction.worker_entry_position, "construction": true}
		for order: WorkOrder in WorkManager.active_orders.values():
			if order.worker_kind == WorkOrder.Worker_Type.NPC and order.current_status == WorkOrder.Status.RUNNING and str(order.get_meta("visual_plot_id", "")) == construction.order_id:
				active[order.worker_id] = {"owner": construction.order_id, "key": order.order_id, "entry": construction.worker_entry_position, "construction": false}
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
		# Legacy saves had no contradictory physical pose. Preserve their prior
		# initial-sync-inside interpretation; native assignments are nonempty.
		if worker.physical_approach.is_empty():
			actor.global_position = task.entry - FEET
			actor.hide()
			worker.current_work_status = WorkerData.WorkStatus.RESTING if worker.is_payroll_blocked() else WorkerData.WorkStatus.WORKING
			if live_plots.has(task.owner):
				live_plots[task.owner].mark_worker_arrived(id, task.key)
			continue
		if not worker.matches_physical_approach("plot", task.key, task.owner):
			actor.hide()
			continue
		var approach: Dictionary = worker.physical_approach
		actor.global_position = approach.position - FEET
		if worker.is_payroll_blocked():
			worker.current_work_status = WorkerData.WorkStatus.RESTING
			if bool(task.construction):
				# Keep the saved approach target at the authored plot entrance. An
				# unpaid builder walks away and must physically return after renewal.
				if approach.arrived:
					approach.arrived = false
					approach.arrival_minute = -1
				var departure: Vector2 = _departure_position(visuals, task)
				var previous: Vector2 = approach.position
				if not visuals.get_tree().paused and not TimeComponentManager.is_paused and not SceneTransition.is_transitioning:
					_advance_toward(visuals, id, worker, task.key + ":departure", departure, maxf(delta, 0.0))
				actor.global_position = approach.position - FEET
				actor.visible = approach.position.distance_to(departure) > 0.1 and visuals.get_parent().enable_worker_commute
				var direction: String = "left" if approach.position.x < previous.x else "right"
				visuals._play(actor, "walk" if approach.position.distance_to(previous) > 0.001 else "idle", direction)
			else:
				actor.visible = not approach.arrived and visuals.get_parent().enable_worker_commute
				visuals._play(actor, "idle", "right")
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
	if not states.has(id) or states[id].key != route_key:
		var route: PackedVector2Array = navigation.route(approach.position, target) if navigation != null else PackedVector2Array([target])
		states[id] = {"key": route_key, "route": route, "index": 0}
	var state: Dictionary = states[id]
	var budget: float = WALK_SPEED * delta
	while state.index < state.route.size() and budget > 0.0:
		var waypoint: Vector2 = state.route[state.index]
		var step: Vector2 = approach.position.move_toward(waypoint, budget)
		if navigation != null and not navigation.segment_clear(approach.position, step):
			states.erase(id)
			return
		budget -= approach.position.distance_to(step)
		approach.position = step
		if approach.position.distance_to(waypoint) <= 0.01:
			state.index += 1
		else:
			break
