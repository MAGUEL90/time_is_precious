extends Node

## Integration/evidence run. Uses a fresh process and the native modal signal paths.
const CAPTURE: PackedScene = preload("res://scenes/content_scene/capture/portrait_capture.tscn")
const STARTUP = preload("res://scenes/content_scene/startup/initial_worksites.gd")
var failures: int = 0
var rig: Node
var checkpoint_before: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _settle() -> void:
	for frame: int in range(5):
		await get_tree().process_frame

func _capture(filename: String) -> void:
	await _settle()
	_text_style(get_tree().root)
	var folder: String = OS.get_environment("TIP_CAPTURE_EVIDENCE")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_expect(image.get_width() * 16 == image.get_height() * 9, "Renderer output retains the portrait aspect ratio.")
	image.resize(1080, 1920, Image.INTERPOLATE_NEAREST)
	_expect(image.save_png(folder.path_join(filename)) == OK, "Evidence PNG can be saved.")

func _bounds(control: Control, context: String) -> void:
	_expect(get_viewport().get_visible_rect().encloses(control.get_global_rect()), context + " stays inside the portrait viewport.")
	_text_style(control)

func _text_style(node: Node) -> void:
	if node is Control or node is Window:
		var themed: Variant = node
		_expect(themed.get_theme_font("font") == rig.CAPTURE_FONT and themed.get_theme_font_size("font_size") == 6, "Capture font stays pixel_rpg at size 6: " + str(node.get_path()))
		if node is RichTextLabel:
			_expect(themed.get_theme_font("normal_font") == rig.CAPTURE_FONT and themed.get_theme_font_size("normal_font_size") == 6, "Rich text uses the same capture font and size.")
	for child: Node in node.get_children(true):
		_text_style(child)

func _run() -> void:
	# Do not write or replace the normal slot. The harness may seed isolated sentinels.
	for suffix: String in ["", ".bak", ".tmp", ".pending"]:
		var path: String = "user://city_save/checkpoint_v1.json" + suffix
		checkpoint_before[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	rig = CAPTURE.instantiate()
	get_tree().root.add_child(rig)
	get_tree().current_scene = rig
	var deadline: int = Time.get_ticks_msec() + 10000
	while not rig.ready_for_capture and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(rig.ready_for_capture, "Fresh capture starts through the real map.")
	if not rig.ready_for_capture:
		_finish()
		return
	await _settle()
	_text_style(get_tree().root)
	var home: Area2D = rig.content.get_node("YSortWorld/HomeDoor")
	_expect(not home.is_visible_in_tree() and not home.monitoring and home.get_node("CollisionShape2D").disabled, "Capture hides Home / Sleep and disables only its capture entry trigger.")
	var authored: Node = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	_expect(authored.get_node("YSortWorld/HomeDoor").visible and authored.get_node("YSortWorld/HomeDoor").monitoring, "Authored gameplay home remains visible and usable.")
	authored.free()
	_expect(get_tree().current_scene == rig.content, "Authored ContentScene remains the real current scene.")
	_expect(get_viewport().get_visible_rect().size == Vector2(360, 640), "Logical portrait viewport is 360x640.")
	_expect(ProjectSettings.get_setting("display/window/size/viewport_width") == 400 and ProjectSettings.get_setting("display/window/size/viewport_height") == 225, "Project-wide display settings remain authored.")
	_expect(not rig.player.debug_disable_player_needs and not rig.player.debug_disable_fatigue, "Native player needs stay enabled.")
	_expect(WorkerDatabase.get_all_workers().size() == 2 and rig.runtime.city_tools.has_equipped(STARTUP.HAULER_APPLICANT_ID, "cart"), "Real initial applicants and the physical starting cart are prepared.")
	var visible_sites: int = 0
	var visible_stockpiles: int = 0
	for marker: Marker2D in rig.runtime.get_node("WorksiteMarkers").get_children():
		visible_sites += int(marker.is_visible_in_tree())
		_expect(marker.visible == (marker == rig.site), "Only the preset site is drawn; other native site nodes remain registered.")
	for site_id: StringName in rig.runtime.storage_destinations:
		var stockpile: StorageDestination = rig.runtime._storage_destination(site_id)
		visible_stockpiles += int(stockpile.is_visible_in_tree())
		_expect(not stockpile.get_node("CollisionShape2D").disabled and stockpile.is_available(), "Hiding a stockpile preserves its native delivery endpoint and collision shape.")
	_expect(visible_sites == 1 and visible_stockpiles == 1 and rig.runtime.sites.size() == 5, "Capture draws one site and one stockpile while all five native sessions remain intact.")
	_expect(not rig.runtime.get_node("CityStorageArea").is_visible_in_tree(), "Unrelated City Storage icon and labels are hidden only in capture.")
	var now: int = rig.runtime.daily.now()
	await get_tree().create_timer(0.2, true).timeout
	_expect(rig.runtime.daily.now() == now, "Holding the recording clock consumes no automatic minutes.")
	_expect(not await rig.prepare_next_shift(), "Overnight preparation refuses an uncommitted assignment.")
	await _capture("portrait-01-opening.png")
	if DisplayServer.get_name() != "headless":
		var png_path: String = await rig.save_portrait()
		_expect(not png_path.is_empty() and Image.load_from_file(png_path).get_size() == Vector2i(1080, 1920), "F8's capture transaction saves a full 1080x1920 PNG.")
	var hub_key := InputEventAction.new()
	hub_key.action = &"open_worker_hub"
	hub_key.pressed = true
	get_viewport().push_input(hub_key)
	await _settle()
	var hub: CanvasLayer = rig.runtime.worker_control
	_expect(hub.visible, "Native Worker Hub opens in the portrait map.")
	_bounds(hub.window, "Worker Hub")
	hub.tools_tab_button.pressed.emit()
	await _capture("portrait-01b-worker-hub.png")
	hub.close_button.pressed.emit()

	# Manual work uses E, Hourly, duration, Next and Start Work.
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	get_viewport().push_input(event)
	await _settle()
	var inspector: Control = rig.runtime.inspector
	_expect(inspector.visible, "Native E interaction opens the clay worksite.")
	if not inspector.visible:
		_finish()
		return
	_bounds(inspector.window, "Worksite panel")
	inspector.hourly_button.pressed.emit()
	await _settle()
	_bounds(inspector.hourly_setup_panel, "Hourly duration panel")
	inspector.duration_buttons.get_child(0).pressed.emit()
	inspector.next_button.pressed.emit()
	await _capture("portrait-02-manual-preview.png")
	var before_fatigue: float = rig.player.fatigue
	_expect(not inspector.start_button.disabled, "The three-hour manual work preview is startable.")
	inspector.start_button.pressed.emit()
	await rig.runtime.work_finished
	_expect(rig.runtime.daily.now() == now + 180 and rig.runtime.last_work_result.units > 0, "Manual work advances three actual hours and yields real output.")
	_expect(rig.player.fatigue > before_fatigue, "Manual work retains its fatigue cost.")
	await _capture("portrait-03-manual-result.png")
	var inventory: CanvasLayer = rig.content.get_node("InventoryUI")
	inventory.toggle_inventory()
	await _settle()
	_bounds(inventory.inventory_container, "Inventory panel")
	await _capture("portrait-03b-inventory.png")
	inventory.toggle_inventory()

	# Native worker selection and Hauler destination/target confirmation.
	rig.runtime._open_site_panel(rig.site)
	inspector.daily_button.pressed.emit()
	var assignment = inspector.assignment_ui
	await _settle()
	_bounds(assignment.get_node("Root/Center/TextureWindow"), "Worker assignment panel")
	assignment._open_worker_selection(0)
	await _capture("portrait-04-worker-selection.png")
	assignment._on_worker_selected(STARTUP.APPLICANT_ID)
	assignment._open_worker_selection(1)
	assignment._on_worker_selected(STARTUP.HAULER_APPLICANT_ID)
	var setup: Control = assignment.hauler_setup
	await _settle()
	_bounds(setup.get_node("Center/Panel"), "Hauler destination panel")
	var destination: Node = rig.runtime.get_node("ClayStorage")
	var found: bool = false
	for index: int in range(setup.destination_button.item_count):
		if setup.destination_button.get_item_metadata(index) == rig.runtime.get_path_to(destination):
			setup.destination_button.select(index)
			setup.destination_button.item_selected.emit(index)
			found = true
	_expect(found, "The actual clay stockpile is available as a delivery destination.")
	setup.target_edit.grab_focus()
	setup.target_edit.caret_column = setup.target_edit.text.length()
	var number_key := InputEventKey.new()
	number_key.keycode = KEY_2
	number_key.unicode = 50
	number_key.pressed = true
	get_viewport().push_input(number_key)
	await _settle()
	_expect(setup.target_edit.text == "202" and not rig.follow_player, "Capture camera shortcuts preserve native numeric target editing.")
	setup.target_edit.text = "20"
	setup._validate()
	await _capture("portrait-05-hauler-setup.png")
	setup.assign_button.pressed.emit()
	assignment.next_button.pressed.emit()
	await _capture("portrait-06-assignment-preview.png")
	inspector.start_button.pressed.emit()
	_expect(rig.runtime.daily.jobs.has(rig.preset.site_name), "Native Start Work commits the plan.")
	_expect(rig.runtime.daily.jobs.size() == 1, "The take schedules only its one focused worksite.")
	if not rig.runtime.daily.jobs.has(rig.preset.site_name):
		_finish()
		return
	var start: int = rig.runtime.daily.jobs[rig.preset.site_name].starts[STARTUP.APPLICANT_ID]
	_expect(start == 1440 + 420, "Delegation starts on day one at 07:00, never instantly.")
	_expect(rig.runtime._daily_output_count(rig.preset.site_name) == 0, "Assignment does not fabricate production before the shift.")
	_expect(await rig.prepare_next_shift(), "Native sleep and waiting prepare the next shift.")
	_expect(rig.runtime.daily.now() == start - 15 and TimeComponentManager.current_day == 1, "Overnight preparation visibly changes day and reaches 06:45.")
	_expect(Inventory.items.get(rig.preset.food_item, 0) == 1 and not rig.player.has_critical_condition() and rig.player.can_move, "Three physical meals are consumed; native player conditions permit movement.")
	await _capture("portrait-07-next-day.png")

	# Start the real native clock rate. Sample a route while the player walks away.
	rig.debug.set_speed(rig.preset.recording_speed)
	rig.set_clock_running(true)
	deadline = Time.get_ticks_msec() + 20000
	while rig.runtime.hauling.status(STARTUP.HAULER_APPLICANT_ID) != "outbound" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	rig.set_clock_running(false)
	_expect(rig.runtime.hauling.status(STARTUP.HAULER_APPLICANT_ID) == "outbound", "Real production initiates a native loaded-cart delivery route.")
	await _capture("portrait-08a-loaded-cart.png")
	var origin: Vector2 = rig.player.global_position
	var walking_start: int = rig.runtime.daily.now()
	var walking_output: int = rig.runtime.daily.jobs[rig.preset.site_name].stats[STARTUP.APPLICANT_ID].output
	rig.set_clock_running(true)
	Input.action_press(&"move_up")
	await get_tree().create_timer(1.2, true).timeout
	Input.action_release(&"move_up")
	_expect(not rig.player.global_position.is_equal_approx(origin), "Player movement remains available after delegation.")
	deadline = Time.get_ticks_msec() + 10000
	while rig.runtime.daily.jobs[rig.preset.site_name].stats[STARTUP.APPLICANT_ID].output <= walking_output and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(rig.runtime.daily.now() > walking_start and rig.runtime.daily.jobs[rig.preset.site_name].stats[STARTUP.APPLICANT_ID].output > walking_output, "Native time and laborer production continue while the player leaves the worksite.")
	await _capture("portrait-08-workers-and-player.png")
	rig.set_clock_running(false)
	TimeComponentManager.advance_minutes(60)
	_expect(rig.runtime.hauling.delivered_on_day(STARTUP.HAULER_APPLICANT_ID, 1) > 0, "Hauler delivers produced materials through the stockpile contract.")
	var output: int = rig.runtime.daily.jobs[rig.preset.site_name].stats[STARTUP.APPLICANT_ID].output
	var stored: int = destination.get_storage().quantity
	var cargo: int = rig.runtime.hauling.routes[STARTUP.HAULER_APPLICANT_ID].cargo.quantity
	_expect(output == stored + cargo + rig.runtime._daily_output_count(rig.preset.site_name), "Laborer output is conserved across ground, cart and storage.")
	rig.runtime._open_site_panel(rig.site)
	inspector.progress_button.pressed.emit()
	await _settle()
	_bounds(inspector.progress_panel, "Worker Progress panel")
	await _capture("portrait-09-worker-progress.png")
	inspector.close_requested.emit()
	var save: Node = WorkStateRuntime.get_node("CitySave")
	_expect(save.disk.path.begins_with(rig.SAVE_ROOT + "/session-") and save.save_checkpoint(), "A real checkpoint writes only to the dedicated capture session.")
	for path: String in checkpoint_before:
		var after: Variant = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		_expect(after == checkpoint_before[path], "Normal checkpoint and recovery candidate remain byte-for-byte unchanged: " + path)
	_expect(rig.restart_arguments().has(rig.scene_file_path), "Repeat take launches the same reusable recording scene.")
	_finish()

func _finish() -> void:
	get_tree().paused = false
	print("PortraitCaptureTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
