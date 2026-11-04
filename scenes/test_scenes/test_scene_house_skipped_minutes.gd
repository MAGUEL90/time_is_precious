extends Node

## Boundary fixtures use the actual city, plot state, navigation and clock.
## Funds, citizens, the cleaned plot and boundary positions are test fixtures.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const HOUSE_ID: String = "construction:citizen_house_1"
const WORK: int = 2880
var failures: int = 0
var content: Node
var state: Node
var runtime: Node
var visuals: Node
var first: WorkerData
var replacement: WorkerData
var watched: WorkerData
var observed_arrival: int = -99

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _observe_simulated_minute(_arrival_minute: int) -> void:
	if watched != null:
		observed_arrival = int(watched.physical_approach.get("arrival_minute", -99))

func _hire(id: String) -> WorkerData:
	var citizen := CitizenData.new()
	citizen.citizen_id = id
	citizen.display_name = id
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	citizen.satisfaction = 0.95
	citizen.visual_profile = VisualProfile.new()
	CitizenManager.add_citizen(citizen)
	_expect(CitizenManager.register_applicant(id, WorkerData.Profession.LABORER), "Fixture citizen applies: " + id)
	var worker: WorkerData = WorkerDatabase.hire_applicant(id, 1, 9)
	_expect(worker != null and not worker.is_payroll_blocked(), "Fixture citizen has a paid contract: " + id)
	return worker

func _set_near_entrance(worker: WorkerData) -> bool:
	var target: Vector2 = state.worker_entry_position
	for direction: Vector2 in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]:
		var start: Vector2 = target + direction * 8.0
		if runtime.worksite_navigation.segment_clear(start, target):
			worker.begin_physical_approach("plot", HOUSE_ID + ":building", HOUSE_ID, start, target)
			visuals.plot_presence.states.erase(worker.worker_id)
			return true
	return false

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	TimeComponentManager.emit_time_signal()
	content = CONTENT.instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	for frame: int in range(4):
		await get_tree().process_frame
	runtime = content.get_node("YSortWorld/WorkerRuntime")
	visuals = runtime.get_node("WorkerVisuals")
	visuals.set_process(false)
	var house: Node = content.get_node("YSortWorld/CitizenHousePlot")
	state = house.construction
	var player: Player = content.get_node("YSortWorld/Player")
	_expect(not player.debug_disable_player_needs and not player.debug_disable_fatigue, "Player needs remain active")
	Inventory.add_item("shekel", 12)
	first = _hire("skip_first")
	var second: WorkerData = _hire("skip_second")
	replacement = _hire("skip_replacement")
	if first == null or second == null or replacement == null:
		_finish()
		return
	TimeComponentManager.current_day = 1
	TimeComponentManager.current_hour = 6
	TimeComponentManager.current_minute = 59
	TimeComponentManager.emit_time_signal()
	state.phase = "empty" # Cleaning is covered by the full house integration test.
	state.changed.emit()
	Inventory.add_bulk_item({"wood_log": 4, "clay_lump": 8, "reed_bundle": 6})
	if OS.get_cmdline_user_args().has("--debug-day"):
		TimeComponentManager.current_hour = 10
		TimeComponentManager.current_minute = 59
		TimeComponentManager.emit_time_signal()
		player.fatigue = 0.0 # A rested fixture permits the one-day jump without disabling needs.
		var entry: Vector2 = house.get_worker_entry_position()
		var debug_actor: Node2D = visuals.ensure_actor(first.worker_id, entry - Vector2(0, 16))
		debug_actor.global_position = entry - Vector2(0, 16)
		_expect(bool(state.start_build([first.worker_id] as Array[String]).get("success", false)), "A paid builder at the entrance starts at 10:59")
		for frame: int in range(5):
			await get_tree().process_frame
		var before_day: int = _now()
		_expect(first.physical_approach.arrived and int(first.physical_approach.arrival_minute) == before_day,
			"The real assignment records the builder's initial arrival")
		var overlay: Node = content.get_node("TimeDebugOverlay")
		overlay._refresh_controls()
		_expect(overlay.can_advance() and not overlay.step_buttons[2].disabled, "The actual +1d button is enabled")
		overlay.step_buttons[2].pressed.emit()
		var next_arrival: int = int(first.physical_approach.get("arrival_minute", -1))
		var work_before_close: int = 15 * 60 - (10 * 60 + 59)
		var work_next_shift: int = _now() - next_arrival
		_expect(_now() == before_day + 1440 and not player.is_collapsing
			and not player.debug_disable_player_needs and not player.debug_disable_fatigue
			and first.physical_approach.get("arrived", false) and next_arrival >= 2 * 1440 + 7 * 60
			and work_next_shift > 0 and state._remaining_work_units() == WORK - work_before_close - work_next_shift,
			"+1d completes the prior departure and credits only both paid shifts after physical arrival")
		var store: Node = WorkStateRuntime.get_node("CitySave")
		store.disk.path = "user://house_skipped_minutes/checkpoint.json"
		var saved_remaining: int = state._remaining_work_units()
		_expect(store.save_checkpoint(), "The post-jump state saves to an isolated checkpoint: " + store.last_error)
		var saved_bytes: PackedByteArray = FileAccess.get_file_as_bytes(store.disk.path)
		for attempt: int in range(2):
			var loaded: bool = store.load_checkpoint()
			var restored: WorkerData = WorkerDatabase.get_worker_data(first.worker_id)
			_expect(loaded and restored != null and restored.physical_approach.get("arrived", false)
				and int(restored.physical_approach.arrival_minute) == next_arrival
				and state._remaining_work_units() == saved_remaining and _now() == before_day + 1440
				and FileAccess.get_file_as_bytes(store.disk.path) == saved_bytes,
				"Repeated Continue preserves arrival, progress, clock and checkpoint bytes")
		_finish()
		return
	if OS.get_cmdline_user_args().has("--at-seven"):
		_expect(TimeComponentManager.advance_minutes(1) and _now() == 1440 + 420, "Reach exactly 07:00")
		var entrance: Vector2 = house.get_worker_entry_position()
		var actor: Node2D = visuals.ensure_actor(first.worker_id, entrance - Vector2(0, 16))
		actor.global_position = entrance - Vector2(0, 16) # Position fixture; the actual assignment marks arrival.
		_expect(bool(state.start_build([first.worker_id] as Array[String]).get("success", false)), "The worker at the entrance starts at 07:00")
		for frame: int in range(5):
			await get_tree().process_frame
		var one_label: Label = house.get_node("BuildingProgress/ProgressPercent")
		_expect(first.physical_approach.arrived and int(first.physical_approach.arrival_minute) == 1440 + 420
			and state._remaining_work_units() == WORK and one_label.text == "0%", "Arrival at 07:00 itself grants no prior work")
		var zero_pixels: PackedByteArray = PackedByteArray()
		var bar_bounds := Rect2i()
		if DisplayServer.get_name() != "headless":
			player.global_position = house.global_position + Vector2(0, 60)
			for frame: int in range(3):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var bar: TextureProgressBar = house.get_node("BuildingProgress")
			bar_bounds = Rect2i(Vector2i(bar.get_global_transform_with_canvas().origin.floor()), Vector2i(bar.size))
			zero_pixels = get_viewport().get_texture().get_image().get_region(bar_bounds).get_data()
		_expect(TimeComponentManager.advance_minutes(1) and state._remaining_work_units() == WORK - 1
			and one_label.text == "0.03%", "Only the first minute after 07:00 is credited")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var one_pixels: PackedByteArray = get_viewport().get_texture().get_image().get_region(bar_bounds).get_data()
			_expect(not zero_pixels.is_empty() and zero_pixels != one_pixels, "The actual house bar pixels distinguish zero from one work unit")
		_finish()
		return
	_expect(bool(state.start_build([first.worker_id, second.worker_id] as Array[String]).get("success", false)), "Two paid builders start the house")
	for frame: int in range(5):
		await get_tree().process_frame
	_expect(runtime.can_simulate_plot_travel(), "The live navigation geometry is ready")
	var label: Label = house.get_node("BuildingProgress/ProgressPercent")
	_expect(label.visible and label.text == "0%" and state._remaining_work_units() == WORK, "Before arrival the visible value is exactly zero")
	_expect(TimeComponentManager.advance_minutes(1), "The clock reaches 07:00")
	_expect(state._remaining_work_units() == WORK and not first.physical_approach.get("arrived", false), "No travel or work is credited before 07:00")
	for minute: int in range(15):
		if first.physical_approach.get("arrived", false) and second.physical_approach.get("arrived", false):
			break
		_expect(TimeComponentManager.advance_minutes(1), "A simulated minute advances")
	_expect(first.physical_approach.get("arrived", false) and second.physical_approach.get("arrived", false)
		and int(first.physical_approach.arrival_minute) > 1440 + 420
		and state._remaining_work_units() == WORK, "Both builders arrive on their real routes without early work")
	_expect(TimeComponentManager.advance_minutes(1) and state._remaining_work_units() == WORK - 2
		and label.text == "0.06%", "The first two real work units are visible without rounding up")
	var before_change: int = state._remaining_work_units()
	var before_label: String = label.text
	second.resignation_pending = true
	_expect(state.resign_worker(second.worker_id) and state._remaining_work_units() == before_change and label.text == before_label,
		"Resignation preserves work units and displayed progress")
	_expect(bool(state.add_replacement_workers([replacement.worker_id] as Array[String]).get("success", false))
		and state._remaining_work_units() == before_change and label.text == before_label,
		"Adding a replacement preserves work units and displayed progress")
	_expect(TimeComponentManager.advance_minutes(10), "Replacement travels during simulated time")
	_expect(replacement.physical_approach.get("arrived", false), "Replacement actually reaches the plot")
	var to_close: int = 899 - (TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute)
	_expect(to_close > 0 and TimeComponentManager.advance_minutes(to_close), "Advance to 14:59")
	_expect(_set_near_entrance(first), "A clear physical route can reach the entrance in one minute")
	# The fixture relocates this worker manually after a long synchronous skip.
	# A real player action happens on a new frame, with a new planning budget.
	await get_tree().process_frame
	TimeComponentManager.simulated_minute_started.connect(_observe_simulated_minute)
	watched = first
	observed_arrival = -99
	var before_close: int = state._remaining_work_units()
	_expect(TimeComponentManager.advance_minutes(1), "Advance through 15:00")
	_expect(observed_arrival == 1440 + 900 and state._remaining_work_units() == before_close - 1
		and int(first.physical_approach.arrival_minute) == WorkerData.PLOT_DEPARTURE_PENDING,
		"Arrival exactly at 15:00 earns no earlier work; only the already-arrived teammate contributes")
	watched = null
	_expect(TimeComponentManager.advance_minutes(1440 - 900 + 479), "Advance to the following 07:59")
	first.payroll_paid_from_day = 0
	first.payroll_paid_start_minute = 0
	first.payroll_paid_until_day = 1
	first.payroll_contract_days = 0 # Legacy contracts expire exactly at 08:00.
	_expect(not first.is_payroll_blocked() and _set_near_entrance(first), "The legacy contract is paid through 07:59")
	await get_tree().process_frame
	watched = first
	observed_arrival = -99
	var before_expiry: int = state._remaining_work_units()
	_expect(TimeComponentManager.advance_minutes(1), "Advance through the contract boundary")
	_expect(observed_arrival == 2 * 1440 + 480 and first.is_payroll_blocked()
		and state._remaining_work_units() == before_expiry - 1,
		"Arrival at contract expiry cannot credit the previous minute")
	watched = null
	before_expiry = state._remaining_work_units()
	_expect(TimeComponentManager.advance_minutes(3) and state._remaining_work_units() == before_expiry - 3,
		"The expired worker earns nothing while the paid teammate continues")
	first.payroll_paid_until_day = 10
	first.payroll_contract_days = 3
	var target: Vector2 = state.worker_entry_position
	first.begin_physical_approach("plot", HOUSE_ID + ":building", HOUSE_ID, target + Vector2(0, 32), target)
	visuals.plot_presence.states.erase(first.worker_id)
	runtime.worksite_navigation.polygons.append(PackedVector2Array([target + Vector2(-12, -12), target + Vector2(12, -12), target + Vector2(12, 12), target + Vector2(-12, 12)]))
	var blocked_start: Vector2 = first.physical_approach.position
	var blocked_remaining: int = state._remaining_work_units()
	_expect(TimeComponentManager.advance_minutes(5) and not first.physical_approach.arrived
		and first.physical_approach.position == blocked_start and state._remaining_work_units() == blocked_remaining - 5,
		"A blocked route never teleports or credits its worker")
	runtime.worksite_navigation.polygons.pop_back()
	visuals.plot_presence.states.erase(first.worker_id)
	CityStockManager.shelter_capacity = CityStockManager.MAX_SHELTER_CAPACITY - 2
	state.completes_at = state._latest_time + 1
	state.payroll_work_remainder = 1 # Two builders: one work unit remains.
	state.changed.emit()
	_expect(state._remaining_work_units() == 1 and label.text == "99.96%", "One remaining work unit never displays 100%")
	_expect(TimeComponentManager.advance_minutes(3) and state.phase == "building"
		and state._remaining_work_units() == 1 and label.text == "99.96%", "A full shelter keeps the last real unit unfinished")
	TimeComponentManager.simulated_minute_started.disconnect(_observe_simulated_minute)
	_finish()

func _finish() -> void:
	print("HouseSkippedMinutesTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
