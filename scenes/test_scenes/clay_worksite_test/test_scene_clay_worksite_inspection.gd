extends Node

var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var fixture = load("res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn").instantiate()
	var saved_ui: Control = fixture.get_node("InspectionUI/ClayWorksiteInspector")
	var authored_picker_size: Vector2 = saved_ui.get_node("Center/HourlySetup").custom_minimum_size
	var authored_player_caption: String = saved_ui.get_node("Center/TextureWindow/Margin/MainVBox/ModeRow/HourlyButton").text
	var authored_worker_caption: String = saved_ui.get_node("Center/TextureWindow/Margin/MainVBox/ModeRow/DailyButton").text
	_expect(not saved_ui.get_node("Center/HourlySetup").visible and not saved_ui.get_node("Center/TextureWindow/Margin/MainVBox/Confirmation").visible and not saved_ui.get_node("Center/TextureWindow/Margin/MainVBox/Footer/StartButton").visible, "Saved editor state already hides setup and confirmation before any runtime script.")
	_expect(saved_ui.find_child("OutputLabel", true, false) == null and saved_ui.find_child("AddWorkerButton", true, false) == null, "Obsolete UI nodes are removed from the scene, not merely hidden.")
	add_child(fixture)
	await get_tree().process_frame
	fixture.sites[&"ClaySiteA"].toggle_participant("player")
	fixture.sites[&"ClaySiteB"].toggle_participant("player")
	var player: Player = fixture.player
	var panel = fixture.inspector
	var site = fixture.get_node("WorksiteMarkers/ClaySiteA")
	var items_before: Dictionary = Inventory.items.duplicate()
	var exp_before: int = player.current_experience
	_expect(fixture.get_node("TopHUD").visible, "Existing Top HUD must be present.")
	_expect(not site.get_node("InteractPrompt").visible, "No E prompt when distant.")
	player.global_position = site.global_position
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(site.get_node("InteractPrompt").visible, "Shared E prompt appears in site range.")
	await _press("interact")
	_expect(panel.hourly_button.text == authored_player_caption and panel.daily_button.text == authored_worker_caption, "Runtime preserves scene-authored mode captions.")
	_expect(panel.visible and not site.get_node("InteractPrompt").visible, "Opening hides E prompt.")
	_expect(panel.find_child("AddWorkerButton", true, false) == null and panel.find_child("OutputLabel", true, false) == null, "No footer Add Worker or estimated output.")
	_expect(panel.get_node("Center/TextureWindow/Margin/MainVBox/QuestionLabel").visible and not panel.get_node("Center/TextureWindow/Margin/MainVBox/Confirmation/WorkersLabel").visible, "Initial menu asks duration without empty worker feedback.")
	if OS.get_environment("TIP_CAPTURE_INSPECTOR") == "1" and DisplayServer.get_name() != "headless":
		await _capture("worksite-initial.png")
	panel.hourly_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var required_picker_size: Vector2 = authored_picker_size.max(panel.hourly_setup_panel.get_node("Margin").get_combined_minimum_size())
	_expect(panel.hourly_setup_panel.custom_minimum_size == required_picker_size, "Picker uses authored size and expands only as required by its content.")
	_expect(panel.next_button.get_global_rect().end.y <= panel.hourly_setup_panel.get_global_rect().end.y - 8, "New label and footer fit within picker padding.")
	_expect(panel.get_duration_minutes() == 180 and panel.duration_buttons.get_child_count() == 3, "Three fixed durations; three-hour default.")
	_expect(panel.back_button.visible and panel.next_button.text == "Next" and not panel.title.is_visible_in_tree() and not panel.hourly_button.is_visible_in_tree(), "Hourly picker has Back/Next without main header and mode controls.")
	_expect(not panel.energy_label.is_visible_in_tree() and not panel.status_label.visible, "Picker hides condition/tool/status feedback.")
	if OS.get_environment("TIP_CAPTURE_INSPECTOR") == "1" and DisplayServer.get_name() != "headless":
		await _capture("worksite-hourly-picker.png")
	panel.select_duration(1)
	panel.back_button.pressed.emit()
	_expect(panel.work_mode.is_empty() and panel.selected_duration == 180 and not panel.start_button.visible, "Back cancels draft selection and returns to initial menu.")
	panel.hourly_button.pressed.emit()
	panel.next_button.pressed.emit()
	_expect(not panel._hourly_setup and panel.start_button.text == "Start Work" and not fixture._working, "Next returns to confirmation without starting work.")
	_expect(panel.daily_button.disabled, "Confirmed Player setup locks Worker choice.")
	var now: int = TimeComponentManager.current_minute
	player.fatigue = 0.5
	player.hunger = 0.0
	player.condition_changed.emit()
	_expect(fixture.sites[&"ClaySiteA"].preview(180, player).units == 18, "Three hours previews eighteen clay.")
	_expect(panel.energy_label.text == "Energy -9%" and panel.satiety_label.text == "Satiety -18%", "Show only the selected duration's costs.")
	_expect(not panel.status_label.visible, "Hide normal stock/time/bag breakdown.")
	panel.hourly_button.pressed.emit()
	panel.duration_buttons.get_child(1).pressed.emit()
	panel.next_button.pressed.emit()
	_expect(panel.get_duration_minutes() == 360 and fixture.sites[&"ClaySiteA"].preview(360, player).units == 36, "Six-hour preset.")
	_expect(panel.energy_label.text == "Energy -18%" and panel.satiety_label.text == "Satiety -36%", "Six-hour costs remain accurate.")
	panel.hourly_button.pressed.emit()
	panel.duration_buttons.get_child(2).pressed.emit()
	panel.next_button.pressed.emit()
	_expect(panel.get_duration_minutes() == 540 and fixture.sites[&"ClaySiteA"].preview(540, player).units == 54, "Nine-hour manual preset.")
	_expect(not panel.start_button.disabled and not panel.status_label.visible, "Player can start nine hours.")
	panel.hourly_button.pressed.emit()
	panel.select_duration(0)
	await _press("ui_cancel")
	_expect(panel.visible and panel.selected_duration == 540 and panel.work_mode == "Hourly" and get_tree().paused, "Escape cancels a draft while preserving confirmed setup and modal lock.")
	var max_load: float = Inventory.max_load
	Inventory.max_load = Inventory.get_total_inventory_weight()
	panel.select_duration(0)
	_expect(not panel.start_button.disabled and not panel.status_label.visible, "Full bag keeps Start available without extra normal feedback.")
	Inventory.max_load = max_load
	Inventory.items_changed.emit()
	await get_tree().create_timer(1.05, true).timeout
	_expect(TimeComponentManager.current_minute == now and player.fatigue == 0.5 and player.hunger == 0.0, "No condition/time mutation in preview.")
	await _press("open_inventory")
	_expect(not fixture.get_node("InventoryUI").visible, "Modal blocks competing menu.")
	if OS.get_environment("TIP_CAPTURE_INSPECTOR") == "1" and DisplayServer.get_name() != "headless":
		await _capture("panel.png")
		panel.title.text = "Clay Worksite With A Very Long Location Name"
		await _capture("long-title.png")
		_expect(panel.title.get_global_rect().end.x <= panel.close_button.global_position.x, "Title leaves Close clear.")
	_expect(panel.window.size.x == 240 and panel.window.size.y <= 155, "Use the smaller workshop panel bounds.")
	_expect(panel.start_button.get_global_rect().end.y <= panel.window.get_global_rect().end.y - 10, "Footer fits window.")
	await _press("ui_cancel")
	_expect(not panel.visible and player.can_move and not get_tree().paused, "Closing restores gameplay.")
	_expect(panel.work_mode.is_empty() and panel.selected_duration == 180, "Close resets Player setup.")
	for site_name: String in ["ClaySiteB", "ClaySiteA"]:
		player.global_position = fixture.get_node("WorksiteMarkers/" + site_name).global_position
		await _press("interact")
		_expect(panel.visible and panel.get_duration_minutes() == 180, "Reopen resets selection only.")
		panel.close_button.pressed.emit()
	_expect(Inventory.items == items_before and player.current_experience == exp_before, "UI grants no items/EXP.")
	await _press("interact")
	fixture.queue_free()
	await get_tree().process_frame
	_expect(not get_tree().paused, "Freeing open modal releases pause.")
	print("ClayWorksiteInspectionTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)

func _capture(filename: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("tip-clay-feedback-20260907/" + filename))

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
