extends Node

## F6 entrypoint; retains a small recording rig beside the real current_scene.
## Never reads the player's checkpoint. Each process gets its own capture slot.
signal capture_ready
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const STARTUP = preload("res://scenes/content_scene/startup/initial_worksites.gd")
const THEME: Theme = preload("res://resources/ui_gameplay_theme/ui_gameplay_theme.tres")
const CAPTURE_FONT: Font = preload("res://assets/font/pixel_rpg.ttf")
const CAPTURE_FONT_SIZE: int = 6
const LOGICAL_SIZE: Vector2i = Vector2i(360, 640)
const OUTPUT_SIZE: Vector2i = Vector2i(1080, 1920)
const SAVE_ROOT: String = "user://content_capture"
@export var preset: Resource

var content: Node
var player: Player
var runtime: Node2D
var site: Marker2D
var camera: Camera2D
var clock_label: Label
var debug: CanvasLayer
var ready_for_capture: bool = false
var clock_running: bool = false
var follow_player: bool = false
var session_path: String
var _busy: bool = false
var _capture_count: int = 0
var _styling_text: bool = false

func _ready() -> void:
	_start.call_deferred()

func _start() -> void:
	if not OS.is_debug_build() or get_tree().current_scene != self:
		push_error("Run portrait_capture.tscn directly in a fresh debug process (F6).")
		return
	if not WorkerDatabase.get_all_workers().is_empty() or not Inventory.items.is_empty() or WorkStateRuntime.has_node("CitySave"):
		push_error("Capture requires a fresh process; existing session was preserved.")
		return
	if preset == null or preset.recording_speed not in [1, 10, 60]:
		push_error("Capture requires a preset with a supported native clock speed (1, 10, 60).")
		return
	get_tree().paused = true
	var window: Window = get_window()
	window.content_scale_size = LOGICAL_SIZE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.size = LOGICAL_SIZE * preset.preview_scale
	window.title = "Time is Precious — Portrait Capture"
	session_path = SAVE_ROOT.path_join("session-%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()])
	# Initial state uses a clock broadcast, never elapsed-time/day settlement.
	TimeComponentManager.set_process(false)
	TimeComponentManager.current_hour = preset.start_hour
	TimeComponentManager.current_minute = 0
	TimeComponentManager.emit_time_signal()
	TimeComponentManager.day_cycle(true)
	content = CONTENT.instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	player = content.get_node("YSortWorld/Player")
	runtime = content.get_node("YSortWorld/WorkerRuntime")
	site = runtime.get_node_or_null("WorksiteMarkers/" + str(preset.site_name))
	if site == null:
		push_error("Capture preset site is absent from the authored map.")
		get_tree().paused = false
		return
	for frame in range(3):
		await get_tree().process_frame
	# CitySave has now been bound by the existing RaidBootstrap. No sleep has run.
	var save: Node = WorkStateRuntime.get_node("CitySave")
	save.disk.path = session_path.path_join("checkpoint_v1.json")
	# Older local stores start fresh and observe the new disk path on first save.
	if save.has_method("refresh_checkpoint_slot"):
		save.refresh_checkpoint_slot()
	if not _prepare_cast():
		push_error("Capture cast could not be prepared through the existing hiring/equipment APIs.")
		get_tree().paused = false
		return
	_apply_site_focus()
	_hide_capture_home()
	get_tree().node_added.connect(_capture_node_added)
	_style_capture_tree(get_tree().root)
	player.fatigue = preset.initial_fatigue
	player.hunger = 0.0
	player.focus = 1.0
	player.global_position = site.global_position + Vector2(0, 12)
	player.condition_changed.emit()
	runtime.get_node("WorkerVisuals").rng.seed = preset.visual_seed
	# Same starting random stream, retaining the native weather/visitor rolls.
	seed(preset.visual_seed)
	debug = content.get_node("TimeDebugOverlay")
	debug.hide()
	debug.set_speed(1)
	camera = Camera2D.new()
	camera.name = "CaptureCamera"
	camera.zoom = Vector2.ONE * preset.camera_zoom
	add_child(camera)
	player.get_node("Camera2D").enabled = false
	camera.global_position = site.global_position + preset.camera_offset
	camera.make_current()
	_create_clock()
	set_clock_running(false)
	get_tree().paused = false
	ready_for_capture = true
	print("Portrait capture ready. Space: clock hold/run; F5: x1/x%d; F4: overnight preparation; 1/2: camera; F8: PNG; R: fresh process." % preset.recording_speed)
	print("Capture-only checkpoint: " + ProjectSettings.globalize_path(save.disk.path))
	capture_ready.emit()

func _hide_capture_home() -> void:
	# Keep the authored node and save paths. Capture uses F4's native player sleep.
	var door: Area2D = content.get_node("YSortWorld/HomeDoor")
	door.hide()
	door.monitoring = false
	door.monitorable = false
	door.process_mode = Node.PROCESS_MODE_DISABLED
	door.get_node("CollisionShape2D").set_deferred("disabled", true)

func _capture_node_added(node: Node) -> void:
	# UI builders set their local overrides during _ready(); apply after that.
	if node is Control or node is Window:
		_capture_style_id.call_deferred(node.get_instance_id())

func _capture_style_id(id: int) -> void:
	# A menu can replace its rows before the deferred styling pass runs.
	var node: Object = instance_from_id(id)
	if is_instance_valid(node) and node is Node:
		_capture_text_style(node)

func _style_capture_tree(node: Node) -> void:
	_capture_text_style(node)
	for child: Node in node.get_children(true):
		_style_capture_tree(child)

func _capture_text_style(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or _styling_text:
		return
	if not node is Control and not node is Window:
		return
	_styling_text = true
	# Per-instance overrides also cover popup Windows; shared gameplay themes stay intact.
	var themed: Variant = node
	var font_keys: Array[String] = ["font"]
	var size_keys: Array[String] = ["font_size"]
	if node is RichTextLabel:
		font_keys.append_array(["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"])
		size_keys.append_array(["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"])
	for key: String in font_keys:
		if themed.get_theme_font(key) != CAPTURE_FONT:
			themed.add_theme_font_override(key, CAPTURE_FONT)
	for key: String in size_keys:
		if themed.get_theme_font_size(key) != CAPTURE_FONT_SIZE:
			themed.add_theme_font_size_override(key, CAPTURE_FONT_SIZE)
	if node is Label or node is Button or node is RichTextLabel:
		if themed.get_theme_constant("outline_size") != 0:
			themed.add_theme_constant_override("outline_size", 0)
	if _capture_world_label(node):
		# Counter the capture camera zoom: the same six-pixel text as screen UI.
		themed.scale = Vector2.ONE / preset.camera_zoom
		themed.pivot_offset = themed.size * 0.5
		if node.name == &"CargoLabel":
			# Native cargo text starts to the right of the cart; center it above instead.
			themed.pivot_offset = Vector2.ZERO
			themed.position = Vector2(-themed.size.x * themed.scale.x * 0.5, -24)
	var changed: Callable = _capture_text_style.bind(node)
	if not node.is_connected("theme_changed", changed):
		node.connect("theme_changed", changed)
	if node is Label and _capture_world_label(node) and not node.is_connected("resized", changed):
		node.connect("resized", changed)
	_styling_text = false

func _capture_world_label(node: Node) -> bool:
	if not node is Label:
		return false
	var ancestor: Node = node.get_parent()
	while ancestor != null:
		if ancestor is CanvasLayer:
			return false
		if ancestor == content.get_node("YSortWorld"):
			return true
		ancestor = ancestor.get_parent()
	return false

func _apply_site_focus() -> void:
	if not preset.focus_site_only:
		return
	# Hide presentation only. All native site sessions, destinations and collision
	# shapes remain registered so delivery, scheduling and checkpoint data stay intact.
	for marker: Marker2D in runtime.get_node("WorksiteMarkers").get_children():
		marker.visible = marker == site
	var destination: Node = runtime._storage_destination(site.name)
	for site_id: StringName in runtime.storage_destinations:
		var stockpile: CanvasItem = runtime._storage_destination(site_id)
		if is_instance_valid(stockpile):
			stockpile.visible = stockpile == destination
	var city_storage: CanvasItem = runtime.get_node_or_null("CityStorageArea")
	if city_storage != null:
		city_storage.hide()

func _prepare_cast() -> bool:
	var board: JobBoard = content.get_node("YSortWorld/InitialWorksites/JobBoard")
	for id: String in [STARTUP.APPLICANT_ID, STARTUP.HAULER_APPLICANT_ID]:
		if WorkerDatabase.hire_applicant(id, board.default_daily_wage) == null:
			return false
	runtime.worker_management.equip(STARTUP.HAULER_APPLICANT_ID, STARTUP.CART_UNIT_ID)
	if not runtime.city_tools.has_equipped(STARTUP.HAULER_APPLICANT_ID, "cart"):
		return false
	if not Inventory.try_add_item("shekel", preset.personal_shekel) or not Inventory.try_add_item(preset.food_item, preset.personal_food):
		return false
	# A physical one-day supply prevents a fixture-only midnight needs shortage.
	var residents: int = CitizenManager.get_all_residents().size()
	if not runtime.city_tools.try_add_item(preset.food_item, residents) or not runtime.city_tools.try_add_item("simple_clothes", residents):
		return false
	CityStockManager.add_shekel(preset.personal_shekel)
	if CityStockManager.shelter_capacity < residents:
		CityStockManager.add_shelter_capacity(residents - CityStockManager.shelter_capacity)
	return true

func _create_clock() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	clock_label = Label.new()
	clock_label.position = Vector2(12, 30)
	clock_label.size = Vector2(336, 24)
	clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_label.theme = THEME
	clock_label.add_theme_font_override("font", CAPTURE_FONT)
	clock_label.add_theme_font_size_override("font_size", CAPTURE_FONT_SIZE)
	clock_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	clock_label.add_theme_constant_override("shadow_offset_x", 1)
	clock_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(clock_label)

func _process(_delta: float) -> void:
	if not ready_for_capture:
		return
	if follow_player and is_instance_valid(player):
		camera.global_position = player.global_position + Vector2(0, -16)
	# Clock hold stops elapsed minutes, but the native time-of-day tint must settle.
	if not clock_running and not get_tree().paused and not TimeComponentManager.is_paused:
		TimeComponentManager.environment.color = TimeComponentManager.environment.color.lerp(
			TimeComponentManager._target_environment_color, 1.0 - exp(-TimeComponentManager.env_transition_speed * _delta))
	clock_label.text = "Day %d  %02d:%02d  %s" % [TimeComponentManager.current_day, TimeComponentManager.current_hour,
		TimeComponentManager.current_minute, "x%d" % (debug.get_effective_speed() if is_instance_valid(debug) else 1) if clock_running else "HOLD"]

func set_clock_running(running: bool) -> void:
	clock_running = running
	TimeComponentManager.set_process(running)
	if is_instance_valid(debug):
		debug.set_process(running)

func _input(event: InputEvent) -> void:
	if not ready_for_capture or _busy or not event is InputEventKey or not event.pressed or event.echo:
		return
	# Keep native number/name editing intact while recording shortcuts are active.
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	match event.keycode:
		KEY_SPACE:
			set_clock_running(not clock_running)
		KEY_F5:
			if is_instance_valid(debug):
				debug.set_speed(preset.recording_speed if debug.speed_multiplier == 1 else 1)
		KEY_1:
			follow_player = false
			if is_instance_valid(site):
				camera.global_position = site.global_position + preset.camera_offset
		KEY_2:
			follow_player = true
		KEY_F4:
			prepare_next_shift()
		KEY_F8:
			save_portrait()
		KEY_R:
			if OS.create_instance(restart_arguments()) > 0:
				get_tree().quit()
		_:
			return
	get_viewport().set_input_as_handled()

func restart_arguments() -> PackedStringArray:
	return PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--scene", scene_file_path])

func prepare_next_shift() -> bool:
	if _busy or not is_instance_valid(runtime) or not is_instance_valid(player) or not runtime._can_open_worker_hub() or not runtime.daily.jobs.has(preset.site_name):
		print("Capture prep refused: stay in the content map, close menus and commit a Daily plan first.")
		return false
	var starts: Array = runtime.daily.jobs[preset.site_name].starts.values()
	var target: int = int(starts.min()) - 15
	var now: int = runtime.daily.now()
	if target <= now or not player.can_sleep() or now + player.sleep_duration_minutes > target:
		print("Capture prep refused: native sleep cannot fit before the next committed shift; repeat the take with R.")
		return false
	_busy = true
	set_clock_running(false)
	# Existing seven-hour sleep and minute signals retain costs, day settlement and wages.
	var rested: bool = await SceneTransition.run_with_fade(Callable(player, "sleep"))
	if rested:
		# Eat after waking, before the remaining wait can reach the native hunger guard.
		await content.get_node("InventoryUI")._execute_use_item(preset.food_item, 3)
		while runtime.daily.now() < target and player.can_move and not player.has_critical_condition():
			TimeComponentManager.advance_minutes(1)
	_busy = false
	var prepared: bool = rested and runtime.daily.now() == target
	print("Capture prep ready: next day 06:45. Resume with Space." if prepared else "Capture prep stopped by native conditions. Repeat the take with R.")
	return prepared

func save_portrait() -> String:
	if DisplayServer.get_name() == "headless":
		push_warning("Portrait PNG requires a graphical renderer.")
		return ""
	await RenderingServer.frame_post_draw
	var picture: Image = get_viewport().get_texture().get_image()
	picture.resize(OUTPUT_SIZE.x, OUTPUT_SIZE.y, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(session_path)
	_capture_count += 1
	var path: String = session_path.path_join("shot-%02d.png" % _capture_count)
	if picture.save_png(path) != OK:
		return ""
	print("Portrait PNG: " + ProjectSettings.globalize_path(path))
	return ProjectSettings.globalize_path(path)
