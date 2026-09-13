extends Node2D

const VISUAL = preload("res://scenes/worker_visual/base_worker_visual.tscn")
var actors: Dictionary = {}
var last_minute: int = -1
var fraction: float = 0.0
var work_cycles: Dictionary = {}
var roaming: Dictionary = {}
var rng := RandomNumberGenerator.new()
@export var idle_min_seconds: float = 0.4
@export var idle_max_seconds: float = 1.8

func _ready() -> void:
	rng.randomize()

func _process(delta: float) -> void:
	var fixture = get_parent()
	var schedule = fixture.daily
	var minute: int = schedule.now()
	if minute != last_minute:
		fraction = 0.0
		last_minute = minute
	else:
		fraction = minf(fraction + delta / maxf(TimeComponentManager.seconds_per_minute, 0.001), 0.999)
	var retained: Array[String] = []
	for site_id in schedule.jobs:
		var job: Dictionary = schedule.jobs[site_id]
		for id: String in job.ids:
			retained.append(id)
			if not actors.has(id):
				var actor = VISUAL.instantiate()
				actor.set_meta("worker_id", id)
				var worker: WorkerData = WorkerDatabase.get_worker_data(id)
				var citizen: CitizenData = worker.get_linked_citizen()
				if citizen != null and citizen.visual_profile != null:
					var profile: VisualProfile = citizen.visual_profile
					actor.skin_tone = profile.skin_tone
					actor.clothes_id = profile.clothes_id
					actor.hair_style = profile.hair_style
					actor.accessory = profile.accessory
				if schedule.is_hauler(id):
					# Keep the supplied light appearance consistent with the cart sheets.
					actor.skin_tone = "light"
				add_child(actor)
				actor.global_position = fixture.worker_spawn(site_id, id)
				actor.hide()
				actors[id] = actor
			var actor = actors[id]
			if not fixture.enable_worker_commute:
				actor.hide()
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
				actor.get_node("CargoLabel").text = "Clay x%d" % int(hauling_visual.carrying) if int(hauling_visual.carrying) > 0 else ""
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
	actor.global_position = actor.global_position.move_toward(state.target, delta * 10.0)
	_play(actor, "walk", state.direction)

func _play(actor: Node2D, action: String, direction: String) -> void:
	# The hauling branch requests cart poses; commute and post-work roaming do not.
	actor.play_visual(actor.skin_tone, "base", action, direction, actor.accessory, actor.clothes_id, actor.hair_style)

func _update_work_cycle(id: String, actor: Node2D, center: Vector2, direction: String, delta: float) -> void:
	if not work_cycles.has(id):
		actor.global_position = center
		work_cycles[id] = {"phase": 0, "elapsed": 0.0, "direction": direction,
			"origin": center, "target": center, "idle": rng.randf_range(idle_min_seconds, idle_max_seconds)}
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
