extends Node2D

## Keep the completed bar intact: a small bounce, highlight, then fade.
var texture: Texture2D
var under_texture: Texture2D
var display_size := Vector2(46, 7)
var elapsed: float = 0.0
var _completed_texture: ImageTexture
const LIFETIME: float = 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 11
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Fade the finished silhouette once, not two translucent overlapping layers.
	var completed_image: Image = under_texture.get_image()
	var fill_image: Image = texture.get_image()
	completed_image.convert(Image.FORMAT_RGBA8)
	fill_image.convert(Image.FORMAT_RGBA8)
	completed_image.blend_rect(fill_image, Rect2i(Vector2i.ZERO, fill_image.get_size()), Vector2i.ZERO)
	_completed_texture = ImageTexture.create_from_image(completed_image)
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= LIFETIME:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	# An exact zero avoids tiny negative sin(PI) offsets crossing a pixel boundary.
	var pulse: float = sin(PI * elapsed / 0.35) if elapsed < 0.35 else 0.0
	var opacity: float = 1.0 - smoothstep(0.35, 0.85, elapsed)
	var brightness: float = 1.0 + 0.4 * pulse
	var rect := Rect2(Vector2.ZERO, display_size)
	# Keep texels 1:1. Fractional scaling resamples a seven-pixel-high bar
	# unevenly; a half-pixel centered origin also disagrees with pixel snapping.
	draw_set_transform(Vector2(0, roundf(-3.0 * pulse)))
	draw_texture_rect(_completed_texture, rect, false, Color(brightness, brightness, brightness, opacity))
	draw_set_transform(Vector2.ZERO)
