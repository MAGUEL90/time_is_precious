extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture = load("res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn").instantiate()
	fixture.prepare_nightmare_test = false
	add_child(fixture)
	fixture.player.debug_disable_player_needs = true
	get_tree().paused = true
	var schedule = fixture.daily
	var ids: Array[String] = ["departure_near", "departure_far"]
	for id: String in ids:
		var worker := WorkerData.new()
		worker.worker_id = id
		WorkerDatabase.workers_by_id[id] = worker
		schedule.toggle(&"ClaySiteA", id)
	schedule.start(&"ClaySiteA", fixture._drop_daily_output.bind(fixture.get_node("WorksiteMarkers/ClaySiteA")))
	var day: int = TimeComponentManager.current_day + 1
	var a: Dictionary = fixture.worker_journey(&"ClaySiteA", ids[0], day)
	var b: Dictionary = fixture.worker_journey(&"ClaySiteA", ids[1], day)
	var failures: int = 0
	if a.origin == b.origin or a.start <= b.start or a.arrival != b.arrival:
		failures += 1
	for route: Dictionary in [a, b]:
		var speed: float = route.origin.distance_to(route.target) / (route.arrival - route.start)
		if not is_equal_approx(speed, fixture.worker_walk_pixels_per_game_minute):
			failures += 1
	TimeComponentManager.advance_minutes(int(a.arrival) - schedule.now())
	var site = fixture.sites[&"ClaySiteA"]
	site.stock = 84
	TimeComponentManager.advance_minutes(7 * 60)
	if TimeComponentManager.current_hour != 14 or site.stock != 0 or schedule.active_count(&"ClaySiteA") != 0:
		failures += 1
	if WorkerDatabase.get_worker_data(ids[0]).current_work_status != WorkerData.WorkStatus.WAITING_FOR_RESOURCES:
		failures += 1
	TimeComponentManager.advance_minutes(17 * 60)
	site.stock = 1000
	TimeComponentManager.advance_minutes(7 * 60)
	if TimeComponentManager.current_hour != 14 or schedule.active_count(&"ClaySiteA") != 2:
		failures += 1
	TimeComponentManager.advance_minutes(60)
	if TimeComponentManager.current_hour != 15 or schedule.active_count(&"ClaySiteA") != 0 or int(schedule.minutes_by_worker[ids[0]]) != 480:
		failures += 1
	get_tree().paused = false
	fixture.queue_free()
	await get_tree().process_frame
	for id: String in ids:
		WorkerDatabase.workers_by_id.erase(id)
	print("WorksiteDepartureTest %s" % ("PASSED" if failures == 0 else "FAILED: %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)
