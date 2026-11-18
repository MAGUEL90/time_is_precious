@tool
extends RefCounted

## Optional Clay editor controls, read once by the validated authored binding.
## The source body is a layer-zero template; only the runtime copy collides.
static func read(source: Sprite2D) -> Dictionary:
	var controls: Node = source.get_node_or_null("ClayControls")
	if controls == null:
		return {"ok": true, "configured": false}
	var body := controls.get_node_or_null("Collision") as StaticBody2D
	var shape := controls.get_node_or_null("Collision/CollisionPolygon2D") as CollisionPolygon2D
	var first := controls.get_node_or_null("WorkPoint1") as Marker2D
	var second := controls.get_node_or_null("WorkPoint2") as Marker2D
	if body == null or shape == null or first == null or second == null:
		return {"ok": false, "error": "ClayControls requires Collision/CollisionPolygon2D and WorkPoint1/WorkPoint2."}
	if shape.disabled or body.collision_layer != 0 or body.collision_mask != 0 or shape.build_mode != CollisionPolygon2D.BUILD_SOLIDS:
		return {"ok": false, "error": "Clay collision template must use layer/mask zero, enabled shape and solid polygon mode."}
	var points := PackedVector2Array()
	for point: Vector2 in shape.polygon:
		var world: Vector2 = shape.to_global(point)
		if not world.is_finite() or world.length() > 1000000.0:
			return {"ok": false, "error": "Clay collision contains invalid coordinates."}
		points.append(world)
	if points.size() < 3 or Geometry2D.triangulate_polygon(points).is_empty():
		return {"ok": false, "error": "Clay collision needs a simple non-empty polygon."}
	for i: int in range(points.size()):
		if points[i].distance_to(points[(i + 1) % points.size()]) < 0.001:
			return {"ok": false, "error": "Clay collision contains duplicate adjacent vertices."}
		for j: int in range(i + 1, points.size()):
			if j == i + 1 or (i == 0 and j == points.size() - 1):
				continue
			if Geometry2D.segment_intersects_segment(points[i], points[(i + 1) % points.size()], points[j], points[(j + 1) % points.size()]) != null:
				return {"ok": false, "error": "Clay collision edges cross."}
	var slots := PackedVector2Array([first.global_position, second.global_position])
	for point: Vector2 in slots:
		if not point.is_finite() or point.length() > 1000000.0:
			return {"ok": false, "error": "Clay work point contains invalid coordinates."}
	return {"ok": true, "configured": true, "collision": points, "slots": slots}
