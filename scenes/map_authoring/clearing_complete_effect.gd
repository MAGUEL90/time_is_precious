extends Node2D

## Short presentation only: the actual plot changes state independently.
const DURATION: float = 0.9
const DUST_COLORS: Array[Color] = [Color("c4ab76"), Color("9d8254")]
const DUST_ORIGINS: Array[Vector2] = [
	Vector2(-14, 6), Vector2(-9, 10), Vector2(-4, 5), Vector2(1, 9),
	Vector2(7, 5), Vector2(13, 9), Vector2(-11, -1), Vector2(10, -2),
]

var elapsed: float = 0.0
var rubble: Sprite2D
var original_color: Color

func configure(source: Sprite2D) -> void:
	transform = source.transform
	z_index = source.z_index + 1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	original_color = source.modulate
	rubble = Sprite2D.new()
	rubble.texture = source.texture
	rubble.centered = source.centered
	rubble.offset = source.offset
	rubble.flip_h = source.flip_h
	rubble.flip_v = source.flip_v
	rubble.region_enabled = source.region_enabled
	rubble.region_rect = source.region_rect
	rubble.modulate = original_color
	rubble.self_modulate = source.self_modulate
	rubble.material = source.material
	rubble.z_index = -1
	add_child(rubble)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= DURATION:
		queue_free()
		return
	rubble.modulate.a = original_color.a * (1.0 - smoothstep(0.15, 0.72, elapsed))
	queue_redraw()

func _draw() -> void:
	var progress: float = clampf(elapsed / DURATION, 0.0, 1.0)
	var opacity: float = 1.0 - smoothstep(0.35, 1.0, progress)
	for i: int in range(DUST_ORIGINS.size()):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var point: Vector2 = DUST_ORIGINS[i] + Vector2(side * 4.0 * progress, -7.0 * progress)
		var color: Color = DUST_COLORS[i % DUST_COLORS.size()]
		color.a = opacity
		var size: float = 3.0 if progress < 0.55 else 2.0
		draw_rect(Rect2(point.round(), Vector2(size, size)), color)
