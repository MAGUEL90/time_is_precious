extends Node

var failures: int = 0
var content: Node
var state: Node
var ui: CanvasLayer
var debug: CanvasLayer
var player: Player
var wall_spot: Node2D
var wall_map: TileMapLayer

func _ready() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _load_map() -> void:
	content = preload("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	player = content.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	wall_spot = content.get_node("YSortWorld/WallManagementSpot")
	wall_map = content.get_node("YSortWorld/WallStone")
	state = content.get_node("RaidBootstrap").state
	# This scene checks the original free caretaker dialogue flow; timed costs and raid scheduling have a separate synthetic test.
	state.config.timed_work_enabled = false
	state.config.ranked_looting_enabled = false
	state.config.satisfaction_penalty = 0.0
	state.config.instant_build_enabled = true
	state.config.instant_repair_enabled = true
	state.config.raids_enabled = false
	state.config.party_profile = null
	ui = state.get_node("RaidUI")
	debug = content.get_node("TimeDebugOverlay")

func _move_to_wall_spot() -> void:
	player.global_position = wall_spot.global_position + Vector2(0, 15)
	await _settle_physics()
	player._refresh_current_interactable()
	await get_tree().process_frame

func _get_greeting_balloon() -> BaseGameDialogueBalloon:
	return wall_spot.get("greeting_balloon") as BaseGameDialogueBalloon

func _open_wall_greeting() -> BaseGameDialogueBalloon:
	await _move_to_wall_spot()
	var interact_event := InputEventAction.new()
	interact_event.action = &"interact"
	interact_event.pressed = true
	player._unhandled_input(interact_event)
	var deadline: int = Time.get_ticks_msec() + 5000
	while not bool(wall_spot.call("_has_live_greeting_balloon")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var balloon: BaseGameDialogueBalloon = _get_greeting_balloon()
	while is_instance_valid(balloon) and not is_instance_valid(balloon.dialogue_line) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(is_instance_valid(balloon) and is_instance_valid(balloon.dialogue_line), "E opens the native wall caretaker dialogue.")
	if not is_instance_valid(balloon) or not is_instance_valid(balloon.dialogue_line):
		return null
	if balloon.dialogue_label.is_typing:
		balloon.dialogue_label.skip_typing()
	while is_instance_valid(balloon) and not balloon.is_waiting_for_input and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(not get_tree().paused and not TimeComponentManager.is_paused and not player.can_move,
		"Wall dialogue holds Player movement without pausing the world clock.")
	return balloon

func _show_wall_responses(balloon: BaseGameDialogueBalloon) -> void:
	if not is_instance_valid(balloon):
		return
	var expected_opener: String = "Good to see you. Shall we look at the city's defences?"
	var active_raid: bool = bool(wall_spot.call("wall_is_attacking"))
	if active_raid:
		expected_opener = "The raiders are still here. We can repair the wall once they leave."
	elif bool(wall_spot.call("wall_has_warning")):
		expected_opener = "Raider tracks have been spotted nearby. They are nearing the castle. Prepare the wall."
	_expect(balloon.dialogue_line.text == expected_opener,
		"Iddin-Sin opens with the appropriate safe, warning, or attack line.")
	if not active_raid:
		await _advance_wall_opener_to_work(balloon)
	if balloon.dialogue_label.is_typing:
		balloon.dialogue_label.skip_typing()
	balloon.show_responses()
	await get_tree().process_frame

func _advance_wall_opener_to_work(balloon: BaseGameDialogueBalloon) -> void:
	var opening_line: DialogueLine = balloon.dialogue_line
	if balloon.dialogue_label.is_typing:
		balloon.dialogue_label.skip_typing()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	balloon._on_balloon_gui_input(click)
	var deadline: int = Time.get_ticks_msec() + 5000
	while is_instance_valid(balloon) and balloon.dialogue_line == opening_line and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	while is_instance_valid(balloon) and not balloon.is_waiting_for_input and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(is_instance_valid(balloon) and balloon.dialogue_line != opening_line,
		"The native wall dialogue advances from its opener to the existing work summary.")

func _visible_wall_responses(balloon: BaseGameDialogueBalloon) -> Array[String]:
	var texts: Array[String] = []
	if not is_instance_valid(balloon) or not balloon.responses_menu.visible:
		return texts
	for item: Control in balloon.responses_menu.get_menu_items():
		var response: DialogueResponse = item.get_meta("response") as DialogueResponse
		if is_instance_valid(response):
			texts.append(response.text.strip_edges())
	return texts

func _choose_wall_response(balloon: BaseGameDialogueBalloon, response_text: String) -> void:
	if not is_instance_valid(balloon):
		_expect(false, "A live wall greeting exists before response selection.")
		return
	if not balloon.responses_menu.visible:
		balloon.show_responses()
	var response_button: Control
	for item: Control in balloon.responses_menu.get_menu_items():
		var response: DialogueResponse = item.get_meta("response") as DialogueResponse
		if is_instance_valid(response) and response.text.strip_edges() == response_text:
			response_button = item
	_expect(is_instance_valid(response_button), "Wall greeting exposes the %s response." % response_text)
	if not is_instance_valid(response_button):
		return
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	response_button.gui_input.emit(click)

func _wait_for_wall_greeting_end() -> void:
	var deadline: int = Time.get_ticks_msec() + 5000
	while (bool(wall_spot.call("_has_live_greeting_balloon")) or not player.can_move or TimeComponentManager.is_paused) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(not bool(wall_spot.call("_has_live_greeting_balloon")), "Wall dialogue ends or cancels cleanly.")
	_expect(player.can_move and not get_tree().paused and not TimeComponentManager.is_paused,
		"Ending wall dialogue releases its Player movement lock without pausing time.")

func _settle_physics() -> void:
	for frame: int in range(5):
		await get_tree().physics_frame

func _wall_atlas_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for cell: Vector2i in wall_map.get_used_cells():
		snapshot[cell] = wall_map.get_cell_atlas_coords(cell)
	return snapshot

func _expect_wall_visual(source_id: int, atlas_snapshot: Dictionary, message: String) -> void:
	var current_cells: Array[Vector2i] = wall_map.get_used_cells()
	_expect(current_cells.size() == atlas_snapshot.size(), "%s (same tile count)" % message)
	for cell: Vector2i in atlas_snapshot:
		_expect(current_cells.has(cell), "%s (cell %s remains)" % [message, cell])
		_expect(wall_map.get_cell_source_id(cell) == source_id, "%s (cell %s source)" % [message, cell])
		_expect(wall_map.get_cell_atlas_coords(cell) == atlas_snapshot[cell], "%s (cell %s atlas)" % [message, cell])

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	_load_map()
	await _settle_physics()
	var wall_atlas: Dictionary = _wall_atlas_snapshot()
	debug.panel.show()
	debug._refresh_controls()
	_expect(debug.raid_journey_button.disabled, "Raid debug controls require a built wall.")
	_expect(not state.start_debug_raid(false), "A direct debug request cannot bypass initial construction.")

	# Details stays read-only. Build through the selected caretaker's real dialogue.
	ui.open_details()
	await get_tree().process_frame
	_expect(ui.details_panel.visible and not ui.build_button.visible, "Read-only Details does not offer wall construction.")
	ui.build_button.pressed.emit()
	await get_tree().process_frame
	_expect(state.wall_hp == 0 and state.wall_level == 0, "A forced Details Build signal cannot construct the wall.")
	ui.close_details()
	var greeting: BaseGameDialogueBalloon = await _open_wall_greeting()
	_expect(player.current_interactable == wall_spot, "The wall spot is selected when Player enters its range.")
	_expect(greeting.dialogue_line.text == "Good to see you. Shall we look at the city's defences?", "The caretaker starts with the approved English greeting.")
	await _show_wall_responses(greeting)
	var response_texts: Array[String] = _visible_wall_responses(greeting)
	_expect(response_texts.size() == 2 and response_texts.has("Repair wall (free)") and response_texts.has("Not now"),
		"A ruined wall offers free construction or declining.")
	_choose_wall_response(greeting, "Repair wall (free)")
	await _wait_for_wall_greeting_end()
	debug._refresh_controls()
	_expect(state.wall_hp == 50 and state.wall_level == 1, "Initial wall construction follows the real caretaker dialogue response.")
	_expect_wall_visual(1, wall_atlas, "Building changes every existing wall cell to the intact tile source while preserving coordinates")
	_expect(debug.raid_journey_button.disabled, "The legacy free fixture does not expose a normal-party debug journey.")
	_expect(not ui.build_button.visible and not ui.repair_button.visible, "Details stays read-only after initial construction.")

	# A full wall has no work response, even though the player can still talk to the caretaker.
	greeting = await _open_wall_greeting()
	await _show_wall_responses(greeting)
	response_texts = _visible_wall_responses(greeting)
	_expect(response_texts.size() == 1 and response_texts[0] == "Not now", "Full HP does not offer a repair response.")
	_choose_wall_response(greeting, "Not now")
	await _wait_for_wall_greeting_end()
	_expect(state.wall_hp == 50, "Declining at full HP leaves the wall unchanged.")

	_expect(state.config.instant_repair_enabled, "The wall playtest profile enables the requested free repair action.")
	var config_before: Resource = state.config.duplicate(true)
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	debug.set_speed(60)
	debug.panel.hide()
	state.start_debug_raid(false)
	_expect(state.phase == "attacking" and not debug.panel.visible and not ui.details_panel.visible, "Starting the real debug action focuses the live HP bar.")
	_expect(not state.start_debug_raid(true), "A second debug click cannot replace an active attack.")
	var attack_was_processing: bool = state.is_processing()
	state.set_process(false)
	var hp_before_attack_dialogue: int = state.wall_hp
	var elapsed_before_attack_dialogue: float = state._elapsed
	greeting = await _open_wall_greeting()
	await _show_wall_responses(greeting)
	response_texts = _visible_wall_responses(greeting)
	_expect(response_texts.size() == 1 and response_texts[0] == "Not now", "An active raid does not offer wall work.")
	_choose_wall_response(greeting, "Not now")
	await _wait_for_wall_greeting_end()
	_expect(state.phase == "attacking" and not state.can_repair_wall()
		and state.wall_hp == hp_before_attack_dialogue and state._elapsed == elapsed_before_attack_dialogue,
		"Declining during an attack leaves raid and wall state unchanged.")
	state.set_process(attack_was_processing)
	if OS.get_environment("TIP_RAID_REALTIME_TEST") == "1":
		TimeComponentManager.is_paused = true
		var before_pause: float = state._elapsed
		await get_tree().create_timer(0.2).timeout
		_expect(state._elapsed == before_pause, "Clock pause freezes a real running attack.")
		TimeComponentManager.is_paused = false
		await get_tree().create_timer(5.1).timeout
		state.set_process(false)
		_expect(state._elapsed >= 5.0 and state._elapsed < 10.0, "Real gameplay processing reaches the first five-second hit.")
	else:
		state.set_process(false)
		state.advance_attack(5.0)
	_expect(state.wall_hp == 47 and ui.hp_bar.value == 47, "One live-state hit updates the real main-map HP bar.")
	await _capture("raid-playtest-first-hit.png")
	var elapsed: float = state._elapsed
	var clock_before: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	debug._process(1.0)
	debug.step_minutes(1440)
	debug.set_speed(10)
	var clock_after: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	_expect(clock_after == clock_before and debug.get_effective_speed() == 1 and debug.speed_multiplier == 60,
		"Active raids block debug acceleration, jumps and speed changes while preserving the previous selection.")
	_expect(debug.speed_buttons[0].button_pressed and debug.speed_buttons[2].disabled and debug.step_buttons[2].disabled,
		"Debug displays the enforced x1 and disables time controls during combat.")
	_expect(state._elapsed == elapsed, "Debug time controls never accelerate real raid seconds.")
	state.advance_attack(55.0)
	_expect(debug.get_effective_speed() == 60, "The selected x60 returns after a surviving raid.")
	debug.set_speed(1)
	_expect(state.phase == "recovery" and state.wall_hp == 14, "The light test survives twelve hits with persistent damage.")
	_expect(ui.details_panel.visible and not ui.repair_button.visible, "The real result report stays read-only until Player reaches the wall.")
	await _capture("raid-playtest-survived.png")
	var report: Dictionary = state.get_last_report()
	var next_attack: int = state._attack_at
	greeting = await _open_wall_greeting()
	await _show_wall_responses(greeting)
	response_texts = _visible_wall_responses(greeting)
	_expect(response_texts.has("Repair wall (free)"), "The caretaker offers repair for a damaged wall.")
	_choose_wall_response(greeting, "Repair wall (free)")
	await _wait_for_wall_greeting_end()
	_expect(state.wall_hp == 50 and state._attack_at == next_attack and state.get_last_report() == report, "Repair restores HP without rerolling threats or results.")
	_expect(not ui.repair_button.visible, "The Details panel stays read-only after repair.")
	_expect(Inventory.items == inventory_before, "Free fixture repair does not spend personal Inventory.")
	_expect(state.config.attack_min == config_before.attack_min and state.config.attack_max == config_before.attack_max and state.config.raids_enabled == config_before.raids_enabled, "Debug raid overrides do not rewrite live raid balance.")
	state.start_debug_raid(true)
	state.set_process(false)
	state.advance_attack(20.0)
	var ledger: Node = state
	content.free()
	await _settle_physics()
	_expect(not ui.details_panel.visible, "Leaving the map during an attack keeps Details closed.")
	var home: Node = preload("res://scenes/player_home_interior/player_home_interior.tscn").instantiate()
	add_child(home)
	await get_tree().process_frame
	_expect(ledger.wall_hp == 30 and ledger.phase == "attacking", "An active raid survives going home.")
	ledger.advance_attack(30.0)
	_expect(ledger.wall_hp == 0 and ledger.get_last_report().hits == 10, "The heavy test breaches at fifty seconds, including while away from the map.")
	_expect(ui.details_panel.visible and not ui.build_button.visible, "The breach report is read-only and does not offer Build away from the wall.")
	await _capture("raid-playtest-breached.png")
	home.free()
	await get_tree().process_frame
	_load_map()
	await _settle_physics()
	_expect(state == ledger and state.get_last_report().outcome == "breached", "Map return retains the exact breach report and ledger.")
	_expect(not ui.build_button.visible, "Map return retains no stale wall management authority.")
	_expect_wall_visual(0, wall_atlas, "A breach changes every existing wall cell to the ruined tile source while preserving coordinates")
	greeting = await _open_wall_greeting()
	await _show_wall_responses(greeting)
	response_texts = _visible_wall_responses(greeting)
	_expect(player.current_interactable == wall_spot and response_texts.has("Repair wall (free)"), "Returning to range offers dialogue-based rebuilding after breach.")
	_choose_wall_response(greeting, "Repair wall (free)")
	await _wait_for_wall_greeting_end()
	_expect(state.wall_hp == 50 and state.wall_level == 1, "Rebuild returns the ruined wall to level 1 without granting an upgrade.")
	_expect_wall_visual(1, wall_atlas, "Rebuilding restores intact tile sources and preserves cell coordinates")
	_expect(not ui.build_button.visible and not ui.repair_button.visible, "The raid report remains read-only after rebuilding.")
	_expect(ui.repair_requested.get_connections().size() == 1, "Map reload does not duplicate repair callbacks.")
	# Debug reset remains useful when gameplay repair is not enabled.
	state.config.instant_repair_enabled = false
	_expect(state.start_debug_raid(false), "A subsequent manual raid can be started after rebuilding.")
	state.set_process(false)
	state.advance_attack(60.0)
	var reset_report: Dictionary = state.get_last_report()
	var reset_schedule: int = state._attack_at
	var damaged_hp: int = state.wall_hp
	greeting = await _open_wall_greeting()
	await _show_wall_responses(greeting)
	response_texts = _visible_wall_responses(greeting)
	_expect(response_texts.size() == 1 and response_texts[0] == "Not now", "Disabling instant repair removes the work response from dialogue.")
	_choose_wall_response(greeting, "Not now")
	await _wait_for_wall_greeting_end()
	_expect(state.wall_hp == damaged_hp and not ui.repair_button.visible, "Declining with gameplay repair disabled preserves damage and read-only Details.")
	get_tree().paused = true
	_expect(not debug.reset_wall_test(), "Debug reset respects another system's pause.")
	get_tree().paused = false
	debug.raid_reset_button.pressed.emit()
	_expect(state.wall_hp == 50 and not state.config.instant_repair_enabled, "Explicit debug reset restores HP without enabling free gameplay repair.")
	_expect(state.get_last_report() == reset_report and state._attack_at == reset_schedule, "Debug reset preserves raid results and schedule.")
	ui.close_details()
	debug.panel.show()
	debug._refresh_controls()
	var scroll: ScrollContainer = debug.panel.get_child(0)
	scroll.scroll_vertical = 0
	await get_tree().process_frame
	await _capture("raid-playtest-debug.png")
	content.free()
	print("RaidPlaytestTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _capture(file_name: String) -> void:
	var folder: String = OS.get_environment("TIP_RAID_CAPTURE_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(file_name))
