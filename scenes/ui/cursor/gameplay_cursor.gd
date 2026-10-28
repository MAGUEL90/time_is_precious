extends Node

# A child of each gameplay Player: city/home transitions install a fresh cursor,
# and leaving gameplay restores the native defaults without an autoload.
const CURSOR: Texture2D = preload("res://assets/ui/ui_icon/cursors/mouse_icon.png")
const MAX_NATIVE_CURSOR_SIZE: int = 256
const SHAPES: Array[int] = [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND, Input.CURSOR_IBEAM]

var cursor_image: Image
var cursor_hotspot: Vector2 = Vector2(-1, -1)
var cursor_texture: ImageTexture
var cursor_applied: bool = false
var previous_mouse_mode: Input.MouseMode


func _ready() -> void:
	cursor_image = CURSOR.get_image()
	if not native_size_supported(cursor_image):
		push_warning("Gameplay cursor must be nonempty and within the native 256x256 limit; artwork was not resized.")
		return
	cursor_hotspot = visible_hotspot(cursor_image)
	if cursor_hotspot.x < 0.0:
		push_warning("Gameplay cursor has no visible pixels; native defaults were retained.")
		return
	if DisplayServer.get_name() == "headless":
		return
	previous_mouse_mode = Input.mouse_mode
	# Preserve the PNG's native pixel dimensions regardless of viewport scaling.
	cursor_texture = ImageTexture.create_from_image(cursor_image)
	for shape: int in SHAPES:
		Input.set_custom_mouse_cursor(cursor_texture, shape, cursor_hotspot)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cursor_applied = true


static func native_size_supported(image: Image) -> bool:
	return (
		image != null
		and not image.is_empty()
		and image.get_width() <= MAX_NATIVE_CURSOR_SIZE
		and image.get_height() <= MAX_NATIVE_CURSOR_SIZE
	)


static func visible_hotspot(image: Image) -> Vector2:
	# The artwork points from its topmost opaque edge, not from its padding.
	if image != null:
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				if image.get_pixel(x, y).a > 0.0:
					return Vector2(x, y)
	return Vector2(-1, -1)


func _exit_tree() -> void:
	if not cursor_applied:
		return
	for shape: int in SHAPES:
		Input.set_custom_mouse_cursor(null, shape)
	Input.mouse_mode = previous_mouse_mode
	cursor_applied = false
