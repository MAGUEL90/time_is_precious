extends StaticBody2D

## Exterior feet area only. Local walls never clamp the player in Nightmare.
@export var walkable_rect := Rect2(24, -232, 336, 208)
const WALL_THICKNESS: float = 16.0

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var a: Vector2 = walkable_rect.position
	var b: Vector2 = walkable_rect.end
	var t: float = WALL_THICKNESS
	var walls: Array[Rect2] = [
		Rect2(a - Vector2(t, t), Vector2(t, walkable_rect.size.y + 2 * t)),
		Rect2(Vector2(b.x, a.y - t), Vector2(t, walkable_rect.size.y + 2 * t)),
		Rect2(Vector2(a.x, a.y - t), Vector2(walkable_rect.size.x, t)),
		Rect2(Vector2(a.x, b.y), Vector2(walkable_rect.size.x, t)),
	]
	for rect: Rect2 in walls:
		var collider := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		collider.shape = shape
		collider.position = rect.get_center()
		add_child(collider)

func get_world_rect() -> Rect2:
	return global_transform * walkable_rect
