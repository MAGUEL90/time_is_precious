extends RefCounted

## A resumable version of the worksite visibility-grid search. Checking one
## polygon edge or scanning one frontier entry consumes one work unit. Long
## sight lines therefore share the same budget as grid expansion. A pending or
## exhausted search never supplies a partial route.
const MAX_CLOSED: int = 20000
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]

var navigation: RefCounted
var grid: float
var clearance: float
var origin: Vector2
var target: Vector2
var status: String = "pending"
var path: PackedVector2Array = []
var building_path: PackedVector2Array = []
var operations: int = 0
var phase: String = "prepare"
var polygon_bounds: Array[Rect2] = []
var bounds: Rect2
var prepare_polygon: int = 0
var prepare_point: int = 0
var preparing_bounds: Rect2
var point: Vector2
var point_polygon: int = 0
var point_edge: int = -1
var point_done: String = ""
var segment_from: Vector2
var segment_to: Vector2
var segment_steps: int = 0
var segment_index: int = 0
var segment_done: String = ""
var segment_bounds: Rect2
var segment_candidates: Array[int] = []
var segment_scan: int = 0
var min_cell: Vector2i
var max_cell: Vector2i
var start: Vector2i
var end: Vector2i
var frontier: Array[Vector2i] = []
var costs: Dictionary = {}
var parents: Dictionary = {}
var closed: Dictionary = {}
var best_index: int = 0
var scan_index: int = 0
var cell: Vector2i
var position: Vector2
var neighbor_index: int = 0
var next_cell: Vector2i

func _init(nav: RefCounted, from: Vector2, to: Vector2) -> void:
	navigation = nav
	grid = nav.GRID
	clearance = nav.CLEARANCE
	origin = from
	target = to
	bounds = Rect2(from, Vector2.ZERO).expand(to).grow(grid * 4.0)

## Return the number of work units consumed. The caller shares the budget
## among all plot workers in the same rendered frame, including a +1d skip.
func step(max_operations: int, deadline_usec: int) -> int:
	var used: int = 0
	while status == "pending" and used < max_operations and Time.get_ticks_usec() < deadline_usec:
		_advance()
		used += 1
	operations += used
	return used

func _advance() -> void:
	match phase:
		"prepare":
			_prepare_bounds()
		"point":
			_check_point()
		"segment_prepare":
			if segment_scan < polygon_bounds.size():
				if segment_bounds.intersects(polygon_bounds[segment_scan], true):
					segment_candidates.append(segment_scan)
				segment_scan += 1
			elif segment_candidates.is_empty():
				# Every sample is outside every clearance-expanded polygon box.
				_finish_segment(true)
			else:
				phase = "segment"
		"segment":
			_begin_point(segment_from.lerp(segment_to, float(segment_index) / segment_steps), "segment")
		"pick":
			if frontier.is_empty():
				status = "unreachable"
			elif closed.size() >= MAX_CLOSED:
				# The inherited finite-grid limit is not proof that no path exists.
				status = "limit"
			else:
				best_index = 0
				scan_index = 1
				phase = "scan"
		"scan":
			if scan_index < frontier.size():
				var candidate: Vector2i = frontier[scan_index]
				var best: Vector2i = frontier[best_index]
				if float(costs[candidate]) + Vector2(candidate - end).length() < float(costs[best]) + Vector2(best - end).length():
					best_index = scan_index
				scan_index += 1
			else:
				cell = frontier.pop_at(best_index)
				if closed.has(cell):
					phase = "pick"
				else:
					closed[cell] = true
					position = origin if cell == start else Vector2(cell) * grid
					_begin_segment(position, target, "goal")
		"neighbor":
			if neighbor_index >= DIRECTIONS.size():
				phase = "pick"
				return
			next_cell = cell + DIRECTIONS[neighbor_index]
			if next_cell.x < min_cell.x or next_cell.y < min_cell.y or next_cell.x > max_cell.x or next_cell.y > max_cell.y or closed.has(next_cell):
				neighbor_index += 1
			else:
				_begin_segment(position, Vector2(next_cell) * grid, "neighbor")
		"reconstruct":
			if parents.has(cell):
				cell = parents[cell]
				building_path.append(origin if cell == start else Vector2(cell) * grid)
			else:
				building_path.reverse()
				path = building_path
				status = "found"

func _prepare_bounds() -> void:
	if prepare_polygon >= navigation.polygons.size():
		_begin_point(origin, "origin")
		return
	var polygon: PackedVector2Array = navigation.polygons[prepare_polygon]
	if prepare_point < polygon.size():
		var vertex: Vector2 = polygon[prepare_point]
		if prepare_point == 0:
			preparing_bounds = Rect2(vertex, Vector2.ZERO)
		else:
			preparing_bounds = preparing_bounds.expand(vertex)
		bounds = bounds.expand(vertex)
		prepare_point += 1
	else:
		# An epsilon keeps points exactly CLEARANCE from an edge inside the
		# broad-phase box; the exact edge test below remains authoritative.
		polygon_bounds.append(preparing_bounds.grow(clearance + 0.001))
		prepare_polygon += 1
		prepare_point = 0

func _begin_point(value: Vector2, done: String) -> void:
	point = value
	point_polygon = 0
	point_edge = -1
	point_done = done
	phase = "point"

func _check_point() -> void:
	var count: int = segment_candidates.size() if point_done == "segment" else navigation.polygons.size()
	if point_polygon >= count:
		_finish_point(true)
		return
	var polygon_index: int = segment_candidates[point_polygon] if point_done == "segment" else point_polygon
	var polygon: PackedVector2Array = navigation.polygons[polygon_index]
	var box: Rect2 = polygon_bounds[polygon_index]
	if point_edge == -1:
		if point.x < box.position.x or point.y < box.position.y or point.x > box.end.x or point.y > box.end.y:
			point_polygon += 1
			return
		if polygon.size() > 2 and Geometry2D.is_point_in_polygon(point, polygon):
			_finish_point(false)
			return
		point_edge = 0
	if point_edge < polygon.size():
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[point_edge], polygon[(point_edge + 1) % polygon.size()])) <= clearance:
			_finish_point(false)
			return
		point_edge += 1
	else:
		point_polygon += 1
		point_edge = -1

func _finish_point(clear: bool) -> void:
	match point_done:
		"origin":
			if clear:
				_begin_point(target, "target")
			else:
				status = "unreachable"
		"target":
			if clear:
				_begin_segment(origin, target, "direct")
			else:
				status = "unreachable"
		"segment":
			if not clear:
				_finish_segment(false)
			else:
				segment_index += 1
				if segment_index > segment_steps:
					_finish_segment(true)
				else:
					phase = "segment"

func _begin_segment(from: Vector2, to: Vector2, done: String) -> void:
	segment_from = from
	segment_to = to
	segment_steps = maxi(1, ceili(from.distance_to(to) / 2.0))
	segment_index = 0
	segment_done = done
	segment_bounds = Rect2(from, to - from).abs()
	segment_candidates.clear()
	segment_scan = 0
	phase = "segment_prepare"

func _finish_segment(clear: bool) -> void:
	match segment_done:
		"direct":
			if clear:
				path = PackedVector2Array([origin, target])
				status = "found"
			else:
				bounds = bounds.grow(grid * 2.0)
				min_cell = Vector2i((bounds.position / grid).floor())
				max_cell = Vector2i((bounds.end / grid).ceil())
				start = Vector2i((origin / grid).round())
				end = Vector2i((target / grid).round())
				frontier = [start]
				costs = {start: 0.0}
				phase = "pick"
		"goal":
			if clear:
				building_path = PackedVector2Array([target, position])
				phase = "reconstruct"
			else:
				neighbor_index = 0
				phase = "neighbor"
		"neighbor":
			if clear:
				var cost: float = float(costs[cell]) + Vector2(DIRECTIONS[neighbor_index]).length()
				if not costs.has(next_cell) or cost < float(costs[next_cell]):
					costs[next_cell] = cost
					parents[next_cell] = cell
					frontier.append(next_cell)
			neighbor_index += 1
			phase = "neighbor"
