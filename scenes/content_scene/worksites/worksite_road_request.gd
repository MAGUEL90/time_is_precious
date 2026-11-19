extends RefCounted

## A transient request; pending is never a usable path or a failed route.
const MAX_SEARCH_OPERATIONS: int = 2000000
var router: RefCounted
var normal: RefCounted
var navigation: RefCounted
var normal_revision: int
var revision: int
var origin: Vector2
var target: Vector2
var status: String = "pending"
var path := PackedVector2Array()
var phase: String = "prepare"
var entries: Array = []
var exits: Array = []
var bounds: Array[Rect2] = []
var entry_index: int = 0
var exit_index: int = 0
var entry: int
var exit_id: int
var component: int
var checked: int = 0
var searched: bool = false
var failed_components: Dictionary = {}
var search: RefCounted
var operations: int = 0

func _init(owner: RefCounted, from: Vector2, to: Vector2, land: RefCounted, destination: RefCounted) -> void:
	router = owner
	origin = from
	target = to
	normal = land
	navigation = destination
	normal_revision = land.revision
	revision = destination.revision

func step(max_operations: int, deadline: int) -> int:
	var used: int = 0
	if normal.revision != normal_revision or navigation.revision != revision:
		status = "invalidated"
	while status == "pending" and used < max_operations and Time.get_ticks_usec() < deadline:
		if phase == "prepare" and not router.road_cells.is_empty() and not router.graph_ready(normal):
			used += router.step_graph(normal, max_operations - used, deadline)
			if not router.graph_ready(normal): break
			continue
		if phase in ["leg", "fallback"]:
			var allowance: int = mini(max_operations - used, MAX_SEARCH_OPERATIONS - search.operations)
			var consumed: int = search.step(maxi(allowance, 0), deadline)
			used += consumed
			if search.status == "pending" and search.operations >= MAX_SEARCH_OPERATIONS:
				search.status = "limit"
			if search.status == "pending":
				break
			if phase == "fallback":
				status = search.status
				if status == "found": path = search.path
			elif search.status == "found":
				_finish_road(search.path)
			else:
				phase = "exit"
			if consumed == 0: used += 1
		else:
			_advance()
			used += 1
	operations += used
	return used

func _advance() -> void:
	match phase:
		"prepare":
			if not navigation.is_clear(origin) or not navigation.is_clear(target):
				status = "unreachable"
				return
			if router.road_cells.is_empty():
				_fallback()
				return
			if router.cell_ids.is_empty():
				_fallback()
				return
			bounds = router.polygon_bounds
			if navigation != normal:
				bounds = []
				for polygon: PackedVector2Array in navigation.polygons:
					var box := Rect2(polygon[0], Vector2.ZERO)
					for vertex: Vector2 in polygon: box = box.expand(vertex)
					bounds.append(box.grow(navigation.CLEARANCE + 0.001))
			entries = router.ordered_road_points(origin)
			exits = router.ordered_road_points(target)
			phase = "entry"
		"entry":
			if entry_index >= entries.size():
				_fallback()
				return
			entry = entries[entry_index]
			entry_index += 1
			component = router.components[entry]
			if failed_components.has(component) or not router._segment_clear_fast(origin, router.graph.get_point_position(entry), navigation, bounds):
				return
			exit_index = 0
			checked = 0
			searched = false
			phase = "exit"
		"exit":
			if exit_index >= exits.size() or checked >= 64:
				failed_components[component] = true
				phase = "entry"
				return
			exit_id = exits[exit_index]
			exit_index += 1
			if router.components[exit_id] != component: return
			checked += 1
			var exit_point: Vector2 = router.graph.get_point_position(exit_id)
			if router._segment_clear_fast(exit_point, target, navigation, bounds):
				_finish_road(PackedVector2Array([exit_point, target]))
			elif not searched:
				searched = true
				search = router.shared_final_leg(exit_id, exit_point, target, normal, navigation)
				phase = "leg"

func _finish_road(leg: PackedVector2Array) -> void:
	var road: PackedVector2Array = router.graph.get_point_path(entry, exit_id)
	if road.is_empty():
		phase = "exit"
		return
	path = PackedVector2Array([origin])
	for point: Vector2 in road:
		if not path[-1].is_equal_approx(point): path.append(point)
	for point: Vector2 in leg:
		if not path[-1].is_equal_approx(point): path.append(point)
	status = "found"

func _fallback() -> void:
	# This has a different start from the road leg, so it is a distinct search.
	# Start it only after road failure/overall limit, never after a frame slice.
	search = navigation.begin_bounded_route(origin, target)
	router.fallback_searches_started += 1
	phase = "fallback"
