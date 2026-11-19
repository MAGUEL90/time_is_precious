extends "res://scenes/test_scenes/test_scene_city_transport_flow.gd"

## The write phase saves a loaded courier from the home scene; the fresh read
## resumes it using the parked city navigation, then returns to the city.
const HOME_SAVE_PATH: String = "user://city_transport_home_continue/checkpoint.json"

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--transport-home-phase="):
			phase = argument.trim_prefix("--transport-home-phase=")
	_expect(phase in ["write", "read"], "Choose --transport-home-phase=write or read.")
	if stopped:
		return
	_expect(FileAccess.file_exists(HOME_SAVE_PATH) == (phase == "read"), "Use an isolated home profile in write/read order.")
	var original_bytes: PackedByteArray = FileAccess.get_file_as_bytes(HOME_SAVE_PATH) if phase == "read" else PackedByteArray()
	get_tree().current_scene = null
	TimeComponentManager.set_process(false)
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = HOME_SAVE_PATH
	menu.session_started.connect(func(from_save: bool):
		continued = from_save
		launched = true)
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames()
	await press(menu.continue_button if phase == "read" else menu.new_game_button)
	for _frame: int in range(1200):
		if launched or stopped:
			break
		await get_tree().process_frame
	_expect(launched and continued == (phase == "read"), "The Start Menu opens the expected home test phase.")
	if stopped:
		return
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	store = WorkStateRuntime.get_node("CitySave")
	transport = WorkStateRuntime.get_node("CityStorageTransport")
	central = transport.get_storage("city")
	annex = transport.get_storage("annex")
	if phase == "write":
		bind_map()
		player.debug_disable_player_needs = true
		player.debug_disable_fatigue = true
		await _write_flow()
		if stopped:
			return
		# Simulate the final unit having just been gathered, before its deferred
		# refill. The parked runtime must wait until the city is restored.
		runtime.sites[&"ClaySiteA"].stock = 0
		runtime._sync_site_timer(&"ClaySiteA") # Committed fixture depletion.
		content.get_node("YSortWorld/HomeDoor")._on_body_entered(player)
		await _wait_for_scene(store.snapshot.HOME_PATH)
		_expect(store.snapshot.is_home(get_tree().current_scene) and is_instance_valid(store.parked_worksite), "A loaded courier survives the actual city-to-home handoff.")
		_expect(store.parked_worksite.sites[&"ClaySiteA"].stock == 0, "An exhausted deposit stays exhausted while the city is parked.")
		_expect(store.save_checkpoint(), "Save in-flight city cargo from the home: " + store.last_error)
	else:
		_expect(FileAccess.get_file_as_bytes(HOME_SAVE_PATH) == original_bytes and store.snapshot.is_home(get_tree().current_scene), "Continue restores the home without rewriting its checkpoint.")
		_expect(int(transport.route.get("quantity", -1)) == 3 and int(central.items.get(ITEM_ID, 0)) == 3 and int(annex.items.get(ITEM_ID, 0)) == 0, "The home checkpoint restores the city route and both stock owners.")
		_expect(store.parked_worksite.sites[&"ClaySiteA"].stock == 0, "Continue at home preserves the exhausted deposit.")
		await _finish_route()
		_expect(store.parked_worksite.sites[&"ClaySiteA"].stock == 0, "Elapsed time at home does not refill the parked deposit.")
		_expect(int(central.items.get(ITEM_ID, 0)) == 3 and int(annex.items.get(ITEM_ID, 0)) == 3 and int(Inventory.items.get(ITEM_ID, 0)) == 4, "Parked city navigation completes the delivery while the player is home.")
		_expect(store.save_checkpoint(), "Save the completed route from home: " + store.last_error)
		var home: Node = get_tree().current_scene
		home.get_node("YSortWorld/ExitDoor")._on_body_entered(home.get_node("YSortWorld/Player"))
		await _wait_for_scene("res://scenes/content_scene/content_scene.tscn")
		bind_map()
		_expect(TimeComponentManager.advance_minutes(1), "Resume the city clock after returning home.")
		await _frames(3)
		var session = runtime.sites[&"ClaySiteA"]
		var fixed_position: Vector2 = runtime.get_node("WorksiteMarkers/ClaySiteA").position
		_expect(session.stock == 0 and session.respawn_due_at > runtime.daily.now(), "The exhausted deposit still waits after the live city returns.")
		_expect(TimeComponentManager.advance_minutes(session.respawn_due_at - runtime.daily.now()), "Advance the remaining respawn delay on the game clock.")
		await _frames(4)
		_expect(session.stock == 36 and runtime.get_node("WorksiteMarkers/ClaySiteA").position == fixed_position and runtime.resource_site_offset(&"ClaySiteA") == Vector2.ZERO, "The exhausted deposit refills at its same authored location after the city returns.")
		_expect(runtime.has_node("CityStorageAnnex") and transport.route.is_empty() and int(annex.items.get(ITEM_ID, 0)) == 3, "Returning to the city keeps the delivered annex goods and released courier.")
	if stopped:
		return
	print("CityStorageTransportHomeContinueTest ", phase, ": PASS")
	get_tree().quit(0)

func _wait_for_scene(path: String) -> void:
	for _frame: int in range(1200):
		var scene: Node = get_tree().current_scene
		if scene != null and scene.scene_file_path == path and not SceneTransition.is_transitioning:
			await _frames(3)
			return
		await get_tree().process_frame
	_expect(false, "The expected city/home scene transition completes: " + path)
