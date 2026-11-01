extends Node2D

var fixture
var storage
var destination
var failures: int = 0
var ids: Array[String] = ["hauler_demo_laborer", "hauler_demo_hauler"]
var manual_withdrawn: int = 0
var seeded_output: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var automated: bool = OS.get_environment("TIP_TEST_HAULER") == "1"
	if automated:
		# Make the fixture begin before today's shift without depending on the
		# project's default start hour or advancing a negative number of minutes.
		TimeComponentManager.set_process(false)
		TimeComponentManager.is_paused = false
		TimeComponentManager.current_hour = 6
		TimeComponentManager.current_minute = 45
		TimeComponentManager._timer = 0.0
	fixture = preload("res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn").instantiate()
	fixture.prepare_nightmare_test = false
	fixture.test_hauler_carts = 1
	add_child(fixture)
	fixture.player.debug_disable_player_needs = true
	fixture.player.position = Vector2(0, 30)
	if automated:
		# The Player attaches its cursor with call_deferred; let that attachment
		# finish before this synchronous clock test can destroy the fixture.
		await get_tree().process_frame
	fixture.get_node("FixtureNotes/Label").text = "K: Worker Hub | 3 items / trip\nF7: advance 30 minutes"
	storage = preload("res://scenes/test_scenes/clay_worksite_test/hauler_test_storage.gd").new()
	storage.name = "TestStorage"
	fixture.add_child(storage)
	destination = preload("res://scenes/storage_destination/storage_destination.tscn").instantiate()
	destination.name = "StorageDestination"
	destination.display_name = "Storage A"
	destination.position = Vector2(80, -65)
	fixture.add_child(destination)
	destination.storage_path = destination.get_path_to(storage)
	fixture.storage_destinations[&"ClaySiteA"] = fixture.get_path_to(destination)
	var outline := Polygon2D.new()
	outline.polygon = PackedVector2Array([Vector2(-16,-12),Vector2(16,-12),Vector2(16,12),Vector2(-16,12)])
	outline.color = Color("80624b")
	destination.add_child(outline)
	var label := Label.new()
	label.position = Vector2(-28, 14)
	label.add_theme_font_size_override("font_size", 6)
	destination.add_child(label)
	storage.changed.connect(func(): label.text = "Storage: %d / %d" % [storage.quantity, storage.capacity])
	storage.changed.emit()
	fixture.city_tools.add_tool_unit("test_hammer", "stone_hammer", "Stone Hammer")
	fixture.city_tools.add_tool_unit("test_basic_glove", "basic_glove", "Basic Glove")
	for index: int in range(2):
		var worker := WorkerData.new()
		worker.worker_id = ids[index]
		worker.display_name = "Arad" if index == 0 else "Belum"
		worker.profession = WorkerData.Profession.LABORER if index == 0 else WorkerData.Profession.HAULER
		# Give demo citizens explicit profiles so the light-only cart assets can be audited.
		var citizen := CitizenData.new()
		citizen.citizen_id = worker.worker_id
		citizen.display_name = worker.display_name
		citizen.profession = worker.profession
		citizen.population_status = CitizenData.PopulationStatus.RESIDENT
		citizen.employment_status = CitizenData.EmploymentStatus.HIRED
		citizen.visual_profile = VisualProfile.new()
		citizen.visual_profile.hair_style = "default"
		citizen.visual_profile.clothes_id = "default"
		CitizenManager.add_citizen(citizen)
		WorkerDatabase.workers_by_id[worker.worker_id] = worker
		if index == 1:
			_expect(not fixture.daily.toggle(&"ClaySiteA", worker.worker_id), "Hauler cannot be assigned without an equipped cart.")
			_expect(fixture.worker_management.equip(worker.worker_id, "test_cart_0") == "Tool equipped.", "Hauler equips the fixture's city-owned cart.")
		if index == 1:
			# Keep enough target headroom to exercise removal and shift boundaries.
			var target: int = 1000 if automated else 20
			_expect(fixture.daily.select_hauler(&"ClaySiteA", worker.worker_id, fixture.get_path_to(destination), destination.display_name, target), "Hauler selects the real destination and target.")
		else:
			_expect(fixture.daily.toggle(&"ClaySiteA", worker.worker_id), "Laborer joins the worksite draft.")
	var started: bool = fixture.daily.start(&"ClaySiteA", fixture._drop_daily_output.bind(fixture.get_node("WorksiteMarkers/ClaySiteA")))
	_expect(started, "Mixed team starts with destination and cart.")
	if not started:
		if automated:
			_finish()
		return
	if not automated:
		return
	get_tree().paused = false
	var start: int = fixture.daily.jobs[&"ClaySiteA"].starts[ids[0]]
	_expect(start == TimeComponentManager.current_day * 1440 + fixture.daily.SHIFT_START, "Before-shift assignments begin at 07:00 today.")
	if not _advance(start - fixture.daily.now()):
		_finish()
		return
	_expect(fixture.daily.jobs[&"ClaySiteA"].stats[ids[0]].output == 0, "No work is awarded before shift start.")
	if not _advance(180):
		_finish()
		return
	_expect(int(fixture.daily.jobs[&"ClaySiteA"].stats[ids[0]].output) == 18, "Only the Laborer gathers 18 clay over exactly three paid shift hours.")
	_expect(int(fixture.daily.minutes_by_worker.get(ids[0], 0)) == 180, "The work ledger records exactly 180 productive minutes.")
	_expect(storage.quantity >= 6, "Hauler completes multiple deliveries.")
	_check_conservation()
	if DisplayServer.get_name() != "headless" and not OS.get_environment("TEMP").is_empty():
		fixture.get_node("WorkerVisuals")._process(0.0)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("tip-hauler-cycle.png"))
	# Close storage while cargo is already travelling: return the load safely.
	var attempts: int = 0
	while _carried() == 0 and attempts < 90:
		if not _advance(1):
			_finish()
			return
		attempts += 1
	_expect(_carried() == 3, "Each full trip carries exactly three items.")
	if _carried() != 3:
		_finish()
		return
	var hauler_actor = _hauler_actor()
	if is_instance_valid(hauler_actor):
		_expect(hauler_actor.visible and str(hauler_actor.body_sprite.animation).contains("push_cart"), "Travelling Hauler uses the imported cart pose.")
	var before_rejection: int = storage.quantity
	var xp_before_rejection: int = WorkerDatabase.get_worker_data(ids[1]).profession_xp
	destination.accepting_deliveries = false
	_advance(60)
	_expect(_carried() == 0 and storage.quantity == before_rejection
		and WorkerDatabase.get_worker_data(ids[1]).profession_xp == xp_before_rejection, "Rejected delivery returns cargo without storage or XP credit.")
	_check_conservation()
	destination.accepting_deliveries = true
	_advance(1)
	_expect(_carried() == 3, "Available destination permits another load.")
	if _carried() != 3:
		_finish()
		return
	var before_removal: int = storage.quantity
	_expect(fixture.daily.withdraw(&"ClaySiteA", ids[1]), "Loaded Hauler removal is accepted.")
	_expect(WorkerDatabase.get_worker_data(ids[1]).is_reserved(), "Loaded removal waits for current trip.")
	_advance(60)
	_expect(not WorkerDatabase.get_worker_data(ids[1]).is_reserved() and storage.quantity == before_removal + 3, "Hauler releases its reservation after one completed delivery.")
	_expect(fixture.city_tools.has_equipped(ids[1], "cart"), "Removing the assignment does not unequip the city-owned cart.")
	_check_leaving_without_cart("Removed after delivery")
	_check_conservation()
	# Reassignment during the current shift begins now. Empty the existing ground
	# pile as an explicitly accounted-for player pickup, then exhaust the site.
	var reassigned_at: int = fixture.daily.now()
	_expect(fixture.daily.select_hauler(&"ClaySiteA", ids[1], fixture.get_path_to(destination), destination.display_name, 1000), "The same equipped Hauler can be selected again.")
	_expect(fixture.daily.start(&"ClaySiteA", fixture._drop_daily_output.bind(fixture.get_node("WorksiteMarkers/ClaySiteA"))), "The Hauler rejoins the standing assignment.")
	_expect(int(fixture.daily.jobs[&"ClaySiteA"].starts[ids[1]]) == reassigned_at, "Mid-shift reassignment starts at the current minute.")
	manual_withdrawn += fixture._take_daily_output(&"ClaySiteA", 10000)
	_check_conservation()
	fixture.sites[&"ClaySiteA"].stock = 1
	storage.capacity = 1000
	var stored_before: int = storage.quantity
	var produced_before: int = int(fixture.daily.jobs[&"ClaySiteA"].stats[ids[0]].output)
	attempts = 0
	while fixture.sites[&"ClaySiteA"].stock > 0 and attempts < 20:
		_advance(1)
		attempts += 1
	_expect(fixture.sites[&"ClaySiteA"].stock == 0
		and int(fixture.daily.jobs[&"ClaySiteA"].stats[ids[0]].output) == produced_before + 1
		and _carried() == 1, "Depletion sends the final item as a partial load.")
	if not fixture.hauling.routes.has(ids[1]) or _carried() != 1:
		_finish()
		return
	var route: Dictionary = fixture.hauling.routes[ids[1]]
	_advance(int(route.arrival) - fixture.daily.now())
	_expect(storage.quantity == stored_before + 1 and _carried() == 0, "The partial load reaches storage once.")
	_check_conservation()
	_advance(int(route.arrival) - fixture.daily.now())
	# A load started at 14:59 finishes after 15:00, with no further pickup.
	var before_last_load: int = (fixture.daily.now() / 1440) * 1440 + 14 * 60 + 58
	if not _advance(before_last_load - fixture.daily.now()):
		_finish()
		return
	_seed_output(3)
	_advance(1)
	_expect(_carried() == 3, "Hauler starts last load before shift end.")
	_advance(2)
	hauler_actor = _hauler_actor()
	if is_instance_valid(hauler_actor):
		_expect(hauler_actor.cart_visual != null and hauler_actor.cart_visual.visible
			and str(hauler_actor.body_sprite.animation).contains("push_cart"), "An unfinished delivery retains the cart after shift end.")
	_seed_output(3)
	stored_before = storage.quantity
	_advance(60)
	_expect(storage.quantity == stored_before + 3 and fixture._daily_output_count(&"ClaySiteA") == 3, "In-flight load finishes after shift; no new load starts.")
	_expect(WorkerDatabase.get_worker_data(ids[1]).is_reserved(), "Shift completion preserves standing Daily assignment.")
	_expect(WorkerDatabase.get_worker_data(ids[1]).profession_xp == storage.quantity, "Only accepted deliveries award Hauler XP.")
	_check_conservation()
	_check_leaving_without_cart("Leaving after completed shift")
	_finish()

func _advance(minutes: int) -> bool:
	if minutes < 0:
		_expect(false, "Cannot advance a negative number of minutes: %d." % minutes)
		return false
	if minutes == 0:
		return true
	var before: int = fixture.daily.now()
	var advanced: bool = TimeComponentManager.advance_minutes(minutes)
	_expect(advanced and fixture.daily.now() == before + minutes, "Clock advances exactly %d requested minutes." % minutes)
	return advanced and fixture.daily.now() == before + minutes

func _seed_output(quantity: int) -> void:
	var dropped: bool = fixture._drop_daily_output(quantity, fixture.get_node("WorksiteMarkers/ClaySiteA"))
	_expect(dropped, "Explicit fixture output is placed at the worksite.")
	if dropped:
		seeded_output += quantity

func _hauler_actor():
	var visuals = fixture.get_node("WorkerVisuals")
	visuals._process(0.0)
	var actor = visuals.actors.get(ids[1], null)
	_expect(is_instance_valid(actor), "The Hauler has an available visual actor.")
	return actor

func _check_leaving_without_cart(context: String) -> void:
	var actor = _hauler_actor()
	if not is_instance_valid(actor):
		return
	_expect(actor.visible and str(actor.body_sprite.animation).begins_with("light_walk_"), context + ": walks normally using the light asset.")
	_expect(actor.cart_visual == null or not actor.cart_visual.visible, context + ": the cart is hidden.")


func _carried() -> int:
	var visual: Dictionary = fixture.hauling.get_visual(ids[1], float(fixture.daily.now()))
	return int(visual.get("carrying", 0))

func _check_conservation() -> void:
	var produced: int = int(fixture.daily.jobs[&"ClaySiteA"].stats[ids[0]].output)
	var accounted: int = storage.quantity + fixture._daily_output_count(&"ClaySiteA") + _carried() + manual_withdrawn
	_expect(accounted == produced + seeded_output, "Produced and seeded clay equals stored, grounded, carried and manually removed clay.")

func _finish() -> void:
	if is_instance_valid(fixture):
		fixture.free()
	for id: String in ids:
		WorkerDatabase.workers_by_id.erase(id)
		WorkerDatabase.dismissed_workers.erase(id)
		CitizenManager.citizens_by_id.erase(id)
	print("ClayWorksiteHaulerTest %s" % ("PASSED" if failures == 0 else "FAILED: %d" % failures))
	get_tree().quit(0 if failures == 0 else 1)

func _unhandled_key_input(event: InputEvent) -> void:
	if fixture == null or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F7 and not get_tree().paused:
		TimeComponentManager.advance_minutes(30)
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if is_instance_valid(fixture):
		fixture.daily.cleanup()
	for id: String in ids:
		WorkerDatabase.workers_by_id.erase(id)
		WorkerDatabase.dismissed_workers.erase(id)
		CitizenManager.citizens_by_id.erase(id)
