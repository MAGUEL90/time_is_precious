extends Node

## Two separate processes share only these explicit fixture checkpoint files.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const SNAPSHOT = preload("res://scenes/new_scenes/save_game/city_save_state.gd")
const FILE = preload("res://scenes/new_scenes/save_game/city_save_file.gd")
const WORKER_ID: String = "site_arrival_continue_fixture"
var city: Node
var runtime: Node
var visuals: Node
var snapshot = SNAPSHOT.new()
var worker: WorkerData
var failures: int = 0
var phase: String = "write"

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--site-arrival-phase="):
			phase = argument.trim_prefix("--site-arrival-phase=")
	_check(phase in ["write", "read"], "Known isolated site arrival phase")
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
	# Let Player's deferred cursor attach before this fixture frees the city.
	await get_tree().process_frame
	if phase == "write":
		_write()
	else:
		_read()
	city.free()
	print("SiteArrivalContinue ", phase, ": ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _write() -> void:
	worker = WorkerData.new()
	worker.worker_id = WORKER_ID
	worker.display_name = "Site arrival continue fixture"
	worker.payroll_start_day = 20
	worker.payroll_paid_from_day = 20
	worker.payroll_paid_until_day = 23
	worker.payroll_last_attempt_day = 20
	worker.payroll_period_rate = 1
	worker.payroll_contract_days = 3
	worker.payroll_paid_start_minute = 20 * 1440 + 11 * 60
	WorkerDatabase.workers_by_id[WORKER_ID] = worker
	runtime.daily.tool_requirement = Callable()
	_check(runtime.daily.toggle(&"ClaySiteA", WORKER_ID), "Select explicit fixture worker")
	_check(runtime.daily.start(&"ClaySiteA", func(_amount: int) -> bool: return true), "Start native physical assignment")
	visuals._process(0.2)
	_check(not worker.physical_approach.arrived, "Pending writer captures physical approach")
	_write_case("pending")
	_walk()
	_check(worker.physical_approach.arrived, "Arrived writer followed the real collision-respecting route")
	TimeComponentManager.advance_minutes(1)
	_write_case("arrived")

func _write_case(name: String) -> void:
	var disk = FILE.new()
	disk.path = "user://site_arrival_continue/" + name + ".json"
	_check(not disk.exists(), "Write phase requires fresh isolated " + name + " fixture path")
	if disk.exists():
		return
	disk.read_snapshot(_validate)
	var document: Dictionary = snapshot.capture(city)
	_check(not document.is_empty(), "Capture " + name + ": " + snapshot.error)
	_check(disk.write_snapshot(document, _validate), "Persist validated " + name + ": " + disk.error + " " + snapshot.error)

func _read() -> void:
	for name: String in ["pending", "arrived"]:
		var disk = FILE.new()
		disk.path = "user://site_arrival_continue/" + name + ".json"
		var document: Dictionary = disk.read_snapshot(_validate)
		_check(not document.is_empty(), "Separate-process read " + name + ": " + disk.error + " " + snapshot.error)
		if document.is_empty():
			continue
		_check(snapshot.prepare(document, city), "Prepare selected " + name + " snapshot")
		var expected: Dictionary = snapshot.prepared.workers.workers_by_id[WORKER_ID].physical_approach.duplicate(true)
		var expected_minutes: int = int(snapshot.prepared.worksites.ledger.minutes.get(WORKER_ID, 0))
		snapshot.apply_prepared(city, false)
		worker = WorkerDatabase.get_worker_data(WORKER_ID)
		_check(worker.physical_approach == expected, "Restore exact physical record in fresh process: " + name)
		visuals._process(0.0)
		_check(visuals.actors[WORKER_ID].global_position + Vector2(0, 16) == Vector2(expected.position),
			"Restore exact actual feet without a snap: " + name)
		_check(worker.physical_approach.arrived == (name == "arrived"), "Preserve pending/arrived evidence: " + name)
		TimeComponentManager.advance_minutes(1)
		_check(int(runtime.daily.minutes_by_worker.get(WORKER_ID, 0)) == expected_minutes + (1 if name == "arrived" else 0),
			"Continue counts paid time only after actual arrival: " + name)
		if name == "pending":
			_walk()
			TimeComponentManager.advance_minutes(1)
			_check(worker.physical_approach.arrived and int(runtime.daily.minutes_by_worker.get(WORKER_ID, 0)) == expected_minutes + 1,
				"Continued pending worker physically arrives before its first production minute")

func _walk() -> void:
	for _frame: int in range(2000):
		if worker.physical_approach.arrived:
			return
		visuals._process(0.05)

func _validate(document: Dictionary) -> bool:
	return snapshot.prepare(document, city)
