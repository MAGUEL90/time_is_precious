extends "res://scenes/test_scenes/test_scene_defense_dialogue.gd"

func _run() -> void:
	_snapshot_globals()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	await load_content()
	var city: Node = WorkStateRuntime.get_node("CityProgression")
	_expect(city.level == 1 and city.progress == 0, "A new city starts at level 1 with zero progress.")
	storage.items = {"stone": 100, "wood_log": 100}
	_expect(state.request_wall_work(state.get_work_quote()), "Wall construction starts with actual materials.")
	var results: Array[Dictionary] = [{"food": true, "clothing": true, "satisfaction": 0.8}]
	for day: int in range(1, 11):
		city.settle_day(city.last_awarded_day + 1, results, false)
	_expect(city.progress == 100 and city.level == 1, "Progress caps at100 and waits for an explicit Level Up.")
	ui.open_details()
	await capture_defense("city-progress-ready.png")
	ui.city_level_up_button.pressed.emit()
	_expect(city.level == 2 and city.progress == 0 and state._composition_stage == &"developing", "The City Hub button advances one level and future raiders.")
	ui.city_level_up_button.pressed.emit()
	_expect(city.level == 2, "Repeated button activation cannot buy another level.")
	city.settle_day(city.last_awarded_day + 1, results, false)
	ui._select_hub_tab(true)
	await capture_defense("city-progress-supply.png")
	var old_city_id: int = city.get_instance_id()
	var old_ui_id: int = ui.get_instance_id()
	content.queue_free()
	await get_tree().process_frame
	await load_content()
	_expect(WorkStateRuntime.get_node("CityProgression").get_instance_id() == old_city_id and ui.get_instance_id() == old_ui_id,
		"Map reload reuses the progression ledger and City Hub.")
	_expect(city.level == 2 and city.progress == 10, "Map reload neither resets nor grants progress.")
	_expect(city.changed.get_connections().size() == 1, "Reload does not duplicate the UI progress subscription.")
	# A full wall starts the actual Developing expedition; leveling cannot reroll it.
	_set_clock_minute(_clock_minute() + 120)
	var party: Dictionary = state._party.duplicate(true)
	var arrival: int = state._attack_at
	for day: int in range(6):
		city.settle_day(city.last_awarded_day + 1, results, true)
	_expect(city.request_level_up() and city.level == 3, "The next completed city level unlocks Advanced parties.")
	_expect(state._party == party and state._attack_at == arrival and state._composition_stage == &"advanced",
		"The current Developing party retains its strength, members and arrival after level up.")
	ui._select_hub_tab(false)
	ui.open_details()
	# Capture the densest dashboard: active raid pauses a watchtower project.
	_expect(state.request_wall_work(state.get_work_quote("watchtower")), "Watchtower construction starts for the dense UI scenario.")
	_set_clock_minute(arrival - 1)
	# Start a fresh fixture project if the clock already completed the first one.
	if state._work_kind.is_empty():
		state.watchtower_built = false
		_expect(state.request_wall_work(state.get_work_quote("watchtower")), "A fresh project is pending before the attack.")
	_set_clock_minute(arrival)
	state.set_process(false)
	ui.open_details()
	await capture_defense("city-progress-under-attack.png")
	var footer: Control = ui.details_panel.get_node("Margin/Contents/FooterRow")
	_expect(footer.get_global_rect().end.y <= ui.details_panel.get_global_rect().end.y - 8,
		"Progress plus attack plus paused construction keep the footer within the frame.")
	_expect(ui.details_panel.get_global_rect().position.y >= 0 and ui.details_panel.get_global_rect().end.y <= 225,
		"The dense City Hub fits the logical viewport.")
	city.settle_day(city.last_awarded_day + 1, results, true)
	_expect(city.progress == 15, "The fixture has earned progress before the actual breach.")
	state.advance_attack(60.0)
	_expect(state.wall_hp == 0 and city.progress == 5, "A live breach deducts exactly ten points once.")
	ui._select_hub_tab(true)
	await capture_defense("city-progress-breach.png")
	_expect(ui.city_event_label.visible and ui.city_event_label.text == "Wall breached: -10", "Supply presents the one-time wall loss.")
	content.queue_free()
	await get_tree().process_frame
	_restore_clock()
	print("CityProgressionHubTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
