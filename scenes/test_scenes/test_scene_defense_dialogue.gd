extends "res://scenes/test_scenes/test_scene_raid_expedition.gd"

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	await load_content()
	storage.items = {"stone": 100, "wood_log": 100}
	_expect(state.request_wall_work(state.get_work_quote()), "Build starts via the shared work ledger.")
	_set_clock_minute(_clock_minute() + 120)
	var arrival: int = state._attack_at
	await _open_wall_greeting()
	await _show_responses(wall_spot.greeting_balloon)
	await choose("Improve")
	_expect(_visible_responses(wall_spot.greeting_balloon).has("Wall Lv. 2") and _visible_responses(wall_spot.greeting_balloon).has("Watchtower"), "Improve offers the two independent defense projects.")
	await choose("Wall Lv. 2")
	var text: String = wall_spot.greeting_balloon.dialogue_line.text
	_expect(text.contains("80 HP") and text.contains("DEF 3") and text.contains("20 Stone") and text.contains("10 Wood") and text.contains("4h"), "Upgrade presents its actual benefits, cost and duration before confirmation.")
	_expect(wall_spot.greeting_balloon.dialogue_label.get_content_height() <= wall_spot.greeting_balloon.dialogue_label.size.y + 1.0, "Upgrade quote fits the existing dialogue text box.")
	await capture_defense("wall-upgrade-quote.png")
	var stock_before: Dictionary = storage.items.duplicate(true)
	await choose("Back")
	_expect(state._work_kind.is_empty() and storage.items == stock_before, "Back from a quote spends nothing.")
	await choose("Wall Lv. 2")
	_choose_response(wall_spot.greeting_balloon, "Start")
	await _wait_for_greeting_end()
	_expect(state._work_kind == "upgrade" and state.wall_level == 1, "Native Start begins the upgrade without granting its benefits immediately.")
	_set_clock_minute(_clock_minute() + 120)
	var ledger: Node = state
	content.queue_free()
	await get_tree().process_frame
	await load_content()
	_expect(state == ledger and state._work_kind == "upgrade" and state._work_remaining == 120, "Upgrade work survives a main-map reload.")
	_set_clock_minute(_clock_minute() + 120)
	_expect(state.wall_level == 2 and state.wall_hp == 80 and state._attack_at == arrival, "Native upgrade completes without changing the party schedule.")
	await _open_wall_greeting()
	await _show_responses(wall_spot.greeting_balloon)
	await choose("Improve")
	_expect(not _visible_responses(wall_spot.greeting_balloon).has("Wall Lv. 2"), "Completed level upgrade is not offered again.")
	await choose("Watchtower")
	text = wall_spot.greeting_balloon.dialogue_line.text
	_expect(text.contains("2 days") and text.contains("Inspect") and text.contains("10 Stone") and text.contains("10 Wood") and text.contains("3h"), "Tower quote shows detection, Inspect, cost and duration.")
	_expect(wall_spot.greeting_balloon.dialogue_label.get_content_height() <= wall_spot.greeting_balloon.dialogue_label.size.y + 1.0, "Tower quote fits the dialogue text box.")
	await capture_defense("watchtower-quote.png")
	_choose_response(wall_spot.greeting_balloon, "Start")
	await _wait_for_greeting_end()
	_expect(state._work_kind == "watchtower" and not state.watchtower_built, "Watchtower is a timed project selected through the caretaker.")
	_set_clock_minute(_clock_minute() + 180)
	_expect(state.watchtower_built and state.inspect_raiders().is_empty(), "Tower completion does not reveal an undetected party.")
	_set_clock_minute(arrival - 2880)
	_expect(state.phase == "warning" and state.inspect_raiders().type == "Normal raiders", "The actual map now detects and identifies the normal party two days early.")
	ui.open_details()
	ui.inspect_button.pressed.emit()
	_expect(ui.watchtower_status_label.text.contains("Normal raiders") and ui.travel_progress.visible, "Inspect uses the live normal-party data beside the travel bar.")
	await capture_defense("watchtower-inspect.png")
	ui.close_details()
	_expect(content.get_node("RaidBootstrap/WatchtowerVisual").visible, "Completed watchtower is visible on the actual wall.")
	await capture_defense("watchtower-world.png")

	await _open_wall_greeting()
	await _advance_to_work_summary(wall_spot.greeting_balloon)
	await _show_responses(wall_spot.greeting_balloon)
	_expect(not _visible_responses(wall_spot.greeting_balloon).has("Improve"), "Both completed improvements disappear from the project menu.")
	_choose_response(wall_spot.greeting_balloon, "Not now")
	await _wait_for_greeting_end()
	content.queue_free()
	await get_tree().process_frame
	_restore_clock()
	print("DefenseDialogueTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func load_content() -> void:
	content = CONTENT_SCENE.instantiate()
	add_child(content)
	await _settle_physics()
	player = content.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	wall_spot = content.get_node("YSortWorld/WallManagementSpot")
	wall_map = content.get_node("YSortWorld/WallStone")
	state = content.get_node("RaidBootstrap").state
	ui = state.get_node("RaidUI")
	storage = state.storage

func choose(text: String) -> void:
	var balloon: BaseGameDialogueBalloon = wall_spot.greeting_balloon
	var old_id: String = balloon.dialogue_line.id
	_choose_response(balloon, text)
	var deadline: int = Time.get_ticks_msec() + 4000
	while balloon.dialogue_line.id == old_id and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	for frame in range(3):
		await get_tree().process_frame
	await _show_responses(balloon)

func capture_defense(file_name: String) -> void:
	var folder: String = OS.get_environment("TIP_RAID_CAPTURE_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	for frame in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(file_name))
