extends "res://scenes/test_scenes/test_scene_city_sleep_save.gd"

@export var cross_shift: bool = false

class SleepRouteGate extends Node:
	var worker: WorkerData
	var construction: Node
	var calls: int = 0
	var clock_before: int = -1
	var position_before: Vector2
	var work_before: int
	var changed_while_pending: bool = false

	func prepare_simulated_minute(_arrival_minute: int) -> bool:
		if calls >= 25:
			return true
		var now: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
		if calls == 0:
			clock_before = now
			position_before = worker.physical_approach.position
			work_before = construction._remaining_work_units()
		elif now != clock_before or worker.physical_approach.position != position_before or construction._remaining_work_units() != work_before:
			changed_while_pending = true
		calls += 1
		return false

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	_reset_singletons_before_load()
	await _load_root_city()
	TimeComponentManager.set_process(false)
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	TimeComponentManager.emit_time_signal()
	store.disk.path = "user://staged_plot_home/checkpoint.json"
	var citizen := CitizenData.new()
	citizen.citizen_id = "staged_home_builder"
	citizen.display_name = "Staged Builder"
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	citizen.satisfaction = 0.95
	citizen.visual_profile = VisualProfile.new()
	CitizenManager.add_citizen(citizen)
	Inventory.add_item("shekel", 100)
	_expect(CitizenManager.register_applicant(citizen.citizen_id, WorkerData.Profession.LABORER), "Builder can apply")
	var worker: WorkerData = WorkerDatabase.hire_applicant(citizen.citizen_id, 1, 9)
	_expect(worker != null, "Builder has a paid contract")
	if worker == null:
		_finish_sleep_test()
		return
	TimeComponentManager.current_day = 1
	TimeComponentManager.current_hour = 14 if cross_shift else 7
	TimeComponentManager.current_minute = 55 if cross_shift else 0
	TimeComponentManager.emit_time_signal()
	var house: Node = content.get_node("YSortWorld/CitizenHousePlot")
	var construction: Node = house.construction
	construction.phase = "empty" # Controlled cleaning fixture, not a gameplay rule.
	construction.changed.emit()
	Inventory.add_bulk_item(construction.get_requirements())
	_expect(bool(construction.start_build([worker.worker_id] as Array[String]).get("success", false)), "House work starts")
	for frame: int in range(8):
		await get_tree().process_frame
	var target: Vector2 = construction.worker_entry_position
	var origin: Vector2 = Vector2.INF
	for direction: Vector2 in [Vector2.DOWN, Vector2.RIGHT, Vector2.LEFT, Vector2.UP]:
		if runtime.worksite_navigation.segment_clear(target + direction * 8.0, target):
			origin = target + direction * 8.0
			break
	_expect(origin.is_finite(), "A real clear last approach exists")
	if not origin.is_finite():
		_finish_sleep_test()
		return
	worker.begin_physical_approach("plot", construction.order_id + ":building", construction.order_id, origin, target)
	runtime.get_node("WorkerVisuals").plot_presence.states.clear()
	content.get_node("YSortWorld/HomeDoor")._on_body_entered(player)
	if not await _wait_scene(store.snapshot.HOME_PATH):
		_finish_sleep_test()
		return
	var home: Node = get_tree().current_scene
	player = home.get_node("YSortWorld/Player")
	player.sleep_duration_minutes = 10
	player.last_sleep_day = -1
	TimeComponentManager.set_process(false)
	var before: int = _clock_minute()
	var work_before: int = construction._remaining_work_units()
	_expect(not worker.physical_approach.arrived, "The parked builder has not yet arrived")
	# Freeze ordinary visual frames so this test observes only real staged sleep.
	runtime.get_node("WorkerVisuals").set_process(false)
	var gate := SleepRouteGate.new()
	gate.worker = worker
	gate.construction = construction
	add_child(gate)
	gate.add_to_group("staged_time_participants")
	await home.get_node("YSortWorld/SleepSpot").on_player_interact(player)
	gate.remove_from_group("staged_time_participants")
	_expect(gate.calls == 25 and not gate.changed_while_pending,
		"The real bed waits more than 20 frames without consuming time, movement or work")
	print("SLEEP_PENDING_GATE: calls=", gate.calls, " changed=", gate.changed_while_pending)
	gate.queue_free()
	_expect(bool(player.last_staged_sleep_result.get("completed", false)) and _clock_minute() == before + 10,
		"The actual bed completes staged travel against the parked city geometry")
	if cross_shift:
		_expect(not worker.physical_approach.arrived and int(worker.physical_approach.arrival_minute) == WorkerData.PLOT_DEPARTURE_PENDING,
			"The builder leaves the plot after the 15:00 shift boundary")
	else:
		_expect(worker.physical_approach.arrived and int(worker.physical_approach.arrival_minute) > before,
			"The parked builder records a real simulated arrival during sleep")
	# Cross-shift fixture: arrival at 14:56, then only 14:56–15:00 is paid work.
	var eligible: int = 4 if cross_shift else worker.get_arrived_paid_minutes(before, _clock_minute(), "plot", construction.order_id + ":building", construction.order_id)
	_expect(eligible > 0 and work_before - construction._remaining_work_units() == eligible,
		"Parked construction receives only post-arrival paid work, exactly once")
	_expect(store.status == "Saved", "The parked route and completed sleep checkpoint save successfully")
	print("StagedSleepPlotHomeTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures, " cross_shift=", cross_shift, " work=", eligible)
	_finish_sleep_test()
