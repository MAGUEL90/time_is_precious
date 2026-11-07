extends "res://scenes/test_scenes/test_scene_defense_dialogue.gd"

func _run() -> void:
	_snapshot_globals()
	if DisplayServer.get_name() == "headless":
		# Match the project's development window; headless defaults to a square viewport.
		get_window().size = Vector2i(1200, 675)
		await get_tree().process_frame
		_expect(get_viewport().get_visible_rect().size == Vector2(400, 225), "Headless Hub checks use the intended 400x225 viewport.")
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	var original_window_size: Vector2i = get_window().size
	get_window().size = Vector2i(1200, 675)
	var original_inventory: Dictionary = Inventory.items.duplicate(true)
	var original_capacity: float = Inventory.max_load
	Inventory.max_load = 100000.0
	Inventory.items.assign({"stone": 100, "wood_log": 100})
	await load_content()
	_expect(get_viewport().get_visible_rect().size == Vector2(400, 225),
		"The fixture uses the project's 400 x 225 logical viewport.")
	var city: Node = WorkStateRuntime.get_node("CityProgression")
	_expect(city.level == 1 and city.progress == 0, "A new city starts at level 1 with zero progress.")
	# Wall and watchtower work consume player inventory, not City Storage.
	Inventory.items.assign({"stone": 100, "wood_log": 100})
	Inventory.items_changed.emit()
	storage.items = {"stone": 100, "wood_log": 100}
	_expect(state.request_wall_work(state.get_work_quote()), "Wall construction starts with actual materials.")
	_expect(Inventory.items == {"stone": 90, "wood_log": 95}
		and storage.items == {"stone": 100, "wood_log": 100},
		"Wall construction spends player Inventory and leaves City Storage untouched.")
	var results: Array[Dictionary] = [{"food": true, "clothing": true, "satisfaction": 0.8}]
	for day: int in range(1, 11):
		city.settle_day(city.last_awarded_day + 1, results, false)
	_expect(city.progress == 100 and city.level == 1, "Progress caps at100 and waits for an explicit Level Up.")
	ui.open_details()
	await get_tree().process_frame
	await get_tree().process_frame
	await capture_defense("city-progress-ready.png")
	for _frame: int in range(3):
		await get_tree().process_frame
	var management_rect: Rect2 = ui.details_panel.get_global_rect()
	_assert_hub_tab_layout("Management")
	_expect(not ui.storage_summary.visible and not ui.watchtower_status_label.visible, "Management omits the requested storage/watchtower feedback.")
	_expect(ui.city_storage_button.is_visible_in_tree() and not ui.city_storage_button.disabled,
		"City Hub presents an enabled City Storage action.")
	await capture_defense("city-hub-storage-button.png")
	var management_button: Button = ui.hub_tabs.get_child(0)
	var supply_button: Button = ui.hub_tabs.get_child(1)
	await _click_hub_button(supply_button)
	_expect(ui._supply_selected and supply_button.button_pressed and ui.supply_view.visible,
		"A mouse click selects Supply after centering the tabs.")
	_assert_hub_tab_layout("Supply")
	await _click_hub_button(management_button)
	_expect(not ui._supply_selected and management_button.button_pressed and not ui.supply_view.visible,
		"A mouse click returns to Management after centering the tabs.")
	var stock_before_browse: Dictionary = storage.items.duplicate(true)
	var treasury_before_browse: int = CityStockManager.treasury_shekel
	await _click_hub_button(ui.city_storage_button)
	await get_tree().process_frame
	var browse = ui.city_storage_view
	_expect(is_instance_valid(browse) and browse.read_only and browse.storage == storage and not ui.details_panel.visible,
		"City Hub opens the shared central stock as a read-only view.")
	if is_instance_valid(browse):
		_expect(browse.deposit_button.disabled and browse.haul_button.disabled, "Remote Deposit and Send remain disabled.")
		browse._open_transfer("deposit")
		browse._open_haul()
		_expect(not is_instance_valid(browse.transfer_ui) and not is_instance_valid(browse.haul_ui)
			and storage.items == stock_before_browse and CityStockManager.treasury_shekel == treasury_before_browse,
			"Browsing and direct action calls do not move stock or money.")
		for modifier: String in ["ctrl_pressed", "alt_pressed", "meta_pressed", "shift_pressed"]:
			var modified: InputEventKey = _storage_key(KEY_C)
			modified.set(modifier, true)
			get_viewport().push_input(modified)
			await get_tree().process_frame
			_expect(is_instance_valid(ui.city_storage_view) and ui.city_storage_view == browse and get_tree().paused,
				"Modified C leaves read-only storage open: " + modifier)
		var repeated: InputEventKey = _storage_key(KEY_C)
		repeated.echo = true
		get_viewport().push_input(repeated)
		var released: InputEventKey = _storage_key(KEY_C)
		released.pressed = false
		get_viewport().push_input(released)
		await get_tree().process_frame
		_expect(is_instance_valid(ui.city_storage_view) and ui.city_storage_view == browse and get_tree().paused,
			"Echo and release events leave read-only storage open.")
		browse.view.get_node("Margin/Content/Footer/Back").pressed.emit()
		await get_tree().process_frame
		_expect(ui.details_panel.visible and not get_tree().paused, "Back returns from storage to City Hub and restores pause state.")
	ui.city_storage_button.pressed.emit()
	await get_tree().process_frame
	_expect(is_instance_valid(ui.city_storage_view) and get_tree().paused, "City Storage can be reopened before testing C.")
	get_viewport().push_input(_storage_key(KEY_C))
	await get_tree().process_frame
	_expect(not is_instance_valid(ui.city_storage_view) and ui.details_panel.visible and not get_tree().paused,
		"An unmodified C press through viewport input returns from storage to City Hub.")
	var release_c: InputEventKey = _storage_key(KEY_C)
	release_c.pressed = false
	get_viewport().push_input(release_c)
	await get_tree().process_frame
	_expect(ui.details_panel.visible, "Releasing C leaves City Hub open after returning from storage.")
	get_viewport().push_input(_storage_key(KEY_C))
	await get_tree().process_frame
	_expect(not ui.details_panel.visible, "A subsequent C press keeps the existing City Hub close behavior.")
	ui.open_details()
	ui.city_storage_button.pressed.emit()
	await get_tree().process_frame
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	get_viewport().push_input(cancel)
	await get_tree().process_frame
	_expect(not is_instance_valid(ui.city_storage_view) and ui.details_panel.visible and not get_tree().paused,
		"Escape still returns from read-only storage to City Hub.")
	ui.city_level_up_button.pressed.emit()
	_expect(city.level == 2 and city.progress == 0 and state._composition_stage == &"developing", "The City Hub button advances one level and future raiders.")
	ui.city_level_up_button.pressed.emit()
	_expect(city.level == 2, "Repeated button activation cannot buy another level.")
	city.settle_day(city.last_awarded_day + 1, results, false)
	ui._select_hub_tab(true)
	await get_tree().process_frame
	await get_tree().process_frame
	await capture_defense("city-progress-supply.png")
	for _frame: int in range(3):
		await get_tree().process_frame
	_expect(ui.details_panel.get_global_rect() == management_rect, "Switching to Supply preserves the exact panel size and position.")
	for summary: Label in [ui.supply_food, ui.supply_clothing, ui.supply_shelter]:
		var icon: TextureRect = summary.get_parent().get_node("IconFrame/Icon")
		_expect(icon.size == Vector2(16, 16) and icon.stretch_mode == TextureRect.STRETCH_KEEP and icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"Supply icons preserve their native pixel size without fractional resampling.")
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
	await get_tree().process_frame
	await get_tree().process_frame
	await capture_defense("city-progress-under-attack.png")
	for _frame: int in range(3):
		await get_tree().process_frame
	_assert_hub_tab_layout("Dense Management")
	_expect(ui.details_panel.get_global_rect() == management_rect, "Construction and attack status preserve the same City Hub frame.")
	var footer: Control = ui.details_panel.get_node("Margin/Contents/FooterRow")
	_expect(footer.get_global_rect().end.y <= ui.details_panel.get_global_rect().end.y - 8,
		"Progress plus attack plus paused construction keep the footer within the frame.")
	var dense_rect: Rect2 = ui.details_panel.get_global_rect()
	_expect(dense_rect.position.y >= 0 and dense_rect.end.y <= 225,
		"The dense City Hub fits the logical viewport (panel: %s, viewport: %s)." % [dense_rect, get_viewport().get_visible_rect()])
	city.settle_day(city.last_awarded_day + 1, results, true)
	_expect(city.progress == 15, "The fixture has earned progress before the actual breach.")
	state.advance_attack(60.0)
	_expect(state.wall_hp == 0 and city.progress == 5, "A live breach deducts exactly ten points once.")
	ui._select_hub_tab(true)
	await capture_defense("city-progress-breach.png")
	_expect(ui.city_event_label.visible and ui.city_event_label.text == "Wall breached: -10", "Supply presents the one-time wall loss.")
	content.queue_free()
	await get_tree().process_frame
	Inventory.items.assign(original_inventory)
	Inventory.items_changed.emit()
	_restore_clock()
	get_window().size = original_window_size
	Inventory.max_load = original_capacity
	print("CityProgressionHubTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _assert_hub_tab_layout(context: String) -> void:
	var tabs: HBoxContainer = ui.hub_tabs
	_expect(tabs.get_child_count() == 3, context + ": City Hub retains three top buttons.")
	if tabs.get_child_count() != 3:
		return
	var first: Control = tabs.get_child(0)
	var last: Control = tabs.get_child(2)
	var contents: Control = tabs.get_parent()
	var group_left: float = first.get_global_rect().position.x
	var group_right: float = last.get_global_rect().end.x
	var contents_center: float = contents.get_global_rect().get_center().x
	_expect(absf((group_left + group_right) * 0.5 - contents_center) <= 0.5,
		context + ": the three-button group is centered in the panel.")
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var previous: Control = null
	for button: Control in tabs.get_children():
		var button_rect: Rect2 = button.get_global_rect()
		_expect(button.is_visible_in_tree() and contents.get_global_rect().encloses(button_rect) and viewport_rect.encloses(button_rect),
			context + ": each top button is visible inside the panel and viewport.")
		if is_instance_valid(previous):
			_expect(button_rect.position.x - previous.get_global_rect().end.x >= 6.0,
				context + ": top buttons retain their six-pixel gap.")
		previous = button
	for control: Control in contents.get_children():
		if control == tabs or not control.is_visible_in_tree():
			continue
		for button: Control in tabs.get_children():
			_expect(not button.get_global_rect().intersects(control.get_global_rect()),
				context + ": top buttons do not overlap other visible sections.")

func _click_hub_button(button: Button) -> void:
	var point: Vector2 = button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	event.button_mask = 0
	get_viewport().push_input(event, true)
	await get_tree().process_frame

func _storage_key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event
