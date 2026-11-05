extends "res://scenes/test_scenes/test_scene_multi_worker_navigation.gd"

## Integration fixture: two distinct workers use the live city receipt, then
## Continue, produce again and cross the shift boundary without duplicating stock.
const CITY_EVIDENCE_PATH: String = "user://multi_worker_navigation/city_evidence.json"

func _write_scenario() -> void:
	for id: String in IDS.slice(0, 2):
		_new_worker(id)
		_check(runtime.daily.toggle(SITE, id), "Select " + id)
	var city_storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var site = runtime.sites[SITE]
	var city_before: int = int(city_storage.items.get("wood_log", 0))
	var stock_before: int = site.stock
	var bag_before: int = int(Inventory.items.get("wood_log", 0))
	_check(runtime.daily.start(SITE, runtime._deliver_daily_output.bind(runtime.get_node("WorksiteMarkers/WoodSite"))), "Start both workers using the actual city receipt")
	if failures:
		return
	_walk_until_arrived(IDS.slice(0, 2))
	_check(TimeComponentManager.advance_minutes(30), "Advance paid work after both physical arrivals")
	var job: Dictionary = runtime.daily.jobs[SITE]
	var first: int = int(job.stats[IDS[0]].output)
	var second: int = int(job.stats[IDS[1]].output)
	_check(first > 0 and second > 0, "Both workers contribute after arriving")
	_check(int(city_storage.items.get("wood_log", 0)) - city_before == first + second and stock_before - site.stock == first + second, "Both outputs move from natural stock into City Storage exactly once")
	_check(int(job.units) == 0 and runtime._daily_output_count(SITE) == 0 and int(Inventory.items.get("wood_log", 0)) == bag_before, "No output remains in the job, on the ground or in the player's bag")
	# Arrange one remaining unit and nearly completed work for both employees.
	# The first completion owns that single unit; both retain their assignment
	# and must walk to the replacement deposit before continuing.
	var old_position: Vector2 = runtime.get_node("WorksiteMarkers/WoodSite").position
	site.stock = 1
	for id: String in IDS.slice(0, 2):
		job.progress[id] = site.minutes_per_unit - 1.0
	var before_last: int = int(city_storage.items.get("wood_log", 0))
	_check(TimeComponentManager.advance_minutes(1), "Advance both workers against the final unit")
	_check(site.stock == 0 and int(city_storage.items.get("wood_log", 0)) == before_last + 1, "The shared final unit reaches City Storage exactly once")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(site.stock == 240 and runtime.get_node("WorksiteMarkers/WoodSite").position != old_position, "An exhausted Wood Site appears at a new location")
	_check(job.ids == IDS.slice(0, 2) and not _worker(IDS[0]).physical_approach.arrived and not _worker(IDS[1]).physical_approach.arrived
		and _worker(IDS[0]).physical_approach.target != _worker(IDS[1]).physical_approach.target, "Both assigned workers must walk to distinct entries at the replacement site")
	if failures:
		return
	_walk_until_arrived(IDS.slice(0, 2))
	first = int(job.stats[IDS[0]].output)
	second = int(job.stats[IDS[1]].output)
	_check(store.save_checkpoint(), "Save both working city-supply assignments: " + store.last_error)
	if failures:
		return
	var evidence := {"city": int(city_storage.items.get("wood_log", 0)), "stock": site.stock,
		"bag": bag_before, "first": first, "second": second}
	var file: FileAccess = FileAccess.open(CITY_EVIDENCE_PATH, FileAccess.WRITE)
	_check(file != null, "Record the separate-process city-supply evidence")
	if file != null:
		file.store_string(JSON.stringify(evidence))
		file.close()

func _read_scenario() -> void:
	_check(store.load_checkpoint(), "Continue the two city-supply workers: " + store.last_error)
	if failures:
		return
	for _i in range(3):
		await get_tree().process_frame
	visuals.set_process(false)
	var city_storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var site = runtime.sites[SITE]
	var job: Dictionary = runtime.daily.jobs.get(SITE, {})
	_check(not job.is_empty() and job.ids == IDS.slice(0, 2), "Continue restores both distinct assignments")
	if job.is_empty():
		return
	var evidence: Variant = JSON.parse_string(FileAccess.get_file_as_string(CITY_EVIDENCE_PATH))
	_check(evidence is Dictionary, "Read the independent write-phase evidence")
	if not evidence is Dictionary:
		return
	_check(int(city_storage.items.get("wood_log", 0)) == int(evidence.city) and site.stock == int(evidence.stock)
		and int(Inventory.items.get("wood_log", 0)) == int(evidence.bag)
		and int(job.stats[IDS[0]].output) == int(evidence.first) and int(job.stats[IDS[1]].output) == int(evidence.second),
		"A fresh process restores both worker totals and every saved stock owner exactly")
	var city_before: int = int(city_storage.items.get("wood_log", 0))
	var stock_before: int = site.stock
	var bag_before: int = int(Inventory.items.get("wood_log", 0))
	var first_before: int = int(job.stats[IDS[0]].output)
	var second_before: int = int(job.stats[IDS[1]].output)
	_check(TimeComponentManager.advance_minutes(30), "Both restored workers continue paid production")
	var first_delta: int = int(job.stats[IDS[0]].output) - first_before
	var second_delta: int = int(job.stats[IDS[1]].output) - second_before
	_check(first_delta > 0 and second_delta > 0, "Each restored worker contributes")
	_check(int(city_storage.items.get("wood_log", 0)) - city_before == first_delta + second_delta and stock_before - site.stock == first_delta + second_delta, "Restored production reaches the city once and consumes the same natural stock")
	_check(int(Inventory.items.get("wood_log", 0)) == bag_before and runtime._daily_output_count(SITE) == 0, "Restored production creates no personal or ground output")
	_check(store.load_checkpoint(), "Reload the same city-supply checkpoint: " + store.last_error)
	city_storage = WorkStateRuntime.get_node("CityToolStorage")
	site = runtime.sites[SITE]
	job = runtime.daily.jobs.get(SITE, {})
	_check(int(city_storage.items.get("wood_log", 0)) == city_before and site.stock == stock_before and int(Inventory.items.get("wood_log", 0)) == bag_before, "Repeated load restores the saved owners without duplicating production")
	# Keep this fixture supplied through 15:00 so a depleted site cannot make
	# the post-shift assertion pass without exercising the shift boundary.
	site.stock = 1000
	var to_close: int = 15 * 60 - (runtime.daily.now() % 1440)
	_check(to_close > 0 and TimeComponentManager.advance_minutes(to_close), "Advance to the 15:00 shift boundary")
	var output_at_close: int = int(job.stats[IDS[0]].output) + int(job.stats[IDS[1]].output)
	var city_at_close: int = int(city_storage.items.get("wood_log", 0))
	_check(site.stock > 0 and output_at_close > first_before + second_before
		and _worker(IDS[0]).current_work_status == WorkerData.WorkStatus.RESTING
		and _worker(IDS[1]).current_work_status == WorkerData.WorkStatus.RESTING,
		"Both workers reach shift end after producing while stock remains available")
	_check(TimeComponentManager.advance_minutes(2), "Advance after the shift")
	_check(int(job.stats[IDS[0]].output) + int(job.stats[IDS[1]].output) == output_at_close and int(city_storage.items.get("wood_log", 0)) == city_at_close, "Neither worker produces or delivers new stock after the shift")
