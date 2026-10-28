extends RefCounted

## Value-only copy of authored solid geometry. Survives the city/home handoff.
## The map has no authored walkable terrain metadata: this does not classify water.
const GRID: float = 8.0
const CLEARANCE: float = 4.5
var polygons: Array[PackedVector2Array] = []
var resource_bottoms: Dictionary = {}

func configure(map: Node) -> void:
	polygons.clear()
	resource_bottoms.clear()
	if not is_instance_valid(map):
		return
	_collect(map)

func _collect(node: Node) -> void:
	if node is Sprite2D and node.name == "ResourceIcon" and node.get_parent() is Marker2D:
		_resource_contact(node)
	elif node is CollisionShape2D and not node.disabled and node.shape != null:
		var body: Node = node.get_parent()
		if body is StaticBody2D and body.collision_layer != 0:
			_add_shape(node.shape, node.global_transform)
	elif node is CollisionPolygon2D and not node.disabled:
		var body: Node = node.get_parent()
		if body is StaticBody2D and body.collision_layer != 0:
			_add_polygon(node.polygon, node.global_transform)
	elif node is TileMapLayer and node.enabled and node.collision_enabled and node.tile_set != null:
		for cell: Vector2i in node.get_used_cells():
			var tile: TileData = node.get_cell_tile_data(cell)
			if tile == null:
				continue
			var transform: Transform2D = node.global_transform
			transform.origin = node.to_global(node.map_to_local(cell))
			for layer: int in range(node.tile_set.get_physics_layers_count()):
				if node.tile_set.get_physics_layer_collision_layer(layer) == 0:
					continue
				for index: int in range(tile.get_collision_polygons_count(layer)):
					var points: PackedVector2Array = tile.get_collision_polygon_points(layer, index)
					for i: int in range(points.size()):
						if tile.transpose:
							points[i] = Vector2(points[i].y, points[i].x)
						if tile.flip_h:
							points[i].x = -points[i].x
						if tile.flip_v:
							points[i].y = -points[i].y
					_add_polygon(points, transform)
	for child: Node in node.get_children():
		_collect(child)

func _resource_contact(icon: Sprite2D) -> void:
	if icon.texture == null:
		return
	var image: Image = icon.texture.get_image()
	var used: Rect2i = image.get_used_rect()
	var left: int = image.get_width()
	var right: int = -1
	var top: int = maxi(used.position.y, used.end.y - 6)
	for y: int in range(top, used.end.y):
		for x: int in range(used.position.x, used.end.x):
			if image.get_pixel(x, y).a > 0.0:
				left = mini(left, x)
				right = maxi(right, x)
	if right < left:
		return
	var offset: Vector2 = icon.offset - Vector2(image.get_size()) * 0.5 if icon.centered else icon.offset
	var contact := PackedVector2Array([Vector2(left, top) + offset, Vector2(right + 1, top) + offset,
		Vector2(right + 1, used.end.y) + offset, Vector2(left, used.end.y) + offset])
	# Production sites provide the same polygon as an actual player collider.
	if not icon.get_parent().has_node("ResourceBase"):
		_add_polygon(contact, icon.global_transform)
	var bottom: float = -INF
	for point: Vector2 in contact:
		bottom = maxf(bottom, icon.to_global(point).y)
	resource_bottoms[str(icon.get_parent().name)] = bottom

func _add_shape(shape: Shape2D, transform: Transform2D) -> void:
	var points := PackedVector2Array()
	if shape is RectangleShape2D:
		var half: Vector2 = shape.size * 0.5
		points = PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
	elif shape is ConvexPolygonShape2D:
		points = shape.points
	elif shape is ConcavePolygonShape2D:
		var segments: PackedVector2Array = shape.segments
		for i: int in range(0, segments.size(), 2):
			_add_polygon(PackedVector2Array([segments[i], segments[i + 1]]), transform)
		return
	elif shape is SegmentShape2D:
		points = PackedVector2Array([shape.a, shape.b])
	elif shape is CircleShape2D or shape is CapsuleShape2D:
		var radius: float = shape.radius
		var offset: float = maxf(shape.height * 0.5 - radius, 0.0) if shape is CapsuleShape2D else 0.0
		# Circumscribe curved shapes so the route never cuts through their surface.
		for i: int in range(32):
			var direction: Vector2 = Vector2.from_angle(TAU * float(i) / 32.0)
			points.append(direction * (radius / cos(PI / 32.0)) + Vector2(0, offset if direction.y >= 0 else -offset))
	else:
		push_error("Worksite navigation: unsupported authored solid shape: " + shape.get_class())
		return
	_add_polygon(points, transform)

func _add_polygon(points: PackedVector2Array, transform: Transform2D) -> void:
	var world := PackedVector2Array()
	for point: Vector2 in points:
		world.append(transform * point)
	if world.size() >= 2:
		polygons.append(world)

func is_clear(point: Vector2) -> bool:
	for polygon: PackedVector2Array in polygons:
		if polygon.size() > 2 and Geometry2D.is_point_in_polygon(point, polygon):
			return false
		for i: int in range(polygon.size()):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])) <= CLEARANCE:
				return false
	return true

func segment_clear(from: Vector2, to: Vector2) -> bool:
	var steps: int = maxi(1, ceili(from.distance_to(to) / 2.0))
	for i: int in range(steps + 1):
		if not is_clear(from.lerp(to, float(i) / steps)):
			return false
	return true

func reachable_point(origin: Vector2, desired: Vector2) -> Vector2:
	# Authored collision proves clearance/reachability only, never dry terrain.
	if not is_clear(origin):
		return Vector2.INF
	var candidates: Array[Vector2] = [desired]
	for radius: int in range(1, 13):
		for direction: int in range(16):
			candidates.append(desired + Vector2.from_angle(TAU * direction / 16.0) * GRID * radius)
	for point: Vector2 in candidates:
		if not is_clear(point):
			continue
		var points: PackedVector2Array = route(origin, point)
		if not points.is_empty() and points[-1].distance_to(point) < 0.1:
			return point
	return Vector2.INF

func route(from: Vector2, to: Vector2) -> PackedVector2Array:
	if not is_clear(from) or not is_clear(to):
		return PackedVector2Array()
	if segment_clear(from, to):
		return PackedVector2Array([from, to])
	# Finite visibility grid; bounds include the endpoints and relevant solids.
	var bounds := Rect2(from, Vector2.ZERO).expand(to).grow(GRID * 4.0)
	for polygon: PackedVector2Array in polygons:
		for point: Vector2 in polygon:
			bounds = bounds.expand(point)
	bounds = bounds.grow(GRID * 2.0)
	var min_cell := Vector2i((bounds.position / GRID).floor())
	var max_cell := Vector2i((bounds.end / GRID).ceil())
	var start := Vector2i((from / GRID).round())
	var end := Vector2i((to / GRID).round())
	var frontier: Array[Vector2i] = [start]
	var costs: Dictionary = {start: 0.0}
	var parents: Dictionary = {}
	var closed: Dictionary = {}
	while not frontier.is_empty() and closed.size() < 20000:
		var best: int = 0
		for i: int in range(1, frontier.size()):
			if float(costs[frontier[i]]) + Vector2(frontier[i] - end).length() < float(costs[frontier[best]]) + Vector2(frontier[best] - end).length():
				best = i
		var cell: Vector2i = frontier.pop_at(best)
		if closed.has(cell):
			continue
		closed[cell] = true
		var position: Vector2 = from if cell == start else Vector2(cell) * GRID
		if segment_clear(position, to):
			var result := PackedVector2Array([to, position])
			while parents.has(cell):
				cell = parents[cell]
				result.append(from if cell == start else Vector2(cell) * GRID)
			result.reverse()
			return result
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			var next: Vector2i = cell + direction
			if next.x < min_cell.x or next.y < min_cell.y or next.x > max_cell.x or next.y > max_cell.y or closed.has(next):
				continue
			if not segment_clear(position, Vector2(next) * GRID):
				continue
			var cost: float = float(costs[cell]) + Vector2(direction).length()
			if not costs.has(next) or cost < float(costs[next]):
				costs[next] = cost
				parents[next] = cell
				frontier.append(next)
	return PackedVector2Array()
