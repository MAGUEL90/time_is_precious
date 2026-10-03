extends Node2D

## Short, cosmetic pixel puff. No shared RNG or gameplay clock mutations.
var elapsed: float = 0.0
const LIFETIME: float = 0.55

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 5
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= LIFETIME:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	var progress: float = clampf(elapsed / LIFETIME, 0.0, 1.0)
	for i in range(8):
		var angle: float = float(i) * TAU / 8.0
		var offset := Vector2(cos(angle) * 9.0, sin(angle) * 4.0) * progress
		offset.y -= progress * 5.0
		var tint := Color("c4ab76") if i % 2 == 0 else Color("9d8254")
		tint.a = 1.0 - progress
		draw_rect(Rect2(offset.round(), Vector2(3, 3) if progress < 0.5 else Vector2(2, 2)), tint)
