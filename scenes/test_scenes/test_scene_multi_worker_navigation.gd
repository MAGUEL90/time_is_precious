extends Node

## Actual city geometry and worker scheduler. Worksite delivery is deliberately
## not asserted here: its destination is owned by the separate logistics work.
## Run write and read in separate processes with the same fresh XDG data root.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const SITE: StringName = &"WoodSite"
const IDS: Array[String] = ["navigation_worker_a", "navigation_worker_b", "navigation_worker_c"]
const HIRED_IDS: Array[String] = ["initial_workshop_laborer", "initial_worksite_hauler", "navigation_hired_replacement"]
const SAVE_PATH: String = "user://multi_worker_navigation/checkpoint.json"
var failures: int = 0
var checks: int = 0
var phase: String = "write"
var city: Node
var runtime: Node
var visuals: Node
var store: Node

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MultiWorkerNavigation: " + message)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--navigation-phase="):
			phase = argument.trim_prefix("--navigation-phase=")
	_check(phase in ["write", "read", "hire"], "Choose the write, read or hire phase")
	var isolated_root: String = OS.get_environment("TIP_ISOLATED_DATA_ROOT").simplify_path().replace("\\", "/").trim_suffix("/")
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path().replace("\\", "/").trim_suffix("/")
	_check(not isolated_root.is_empty() and isolated_root.is_absolute_path() and user_root.begins_with(isolated_root + "/"),
		"Use a fresh TIP_ISOLATED_DATA_ROOT containing the Godot user directory")
	if failures > 0:
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 20
	TimeComponentManager.current_hour = 11
	TimeComponentManager.current_minute = 0
	city = CONTENT.instantiate()
	add_child(city)
	runtime = city.get_node("YSortWorld/WorkerRuntime")
	visuals = runtime.get_node("WorkerVisuals")
	visuals.set_process(false)
	var player: Player = city.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	for _i in range(3):
		await get_tree().process_frame
	store = WorkStateRuntime.get_node("CitySave")
	store.disk.path = SAVE_PATH
	if phase == "write":
		_check(not FileAccess.file_exists(SAVE_PATH), "The write phase uses a fresh checkpoint")
		if failures == 0:
			await _write_scenario()
	elif phase == "read":
		await _read_scenario()
	else:
		_hire_scenario()
	city.free()
	for id: String in IDS:
		WorkerDatabase.workers_by_id.erase(id)
	print("MultiWorkerNavigation ", phase, ": ", "PASS" if failures == 0 else "FAIL", " checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _hire_scenario() -> void:
	# The first two are the actual starting resident/applicant identities. The
	# third is one explicit replacement applicant; the wallet grant is test-only.
	Inventory.add_item("shekel", 10)
	var first_actors: Dictionary = {}
	for id: String in HIRED_IDS.slice(0, 2):
		_check(visuals.actors.has(id), id + " begins as an actual resident visual")
		first_actors[id] = visuals.actors.get(id)
		_check(WorkerDatabase.hire_applicant(id) != null, id + " is hired through the real backend")
		_check(visuals.actors.get(id) == first_actors[id], id + " keeps the resident's actor after hiring")
		_check(runtime.daily.toggle(SITE, id), "Select hired resident " + id)
	if failures > 0:
		return
	_check(runtime.daily.start(SITE, runtime._drop_daily_output.bind(runtime.get_node("WorksiteMarkers/WoodSite"))),
		"Start both actual residents at the Wood Site")
	if not runtime.daily.jobs.has(SITE):
		return
	_check(_worker(HIRED_IDS[0]).physical_approach.target != _worker(HIRED_IDS[1]).physical_approach.target,
		"The two hires have distinct physical destinations")
	_walk_until_arrived(HIRED_IDS.slice(0, 2))
	TimeComponentManager.advance_minutes(30)
	for id: String in HIRED_IDS.slice(0, 2):
		_check(_worker(id).physical_approach.arrived and int(runtime.daily.jobs[SITE].stats[id].output) > 0,
			id + " reaches the site from its resident position and contributes")
	_check(runtime.daily.withdraw(SITE, HIRED_IDS[0]), "Release the first hired resident")
	var applicant := CitizenData.new()
	applicant.citizen_id = HIRED_IDS[2]
	applicant.display_name = "Replacement fixture"
	applicant.population_status = CitizenData.PopulationStatus.RESIDENT
	applicant.satisfaction = 0.5
	CitizenManager.add_citizen(applicant)
	_check(CitizenManager.register_applicant(HIRED_IDS[2], WorkerData.Profession.LABORER), "Register a replacement applicant")
	_check(WorkerDatabase.hire_applicant(HIRED_IDS[2]) != null, "Hire the replacement through the real backend")
	if not WorkerDatabase.has_worker_data(HIRED_IDS[2]):
		return
	_assign(HIRED_IDS[2])
	_check(_worker(HIRED_IDS[1]).physical_approach.target != _worker(HIRED_IDS[2]).physical_approach.target,
		"The hired replacement takes the survivor's vacant entry")
	_walk_until_arrived([HIRED_IDS[2]])
	TimeComponentManager.advance_minutes(30)
	_check(int(runtime.daily.jobs[SITE].stats[HIRED_IDS[2]].output) > 0, "The replacement contributes after arriving")

func _new_worker(id: String) -> void:
	var worker := WorkerData.new()
	worker.worker_id = id
	worker.display_name = id
	worker.payroll_start_day = 20
	worker.payroll_paid_from_day = 20
	worker.payroll_paid_until_day = 23
	worker.payroll_last_attempt_day = 20
	worker.payroll_period_rate = 1
	worker.payroll_contract_days = 3
	worker.payroll_paid_start_minute = 20 * 1440 + 11 * 60
	WorkerDatabase.workers_by_id[id] = worker

func _worker(id: String) -> WorkerData:
	return WorkerDatabase.get_worker_data(id)

func _assign(id: String) -> void:
	_check(runtime.daily.toggle(SITE, id), "Select " + id)
	_check(runtime.daily.start(SITE, runtime._drop_daily_output.bind(runtime.get_node("WorksiteMarkers/WoodSite"))), "Start " + id)

func _walk_until_arrived(ids: Array[String]) -> void:
	for _frame in range(1000):
		var complete: bool = true
		var positions: Dictionary = {}
		for id: String in ids:
			var worker: WorkerData = _worker(id)
			if not worker.physical_approach.arrived:
				positions[id] = worker.physical_approach.position
				complete = false
		if complete:
			return
		visuals._process(0.1)
		for id: String in positions:
			var position: Vector2 = _worker(id).physical_approach.position
			_check(position.distance_to(positions[id]) <= visuals.APPROACH_SPEED * 0.1 + 0.002,
				id + " walks within the frame distance budget")
			_check(runtime.worksite_navigation.segment_clear(positions[id], position),
				id + " does not walk through authored solids")
	for id: String in ids:
		_check(_worker(id).physical_approach.arrived, id + " reaches its assigned entry")

func _write_scenario() -> void:
	for id: String in IDS:
		_new_worker(id)
	for id: String in IDS.slice(0, 2):
		_check(runtime.daily.toggle(SITE, id), "Select " + id)
	_check(runtime.daily.start(SITE, runtime._drop_daily_output.bind(runtime.get_node("WorksiteMarkers/WoodSite"))), "Start two workers together")
	TimeComponentManager.advance_minutes(3)
	for id: String in IDS.slice(0, 2):
		_check(not _worker(id).physical_approach.arrived and int(runtime.daily.minutes_by_worker.get(id, 0)) == 0,
			id + " cannot work while the clock advances without a physical walk")
	_walk_until_arrived(IDS.slice(0, 2))
	TimeComponentManager.advance_minutes(30)
	for id: String in IDS.slice(0, 2):
		_check(_worker(id).physical_approach.arrived and int(runtime.daily.jobs[SITE].stats[id].output) > 0,
			id + " reaches the wood site and contributes")

	# A surviving worker retains entry 1 even after moving to list index 0.
	_check(runtime.daily.withdraw(SITE, IDS[0]), "Withdraw the first worker")
	_assign(IDS[2])
	var remaining: WorkerData = _worker(IDS[1])
	var replacement: WorkerData = _worker(IDS[2])
	var remaining_target: Vector2 = remaining.physical_approach.target
	_check(remaining_target == runtime.site_slot_destination(SITE, 1)
		and replacement.physical_approach.target == runtime.site_slot_destination(SITE, 0),
		"The replacement takes the vacant entry without moving its teammate")

	# Temporary geometry is controlled by the fixture, not the live map. A
	# cached no-route result must not survive a navigation revision.
	var original_polygons: Array[PackedVector2Array] = runtime.worksite_navigation.polygons.duplicate()
	var blocked_polygons: Array[PackedVector2Array] = original_polygons.duplicate()
	var target: Vector2 = replacement.physical_approach.target
	blocked_polygons.append(PackedVector2Array([target + Vector2(-2, -2), target + Vector2(2, -2), target + Vector2(2, 2), target + Vector2(-2, 2)]))
	runtime.worksite_navigation.replace_polygons(blocked_polygons)
	var blocked_pose: Vector2 = replacement.physical_approach.position
	visuals._process(0.1)
	_check(not replacement.physical_approach.arrived and replacement.physical_approach.position == blocked_pose,
		"An obstructed target cannot create movement or arrival")
	TimeComponentManager.advance_minutes(2)
	_check(int(runtime.daily.minutes_by_worker.get(IDS[2], 0)) == 0, "An obstructed worker cannot produce remotely")
	runtime.worksite_navigation.replace_polygons(original_polygons)
	SceneTransition.is_transitioning = true
	visuals._process(0.2)
	SceneTransition.is_transitioning = false
	_check(replacement.physical_approach.position == blocked_pose, "A scene transition pauses the pending worker's walk")
	var paid_until: int = replacement.payroll_paid_until_day
	replacement.payroll_paid_until_day = 19
	visuals._process(0.2)
	_check(replacement.physical_approach.position == blocked_pose and not replacement.physical_approach.arrived,
		"An unpaid replacement cannot walk or receive a false arrival")
	replacement.payroll_paid_until_day = paid_until
	_walk_until_arrived([IDS[2]])
	_check(replacement.physical_approach.arrived, "The replacement replans when the obstruction is removed")

	# Both approach a single remaining unit at once. The scheduler may choose
	# either worker first, but the shared stock must not be spent twice.
	var job: Dictionary = runtime.daily.jobs[SITE]
	var session = runtime.sites[SITE]
	session.stock = 1
	for id: String in IDS.slice(1):
		job.progress[id] = session.minutes_per_unit - _worker(id).get_satisfaction_work_multiplier()
	var total_before: int = int(job.stats[IDS[1]].output) + int(job.stats[IDS[2]].output)
	TimeComponentManager.advance_minutes(1)
	var total_after: int = int(job.stats[IDS[1]].output) + int(job.stats[IDS[2]].output)
	_check(session.stock == 0 and total_after == total_before + 1,
		"Two workers competing for the final unit cannot duplicate or make stock negative")

	# The long stock is a fixture; finite deposits do not replenish at midnight.
	session.stock = 1000
	var to_1459: int = 14 * 60 + 59 - (runtime.daily.now() % 1440)
	TimeComponentManager.advance_minutes(to_1459)
	TimeComponentManager.advance_minutes(1)
	var minutes_at_close: Dictionary = runtime.daily.minutes_by_worker.duplicate()
	var output_at_close: int = int(job.stats[IDS[1]].output) + int(job.stats[IDS[2]].output)
	var stock_at_close: int = session.stock
	_check(_worker(IDS[1]).current_work_status == WorkerData.WorkStatus.RESTING
		and _worker(IDS[2]).current_work_status == WorkerData.WorkStatus.RESTING, "Both workers rest at 15:00")
	TimeComponentManager.advance_minutes(1)
	_check(runtime.daily.minutes_by_worker == minutes_at_close
		and int(job.stats[IDS[1]].output) + int(job.stats[IDS[2]].output) == output_at_close,
		"Neither worker produces after the shift ends")

	# Put the two idle actors at authored departure points to make the next
	# commute reproducible; all movement after this explicit setup is real.
	for id: String in IDS.slice(1):
		var origin: Vector2 = runtime.worker_spawn(SITE, id)
		visuals.actors[id].global_position = origin
		_worker(id).physical_approach.position = origin + Vector2(0, 16)
	TimeComponentManager.advance_minutes(16 * 60 + 59)
	_check(TimeComponentManager.current_day == 21 and TimeComponentManager.current_hour == 8,
		"The real clock reaches the next day after the midnight settlement")
	_check(session.stock == stock_at_close, "Midnight preserves the remaining finite stock without changing either job")
	var outputs_before_walk: Array[int] = [int(job.stats[IDS[1]].output), int(job.stats[IDS[2]].output)]
	TimeComponentManager.advance_minutes(1)
	_check(int(job.stats[IDS[1]].output) == outputs_before_walk[0] and int(job.stats[IDS[2]].output) == outputs_before_walk[1],
		"A clock skip cannot create next-day arrival or output")
	visuals._process(0.1)
	for id: String in IDS.slice(1):
		_check(not _worker(id).physical_approach.arrived, id + " is still physically travelling before save")
	_check(_worker(IDS[1]).physical_approach.target != _worker(IDS[2]).physical_approach.target,
		"Distinct entries survive the next shift")
	_check(store.save_checkpoint(), "Save both in-flight workers: " + store.last_error)

func _read_scenario() -> void:
	_check(store.load_checkpoint(), "Continue both in-flight workers: " + store.last_error)
	if failures:
		return
	for _i in range(3):
		await get_tree().process_frame
	visuals.set_process(false)
	var job: Dictionary = runtime.daily.jobs.get(SITE, {})
	_check(not job.is_empty() and job.ids == IDS.slice(1), "Continue restores both assignments in order")
	if job.is_empty() or not WorkerDatabase.has_worker_data(IDS[1]) or not WorkerDatabase.has_worker_data(IDS[2]):
		return
	var saved_approaches: Dictionary = {}
	for id: String in IDS.slice(1):
		var worker: WorkerData = _worker(id)
		saved_approaches[id] = worker.physical_approach.duplicate(true)
		_check(not worker.physical_approach.arrived, id + " resumes its pending journey")
	_check(saved_approaches[IDS[1]].target != saved_approaches[IDS[2]].target, "Continue keeps distinct destinations")
	var before_output: Array[int] = [int(job.stats[IDS[1]].output), int(job.stats[IDS[2]].output)]
	var before_stock: int = runtime.sites[SITE].stock
	_walk_until_arrived(IDS.slice(1))
	TimeComponentManager.advance_minutes(30)
	var produced: int = int(job.stats[IDS[1]].output) + int(job.stats[IDS[2]].output) - before_output[0] - before_output[1]
	_check(int(job.stats[IDS[1]].output) > before_output[0] and int(job.stats[IDS[2]].output) > before_output[1],
		"Both restored workers contribute after physically arriving")
	_check(before_stock - runtime.sites[SITE].stock == produced, "Restored workers consume shared stock exactly once")
	_check(store.load_checkpoint(), "The same checkpoint can be loaded repeatedly: " + store.last_error)
	for id: String in IDS.slice(1):
		_check(_worker(id).physical_approach == saved_approaches[id], id + " returns to the saved pose without duplication")

	# Recreate the old, valid schema with two workers sharing one target. This
	# uses another isolated slot and never changes a player's existing checkpoint.
	store.disk.path = "user://multi_worker_navigation/legacy_overlap.json"
	_check(not FileAccess.file_exists(store.disk.path), "The legacy compatibility fixture uses a fresh slot")
	if failures > 0:
		return
	var old_shared_entry: Vector2 = _worker(IDS[1]).physical_approach.target
	for id: String in IDS.slice(1):
		var worker: WorkerData = _worker(id)
		worker.physical_approach.target = old_shared_entry
		worker.physical_approach.position = old_shared_entry
		_check(worker.mark_physical_arrival(worker.physical_approach.task),
			"Create the previously valid overlapping arrived state for " + id)
	runtime.daily._sync_activities()
	_check(store.save_checkpoint(), "A legacy overlapping approach remains save-compatible: " + store.last_error)
	_check(store.load_checkpoint(), "A legacy overlapping approach can be loaded: " + store.last_error)
	for _i in range(3):
		await get_tree().process_frame
	visuals.set_process(false)
	_check(_worker(IDS[1]).physical_approach.arrived and _worker(IDS[2]).physical_approach.arrived
		and _worker(IDS[1]).physical_approach.target == _worker(IDS[2]).physical_approach.target,
		"Loading keeps both recorded arrived journeys rather than rewriting their saved poses")
	TimeComponentManager.advance_minutes(24 * 60)
	visuals._process(0.0)
	_check(_worker(IDS[1]).physical_approach.target != _worker(IDS[2]).physical_approach.target,
		"An old overlapping checkpoint claims separate entries on the next shift")
	_walk_until_arrived(IDS.slice(1))
	_check(_worker(IDS[1]).physical_approach.arrived and _worker(IDS[2]).physical_approach.arrived,
		"Both workers physically reach their recovered entries")

	# The reverse removal order also preserves the survivor's entry.
	var surviving_target: Vector2 = _worker(IDS[2]).physical_approach.target
	_check(runtime.daily.withdraw(SITE, IDS[1]), "Withdraw the other original teammate")
	_assign(IDS[0])
	_check(_worker(IDS[2]).physical_approach.target == surviving_target
		and _worker(IDS[0]).physical_approach.target != surviving_target,
		"Reverse-order replacement uses the vacant entry without disturbing the survivor")
	_walk_until_arrived([IDS[0]])
