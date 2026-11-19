extends Node

const STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const PANEL_SCENE: PackedScene = preload("res://scenes/ui/citizen_inspection/citizen_inspection_panel.tscn")
const MINUTE_RATE: float = 0.05 / 1440.0

var storage: Node
var failures: int = 0
var left_events: int = 0
var panel: CitizenInspectionPanel

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _near(actual: float, expected: float, label: String, tolerance: float = 0.000002) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s: expected %.9f, got %.9f" % [label, expected, actual])

func _reset(day: int = 20, hour: int = 10) -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	TimeComponentManager.current_day = day
	TimeComponentManager.current_hour = hour
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
	CitizenNeedsManager._daily_needs_retry_pending = false
	storage.items.clear()
	storage.food_portions.clear()
	storage.units.clear()
	CityStockManager.shelter_capacity = 0
	left_events = 0

func _person(id: String, satisfaction: float) -> CitizenData:
	var citizen := CitizenData.new()
	citizen.citizen_id = id
	citizen.display_name = id
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	citizen.satisfaction = satisfaction
	CitizenManager.add_citizen(citizen)
	return citizen

func _advance(minutes: int) -> void:
	_expect(TimeComponentManager.advance_minutes(minutes), "The clock accepted %d simulated minutes." % minutes)

func _left(citizen: CitizenData) -> void:
	if citizen.citizen_id == "leaver":
		left_events += 1

func _capture(label: String) -> void:
	var directory: String = OS.get_environment("TIP_TIME_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	_expect(get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK,
		"The actual live needs panel was captured: " + label)

func _run() -> void:
	storage = WorkStateRuntime.get_node_or_null("CityToolStorage")
	if storage == null:
		storage = STORAGE_SCRIPT.new()
		storage.name = "CityToolStorage"
		WorkStateRuntime.add_child(storage)
	CitizenManager.citizen_left.connect(_left)

	# A ration supplied after 12 hours cannot undo 12 hours without food.
	_reset()
	var late := _person("late", 0.30)
	await get_tree().process_frame
	panel = PANEL_SCENE.instantiate()
	panel.summary_provider = Callable(CitizenNeedsManager, "get_person_needs_summary")
	add_child(panel)
	panel.open_for("late")
	await get_tree().process_frame
	_advance(720)
	_near(late.satisfaction, 0.275, "Twelve game hours with no service")
	panel.call("_refresh_view")
	await _capture("shortage")
	_expect(storage.try_add_worksite_output("barley_bread", 1), "A real bread delivery is accepted.")
	await get_tree().process_frame
	await get_tree().process_frame
	var late_summary: Dictionary = CitizenNeedsManager.get_person_needs_summary("late")
	_expect(bool(late_summary.get("food", false)), "Actual delivered food becomes a live entitlement.")
	panel.call("_refresh_view")
	var food_icon: TextureRect = panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/DailyNeedsRow/FoodStatus/Status/MetIcon")
	_expect(food_icon.visible, "The open citizen panel displays the actual newly received food.")
	for _repeat: int in range(3):
		panel.close()
		panel.open_for("late")
	_expect(panel.visible and food_icon.visible, "Repeated open/close keeps the real food state visible.")
	await _capture("food-received")
	_expect(storage.get_food_supply_points() == 0, "The entitlement consumes one physical food point.")
	var expiry: int = int(CitizenNeedsManager.food_coverage_until.get("late", -1))
	var delivered_at: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	_expect(expiry == delivered_at + 1440, "A consumed ration covers exactly 24 game hours from delivery.")
	TimeComponentManager.emit_time_signal()
	CitizenNeedsManager.process_daily_needs()
	CitizenNeedsManager.process_daily_needs()
	_expect(storage.get_food_supply_points() == 0 and int(CitizenNeedsManager.food_coverage_until.get("late", -1)) == expiry,
		"Repeated snapshot and settlement calls do not create extra food coverage.")
	_advance(720)
	_near(late.satisfaction, 0.30, "Recovery after twelve further hours with food")
	_expect(bool(CitizenNeedsManager.get_person_needs_summary("late").get("food", false)), "Food remains covered halfway through entitlement.")
	_advance(720)
	_near(late.satisfaction, 0.325, "The entire consumed ration provides 24 hours of coverage")
	_expect(not bool(CitizenNeedsManager.get_person_needs_summary("late").get("food", true)), "Food coverage expires at the actual entitlement deadline.")

	# A newcomer starts at their own arrival minute, not at a previous day's clock.
	_reset(30)
	var old := _person("old", 0.5)
	await get_tree().process_frame
	_advance(360)
	_near(old.satisfaction, 0.4875, "Existing resident after six hours")
	var newcomer := _person("newcomer", 0.5)
	await get_tree().process_frame
	_near(newcomer.satisfaction, 0.5, "New arrival has no pre-arrival change")
	_advance(60)
	_near(newcomer.satisfaction, 0.5 - 60.0 * MINUTE_RATE, "New arrival accrues only one subsequent hour")
	# Linked employment must not create a second consumer or mix service targets.
	_reset(32)
	CityStockManager.shelter_capacity = 1
	storage.items["barley_bread"] = 1
	var served := _person("served_linked", 0.5)
	served.employment_status = CitizenData.EmploymentStatus.HIRED
	var linked := WorkerData.new()
	linked.worker_id = served.citizen_id
	WorkerDatabase.workers_by_id[linked.worker_id] = linked
	var unserved := _person("unserved", 0.5)
	await get_tree().process_frame
	_expect(CitizenNeedsManager.get_food_consumer_count() == 2 and storage.get_food_supply_points() == 0,
		"A linked worker consumes one ration as a resident, without a duplicate worker ration.")
	_advance(720)
	_near(served.satisfaction, 0.525, "A fed sheltered linked worker improves gradually")
	_near(unserved.satisfaction, 0.475, "An unserved civilian simultaneously declines gradually")
	_near(linked.get_resolved_satisfaction(), served.satisfaction, "The linked worker reads the same individual value")
	_reset(35)
	var full := _person("full_start", 1.0)
	await get_tree().process_frame
	_advance(1)
	_near(full.satisfaction, 1.0 - MINUTE_RATE, "A valid 100% start observes the per-minute rate limit", 0.0000005)

	# Snapshot signals and pause must not advance needs. Exact zero causes one departure.
	_reset(40)
	var leaver := _person("leaver", 0.00005)
	await get_tree().process_frame
	panel.open_for("leaver")
	var satisfaction_label: Label = panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/SatisfactionLabel")
	_expect(satisfaction_label.text == "Actual satisfaction: 1%", "A positive value below one percent displays as 1% without changing its underlying value.")
	TimeComponentManager.is_paused = true
	TimeComponentManager._process(100.0)
	TimeComponentManager.emit_time_signal()
	_near(leaver.satisfaction, 0.00005, "Paused and snapshot-only clock")
	_expect(left_events == 0, "A positive Satisfaction resident does not leave before reaching zero.")
	TimeComponentManager.is_paused = false
	_advance(1)
	_expect(leaver.population_status == CitizenData.PopulationStatus.RESIDENT and leaver.satisfaction > 0.0, "A resident remains at a small positive value.")
	_advance(1)
	_expect(leaver.population_status == CitizenData.PopulationStatus.LEFT_CITY and is_zero_approx(leaver.satisfaction), "A resident leaves at actual zero.")
	_advance(2)
	CitizenNeedsManager.process_daily_needs()
	_expect(left_events == 1, "Repeated ticks and daily calls emit one departure only.")

	# Bulk and ordinary frame time must account for the same elapsed minutes.
	_reset(50)
	var bulk := _person("bulk", 0.5)
	await get_tree().process_frame
	_advance(720)
	var bulk_result: float = bulk.satisfaction
	_reset(50)
	var normal := _person("normal", 0.5)
	await get_tree().process_frame
	for _minute: int in range(720):
		TimeComponentManager._process(TimeComponentManager.seconds_per_minute)
	_near(normal.satisfaction, bulk_result, "Normal frame clock equals bulk skip")
	_near(bulk_result, 0.475, "Twelve hours respect the five points per day limit")
	_reset(60)
	var three_days := _person("three_days", 0.5)
	await get_tree().process_frame
	_advance(4320)
	_near(three_days.satisfaction, 0.35, "A three-day skip integrates all 4320 minutes", 0.00001)

	print("GradualNeedsTest: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
