extends Node

const RAID_STATE_SCRIPT: Script = preload("res://scenes/raid/raid_state.gd")
const CITY_STORAGE_SCRIPT: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const CONTENT_SCENE: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const MINUTES_PER_DAY: int = 1440

var failures: int = 0
var content: Node
var player: Player
var wall_spot: Node2D
var wall_map: TileMapLayer
var state: Node
var ui: RaidUI
var storage: Node
var inventory_before: Dictionary = {}
var clock_before: Dictionary = {}
var clock_processing_before: bool = false
var clock_paused_before: bool = false

func _ready() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false

	content = CONTENT_SCENE.instantiate()
	add_child(content)
	await _settle_physics()
	player = content.get_node("YSortWorld/Player") as Player
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	wall_spot = content.get_node("YSortWorld/WallManagementSpot") as Node2D
	wall_map = content.get_node("YSortWorld/WallStone") as TileMapLayer
	state = content.get_node("RaidBootstrap").state
	ui = state.get_node("RaidUI") as RaidUI
	storage = WorkStateRuntime.get_node_or_null("CityToolStorage")
	inventory_before = Inventory.items.duplicate(true)

	_expect(is_instance_valid(storage) and state.storage == storage,
		"The live main-map raid ledger receives the WorkStateRuntime CityToolStorage provider.")
	_expect(wall_spot.get_node("Caption").text == "Iddin-Sin",
		"The live main-map wall caretaker remains identified as Iddin-Sin.")
	_expect(wall_spot.is_in_group("wall_management_spots") and wall_map.get_used_cells().size() > 0,
		"The live main-map caretaker and wall tilemap are present.")
	_assert_approved_profile()
	_expect(state.phase == "unbuilt" and state.wall_hp == 0 and state.wall_level == 0
		and state._work_kind.is_empty() and state._report_sequence == 0,
		"The expedition scenario starts with a fresh ruined wall ledger.")

	# Isolate a late warning observation so it cannot move the main-map schedule.
	await _test_late_warning_does_not_move_arrival()
	await _test_main_map_expedition()

	_expect(Inventory.items == inventory_before,
		"Wall construction, repairs, and the raid leave Player Inventory unchanged.")
	content.queue_free()
	await get_tree().process_frame
	_restore_clock()
	print("RaidExpeditionTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _assert_approved_profile() -> void:
	var config: Resource = state.config
	var profile: Resource = config.get("party_profile") as Resource
	_expect(bool(config.get("timed_work_enabled"))
		and not bool(config.get("instant_build_enabled"))
		and not bool(config.get("instant_repair_enabled")),
		"The active main-map profile enables timed work and disables instant work.")
	_expect(config.get("build_materials") == {"stone": 10, "wood_log": 5}
		and int(config.get("build_minutes")) == 120,
		"The active build profile costs 10 stone and 5 wood log for 120 minutes.")
	_expect(config.get("repair_materials_per_step") == {"stone": 1}
		and int(config.get("repair_hp_per_step")) == 5
		and int(config.get("repair_minutes")) == 60,
		"The active repair profile costs one stone per five HP for 60 minutes.")
	_expect(bool(config.get("raids_enabled")) and is_instance_valid(profile)
		and str(profile.get("display_name")).to_lower().contains("normal")
		and int(profile.get("travel_days")) == 3
		and int(profile.get("attack_min")) == 5
		and int(profile.get("attack_max")) == 7
		and int(config.get("warning_days")) == 1
		and int(config.get("wall_defend")) == 2
		and int(config.get("recovery_days")) == 3,
		"The live profile uses the approved normal three-day party, one-day warning, 5–7 attack, 2 defend, and three-day recovery.")

func _test_main_map_expedition() -> void:
	var base_minute: int = _clock_minute()
	storage.items = {"stone": 9, "wood_log": 5}
	var short_stock: Dictionary = storage.items.duplicate(true)
	var quote: Dictionary = state.get_work_quote()
	_expect(quote.kind == "build" and quote.materials == {"stone": 10, "wood_log": 5}
		and int(quote.duration_minutes) == 120 and not quote.can_start,
		"The live City Storage shortage is reflected in the build quote.")
	_expect(not state.request_wall_work(quote) and storage.items == short_stock
		and state._work_kind.is_empty(),
		"Insufficient City Storage rejects paid construction without charging or starting work.")

	var greeting: BaseGameDialogueBalloon = await _open_wall_greeting()
	if is_instance_valid(greeting):
		_expect(greeting.dialogue_line.text.contains("City Storage is short"),
			"Iddin-Sin explains that City Storage is short on the main-map quote.")
		await _show_responses(greeting)
		var responses: Array[String] = _visible_responses(greeting)
		_expect(responses.size() == 1 and responses.has("Not now"),
			"The live caretaker does not offer unaffordable paid construction.")
		_choose_response(greeting, "Not now")
		await _wait_for_greeting_end()
	_expect(storage.items == short_stock and state._work_kind.is_empty(),
		"Declining an unaffordable wall quote preserves the exact City Storage stock.")

	storage.items.clear()
	var debug_overlay: Node = content.get_node("TimeDebugOverlay")
	var inventory_before_debug_supply: Dictionary = Inventory.items.duplicate(true)
	_expect(bool(debug_overlay.call("give_wall_materials"))
		and storage.items == quote.materials,
		"The explicit debug wall-material action adds exactly the current quote to City Storage.")
	_expect(Inventory.items == inventory_before_debug_supply,
		"Debug wall materials go to City Storage without changing Player Inventory.")
	var topped_up_stock: Dictionary = storage.items.duplicate(true)
	_expect(not bool(debug_overlay.call("give_wall_materials")) and storage.items == topped_up_stock,
		"Repeating debug wall-material supply returns false and adds no extra stock.")
	get_tree().paused = true
	var paused_supply_result: bool = bool(debug_overlay.call("give_wall_materials"))
	get_tree().paused = false
	_expect(not paused_supply_result and storage.items == topped_up_stock,
		"The debug wall-material action rejects while paused without changing City Storage.")

	greeting = await _open_wall_greeting()
	if is_instance_valid(greeting):
		var quoted_text: String = greeting.dialogue_line.text
		_expect(quoted_text.contains("120 min") and quoted_text.contains("10 Stone")
			and quoted_text.contains("5 Wood Log") and quoted_text.contains("City Storage"),
			"Iddin-Sin's native dialogue quotes the build duration and named materials.")
		await _show_responses(greeting)
		var responses: Array[String] = _visible_responses(greeting)
		_expect(responses.has("Start wall work") and responses.has("Not now"),
			"The live caretaker offers the paid Start wall work choice when stock is sufficient.")
		_choose_response(greeting, "Start wall work")
		await _wait_for_greeting_end()
	_expect(state._work_kind == "build" and state._work_remaining == 120
		and state.wall_hp == 0 and state.wall_level == 0,
		"Choosing Start wall work starts a pending build while the ruined wall still has zero HP.")
	_expect(storage.items.is_empty(),
		"Starting main-map construction consumes exactly the quoted stone and wood log once.")
	await _reload_main_map_during_build()

	_set_clock_minute(base_minute + 119)
	_expect(state._work_remaining == 1 and state.wall_hp == 0,
		"The main-map build stays pending one minute before completion.")
	_set_clock_minute(base_minute + 30)
	_set_clock_minute(base_minute + 119)
	_expect(state._work_remaining == 1 and state.wall_hp == 0,
		"Rewinding the world clock and returning below its high-water minute does not repeat work time.")
	_set_clock_minute(base_minute + 120)
	var build_complete_at: int = base_minute + 120
	_expect(state._work_kind.is_empty() and state._work_remaining == 0
		and state.wall_hp == 50 and state.wall_level == 1,
		"The paid main-map build completes at 120 minutes and restores the wall to 50 HP.")
	_expect(state.phase == "safe" and state._departure_at == build_complete_at
		and state._attack_at == build_complete_at + 3 * MINUTES_PER_DAY,
		"The first party departure is the build completion time and arrival is three travel days later.")
	_expect(_wall_cells_use_source(1),
		"The main-map bootstrap paints the built wall tile source after paid construction completes.")
	_set_clock_minute(build_complete_at)
	_expect(state.wall_hp == 50 and state._attack_at == build_complete_at + 3 * MINUTES_PER_DAY,
		"Repeating the completion timestamp does not complete or schedule the first build twice.")

	# Stage one damaged wall step to exercise the configured repair quote through Iddin-Sin.
	state.wall_hp = 45
	state.changed.emit()
	storage.items = {"stone": 1}
	greeting = await _open_wall_greeting()
	if is_instance_valid(greeting):
		var repair_text: String = greeting.dialogue_line.text
		_expect(repair_text.contains("60 min") and repair_text.contains("1 Stone"),
			"Iddin-Sin's live repair quote uses one stone for a five-HP repair and 60 minutes.")
		await _show_responses(greeting)
		var responses: Array[String] = _visible_responses(greeting)
		_expect(responses.has("Start wall work"),
			"The live caretaker offers a paid repair while City Storage has the quoted stone.")
		_choose_response(greeting, "Start wall work")
		await _wait_for_greeting_end()
	var repair_started_at: int = _clock_minute()
	_expect(state._work_kind == "repair" and state._work_remaining == 60
		and state.wall_hp == 45 and storage.items.is_empty(),
		"Starting the native repair choice consumes its stone and leaves HP unchanged until work finishes.")
	_set_clock_minute(repair_started_at + 60)
	_expect(state._work_kind.is_empty() and state.wall_hp == 50
		and state._attack_at == build_complete_at + 3 * MINUTES_PER_DAY,
		"Paid repair restores five HP without moving the party's already-scheduled arrival.")

	var arrival_at: int = build_complete_at + 3 * MINUTES_PER_DAY
	_set_clock_minute(arrival_at - MINUTES_PER_DAY - 1)
	_expect(state.phase == "safe" and not ui.raid_notice.visible,
		"The raid remains hidden and safe one minute before the one-day warning window.")
	_set_clock_minute(arrival_at - MINUTES_PER_DAY)
	_expect(state.phase == "warning" and ui.raid_notice.visible
		and ui.raid_notice.text.to_lower().contains("raid"),
		"The warning phase and raid notice appear exactly one day before scheduled arrival.")

	greeting = await _open_wall_greeting()
	if is_instance_valid(greeting):
		var warning_line: String = greeting.dialogue_line.text
		_expect(warning_line.contains("Raider tracks") and warning_line.contains("nearby"),
			"Iddin-Sin speaks the warning from the native dialogue before work details.")
		await _advance_to_work_summary(greeting)
		_expect(greeting.dialogue_line.text.to_lower().contains("good condition"),
			"The caretaker follows the warning with the current wall-work summary.")
		await _show_responses(greeting)
		var responses: Array[String] = _visible_responses(greeting)
		_expect(responses.size() == 1 and responses.has("Not now"),
			"A full wall does not offer a repair action during the warning.")
		_choose_response(greeting, "Not now")
		await _wait_for_greeting_end()

	storage.items = {"stone": 4}
	_set_clock_minute(arrival_at - 2)
	var time_debug: Node = content.get_node("TimeDebugOverlay")
	time_debug.set_process(false)
	time_debug.set_speed(60)
	time_debug.step_minutes(180)
	_expect(_clock_minute() == arrival_at and time_debug.get_effective_speed() == 1,
		"A debug jump stops at raid arrival instead of skipping through combat.")
	_expect(state.phase == "attacking" and ui.attack_warning.visible
		and not ui.raid_notice.visible,
		"The party starts its automatic attack at the original scheduled arrival minute.")
	_expect(state._attack_strength >= 5 and state._attack_strength <= 7
		and int(state.config.get("wall_defend")) == 2,
		"The live main-map attack rolls 5–7 strength against the configured defend value of 2.")
	state.advance_attack(float(state.config.get("duration_seconds")))
	var report: Dictionary = state.get_last_report()
	_expect(state.phase == "recovery" and report.has("id"),
		"Finishing the automatic main-map attack records a report and enters recovery.")
	_expect(report.get("stolen", {}).is_empty() and storage.items == {"stone": 4}
		and int(state.config.get("theft_capacity")) == 0,
		"The approved main-map profile causes no random storage loot loss.")
	_expect(state._departure_at == arrival_at + 3 * MINUTES_PER_DAY
		and state._attack_at == arrival_at + 6 * MINUTES_PER_DAY,
		"After the attack, the next party departs after three recovery days and arrives three travel days later.")

	_expect(time_debug.get_effective_speed() == 60, "Scheduled raid completion restores the selected speed.")
	# Exercise arrival within the accelerated-minute loop as well as manual jumps.
	state.wall_hp = 50
	_set_clock_minute(state._attack_at - 2)
	time_debug._process(1.0)
	var second_arrival: int = state._attack_at
	_expect(_clock_minute() == second_arrival and state.phase == "attacking",
		"Accelerated processing stops adding minutes as soon as the next raid arrives.")
	state.wall_hp = 1
	state.advance_attack(5.0)
	_expect(state.get_last_report().outcome == "breached" and time_debug.get_effective_speed() == 60,
		"A breached raid also restores the previous speed.")
	time_debug._process(1.0)
	_expect(_clock_minute() == second_arrival + 59,
		"Resumed acceleration adds only the new frame's minutes, without leftover pre-raid time.")
	time_debug.set_speed(1)

func _test_late_warning_does_not_move_arrival() -> void:
	var fixture_storage: Node = CITY_STORAGE_SCRIPT.new()
	fixture_storage.name = "ExpeditionScheduleFixtureStorage"
	add_child(fixture_storage)
	fixture_storage.items = {"stone": 10, "wood_log": 5}
	var fixture: Node = RAID_STATE_SCRIPT.new()
	fixture.name = "ExpeditionScheduleFixture"
	fixture.config = state.config.duplicate(true)
	fixture.storage = fixture_storage
	add_child(fixture)
	await get_tree().process_frame
	var start_at: int = _clock_minute()
	var quote: Dictionary = fixture.get_work_quote()
	_expect(quote.can_start and fixture.request_wall_work(quote),
		"An isolated ledger can start construction using the active main-map profile.")
	_notify_ledger_at(fixture, start_at + 120)
	var arrival_at: int = start_at + 120 + 3 * MINUTES_PER_DAY
	_expect(fixture._attack_at == arrival_at,
		"The isolated ledger schedules arrival three days after construction completion.")
	_notify_ledger_at(fixture, arrival_at - MINUTES_PER_DAY + 120)
	_expect(fixture.phase == "warning" and fixture._attack_at == arrival_at,
		"Detecting the warning two hours after its threshold leaves the party's arrival unchanged.")
	_notify_ledger_at(fixture, arrival_at)
	_expect(fixture.phase == "attacking" and fixture._attack_at == arrival_at,
		"A late warning still transitions into an attack at the original arrival time.")
	_disconnect_and_free_fixture(fixture, fixture_storage)

func _reload_main_map_during_build() -> void:
	var original_state: Node = state
	var original_storage: Node = storage
	content.queue_free()
	await get_tree().process_frame
	content = CONTENT_SCENE.instantiate()
	add_child(content)
	await _settle_physics()
	player = content.get_node("YSortWorld/Player") as Player
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	wall_spot = content.get_node("YSortWorld/WallManagementSpot") as Node2D
	wall_map = content.get_node("YSortWorld/WallStone") as TileMapLayer
	state = content.get_node("RaidBootstrap").state
	ui = state.get_node("RaidUI") as RaidUI
	storage = WorkStateRuntime.get_node_or_null("CityToolStorage")
	_expect(state == original_state and storage == original_storage
		and state.storage == storage and state.get_child_count() == 1,
		"Reentering the main map reuses one hosted raid ledger, HUD, and City Storage provider.")
	_expect(state._work_kind == "build" and state._work_remaining == 120
		and state.wall_hp == 0 and wall_map.get_used_cells().size() > 0,
		"The pending paid build survives a main-map reload without granting premature wall HP.")

func _open_wall_greeting() -> BaseGameDialogueBalloon:
	player.global_position = wall_spot.global_position + Vector2(0, 15)
	await _settle_physics()
	player._refresh_current_interactable()
	await get_tree().process_frame
	var interact_event := InputEventAction.new()
	interact_event.action = &"interact"
	interact_event.pressed = true
	player._unhandled_input(interact_event)
	var deadline: int = Time.get_ticks_msec() + 5000
	while not bool(wall_spot.call("_has_live_greeting_balloon")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var balloon: BaseGameDialogueBalloon = wall_spot.get("greeting_balloon") as BaseGameDialogueBalloon
	while is_instance_valid(balloon) and not is_instance_valid(balloon.dialogue_line) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(is_instance_valid(balloon) and is_instance_valid(balloon.dialogue_line),
		"E opens Iddin-Sin's native wall dialogue from the live main map.")
	if not is_instance_valid(balloon) or not is_instance_valid(balloon.dialogue_line):
		return null
	if balloon.dialogue_label.is_typing:
		balloon.dialogue_label.skip_typing()
	while is_instance_valid(balloon) and not balloon.is_waiting_for_input and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(not get_tree().paused and not TimeComponentManager.is_paused and not player.can_move,
		"Iddin-Sin's native dialogue locks Player movement without pausing world time.")
	return balloon

func _show_responses(balloon: BaseGameDialogueBalloon) -> void:
	if not is_instance_valid(balloon):
		return
	if balloon.dialogue_label.is_typing:
		balloon.dialogue_label.skip_typing()
	balloon.show_responses()
	await get_tree().process_frame

func _visible_responses(balloon: BaseGameDialogueBalloon) -> Array[String]:
	var texts: Array[String] = []
	if not is_instance_valid(balloon) or not balloon.responses_menu.visible:
		return texts
	for item: Control in balloon.responses_menu.get_menu_items():
		var response: DialogueResponse = item.get_meta("response") as DialogueResponse
		if is_instance_valid(response):
			texts.append(response.text.strip_edges())
	return texts

func _choose_response(balloon: BaseGameDialogueBalloon, response_text: String) -> void:
	if not is_instance_valid(balloon):
		_expect(false, "A live Iddin-Sin dialogue exists before choosing a response.")
		return
	if not balloon.responses_menu.visible:
		balloon.show_responses()
	var response_button: Control
	for item: Control in balloon.responses_menu.get_menu_items():
		var response: DialogueResponse = item.get_meta("response") as DialogueResponse
		if is_instance_valid(response) and response.text.strip_edges() == response_text:
			response_button = item
	_expect(is_instance_valid(response_button),
		"Iddin-Sin's native dialogue exposes the %s response." % response_text)
	if not is_instance_valid(response_button):
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	response_button.gui_input.emit(click)

func _advance_to_work_summary(balloon: BaseGameDialogueBalloon) -> void:
	if not is_instance_valid(balloon):
		return
	var warning_line: DialogueLine = balloon.dialogue_line
	if balloon.dialogue_label.is_typing:
		balloon.dialogue_label.skip_typing()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	balloon._on_balloon_gui_input(click)
	var deadline: int = Time.get_ticks_msec() + 5000
	while is_instance_valid(balloon) and balloon.dialogue_line == warning_line and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	while is_instance_valid(balloon) and not balloon.is_waiting_for_input and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(is_instance_valid(balloon) and balloon.dialogue_line != warning_line,
		"The native caretaker dialogue advances from its warning line to wall-work details.")

func _wait_for_greeting_end() -> void:
	var deadline: int = Time.get_ticks_msec() + 5000
	while (bool(wall_spot.call("_has_live_greeting_balloon")) or not player.can_move or TimeComponentManager.is_paused) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(not bool(wall_spot.call("_has_live_greeting_balloon")) and player.can_move
		and not get_tree().paused and not TimeComponentManager.is_paused,
		"Ending Iddin-Sin's dialogue releases Player movement and leaves world time running.")

func _settle_physics() -> void:
	for frame: int in range(5):
		await get_tree().physics_frame

func _wall_cells_use_source(expected_source: int) -> bool:
	for cell: Vector2i in wall_map.get_used_cells():
		if wall_map.get_cell_source_id(cell) != expected_source:
			return false
	return not wall_map.get_used_cells().is_empty()

func _clock_minute() -> int:
	return TimeComponentManager.current_day * MINUTES_PER_DAY \
		+ TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute

func _set_clock_minute(total_minutes: int) -> void:
	TimeComponentManager.current_day = floori(float(total_minutes) / float(MINUTES_PER_DAY))
	var minute_of_day: int = posmod(total_minutes, MINUTES_PER_DAY)
	TimeComponentManager.current_hour = minute_of_day / 60
	TimeComponentManager.current_minute = minute_of_day % 60
	TimeComponentManager.emit_time_signal()

func _notify_ledger_at(ledger: Node, total_minutes: int) -> void:
	var day: int = floori(float(total_minutes) / float(MINUTES_PER_DAY))
	var minute_of_day: int = posmod(total_minutes, MINUTES_PER_DAY)
	ledger._on_time_changed(day, minute_of_day / 60, minute_of_day % 60, "clear")

func _disconnect_and_free_fixture(fixture: Node, fixture_storage: Node) -> void:
	var callback: Callable = Callable(fixture, "_on_time_changed")
	if TimeComponentManager.time_changed.is_connected(callback):
		TimeComponentManager.time_changed.disconnect(callback)
	fixture.free()
	fixture_storage.free()

func _snapshot_globals() -> void:
	clock_before = {
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"weather": TimeComponentManager.current_weather
	}
	clock_processing_before = TimeComponentManager.is_processing()
	clock_paused_before = TimeComponentManager.is_paused

func _restore_clock() -> void:
	TimeComponentManager.current_day = int(clock_before.day)
	TimeComponentManager.current_hour = int(clock_before.hour)
	TimeComponentManager.current_minute = int(clock_before.minute)
	TimeComponentManager.current_weather = str(clock_before.weather)
	TimeComponentManager.is_paused = clock_paused_before
	TimeComponentManager.set_process(clock_processing_before)
