extends Node2D

## Checks the real scene label and feedback without loading or writing a save.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const BED: PackedScene = preload("res://scenes/sleep_spot/sleep_spot.tscn")
const PLAYER: PackedScene = preload("res://scenes/player/player.tscn")
const FONT_PATH: String = "res://assets/font/pixel_rpg.ttf"
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _check_font(label: Label, text: String, bounds: Vector2) -> void:
	var font: Font = label.get_theme_font("font")
	_expect(font != null and font.resource_path == FONT_PATH, text + ": uses the supplied pixel font")
	_expect(label.get_theme_font_size("font_size") == 6, text + ": retains size 6")
	if font != null:
		_expect(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x <= bounds.x,
			text + ": fits the existing label width")
		_expect(font.get_height(6) <= bounds.y, text + ": fits the existing label height")


func _run() -> void:
	# The map is instantiated off-tree: only its real label is attached to this fixture.
	var content: Node = CONTENT.instantiate()
	var door: Node2D = content.get_node("YSortWorld/HomeDoor") as Node2D
	var door_label: Label = door.get_node("Label") as Label
	_expect(door.position == Vector2(-256, -478), "The HomeDoor map position remains unchanged")
	_expect(door_label.offset_left == -26.0 and door_label.offset_top == 5.0
		and door_label.offset_right == 26.0 and door_label.offset_bottom == 15.0,
		"The HomeDoor label keeps its authored offsets")
	door.remove_child(door_label)
	door_label.owner = null
	add_child(door_label)
	content.free()
	_expect(door_label.text == "Sleep", "The HomeDoor text remains unchanged")
	_check_font(door_label, door_label.text, Vector2(52, 10))

	# A disabled real player satisfies SleepSpot's normal signal setup; no sleep occurs.
	var player: Player = PLAYER.instantiate() as Player
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.collision_layer = 0
	add_child(player)
	var bed: SleepSpot = BED.instantiate() as SleepSpot
	add_child(bed)
	var feedback: Label = bed.get_node("SaveFeedback") as Label
	# Match the original pre-change construction to compare Godot's effective
	# control bounds, which may be larger than the size requested while off-tree.
	var baseline := Label.new()
	baseline.theme = preload("res://resources/ui_gameplay_theme/ui_gameplay_theme.tres")
	baseline.add_theme_font_size_override("font_size", 6)
	baseline.add_theme_color_override("font_shadow_color", Color(0.20, 0.14, 0.10))
	baseline.add_theme_constant_override("shadow_offset_x", 1)
	baseline.add_theme_constant_override("shadow_offset_y", 1)
	baseline.position = Vector2(-48, -24)
	baseline.size = Vector2(96, 10)
	baseline.hide()
	bed.add_child(baseline)
	# Player._ready() schedules its cursor node; let it attach before cleanup.
	await get_tree().process_frame
	print("Sleep feedback bounds: pixel=", feedback.position, "/", feedback.size,
		" baseline=", baseline.position, "/", baseline.size)
	_expect(feedback.position == Vector2(-48, -24) and feedback.size == baseline.size,
		"The sleep feedback retains the effective bounds of the original construction")
	baseline.free()
	_expect(feedback.get_theme_color("font_shadow_color") == Color(0.20, 0.14, 0.10),
		"The existing feedback shadow color remains in place")
	_expect(feedback.get_theme_constant("shadow_offset_x") == 1 and feedback.get_theme_constant("shadow_offset_y") == 1,
		"The existing feedback shadow offsets remain in place")
	door_label.position = Vector2(36, 48)
	bed.position = Vector2(-100, -20)
	for message: String in ["Game saved", "Save failed", "Already rested today"]:
		bed._show_save_feedback(message)
		_expect(feedback.visible and feedback.text == message, message + ": is still shown")
		_check_font(feedback, message, Vector2(96, 10))
		if not OS.get_environment("TIP_SLEEP_FONT_CAPTURE_DIR").is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var directory: String = OS.get_environment("TIP_SLEEP_FONT_CAPTURE_DIR")
			DirAccess.make_dir_recursive_absolute(directory)
			var name: String = message.to_lower().replace(" ", "-") + ".png"
			_expect(get_viewport().get_texture().get_image().save_png(directory.path_join(name)) == OK,
				message + ": visual evidence captured")
	bed.free()
	player.free()
	door_label.free()
	print("SleepPixelFontTest %s" % ("PASSED" if failures == 0 else "FAILED: %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)
