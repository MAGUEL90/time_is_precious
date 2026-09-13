extends Node2D

const WorksiteSession = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_session.gd")
const DailySchedule = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_daily.gd")
const PICKUP_SCENE: PackedScene = preload("res://scenes/pickup_item/pickup_item.tscn")
const DAILY_PICKUP_SCRIPT = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_daily_pickup.gd")
const WORK_FADE_SECONDS: float = 0.15
const WORK_BLACKOUT_SECONDS: float = 1.0
signal work_finished
const INSPECTION_DISTANCE: float = 32.0 # Fixture interaction reach, not production tuning.
@export var prepare_overflow_test: bool = false
@export var prepare_nightmare_test: bool = false
@export var daily_stock_min: int = 72
@export var daily_stock_max: int = 72
@export var enable_worker_commute: bool = true
@export_range(1.0, 32.0, 1.0) var worker_walk_pixels_per_game_minute: float = 10.0
var worker_journeys: Dictionary = {}
var journey_cache_day: int = -1
@export var storage_destinations: Dictionary[StringName, NodePath] = {}
@export_range(0, 20, 1) var test_hauler_carts: int = 0
@export_node_path("Player") var player_path: NodePath = ^"Player"
@export_node_path("CanvasLayer") var inventory_ui_path: NodePath = ^"InventoryUI"
var hauling
var city_tools
var worker_management
var worker_control


@onready var player: Player = get_node_or_null(player_path)
@onready var inventory_ui: CanvasLayer = get_node_or_null(inventory_ui_path)
@onready var inspector: Control = $InspectionUI/ClayWorksiteInspector

var _previous_can_move: bool = true
var sites: Dictionary = {}
var daily = DailySchedule.new()
var _selected_site: Marker2D
var _working: bool = false
var _pickup_focused: bool = false
var last_work_result: Dictionary = {}

func _ready() -> void:
	inspector.close_requested.connect(_close_inspector)
	inspector.work_requested.connect(_start_work)
	inspector.participant_toggled.connect(_toggle_participant)
	inspector.worker_setup_discarded.connect(_reset_worker_draft)
	inspector.worker_removed.connect(_remove_worker)
	inspector.assignment_ui.destination_choices_provider = _storage_choices
	inspector.assignment_ui.hauler_assignment = _assign_hauler
	for site: Marker2D in $WorksiteMarkers.get_children():
		sites[site.name] = WorksiteSession.new()
		sites[site.name].reserved_slots = daily.active_count.bind(site.name)
	daily.setup(sites)
	city_tools = preload("res://scenes/storage_destination/city_tool_storage.gd").new()
	city_tools.name = "CityToolStorage"
	add_child(city_tools)
	for index: int in range(test_hauler_carts):
		city_tools.add_tool_unit("test_cart_%d" % index, "cart", "Cart %d" % (index + 1))
	worker_management = preload("res://scenes/test_scenes/clay_worksite_test/clay_worker_management.gd").new()
	worker_management.storage = city_tools
	worker_management.schedule = daily
	daily.tool_requirement = _worker_tool_requirement
	daily.gathered.connect(worker_management.record_contribution)
	daily.journey_provider = worker_journey
	hauling = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_hauling.gd").new()
	hauling.destination_provider = _storage_destination
	hauling.assigned_destination_provider = _assigned_storage_destination
	hauling.origin_provider = func(site_id: StringName, id: String): return worker_destination(site_id, id) - Vector2(0, 16)
	hauling.take_output = _take_daily_output
	hauling.output_count = _daily_output_count
	hauling.return_output = func(site_id: StringName, quantity: int): return _drop_daily_output(quantity, get_node("WorksiteMarkers/" + str(site_id)))
	hauling.speed = worker_walk_pixels_per_game_minute
	hauling.delivered.connect(_hauler_delivered)
	daily.hauling = hauling
	daily.hauler_ready = _hauler_ready
	worker_control = preload("res://scenes/test_scenes/ui_sandbox/worker_control/worker_control.tscn").instantiate()
	worker_control.rows_provider = worker_management.rows
	worker_control.tools_provider = worker_management.tools_for
	worker_control.can_open = func(): return not inspector.visible and not _working and not inventory_ui.visible and not player.is_collapsing and not SceneTransition.is_transitioning
	add_child(worker_control)
	worker_control.equip_requested.connect(func(id: String, unit_id: String):
		var feedback: String = worker_management.equip(id, unit_id)
		worker_control.refresh.call_deferred()
		worker_control.set_feedback.call_deferred(feedback)
	)
	worker_control.unequip_requested.connect(func(id: String, unit_id: String):
		var feedback: String = worker_management.unequip(id, unit_id)
		worker_control.refresh.call_deferred()
		worker_control.set_feedback.call_deferred(feedback)
	)
	worker_control.remove_requested.connect(func(id: String):
		var feedback: String = worker_management.fire(id)
		worker_control.refresh.call_deferred()
		worker_control.set_feedback.call_deferred(feedback)
	)
	worker_control.goto_requested.connect(_go_to_worker)
	var visuals = Node2D.new()
	visuals.set_script(preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_worker_visuals.gd"))
	visuals.name = "WorkerVisuals"
	add_child(visuals)
	daily.stock_min = maxi(daily_stock_min, 0)
	daily.stock_max = maxi(daily_stock_max, daily.stock_min)
	TimeComponentManager.minute_changed.connect(_advance_worker_jobs)
	call_deferred("_prepare_overflow_test")
	call_deferred("_prepare_nightmare_test")

func _storage_destination(site_id: StringName):
	return get_node_or_null(storage_destinations.get(site_id, NodePath(""))) if storage_destinations.has(site_id) else null

func _assigned_storage_destination(path: NodePath) -> StorageDestination:
	return get_node_or_null(path) as StorageDestination if not path.is_empty() else null

func _storage_choices() -> Array[Dictionary]:
	var destinations: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group("storage_destinations"):
		if is_ancestor_of(node) and not node.is_queued_for_deletion():
			destinations.append(node)
	for site_id in storage_destinations:
		var node = _storage_destination(site_id)
		if is_instance_valid(node) and not node.is_queued_for_deletion() and not destinations.has(node):
			destinations.append(node)
	var choices: Array[Dictionary] = []
	for node: StorageDestination in destinations:
		choices.append({"path": get_path_to(node), "name": node.display_name, "available": node.is_available()})
	choices.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return choices

func _assign_hauler(id: String, destination_path: NodePath, daily_target: int) -> String:
	if _working or not inspector.visible or not is_instance_valid(_selected_site):
		return "Worksite is unavailable."
	for entry: Dictionary in _storage_choices():
		if entry.path == destination_path and bool(entry.available):
			if daily.select_hauler(_selected_site.name, id, destination_path, str(entry.name), daily_target):
				inspector.refresh_team()
				return ""
			return "Worker unavailable or target invalid."
	return "Storage is unavailable. Choose again."

func _go_to_worker(id: String) -> void:
	var site_id: StringName = worker_management.assigned_site(id)
	if site_id.is_empty() or not worker_management.is_active(id):
		return
	var site := get_node_or_null("WorksiteMarkers/" + str(site_id)) as Marker2D
	if site == null or _working or player.is_collapsing or SceneTransition.is_transitioning:
		return
	worker_control.close()
	_open_site_panel(site)

func _open_site_panel(site: Marker2D) -> void:
	_previous_can_move = player.can_move
	_selected_site = site
	player.can_move = false
	player.velocity = Vector2.ZERO
	$FixtureNotes/Label.hide()
	_hide_prompts()
	inspector.show_site(site.get_node("Label").text, player, _preview_work, _get_roster)
func _hauler_ready(site_id: StringName, _count: int) -> String:
	for id: String in daily.selected[site_id]:
		if not daily.is_hauler(id):
			continue
		var plan: Dictionary = daily.hauler_setups.get(id, {})
		var destination = _assigned_storage_destination(plan.get("destination_path", NodePath("")))
		if destination == null or destination.is_queued_for_deletion() or not destination.is_available():
			return "Selected Hauler storage is unavailable."
	return ""

func _worker_tool_requirement(id: String) -> String:
	if daily.is_hauler(id) and not city_tools.has_equipped(id, "cart"):
		return "Requires a cart. Equip in Worker Hub."
	return ""

func _hauler_delivered(id: String, quantity: int) -> void:
	worker_management.record_contribution(id, quantity)
	for job: Dictionary in daily.jobs.values():
		if job.stats.has(id):
			job.stats[id].output += quantity
			if not job.stats[id].days.has(TimeComponentManager.current_day):
				job.stats[id].days.append(TimeComponentManager.current_day)

func _daily_output_count(site_id: StringName) -> int:
	var quantity: int = 0
	for stack: PickUpItem in $GroundOutput.get_children():
		if not stack.is_queued_for_deletion() and not stack.is_collecting and stack.get_meta("daily_site", "") == str(site_id):
			quantity += stack.quantity
	return quantity

func _take_daily_output(site_id: StringName, maximum: int) -> int:
	var taken: int = 0
	for stack: PickUpItem in $GroundOutput.get_children():
		if stack.is_queued_for_deletion() or stack.is_collecting or stack.get_meta("daily_site", "") != str(site_id):
			continue
		var count: int = mini(stack.quantity, maximum - taken)
		stack.quantity -= count
		taken += count
		if stack.quantity <= 0:
			stack.queue_free()
		else:
			stack.get_node("QuantityLabel").text = "x%d" % stack.quantity
		if taken >= maximum:
			break
	return taken

func _prepare_nightmare_test() -> void:
	if not prepare_nightmare_test or get_tree().current_scene != self:
		return
	player.fatigue = 0.89
	player.hunger = 0.0
	player.focus = 1.0
	player.condition_changed.emit()
	player.global_position = $WorksiteMarkers/ClaySiteA.global_position

func worker_destination(site_id: StringName, id: String) -> Vector2:
	var slot: int = daily.jobs[site_id].ids.find(id)
	return get_node("WorksiteMarkers/" + str(site_id)).global_position + Vector2(-10 + slot * 20, 8)

func worker_spawn(site_id: StringName, id: String) -> Vector2:
	var markers: Array[Node] = $WorkerDeparture.get_children()
	var slot: int = daily.jobs[site_id].ids.find(id)
	if not markers.is_empty():
		return markers[maxi(slot, 0) % markers.size()].global_position + Vector2(0, -16)
	return $WorkerDeparture.global_position + Vector2(0, -16)

func worker_journey(site_id: StringName, id: String, day: int) -> Dictionary:
	if journey_cache_day != TimeComponentManager.current_day:
		worker_journeys.clear()
		journey_cache_day = TimeComponentManager.current_day
	var key: String = "%s:%s:%d" % [site_id, id, day]
	if worker_journeys.has(key) and daily.now() >= int(floor(worker_journeys[key].start)):
		return worker_journeys[key]
	var origin: Vector2 = worker_spawn(site_id, id)
	var visuals = get_node_or_null("WorkerVisuals")
	if visuals != null and visuals.actors.has(id) and visuals.actors[id].visible:
		origin = visuals.actors[id].global_position
	var destination: Vector2 = worker_destination(site_id, id) + Vector2(0, -16)
	var arrival: int = day * 1440 + DailySchedule.SHIFT_START
	var duration: float = origin.distance_to(destination) / worker_walk_pixels_per_game_minute if enable_worker_commute else 0.0
	var route: Dictionary = {"origin": origin, "target": destination, "start": arrival - duration, "arrival": arrival}
	worker_journeys[key] = route
	return route

func _reset_worker_draft() -> void:
	if not is_instance_valid(_selected_site):
		return
	daily.discard_setup(_selected_site.name)

func _remove_worker(id: String) -> void:
	if is_instance_valid(_selected_site):
		daily.withdraw(_selected_site.name, id)
		inspector.refresh_team.call_deferred()

func _exit_tree() -> void:
	if worker_management != null:
		if daily.gathered.is_connected(worker_management.record_contribution):
			daily.gathered.disconnect(worker_management.record_contribution)
		worker_management.schedule = null
	if TimeComponentManager.minute_changed.is_connected(_advance_worker_jobs):
		TimeComponentManager.minute_changed.disconnect(_advance_worker_jobs)
	for session in sites.values():
		session.cancel()
		session.reserved_slots = Callable()
	daily.cleanup()

func _advance_worker_jobs(_minute: int) -> void:
	daily.tick()
	if worker_control != null and worker_control.visible:
		worker_control.refresh()

func _prepare_overflow_test() -> void:
	# Seed only a directly launched F6 fixture, never fixtures inside regression tests.
	if not prepare_overflow_test or get_tree().current_scene != self:
		return
	player.fatigue = 0.5
	player.hunger = 0.0
	player.focus = 1.0
	player.condition_changed.emit()
	var clay: ItemData = ItemDatabase.get_item_data("clay_lump")
	if clay == null or clay.weight <= 0.0:
		return
	# Leave room for two clay. Preserve any inventory that was already present.
	var fill_quantity: int = maxi(int(floor(Inventory.get_remaining_capacity() / clay.weight)) - 2, 0)
	if fill_quantity > 0:
		Inventory.try_add_item("clay_lump", fill_quantity)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or event.is_echo():
		return
	if _working or not player.can_move or player.is_collapsing or player.is_sleeping or SceneTransition.is_transitioning or inventory_ui.visible or get_tree().paused:
		return
	# Let existing pickups own E when a ground stack is focused.
	if _pickup_focused or (is_instance_valid(player.current_interactable) and player.current_interactable is PickUpItem):
		return
	var nearest: Marker2D = null
	var nearest_distance: float = INSPECTION_DISTANCE
	for site: Marker2D in $WorksiteMarkers.get_children():
		var distance: float = player.global_position.distance_to(site.global_position)
		if distance <= nearest_distance:
			nearest = site
			nearest_distance = distance
	if nearest == null:
		return
	_open_site_panel(nearest)
	get_viewport().set_input_as_handled()

func _close_inspector() -> void:
	if not inspector.visible or _working:
		return
	inspector.close_panel()
	_reset_worker_draft()
	if not player.is_collapsing and not SceneTransition.is_transitioning:
		player.can_move = _previous_can_move
	$FixtureNotes/Label.show()

func _preview_work(minutes: int) -> Dictionary:
	var session = sites[_selected_site.name]
	if inspector.work_mode != "Hourly":
		var ids: Array = daily.selected[_selected_site.name]
		var names: PackedStringArray = []
		for id: String in ids:
			var worker: WorkerData = WorkerDatabase.get_worker_data(id)
			names.append(worker.get_resolved_display_name() if worker != null else "Unavailable")
		var reason: String = "" if not ids.is_empty() or daily.reserved_count(_selected_site.name) > 0 else "Assign workers to begin."
		var active_ids: Array = daily.jobs[_selected_site.name].ids if daily.jobs.has(_selected_site.name) else []
		for id: String in ids:
			if not active_ids.has(id) and not daily.unavailable(id).is_empty():
				reason = "Selected worker is unavailable."
		if reason.is_empty():
			reason = daily.start_reason(_selected_site.name)
		return {"units": 0, "minutes": 0, "reason": reason, "worker_count": ids.size() + active_ids.size(),
			"active_count": active_ids.size(), "has_draft": not ids.is_empty(),
			"worker_progress": daily.progress_rows(_selected_site.name),
			"worker_capacity": 2, "includes_player": false, "working": false,
			"worker_names": ", ".join(names),
			"duration_text": "Duration: %d h / day\n%02d:%02d - %02d:%02d" % [
				floori(DailySchedule.DAILY_LIMIT / 60.0), floori(DailySchedule.SHIFT_START / 60.0),
				DailySchedule.SHIFT_START % 60, floori(DailySchedule.SHIFT_END / 60.0),
				DailySchedule.SHIFT_END % 60]}
	session.participants.assign(["player"])
	return session.preview(minutes, player)

func _get_roster() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for worker: WorkerData in WorkerDatabase.get_all_workers():
		entries.append({
			"id": worker.worker_id, "name": worker.get_resolved_display_name(),
			"profession": WorkerData.Profession.keys()[worker.profession].capitalize(),
			"selected": daily.selected[_selected_site.name].has(worker.worker_id),
			"slots_available": 2 - daily.reserved_count(_selected_site.name),
			"reason": daily.unavailable(worker.worker_id)
		})
	return entries

func _toggle_participant(id: String) -> void:
	if _working or not inspector.visible or not is_instance_valid(_selected_site):
		return
	daily.toggle(_selected_site.name, id)
	inspector.refresh_team()

func _start_work(minutes: int) -> void:
	if _working or not inspector.visible or not is_instance_valid(_selected_site):
		return
	if not str(_preview_work(minutes).reason).is_empty():
		inspector.refresh_team()
		return
	if inspector.work_mode == "Daily":
		if daily.start(_selected_site.name, _drop_daily_output.bind(_selected_site)):
			_close_inspector()
		else:
			inspector.refresh_team()
		return
	_working = true
	inspector.set_busy(true)
	_hide_prompts()
	var blackout: ColorRect = $WorkTransition/Blackout
	var interruption_message: Label = $WorkTransition/Blackout/InterruptionMessage
	interruption_message.text = ""
	interruption_message.hide()
	blackout.modulate.a = 0.0
	blackout.show()
	await _fade_work(1.0)
	if is_queued_for_deletion():
		return
	# Keep the modal's tree pause during the synchronous time skip. Restore movement
	# before signals run so collapse captures the correct pre-work movement state.
	player.can_move = _previous_can_move
	last_work_result = sites[_selected_site.name].execute(minutes, player, self, _drop_output)
	if last_work_result.interrupted:
		var reason: String = "Too exhausted to continue." if player.is_collapsing else "Work interrupted."
		interruption_message.text = "%s\nWorked %d min." % [reason, int(last_work_result.minutes)]
		interruption_message.show()
	player.can_move = false
	await get_tree().create_timer(WORK_BLACKOUT_SECONDS, true).timeout
	if player.is_collapsing:
		# Close behind opaque black, then resume the existing faint/Nightmare flow.
		# Keep our cover until the global transition owns an opaque frame.
		inspector.close_panel()
		$FixtureNotes/Label.hide()
		while player.is_collapsing and SceneTransition.fade_overlay.modulate.a < 0.999:
			await get_tree().process_frame
		interruption_message.hide()
		if SceneTransition.fade_overlay.modulate.a < 0.999:
			await _fade_work(0.0)
		blackout.hide()
		_working = false
		inspector.set_busy(false)
		work_finished.emit()
		return
	# Remove the panel behind opaque black; keep the modal input/pause lock until
	# the world reveal finishes.
	inspector.window.hide()
	await _fade_work(0.0)
	blackout.hide()
	interruption_message.hide()
	_working = false
	inspector.set_busy(false)
	_close_inspector()
	inspector.window.show()
	$FixtureNotes/Label.text = "Gathered %d clay in %d min%s\nApproach a site and press E to work" % [
		int(last_work_result.units), int(last_work_result.minutes),
		" (interrupted)" if last_work_result.interrupted else ""
	]
	if last_work_result.interrupted:
		$FixtureNotes/Label.hide()
	work_finished.emit()

func _fade_work(alpha: float) -> void:
	var tween: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property($WorkTransition/Blackout, "modulate:a", alpha, WORK_FADE_SECONDS)
	await tween.finished

func _drop_output(quantity: int) -> bool:
	return _drop_output_at(quantity, $GroundOutput.to_local(player.global_position + Vector2(0, 16)))

func _drop_daily_output(quantity: int, site: Marker2D) -> bool:
	if not is_inside_tree() or is_queued_for_deletion():
		return false
	for stack: PickUpItem in $GroundOutput.get_children():
		if not stack.is_queued_for_deletion() and not stack.is_collecting and stack.get_meta("daily_site", "") == str(site.name):
			stack.quantity += quantity
			stack.get_node("QuantityLabel").text = "x%d" % stack.quantity
			return true
	if not _drop_output_at(quantity, $GroundOutput.to_local(site.global_position + Vector2(0, 24)), _drop_daily_output.bind(site)):
		return false
	$GroundOutput.get_child(-1).set_meta("daily_site", str(site.name))
	return true

func _drop_output_at(quantity: int, drop_position: Vector2, return_remainder: Callable = Callable()) -> bool:
	if is_queued_for_deletion() or not is_inside_tree():
		return false
	var drop: PickUpItem = PICKUP_SCENE.instantiate()
	if return_remainder.is_valid():
		drop.set_script(DAILY_PICKUP_SCRIPT)
		drop.return_remainder = return_remainder
	drop.item_id = "clay_lump"
	drop.quantity = quantity
	drop.position = drop_position
	$GroundOutput.add_child(drop)
	var count_label := Label.new()
	count_label.name = "QuantityLabel"
	count_label.text = "x%d" % quantity
	count_label.position = Vector2(-10, 4)
	count_label.add_theme_font_size_override("font_size", 8)
	drop.add_child(count_label)
	drop.play_drop_spawn_feedback()
	return true

func _process(_delta: float) -> void:
	_pickup_focused = is_instance_valid(player.current_interactable) and player.current_interactable is PickUpItem
	var nearest: Marker2D = null
	var distance: float = INSPECTION_DISTANCE
	if player.can_move and not _working and not inspector.visible and not inventory_ui.visible and not player.is_collapsing and not SceneTransition.is_transitioning and not is_instance_valid(player.current_interactable):
		for site: Marker2D in $WorksiteMarkers.get_children():
			var candidate: float = player.global_position.distance_to(site.global_position)
			if candidate <= distance:
				nearest = site
				distance = candidate
	for site: Marker2D in $WorksiteMarkers.get_children():
		site.get_node("InteractPrompt").visible = site == nearest

func _hide_prompts() -> void:
	for site: Marker2D in $WorksiteMarkers.get_children():
		site.get_node("InteractPrompt").hide()

func _draw() -> void:
	var ground := Rect2(-320, -180, 640, 360)
	draw_rect(ground, Color("343d35"))
	for x: int in range(-320, 321, 16):
		draw_line(Vector2(x, -180), Vector2(x, 180), Color("3c453d"))
	for y: int in range(-180, 181, 16):
		draw_line(Vector2(-320, y), Vector2(320, y), Color("3c453d"))
	for site: Node2D in [$WorksiteMarkers/ClaySiteA, $WorksiteMarkers/ClaySiteB]:
		draw_circle(site.position, 20.0, Color("80624b"))
		draw_arc(site.position, 20.0, 0.0, TAU, 32, Color("cba477"), 1.0)
