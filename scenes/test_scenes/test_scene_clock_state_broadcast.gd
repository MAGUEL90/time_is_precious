extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const TIME_LABEL_SCENE: PackedScene = preload("res://scenes/time_label/time_label.tscn")

var failures: int = 0
var player: Player
var time_label: Control
var time_snapshot_count: int = 0
var minute_signal_count: int = 0
var hour_signal_count: int = 0
var day_signal_count: int = 0
var new_day_signal_count: int = 0
var weather_signal_count: int = 0
var last_snapshot_day: int = -1
var last_snapshot_hour: int = -1
var last_snapshot_minute: int = -1
var last_snapshot_weather: String = ""
var work_order_id: String = ""

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.time_changed.connect(_on_time_changed)
	TimeComponentManager.minute_changed.connect(_on_minute_changed)
	TimeComponentManager.hour_changed.connect(_on_hour_changed)
	TimeComponentManager.day_changed.connect(_on_day_changed)
	TimeComponentManager.new_day_started.connect(_on_new_day_started)
	TimeComponentManager.weather_changed.connect(_on_weather_changed)

	time_label = TIME_LABEL_SCENE.instantiate()
	add_child(time_label)
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	await get_tree().process_frame

	# Move to a boundary so the same job can cover an ordinary minute and midnight.
	TimeComponentManager.current_hour = 23
	TimeComponentManager.current_minute = 58
	WorkManager.on_time_changed(
		TimeComponentManager.current_day,
		TimeComponentManager.current_hour,
		TimeComponentManager.current_minute
	)
	_set_player_conditions()
	var job: JobData = JobData.new()
	job.job_id = "clock_state_broadcast_test"
	job.display_name = "Clock Snapshot Test"
	job.base_duration_minutes = 1
	job.outputs = {"wood_log": 1}
	var previous_wood_logs: int = int(Inventory.items.get("wood_log", 0))
	work_order_id = WorkManager.start_job(
		job,
		WorkOrder.Worker_Type.PLAYER,
		"clock_state_broadcast_test",
		null,
		Inventory,
		Inventory
	)
	_expect(not work_order_id.is_empty(), "The real WorkManager accepts the one-minute regression job.")
	if work_order_id.is_empty():
		_finish()
		return
	var work_order: WorkOrder = WorkManager.active_orders[work_order_id] as WorkOrder
	var initial_needs: Vector3 = _player_needs()

	TimeComponentManager.emit_time_signal()
	TimeComponentManager.emit_time_signal()
	_expect(time_snapshot_count == 2, "Repeated state broadcasts still reach time consumers.")
	_expect(last_snapshot_day == TimeComponentManager.current_day
		and last_snapshot_hour == 23
		and last_snapshot_minute == 58
		and last_snapshot_weather == TimeComponentManager.current_weather,
		"Each snapshot carries the current day, hour, minute, and weather.")
	_expect(_time_label_text() == _clock_text(TimeComponentManager.current_day, 23, 58),
		"The existing time label refreshes from the state snapshot.")
	_expect(minute_signal_count == 0 and hour_signal_count == 0 and day_signal_count == 0,
		"State broadcasts emit no elapsed minute, hour, or day boundary signals.")
	_expect(_player_needs() == initial_needs,
		"Repeated snapshots do not change actual Player hunger, fatigue, or Focus.")
	_expect(work_order.current_status == WorkOrder.Status.RUNNING
		and WorkManager.active_orders.has(work_order_id)
		and int(Inventory.items.get("wood_log", 0)) == previous_wood_logs,
		"Repeated snapshots do not advance or complete a real work order.")

	TimeComponentManager.advance_one_minute()
	_expect(minute_signal_count == 1 and hour_signal_count == 0 and day_signal_count == 0,
		"Ordinary minute progression emits only one minute boundary signal.")
	_expect(time_snapshot_count == 3
		and last_snapshot_minute == 59
		and _time_label_text() == _clock_text(TimeComponentManager.current_day, 23, 59),
		"Ordinary progression publishes one updated snapshot to time consumers.")
	_expect(_player_needs_match(0.201, 0.3005, 0.79975),
		"One elapsed minute applies Player needs and Focus exactly once.")
	_expect(work_order.current_status == WorkOrder.Status.DONE
		and not WorkManager.active_orders.has(work_order_id)
		and int(Inventory.items.get("wood_log", 0)) == previous_wood_logs + 1,
		"One elapsed work minute completes the job and grants its output once.")

	_set_player_conditions()
	var day_before_midnight: int = TimeComponentManager.current_day
	TimeComponentManager.advance_one_minute()
	_expect(TimeComponentManager.current_day == day_before_midnight + 1
		and TimeComponentManager.current_hour == 0
		and TimeComponentManager.current_minute == 0,
		"Normal minute progression crosses midnight once.")
	_expect(minute_signal_count == 2 and hour_signal_count == 1 and day_signal_count == 1
		and new_day_signal_count == 1 and weather_signal_count == 1,
		"Midnight emits one minute, hour, day, new-day, and weather event.")
	_expect(time_snapshot_count == 4
		and last_snapshot_day == day_before_midnight + 1
		and last_snapshot_hour == 0
		and last_snapshot_minute == 0
		and _time_label_text() == _clock_text(day_before_midnight + 1, 0, 0),
		"Midnight publishes one current snapshot to time consumers.")
	_expect(_player_needs_match(0.201, 0.3005, 0.79975),
		"Midnight's elapsed minute applies Player needs and Focus exactly once.")
	_expect(int(Inventory.items.get("wood_log", 0)) == previous_wood_logs + 1,
		"The completed work order receives no duplicate output at midnight.")
	_finish()

func _on_time_changed(day: int, hour: int, minute: int, weather: String) -> void:
	time_snapshot_count += 1
	last_snapshot_day = day
	last_snapshot_hour = hour
	last_snapshot_minute = minute
	last_snapshot_weather = weather

func _on_minute_changed(_minute: int) -> void:
	minute_signal_count += 1

func _on_hour_changed(_hour: int) -> void:
	hour_signal_count += 1

func _on_day_changed(_day: int) -> void:
	day_signal_count += 1

func _on_new_day_started(_day: int) -> void:
	new_day_signal_count += 1

func _on_weather_changed(_weather: String) -> void:
	weather_signal_count += 1

func _set_player_conditions() -> void:
	player.debug_disable_player_needs = false
	player.debug_disable_fatigue = false
	player.is_sleeping = false
	player.hunger = 0.2
	player.fatigue = 0.3
	player.focus = 0.8

func _player_needs() -> Vector3:
	return Vector3(player.hunger, player.fatigue, player.focus)

func _player_needs_match(hunger: float, fatigue: float, focus: float) -> bool:
	return is_equal_approx(player.hunger, hunger) \
		and is_equal_approx(player.fatigue, fatigue) \
		and is_equal_approx(player.focus, focus)

func _time_label_text() -> String:
	var clock_label: Label = time_label.get_node(
		"VBoxContainer/HBoxContainer/TimeLabel"
	) as Label
	return clock_label.text

func _clock_text(day: int, hour: int, minute: int) -> String:
	return "Day: %d, Hour: %d, Minute: %d" % [day, hour, minute]

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _finish() -> void:
	print("ClockStateBroadcastTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
