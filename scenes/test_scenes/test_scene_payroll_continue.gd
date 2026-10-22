extends Node
## Fixture-owned money/rates/clock, real New Game/Continue and checkpoint files.
## Player and citizen needs remain active. This is not a normal-income journey.
const MENU = preload("res://scenes/ui/start_menu/start_menu.tscn")
const VALUES = preload("res://scenes/new_scenes/save_game/city_save_values.gd")
const PATH: String = "user://payroll_continue/checkpoint.json"
var checkpoint_path: String = PATH
var failures: int = 0
var mode: String = "write"
var launched: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	get_tree().current_scene = null
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--payroll-phase="):
			mode = argument.trim_prefix("--payroll-phase=")
	TimeComponentManager.set_process(false)
	WorkerDatabase.onboarding_period_rates = {WorkerData.Profession.LABORER: 1, WorkerData.Profession.HAULER: 2}
	var menu = MENU.instantiate()
	if mode.begins_with("sleep-"):
		checkpoint_path = "user://payroll_sleep/checkpoint.json"
	menu.checkpoint_file.path = checkpoint_path
	menu.session_started.connect(func(_continued: bool): launched = true)
	get_tree().root.add_child(menu)
	if mode in ["write", "sleep-write"]:
		menu._request_new_game()
	else:
		menu.continue_button.pressed.emit()
	for frame: int in range(600):
		if launched:
			break
		await get_tree().process_frame
	check(launched, "Real startup menu must finish " + mode)
	if not launched:
		_finish()
		return
	var city: Node = get_tree().current_scene
	var player: Player = city.get_node("YSortWorld/Player")
	check(not player.debug_disable_player_needs and not player.debug_disable_fatigue, "Player needs stay active")
	var store: Node = WorkStateRuntime.get_node("CitySave")
	if mode.begins_with("sleep-"):
		await _sleep_flow(city, player, store)
		_finish()
		return
	if mode == "write":
		check(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(), "New Game starts empty before fixture grants")
		TimeComponentManager.current_hour = 16
		TimeComponentManager.current_minute = 59
		Inventory.add_item("shekel", 3)
		check(CityStockManager.deposit_wallet_shekel(1), "Explicit initial fixture deposit")
		var worker: WorkerData = WorkerDatabase.hire_applicant("initial_workshop_laborer")
		var hauler: WorkerData = WorkerDatabase.hire_applicant("initial_worksite_hauler")
		check(worker != null and hauler != null, "Both authored applicants hired before closing")
		if worker == null or hauler == null:
			_finish()
			return
		check(worker.is_waiting_for_first_payment() and not WorkerDatabase.assign_worker(worker.worker_id), "Pending hire cannot start work")
		# Place fixture immediately before the actual elapsed 08:00 boundary.
		TimeComponentManager.current_day = worker.payroll_start_day
		TimeComponentManager.current_hour = 7
		TimeComponentManager.current_minute = 59
		TimeComponentManager.emit_time_signal()
	else:
		var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		check(_canonical(store.snapshot.capture(city)) == _canonical(disk), "Separate-process Continue restores every captured field exactly")
		var worker: WorkerData = WorkerDatabase.get_worker_data("initial_workshop_laborer")
		var hauler: WorkerData = WorkerDatabase.get_worker_data("initial_worksite_hauler")
		check(worker != null and hauler != null, "Both hires survive Continue")
		if worker == null or hauler == null:
			_finish()
			return
		if mode == "pending":
			check(worker.is_waiting_for_first_payment(), "Pending state restored before 08:00")
			TimeComponentManager.advance_minutes(1)
			check(worker.is_waiting_for_first_payment() and hauler.is_waiting_for_first_payment() and CityStockManager.treasury_shekel == 1, "Insufficient group payment deducts nothing")
			check(CityStockManager.deposit_wallet_shekel(2), "Explicit top-up after failed batch")
			TimeComponentManager.emit_time_signal()
			TimeComponentManager.hour_changed.emit(8)
			check(worker.is_waiting_for_first_payment() and CityStockManager.treasury_shekel == 3, "Snapshot and same-day replay cannot retry top-up")
		elif mode == "waiting":
			check(worker.is_waiting_for_first_payment() and worker.payroll_last_attempt_day == TimeComponentManager.current_day, "Failed attempt persists")
			# Fixture boundary placement avoids starving a player during a 24h jump.
			TimeComponentManager.current_day += 1
			TimeComponentManager.current_hour = 7
			TimeComponentManager.current_minute = 59
			TimeComponentManager.advance_minutes(1)
			check(not worker.is_waiting_for_first_payment() and not hauler.is_waiting_for_first_payment(), "Next morning pays the whole waiting group")
			check(CityStockManager.treasury_shekel == 0 and Inventory.items.get("shekel", 0) == 0, "Only deposited city funds are charged once")
			check(worker.payroll_paid_until_day == worker.payroll_paid_from_day + 6 and hauler.payroll_period_rate == 2, "Seven full days and profession rate persist")
		elif mode == "paid":
			check(worker.payroll_period_rate == 1 and not worker.is_waiting_for_first_payment(), "Paid state survives Continue")
			TimeComponentManager.emit_time_signal()
			TimeComponentManager.hour_changed.emit(8)
			check(CityStockManager.treasury_shekel == 0, "Paid Continue never charges twice")
			_test_legacy_and_corruption(store, city)
		else:
			check(false, "Unknown test phase")
	# Settle layout before asserting the actual modal at 400x225.
	var board: JobBoardUI = preload("res://scenes/ui/job_board_ui/job_board_ui.tscn").instantiate()
	city.add_child(board)
	board.open()
	for frame: int in range(3):
		await get_tree().process_frame
	check(board.treasury_label.text.contains("City"), "Job Board shows shared treasury")
	var window: Control = board.get_node("Root/Center/Window")
	check(window.size.x <= 400 and window.size.y <= 225, "Job Board fits logical viewport")
	var actions: Control = board.get_node("Root/Center/Window/Margin/MainVBox/Actions")
	check(actions.get_global_rect().end.y <= window.get_global_rect().end.y - 12, "Job Board actions stay inside window")
	board.close()
	board.queue_free()
	await get_tree().process_frame
	if mode != "paid":
		check(store.save_checkpoint(), "Write next phase checkpoint: " + store.last_error)
	_finish()

func _canonical(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))

func _test_legacy_and_corruption(store: Node, city: Node) -> void:
	var current: Dictionary = store.snapshot.capture(city)
	var legacy: Dictionary = current.duplicate(true)
	legacy.schema_version = 4
	_strip_plot_payroll(legacy)
	_strip_payroll(legacy.state)
	check(store.snapshot.prepare(legacy, city), "v4 worker codec explicitly migrates omitted fields")
	check(store.snapshot.prepared.workers.workers_by_id.initial_workshop_laborer.payroll_start_day == -1, "Legacy workers retain old behavior without retroactive charge")
	for version: int in [1, 2, 3]:
		var legacy_values = VALUES.new()
		var legacy_raw: Dictionary = legacy_values.decode(current.state)
		if version == 3:
			var palms: Dictionary = {}
			for id: String in legacy_raw.pickup_sources:
				if id.begins_with("DatePalm_"):
					palms[id] = legacy_raw.pickup_sources[id].duplicate(true)
					palms[id].erase("config")
			legacy_raw["date_palms"] = palms
		legacy_raw.erase("pickup_sources")
		var older: Dictionary = current.duplicate(true)
		older.schema_version = version
		if version == 1:
			older.erase("location")
		older.state = legacy_values.encode(legacy_raw)
		_strip_plot_payroll(older)
		_strip_payroll(older.state)
		check(store.snapshot.prepare(older, city), "Legacy v%d with original worker schema prepares" % version)
	var malformed: Dictionary = current.duplicate(true)
	_strip_payroll(malformed.state)
	check(not store.snapshot.prepare(malformed, city), "Current schema cannot silently accept missing payroll fields")
	var values = VALUES.new()
	var raw: Dictionary = values.decode(current.state)
	raw.workers.workers_by_id.initial_workshop_laborer.payroll_paid_until_day += 1
	malformed = current.duplicate(true)
	malformed.state = values.encode(raw)
	check(not store.snapshot.prepare(malformed, city), "Reject corrupt paid duration before applying owners")
	check(store.snapshot.prepare(current, city), "Current snapshot still valid after rejected corruption")

func _strip_payroll(value: Variant) -> void:
	if value is Dictionary:
		if value.get("$type") == "object" and value.get("class") == "WorkerData":
			for field: String in VALUES.PAYROLL_FIELDS:
				value.fields.erase(field)
		for child: Variant in value.values():
			_strip_payroll(child)
	elif value is Array:
		for child: Variant in value:
			_strip_payroll(child)

func _finish() -> void:
	print("PayrollContinue ", mode, ": ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _sleep_flow(city: Node, player: Player, store: Node) -> void:
	if mode == "sleep-read":
		check(store.snapshot.is_home(city), "Continue reopens the saved home")
		var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(checkpoint_path))
		check(_canonical(store.snapshot.capture(city)) == _canonical(disk), "Home Continue restores exact sleep checkpoint")
		var worker: WorkerData = WorkerDatabase.get_worker_data("initial_workshop_laborer")
		check(worker != null and worker.payroll_paid_from_day == TimeComponentManager.current_day, "Home Continue retains payment made during sleep")
		check(CityStockManager.treasury_shekel == 0, "Home Continue does not recharge payroll")
		return
	Inventory.add_item("shekel", 1)
	check(CityStockManager.deposit_wallet_shekel(1), "Sleep fixture explicitly funds city")
	var worker: WorkerData = WorkerDatabase.hire_applicant("initial_workshop_laborer")
	check(worker != null, "Sleep fixture hires authored applicant")
	if worker == null:
		return
	TimeComponentManager.current_day = worker.payroll_start_day
	TimeComponentManager.current_hour = 1
	TimeComponentManager.current_minute = 0
	TimeComponentManager.emit_time_signal()
	city.get_node("YSortWorld/HomeDoor")._on_body_entered(player)
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var scene: Node = get_tree().current_scene
		if is_instance_valid(scene) and store.snapshot.is_home(scene) and not SceneTransition.is_transitioning:
			break
		await get_tree().process_frame
	var home: Node = get_tree().current_scene
	check(store.snapshot.is_home(home), "Fixture enters authored home")
	if not store.snapshot.is_home(home):
		return
	var home_player: Player = home.get_node("YSortWorld/Player")
	check(not home_player.debug_disable_player_needs and not home_player.debug_disable_fatigue, "Sleep keeps player needs active")
	var bed: SleepSpot = home.get_node("YSortWorld/SleepSpot")
	await bed.on_player_interact(home_player)
	check(TimeComponentManager.current_hour == 8 and TimeComponentManager.current_minute == 0, "Real seven-hour sleep crosses exactly 08:00")
	check(not worker.is_waiting_for_first_payment() and CityStockManager.treasury_shekel == 0, "Sleep pays once from the city")
	check(store.status == "Saved" and FileAccess.file_exists(checkpoint_path), "Real bed writes paid home checkpoint: " + store.last_error)

func _strip_plot_payroll(document: Dictionary) -> void:
	var values = VALUES.new()
	var raw: Dictionary = values.decode(document.state)
	for plot: Dictionary in raw.plots.values():
		plot.erase("payroll_work_remainder")
	document.state = values.encode(raw)
