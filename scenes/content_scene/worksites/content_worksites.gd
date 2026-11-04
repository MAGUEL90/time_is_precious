extends "res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.gd"

## Content adapter for the tested worksite loop. Uses the map's existing Player/HUD.
## City stock uses the existing runtime host; other worksite data remains scene-local.
## Never opens or overwrites the prototype save slot.
@export_category("Content playtest")
@export var seed_playtest_equipment: bool = false
@export var seed_playtest_hauler: bool = false
@export var enable_time_shortcuts: bool = true
@export var retain_resource_stock: bool = false
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
		RESOURCE_PRESENTATION.configure(site)
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
	worker_control.can_open = _can_open_worker_hub
	# Resource-only map sections can reuse this adapter without a city warehouse.
	var city_storage_area: Node = get_node_or_null("CityStorageArea")
	if city_storage_area != null:
		city_storage_area.configure(player, city_tools, _can_open_worker_hub)
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
	return site_slot_destination(site_id, daily.jobs[site_id].ids.find(id))

# Snapshot validation can resolve authored slots before live jobs are restored.
func site_slot_destination(site_id: StringName, slot: int) -> Vector2:
	var destination: Vector2 = get_node("WorksiteMarkers/" + str(site_id)).global_position + Vector2(-10 + slot * 20, 8)
	if worksite_navigation.resource_bottoms.has(str(site_id)):
		destination.y = maxf(destination.y, float(worksite_navigation.resource_bottoms[str(site_id)]) + worksite_navigation.CLEARANCE + 1.0)
	return destination

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
			snapshot.sites[id] = sites[id].stock
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
	if int(snapshot.day) == TimeComponentManager.current_day:
		for id: StringName in sites:
			if snapshot.sites.has(id):
				sites[id].stock = int(snapshot.sites[id])
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
				"drop": _drop_daily_output.bind(get_node("WorksiteMarkers/" + str(site_id)))}
	for saved_id: Variant in snapshot.get("pending_progress", {}):
		var site_id := StringName(saved_id)
		if sites.has(site_id):
			daily.pending_progress[site_id] = snapshot.pending_progress[saved_id].duplicate()
