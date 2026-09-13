extends Node2D

var fixture
var storage
var destination
var failures: int = 0
var ids: Array[String] = ["hauler_demo_laborer", "hauler_demo_hauler"]

func _ready() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	fixture = preload("res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn").instantiate()
	fixture.prepare_nightmare_test = false
	fixture.test_hauler_carts = 1
	add_child(fixture)
	fixture.player.debug_disable_player_needs = true
	fixture.player.position = Vector2(0, 30)
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
			fixture.worker_management.equip(worker.worker_id, "test_cart_0")
		if index == 1:
			# Interactive demo uses the editable MVP example; the legacy stress
			# test keeps enough headroom to exercise removal and shift boundaries.
			var target: int = 1000 if OS.get_environment("TIP_TEST_HAULER") == "1" else 20
			fixture.daily.select_hauler(&"ClaySiteA", worker.worker_id, fixture.get_path_to(destination), destination.display_name, target)
		else:
			fixture.daily.toggle(&"ClaySiteA", worker.worker_id)
	_expect(fixture.daily.start(&"ClaySiteA", fixture._drop_daily_output.bind(fixture.get_node("WorksiteMarkers/ClaySiteA"))), "Mixed team starts with destination and cart.")
	var start: int = fixture.daily.jobs[&"ClaySiteA"].starts[ids[0]]
	TimeComponentManager.advance_minutes(start - fixture.daily.now() - 15)
	if OS.get_environment("TIP_TEST_HAULER") != "1":
		return
	get_tree().paused = true
	TimeComponentManager.advance_minutes(15 + 180)
	_expect(fixture.daily.jobs[&"ClaySiteA"].stats[ids[0]].output == 18, "Only Laborer gathers: 18 clay over three hours.")
	_expect(storage.quantity >= 6, "Hauler completes multiple deliveries.")
	_check_conservation(18)
	if DisplayServer.get_name() != "headless":
		fixture.get_node("WorkerVisuals")._process(0.0)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("tip-hauler-cycle.png"))
	# Close storage while cargo is already travelling: return the load safely.
	var attempts: int = 0
	while _carried() == 0 and attempts < 90:
		TimeComponentManager.advance_minutes(1)
		attempts += 1
	_expect(_carried() == 3, "Each full trip carries exactly three items.")
	fixture.get_node("WorkerVisuals")._process(0.0)
	var hauler_actor = fixture.get_node("WorkerVisuals").actors[ids[1]]
	_expect(str(hauler_actor.body_sprite.animation).contains("push_cart"), "Travelling Hauler uses the imported cart pose.")
	destination.accepting_deliveries = false
	TimeComponentManager.advance_minutes(60)
	_expect(_carried() == 0, "Rejected delivery returns cargo to worksite.")
	_check_conservation(fixture.daily.jobs[&"ClaySiteA"].stats[ids[0]].output)
	destination.accepting_deliveries = true
	TimeComponentManager.advance_minutes(1)
	_expect(_carried() == 3, "Available destination permits another load.")
	fixture.daily.withdraw(&"ClaySiteA", ids[1])
	_expect(WorkerDatabase.get_worker_data(ids[1]).is_reserved(), "Loaded removal waits for current trip.")
	TimeComponentManager.advance_minutes(60)
	_expect(not WorkerDatabase.get_worker_data(ids[1]).is_reserved(), "Hauler releases reservation after trip.")
	_check_leaving_without_cart("Removed after delivery")
	_check_conservation(fixture.daily.jobs[&"ClaySiteA"].stats[ids[0]].output)
	# Reassign tomorrow and exhaust the site with less than a full cart.
	fixture.daily.select_hauler(&"ClaySiteA", ids[1], fixture.get_path_to(destination), destination.display_name, 1000)
	fixture.daily.start(&"ClaySiteA", fixture._drop_daily_output.bind(fixture.get_node("WorksiteMarkers/ClaySiteA")))
	var tomorrow: int = fixture.daily.jobs[&"ClaySiteA"].starts[ids[1]]
	TimeComponentManager.advance_minutes(tomorrow - fixture.daily.now() - 1)
	fixture._take_daily_output(&"ClaySiteA", 10000)
	fixture.sites[&"ClaySiteA"].stock = 1
	TimeComponentManager.advance_minutes(1)
	storage.capacity = 1000
	var stored_before: int = storage.quantity
	TimeComponentManager.advance_minutes(60)
	_expect(storage.quantity == stored_before + 1, "Depleted site sends its final partial load.")
	# A load started at 14:59 finishes after 15:00, with no further pickup.
	TimeComponentManager.advance_minutes(14 * 60 + 58 - fixture.daily.now() % 1440)
	fixture._drop_daily_output(3, fixture.get_node("WorksiteMarkers/ClaySiteA"))
	TimeComponentManager.advance_minutes(1)
	_expect(_carried() == 3, "Hauler starts last load before shift end.")
	TimeComponentManager.advance_minutes(2)
	fixture.get_node("WorkerVisuals")._process(0.1)
	_expect(hauler_actor.cart_visual.visible and str(hauler_actor.body_sprite.animation).contains("push_cart"), "An unfinished delivery retains the cart after shift end.")
	fixture._drop_daily_output(3, fixture.get_node("WorksiteMarkers/ClaySiteA"))
	stored_before = storage.quantity
	TimeComponentManager.advance_minutes(60)
	_expect(storage.quantity == stored_before + 3 and fixture._daily_output_count(&"ClaySiteA") == 3, "In-flight load finishes after shift; no new load starts.")
	_expect(WorkerDatabase.get_worker_data(ids[1]).is_reserved(), "Shift completion preserves standing Daily assignment.")
	_check_leaving_without_cart("Leaving after completed shift")
	fixture.daily.cleanup()
	for id: String in ids:
		WorkerDatabase.workers_by_id.erase(id)
	print("ClayWorksiteHaulerTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)

func _check_leaving_without_cart(context: String) -> void:
	var visuals = fixture.get_node("WorkerVisuals")
	visuals._process(0.1)
	var actor = visuals.actors[ids[1]]
	_expect(actor.visible and str(actor.body_sprite.animation).begins_with("light_walk_"), context + ": walks normally using the light asset.")
	_expect(actor.cart_visual == null or not actor.cart_visual.visible, context + ": the cart is hidden.")


func _carried() -> int:
	var visual: Dictionary = fixture.hauling.get_visual(ids[1], float(fixture.daily.now()))
	return int(visual.get("carrying", 0))

func _check_conservation(produced: int) -> void:
	_expect(storage.quantity + fixture._daily_output_count(&"ClaySiteA") + _carried() == produced, "Produced clay equals stored, grounded and carried clay.")

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
