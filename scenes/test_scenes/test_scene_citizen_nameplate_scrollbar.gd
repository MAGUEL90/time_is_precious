extends Node

const CITIZEN_PANEL_SCENE: PackedScene = preload(
	"res://scenes/ui/citizen_inspection/citizen_inspection_panel.tscn"
)
const GAMEPLAY_THEME: Theme = preload(
	"res://resources/ui_gameplay_theme/ui_gameplay_theme.tres"
)
const NAMEPLATE_TEXTURE: Texture2D = preload(
	"res://assets/ui/ui_panel/panel_name.png"
)
const SATISFACTION_DISPLAY: Script = preload("res://scenes/ui/satisfaction_display.gd")
const WORKER_CONTROL: Script = preload("res://scenes/test_scenes/ui_sandbox/worker_control/worker_control.gd")
const VERTICAL_SCROLLBAR_TEXTURE: Texture2D = preload(
	"res://assets/ui/ui_icon/vertical_scrollbar.png"
)
const NAME_LABEL_PATH: NodePath = NodePath("Root/Frame/Margin/Contents/NameRow/NameLabel")
const BODY_SCROLL_PATH: NodePath = NodePath("Root/Frame/Margin/Contents/BodyScroll")
const INITIAL_WORKSITES = preload("res://scenes/content_scene/startup/initial_worksites.gd")
const INITIAL_WORKSITE_NAMES: Array[String] = [
	INITIAL_WORKSITES.LABORER_NAME,
	INITIAL_WORKSITES.HAULER_NAME,
	INITIAL_WORKSITES.CITY_HAULER_NAME
]

var failures: int = 0
var _panel: CanvasLayer
var _summary: Dictionary = {}
var _closed_count: int = 0
var _capture_directory: String = ""
var _widest_default_name: String = ""


func _ready() -> void:
	_capture_directory = OS.get_environment("TIP_CITIZEN_NAMEPLATE_CAPTURE_DIR")
	var background := ColorRect.new()
	background.color = Color(0.12, 0.16, 0.19, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_panel = CITIZEN_PANEL_SCENE.instantiate() as CanvasLayer
	add_child(_panel)
	_panel.set("summary_provider", Callable(self, "_provide_summary"))
	_panel.connect("closed", Callable(self, "_on_panel_closed"))
	await get_tree().process_frame

	_test_satisfaction_helper_thresholds()
	_test_worker_control_satisfaction_boundaries()
	_panel.visible = true
	await _test_nameplate_style()
	await _test_shared_vertical_scrollbar_style()
	await _test_open_close_and_long_name()
	await _test_default_name_samples()
	await _test_satisfaction_display()

	if failures == 0:
		print("CitizenNameplateScrollbarTest PASSED")
	else:
		print("CitizenNameplateScrollbarTest FAILED: %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _test_nameplate_style() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var name_label: Label = _panel.get_node(NAME_LABEL_PATH) as Label
	var name_plate: TextureRect = name_label.get_node("NamePlate") as TextureRect
	_expect(name_label.get_theme_font_size("font_size") == 6,
		"The citizen name uses the requested six-pixel font with its nameplate.")
	_expect(name_label.size.is_equal_approx(Vector2(42.0, 11.0))
		and name_plate.size.is_equal_approx(Vector2(54.0, 11.0)),
		"The label has 42 px of text room and the supplied nameplate stays at native 54x11 size.")
	_expect(name_plate.texture == NAMEPLATE_TEXTURE and name_plate.show_behind_parent
		and name_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER
		and name_label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER,
		"The supplied plate is behind the center-aligned existing name Label.")
	var name_font: Font = name_label.get_theme_font("font")
	var font_height: float = name_font.get_height(name_label.get_theme_font_size("font_size"))
	var available_text_width: float = name_label.size.x
	var ada_width: float = name_font.get_string_size("Ada", HORIZONTAL_ALIGNMENT_LEFT, -1, name_label.get_theme_font_size("font_size")).x
	var citizen_width: float = name_font.get_string_size("Citizen", HORIZONTAL_ALIGNMENT_LEFT, -1, name_label.get_theme_font_size("font_size")).x
	_expect(font_height <= 7.0 and ada_width <= available_text_width and citizen_width <= available_text_width,
		"Six-pixel font metrics fit short names inside the plate's 42 px text width.")
	print("Nameplate metrics: 54x11 panel, 42 px text width, font6 height=%.2f, Ada=%.2f, Citizen=%.2f px" % [font_height, ada_width, citizen_width])
	_test_default_name_widths(name_font, available_text_width)


func _test_default_name_widths(name_font: Font, available_text_width: float) -> void:
	var names: Array[String] = []
	for generated_name: Variant in CitizenGenerator.display_name_container:
		names.append(str(generated_name))
	names.append_array(INITIAL_WORKSITE_NAMES)
	var widest_name: String = ""
	var widest_name_width: float = 0.0
	_expect(not names.is_empty(), "The default citizen name pool is available to inspect without generating residents.")
	for name: String in names:
		var width: float = name_font.get_string_size(
			name,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			6
		).x
		_expect(not name.strip_edges().is_empty() and name.length() <= 6 and width <= available_text_width,
			"Default/generated name '%s' fits the six-character, 42 px nameplate allowance." % name)
		if width > widest_name_width:
			widest_name = name
			widest_name_width = width
	_widest_default_name = widest_name
	print("Default citizen names at 6 px: widest '%s' measures %.2f/%.2f px" % [
		widest_name,
		widest_name_width,
		available_text_width
	])


func _test_default_name_samples() -> void:
	var names: Array[String] = [_widest_default_name]
	names.append_array(INITIAL_WORKSITE_NAMES)
	for index: int in range(names.size()):
		_summary = {"name": names[index], "evaluated": true, "satisfaction": 0.24}
		_panel.call("open_for", "default-name-sample")
		await get_tree().process_frame
		var name_label: Label = _panel.get_node(NAME_LABEL_PATH) as Label
		_expect(name_label.text == names[index], "The actual nameplate shows its generated/starter name sample.")
		await _capture_at_window_sizes("citizen-default-name-%d" % index, name_label)
		await _assert_name_ink_center(name_label)
		await _assert_nameplate_art_visible(name_label)
	_panel.call("close")


func _assert_name_ink_center(name_label: Label) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var rect: Rect2 = (name_label.get_node("NamePlate") as TextureRect).get_global_rect()
	var min_x: int = image.get_width()
	var max_x: int = -1
	for y: int in range(maxi(0, floori(rect.position.y)), mini(image.get_height(), ceili(rect.end.y))):
		for x: int in range(maxi(0, floori(rect.position.x)), mini(image.get_width(), ceili(rect.end.x))):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r >= 0.94 and pixel.g >= 0.94 and pixel.b >= 0.94 and pixel.a >= 0.9:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	_expect(max_x >= min_x, "Rendered default name has visible text pixels on the nameplate.")
	if max_x >= min_x:
		var ink_center: float = float(min_x + max_x + 1) / 2.0
		_expect(absf(ink_center - rect.get_center().x) <= 0.5,
			"Rendered name '%s' is optically centered within half a logical pixel." % name_label.text)


func _assert_nameplate_art_visible(name_label: Label) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var plate: TextureRect = name_label.get_node("NamePlate") as TextureRect
	var source: Image = NAMEPLATE_TEXTURE.get_image()
	var plate_position: Vector2 = plate.get_global_rect().position
	var origin: Vector2i = Vector2i(roundi(plate_position.x), roundi(plate_position.y))
	for point: Vector2i in [Vector2i(0, 5), Vector2i(1, 5), Vector2i(52, 5), Vector2i(53, 5), Vector2i(4, 0), Vector2i(4, 10)]:
		var actual: Color = image.get_pixelv(origin + point)
		var expected: Color = source.get_pixelv(point)
		_expect(actual.is_equal_approx(expected), "The supplied nameplate's outer pixels remain visible at native size.")


func _assert_long_name_within_text_area(name_label: Label) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var label_rect: Rect2 = name_label.get_global_rect()
	var plate_rect: Rect2 = (name_label.get_node("NamePlate") as TextureRect).get_global_rect()
	var visible_ink: int = 0
	var outside_ink: int = 0
	for y: int in range(floori(plate_rect.position.y), ceili(plate_rect.end.y)):
		for x: int in range(floori(plate_rect.position.x), ceili(plate_rect.end.x)):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r >= 0.94 and pixel.g >= 0.94 and pixel.b >= 0.94 and pixel.a >= 0.9:
				visible_ink += 1
				if not label_rect.has_point(Vector2(x, y)):
					outside_ink += 1
	_expect(visible_ink > 0 and outside_ink == 0,
		"A long name is ellipsized within the 42 px text area without clipping the plate art.")


func _test_shared_vertical_scrollbar_style() -> void:
	_panel.visible = true
	var grabber: StyleBoxTexture = GAMEPLAY_THEME.get_stylebox("grabber", "VScrollBar") as StyleBoxTexture
	var track: StyleBoxFlat = GAMEPLAY_THEME.get_stylebox("scroll", "VScrollBar") as StyleBoxFlat
	var body_scroll: ScrollContainer = _panel.get_node(BODY_SCROLL_PATH) as ScrollContainer
	var panel_scrollbar: VScrollBar = body_scroll.get_v_scroll_bar()
	var inherited_grabber: StyleBoxTexture = panel_scrollbar.get_theme_stylebox("grabber") as StyleBoxTexture
	_expect(is_instance_valid(grabber) and grabber.texture == VERTICAL_SCROLLBAR_TEXTURE
		and grabber.texture_margin_top == 3.0 and grabber.texture_margin_bottom == 3.0,
		"The shared vertical scrollbar uses the supplied thumb art with nine-patch caps.")
	_expect(is_instance_valid(track) and track.bg_color.a > 0.0
		and track.content_margin_left >= 3.0 and track.content_margin_right >= 3.0,
		"The shared vertical scrollbar keeps a readable track and eight-pixel minimum width.")
	_expect(is_instance_valid(inherited_grabber) and inherited_grabber.texture == VERTICAL_SCROLLBAR_TEXTURE
		and body_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO,
		"Citizen inspection inherits the shared scrollbar style and retains automatic vertical scrolling.")
	_expect(is_equal_approx(panel_scrollbar.custom_minimum_size.x, 8.0),
		"The citizen scrollbar keeps its eight-pixel hit width.")

	var body: VBoxContainer = body_scroll.get_node("Body") as VBoxContainer
	for index: int in range(8):
		var spacer := Label.new()
		spacer.name = "ScrollbarTestSpacer%d" % index
		spacer.text = "Row %d" % (index + 1)
		spacer.theme_type_variation = &"HudLabelShortcut"
		spacer.custom_minimum_size.y = 20.0
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(spacer)
	await get_tree().process_frame
	await get_tree().process_frame
	var horizontal_scrollbar: HScrollBar = body_scroll.get_h_scroll_bar()
	var first_test_row: Label = body.get_node("ScrollbarTestSpacer0") as Label
	var shared_font: Font = GAMEPLAY_THEME.get_font("font", "HudLabelShortcut")
	_expect(first_test_row.get_theme_font("font") == shared_font
		and first_test_row.get_theme_font_size("font_size") == 6,
		"Overflow fixture rows use the shared six-pixel HUD font.")
	_expect(not horizontal_scrollbar.visible and body_scroll.scroll_horizontal == 0,
		"Short fixture rows fit the body without creating horizontal scrolling.")
	_expect(panel_scrollbar.visible and panel_scrollbar.max_value > panel_scrollbar.min_value
		and is_equal_approx(panel_scrollbar.size.x, 8.0),
		"Overflow reveals the themed scrollbar with its intended rendered width.")
	if not panel_scrollbar.visible or panel_scrollbar.max_value <= panel_scrollbar.min_value:
		for child: Node in body.get_children():
			if child is Control and child.name.begins_with("ScrollbarTestSpacer"):
				child.queue_free()
		_panel.visible = false
		return
	body_scroll.scroll_vertical = 0
	await get_tree().process_frame
	_expect(is_zero_approx(body_scroll.scroll_vertical),
		"The overflow fixture starts at the top of its scroll range.")
	await _capture_at_window_sizes("citizen-scroll-top", _panel.get_node(NAME_LABEL_PATH) as Label)

	var bottom_value: float = maxf(panel_scrollbar.min_value, panel_scrollbar.max_value - panel_scrollbar.page)
	panel_scrollbar.value = bottom_value
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(is_equal_approx(body_scroll.scroll_vertical, bottom_value),
		"The overflow fixture can reach the bottom of its scroll range.")
	await _capture_at_window_sizes("citizen-scroll-bottom", _panel.get_node(NAME_LABEL_PATH) as Label)

	panel_scrollbar.value = panel_scrollbar.min_value
	await get_tree().process_frame
	var drag_start: Vector2 = panel_scrollbar.get_global_rect().position + Vector2(panel_scrollbar.size.x * 0.5, 5.0)
	var drag_end: Vector2 = panel_scrollbar.get_global_rect().position + Vector2(panel_scrollbar.size.x * 0.5, panel_scrollbar.size.y - 5.0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = drag_start
	press.global_position = drag_start
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = drag_end
	motion.global_position = drag_end
	motion.relative = drag_end - drag_start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = drag_end
	release.global_position = drag_end
	get_viewport().push_input(release, true)
	await get_tree().process_frame
	_expect(panel_scrollbar.value > panel_scrollbar.min_value,
		"Dragging the vertical thumb still changes its scroll value.")

	panel_scrollbar.value = panel_scrollbar.min_value
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = body_scroll.get_global_rect().get_center()
	wheel.global_position = wheel.position
	get_viewport().push_input(wheel, true)
	await get_tree().process_frame
	_expect(panel_scrollbar.value > panel_scrollbar.min_value,
		"Mouse-wheel input still advances an overflowing citizen panel.")

	for child: Node in body.get_children():
		if child is Control and child.name.begins_with("ScrollbarTestSpacer"):
			child.queue_free()
	_panel.visible = false


func _test_open_close_and_long_name() -> void:
	_summary = {"name": "Nabu", "evaluated": true, "satisfaction": 0.24}
	_panel.call("open_for", "resident-one")
	await get_tree().process_frame
	var name_label: Label = _panel.get_node(NAME_LABEL_PATH) as Label
	_expect(_panel.visible and str(_panel.get("selected_id")) == "resident-one"
		and name_label.text == "Nabu",
		"Opening the inspection panel selects the requested resident and updates the name.")
	await _capture_at_window_sizes("citizen-name-short", name_label)

	var long_name: String = "Naram Lugal Ashur Nabu Enkiya Urani Dagan Tammuz Sinbel Iddin"
	_summary["name"] = long_name
	_panel.call("_refresh_view")
	await get_tree().process_frame
	var name_row: Control = name_label.get_parent() as Control
	var frame: Control = _panel.get_node("Root/Frame") as Control
	var long_name_width: float = name_label.get_theme_font("font").get_string_size(
		long_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		name_label.get_theme_font_size("font_size")
	).x
	_expect(name_label.text == long_name and name_label.autowrap_mode == TextServer.AUTOWRAP_OFF
		and name_label.text_overrun_behavior == 4 and long_name_width > name_label.size.x
		and name_label.size.is_equal_approx(Vector2(42.0, 11.0))
		and name_row.get_global_rect().encloses(name_label.get_global_rect())
		and frame.get_global_rect().encloses(name_label.get_global_rect()),
		"A long resident name remains clipped within its existing Label and card bounds.")
	await _capture_at_window_sizes("citizen-name-long", name_label)
	await _assert_long_name_within_text_area(name_label)

	var refresh_timer: Timer = _panel.get_node("RefreshTimer") as Timer
	var timer_connections: int = refresh_timer.get_signal_connection_list("timeout").size()
	_panel.call("open_for", "resident-one")
	_panel.call("open_for", "resident-one")
	_expect(refresh_timer.get_signal_connection_list("timeout").size() == timer_connections
		and refresh_timer.is_stopped() == false,
		"Repeated opens keep one refresh connection and restart the live timer safely.")
	_panel.call("close")
	_expect(not _panel.visible and str(_panel.get("selected_id")).is_empty() and _closed_count == 1,
		"Closing the citizen panel clears selection and emits one close signal.")
	_summary["name"] = "Ashur"
	_panel.call("open_for", "resident-two")
	await get_tree().process_frame
	_expect(_panel.visible and str(_panel.get("selected_id")) == "resident-two"
		and name_label.text == "Ashur" and not refresh_timer.is_stopped(),
		"The panel reopens for another resident with fresh content and its timer running.")
	_panel.call("close")
	_expect(_closed_count == 2,
		"A second open-close cycle emits exactly one additional close signal.")


func _test_satisfaction_display() -> void:
	var satisfaction_label: Label = _panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/SatisfactionLabel") as Label
	var satisfaction_bar: TextureProgressBar = _panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/SatisfactionBar") as TextureProgressBar
	_summary["satisfaction"] = 0.001
	_panel.call("open_for", "resident-satisfaction")
	await get_tree().process_frame
	var body: Control = satisfaction_bar.get_parent() as Control
	_expect(satisfaction_bar.texture_under == load("res://assets/ui/ui_icon/empty_bar.png")
		and satisfaction_bar.texture_progress == load("res://assets/ui/ui_icon/filled_bar.png")
		and satisfaction_bar.tint_progress.is_equal_approx(Color.WHITE),
		"Satisfaction uses the existing empty and filled bar art without a color tint.")
	_expect(satisfaction_bar.size.is_equal_approx(Vector2(46.0, 7.0))
		and absf(satisfaction_bar.get_global_rect().get_center().x - body.get_global_rect().get_center().x) <= 0.5,
		"Satisfaction displays the supplied 46x7 bar centered at native size.")
	_expect(satisfaction_label.text == "Actual satisfaction: 1%"
		and is_equal_approx(satisfaction_bar.value, 0.1),
		"A positive sub-one-percent value displays as 1% while its exact bar value is preserved.")
	_summary["satisfaction"] = 0.0
	_panel.call("_refresh_view")
	_expect(satisfaction_label.text == "Actual satisfaction: 0%" and satisfaction_bar.value == 0.0,
		"Zero satisfaction remains 0% with an empty bar.")
	await _capture_window("citizen-satisfaction-0")
	_summary["satisfaction"] = 0.24
	_panel.call("_refresh_view")
	_expect(satisfaction_label.text == "Actual satisfaction: 24%"
		and is_equal_approx(satisfaction_bar.value, 24.0),
		"Ordinary satisfaction percentages and their bar values remain unchanged.")
	await _capture_window("citizen-satisfaction-24")
	_summary["satisfaction"] = 1.0
	_panel.call("_refresh_view")
	_expect(satisfaction_label.text == "Actual satisfaction: 100%" and satisfaction_bar.value == 100.0,
		"Full satisfaction displays a filled bar and 100%.")
	await _capture_window("citizen-satisfaction-100")
	_panel.call("close")


func _test_satisfaction_helper_thresholds() -> void:
	_expect(SATISFACTION_DISPLAY.to_percent(0.0) == 0,
		"Exact zero satisfaction remains zero percent.")
	_expect(SATISFACTION_DISPLAY.to_percent(0.0001) == 1
		and SATISFACTION_DISPLAY.to_percent(0.0099) == 1,
		"Positive satisfaction below one percent displays as one percent.")
	_expect(SATISFACTION_DISPLAY.to_percent(0.01) == 1
		and SATISFACTION_DISPLAY.to_percent(0.24) == 24
		and SATISFACTION_DISPLAY.to_percent(1.0) == 100,
		"The shared formatter keeps existing rounding at normal values and the one-percent boundary.")


func _test_worker_control_satisfaction_boundaries() -> void:
	var control: Node = WORKER_CONTROL.new()
	for sample: Array in [[0.0, 0], [0.000001, 1], [0.0049, 1], [0.0099, 1], [0.01, 1], [0.015, 2], [1.0, 100]]:
		var needs: Dictionary = {"satisfaction": sample[0], "evaluated": true, "satisfaction_delta": -0.015}
		var actual: String = control.call("_format_satisfaction_text", needs)
		_expect(actual == "Satisfaction: %d%% current (check -2%%)" % int(sample[1]),
			"Worker details show the correct current satisfaction without changing daily delta rounding.")
	control.free()


func _capture_at_window_sizes(prefix: String, name_label: Label) -> void:
	var window_sizes: Array[Vector2i] = [Vector2i(400, 225), Vector2i(1200, 675)]
	for requested_size: Vector2i in window_sizes:
		get_window().size = requested_size
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		_assert_margin_bounds(name_label)
		await _capture_window("%s-%dx%d" % [prefix, requested_size.x, requested_size.y])


func _assert_margin_bounds(name_label: Label) -> void:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var frame: Control = _panel.get_node("Root/Frame") as Control
	var frame_rect: Rect2 = frame.get_global_rect()
	var contents: Control = _panel.get_node("Root/Frame/Margin/Contents") as Control
	var contents_rect: Rect2 = contents.get_global_rect()
	var name_row: Control = name_label.get_parent() as Control
	var name_plate: TextureRect = name_label.get_node("NamePlate") as TextureRect
	var close_button: Control = _panel.get_node("Root/Frame/Margin/Contents/NameRow/CloseButton") as Control
	var body_scroll: ScrollContainer = _panel.get_node(BODY_SCROLL_PATH) as ScrollContainer
	var scrollbar: VScrollBar = body_scroll.get_v_scroll_bar()
	var margin_left: float = contents_rect.position.x - frame_rect.position.x
	var margin_right: float = frame_rect.end.x - contents_rect.end.x
	var margin_top: float = contents_rect.position.y - frame_rect.position.y
	var margin_bottom: float = frame_rect.end.y - contents_rect.end.y
	_expect(viewport_rect.size.is_equal_approx(Vector2(400.0, 225.0))
		and viewport_rect.encloses(frame_rect)
		and is_equal_approx(frame_rect.size.x, 160.0)
		and is_equal_approx(frame_rect.size.y, 104.0)
		and absf(viewport_rect.end.x - frame_rect.end.x - 8.0) <= 0.5
		and absf(frame_rect.get_center().y - viewport_rect.get_center().y) <= 0.5,
		"The card stays inside the 400×225 logical viewport with its 8 px right inset and centered 160×104 frame.")
	_expect(absf(margin_left - 14.0) <= 0.5 and absf(margin_right - 14.0) <= 0.5
		and absf(margin_top - 9.0) <= 0.5 and absf(margin_bottom - 9.0) <= 0.5,
		"The frame keeps its measured 14 px side and 9 px vertical content margins.")
	_expect(frame_rect.encloses(name_row.get_global_rect())
		and name_row.get_global_rect().encloses(name_label.get_global_rect())
		and name_label.size.is_equal_approx(Vector2(42.0, 11.0))
		and name_plate.size.is_equal_approx(Vector2(54.0, 11.0))
		and name_row.get_global_rect().encloses(name_plate.get_global_rect())
		and name_plate.get_global_rect().encloses(name_label.get_global_rect())
		and absf(name_plate.get_global_rect().get_center().x - frame_rect.get_center().x) <= 0.5
		and name_row.get_global_rect().encloses(close_button.get_global_rect())
		and not name_plate.get_global_rect().intersects(close_button.get_global_rect())
		and frame_rect.encloses(body_scroll.get_global_rect())
		and contents_rect.encloses(body_scroll.get_global_rect())
		and (not scrollbar.visible or body_scroll.get_global_rect().encloses(scrollbar.get_global_rect())),
		"The name, close button, scroll viewport, and visible scrollbar stay within their parent margins without overlap.")


func _capture_window(filename: String) -> void:
	if _capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(_capture_directory)
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	print("Nameplate UI capture %s: logical render %s, window %s" % [filename, image.get_size(), get_window().size])
	_expect(image.get_size() == Vector2i(400, 225),
		"The captured viewport render stays at the configured 400×225 logical size: " + filename)
	var logical_path: String = _capture_directory.path_join(filename + "-logical400x225.png")
	var error: Error = image.save_png(logical_path)
	_expect(error == OK, "Rendered logical UI screenshot is saved: " + filename)
	if get_window().size == Vector2i(1200, 675) and image.get_size() != get_window().size:
		var scaled_preview: Image = image.duplicate()
		scaled_preview.resize(1200, 675, Image.INTERPOLATE_NEAREST)
		var preview_path: String = _capture_directory.path_join(filename + "-nearest-preview1200x675.png")
		error = scaled_preview.save_png(preview_path)
		_expect(error == OK, "The 3× nearest-neighbor window-scale preview is saved: " + filename)


func _provide_summary(_person_id: String) -> Dictionary:
	return _summary


func _on_panel_closed() -> void:
	_closed_count += 1


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
