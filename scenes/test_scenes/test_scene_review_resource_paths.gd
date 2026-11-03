extends "res://scenes/test_scenes/test_scene_citizen_house_navigation.gd"

## Review-only scene. One pickup per site is a fixture; production is tested
## separately by the real three-process laborer/Continue flow.
func _run() -> void:
	get_tree().current_scene = null
	var menu = MENU.instantiate()
	menu.checkpoint_file.path = "user://review_resource_routes/checkpoint.json"
	menu.session_started.connect(_on_session_started)
	get_tree().root.add_child(menu)
	menu._request_new_game()
	for frame in range(600):
		if launched:
			break
		await get_tree().process_frame
	_expect(launched and not continued, "The real menu opens the review New Game.")
	if not launched or continued:
		_finish_review()
		return
	content = get_tree().current_scene as Node2D
	player = content.get_node("YSortWorld/Player") as Player
	var runtime: Node = content.get_node("YSortWorld/WorkerRuntime")
	TimeComponentManager.set_process(false)
	var origin: Vector2 = runtime.get_node("WorkerDeparture/NearSpawn").global_position
	for id: String in ["ClaySiteA", "WoodSite", "ReedSite", "StrawSite", "WaterSite"]:
		var marker: Node2D = runtime.get_node("WorksiteMarkers/" + id)
		for slot: int in [0, 1]:
			var target: Vector2 = runtime.site_slot_destination(StringName(id), slot)
			_expect(not runtime.worksite_navigation.route(origin, target).is_empty(),
				"A worker can reach %s slot %d from the real departure point." % [id, slot])
		if failures > 0:
			_finish_review()
			return
		var item_id: String = runtime.sites[StringName(id)].item_id
		var before: int = int(Inventory.items.get(item_id, 0))
		_expect(runtime._drop_daily_output(1, marker), "The %s fixture pickup appears on the ground." % id)
		var pile: PickUpItem
		for child in runtime.get_node("GroundOutput").get_children():
			if child is PickUpItem and child.get_meta("daily_site", "") == id and not child.is_collecting:
				pile = child
				break
		_expect(is_instance_valid(pile), "The %s ground pickup exists." % id)
		if not is_instance_valid(pile):
			_finish_review()
			return
		if not await _walk_to(pile.global_position + Vector2(0, -5), "ground output at " + id):
			_finish_review()
			return
		_expect(player.current_interactable == pile, "The player can select the %s pickup." % id)
		if player.current_interactable != pile:
			_finish_review()
			return
		await _press_interact()
		for frame in range(240):
			if player.can_move and not is_instance_valid(pile):
				break
			await get_tree().physics_frame
		_expect(int(Inventory.items.get(item_id, 0)) == before + 1 and player.can_move and not is_instance_valid(pile),
			"The %s item is picked up once and movement resumes." % id)
		if failures > 0:
			_finish_review()
			return
	_finish_review()

func _finish_review() -> void:
	_release_input()
	get_tree().paused = false
	print("ReviewResourcePathsTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures, "; walked=", walked)
	get_tree().quit(0 if failures == 0 else 1)
