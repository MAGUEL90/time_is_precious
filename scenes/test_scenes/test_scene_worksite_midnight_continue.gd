extends "res://scenes/test_scenes/test_scene_city_save_economy.gd"

## Actual 15:00/midnight needs boundary and separate-process replacement.
const MIDNIGHT_CHECKPOINT: String = "user://worksite_midnight_continue/checkpoint.json"
const EXPECTED_PROGRESS: float = 19.15
var phase: String = "write"

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--midnight-phase="):
			phase = argument.trim_prefix("--midnight-phase=")
	_expect(phase in ["write", "read"], "A write or read phase is required.")
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	_reset_singletons_before_load()
	await load_content()
	for _frame: int in range(2):
		await get_tree().process_frame
	runtime = content.get_node("YSortWorld/WorkerRuntime")
	# Both phases reconstruct the same isolated pre-removal Hauler fixture.
	runtime.daily.allow_haulers = true
	city_storage = WorkStateRuntime.get_node("CityToolStorage")
	wood_storage = runtime.get_node("CityStorageArea/DeliveryPoint")
	store = WorkStateRuntime.get_node("CitySave")
	store.disk.path = MIDNIGHT_CHECKPOINT
	if phase == "write":
		_test_midnight_write()
	else:
		_test_midnight_read()
	await _finish_midnight()

func _test_midnight_write() -> void:
	_expect(not FileAccess.file_exists(MIDNIGHT_CHECKPOINT), "Use a fresh isolated midnight checkpoint directory.")
	_prepare_city_state()
	if not _hire_and_assign_team():
		return
	var laborer: WorkerData = WorkerDatabase.get_worker_data(LABORER_ID)
	var citizen: CitizenData = CitizenManager.get_citizen(LABORER_ID)
	citizen.satisfaction = 0.05
	city_storage.items.erase("barley_bread")
	city_storage.food_portions.clear()
	# Place the fixture at 14:59 with a physically arrived worker and one
	# incomplete item, then use real clock signals for both boundaries.
	TimeComponentManager.current_hour = 14
	TimeComponentManager.current_minute = 59
	runtime.daily.last_tick = _clock_minute()
	runtime.daily.last_stock_day = TimeComponentManager.current_day
	runtime.daily.jobs[WOOD_SITE].progress[LABORER_ID] = 18.3
	laborer.physical_approach.position = laborer.physical_approach.target
	var task: String = runtime.site_approach_task(WOOD_SITE, LABORER_ID, TimeComponentManager.current_day)
	_expect(laborer.mark_physical_arrival(task), "The fixture worker is physically present before the last shift minute.")
	_expect(TimeComponentManager.advance_minutes(1), "Advance the real 14:59 work minute.")
	_expect(TimeComponentManager.current_hour == 15 and TimeComponentManager.current_minute == 0
		and is_equal_approx(float(runtime.daily.jobs[WOOD_SITE].progress[LABORER_ID]), EXPECTED_PROGRESS),
		"The actual 15:00 boundary preserves the unfinished item.")
	_expect(TimeComponentManager.advance_minutes(9 * 60), "Advance the real clock to midnight.")
	_expect(TimeComponentManager.current_hour == 0 and TimeComponentManager.current_minute == 0
		and citizen.satisfaction == 0.0 and not WorkerDatabase.has_worker_data(LABORER_ID)
		and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED,
		"The real midnight needs settlement immediately resigns the worker at zero.")
	_expect(runtime.daily.jobs[WOOD_SITE].ids == [HAULER_ID]
		and is_equal_approx(float(runtime.daily.pending_progress[WOOD_SITE][0]), EXPECTED_PROGRESS),
		"The remaining hauler stays assigned and the incomplete item is retained at the site.")
	_expect(store.save_checkpoint(), "Save the real midnight resignation: " + store.last_error)

func _test_midnight_read() -> void:
	_expect(store.load_checkpoint(), "Continue the midnight checkpoint in a fresh process: " + store.last_error)
	_expect(not WorkerDatabase.has_worker_data(LABORER_ID)
		and is_equal_approx(float(runtime.daily.pending_progress[WOOD_SITE][0]), EXPECTED_PROGRESS),
		"The departed worker and exact incomplete item survive Continue.")
	_expect(runtime.daily.toggle(WOOD_SITE, PRODUCTION_ID)
		and runtime.daily.start(WOOD_SITE, runtime._drop_daily_output.bind(runtime.get_node("WorksiteMarkers/WoodSite"))),
		"The replacement joins the still-assigned coworker.")
	var job: Dictionary = runtime.daily.jobs[WOOD_SITE]
	_expect(not runtime.daily.pending_progress.has(WOOD_SITE)
		and is_equal_approx(float(job.progress[PRODUCTION_ID]), EXPECTED_PROGRESS),
		"The replacement claims the saved item once.")
	_expect(TimeComponentManager.advance_minutes(7 * 60), "Advance to the replacement's next shift.")
	var replacement: WorkerData = WorkerDatabase.get_worker_data(PRODUCTION_ID)
	replacement.physical_approach.position = replacement.physical_approach.target
	var task: String = runtime.site_approach_task(WOOD_SITE, PRODUCTION_ID, TimeComponentManager.current_day)
	_expect(replacement.mark_physical_arrival(task), "The replacement reaches the site at shift start.")
	var before: int = int(job.stats[PRODUCTION_ID].output)
	_expect(TimeComponentManager.advance_minutes(1), "Advance one replacement work minute.")
	_expect(int(job.stats[PRODUCTION_ID].output) == before + 1
		and is_equal_approx(float(job.progress[PRODUCTION_ID]), 0.15),
		"The replacement finishes exactly one retained item and keeps the remainder.")

func _finish_midnight() -> void:
	if is_instance_valid(content):
		content.queue_free()
		await get_tree().process_frame
	_restore_clock()
	print("WorksiteMidnightContinueTest ", phase, ": ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
