extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var worker := WorkerData.new()
	worker.worker_id = "commute_test_worker"
	worker.display_name = "Arad"
	WorkerDatabase.workers_by_id[worker.worker_id] = worker
	var fixture = load("res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn").instantiate()
	fixture.prepare_nightmare_test = false
	add_child(fixture)
	fixture.player.debug_disable_player_needs = true
	fixture.player.global_position = Vector2(0, 30)
	var schedule = fixture.daily
	var site = fixture.sites[&"ClaySiteA"]
	schedule.toggle(&"ClaySiteA", worker.worker_id)
	schedule.start(&"ClaySiteA", fixture._drop_daily_output.bind(fixture.get_node("WorksiteMarkers/ClaySiteA")))
	var first_day: int = int(schedule.jobs[&"ClaySiteA"].starts[worker.worker_id]) / 1440
	var departure: int = schedule.departure_time(&"ClaySiteA", worker.worker_id, first_day)
	TimeComponentManager.advance_minutes(departure - schedule.now() - 2)
	if OS.get_environment("TIP_TEST_COMMUTE") != "1":
		return
	get_tree().paused = true
	var failures: int = 0
	var visuals = fixture.get_node("WorkerVisuals")
	visuals.idle_min_seconds = 0.7
	visuals.idle_max_seconds = 0.7
	visuals._process(0.0)
	if visuals.actors[worker.worker_id].visible:
		failures += 1
	TimeComponentManager.advance_minutes(2)
	visuals._process(0.0)
	var actor = visuals.actors[worker.worker_id]
	if worker.current_work_status != WorkerData.WorkStatus.TRAVELLING or not actor.visible or not str(actor.body_sprite.animation).contains("walk"):
		failures += 1
	var initial_position: Vector2 = actor.global_position
	var initial_stock: int = site.stock
	var duration: int = schedule.arrival_time(&"ClaySiteA", worker.worker_id, first_day) - departure
	TimeComponentManager.advance_minutes(duration - 1)
	visuals._process(0.0)
	if actor.global_position == initial_position or site.stock != initial_stock or worker.is_working():
		failures += 1
	TimeComponentManager.advance_minutes(1)
	visuals._process(0.0)
	if not worker.is_working() or not str(actor.head_sprite.animation).begins_with("base_") or not str(actor.body_sprite.animation).contains("idle"):
		failures += 1
	if not actor.global_position.is_equal_approx(fixture.worker_destination(&"ClaySiteA", worker.worker_id) + Vector2(0, -16)) or site.stock != initial_stock:
		failures += 1
	visuals._process(0.7)
	var first_direction: String = visuals.work_cycles[worker.worker_id].direction
	if not str(actor.body_sprite.animation).contains("work") or actor.body_sprite.frame != 0:
		failures += 1
	var work_duration: float = 7.0 / actor.anim_speed
	visuals._process(work_duration - 0.01)
	if actor.body_sprite.frame != 6 or actor.head_sprite.frame != 6:
		failures += 1
	visuals._process(0.02)
	if visuals.work_cycles[worker.worker_id].direction == first_direction or actor.body_sprite.frame != 0:
		failures += 1
	visuals._process(work_duration)
	if not str(actor.body_sprite.animation).contains("idle"):
		failures += 1
	visuals._process(0.7)
	if not str(actor.body_sprite.animation).contains("walk"):
		failures += 1
	var move_duration: float = visuals._phase_duration(visuals.work_cycles[worker.worker_id], actor)
	visuals._process(move_duration)
	if not str(actor.body_sprite.animation).contains("idle") or actor.global_position.is_equal_approx(fixture.worker_destination(&"ClaySiteA", worker.worker_id) + Vector2(0, -16)):
		failures += 1
	if site.stock != initial_stock:
		failures += 1
	visuals.idle_min_seconds = 0.4
	visuals.idle_max_seconds = 1.8
	visuals.rng.seed = 117
	var idle_values: Array[float] = []
	var route_values: Array[Vector2] = []
	for step in range(18):
		var cycle: Dictionary = visuals.work_cycles[worker.worker_id]
		visuals._process(visuals._phase_duration(cycle, actor) - float(cycle.elapsed) + 0.001)
		if not idle_values.has(cycle.idle):
			idle_values.append(cycle.idle)
		if cycle.phase == 4:
			if cycle.target.distance_to(fixture.worker_destination(&"ClaySiteA", worker.worker_id) + Vector2(0, -16)) > 10.01:
				failures += 1
			if not route_values.has(cycle.target):
				route_values.append(cycle.target)
	if idle_values.size() < 2 or route_values.size() < 2:
		failures += 1
	TimeComponentManager.advance_minutes(10)
	if site.stock != initial_stock - 1:
		failures += 1
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("tip-worksite-commute.png"))
	site.stock = 0
	TimeComponentManager.advance_minutes(1)
	visuals._process(0.0)
	if not str(actor.body_sprite.animation).contains("walk") or not actor.visible or not worker.is_reserved():
		failures += 1
	var exit_position: Vector2 = actor.global_position
	visuals._process(1.0)
	if actor.global_position.is_equal_approx(exit_position):
		failures += 1
	TimeComponentManager.advance_minutes(900 - schedule.now() % 1440)
	visuals._process(0.0)
	if not actor.visible or not worker.is_reserved() or schedule.active_count(&"ClaySiteA") != 0:
		failures += 1
	TimeComponentManager.advance_minutes(15 * 60)
	visuals._process(0.0)
	var next_route: Dictionary = fixture.worker_journey(&"ClaySiteA", worker.worker_id, TimeComponentManager.current_day)
	TimeComponentManager.advance_minutes(maxi(0, int(floor(next_route.start)) - schedule.now()))
	visuals._process(0.0)
	if not actor.visible or worker.current_work_status != WorkerData.WorkStatus.TRAVELLING:
		failures += 1
	TimeComponentManager.advance_minutes(schedule.arrival_time(&"ClaySiteA", worker.worker_id, TimeComponentManager.current_day) - schedule.now())
	visuals._process(0.0)
	if not worker.is_working() or not actor.visible:
		failures += 1
	schedule.withdraw(&"ClaySiteA", worker.worker_id)
	visuals._process(0.0)
	if not visuals.actors.has(worker.worker_id) or not actor.visible or worker.is_reserved():
		failures += 1
	get_tree().paused = false
	fixture.queue_free()
	await get_tree().process_frame
	WorkerDatabase.workers_by_id.erase(worker.worker_id)
	print("WorksiteCommuteTest %s" % ("PASSED" if failures == 0 else "FAILED: %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)
