extends "res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.gd"

## Content adapter for the tested worksite loop. Uses the map's existing Player/HUD.
## City stock uses the existing runtime host; other worksite data remains scene-local.
## Never opens or overwrites the prototype save slot.
@export_category("Content playtest")
@export var seed_playtest_equipment: bool = false
@export var seed_playtest_hauler: bool = false
@export var enable_time_shortcuts: bool = true
@export var retain_resource_stock: bool = false
@export var finite_resource_sites: bool = false
# Explicitly temporary values authorized for testing; final balance is pending.
const TEST_RESOURCE_CAPACITY: Dictionary = {
	"clay_lump": 36, "wood_log": 24, "reed_bundle": 40, "water_jar": 48,
}
const RESPAWN_MIN_MINUTES: int = 2 * 1440
const RESPAWN_MAX_MINUTES: int = 3 * 1440
const RESOURCE_OFFSETS: Array[Vector2] = [
	Vector2.ZERO, Vector2(-48, 0), Vector2(48, 0), Vector2(0, -48), Vector2(0, 48),
	Vector2(-48, -48), Vector2(48, -48), Vector2(-48, 48), Vector2(48, 48),
	Vector2(-72, 0), Vector2(72, 0), Vector2(0, -72), Vector2(0, 72),
]
# Temporary review points in WorksiteMarkers-local coordinates, south of the
# authored lots. These are not the game's final random placement policy.
const TEMP_RELOCATION_POINTS: Array[Vector2] = [
	Vector2(65, 177),
	Vector2(-40, 217), Vector2(40, 217), Vector2(120, 217),
	Vector2(-40, 297), Vector2(40, 297), Vector2(120, 297),
	Vector2(-40, 377), Vector2(40, 377), Vector2(120, 377),
]
const RESOURCE_ROUTE_BUDGET_USEC: int = 15000
var _site_origins: Dictionary = {}
var _relocation_queued: bool = false
var _last_relocation_attempt: Dictionary = {}
var _resource_art_visibility: Dictionary = {}
var _resource_label_visibility: Dictionary = {}
var _depleted_presentation: Dictionary = {}
var checkpoint_handoff: bool = false
var worksite_navigation = preload("res://scenes/content_scene/worksites/worksite_navigation.gd").new()
const RESOURCE_PRESENTATION = preload("res://scenes/content_scene/worksites/resource_site_presentation.gd")
const LEGACY_STOCKPILES = preload("res://scenes/content_scene/worksites/legacy_stockpile_layout.gd")
const LEGACY_PICKUP = preload("res://scenes/content_scene/worksites/legacy_stockpile_pickup.gd")
const WORKSHOP_BACKEND: PackedScene = preload("res://scenes/workshop/workshop.tscn")
var navigation_map: WeakRef
var navigation_phases: Dictionary = {}
# The retained navigation copy can outlive the city scene. A phase change may
# queue a collider change for a later frame, so its geometry is not yet usable
# for an entire synchronous time skip.
var navigation_geometry_phases: Dictionary = {}
var navigation_refresh_pending: bool = false
# Each template contains only the collision shapes whose enabled state changes
# with that plot. It is captured while the authored city view is still alive.
var navigation_plot_templates: Dictionary = {}

const RESOURCE_STOCK_META: StringName = &"main_map_resource_stock"

const PLAYTEST_HAULER_ID: String = "content_hauler_belum"

func _create_city_tool_storage() -> Node:
	# Inventory survives map changes. Its deposited goods must have the same lifetime.
	# Reuse the existing provider under WorkStateRuntime, without another autoload.
	var storage := WorkStateRuntime.get_node_or_null("CityToolStorage")
	if storage == null:
		storage = preload("res://scenes/storage_destination/city_tool_storage.gd").new()
		storage.name = "CityToolStorage"
		WorkStateRuntime.add_child(storage)
	return storage

func _ready() -> void:
	if player == null or inventory_ui == null:
		set_process(false)
		set_process_unhandled_input(false)
		if get_parent() == get_tree().root:
			# F6 on this reusable component previews it in its real map context.
			_open_content_preview.call_deferred()
		else:
			push_error("Worksites: set player_path and inventory_ui_path to the map's Player and InventoryUI.")
		return
	daily.physical_arrival = _physical_site_arrival
	daily.assignment_started = _begin_site_assignments
	daily.assignment_released = _release_site_approach
	daily.allow_haulers = false
	super._ready()
	for site: Node2D in $WorksiteMarkers.get_children():
		_site_origins[site.name] = site.position
		if finite_resource_sites:
			var session = sites[site.name]
			session.finite_resource = true
			# StrawSite is the existing compatibility source until farming exists;
			# its prior marker default is retained, not used as a new farming design.
			session.deposit_capacity = int(TEST_RESOURCE_CAPACITY.get(session.item_id, session.stock))
			session.stock = session.deposit_capacity
			session.stock_settled.connect(_on_hourly_stock_settled.bind(site.name))
		RESOURCE_PRESENTATION.configure(site)
		var footprint: CanvasItem = site.get_node_or_null("Footprint") as CanvasItem
		_resource_art_visibility[site.name] = footprint.visible if footprint != null else false
		var label: CanvasItem = site.get_node_or_null("Label") as CanvasItem
		_resource_label_visibility[site.name] = label.visible if label != null else false
	if finite_resource_sites:
		daily.settlement_finished.connect(_on_daily_stock_settled)
		work_finished.connect(_on_daily_stock_settled)
	_refresh_navigation()
	# Other plot views may still have deferred their initial collider toggles.
	# Recollect after those toggles before allowing simulated travel.
	navigation_refresh_pending = true
	_queue_navigation_after_colliders.call_deferred()
	if retain_resource_stock:
		_restore_resource_stock()
	# Notes belong to the isolated fixture, not the content HUD.
	$FixtureNotes.hide()
	$WorkerVisuals.y_sort_enabled = true
	var resident_spawn: Node2D = get_node_or_null("ResidentSpawn") as Node2D
	if resident_spawn != null:
		$WorkerVisuals.enable_city_residents(resident_spawn)
		var inspection := preload("res://scenes/content_scene/citizen_inspection_controller.gd").new()
		inspection.name = "CitizenInspectionController"
		inspection.configure(self, $WorkerVisuals)
		add_child(inspection)
	worker_control.can_open = _can_open_worker_hub
	# Resource-only map sections can reuse this adapter without a city warehouse.
	var city_storage_area: Node = get_node_or_null("CityStorageArea")
	if city_storage_area != null:
		city_storage_area.configure(player, city_tools, _can_open_worker_hub)
	var city_storage_annex: Node = get_node_or_null("CityStorageAnnex")
	if city_storage_area != null and city_storage_annex != null:
		# Both providers are city property. Keep the annex and in-flight cargo in
		# the existing persistent world host during the city/home handoff.
		var transport: Node = WorkStateRuntime.get_node_or_null("CityStorageTransport")
		if transport == null:
			transport = preload("res://scenes/storage_destination/city_storage_transport.gd").new()
			transport.name = "CityStorageTransport"
			var annex: Node = preload("res://scenes/storage_destination/city_tool_storage.gd").new()
			annex.name = "Annex"
			transport.add_child(annex)
			WorkStateRuntime.add_child(transport)
		transport.configure(city_tools, city_storage_area.get_node("DeliveryPoint").global_position,
			city_storage_annex.get_node("DeliveryPoint").global_position)
		city_storage_annex.configure(player, transport.get_storage("annex"), _can_open_worker_hub)
	if seed_playtest_equipment:
		city_tools.add_tool_unit("content_cart", "cart", "Cart")
		city_tools.add_tool_unit("content_glove", "basic_glove", "Basic Glove")
		city_tools.add_tool_unit("content_hammer", "stone_hammer", "Raw Hammer")
	if seed_playtest_hauler and not WorkerDatabase.has_worker_data(PLAYTEST_HAULER_ID) and not WorkerDatabase.dismissed_workers.has(PLAYTEST_HAULER_ID):
		# Same legacy WorkerData fixture contract as the existing Naram/Enki roster.
		# This does not alter the city's citizen generation or hiring rules.
		var worker := WorkerData.new()
		worker.worker_id = PLAYTEST_HAULER_ID
		worker.display_name = "Belum"
		worker.profession = WorkerData.Profession.HAULER
		WorkerDatabase.workers_by_id[worker.worker_id] = worker

## Save an offset relative to the authored marker, not a node path or world
## coordinate. Only this bounded list is accepted when loading a checkpoint.
func resource_site_offset(site_id: StringName) -> Vector2:
	var marker: Node2D = $WorksiteMarkers.get_node_or_null(NodePath(str(site_id)))
	if marker == null or not _site_origins.has(site_id):
		return Vector2.ZERO
	return marker.position - Vector2(_site_origins[site_id])

func resource_offset_valid(offset: Vector2, site_id: StringName) -> bool:
	if offset in RESOURCE_OFFSETS:
		return true # Retain locations in already-issued v5 saves.
	if not _site_origins.has(site_id):
		return false
	for point: Vector2 in TEMP_RELOCATION_POINTS:
		if offset == point - Vector2(_site_origins[site_id]):
			return true
	return false

func restore_resource_offsets(saved_sites: Dictionary) -> void:
	# Retry throttling belongs to the discarded live timeline. Keeping a later
	# attempt after Continue would postpone an otherwise due deposit until that
	# old future minute, even when a checked replacement point is available.
	_last_relocation_attempt.clear()
	for site_id: String in saved_sites:
		var key := StringName(site_id)
		var marker: Node2D = $WorksiteMarkers.get_node_or_null(NodePath(site_id))
		if marker != null and _site_origins.has(key):
			marker.position = Vector2(_site_origins[key]) + Vector2(saved_sites[site_id].get("offset", Vector2.ZERO))
	_refresh_navigation()
	# Save restoration also changes building phases before their colliders are
	# deferred. Recollect once those physics updates have finished.
	navigation_refresh_pending = true
	_queue_navigation_after_colliders.call_deferred()
	_queue_depleted_sites()

func _on_hourly_stock_settled(site_id: StringName) -> void:
	if not finite_resource_sites or not sites.has(site_id):
		return
	_sync_site_timer(site_id)
	_queue_depleted_sites()

func _on_daily_stock_settled() -> void:
	if not finite_resource_sites:
		return
	for key: Variant in sites:
		_sync_site_timer(StringName(key))
	_queue_depleted_sites()

func _sync_site_timer(site_id: StringName) -> void:
	var session = sites[site_id]
	if session.stock <= 0:
		# Hourly work can still return its uncommitted units on cancellation.
		# Do not start a deadline until that transaction has settled.
		if session.working:
			return
		if session.respawn_started_at < 0:
			session.respawn_started_at = daily.now()
			session.respawn_due_at = session.respawn_started_at + daily.rng.randi_range(RESPAWN_MIN_MINUTES, RESPAWN_MAX_MINUTES)
	elif not session.working:
		# An aborted Hourly transaction may return stock to the deposit. In that
		# case it was not actually depleted and must not keep a stale deadline.
		session.respawn_started_at = -1
		session.respawn_due_at = -1
	_set_site_depleted_presentation(site_id, session.stock <= 0 and not session.working)

func sync_resource_presentation() -> void:
	if not finite_resource_sites:
		return
	for key: Variant in sites:
		var site_id := StringName(key)
		_set_site_depleted_presentation(site_id, int(sites[site_id].stock) <= 0)

func _set_site_depleted_presentation(site_id: StringName, depleted: bool) -> void:
	if _depleted_presentation.has(site_id) and bool(_depleted_presentation[site_id]) == depleted:
		return
	_depleted_presentation[site_id] = depleted
	var marker: Node2D = $WorksiteMarkers.get_node_or_null(NodePath(str(site_id)))
	if marker == null:
		return
	var icon: CanvasItem = marker.get_node_or_null("ResourceIcon") as CanvasItem
	if icon != null:
		icon.visible = not depleted
	var footprint: CanvasItem = marker.get_node_or_null("Footprint") as CanvasItem
	if footprint != null:
		footprint.visible = not depleted and bool(_resource_art_visibility.get(site_id, false))
	var label: CanvasItem = marker.get_node_or_null("Label") as CanvasItem
	if label != null:
		label.visible = not depleted and bool(_resource_label_visibility.get(site_id, false))
	var collider: CollisionPolygon2D = marker.get_node_or_null("ResourceBase/CollisionPolygon2D") as CollisionPolygon2D
	if collider != null:
		collider.set_deferred("disabled", depleted)
		navigation_refresh_pending = true
		_queue_navigation_after_colliders.call_deferred()

func _queue_depleted_sites() -> void:
	if not finite_resource_sites or _relocation_queued:
		return
	for session in sites.values():
		if session.stock <= 0 and not session.working and session.respawn_due_at >= 0 and daily.now() >= session.respawn_due_at:
			_relocation_queued = true
			_relocate_depleted_sites.call_deferred()
			return

func _relocate_depleted_sites() -> void:
	_relocation_queued = false
	# A parked runtime continues worker time but has no live map to validate a
	# new location. Wait until the city is restored; do not conjure resources.
	if not is_inside_tree() or checkpoint_handoff or _working or daily.is_settlement_busy() or navigation_refresh_pending or get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return
	var map: Node = navigation_map.get_ref() if navigation_map != null else null
	if not is_instance_valid(map) or not map.is_ancestor_of(self):
		return
	# Regression fixtures can wrap the city in a test node. Terrain belongs to
	# the nearest city ancestor rather than necessarily the outer navigation root.
	var terrain_map: Node = self
	while terrain_map != null and not terrain_map.has_node("AuthoredMap/Ground/Base"):
		terrain_map = terrain_map.get_parent()
	if terrain_map == null:
		return
	for key: Variant in sites:
		var site_id := StringName(key)
		var session = sites[site_id]
		if session.stock > 0 or session.working or session.respawn_due_at < 0 or daily.now() < session.respawn_due_at:
			continue
		var now: int = daily.now()
		if now - int(_last_relocation_attempt.get(site_id, -1000000)) < 60:
			continue
		_last_relocation_attempt[site_id] = now
		var marker: Node2D = $WorksiteMarkers.get_node(NodePath(str(site_id)))
		var current_offset: Vector2 = resource_site_offset(site_id)
		for point: Vector2 in TEMP_RELOCATION_POINTS:
			var offset: Vector2 = point - Vector2(_site_origins[site_id])
			if offset == current_offset:
				continue
			var candidate: Vector2 = marker.get_parent().to_global(Vector2(_site_origins[site_id]) + offset)
			if not _resource_candidate_clear(terrain_map, marker, candidate):
				continue
			# The old deposit vanishes and the replacement receives its own stock.
			# Workers keep their assignment but must physically reach the new site.
			marker.position = Vector2(_site_origins[site_id]) + offset
			session.stock = session.deposit_capacity
			session.respawn_started_at = -1
			session.respawn_due_at = -1
			_set_site_depleted_presentation(site_id, false)
			worker_journeys.clear()
			_refresh_navigation()
			if daily.jobs.has(site_id):
				var ids: Array[String] = []
				ids.assign(daily.jobs[site_id].ids)
				_begin_site_assignments(site_id, ids)
			break

func _resource_candidate_clear(map: Node, marker: Node2D, candidate: Vector2) -> bool:
	var base: TileMapLayer = map.get_node_or_null("AuthoredMap/Ground/Base") as TileMapLayer
	var base2: TileMapLayer = map.get_node_or_null("AuthoredMap/Ground/Base2") as TileMapLayer
	if base == null or base2 == null or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	if is_instance_valid(player) and candidate.distance_to(player.global_position + Vector2(0, 16)) < 28.0:
		return false
	var visuals: Node = get_node_or_null("WorkerVisuals")
	if visuals != null:
		for actor: Node2D in visuals.actors.values():
			if is_instance_valid(actor) and actor.visible and candidate.distance_to(actor.global_position + Vector2(0, 16)) < 28.0:
				return false
	for other: Node2D in $WorksiteMarkers.get_children():
		if other != marker and candidate.distance_to(other.global_position) < 40.0:
			return false
	# Authored plot art has no physics collider before construction, so test it
	# explicitly instead of allowing a resource deposit to cover a future plot.
	var authored_world: Node = map.get_node_or_null("AuthoredMap/YSortWorld")
	if authored_world == null:
		return false
	var candidate_bounds := Rect2(candidate - Vector2(20, 20), Vector2(40, 40))
	for object: Node in authored_world.get_children():
		if object is Sprite2D and str(object.name).begins_with("ToBeClean"):
			var plot_bounds: Rect2 = object.global_transform * object.get_rect()
			if candidate_bounds.intersects(plot_bounds):
				return false
	var bottom: float = float(worksite_navigation.resource_bottoms.get(str(marker.name), marker.global_position.y)) - marker.global_position.y
	var feet_y: float = maxf(8.0, bottom + worksite_navigation.CLEARANCE + 1.0)
	var checks: Array[Vector2] = [Vector2(-16, -10), Vector2(16, -10), Vector2(-16, 12), Vector2(16, 12), Vector2.ZERO, Vector2(-10, feet_y), Vector2(10, feet_y)]
	for delta: Vector2 in checks:
		var point: Vector2 = candidate + delta
		if not worksite_navigation.is_clear(point):
			return false
		if base.get_cell_source_id(base.local_to_map(base.to_local(point))) < 0 and base2.get_cell_source_id(base2.local_to_map(base2.to_local(point))) < 0:
			return false
	var origin: Vector2 = player.global_position + Vector2(0, 16)
	if not worksite_navigation.is_clear(origin):
		return false
	for x: float in [-10.0, 10.0]:
		var route: PackedVector2Array = _bounded_resource_route(origin, candidate + Vector2(x, feet_y))
		if not _route_on_land(route, base, base2):
			return false
	var job: Dictionary = daily.jobs.get(marker.name, {})
	for id: String in job.get("ids", []):
		var worker: WorkerData = WorkerDatabase.get_worker_data(id)
		if worker == null or worker.physical_approach.is_empty():
			continue
		var worker_feet: Vector2 = worker.physical_approach.position
		var slot: int = job.ids.find(id)
		if not worksite_navigation.is_clear(worker_feet):
			return false
		var worker_route: PackedVector2Array = _bounded_resource_route(worker_feet, candidate + Vector2(-10 + slot * 20, feet_y))
		if not _route_on_land(worker_route, base, base2):
			return false
	return true

func _bounded_resource_route(origin: Vector2, target: Vector2) -> PackedVector2Array:
	return _site_route(origin, target, true)

## Route around real collision geometry. The old village wall is no longer
## shown, so there is no visual gate that workers need to pass through.
func site_approach_route(origin: Vector2, target: Vector2) -> PackedVector2Array:
	return _site_route(origin, target, false)

func _site_route(origin: Vector2, target: Vector2, bounded: bool) -> PackedVector2Array:
	return _bounded_direct_resource_route(origin, target) if bounded else worksite_navigation.route(origin, target)

func _bounded_direct_resource_route(origin: Vector2, target: Vector2) -> PackedVector2Array:
	if worksite_navigation.segment_clear(origin, target):
		return PackedVector2Array([origin, target])
	# A blocked candidate must not stall the game while a visibility-grid
	# search expands. An unfinished search is never treated as a valid route.
	var search: RefCounted = worksite_navigation.begin_bounded_route(origin, target)
	search.step(100000, Time.get_ticks_usec() + RESOURCE_ROUTE_BUDGET_USEC)
	return search.path if search.status == "found" else PackedVector2Array()

func _route_on_land(route: PackedVector2Array, base: TileMapLayer, base2: TileMapLayer) -> bool:
	if route.is_empty():
		return false
	for index: int in range(1, route.size()):
		var start: Vector2 = route[index - 1]
		var finish: Vector2 = route[index]
		var steps: int = maxi(1, ceili(start.distance_to(finish) / 4.0))
		for step: int in range(steps + 1):
			var point: Vector2 = start.lerp(finish, float(step) / steps)
			if base.get_cell_source_id(base.local_to_map(base.to_local(point))) < 0 and base2.get_cell_source_id(base2.local_to_map(base2.to_local(point))) < 0:
				return false
	return true

func _refresh_navigation() -> void:
	var map: Node = navigation_map.get_ref() if navigation_map != null else null
	if navigation_map == null:
		map = self
		while map.get_parent() != null and map.get_parent() != get_tree().root:
			map = map.get_parent()
		navigation_map = weakref(map)
	# A parked runtime keeps its value geometry through the home handoff.
	if map == null or (map != self and not map.is_ancestor_of(self)):
		return
	worksite_navigation.configure(map)
	navigation_geometry_phases.clear()
	navigation_plot_templates.clear()
	_watch_navigation_changes(map)
	var visuals: Node = get_node_or_null("WorkerVisuals")
	if visuals != null:
		visuals.site_paths.clear()
		visuals.plot_presence.states.clear()
	navigation_refresh_pending = false
	_queue_depleted_sites()

func _watch_navigation_changes(node: Node) -> void:
	if node.is_in_group("workshop_plots") and node.construction != null:
		# Construction outlives a city plot while the player is at home. Bind its
		# stable ID so a later signal never carries a freed Node argument.
		var callback := Callable(self, "_queue_navigation_refresh").bind(node.construction.get_instance_id(), node.get_instance_id())
		if not node.construction.changed.is_connected(callback):
			node.construction.changed.connect(callback)
		navigation_phases[node.get_instance_id()] = node.construction.phase
		navigation_geometry_phases[node.construction.get_instance_id()] = node.construction.phase
		navigation_plot_templates[node.construction.get_instance_id()] = _plot_navigation_template(node)
	for child: Node in node.get_children():
		_watch_navigation_changes(child)

func can_simulate_plot_travel() -> bool:
	if navigation_refresh_pending or navigation_geometry_phases.is_empty():
		return false
	for state_id: int in navigation_geometry_phases:
		var state: Node = instance_from_id(state_id) as Node
		if not is_instance_valid(state) or state.phase != navigation_geometry_phases[state_id]:
			return false
	var store: Node = WorkStateRuntime.get_node_or_null("CitySave")
	if store != null and store.parked_worksite == self:
		for state: Node in store.city_plots.values():
			if not is_instance_valid(state) or not navigation_geometry_phases.has(state.get_instance_id()):
				return false
	else:
		var map: Node = navigation_map.get_ref() if navigation_map != null else null
		if not is_instance_valid(map) or not map.is_ancestor_of(self):
			return false
		for plot: Node in get_tree().get_nodes_in_group("workshop_plots"):
			if map.is_ancestor_of(plot) and (not is_instance_valid(plot.construction) or not navigation_geometry_phases.has(plot.construction.get_instance_id())):
				return false
	return true

func _queue_navigation_refresh(state_id: int, plot_id: int) -> void:
	var state: Node = instance_from_id(state_id) as Node
	if not is_instance_valid(state) or not navigation_geometry_phases.has(state_id):
		return
	var previous: String = str(navigation_geometry_phases[state_id])
	if previous == state.phase:
		return
	var store: Node = WorkStateRuntime.get_node_or_null("CitySave")
	if store != null and store.parked_worksite == self:
		# The city view is gone. Its captured phase shapes can be swapped now,
		# without waiting for a deferred physics update on freed scene nodes.
		if _update_parked_plot_geometry(state_id, previous, state.phase):
			navigation_geometry_phases[state_id] = state.phase
		return
	var template: Dictionary = navigation_plot_templates.get(state_id, {})
	if not template.is_empty() and (previous == "built") == (state.phase == "built"):
		# Known open phases share identical collision. Do not freeze unrelated
		# workers just because cleaning began or the rubble was cleared.
		navigation_geometry_phases[state_id] = state.phase
		navigation_phases[plot_id] = state.phase
		return
	var plot: Node = instance_from_id(plot_id) as Node
	if plot == null or not plot.is_inside_tree():
		return
	if navigation_phases.get(plot_id, "") == plot.construction.phase:
		return
	navigation_phases[plot_id] = plot.construction.phase
	# Queue behind the phase owners' deferred collider toggles even when this
	# callback happened to run before their own changed-signal callbacks.
	navigation_refresh_pending = true
	_queue_navigation_after_colliders.call_deferred()

func _queue_navigation_after_colliders() -> void:
	_refresh_navigation.call_deferred()

func _plot_navigation_template(plot: Node) -> Dictionary:
	if not plot is Node2D or not plot.has_method("is_citizen_house_plot"):
		return {}
	var plot_script: Script = plot.get_script() as Script
	if plot_script == null:
		return {}
	var script_path: String = plot_script.resource_path
	var open: Array[PackedVector2Array] = []
	var built: Array[PackedVector2Array] = []
	if script_path == "res://scenes/citizen_house_plot/citizen_house_plot.gd":
		var house_shape: CollisionShape2D = plot.get_node_or_null("HouseBody/CollisionShape2D") as CollisionShape2D
		if not _append_live_template_shape(house_shape, built):
			return {}
	elif script_path == "res://scenes/workshop_plot/keeper/workshop_keeper_plot.gd":
		for shape: CollisionShape2D in plot._open_shapes:
			if not _append_live_template_shape(shape, open):
				return {}
		for shape: CollisionShape2D in plot._built_shapes:
			if not _append_live_template_shape(shape, built):
				return {}
		if not _append_workshop_backend_shape(plot, built):
			return {}
	elif script_path == "res://scenes/workshop_plot/workshop_plot.gd":
		if not _append_workshop_backend_shape(plot, built):
			return {}
	else:
		# Unknown plot subclasses can retain their previous conservative guard.
		return {}
	return {"open": open, "built": built}

func _append_live_template_shape(shape: CollisionShape2D, destination: Array[PackedVector2Array]) -> bool:
	if shape == null or shape.shape == null:
		return false
	var body: StaticBody2D = shape.get_parent() as StaticBody2D
	if body == null:
		return false
	if body.collision_layer == 0:
		return true
	var polygons: Array[PackedVector2Array] = worksite_navigation.polygons_for_shape(shape.shape, shape.global_transform)
	if polygons.is_empty():
		return false # An unsupported or empty collider must not be ignored.
	destination.append_array(polygons)
	return true

func _append_workshop_backend_shape(plot: Node2D, destination: Array[PackedVector2Array]) -> bool:
	# The normal plot instantiates this backend with its default local transform.
	# Inspect its detached shape without entering the tree or starting gameplay.
	var backend: Node2D = WORKSHOP_BACKEND.instantiate() as Node2D
	if backend == null:
		return false
	var body: StaticBody2D = backend.get_node_or_null("StaticBody2D") as StaticBody2D
	var shape: CollisionShape2D = body.get_node_or_null("CollisionShape2D") as CollisionShape2D if body != null else null
	if shape == null or shape.shape == null:
		backend.free()
		return false
	if body.collision_layer == 0:
		backend.free()
		return true
	var transform: Transform2D = plot.global_transform * backend.transform * body.transform * shape.transform
	var polygons: Array[PackedVector2Array] = worksite_navigation.polygons_for_shape(shape.shape, transform)
	backend.free()
	if polygons.is_empty():
		return false
	destination.append_array(polygons)
	return true

func _update_parked_plot_geometry(state_id: int, previous: String, next: String) -> bool:
	var template: Dictionary = navigation_plot_templates.get(state_id, {})
	if template.is_empty():
		return false
	var old_key: String = "built" if previous == "built" else "open"
	var new_key: String = "built" if next == "built" else "open"
	if old_key == new_key:
		return true
	var polygons: Array[PackedVector2Array] = worksite_navigation.polygons.duplicate()
	for polygon: PackedVector2Array in template[old_key]:
		var index: int = polygons.find(polygon)
		if index < 0:
			return false # Never publish an uncertain collision snapshot.
		polygons.remove_at(index)
	polygons.append_array(template[new_key])
	worksite_navigation.replace_polygons(polygons)
	var visuals: Node = get_node_or_null("WorkerVisuals")
	if visuals != null:
		visuals.site_paths.clear()
		visuals.plot_presence.states.clear()
	return true

## New worker production is received once by City Storage. Old ground piles
## and returned legacy cargo still use _drop_daily_output and remain collectable.
func _deliver_daily_output(quantity: int, site: Marker2D) -> bool:
	if not is_instance_valid(site) or not sites.has(site.name) or not is_instance_valid(city_tools):
		return false
	return bool(city_tools.try_add_worksite_output(str(sites[site.name].item_id), quantity))

func _drop_daily_output(quantity: int, site: Marker2D) -> bool:
	if site.name != &"ReedSite":
		return super._drop_daily_output(quantity, site)
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(player):
		return false
	var destination: Vector2 = worksite_navigation.reachable_point(player.global_position + Vector2(0, -4), site.global_position + Vector2(0, 24))
	if not destination.is_finite():
		return false # The scheduler retains unclaimed units for a later retry.
	for stack: PickUpItem in $GroundOutput.get_children():
		if not stack.is_queued_for_deletion() and not stack.is_collecting and stack.get_meta("daily_site", "") == str(site.name):
			stack.global_position = destination
			stack.quantity += quantity
			stack.get_node("QuantityLabel").text = "x%d" % stack.quantity
			return true
	if not _drop_output_at(quantity, $GroundOutput.to_local(destination), _drop_daily_output.bind(site), sites[site.name].item_id):
		return false
	$GroundOutput.get_child(-1).set_meta("daily_site", str(site.name))
	return true

func _drop_output_at(quantity: int, drop_position: Vector2, return_remainder: Callable = Callable(), resource_id: String = "clay_lump") -> bool:
	var dropped: bool = super._drop_output_at(quantity, drop_position, return_remainder, resource_id)
	if dropped:
		# Keep the count node/text for merging, pickup feedback and restored piles.
		$GroundOutput.get_child(-1).get_node("QuantityLabel").hide()
	return dropped

## Legacy stockpile goods remain an ordinary world pile, but a large pile can
## be collected in portions without becoming a worksite Hauler target.
func _drop_legacy_stockpile_output(quantity: int, drop_position: Vector2, resource_id: String) -> bool:
	if quantity <= 0 or is_queued_for_deletion() or not is_inside_tree():
		return false
	var drop: PickUpItem = PICKUP_SCENE.instantiate()
	drop.set_script(LEGACY_PICKUP)
	drop.item_id = resource_id
	drop.quantity = quantity
	drop.position = drop_position
	drop.set_meta("legacy_stockpile", true)
	var count_label := Label.new()
	count_label.name = "QuantityLabel"
	count_label.text = "x%d" % quantity
	count_label.position = Vector2(-10, 4)
	count_label.add_theme_font_size_override("font_size", 8)
	count_label.hide()
	drop.add_child(count_label)
	$GroundOutput.add_child(drop)
	drop.play_drop_spawn_feedback()
	return true

# Physical records use feet coordinates; the visual's art origin is 16px above.
func worker_destination(site_id: StringName, id: String) -> Vector2:
	var ids: Array = daily.jobs[site_id].ids
	var slot: int = ids.find(id)
	var entries: Array[Vector2] = [site_slot_destination(site_id, 0), site_slot_destination(site_id, 1)]
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	var own_entry: int = _site_entry_index(worker, site_id, entries)
	var occupied: Array[bool] = [false, false]
	var claimed_by_earlier_worker: bool = false
	for index: int in range(ids.size()):
		var teammate_id: String = ids[index]
		if teammate_id == id:
			continue
		var teammate: WorkerData = WorkerDatabase.get_worker_data(teammate_id)
		var entry: int = _site_entry_index(teammate, site_id, entries)
		if entry < 0:
			# A teammate without a physical record is either a legacy worker or
			# another member whose approach has not been initialized yet.
			entry = index
		if entry >= 0 and entry < entries.size():
			occupied[entry] = true
			if index < slot and entry == own_entry:
				claimed_by_earlier_worker = true
	# Keep a worker's existing destination even when a former teammate's
	# removal changes the worker's list index. Old overlapping checkpoints
	# are separated on their next approach, in assignment order.
	if own_entry >= 0 and not claimed_by_earlier_worker:
		return entries[own_entry]
	if slot >= 0 and slot < entries.size() and not occupied[slot]:
		return entries[slot]
	for entry: int in range(entries.size()):
		if not occupied[entry]:
			return entries[entry]
	return entries[clampi(slot, 0, entries.size() - 1)]

func _site_entry_index(worker: WorkerData, site_id: StringName, entries: Array[Vector2]) -> int:
	if worker == null or worker.physical_approach.get("kind", "") != "site" or worker.physical_approach.get("owner", "") != str(site_id):
		return -1
	var target: Variant = worker.physical_approach.get("target")
	if not target is Vector2:
		return -1
	for index: int in range(entries.size()):
		if target.distance_to(entries[index]) <= 0.1:
			return index
	return -1

# Snapshot validation can resolve authored slots before live jobs are restored.
func site_slot_destination(site_id: StringName, slot: int) -> Vector2:
	var destination: Vector2 = get_node("WorksiteMarkers/" + str(site_id)).global_position + Vector2(-10 + slot * 20, 8)
	if worksite_navigation.resource_bottoms.has(str(site_id)):
		destination.y = maxf(destination.y, float(worksite_navigation.resource_bottoms[str(site_id)]) + worksite_navigation.CLEARANCE + 1.0)
	return destination

## Validation must compare a saved approach with the saved deposit position,
## not with whichever location happens to be live before the load commits.
func site_slot_destination_at_offset(site_id: StringName, slot: int, offset: Vector2) -> Vector2:
	var marker: Node2D = $WorksiteMarkers.get_node(NodePath(str(site_id)))
	var movement: Vector2 = marker.get_parent().global_transform.basis_xform(offset - resource_site_offset(site_id))
	return site_slot_destination(site_id, slot) + movement

func site_approach_task(site_id: StringName, id: String, day: int) -> String:
	var job: Dictionary = daily.jobs[site_id]
	return "%s:%d:%d" % [job.order, int(job.starts[id]), day]

func _begin_site_assignments(site_id: StringName, ids: Array[String]) -> void:
	for id: String in ids:
		if not daily.is_hauler(id):
			begin_site_approach(site_id, id, maxi(int(daily.jobs[site_id].starts[id]) / 1440, TimeComponentManager.current_day))

func begin_site_approach(site_id: StringName, id: String, day: int) -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if worker == null:
		return
	var feet: Vector2 = worker_spawn(site_id, id) + Vector2(0, 16)
	if not worker.physical_approach.is_empty():
		feet = worker.physical_approach.position
	var visuals: Node = get_node_or_null("WorkerVisuals")
	if visuals != null and visuals.actors.has(id):
		feet = visuals.actors[id].global_position + Vector2(0, 16)
	worker.begin_physical_approach("site", site_approach_task(site_id, id, day), str(site_id), feet, worker_destination(site_id, id))
	if visuals != null:
		visuals.work_cycles.erase(id)
		visuals.roaming.erase(id)
		visuals.site_paths.erase(id)

func _physical_site_arrival(site_id: StringName, id: String, day: int) -> int:
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	# Legacy saves have no approach evidence and retain their established state.
	if worker == null or worker.physical_approach.is_empty():
		return day * 1440 + daily.SHIFT_START
	if worker.matches_physical_approach("site", site_approach_task(site_id, id, day), str(site_id)) and worker.physical_approach.arrived:
		return int(worker.physical_approach.arrival_minute)
	return 2147483647

func _release_site_approach(id: String) -> void:
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if worker != null and worker.physical_approach.get("kind", "") == "site":
		worker.physical_approach = {}
	var visuals: Node = get_node_or_null("WorkerVisuals")
	if visuals != null:
		visuals.site_paths.erase(id)

func _open_content_preview() -> void:
	var result: Error = get_tree().change_scene_to_file("res://scenes/content_scene/content_scene.tscn")
	if result != OK:
		push_error("Worksites: content preview could not load (error %d)." % result)

func _can_open_worker_hub() -> bool:
	return player.can_move and not player.is_sleeping and not player.is_collapsing and not _working and not inspector.visible and not inventory_ui.visible and not get_tree().paused and not SceneTransition.is_transitioning

func _unhandled_input(event: InputEvent) -> void:
	# Existing map interactables (workshop, pickups, etc.) retain ownership of E.
	if event.is_action_pressed("interact") and is_instance_valid(player.current_interactable):
		return
	if OS.is_debug_build() and enable_time_shortcuts and event is InputEventKey and event.pressed and not event.echo and _can_open_worker_hub():
		if event.keycode == KEY_F7:
			TimeComponentManager.advance_minutes(30)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F:
			var minute_of_day: int = TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
			TimeComponentManager.advance_minutes(1440 - minute_of_day + 6 * 60 + 45)
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)

func _draw() -> void:
	# Site footprints are authored nodes; the prototype grid is not part of the map.
	pass

# Session-only stocks survive a trip home; this does not introduce a disk save.
func _exit_tree() -> void:
	# A home visit retains this live scheduler under CitySave. Reparenting must
	# not cancel jobs or discard in-flight cargo; normal teardown still cleans up.
	if checkpoint_handoff:
		return
	if retain_resource_stock and is_instance_valid(WorkStateRuntime):
		for session in sites.values():
			session.cancel()
		var snapshot: Dictionary = {"day": TimeComponentManager.current_day, "sites": {}, "storages": {}, "ground": [], "pending_output": {}, "pending_progress": {}}
		for id: StringName in sites:
			snapshot.sites[id] = {"stock": sites[id].stock, "offset": resource_site_offset(id),
				"respawn_started_at": sites[id].respawn_started_at, "respawn_due_at": sites[id].respawn_due_at} if finite_resource_sites else sites[id].stock
		for id: StringName in storage_destinations:
			var endpoint: Node = get_node_or_null(storage_destinations[id])
			if endpoint != null:
				snapshot.storages[id] = endpoint.get_storage().quantity
		for drop: Node in $GroundOutput.get_children():
			if not drop.is_queued_for_deletion() and not drop.is_collecting:
				snapshot.ground.append({"item_id": drop.item_id, "quantity": drop.quantity, "position": drop.position,
					"site": str(drop.get_meta("daily_site", "")), "legacy_stockpile": bool(drop.get_meta("legacy_stockpile", false))})
		for site_id: Variant in daily.pending_output:
			snapshot.pending_output[str(site_id)] = int(daily.pending_output[site_id].quantity)
		for site_id: Variant in daily.pending_progress:
			snapshot.pending_progress[str(site_id)] = daily.pending_progress[site_id].duplicate()
		WorkStateRuntime.set_meta(RESOURCE_STOCK_META, snapshot)
	super._exit_tree()

func _restore_resource_stock() -> void:
	var snapshot: Dictionary = WorkStateRuntime.get_meta(RESOURCE_STOCK_META, {})
	if snapshot.is_empty():
		return
	var saved_offsets: Dictionary = {}
	for id: StringName in sites:
		if not snapshot.sites.has(id):
			continue
		var record: Variant = snapshot.sites[id]
		if finite_resource_sites and record is Dictionary and record.has("stock") and resource_offset_valid(record.get("offset", Vector2.ZERO), id):
			sites[id].stock = int(record.stock)
			if int(record.stock) <= 0 and record.get("respawn_started_at") is int and record.get("respawn_due_at") is int \
				and int(record.respawn_started_at) >= 0 and int(record.respawn_due_at) - int(record.respawn_started_at) >= RESPAWN_MIN_MINUTES \
				and int(record.respawn_due_at) - int(record.respawn_started_at) <= RESPAWN_MAX_MINUTES:
				sites[id].respawn_started_at = int(record.respawn_started_at)
				sites[id].respawn_due_at = int(record.respawn_due_at)
			elif int(record.stock) <= 0:
				_sync_site_timer(id)
			saved_offsets[str(id)] = record
		elif int(snapshot.day) == TimeComponentManager.current_day and record is int:
			sites[id].stock = int(record)
	if not saved_offsets.is_empty():
		restore_resource_offsets(saved_offsets)
		sync_resource_presentation()
	for id: StringName in storage_destinations:
		if snapshot.storages.has(id):
			var storage: Node = get_node(storage_destinations[id]).get_storage()
			storage.quantity = int(snapshot.storages[id])
			storage.changed.emit()
	# An old in-memory scene handoff may still contain the former five piles.
	# Consume each count only after its replacement ground pile is present.
	for record: Dictionary in LEGACY_STOCKPILES.STOCKPILES.values():
		var id := StringName(record.site_id)
		if storage_destinations.has(id) or not snapshot.storages.has(id):
			continue
		var quantity: int = int(snapshot.storages[id])
		if quantity == 0:
			snapshot.storages.erase(id)
		elif quantity > 0 and _drop_legacy_stockpile_output(quantity, $GroundOutput.to_local(to_global(record.position)), str(record.item_id)):
			snapshot.storages.erase(id)
	for entry: Dictionary in snapshot.ground:
		var site_id := StringName(entry.site)
		if bool(entry.get("legacy_stockpile", false)):
			_drop_legacy_stockpile_output(entry.quantity, entry.position, entry.item_id)
			continue
		var callback := Callable()
		if sites.has(site_id):
			callback = _drop_daily_output.bind(get_node("WorksiteMarkers/" + str(site_id)))
		if _drop_output_at(entry.quantity, entry.position, callback, entry.item_id) and not str(site_id).is_empty():
			$GroundOutput.get_child(-1).set_meta("daily_site", str(site_id))
	for saved_id: Variant in snapshot.get("pending_output", {}):
		var site_id := StringName(saved_id)
		if sites.has(site_id):
			daily.pending_output[site_id] = {"quantity": int(snapshot.pending_output[saved_id]),
				"drop": _deliver_daily_output.bind(get_node("WorksiteMarkers/" + str(site_id)))}
	for saved_id: Variant in snapshot.get("pending_progress", {}):
		var site_id := StringName(saved_id)
		if sites.has(site_id):
			daily.pending_progress[site_id] = snapshot.pending_progress[saved_id].duplicate()
