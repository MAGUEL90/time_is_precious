extends Node

## Explicit isolated fixtures only; no checkpoint load/save or economy changes.
const CONTENT = preload("res://scenes/content_scene/content_scene.tscn")
const PRESENTATION = preload("res://scenes/content_scene/worksites/resource_site_presentation.gd")
const NAVIGATION = preload("res://scenes/content_scene/worksites/worksite_navigation.gd")
const WORKER_ID: String = "worksite_presentation_fixture"
var failures: int = 0
var city: Node
var runtime: Node
var visuals: Node
var worker: WorkerData
var capture_camera: Camera2D

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 20
	TimeComponentManager.current_hour = 11
	TimeComponentManager.current_minute = 0
	_test_contact_geometry()
	city = CONTENT.instantiate()
	add_child(city)
	runtime = city.get_node("YSortWorld/WorkerRuntime")
	visuals = runtime.get_node("WorkerVisuals")
	visuals.set_process(false)
	if not OS.get_environment("TIP_MVP_CAPTURE_DIR").is_empty() and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("TIP Worksite Presentation QA 20261028")
		get_window().content_scale_size = Vector2i(400, 225)
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_window().size = Vector2i(1200, 675)
		capture_camera = Camera2D.new()
		city.add_child(capture_camera)
		capture_camera.make_current()
	await get_tree().physics_frame
	_test_player_contacts()
	runtime.daily.tool_requirement = Callable()
	worker = WorkerData.new()
	worker.worker_id = WORKER_ID
	worker.display_name = "Presentation fixture"
	worker.payroll_start_day = 20
	worker.payroll_paid_from_day = 20
	worker.payroll_paid_until_day = 23
	worker.payroll_last_attempt_day = 20
	worker.payroll_period_rate = 1
	worker.payroll_contract_days = 3
	worker.payroll_paid_start_minute = 20 * 1440 + 660
	WorkerDatabase.workers_by_id[WORKER_ID] = worker
	var reed: Marker2D = runtime.get_node("WorksiteMarkers/ReedSite")
	_check(runtime.daily.toggle(&"ReedSite", WORKER_ID) and runtime.daily.start(&"ReedSite", runtime._drop_daily_output.bind(reed)), "Native reed assignment starts")
	visuals._process(0.05)
	var actor: Node2D = visuals.actors[WORKER_ID]
	_check(actor.visible and not worker.physical_approach.arrived, "Reed worker stays visible while approaching")
	_check(actor.z_index == 0 and actor.get_node("FootSort").z_index == 0, "Worker keeps native Z with feet sorting")
	_check(actor.get_node("FootSort").global_position == actor.global_position + Vector2(0, 16), "Worker feet remain sixteen pixels below art origin")
	for _frame: int in range(2400):
		if worker.physical_approach.arrived:
			break
		visuals._process(0.05)
	_check(worker.physical_approach.arrived, "Reed worker reaches authored target physically")
	TimeComponentManager.advance_minutes(1)
	visuals._process(0.05)
	_check(not actor.visible and visuals.reed_inside.has(WORKER_ID), "Arrived active reed worker is inside the reeds")
	_check(visuals.reed_splash != null and visuals.reed_splash.emitting, "Active reed work emits the water splash")
	_check(not visuals.work_cycles.has(WORKER_ID), "Hidden reed work does not wander away from arrival")
	await _capture("reed-working-splash", reed.global_position)
	var units: int = int(runtime.daily.jobs[&"ReedSite"].units)
	var position_before: Vector2 = worker.physical_approach.position
	TimeComponentManager.is_paused = true
	visuals._process(1.0)
	_check(not actor.visible and not visuals.reed_splash.emitting and worker.physical_approach.position == position_before and int(runtime.daily.jobs[&"ReedSite"].units) == units, "Pause preserves hidden reed pose/output and stops splash emission")
	TimeComponentManager.is_paused = false
	_check(runtime._drop_daily_output(2, reed), "Reed output creates a reachable native ground stack")
	var drop: Node2D = runtime.get_node("GroundOutput").get_child(-1)
	var route: PackedVector2Array = runtime.worksite_navigation.route(runtime.player.global_position + Vector2(0, -4), drop.global_position)
	_check(not route.is_empty() and runtime.worksite_navigation.is_clear(drop.global_position), "Reed drop route and endpoint clear authored solids")
	_check(runtime._drop_daily_output(3, reed) and drop.quantity == 5, "Repeated reed output merges into the existing stack")
	visuals._process(0.05)
	await _capture("reed-ground-output", reed.global_position)
	await _walk_to_pickup(drop, route)
	_check(runtime.daily.withdraw(&"ReedSite", WORKER_ID), "Native withdrawal succeeds")
	visuals._process(0.05)
	_check(actor.visible and visuals.reed_inside.is_empty() and not visuals.reed_splash.emitting, "Withdrawal restores worker visibility and stops splash")
	_check(runtime.daily.toggle(&"ReedSite", WORKER_ID) and runtime.daily.start(&"ReedSite", runtime._drop_daily_output.bind(reed)), "Same-minute native reassignment succeeds")
	_check(not worker.physical_approach.arrived and not visuals._reed_working(WORKER_ID), "Reassignment cannot reuse hidden/arrived state")
	runtime.daily.withdraw(&"ReedSite", WORKER_ID)
	await _capture_clay_depth(actor)
	city.free()
	WorkerDatabase.workers_by_id.erase(WORKER_ID)
	print("WorksitePresentation: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _walk_to_pickup(drop: Node2D, route: PackedVector2Array) -> void:
	var player: Player = runtime.player
	player.can_move = false
	var completed: bool = not route.is_empty()
	for point: Vector2 in route:
		var motion: Vector2 = point - (player.global_position + Vector2(0, -4))
		var hit: KinematicCollision2D = player.move_and_collide(motion)
		if hit != null and (player.global_position + Vector2(0, -4)).distance_to(point) > 0.1:
			completed = false
			break
		await get_tree().physics_frame
	player.can_move = true
	await get_tree().physics_frame
	player._refresh_current_interactable()
	_check(completed, "Actual player circle traverses every authored-solid route segment to reed output")
	_check(player.current_interactable == drop, "Reed output gains native E focus after actual player movement")
	if completed and player.current_interactable == drop:
		var before: int = int(Inventory.items.get("reed_bundle", 0))
		var event := InputEventAction.new()
		event.action = &"interact"
		event.pressed = true
		player._unhandled_input(event)
		_check(drop.is_collecting and int(Inventory.items.get("reed_bundle", 0)) == before + 5, "Native E handler picks up the reachable merged reed stack")
		await get_tree().create_timer(0.4).timeout

func _capture_clay_depth(actor: Node2D) -> void:
	if capture_camera == null:
		return
	var site: Node2D = runtime.get_node("WorksiteMarkers/ClaySiteA")
	_check(runtime.daily.toggle(&"ClaySiteA", WORKER_ID) and runtime.daily.start(&"ClaySiteA", func(_quantity: int) -> bool: return true), "Native clay assignment starts for visual depth captures")
	for _frame: int in range(2400):
		if worker.physical_approach.arrived:
			break
		visuals._process(0.05)
	visuals._process(0.05)
	await _capture("clay-arrived-working", site.global_position)
	var original: Vector2 = actor.global_position
	var icon: Sprite2D = site.get_node("ResourceIcon")
	# Render-only probes: task identity, saved approach and authored owners stay intact.
	visuals._play(actor, "work", "right")
	actor.show()
	for layer: Node in actor.get_node("FootSort").get_children():
		if layer is AnimatedSprite2D:
			layer.pause()
			if layer.sprite_frames != null and layer.sprite_frames.has_animation(layer.animation):
				var count: int = layer.sprite_frames.get_frame_count(layer.animation)
				if count > 0:
					layer.set_frame_and_progress(mini(3, count - 1), 0.0)
	actor.global_position = icon.global_position - Vector2(0, 16) + Vector2(0, -2)
	await _capture("clay-worker-behind-render-probe", site.global_position)
	actor.global_position = icon.global_position - Vector2(0, 16) + Vector2(0, 2)
	await _capture("clay-worker-front-render-probe", site.global_position)
	actor.global_position = original
	actor.hide()
	var player: Player = runtime.player
	var previous_player: Vector2 = player.global_position
	var previous_movement: bool = player.can_move
	player.can_move = false
	player.global_position = icon.global_position + Vector2(0, -2)
	await _capture("clay-player-behind-render-probe", site.global_position)
	player.global_position = icon.global_position + Vector2(0, 2)
	await _capture("clay-player-front-render-probe", site.global_position)
	player.global_position = previous_player
	player.can_move = previous_movement
	actor.show()
	runtime.daily.withdraw(&"ClaySiteA", WORKER_ID)

func _capture(stem: String, center: Vector2) -> void:
	var directory: String = OS.get_environment("TIP_MVP_CAPTURE_DIR")
	if directory.is_empty() or capture_camera == null:
		return
	DirAccess.make_dir_recursive_absolute(directory)
	capture_camera.global_position = center
	capture_camera.reset_smoothing()
	capture_camera.force_update_scroll()
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	if stem.begins_with("clay-worker-") and stem.contains("render-probe"):
		var actor: Node2D = visuals.actors[WORKER_ID]
		var icon: Sprite2D = runtime.get_node("WorksiteMarkers/ClaySiteA/ResourceIcon")
		var used: Rect2i = icon.texture.get_image().get_used_rect()
		var offset: Vector2 = icon.offset - Vector2(icon.texture.get_size()) * 0.5 if icon.centered else icon.offset
		var bottom: Vector2 = icon.to_global(Vector2(used.get_center().x, used.end.y) + offset)
		_check(actor.visible and not actor.body_sprite.is_playing() and actor.body_sprite.frame == 3 and actor.head_sprite.frame == 3, "Front/back probes keep the same visible frozen work frame")
		print("WorksiteDepthCapture: ", JSON.stringify({"capture": stem, "worker_feet": str(actor.get_node("FootSort").global_position), "icon_bottom": str(bottom), "visible": actor.is_visible_in_tree(), "body_frame": actor.body_sprite.frame, "head_frame": actor.head_sprite.frame}))
	elif stem.begins_with("clay-player-"):
		_check(runtime.player.is_visible_in_tree() and runtime.player.z_index == 0, "Player depth probes retain native visible root and Z zero")
		print("PlayerDepthCapture: ", JSON.stringify({"capture": stem, "player_feet": str(runtime.player.global_position), "z_index": runtime.player.z_index}))
	var capture: Image = get_viewport().get_texture().get_image()
	var crop_size := Vector2i(mini(128, capture.get_width()), mini(96, capture.get_height()))
	var crop_origin := Vector2i((capture.get_width() - crop_size.x) / 2, maxi(0, (capture.get_height() - crop_size.y) / 2 - 8))
	var crop: Image = capture.get_region(Rect2i(crop_origin, crop_size))
	# Nearest-neighbor enlargement exposes the actual pixel ordering without filtering.
	capture.resize(1200, 675, Image.INTERPOLATE_NEAREST)
	_check(capture.save_png(directory.path_join(stem + ".png")) == OK, "Save 1200x675 visual capture " + stem)
	crop.resize(crop_size.x * 6, crop_size.y * 6, Image.INTERPOLATE_NEAREST)
	_check(crop.save_png(directory.path_join(stem + "-crop.png")) == OK, "Save readable pixel crop " + stem)

func _test_player_contacts() -> void:
	var player: Player = runtime.player
	var original: Vector2 = player.global_position
	player.can_move = false
	for site_id: String in ["ClaySiteA", "ReedSite"]:
		var site: Node2D = runtime.get_node("WorksiteMarkers/" + site_id)
		var body: StaticBody2D = site.get_node("ResourceBase")
		var polygon: CollisionPolygon2D = body.get_child(0)
		var bounds := Rect2(polygon.polygon[0], Vector2.ZERO)
		for point: Vector2 in polygon.polygon:
			bounds = bounds.expand(point)
		var bottom: Vector2 = body.to_global(Vector2(bounds.get_center().x, bounds.end.y))
		# Player collision center is four pixels above its root, as authored.
		player.global_position = bottom + Vector2(0, 16)
		var hit: KinematicCollision2D = player.move_and_collide(Vector2(0, -24), true)
		_check(hit != null and hit.get_collider() == body, site_id + ": actual player circle stops at resource contact")
		_check(is_equal_approx(runtime.site_slot_destination(StringName(site_id), 0).y, site.global_position.y + 11.5), site_id + ": larger art preserves the existing schema8 feet target")
	player.global_position = original
	player.can_move = true

func _test_contact_geometry() -> void:
	var root := Node2D.new()
	var site := Marker2D.new()
	var icon := Sprite2D.new()
	icon.name = "ResourceIcon"
	var image := Image.create(20, 30, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(4, 3, 12, 24), Color.WHITE)
	icon.texture = ImageTexture.create_from_image(image)
	icon.position = Vector2(2, -7)
	icon.offset = Vector2(1, 2)
	site.add_child(icon)
	root.add_child(site)
	add_child(root)
	var pixel_origin: Vector2 = icon.to_global(icon.offset - Vector2(image.get_size()) * 0.5)
	PRESENTATION.configure(site)
	_check(icon.to_global(icon.offset - Vector2(image.get_size()) * 0.5).is_equal_approx(pixel_origin), "Foot anchoring preserves every visible pixel position")
	_check(site.has_node("ResourceBase/CollisionPolygon2D") and site.y_sort_enabled, "Resource art has actual player collision and front/back depth")
	var navigation = NAVIGATION.new()
	navigation.configure(root)
	var center: Vector2 = site.to_global(Vector2(3, 4))
	_check(not navigation.is_clear(center), "Resource contact is shared with worker navigation")
	_check(icon.z_index == 0, "Resource art keeps native Z")
	PRESENTATION.configure(site)
	_check(site.get_child_count() == 2, "Repeated configuration does not duplicate collision")
	root.free()
