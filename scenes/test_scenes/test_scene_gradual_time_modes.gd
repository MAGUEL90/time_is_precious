extends Node

const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
var failures: int = 0
var storage: Node
var player: Player
var debug_overlay: Node

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _seed(day: int, id: String) -> CitizenData:
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	TimeComponentManager._timer = 0.0
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	WorkerDatabase.dismissed_workers.clear()
	CitizenNeedsManager.clothing_allocations.clear()
	CitizenNeedsManager.last_needs_results.clear()
	CitizenNeedsManager.food_coverage_until.clear()
	CitizenNeedsManager.satisfaction_last_minute.clear()
	CitizenNeedsManager.last_processed_day = day
	CitizenNeedsManager.last_food_processed_day = day
	CitizenNeedsManager.last_clothing_processed_day = day
	CityStockManager.shelter_capacity = 0
	storage.items.clear()
	storage.food_portions.clear()
	var person := CitizenData.new()
	person.citizen_id = id
	person.display_name = id
	person.satisfaction = 0.5
	person.population_status = CitizenData.PopulationStatus.RESIDENT
	person.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	CitizenManager.add_citizen(person)
	return person

func _run() -> void:
	var profile: String = OS.get_environment("APPDATA").replace("\\", "/").to_lower().trim_suffix("/")
	var user_root: String = ProjectSettings.globalize_path("user://").replace("\\", "/").to_lower()
	_expect(not profile.is_empty() and user_root.begins_with(profile + "/"), "Time mode test uses isolated APPDATA.")
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var content: Node = CONTENT.instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	for _frame: int in range(5):
		await get_tree().process_frame
	player = content.get_node("YSortWorld/Player") as Player
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	player.can_move = true
	storage = WorkStateRuntime.get_node("CityToolStorage")
	debug_overlay = content.get_node("TimeDebugOverlay")
	debug_overlay.set_process(false)
	TimeComponentManager.set_process(false)
	TimeComponentManager.seconds_per_minute = 1.0
	var baseline := _seed(20, "normal_time")
	await get_tree().process_frame
	_expect(TimeComponentManager.advance_minutes(400), "Baseline world clock advances 400 minutes.")
	var expected: float = baseline.satisfaction
	_expect(absf(expected - (0.5 - 0.05 * 400.0 / 1440.0)) < 0.000002, "Baseline accounts for 400 unsupplied minutes.")
	var accelerated := _seed(30, "accelerated_time")
	await get_tree().process_frame
	debug_overlay.set_speed(25)
	_expect(debug_overlay.get_effective_speed() == 25 and debug_overlay.can_advance(), "The real debug overlay accepts x25.")
	for _second: int in range(16):
		debug_overlay._process(1.0)
		TimeComponentManager._process(1.0)
	_expect(TimeComponentManager.current_hour == 16 and TimeComponentManager.current_minute == 40,
		"Sixteen x25 seconds advance the real clock by 400 minutes.")
	_expect(absf(accelerated.satisfaction - expected) < 0.000002, "x25 equals the same normal game minutes.")
	debug_overlay.set_speed(1)
	var sleeper := _seed(40, "sleep_time")
	player.last_sleep_day = -1
	await get_tree().process_frame
	_expect(player.sleep_for_minutes(400), "The real player sleep action advances 400 game minutes.")
	_expect(absf(sleeper.satisfaction - expected) < 0.000002, "Sleeping equals the same normal game minutes.")
	var skipped := _seed(50, "debug_three_days")
	await get_tree().process_frame
	debug_overlay.step_minutes(4320)
	_expect(TimeComponentManager.current_day == 53 and TimeComponentManager.current_hour == 10
		and TimeComponentManager.current_minute == 0, "The actual +3-day debug path advances 4320 minutes.")
	_expect(absf(skipped.satisfaction - 0.35) < 0.00001, "The actual +3-day debug path applies three days of gradual change.")
	print("GradualTimeModesTest: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
