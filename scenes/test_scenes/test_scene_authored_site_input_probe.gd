extends Node

## Test actual site focus and input from collision-free sampled positions.
## Sampling relocates the player, so it does not establish a walkable route.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const EXPECTED: Array[String] = ["ClaySiteA", "ClaySiteB", "WoodSite", "WoodSiteB", "WoodSiteC", "WoodSiteD", "WoodSiteE", "ReedSite", "StrawSite", "WaterSite"]
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _settle_physics() -> void:
	for _i: int in range(3):
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	var data_root: String = OS.get_environment("XDG_DATA_HOME").simplify_path().trim_suffix("/")
	_check(data_root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(data_root + "/"), "An isolated XDG profile is required")
	if failures:
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var city: Node = CITY.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	await _settle_physics()
	var work: Node = city.get_node("YSortWorld/WorkerRuntime")
	var player: Player = city.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	var markers: Node = work.get_node("WorksiteMarkers")
	_check(markers.get_child_count() == EXPECTED.size(), "The expected current ten-site catalog is loaded")
	if OS.get_environment("TIP_QA_LEGACY_POSES") == "1":
		for site_id: String in ["ClaySiteA", "WoodSite"]:
			var site: Node2D = markers.get_node(site_id)
			for offset: Vector2 in [Vector2(-18, 10), Vector2(-20, -10)]:
				var target: Vector2 = site.global_position + offset
				var solid: bool = player.test_move(Transform2D(0.0, target), Vector2(0.01, 0.0))
				player._set_current_interactable(null)
				player.global_position = target
				await _settle_physics()
				player._refresh_current_interactable()
				work._process(0.0)
				var nearest: Node = work._nearest_interaction_site()
				var focus: Node = player.current_interactable
				print("LEGACY_POSE_DIAGNOSTIC ", JSON.stringify({"wanted": site_id, "offset": str(offset), "collision": solid,
					"nearest": str(nearest.name) if is_instance_valid(nearest) else "none",
					"other_focus": str(focus.name) if is_instance_valid(focus) else "none",
					"prompt_visible": site.get_node("InteractPrompt").visible}))
		get_tree().quit(0 if failures == 0 else 1)
		return
	for site_id: String in EXPECTED:
		var site: Node2D = markers.get_node_or_null(site_id)
		if site == null:
			_check(false, "Missing site: " + site_id)
			continue
		var selected: bool = false
		var collision_free: int = 0
		var blockers: Dictionary = {}
		for radius: float in [20.0, 28.0, 36.0, 44.0, 16.0]:
			for angle_step: int in range(16):
				var offset: Vector2 = Vector2.from_angle(float(angle_step) * TAU / 16.0) * radius
				var target: Vector2 = site.global_position + offset
				if player.test_move(Transform2D(0.0, target), Vector2(0.01, 0.0)):
					continue
				collision_free += 1
				player._set_current_interactable(null)
				player.global_position = target
				await _settle_physics()
				player._refresh_current_interactable()
				work._process(0.0)
				var nearest: Node = work._nearest_interaction_site()
				var focus: Node = player.current_interactable
				var owner: String = str(nearest.name) if is_instance_valid(nearest) else (str(focus.name) if is_instance_valid(focus) else "none")
				blockers[owner] = int(blockers.get(owner, 0)) + 1
				if nearest != site or work._highlighted_site != site or not site.get_node("InteractPrompt").visible:
					continue
				var event := InputEventAction.new()
				event.action = &"interact"
				event.pressed = true
				Input.parse_input_event(event)
				await get_tree().process_frame
				selected = work.inspector.visible and work._selected_site == site
				event.pressed = false
				Input.parse_input_event(event)
				if work.inspector.visible:
					work._close_inspector()
				await _settle_physics()
				if selected:
					print("AUTHORED_SITE_INPUT ", JSON.stringify({"site": site_id, "position": str(target), "offset": str(offset), "collision_free_tested": collision_free}))
					break
			if selected:
				break
		_check(selected, "No sampled collision-free position opened the expected site with E: %s candidates=%d focus=%s" % [site_id, collision_free, JSON.stringify(blockers)])
	print("AuthoredSiteInputProbe: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
