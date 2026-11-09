extends "res://scenes/test_scenes/mvp_first_playthrough.gd"

## Uses the real Player movement inputs from the map's spawn; unlike the focus
## probe, it does not teleport between sites. Needs are disabled only here.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const SITE_IDS: Array[String] = ["WoodSite", "WoodSiteB", "WoodSiteC", "WoodSiteD", "WoodSiteE", "ClaySiteA", "ClaySiteB", "ReedSite", "StrawSite", "WaterSite"]

# The inherited driver assumes every site uses the circular 32px reach.
# Wood uses an asymmetric interaction Area2D, so choose points inside its
# actual shape; retry if nearby worksite focus changes on arrival.
func _site_approach(marker: Marker2D, avoided: Array[Vector2] = []) -> Vector2:
	var candidates: Array[Vector2] = []
	var area: Area2D = marker.get_node_or_null("WoodInteractionArea")
	var shape_node: CollisionShape2D = area.get_child(0) as CollisionShape2D if area != null else null
	# Use a grid-aligned final point so the inherited cardinal walker never
	# inserts an unchecked diagonal detour between the last cell and the pose.
	var center: Vector2i = Vector2i((marker.global_position / 8.0).round())
	for x: int in range(center.x - 4, center.x + 5):
		for y: int in range(center.y - 4, center.y + 5):
			var candidate: Vector2 = Vector2(x * 8, y * 8)
			var radius: float = candidate.distance_to(marker.global_position)
			if radius < 12.0 or radius > 29.0:
				continue
			if shape_node != null and not shape_node.shape.get_rect().grow(-4.0).has_point(shape_node.to_local(candidate)):
				continue
			var nearest: bool = true
			for obstruction: Vector2 in avoided:
				if candidate.distance_to(obstruction) < 8.0:
					nearest = false
					break
			for other: Marker2D in runtime.get_node("WorksiteMarkers").get_children():
				if other != marker and candidate.distance_to(other.global_position) <= radius + 1.5:
					nearest = false
					break
			if nearest:
				candidates.append(candidate)
	return _reachable_approach(candidates, marker.global_position)

func walk_to_site(marker: Marker2D) -> void:
	var avoided: Array[Vector2] = []
	for _attempt: int in range(12):
		var approach: Vector2 = _site_approach(marker, avoided)
		_expect(approach != Vector2.INF, "A collision-clear and reachable worksite approach exists")
		if stopped:
			return
		await walk(approach)
		if stopped:
			return
		if not is_instance_valid(player.current_interactable) and runtime._nearest_interaction_site() == marker:
			return
		avoided.append(approach)
	_expect(false, "A walking approach reaches the intended worksite focus")

func _run() -> void:
	var data_root: String = OS.get_environment("XDG_DATA_HOME").simplify_path().trim_suffix("/")
	_expect(data_root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(data_root + "/"), "Use an isolated XDG profile")
	if stopped:
		return
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var city: Node = CITY.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	await _frames(4)
	bind_map()
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	print("AUTHORED_WALK_START ", player.global_position)
	for id: String in SITE_IDS:
		var site: Marker2D = runtime.get_node("WorksiteMarkers/" + id)
		await walk_to_site(site)
		if stopped:
			return
		var actual: Node = runtime._nearest_interaction_site()
		var highlighted: Node = runtime._highlighted_site
		var focused: Node = player.current_interactable
		var area: Area2D = site.get_node_or_null("WoodInteractionArea")
		print("AUTHORED_WALK_FOCUS ", JSON.stringify({"wanted": id, "position": str(player.global_position),
			"site_position": str(site.global_position), "distance": player.global_position.distance_to(site.global_position),
			"nearest": str(actual.name) if is_instance_valid(actual) else "none",
			"highlighted": str(highlighted.name) if is_instance_valid(highlighted) else "none",
			"other_focus": str(focused.name) if is_instance_valid(focused) else "none",
			"prompt_visible": site.get_node("InteractPrompt").visible,
			"wood_area_overlap": area.overlaps_body(player) if area != null else false,
			"can_move": player.can_move, "inspector": runtime.inspector.visible}))
		_expect(actual == site and highlighted == site and site.get_node("InteractPrompt").visible,
			"Walking reaches the expected site's active E prompt: " + id)
		if stopped:
			return
		await interact()
		_expect(runtime.inspector.visible and runtime._selected_site == site, "Normal E opens the correct site after walking: " + id)
		if stopped:
			return
		runtime._close_inspector()
		await _frames(3)
		print("AUTHORED_WALK_REACHED ", JSON.stringify({"site": id, "position": str(player.global_position), "walked_pixels": walked}))
	release_input()
	print("AuthoredSiteWalkProbe: PASS sites=", SITE_IDS.size(), " walked_pixels=", walked)
	get_tree().quit(0)
