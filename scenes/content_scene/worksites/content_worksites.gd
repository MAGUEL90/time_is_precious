extends "res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.gd"

## Content adapter for the tested worksite loop. Uses the map's existing Player/HUD.
## City stock uses the existing runtime host; other worksite data remains scene-local.
## Never opens or overwrites the prototype save slot.
@export_category("Content playtest")
@export var seed_playtest_equipment: bool = false
@export var seed_playtest_hauler: bool = false
@export var enable_time_shortcuts: bool = true
@export var retain_resource_stock: bool = false
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
	super._ready()
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
