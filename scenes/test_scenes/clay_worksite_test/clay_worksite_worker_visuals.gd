extends Node2D

const VISUAL = preload("res://scenes/worker_visual/base_worker_visual.tscn")
var actors: Dictionary = {}
var last_minute: int = -1
var fraction: float = 0.0
var work_cycles: Dictionary = {}
var roaming: Dictionary = {}
var site_paths: Dictionary = {}
const FEET_OFFSET := Vector2(0, 16)
const APPROACH_SPEED: float = 24.0
var rng := RandomNumberGenerator.new()
var plot_presence = preload("res://scenes/workshop_plot/workshop_worker_presence.gd").new()
@export var idle_min_seconds: float = 0.4
@export var idle_max_seconds: float = 1.8

func _ready() -> void:
	rng.randomize()
	# CitySave disables the parked parent, while this retained physical owner
	# continues hidden approaches using the same real elapsed frame time.
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _process(delta: float) -> void:
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return
	var fixture = get_parent()
	var schedule = fixture.daily
	var minute: int = schedule.now()
	if minute != last_minute:
		fraction = 0.0
		last_minute = minute
	else:
		fraction = minf(fraction + delta / maxf(TimeComponentManager.seconds_per_minute, 0.001), 0.999)
	var retained: Array[String] = plot_presence.update(self, delta)
	var plot_workers: Array[String] = retained.duplicate()
	for site_id in schedule.jobs:
		var job: Dictionary = schedule.jobs[site_id]
		for id: String in job.ids:
			if plot_workers.has(id):
				continue
			retained.append(id)
			var actor = ensure_actor(id, fixture.worker_spawn(site_id, id))
			if actor == null:
				continue
			if not fixture.enable_worker_commute:
				actor.hide()
				continue
			if not schedule.is_hauler(id) and fixture.has_method("site_approach_task") and _physical_site_step(site_id, id, actor, delta):
				continue
			var hauling_visual: Dictionary = fixture.hauling.get_visual(id, minute + fraction) if fixture.hauling != null else {}
			if not hauling_visual.is_empty() and (hauling_visual.get("moving", false) or schedule._hauler_eligible(id)):
				actor.show()
				work_cycles.erase(id)
				roaming.erase(id)
				actor.global_position = hauling_visual.position
				_play(actor, "push_cart" if hauling_visual.moving else "idle_cart", hauling_visual.direction)
				if not actor.has_node("CargoLabel"):
					var label := Label.new()
					label.name = "CargoLabel"
					label.position = Vector2(0, -8)
					label.add_theme_font_size_override("font_size", 6)
					actor.add_child(label)
				var cargo_quantity: int = int(hauling_visual.carrying)
				var cargo_item_id: String = str(hauling_visual.get("item_id", "clay_lump"))
				var cargo_item: ItemData = ItemDatabase.get_item_data(cargo_item_id)
				if cargo_item == null:
					cargo_item = ItemDatabase.get_item_data("clay_lump")
				var cargo_name: String = cargo_item.display_name if cargo_item != null else "Clay"
				actor.get_node("CargoLabel").text = "%s x%d" % [cargo_name, cargo_quantity] if cargo_quantity > 0 else ""
				continue
			if actor.has_node("CargoLabel"):
				actor.get_node("CargoLabel").text = ""
			var first_day: int = int(job.starts[id]) / 1440
			if minute < schedule.departure_time(site_id, id, first_day):
				work_cycles.erase(id)
				if actor.visible:
					_roam(id, actor, delta)
				continue
			var route: Dictionary = fixture.worker_journey(site_id, id, TimeComponentManager.current_day)
			var destination: Vector2 = route.target
			var arrival: int = route.arrival
			var start: float = route.start
			var departure: Vector2 = route.origin
			if not actor.visible and minute < int(floor(start)):
				continue
			actor.show()
			var distance: float = maxf(minute + fraction - start, 0.0) * fixture.worker_walk_pixels_per_game_minute
			var direction: String = "left" if destination.x < departure.x else "right"
			if minute >= int(floor(start)) and minute < arrival:
				roaming.erase(id)
				work_cycles.erase(id)
				actor.global_position = departure.move_toward(destination, distance)
				_play(actor, "walk", direction)
			elif schedule.activity(site_id, id) == WorkerData.WorkStatus.WORKING:
				roaming.erase(id)
				_update_work_cycle(id, actor, destination, direction, delta)
			else:
				work_cycles.erase(id)
				_roam(id, actor, delta)
	for id: String in actors.keys():
		if not retained.has(id):
			work_cycles.erase(id)
			if actors[id].visible:
				_roam(id, actors[id], delta)

func _physical_site_step(site_id: StringName, id: String, actor: Node2D, delta: float) -> bool:
	var fixture: Node = get_parent()
	var schedule = fixture.daily
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if worker == null or worker.physical_approach.is_empty():
		return false # Legacy assignments retain their established native state.
	var day: int = maxi(int(schedule.jobs[site_id].starts[id]) / 1440, TimeComponentManager.current_day)
	var task: String = fixture.site_approach_task(site_id, id, day)
	var journey: Dictionary = fixture.worker_journey(site_id, id, day)
	var current: int = schedule.now()
	if current < int(floor(journey.start)) or current >= day * 1440 + schedule.SHIFT_END:
		work_cycles.erase(id)
		if actor.visible:
			_roam(id, actor, delta)
		worker.physical_approach.position = actor.global_position + FEET_OFFSET
		return true
	if not worker.matches_physical_approach("site", task, str(site_id)):
		fixture.begin_site_approach(site_id, id, day)
	var state: Dictionary = worker.physical_approach
	actor.global_position = Vector2(state.position) - FEET_OFFSET
	actor.show()
	if state.arrived:
		if schedule.activity(site_id, id) == WorkerData.WorkStatus.WORKING:
			_update_work_cycle(id, actor, Vector2(state.target) - FEET_OFFSET, "right", delta)
		else:
			work_cycles.erase(id)
			_play(actor, "idle", "right")
		state.position = actor.global_position + FEET_OFFSET
		return true
	work_cycles.erase(id)
	roaming.erase(id)
	if worker.is_payroll_blocked():
		_play(actor, "idle", "right")
		return true
	var feet: Vector2 = state.position
	var target: Vector2 = state.target
	var navigation = fixture.worksite_navigation
	var path: Dictionary = site_paths.get(id, {})
	if path.get("task", "") != task or path.get("target", Vector2.INF) != target:
		path = {"task": task, "target": target, "points": navigation.route(feet, target), "next": 1}
		site_paths[id] = path
	var remaining: float = APPROACH_SPEED * delta
	var points: PackedVector2Array = path.points
	while int(path.next) < points.size() and remaining > 0.0001:
		var next: Vector2 = points[int(path.next)]
		if feet.distance_to(next) < 0.01:
			path.next += 1
			continue
		var step: Vector2 = feet.move_toward(next, remaining)
		if not navigation.segment_clear(feet, step):
			site_paths.erase(id)
			break
		remaining -= feet.distance_to(step)
		_play(actor, "walk", "left" if step.x < feet.x else "right")
		feet = step
	state.position = feet
	actor.global_position = feet - FEET_OFFSET
	if feet.distance_to(target) < 0.1 and navigation.is_clear(feet):
		if worker.mark_physical_arrival(task):
			site_paths.erase(id)
			schedule._sync_activities()
	elif points.is_empty():
		_play(actor, "idle", "right")
	return true

func ensure_actor(id: String, spawn_position: Vector2) -> Node2D:
	if actors.has(id):
		return actors[id]
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if worker == null:
		return null
	var actor = VISUAL.instantiate()
	actor.set_meta("worker_id", id)
	var citizen: CitizenData = worker.get_linked_citizen()
	var profile: VisualProfile = citizen.visual_profile if citizen != null and citizen.visual_profile != null else VisualProfile.new()
	actor.skin_tone = "light" if get_parent().daily.is_hauler(id) else profile.skin_tone
	actor.clothes_id = profile.clothes_id
	actor.hair_style = profile.hair_style
	actor.accessory = profile.accessory
	add_child(actor)
	actor.global_position = Vector2(worker.physical_approach.position) - FEET_OFFSET if not worker.physical_approach.is_empty() else spawn_position
	var foot := Node2D.new()
	foot.name = "FootSort"
	foot.position = FEET_OFFSET
	actor.add_child(foot)
	for child: Node in actor.get_children():
		if child is AnimatedSprite2D:
			child.reparent(foot, true)
	actor.y_sort_enabled = true
	actor.hide()
	actors[id] = actor
	return actor

func _roam(id: String, actor: Node2D, delta: float) -> void:
	if not roaming.has(id):
		roaming[id] = {"target": actor.global_position + Vector2(rng.randf_range(-45, 45), rng.randf_range(25, 55)), "idle": 0.0, "direction": "right"}
	var state: Dictionary = roaming[id]
	if state.idle > 0.0:
		state.idle -= delta
		_play(actor, "idle", state.direction)
		return
	if actor.global_position.distance_to(state.target) < 0.1:
		state.target = Vector2(rng.randf_range(-170, 170), rng.randf_range(-70, 75)) + get_parent().global_position
		state.idle = rng.randf_range(idle_min_seconds, idle_max_seconds)
		_play(actor, "idle", state.direction)
		return
	state.direction = "left" if state.target.x < actor.global_position.x else "right"
	var step: Vector2 = actor.global_position.move_toward(state.target, delta * 10.0)
	var fixture: Node = get_parent()
	if fixture.has_method("site_approach_task") and not fixture.worksite_navigation.segment_clear(actor.global_position + FEET_OFFSET, step + FEET_OFFSET):
		state.target = actor.global_position
		state.idle = rng.randf_range(idle_min_seconds, idle_max_seconds)
		_play(actor, "idle", state.direction)
		return
	actor.global_position = step
	_play(actor, "walk", state.direction)

func _play(actor: Node2D, action: String, direction: String) -> void:
	# The hauling branch requests cart poses; commute and post-work roaming do not.
	actor.play_visual(actor.skin_tone, "base", action, direction, actor.accessory, actor.clothes_id, actor.hair_style)
	var foot: Node = actor.get_node_or_null("FootSort")
	if foot != null:
		for child: Node in actor.get_children():
			if child is AnimatedSprite2D:
				child.reparent(foot, true)

func _update_work_cycle(id: String, actor: Node2D, center: Vector2, direction: String, delta: float) -> void:
	if not work_cycles.has(id):
		if not get_parent().has_method("site_approach_task"):
			actor.global_position = center
		work_cycles[id] = {"phase": 0, "elapsed": 0.0, "direction": direction,
			"origin": actor.global_position, "target": actor.global_position, "idle": rng.randf_range(idle_min_seconds, idle_max_seconds)}
		# Arrival gets a full idle pause, even after a game-time skip.
		delta = 0.0
	var cycle: Dictionary = work_cycles[id]
	cycle.elapsed += delta
	var duration: float = _phase_duration(cycle, actor)
	while cycle.elapsed >= duration:
		cycle.elapsed -= duration
		cycle.phase = 1 if cycle.phase == 5 else int(cycle.phase) + 1
		cycle.idle = rng.randf_range(idle_min_seconds, idle_max_seconds)
		if cycle.phase == 2:
			cycle.direction = "right" if cycle.direction == "left" else "left"
		if cycle.phase == 4:
			cycle.origin = actor.global_position
			cycle.target = center + Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(4.0, 10.0)
			if get_parent().has_method("site_approach_task") and not get_parent().worksite_navigation.segment_clear(cycle.origin + FEET_OFFSET, cycle.target + FEET_OFFSET):
				cycle.target = cycle.origin
			cycle.direction = "left" if cycle.target.x < cycle.origin.x else "right"
		if cycle.phase == 5:
			actor.global_position = cycle.target
		duration = _phase_duration(cycle, actor)
	var action: String = "idle"
	if cycle.phase == 1 or cycle.phase == 2:
		action = "work"
	elif cycle.phase == 4:
		action = "walk"
		actor.global_position = cycle.origin.lerp(cycle.target, cycle.elapsed / duration)
	_play(actor, action, cycle.direction)
	if action == "work":
		# Use precisely seven frames per facing; the shared eight-frame clips stay intact.
		var frame: int = mini(6, int(cycle.elapsed * maxf(actor.anim_speed, 0.01)))
		for layer: AnimatedSprite2D in [actor.body_sprite, actor.head_sprite]:
			layer.stop()
			layer.set_frame_and_progress(frame, 0.0)

func _phase_duration(cycle: Dictionary, actor: Node2D) -> float:
	if cycle.phase == 1 or cycle.phase == 2:
		return 7.0 / maxf(actor.anim_speed, 0.01)
	if cycle.phase == 4:
		return maxf(cycle.origin.distance_to(cycle.target) / 10.0, 0.1)
	return maxf(cycle.idle, 0.1)
