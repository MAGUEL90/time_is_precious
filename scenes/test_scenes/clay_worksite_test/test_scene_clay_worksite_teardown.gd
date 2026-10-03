extends Node

var failures: int = 0
var fixture: Node
var detach_at_minute: int = -1
var detach_with_transition: bool = false
var free_player_on_detach: bool = false
var reentry_fixture: Node
var reentry_site
var reentry_attempted: bool = false
var reentry_was_working: bool = false
var reentry_result: Dictionary = {}
var reentry_minute_before: int = -1
var reentry_minute_after: int = -1
var reentry_stock_after_cancel: int = -1

func _ready() -> void:
	_run.call_deferred()

func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _run() -> void:
	var saved_clock: Dictionary = {
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
	}
	var saved_inventory: Dictionary = Inventory.items.duplicate(true)
	var saved_max_load: float = Inventory.max_load
	var saved_time_process: bool = TimeComponentManager.is_processing()
	var saved_transition: bool = SceneTransition.is_transitioning
	TimeComponentManager.set_process(false)
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_minute = 0
	SceneTransition.is_transitioning = false

	await _run_teardown_case("owner_detached", false, false)
	await _run_teardown_case("owner_detached_during_transition", true, false)
	await _run_teardown_case("player_freed", false, true)
	await _run_normal_completion_control()

	TimeComponentManager.current_day = int(saved_clock.day)
	TimeComponentManager.current_hour = int(saved_clock.hour)
	TimeComponentManager.current_minute = int(saved_clock.minute)
	TimeComponentManager.set_process(saved_time_process)
	SceneTransition.is_transitioning = saved_transition
	Inventory.items = saved_inventory
	Inventory.max_load = saved_max_load
	print("ClayWorksiteTeardownTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)

func _run_teardown_case(case_name: String, transition: bool, free_player: bool) -> void:
	Inventory.items.clear()
	Inventory.max_load = 1000.0
	fixture = load("res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn").instantiate()
	fixture.prepare_nightmare_test = false
	add_child(fixture)
	await get_tree().process_frame
	fixture.player.debug_disable_player_needs = true
	var site = fixture.sites[&"ClaySiteA"]
	var stock_before: int = site.stock
	_expect(site.toggle_participant("player"), case_name + " starts with Player selected.")
	detach_with_transition = transition
	free_player_on_detach = free_player
	detach_at_minute = _now() + 11
	TimeComponentManager.minute_changed.connect(_interrupt_on_minute)
	var start_time: int = _now()
	var result: Dictionary = site.execute(180, fixture.player, fixture, fixture._drop_output)
	TimeComponentManager.minute_changed.disconnect(_interrupt_on_minute)
	var elapsed: int = _now() - start_time
	var bag: int = int(Inventory.items.get("clay_lump", 0))
	_expect(elapsed == 11, case_name + " stops time at the teardown minute.")
	_expect(result.minutes == elapsed and result.interrupted, case_name + " reports elapsed interrupted work.")
	_expect(result.units == 0 and result.to_bag == 0 and result.to_ground == 0,
		case_name + " reports no output after cancellation.")
	_expect(site.stock == stock_before and bag == 0 and site.stock + bag == stock_before,
		case_name + " returns earned stock without duplicating it into Inventory.")
	_expect(not site.working, case_name + " clears the work session.")
	_expect(site.last_result.minutes == 11 and site.last_result.interrupted
		and site.last_result.units == 0 and site.last_result.to_bag == 0
		and site.last_result.to_ground == 0,
		case_name + " stores a truthful canceled result for later readers.")
	var stock_after_first_cancel: int = site.stock
	site.cancel()
	_expect(site.stock == stock_after_first_cancel, case_name + " repeated cancellation does not refund twice.")
	_expect(_has_result_schema(result), case_name + " preserves the public result dictionary schema.")
	SceneTransition.is_transitioning = false
	# The freed-Player case must not leave its controller alive for another frame.
	fixture.free()
	await get_tree().process_frame

func _interrupt_on_minute(_minute: int) -> void:
	if fixture == null or _now() != detach_at_minute:
		return
	if detach_with_transition:
		SceneTransition.is_transitioning = true
	if free_player_on_detach:
		fixture.get_node("Player").free()
	else:
		fixture.get_parent().remove_child(fixture)

func _run_normal_completion_control() -> void:
	Inventory.items.clear()
	Inventory.max_load = 1000.0
	fixture = load("res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn").instantiate()
	fixture.prepare_nightmare_test = false
	add_child(fixture)
	await get_tree().process_frame
	fixture.player.debug_disable_player_needs = true
	var site = fixture.sites[&"ClaySiteA"]
	var stock_before: int = site.stock
	_expect(site.toggle_participant("player"), "Normal control starts with Player selected.")
	reentry_fixture = fixture
	reentry_site = site
	reentry_attempted = false
	reentry_result.clear()
	Inventory.items_changed.connect(_reenter_during_settlement)
	var start_time: int = _now()
	var result: Dictionary = site.execute(180, fixture.player, fixture, fixture._drop_output)
	Inventory.items_changed.disconnect(_reenter_during_settlement)
	var elapsed: int = _now() - start_time
	var bag: int = int(Inventory.items.get("clay_lump", 0))
	_expect(reentry_attempted and reentry_was_working,
		"Inventory notification sees the original session held busy during payout.")
	_expect(reentry_result.get("minutes", -1) == 0 and reentry_minute_before == reentry_minute_after,
		"Reentrant execute is rejected without advancing time.")
	_expect(reentry_stock_after_cancel == stock_before - 18,
		"Cancel during claimed settlement cannot refund output twice.")
	_expect(elapsed == 180 and result.minutes == 180 and not result.interrupted,
		"Normal control completes the requested time.")
	_expect(result.units == 18 and result.to_bag == 18 and result.to_ground == 0 and bag == 18,
		"Normal control settles all completed output once.")
	_expect(site.stock == stock_before - 18 and site.stock + bag == stock_before,
		"Normal control preserves stock and Inventory conservation.")
	_expect(not site.working and _has_result_schema(result),
		"Normal control clears the session and keeps the result schema.")
	fixture.queue_free()
	await get_tree().process_frame

func _has_result_schema(result: Dictionary) -> bool:
	return (result.size() == 5 and result.has("units") and result.has("minutes")
		and result.has("interrupted") and result.has("to_bag") and result.has("to_ground"))

func _reenter_during_settlement() -> void:
	if reentry_attempted:
		return
	reentry_attempted = true
	reentry_was_working = reentry_site.working
	reentry_minute_before = _now()
	reentry_result = reentry_site.execute(180, reentry_fixture.player, reentry_fixture, reentry_fixture._drop_output)
	reentry_site.cancel()
	reentry_minute_after = _now()
	reentry_stock_after_cancel = reentry_site.stock

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
