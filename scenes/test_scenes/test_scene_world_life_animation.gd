extends Node

## Isolated city fixture. Use a disposable XDG_DATA_HOME for every run.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const DUST: Script = preload("res://scenes/worker_visual/footstep_dust.gd")
const RESIDENT_ID: String = "world_life_animation_fixture"
var failures: int = 0
var city: Node2D
var visuals: Node2D
var runtime: Node
var actor: Node2D
var camera: Camera2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var data_root: String = OS.get_environment("XDG_DATA_HOME")
	_check(data_root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(data_root.simplify_path().trim_suffix("/") + "/"), "Use a disposable XDG_DATA_HOME.")
	if failures > 0:
		get_tree().quit(1)
		return
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 20
	TimeComponentManager.current_hour = 11
	TimeComponentManager.current_minute = 0
	city = CITY.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	runtime = city.get_node("YSortWorld/WorkerRuntime")
	visuals = runtime.get_node("WorkerVisuals")
	visuals.set_process(false)
	if DisplayServer.get_name() != "headless":
		get_window().content_scale_size = Vector2i(400, 225)
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().size = Vector2i(1200, 675)
		camera = Camera2D.new()
		city.add_child(camera)
		camera.make_current()
	await get_tree().physics_frame
	await get_tree().process_frame
	await _test_palms()
	await _test_footsteps()
	if failures == 0:
		print("WorldLifeAnimationTest PASSED")
	else:
		print("WorldLifeAnimationTest FAILED: %d" % failures)
	get_tree().paused = false
	SceneTransition.is_transitioning = false
	TimeComponentManager.is_paused = false
	get_tree().quit(0 if failures == 0 else 1)

func _test_palms() -> void:
	var palm: Sprite2D = city.get_node("YSortWorld/DatePalmTree")
	var sway: Node = palm.get_node_or_null("PalmSway")
	_check(sway != null and palm.material is ShaderMaterial, "The real city palm has its visual sway.")
	if sway == null:
		return
	var state: Node = palm.state
	var source_position: Vector2 = palm.global_position
	var available: Array = state.available.duplicate()
	var pickup_positions: Array[Vector2] = []
	for pickup: Node2D in palm._pickups.values():
		pickup_positions.append(pickup.global_position)
	sway.set_process(false)
	sway.phase = 0.0
	sway.elapsed = 0.0
	sway._update_offset()
	var offsets: Dictionary = {}
	var last_sign: int = 0
	var right_excursions: int = 0
	var left_excursions: int = 0
	var rest_stayed_still: bool = true
	for step: int in range(200):
		sway._process(0.05)
		offsets[sway.last_offset] = true
		var sign: int = int(sway.last_offset)
		if sign == 1 and last_sign != 1:
			right_excursions += 1
		elif sign == -1 and last_sign != -1:
			left_excursions += 1
		last_sign = sign
		if step >= 100 and step < 199 and sign != 0:
			rest_stayed_still = false
	_check(offsets.size() >= 3, "Palm canopy moves through multiple whole-pixel positions.")
	_check(right_excursions == 1 and left_excursions == 1, "A complete ten-second cycle has one right and one left excursion.")
	_check(rest_stayed_still, "The canopy rests at its original position during the five-second pause.")
	_check(palm.global_position == source_position and state.available == available, "Sway does not alter the source or its availability.")
	var index: int = 0
	for pickup: Node2D in palm._pickups.values():
		_check(pickup.global_position == pickup_positions[index], "Sway leaves each pickup at its original world position.")
		index += 1
	var frozen: float = sway.elapsed
	TimeComponentManager.is_paused = true
	sway._process(1.0)
	_check(sway.elapsed == frozen, "Palm freezes when game time is paused.")
	TimeComponentManager.is_paused = false
	SceneTransition.is_transitioning = true
	sway._process(1.0)
	_check(sway.elapsed == frozen, "Palm freezes during a scene transition.")
	SceneTransition.is_transitioning = false
	sway.set_process(true)
	get_tree().paused = true
	await get_tree().create_timer(0.2).timeout
	_check(sway.elapsed == frozen, "Palm freezes while the scene tree is paused.")
	get_tree().paused = false
	var copy: Sprite2D = palm.duplicate(Node.DUPLICATE_SCRIPTS)
	copy.name = "AnimationTestPalmCopy"
	palm.get_parent().add_child(copy)
	await get_tree().process_frame
	_check(copy.get_node_or_null("PalmSway") != null and copy.material != palm.material, "Duplicated palms use independent sway materials.")
	var sway_count: int = 0
	for child: Node in copy.get_children():
		if child.name == "PalmSway":
			sway_count += 1
	_check(sway_count == 1 and copy.tree_id != palm.tree_id and copy.state != state, "A copied palm has one animation and its own pickup identity.")
	copy.queue_free()
	await get_tree().process_frame
	_check(palm.material == sway.sway_material and palm.state == state, "Removing a copy preserves the original palm.")
	if camera != null and not OS.get_environment("TIP_ANIMATION_CAPTURE_DIR").is_empty():
		city.get_node("TopHUD").hide()
		city.get_node("BottomHUD").hide()
		city.get_node("TimeDebugOverlay").visible = false
		city.get_node("YSortWorld/InitialWorksites/JobBoard").hide()
	if camera != null and not OS.get_environment("TIP_ANIMATION_CAPTURE_DIR").is_empty():
		sway.phase = 0.0
		sway.elapsed = 0.0
		sway._update_offset()
	await _capture_frames("palm", palm.global_position + Vector2(32, 10), 100)

func _dust_count() -> int:
	var count: int = 0
	for child: Node in visuals.get_children():
		if child.get_script() == DUST and not child.is_queued_for_deletion():
			count += 1
	return count

func _dust() -> Node2D:
	for child: Node in visuals.get_children():
		if child.get_script() == DUST and not child.is_queued_for_deletion():
			return child as Node2D
	return null

func _test_footsteps() -> void:
	var citizen := CitizenData.new()
	citizen.citizen_id = RESIDENT_ID
	citizen.display_name = "Animation fixture"
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	citizen.visual_profile = VisualProfile.new()
	citizen.visual_profile.skin_tone = "tan"
	citizen.visual_profile.clothes_id = "plain_worn_wrap"
	citizen.visual_profile.hair_style = "black_male_01"
	CitizenManager.add_citizen(citizen)
	actor = visuals.actors.get(RESIDENT_ID)
	_check(is_instance_valid(actor) and actor.is_visible_in_tree(), "A real resident gets one visible actor.")
	if not is_instance_valid(actor):
		return
	var emitter: Node = actor.get_node_or_null("Footsteps")
	_check(emitter != null, "The resident owns one footstep listener.")
	if emitter == null:
		return
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var time_before: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	# Existing layers remain intact for every supported skin tone and both facings.
	for tone: String in ["dark", "light", "tan", "warm"]:
		for facing: String in ["left", "right"]:
			for clothing: String in ["plain_worn_wrap", "clay_worn_wrap"]:
				for hair: String in ["black_male_01", "red_female_03", "brown_male_02", "grey_female_01"]:
					actor.skin_tone = tone
					actor.clothes_id = clothing
					actor.hair_style = hair
					actor.accessory = "farmer_hat"
					visuals._play(actor, "walk", facing)
					_check(actor.body_sprite.animation == StringName(tone + "_walk_" + facing), "Walking retains the native body and facing.")
					_check(actor.clothes_sprite.visible and actor.clothes_sprite.animation == StringName(clothing + "_walk_" + facing), "Walking retains the resident's clothes.")
					_check(actor.hair_sprite.visible and actor.hair_sprite.animation == StringName(hair + "_walk_" + facing), "Walking retains the resident's hair.")
					_check(actor.accessories_sprite.visible and actor.accessories_sprite.animation == StringName("farmer_hat_walk_" + facing), "Walking retains the resident's accessory.")
					visuals._play(actor, "idle", facing)
	actor.skin_tone = citizen.visual_profile.skin_tone
	actor.clothes_id = citizen.visual_profile.clothes_id
	actor.hair_style = citizen.visual_profile.hair_style
	actor.accessory = citizen.visual_profile.accessory
	visuals._play(actor, "walk", "right")
	actor.body_sprite.pause()
	actor.global_position += Vector2(6, 0)
	actor.body_sprite.set_frame_and_progress(2, 0.0)
	# Calling again proves that repeated requests on the same step cannot duplicate it.
	emitter._on_body_frame_changed()
	_check(_dust_count() == 1, "A moving right-facing walk step emits exactly one puff.")
	var puff: Node2D = _dust()
	if puff == null:
		return
	_check(puff.global_position.x < actor.global_position.x, "The right-facing puff stays behind the feet.")
	var origin: Vector2 = puff.global_position
	actor.global_position += Vector2(1, 0)
	_check(puff.global_position == origin, "The puff remains on the ground when the actor moves on.")
	var before: float = puff.elapsed
	TimeComponentManager.is_paused = true
	actor.global_position += Vector2(6, 0)
	emitter._on_body_frame_changed()
	await get_tree().create_timer(0.2).timeout
	_check(puff.elapsed == before and _dust_count() == 1, "Game-time pause freezes existing dust and prevents new steps.")
	TimeComponentManager.is_paused = false
	SceneTransition.is_transitioning = true
	emitter._on_body_frame_changed()
	await get_tree().create_timer(0.2).timeout
	_check(puff.elapsed == before and _dust_count() == 1, "Scene transitions freeze dust and prevent new steps.")
	SceneTransition.is_transitioning = false
	get_tree().paused = true
	emitter._on_body_frame_changed()
	await get_tree().create_timer(0.2).timeout
	_check(puff.elapsed == before and _dust_count() == 1, "Tree pause freezes dust and prevents new steps.")
	get_tree().paused = false
	visuals._play(actor, "idle", "right")
	actor.global_position += Vector2(6, 0)
	emitter._on_body_frame_changed()
	_check(_dust_count() == 1, "Idle cannot emit a new puff.")
	await get_tree().create_timer(0.8).timeout
	_check(_dust_count() == 0, "The last puff clears after walking stops.")
	visuals._play(actor, "walk", "left")
	actor.body_sprite.pause()
	actor.global_position -= Vector2(6, 0)
	actor.body_sprite.set_frame_and_progress(2, 0.0)
	emitter._on_body_frame_changed()
	puff = _dust()
	_check(puff != null and puff.global_position.x > actor.global_position.x, "The left-facing puff stays behind the feet.")
	if puff != null:
		puff.queue_free()
	await get_tree().process_frame
	visuals._play(actor, "idle", "right")
	visuals._play(actor, "walk", "right")
	actor.body_sprite.pause()
	actor.body_sprite.set_frame_and_progress(2, 0.0)
	actor.hide()
	actor.global_position += Vector2(6, 0)
	emitter._on_body_frame_changed()
	_check(_dust_count() == 0, "A hidden resident cannot emit footsteps.")
	actor.show()
	emitter._on_body_frame_changed()
	_check(_dust_count() == 0, "Reappearing does not turn hidden travel into a fake step.")
	actor.global_position += Vector2(6, 0)
	emitter._on_body_frame_changed()
	_check(_dust_count() == 1, "A visible step can emit after the resident reappears.")
	puff = _dust()
	if puff != null:
		puff.queue_free()
	await get_tree().process_frame
	visuals._play(actor, "idle", "right")
	visuals._play(actor, "walk", "right")
	actor.body_sprite.pause()
	actor.body_sprite.set_frame_and_progress(2, 0.0)
	actor.global_position += Vector2(100, 0)
	emitter._on_body_frame_changed()
	_check(_dust_count() == 0, "A large scene or time-skip jump cannot create a fake step.")
	actor.global_position += Vector2(6, 0)
	emitter._on_body_frame_changed()
	_check(_dust_count() == 1, "Normal steps resume after a jump.")
	puff = _dust()
	if puff != null:
		puff.queue_free()
	await get_tree().process_frame
	_check(Inventory.items == inventory_before and time_before == TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute, "Footsteps do not mutate inventory or game time.")
	_check(citizen.visual_profile.skin_tone == "tan" and citizen.visual_profile.clothes_id == "plain_worn_wrap" and citizen.visual_profile.hair_style == "black_male_01", "The saved citizen profile is unchanged.")
	await _test_live_walking()
	visuals.set_process(false)
	_check(CitizenManager.leave_city(RESIDENT_ID), "The resident can leave normally.")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not is_instance_valid(actor) and not visuals.actors.has(RESIDENT_ID), "The visual and listener are retired with the resident.")

func _test_live_walking() -> void:
	var directory: String = OS.get_environment("TIP_ANIMATION_CAPTURE_DIR")
	var capturing: bool = camera != null and not directory.is_empty()
	# Capture-only staging: keep the real city and actor, hide HUD/board overlap.
	if capturing:
		city.get_node("TopHUD").hide()
		city.get_node("BottomHUD").hide()
		city.get_node("TimeDebugOverlay").visible = false
		city.get_node("YSortWorld/InitialWorksites/JobBoard").hide()
		city.get_node("YSortWorld/Player").hide()
		city.get_node("YSortWorld/TravelingMerchant").hide()
		city.get_node("YSortWorld/WorkshopPlot/Craftsman").hide()
		runtime.get_node("WorksiteMarkers").hide()
		var annex: CanvasItem = runtime.get_node_or_null("CityStorageAnnex")
		if annex != null:
			annex.hide()
	for id: String in visuals.actors:
		if id != RESIDENT_ID:
			visuals.actors[id].hide()
			if capturing:
				visuals.actors[id].modulate.a = 0.0
	var start: Vector2 = Vector2.INF
	for y: int in [40, 60, 25, 0, -25, -50]:
		for x: int in [0, 30, -40, -60, -80]:
			var candidate: Vector2 = runtime.global_position + Vector2(x, y)
			if runtime.worksite_navigation.segment_clear(candidate + Vector2(0, 16), candidate + Vector2(80, 16)):
				start = candidate
				break
		if start != Vector2.INF:
			break
	_check(start != Vector2.INF, "An unobstructed native walk route is available for capture.")
	if start == Vector2.INF:
		return
	actor.global_position = start
	actor.show()
	visuals._play(actor, "idle", "right")
	visuals.roaming[RESIDENT_ID] = {"target": start + Vector2(80, 0), "idle": 0.0, "direction": "right"}
	visuals.set_process(true)
	if capturing:
		DirAccess.make_dir_recursive_absolute(directory.path_join("footsteps"))
		camera.zoom = Vector2(3, 3)
	var saw_puff: bool = false
	for index: int in range(80 if capturing else 25):
		await get_tree().create_timer(0.1).timeout
		saw_puff = saw_puff or _dust_count() > 0
		if capturing:
			camera.global_position = actor.global_position
			camera.force_update_scroll()
			await RenderingServer.frame_post_draw
			var frame: Image = get_viewport().get_texture().get_image()
			_check(frame.save_png(directory.path_join("footsteps").path_join("%04d.png" % index)) == OK, "Save footstep animation frame.")
	_check(actor.global_position.distance_to(start) > 8.0 and saw_puff, "The actual resident roaming cycle moves and emits footsteps.")
	_check(actor.clothes_sprite.visible and actor.hair_sprite.visible, "The naturally walking resident retains hair and clothes.")

func _capture_frames(name: String, center: Vector2, count: int) -> void:
	var directory: String = OS.get_environment("TIP_ANIMATION_CAPTURE_DIR")
	if directory.is_empty() or camera == null:
		return
	DirAccess.make_dir_recursive_absolute(directory.path_join(name))
	camera.global_position = center
	camera.zoom = Vector2(2, 2)
	camera.reset_smoothing()
	camera.force_update_scroll()
	for index: int in range(count):
		await get_tree().create_timer(0.1).timeout
		await RenderingServer.frame_post_draw
		var frame: Image = get_viewport().get_texture().get_image()
		_check(frame.save_png(directory.path_join(name).path_join("%04d.png" % index)) == OK, "Save animation frame.")
