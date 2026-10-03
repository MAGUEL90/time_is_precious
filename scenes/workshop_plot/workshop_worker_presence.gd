extends RefCounted

## Shares existing worksite actors; does not create a second worker simulation.
var states: Dictionary = {}
var initial_sync: bool = true
const WALK_SPEED: float = 24.0

func update(visuals: Node2D, delta: float) -> Array[String]:
	var active: Dictionary = {}
	for plot: Node in visuals.get_tree().get_nodes_in_group("workshop_plots"):
		if plot.construction.phase in ["clearing", "building"]:
			for id: String in plot.construction.worker_ids:
				active[id] = {"plot": plot, "key": plot.construction.order_id + ":" + plot.construction.phase}
		for order: WorkOrder in WorkManager.active_orders.values():
			if order.current_status == WorkOrder.Status.RUNNING and str(order.get_meta("visual_plot_id", "")) == plot.construction.order_id:
				active[order.worker_id] = {"plot": plot, "key": order.order_id}
	var retained: Array[String] = []
	for id: String in active:
		var task: Dictionary = active[id]
		var plot: Node2D = task.plot
		var entry: Vector2 = plot.get_worker_entry_position()
		var actor: Node2D = visuals.ensure_actor(id, entry + Vector2(0, 24))
		if actor == null:
			continue
		retained.append(id)
		visuals.roaming.erase(id)
		visuals.work_cycles.erase(id)
		if actor.has_node("CargoLabel"):
			actor.get_node("CargoLabel").text = ""
		if not states.has(id) or states[id].key != task.key:
			states[id] = {"key": task.key, "entry": entry, "inside": initial_sync}
			if not initial_sync and not actor.visible:
				actor.global_position = entry + Vector2(0, 24)
		var state: Dictionary = states[id]
		state.entry = entry
		if state.inside or not visuals.get_parent().enable_worker_commute:
			actor.hide()
			if state.inside:
				plot.mark_worker_arrived(id, task.key)
			continue
		actor.show()
		var direction: String = "left" if entry.x < actor.global_position.x else "right"
		actor.global_position = actor.global_position.move_toward(entry, WALK_SPEED * delta)
		visuals._play(actor, "walk", direction)
		if actor.global_position.distance_to(entry) < 0.1:
			state.inside = true
			actor.hide()
			plot.mark_worker_arrived(id, task.key)
			plot.show_worker_dust()
	for id: String in states.keys():
		if active.has(id):
			continue
		if visuals.actors.has(id):
			var actor: Node2D = visuals.actors[id]
			actor.global_position = states[id].entry
			actor.visible = visuals.get_parent().enable_worker_commute and WorkerDatabase.has_worker_data(id)
			visuals.roaming.erase(id)
		states.erase(id)
	initial_sync = false
	return retained
