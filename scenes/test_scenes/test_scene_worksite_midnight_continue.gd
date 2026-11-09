extends "res://scenes/test_scenes/test_scene_city_save_economy.gd"

## Synthetic unmet-needs setup, real 15:00/midnight ticks and fresh-process replacement.
const MIDNIGHT_CHECKPOINT: String = "user://worksite_midnight_continue/checkpoint.json"
const EXPECTED_PROGRESS: float = 19.15
const MINUTE_RATE: float = 0.05 / 1440.0
const SHORTAGE_MINUTES: int = 9 * 60 + 1
var phase: String = "write"

func _run() -> void:
	if not _isolated_profile_is_safe():
		push_error("Refusing midnight fixture outside the disposable QA profile.")
		get_tree().quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--midnight-phase="):
			phase = argument.trim_prefix("--midnight-phase=")
	_expect(phase in ["write", "read"], "A write or read phase is required.")
	if failures > 0:
		get_tree().quit(2)
		return
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
	# Place the fixture at 14:59 with a physically arrived worker and one
	# incomplete item, then use real clock signals for both boundaries.
	TimeComponentManager.current_hour = 14
	TimeComponentManager.current_minute = 59
	# This direct fixture clock placement has no elapsed simulation. Start all
	# satisfaction cursors here, then explicitly seed this worker without any
	# consumed ration, clothing allocation, shelter, or replenishing stock.
	for id: String in CitizenNeedsManager.satisfaction_last_minute:
		CitizenNeedsManager.satisfaction_last_minute[id] = _clock_minute()
	city_storage.items.erase("barley_bread")
	city_storage.food_portions.clear()
	city_storage.items.erase("simple_clothes")
	CitizenNeedsManager.food_coverage_until.erase(LABORER_ID)
	CitizenNeedsManager.clothing_allocations.erase(LABORER_ID)
	CitizenNeedsManager.satisfaction_last_minute[LABORER_ID] = _clock_minute()
	CityStockManager.shelter_capacity = 0
	CitizenNeedsManager.process_daily_shelter_capacity_needs()
	citizen.food_fulfilled = false
	citizen.clothing_fulfilled = false
	# Half a minute above zero at 23:59; the next genuine minute reaches zero.
	citizen.satisfaction = MINUTE_RATE * (float(SHORTAGE_MINUTES) - 0.5)
	_expect(not citizen.food_fulfilled and not citizen.clothing_fulfilled
		and not citizen.shelter_fulfilled and city_storage.get_food_supply_points() == 0,
		"The isolated shortage fixture has no live need coverage or replacement food.")
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
	_expect(TimeComponentManager.advance_minutes(9 * 60 - 1), "Advance to the last minute before midnight.")
	_expect(TimeComponentManager.current_hour == 23 and TimeComponentManager.current_minute == 59
		and citizen.satisfaction > 0.0 and absf(citizen.satisfaction - MINUTE_RATE * 0.5) < 0.000000001
		and WorkerDatabase.has_worker_data(LABORER_ID),
		"Gradual decline keeps the worker employed while Satisfaction is still positive at 23:59.")
	_expect(TimeComponentManager.advance_minutes(1), "Advance the real zero-crossing minute to midnight.")
	_expect(TimeComponentManager.current_hour == 0 and TimeComponentManager.current_minute == 0
		and citizen.satisfaction == 0.0 and not WorkerDatabase.has_worker_data(LABORER_ID)
		and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED
		and citizen.population_status == CitizenData.PopulationStatus.LEFT_CITY,
		"The real zero-crossing minute resigns the worker and records departure at midnight.")
	_expect(runtime.daily.jobs[WOOD_SITE].ids == [HAULER_ID]
		and is_equal_approx(float(runtime.daily.pending_progress[WOOD_SITE][0]), EXPECTED_PROGRESS),
		"The remaining hauler stays assigned and the incomplete item is retained at the site.")
	_expect(store.save_checkpoint(), "Save the real midnight resignation: " + store.last_error)

func _test_midnight_read() -> void:
	_expect(FileAccess.file_exists(MIDNIGHT_CHECKPOINT), "The reader requires its separate-process writer checkpoint.")
	if failures > 0:
		return
	var files_before: Dictionary = _midnight_files()
	var loaded: bool = store.load_checkpoint()
	_expect(loaded, "Continue the midnight checkpoint in a fresh process: " + store.last_error)
	if not loaded:
		return
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

	_expect(_midnight_files() == files_before, "Continue and the next shift preserve all checkpoint bytes and filenames.")

func _midnight_files() -> Dictionary:
	var files: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		files[suffix] = FileAccess.get_file_as_bytes(MIDNIGHT_CHECKPOINT + suffix) if FileAccess.file_exists(MIDNIGHT_CHECKPOINT + suffix) else null
	return files

func _finish_midnight() -> void:
	if is_instance_valid(content):
		content.queue_free()
		await get_tree().process_frame
	_restore_clock()
	print("WorksiteMidnightContinueTest ", phase, ": ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
