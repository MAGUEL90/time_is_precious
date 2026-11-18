extends RefCounted

## Road art is currently authored in the city TileMap, without terrain metadata.
## Snapshot its solid brown pixels on a four-pixel grid; never modify the map.
const STEP: int = 4
const ROAD_COLOR: Color = Color8(128, 98, 55)
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var road_cells: Dictionary = {}
var graph: AStar2D = AStar2D.new()
var cell_ids: Dictionary = {}
var components: Dictionary = {}
var graph_revision: int = -1
var graph_navigation_id: int = -1
var graph_build: Dictionary = {}
var point_order_cache: Dictionary = {}
var polygon_bounds: Array[Rect2] = []
const REQUEST = preload("res://scenes/content_scene/worksites/worksite_road_request.gd")
const FRAME_BUDGET_USEC: int = 4000
const FRAME_OPERATIONS: int = 12000
const REQUEST_SLICE: int = 2000
const POINT_ORDER_CACHE_LIMIT: int = 128
var final_leg_cache: Dictionary = {}
var final_leg_searches_started: int = 0
var final_leg_cache_hits: int = 0
var fallback_searches_started: int = 0
var budget_frame: int = -1
var frame_operations: int = 0
var frame_deadline: int = 0

func configure(authored_map: Node2D) -> void:
	road_cells.clear()
	graph_revision = -1
	graph_build.clear()
	final_leg_cache.clear()
	point_order_cache.clear()
	if authored_map == null:
		return
	var layers: Array[TileMapLayer] = []
	for path: String in ["Ground/Base", "Ground/Base2"]:
		var layer := authored_map.get_node_or_null(path) as TileMapLayer
		if layer != null and layer.enabled and layer.tile_set != null:
			layers.append(layer)
	if layers.is_empty():
		return
	# Sample the used tile rectangles rather than assuming map dimensions.
	var bounds := Rect2i()
	var first := true
	for layer: TileMapLayer in layers:
		for cell: Vector2i in layer.get_used_cells():
			var tile_rect := Rect2i(Vector2i((layer.to_global(layer.map_to_local(cell)) - Vector2(8, 8)).floor()), Vector2i(16, 16))
			bounds = tile_rect if first else bounds.merge(tile_rect)
			first = false
	if first:
		return
	var images: Dictionary = {}
	for y: int in range(floori(float(bounds.position.y) / STEP), ceili(float(bounds.end.y) / STEP)):
		for x: int in range(floori(float(bounds.position.x) / STEP), ceili(float(bounds.end.x) / STEP)):
			var point := Vector2(x * STEP, y * STEP)
			var color := Color.TRANSPARENT
			for layer: TileMapLayer in layers:
				var sample: Color = _sample(layer, point, images)
				if sample.a > 0.5:
					color = sample
			if color.is_equal_approx(ROAD_COLOR):
				road_cells[Vector2i(x, y)] = true

func _sample(layer: TileMapLayer, world: Vector2, images: Dictionary) -> Color:
	var local: Vector2 = layer.to_local(world)
	var cell: Vector2i = layer.local_to_map(local)
	var source_id: int = layer.get_cell_source_id(cell)
	if source_id < 0:
		return Color.TRANSPARENT
	var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
	var tile: TileData = layer.get_cell_tile_data(cell)
	if source == null or source.texture == null or tile == null:
		return Color.TRANSPARENT
	if not images.has(source.texture):
		images[source.texture] = source.texture.get_image()
	var image: Image = images[source.texture]
	if image == null:
		return Color.TRANSPARENT
	var size: Vector2i = layer.tile_set.tile_size
	var pixel := Vector2i((local - layer.map_to_local(cell) + Vector2(size) * 0.5).floor())
	if tile.transpose:
		pixel = Vector2i(pixel.y, pixel.x)
	if tile.flip_h:
		pixel.x = size.x - 1 - pixel.x
	if tile.flip_v:
		pixel.y = size.y - 1 - pixel.y
	var atlas: Vector2i = layer.get_cell_atlas_coords(cell)
	var region: Rect2i = source.get_tile_texture_region(atlas)
	var position: Vector2i = region.position + pixel
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= size.x or pixel.y >= size.y or position.x < 0 or position.y < 0 or position.x >= image.get_width() or position.y >= image.get_height():
		return Color.TRANSPARENT
	return image.get_pixelv(position)

func _rebuild(navigation: RefCounted) -> void:
	graph_revision = -1
	graph_build.clear()
	while not graph_ready(navigation):
		step_graph(navigation, 100000, Time.get_ticks_usec() + 1000000)

func _is_clear_fast(point: Vector2, navigation: RefCounted) -> bool:
	if not navigation.is_in_region(point):
		return false
	for index: int in range(navigation.polygons.size()):
		if not polygon_bounds[index].has_point(point):
			continue
		var polygon: PackedVector2Array = navigation.polygons[index]
		if polygon.size() > 2 and Geometry2D.is_point_in_polygon(point, polygon):
			return false
		for i: int in range(polygon.size()):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])) <= navigation.CLEARANCE:
				return false
	return true

func _segment_clear_fast(from: Vector2, to: Vector2, navigation: RefCounted, bounds: Array[Rect2]) -> bool:
	if not navigation.is_in_region(from) or not navigation.is_in_region(to):
		return false
	var segment_bounds := Rect2(from, to - from).abs().grow(0.001)
	var steps: int = maxi(1, ceili(from.distance_to(to) / 2.0))
	for index: int in range(navigation.polygons.size()):
		if not segment_bounds.intersects(bounds[index], true):
			continue
		var polygon: PackedVector2Array = navigation.polygons[index]
		for step: int in range(steps + 1):
			var point: Vector2 = from.lerp(to, float(step) / steps)
			if not bounds[index].has_point(point):
				continue
			if polygon.size() > 2 and Geometry2D.is_point_in_polygon(point, polygon):
				return false
			for edge: int in range(polygon.size()):
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[edge], polygon[(edge + 1) % polygon.size()])) <= navigation.CLEARANCE:
					return false
	return true

## Synchronous adapter for existing diagnostics; live workers use begin/step.
func route(origin: Vector2, target: Vector2, normal: RefCounted, destination_nav: RefCounted) -> PackedVector2Array:
	var request = begin_route(origin, target, normal, destination_nav)
	while request.status == "pending":
		request.step(100000, Time.get_ticks_usec() + 1000000)
	return request.path if request.status == "found" else PackedVector2Array()

func begin_route(origin: Vector2, target: Vector2, normal: RefCounted, destination_nav: RefCounted) -> RefCounted:
	return REQUEST.new(self, origin, target, normal, destination_nav)

func step_route(request: RefCounted) -> void:
	var frame: int = Engine.get_process_frames()
	if budget_frame != frame:
		budget_frame = frame
		frame_operations = 0
		frame_deadline = Time.get_ticks_usec() + FRAME_BUDGET_USEC
	if request.status != "pending" or frame_operations >= FRAME_OPERATIONS or Time.get_ticks_usec() >= frame_deadline:
		return
	frame_operations += request.step(mini(REQUEST_SLICE, FRAME_OPERATIONS - frame_operations), frame_deadline)

func shared_final_leg(exit_id: int, origin: Vector2, target: Vector2, normal: RefCounted, navigation: RefCounted) -> RefCounted:
	var key: String = "%d:%d:%d:%d:%d:%s" % [normal.get_instance_id(), normal.revision, navigation.get_instance_id(), navigation.revision, exit_id, var_to_bytes(target).hex_encode()]
	if final_leg_cache.has(key):
		final_leg_cache_hits += 1
		return final_leg_cache[key]
	var search: RefCounted = navigation.begin_bounded_route(origin, target)
	final_leg_searches_started += 1
	final_leg_cache[key] = search
	return search


func graph_ready(navigation: RefCounted) -> bool:
	return graph_build.is_empty() and graph_revision == navigation.revision and graph_navigation_id == navigation.get_instance_id()

## Shared incremental graph construction; no worker repeats a cold rebuild.
func step_graph(navigation: RefCounted, allowance: int, deadline: int) -> int:
	if graph_build.get("revision", -1) != navigation.revision or graph_build.get("navigation_id", -1) != navigation.get_instance_id():
		graph.clear()
		cell_ids.clear()
		components.clear()
		polygon_bounds.clear()
		final_leg_cache.clear()
		point_order_cache.clear()
		graph_revision = -1
		graph_build = {"revision": navigation.revision, "navigation_id": navigation.get_instance_id(),
			"phase": "bounds", "index": 0, "cells": road_cells.keys(), "ids": [], "queue": [], "queue_index": 0, "component": 0}
	var used: int = 0
	while not graph_build.is_empty() and used < allowance and Time.get_ticks_usec() < deadline:
		used += 1
		var index: int = graph_build.index
		match graph_build.phase:
			"bounds":
				if index < navigation.polygons.size():
					var polygon: PackedVector2Array = navigation.polygons[index]
					var box := Rect2(polygon[0], Vector2.ZERO)
					for vertex: Vector2 in polygon: box = box.expand(vertex)
					polygon_bounds.append(box.grow(navigation.CLEARANCE + 0.001))
					graph_build.index += 1
				else:
					graph_build.phase = "nodes"
					graph_build.index = 0
			"nodes":
				if index < graph_build.cells.size():
					var cell: Vector2i = graph_build.cells[index]
					var point := Vector2(cell * STEP)
					if _is_clear_fast(point, navigation):
						var id: int = cell_ids.size()
						cell_ids[cell] = id
						graph.add_point(id, point)
					graph_build.index += 1
				else:
					graph_build.cells = cell_ids.keys()
					graph_build.index = 0
					graph_build.phase = "edges"
			"edges":
				if index < graph_build.cells.size():
					var cell: Vector2i = graph_build.cells[index]
					for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
						var neighbor: Vector2i = cell + direction
						if cell_ids.has(neighbor) and _is_clear_fast(Vector2(cell * STEP) + Vector2(direction * (STEP / 2)), navigation):
							graph.connect_points(cell_ids[cell], cell_ids[neighbor], true)
					graph_build.index += 1
				else:
					graph_build.ids = cell_ids.values()
					graph_build.index = 0
					graph_build.phase = "components"
			"components":
				if graph_build.queue_index < graph_build.queue.size():
					var id: int = graph_build.queue[graph_build.queue_index]
					for neighbor: int in graph.get_point_connections(id):
						if not components.has(neighbor):
							components[neighbor] = graph_build.component
							graph_build.queue.append(neighbor)
					graph_build.queue_index += 1
				elif index < graph_build.ids.size():
					var id: int = graph_build.ids[index]
					graph_build.index += 1
					if not components.has(id):
						graph_build.component += 1
						components[id] = graph_build.component
						graph_build.queue = [id]
						graph_build.queue_index = 0
				else:
					graph_revision = navigation.revision
					graph_navigation_id = navigation.get_instance_id()
					graph_build.clear()
	return used


func ordered_road_points(point: Vector2) -> Array:
	if point_order_cache.has(point): return point_order_cache[point]
	var distances: Array[float] = []
	var buckets: Dictionary = {}
	for id: int in cell_ids.values():
		var distance: float = graph.get_point_position(id).distance_squared_to(point)
		if not buckets.has(distance):
			buckets[distance] = []
			distances.append(distance)
		buckets[distance].append(id)
	# Native numeric sorting avoids thousands of GDScript comparator calls.
	distances.sort()
	var ordered: Array = []
	for distance: float in distances: ordered.append_array(buckets[distance])
	if point_order_cache.size() >= POINT_ORDER_CACHE_LIMIT:
		point_order_cache.erase(point_order_cache.keys()[0])
	point_order_cache[point] = ordered
	return ordered
