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
var navigation_map: WeakRef
var navigation_phases: Dictionary = {}

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
	super._ready()
	for site: Node2D in $WorksiteMarkers.get_children():
		RESOURCE_PRESENTATION.configure(site)
	_refresh_navigation()
	if retain_resource_stock:
		_restore_resource_stock()
	# Notes belong to the isolated fixture, not the content HUD.
	$FixtureNotes.hide()
	$WorkerVisuals.y_sort_enabled = true
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
	_watch_navigation_changes(map)
	var visuals: Node = get_node_or_null("WorkerVisuals")
	if visuals != null:
		visuals.site_paths.clear()

func _watch_navigation_changes(node: Node) -> void:
	if node.has_method("get_built_footprints") and node.construction != null:
		# Construction outlives a city plot while the player is at home. Bind its
		# stable ID so a later signal never carries a freed Node argument.
		var callback := Callable(self, "_queue_navigation_refresh").bind(node.get_instance_id())
		if not node.construction.changed.is_connected(callback):
			node.construction.changed.connect(callback)
		navigation_phases[node.get_instance_id()] = node.construction.phase
	for child: Node in node.get_children():
		_watch_navigation_changes(child)

func _queue_navigation_refresh(plot_id: int) -> void:
	var plot: Node = instance_from_id(plot_id) as Node
	if plot == null or not plot.is_inside_tree():
		return
	if navigation_phases.get(plot_id, "") == plot.construction.phase:
		return
	navigation_phases[plot_id] = plot.construction.phase
	# Phase owners defer collider toggles; collect their final active geometry.
	_refresh_navigation.call_deferred()

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

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(_highlighted_site):
		var prompt: InteractableLabelComponent = _highlighted_site.get_node("InteractPrompt")
		if prompt.visible:
			if _highlighted_site.name in [&"ClaySiteA", &"WoodSite", &"ReedSite"]:
				prompt.place_below_player(player)
			else:
				prompt.place_above_player(player)

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
		var snapshot: Dictionary = {"day": TimeComponentManager.current_day, "sites": {}, "storages": {}, "ground": []}
		for id: StringName in sites:
			snapshot.sites[id] = sites[id].stock
		for id: StringName in storage_destinations:
			var endpoint: Node = get_node_or_null(storage_destinations[id])
			if endpoint != null:
				snapshot.storages[id] = endpoint.get_storage().quantity
		for drop: Node in $GroundOutput.get_children():
			if not drop.is_queued_for_deletion() and not drop.is_collecting:
				snapshot.ground.append({"item_id": drop.item_id, "quantity": drop.quantity, "position": drop.position,
					"site": str(drop.get_meta("daily_site", ""))})
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
	for entry: Dictionary in snapshot.ground:
		var site_id := StringName(entry.site)
		var callback := Callable()
		if sites.has(site_id):
			callback = _drop_daily_output.bind(get_node("WorksiteMarkers/" + str(site_id)))
		if _drop_output_at(entry.quantity, entry.position, callback, entry.item_id) and not str(site_id).is_empty():
			$GroundOutput.get_child(-1).set_meta("daily_site", str(site_id))
