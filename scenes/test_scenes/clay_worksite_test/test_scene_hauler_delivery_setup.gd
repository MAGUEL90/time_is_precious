extends Node2D

@export var persistence_enabled: bool = true
var save_store
var fixture
var failures: int = 0
var ids: Array[String] = ["delivery_laborer", "delivery_hauler", "delivery_hauler_b"]
var storage_a
var storage_b
var destination_a
var destination_b
var received_b: Array[int] = []

func _ready() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _make_destination(label_text: String, position_value: Vector2):
	var storage = preload("res://scenes/test_scenes/clay_worksite_test/hauler_test_storage.gd").new()
	fixture.add_child(storage)
	var endpoint = preload("res://scenes/storage_destination/storage_destination.tscn").instantiate()
	endpoint.name = label_text.replace(" ", "")
	endpoint.display_name = label_text
	endpoint.position = position_value
	fixture.add_child(endpoint)
	endpoint.storage_path = endpoint.get_path_to(storage)
	var outline := Polygon2D.new()
	outline.polygon = PackedVector2Array([Vector2(-16,-12), Vector2(16,-12), Vector2(16,12), Vector2(-16,12)])
	outline.color = Color("80624b")
	endpoint.add_child(outline)
	var label := Label.new()
	label.position = Vector2(-30, 14)
	label.add_theme_font_size_override("font_size", 6)
	endpoint.add_child(label)
	storage.changed.connect(func(): label.text = "%s: %d / %d" % [label_text, storage.quantity, storage.capacity])
	storage.changed.emit()
	return endpoint

func _run() -> void:
	fixture = preload("res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn").instantiate()
	fixture.prepare_nightmare_test = false
	fixture.test_hauler_carts = 2
	add_child(fixture)
	fixture.player.debug_disable_player_needs = true
	fixture.get_node("FixtureNotes/Label").text = "K: Worker Hub | F7: +30 minutes\nF: next day 06:45"
	destination_a = _make_destination("Storage A", Vector2(-130, -70))
	destination_b = _make_destination("Storage B", Vector2(100, -70))
	storage_a = destination_a.get_storage()
	storage_b = destination_b.get_storage()
	destination_b.delivery_received.connect(func(_item: String, count: int): received_b.append(count))
	for index: int in range(ids.size()):
		var worker := WorkerData.new()
		worker.worker_id = ids[index]
		worker.display_name = ["Arad", "Belum", "Hauler B"][index]
		worker.profession = WorkerData.Profession.LABORER if index == 0 else WorkerData.Profession.HAULER
		WorkerDatabase.workers_by_id[worker.worker_id] = worker
		if index > 0:
			fixture.worker_management.equip(worker.worker_id, "test_cart_%d" % (index - 1))
	fixture.player.position = fixture.get_node("WorksiteMarkers/ClaySiteA").position + Vector2(0, 24)
	if OS.get_environment("TIP_TEST_HAULER_TARGET") != "1":
		# Keep the ordinary F6 fixture small: one Laborer and one equipped Hauler.
		fixture.worker_management.fire(ids[2])
		if persistence_enabled:
			save_store = preload("res://scenes/test_scenes/clay_worksite_test/worksite_save_store.gd").new()
			add_child(save_store)
			save_store.status_changed.connect(_save_status_changed)
			# Stable IDs are independent of generated backend names and NodePaths.
			save_store.start(fixture, {"storage_a": destination_a, "storage_b": destination_b})
		fixture._open_site_panel(fixture.get_node("WorksiteMarkers/ClaySiteA"))
		return
	fixture._open_site_panel(fixture.get_node("WorksiteMarkers/ClaySiteA"))
	var inspector = fixture.inspector
	var assignment = inspector.assignment_ui
	var panel = assignment.hauler_setup
	inspector.select_mode("Daily")
	assignment._open_worker_selection(0)
	assignment._on_worker_selected(ids[0])
	_open_hauler()
	_expect(panel.visible and panel.destination_button.item_count == 2, "Hauler selection opens both registered destinations.")
	_expect(fixture.daily.selected[&"ClaySiteA"] == [ids[0]] and fixture.daily.hauler_setups.is_empty(), "Opening Hauler setup does not assign or reserve.")
	_expect(panel.target_edit.text == "20", "The editable example starts at 20 items per day.")
	await _capture("hauler-delivery-setup.png")
	_check_panel_bounds(panel)
	var setup_rect: Rect2 = panel.get_node("Center/Panel").get_global_rect()
	panel.target_edit.text = "0"
	panel._validate()
	_expect(panel.assign_button.disabled, "Zero target cannot be confirmed.")
	panel.target_edit.text = "abc"
	panel._validate()
	_expect(panel.assign_button.disabled, "Non-integer target cannot be confirmed.")
	panel.cancelled.emit()
	_expect(not panel.visible and fixture.daily.selected[&"ClaySiteA"] == [ids[0]] and get_tree().paused, "Cancel returns to selection and preserves the other draft worker.")
	_open_hauler()
	var empty_destinations: Array[Dictionary] = []
	panel.open_for(ids[1], "Belum", empty_destinations)
	_expect(panel.assign_button.disabled, "Empty destination list blocks assignment.")
	await _capture("hauler-delivery-no-storage.png")
	var long_choices: Array[Dictionary] = fixture._storage_choices()
	long_choices[0].name = "Storage with a very long descriptive location name"
	panel.open_for(ids[1], "Worker with a very long display name", long_choices)
	panel.target_edit.text = "9999999"
	panel._validate()
	await _capture("hauler-delivery-long-values.png")
	_expect(panel.get_node("Center/Panel").get_global_rect() == setup_rect, "Long names and targets preserve panel geometry.")
	_check_panel_bounds(panel)
	panel.get_node("Center/Panel/Margin/Body/Header/CloseButton").pressed.emit()
	_open_hauler()
	_choose_destination(destination_b)
	destination_b.accepting_deliveries = false
	panel.assign_button.pressed.emit()
	_expect(panel.visible and not fixture.daily.selected[&"ClaySiteA"].has(ids[1]), "Storage is revalidated when confirming a stale choice.")
	destination_b.accepting_deliveries = true
	panel.assign_button.pressed.emit()
	_expect(not panel.visible and fixture.daily.selected[&"ClaySiteA"].has(ids[1]), "Confirm adds the configured Hauler to the draft.")
	assignment._on_next_pressed()
	_expect(fixture.daily.jobs.is_empty(), "Next does not start work.")
	_expect(not inspector.progress_button.visible, "Worker Progress is hidden before Start Work commits an assignment.")
	var saved_workers: Array = fixture.daily.selected[&"ClaySiteA"].duplicate()
	var saved_hauler: Dictionary = fixture.daily.hauler_setups[ids[1]].duplicate(true)
	for reopen: int in range(2):
		inspector.daily_button.pressed.emit()
		_expect(fixture.daily.selected[&"ClaySiteA"] == saved_workers, "Returning to Worker after Next preserves both workers.")
		_expect(fixture.daily.hauler_setups.get(ids[1], {}) == saved_hauler, "Returning to Worker preserves Hauler storage and target.")
		_expect(assignment.assigned_info_label.text == "Assigned: 2/2" and assignment.selected_worker_ids.has(ids[0]) and assignment.selected_worker_ids.has(ids[1]), "Reopened slots match the 2/2 main-menu feedback.")
		if reopen == 0:
			await _capture("worker-setup-preserved-after-next.png")
		assignment.back_button.pressed.emit()
		_expect(assignment.discard_overlay.visible, "Back still asks before discarding the retained setup.")
		assignment.keep_button.pressed.emit()
		_expect(fixture.daily.selected[&"ClaySiteA"] == saved_workers and fixture.daily.hauler_setups.get(ids[1], {}) == saved_hauler, "No preserves the complete setup.")
		assignment.next_button.pressed.emit()
	inspector.close_requested.emit()
	_expect(fixture.daily.hauler_setups.is_empty() and fixture.daily.selected[&"ClaySiteA"].is_empty(), "Closing main panel discards destination and target with the draft.")
	# Reopen, confirm and start through the actual UI signal path.
	fixture._open_site_panel(fixture.get_node("WorksiteMarkers/ClaySiteA"))
	inspector.select_mode("Daily")
	assignment._open_worker_selection(0)
	assignment._on_worker_selected(ids[0])
	_open_hauler()
	_choose_destination(destination_b)
	panel.assign_button.pressed.emit()
	assignment._on_next_pressed()
	inspector.start_button.pressed.emit()
	_expect(fixture.daily.jobs.has(&"ClaySiteA"), "Start Work commits the UI plan.")
	if not fixture.daily.jobs.has(&"ClaySiteA"):
		_finish()
		return
	_expect(fixture.hauling.routes[ids[1]].daily_target == 20, "Committed target survives menu cleanup.")
	var first_start: int = fixture.daily.jobs[&"ClaySiteA"].starts[ids[1]]
	_expect(first_start / 1440 == TimeComponentManager.current_day + 1, "Assignment still begins on the next day.")
	# Another Hauler uses a separate destination and target, without a site mapping.
	fixture.daily.select_hauler(&"ClaySiteB", ids[2], fixture.get_path_to(destination_a), destination_a.display_name, 5)
	fixture.daily.start(&"ClaySiteB", fixture._drop_daily_output.bind(fixture.get_node("WorksiteMarkers/ClaySiteB")))
	get_tree().paused = true
	var departure: int = fixture.daily.departure_time(&"ClaySiteA", ids[1], first_start / 1440)
	TimeComponentManager.advance_minutes(departure - fixture.daily.now())
	_check_hauler_pose("walk", false, "Commuting to worksite")
	await _capture("hauler-commuting-without-cart.png")
	TimeComponentManager.advance_minutes(first_start - fixture.daily.now())
	_check_hauler_pose("idle_cart", true, "Arrived and waiting for output")
	fixture._drop_daily_output(50, fixture.get_node("WorksiteMarkers/ClaySiteA"))
	fixture._drop_daily_output(50, fixture.get_node("WorksiteMarkers/ClaySiteB"))
	TimeComponentManager.advance_minutes(1)
	await _check_live_hauler_animation()
	TimeComponentManager.advance_minutes(299)
	_expect(storage_b.quantity == 20 and storage_a.quantity == 5, "Each Hauler stops at its own destination target.")
	_expect(received_b == [3, 3, 3, 3, 3, 3, 2], "Target 20 finishes with two items while natural stock remains.")
	_expect(fixture.sites[&"ClaySiteA"].stock > 0, "Partial final target trip did not require stock depletion.")
	_expect(fixture.hauling.target_reached(ids[1], TimeComponentManager.current_day), "Successful receipts reach the daily target.")
	_expect(not fixture.daily._hauler_eligible(ids[1]) and WorkerDatabase.get_worker_data(ids[1]).is_reserved(), "Hauler stops new trips but keeps the Daily assignment.")
	_expect(WorkerDatabase.get_worker_data(ids[1]).profession_xp == 20 and fixture.worker_management.productive_days[ids[1]].size() == 1, "Delivered target contributes exactly 20 XP and one productive day.")
	_check_hauler_pose("walk", false, "Leaving after daily target")
	await _capture("hauler-leaving-without-cart.png")
	_check_conservation()
	fixture._open_site_panel(fixture.get_node("WorksiteMarkers/ClaySiteA"))
	_expect(inspector.progress_button.is_visible_in_tree(), "Worker Progress appears on the main worksite menu after Start Work.")
	await _capture("worker-progress-button-location.png")
	inspector.progress_button.pressed.emit()
	_expect(inspector.progress_panel.visible, "The visible Worker Progress button opens the progress panel.")
	await _capture("hauler-delivery-progress.png")
	_expect(get_viewport().get_visible_rect().encloses(inspector.progress_panel.get_global_rect()), "Worker Progress with destination and daily target stays inside the viewport.")
	var progress_content: VBoxContainer = inspector.progress_panel.get_node("Margin/ProgressContent")
	var progress_header: HBoxContainer = progress_content.get_node("Header")
	var progress_title: Label = progress_header.get_node("TitleLabel")
	var progress_close: TextureButton = progress_header.get_node("CloseButton")
	_expect(progress_title.get_theme_font_size("font_size") == 12, "Worker Progress heading uses the requested crisp 12-pixel font.")
	_expect(progress_title.size.x >= progress_title.get_minimum_size().x, "The larger heading is not clipped.")
	_expect(progress_close.size == Vector2(8, 8), "The close icon retains its native size beside the larger heading.")
	_expect(progress_header.get_global_rect().end.y <= inspector.progress_list.get_global_rect().position.y, "Worker rows remain below the larger heading.")
	_expect(not progress_content.has_node("BackButton"), "Worker Progress has no extra Back button.")
	for element: Control in [progress_header, inspector.progress_list]:
		_expect(inspector.progress_panel.get_global_rect().encloses(element.get_global_rect()), "Progress controls remain inside the resized panel.")
	progress_close.pressed.emit()
	_expect(not inspector.visible, "The existing close icon closes Worker Progress without a Back button.")
	get_tree().paused = true
	TimeComponentManager.advance_minutes(120)
	_expect(storage_b.quantity == 20, "Idle time after reaching target adds no deliveries.")
	# Full storage on day two: no pickup, no delivery credit, and no XP.
	storage_b.capacity = storage_b.quantity
	var second_start: int = (TimeComponentManager.current_day + 1) * 1440 + 420
	var next_day_key := InputEventKey.new()
	next_day_key.keycode = KEY_F
	next_day_key.pressed = true
	var before_shortcut: int = fixture.daily.now()
	_unhandled_key_input(next_day_key)
	_expect(fixture.daily.now() == before_shortcut, "F cannot skip time while a menu or paused tree owns input.")
	get_tree().paused = false
	next_day_key.echo = true
	_unhandled_key_input(next_day_key)
	_expect(fixture.daily.now() == before_shortcut, "Holding F does not skip multiple days.")
	next_day_key.echo = false
	for old_key: Key in [KEY_F8, KEY_PAGEDOWN]:
		next_day_key.keycode = old_key
		_unhandled_key_input(next_day_key)
		_expect(fixture.daily.now() == before_shortcut, "The former shortcut no longer advances game time.")
	next_day_key.keycode = KEY_F
	_unhandled_key_input(next_day_key)
	get_tree().paused = true
	_expect(fixture.daily.now() == second_start - 15, "F advances the debug fixture to tomorrow at 06:45.")
	TimeComponentManager.advance_minutes(second_start - fixture.daily.now() + 1)
	_expect(fixture.hauling.delivered_on_day(ids[1], TimeComponentManager.current_day) == 0, "Daily counter resets the next day.")
	_expect(fixture.hauling.routes[ids[1]].cargo.quantity == 0 and storage_b.quantity == 20, "Full storage prevents pickup.")
	storage_b.capacity = 96
	TimeComponentManager.advance_minutes(1)
	_expect(fixture.hauling.routes[ids[1]].cargo.quantity == 3, "Available storage resumes the existing daily plan.")
	destination_b.accepting_deliveries = false
	TimeComponentManager.advance_minutes(60)
	_expect(fixture.hauling.routes[ids[1]].cargo.quantity == 0, "Rejected in-flight cargo returns to its worksite.")
	_expect(fixture.hauling.delivered_on_day(ids[1], TimeComponentManager.current_day) == 0 and WorkerDatabase.get_worker_data(ids[1]).profession_xp == 20, "Failed unloading counts neither target nor XP.")
	_check_conservation()
	# Changing a legacy site mapping cannot silently redirect the committed plan.
	fixture.storage_destinations[&"ClaySiteA"] = fixture.get_path_to(destination_a)
	destination_b.accepting_deliveries = true
	TimeComponentManager.advance_minutes(300)
	_expect(storage_b.quantity == 40 and storage_a.quantity == 10, "Both standing plans resume independently tomorrow at the same destinations.")
	_expect(WorkerDatabase.get_worker_data(ids[1]).profession_xp == 40 and fixture.worker_management.productive_days[ids[1]].size() == 2, "Second productive day accumulates exactly the delivered XP.")
	_check_conservation()
	_finish()

func _open_hauler() -> void:
	var assignment = fixture.inspector.assignment_ui
	assignment._open_worker_selection(1)
	assignment._on_worker_selected(ids[1])

func _choose_destination(endpoint: Node) -> void:
	var selector: OptionButton = fixture.inspector.assignment_ui.hauler_setup.destination_button
	for index: int in range(selector.item_count):
		if selector.get_item_metadata(index) == fixture.get_path_to(endpoint):
			selector.select(index)
			selector.item_selected.emit(index)
			return
	_expect(false, "Requested destination is available in the selector.")

func _check_panel_bounds(panel: Control) -> void:
	var content: Control = panel.get_node("Center/Panel/Margin/Body")
	var bounds: Rect2 = panel.get_node("Center/Panel").get_global_rect()
	_expect(bounds.encloses(content.get_global_rect()), "Content stays inside the compact scene-authored panel.")
	_expect(bounds.size.x <= 200 and bounds.size.y <= 145, "Setup panel stays compact at the logical viewport.")
	for child: Control in content.get_children():
		_expect(content.get_global_rect().encloses(child.get_global_rect()), "Setup rows remain inside content bounds.")

func _check_conservation() -> void:
	var gathered: int = fixture.daily.jobs[&"ClaySiteA"].stats[ids[0]].output
	var stored: int = storage_a.quantity + storage_b.quantity
	var ground: int = fixture._daily_output_count(&"ClaySiteA") + fixture._daily_output_count(&"ClaySiteB")
	var cargo: int = 0
	for route: Dictionary in fixture.hauling.routes.values():
		cargo += int(route.cargo.quantity)
	_expect(stored + ground + cargo == 100 + gathered, "Clay is conserved across destinations, output piles and cargo.")

func _check_hauler_pose(action: String, has_cart: bool, context: String) -> void:
	var controller = fixture.get_node("WorkerVisuals")
	controller._process(0.1)
	var actor = controller.actors[ids[1]]
	_expect(actor.visible and str(actor.body_sprite.animation).begins_with("light_%s_" % action), context + ": uses the correct light animation.")
	_expect((actor.cart_visual != null and actor.cart_visual.visible) == has_cart, context + ": cart visibility matches the phase.")
	_expect(fixture.city_tools.has_equipped(ids[1], "cart"), context + ": cart allocation remains equipped.")


func _check_live_hauler_animation() -> void:
	# Keep the delivery clock fixed while real frames exercise the live controller.
	var clock_was_paused: bool = TimeComponentManager.is_paused
	TimeComponentManager.is_paused = true
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	var controller = fixture.get_node("WorkerVisuals")
	var actor = controller.actors.get(ids[1])
	_expect(actor != null and fixture.hauling.status(ids[1]) == "outbound", "The default fixture Hauler has begun a real delivery trip.")
	if actor != null:
		_expect(actor.skin_tone == "light", "The Hauler keeps the requested light appearance across commute and cart work.")
		_expect(str(actor.body_sprite.animation).contains("push_cart"), "An outbound Hauler uses push-cart motion in the actual worksite controller.")
		_expect(str(actor.body_sprite.animation).begins_with("light_") and str(actor.head_sprite.animation).begins_with("base_light_") and str(actor.hand_sprite.animation).begins_with("light_"), "The live Hauler uses the supplied light body, head and hand clips.")
		_expect(actor.body_sprite.material == null and actor.head_sprite.material == null and actor.hand_sprite.material == null, "The live Hauler has no added skin recoloring.")
		var origin: Vector2 = actor.global_position
		var frames: Dictionary = {}
		var sample_until: int = Time.get_ticks_msec() + 800
		while Time.get_ticks_msec() < sample_until:
			await get_tree().process_frame
			frames[actor.body_sprite.frame] = true
		_expect(frames.size() >= 3, "The live Hauler advances through pushing frames while moving.")
		_expect(not actor.global_position.is_equal_approx(origin), "The live delivery animation runs while the Hauler travels.")
		_expect(actor.cart_visual.frame == actor.body_sprite.frame and actor.hand_sprite.frame == actor.body_sprite.frame, "Live cart and hands stay in step with the body: body=%d/%f cart=%d/%f hand=%d/%f." % [actor.body_sprite.frame, actor.body_sprite.frame_progress, actor.cart_visual.frame, actor.cart_visual.frame_progress, actor.hand_sprite.frame, actor.hand_sprite.frame_progress])
		await _capture("hauler-delivery-pushing.png")
	get_tree().paused = true
	TimeComponentManager.is_paused = clock_was_paused


func _capture(filename: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join(filename))

func _finish() -> void:
	print("HaulerDeliverySetupTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)

func _unhandled_key_input(event: InputEvent) -> void:
	if fixture == null or not event is InputEventKey or not event.pressed or event.echo or get_tree().paused:
		return
	if event.keycode == KEY_F7:
		TimeComponentManager.advance_minutes(30)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F:
		var tomorrow: int = (TimeComponentManager.current_day + 1) * 1440 + 6 * 60 + 45
		TimeComponentManager.advance_minutes(tomorrow - fixture.daily.now())
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if is_instance_valid(save_store):
		save_store.enabled = false
	if is_instance_valid(fixture):
		fixture.daily.cleanup()
	for id: String in ids:
		WorkerDatabase.workers_by_id.erase(id)
		WorkerDatabase.dismissed_workers.erase(id)

func _save_status_changed(_message: String) -> void:
	if is_instance_valid(save_store) and save_store.blocked:
		fixture.get_node("FixtureNotes/Label").text = "Save unavailable; existing file preserved.\nSee Godot Output for the save path."
