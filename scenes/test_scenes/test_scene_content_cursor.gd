extends Node

const CURSOR_SCRIPT: Script = preload("res://scenes/ui/cursor/gameplay_cursor.gd")
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	var image: Image = CURSOR_SCRIPT.CURSOR.get_image()
	_expect(image.get_size() == Vector2i(32, 32), "Owner cursor retains its native 32x32 dimensions.")
	_expect(image.get_used_rect() == Rect2i(2, 1, 28, 30), "Owner cursor alpha bounds are preserved.")
	_expect(CURSOR_SCRIPT.visible_hotspot(image) == Vector2(6, 1), "Hotspot follows the owner's visible cursor tip.")
	_expect(CURSOR_SCRIPT.native_size_supported(image), "Owner cursor fits the native size limit.")
	_expect(CURSOR_SCRIPT.SHAPES == [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND, Input.CURSOR_IBEAM],
		"Arrow, pointing hand, and text fields use the same artwork.")
	var padded := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	padded.fill(Color.TRANSPARENT)
	padded.set_pixel(7, 3, Color.WHITE)
	padded.set_pixel(1, 4, Color.WHITE)
	_expect(CURSOR_SCRIPT.visible_hotspot(padded) == Vector2(7, 3), "Transparent padding does not move the pointing hotspot.")
	padded.fill(Color.TRANSPARENT)
	_expect(CURSOR_SCRIPT.visible_hotspot(padded) == Vector2(-1, -1), "Fully transparent artwork cannot install an invisible cursor.")
	var at_limit := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var too_wide := Image.create(257, 16, false, Image.FORMAT_RGBA8)
	var too_tall := Image.create(16, 257, false, Image.FORMAT_RGBA8)
	_expect(CURSOR_SCRIPT.native_size_supported(at_limit), "Native maximum dimensions are accepted.")
	_expect(not CURSOR_SCRIPT.native_size_supported(too_wide) and not CURSOR_SCRIPT.native_size_supported(too_tall),
		"Oversized artwork is rejected on either axis without resizing.")
	_expect(not CURSOR_SCRIPT.native_size_supported(null) and not CURSOR_SCRIPT.native_size_supported(Image.new()),
		"Missing or empty artwork is rejected.")
	for _index: int in range(2):
		var gameplay_owner := Node.new()
		add_child(gameplay_owner)
		var previous_mode: Input.MouseMode = Input.mouse_mode
		var cursor = CURSOR_SCRIPT.new()
		gameplay_owner.add_child(cursor)
		_expect(cursor.cursor_image.get_size() == image.get_size() and cursor.cursor_hotspot == Vector2(6, 1),
			"Each gameplay owner prepares the native image and hotspot, including after a transition.")
		if DisplayServer.get_name() == "headless":
			_expect(not cursor.cursor_applied and Input.mouse_mode == previous_mode,
				"Headless lifecycle skips native cursor and mouse mode changes.")
		else:
			_expect(cursor.cursor_applied, "Native cursor installs while gameplay is active.")
		remove_child(gameplay_owner)
		_expect(not cursor.cursor_applied and Input.mouse_mode == previous_mode,
			"Leaving gameplay clears the cursor and restores the previous mouse mode.")
		gameplay_owner.free()
	print("CONTENT_CURSOR_TEST: %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(0 if failures == 0 else 1)
