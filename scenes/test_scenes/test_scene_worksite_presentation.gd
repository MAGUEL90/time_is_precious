extends Node

## Explicit isolated fixtures only; no checkpoint load/save or economy changes.
const CONTENT = preload("res://scenes/content_scene/content_scene.tscn")
const PRESENTATION = preload("res://scenes/content_scene/worksites/resource_site_presentation.gd")
const NAVIGATION = preload("res://scenes/content_scene/worksites/worksite_navigation.gd")
const VISIBLE_BOUNDS = preload("res://scenes/workshop_plot/keeper/workshop_visual_bounds.gd")
const PROMPT = preload("res://scenes/components/interactable_label_component/interactable_label_component.tscn")
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
	_test_transformed_prompt()
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
	_test_cosmetic_views()
	await _test_active_prompt_positions()
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
	_check(not drop.get_node("QuantityLabel").visible and drop.get_node("QuantityLabel").text == "x5", "Merged ground count stays hidden while its exact text/data remain")
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

func _test_cosmetic_views() -> void:
	for site_id: String in ["ClaySiteA", "WoodSite", "ReedSite", "StrawSite", "WaterSite"]:
		var site: Marker2D = runtime.get_node("WorksiteMarkers/" + site_id)
		var label: Label = site.get_node("Label")
		var prompt: InteractableLabelComponent = site.get_node("InteractPrompt")
		_check(prompt.label.text == "E", site_id + ": prompt keeps the native E action")
		if site_id in ["ClaySiteA", "ReedSite"]:
			_check(not label.visible and not label.text.is_empty(), site_id + ": world name is hidden and its menu text retained")
			runtime._open_site_panel(site)
			_check(runtime.inspector.visible and runtime.inspector.title.text == label.text, site_id + ": native menu retains its title from the hidden world label")
			runtime._close_inspector()
		else:
			_check(label.visible, site_id + ": other world label remains visible")
	for item_id: String in ["clay_lump", "wood_log", "reed_bundle", "straw_bundle", "water_jar"]:
		_check(runtime._drop_output_at(7, Vector2(140, 100), Callable(), item_id), item_id + ": content ground output creates normally")
		var drop: Node = runtime.get_node("GroundOutput").get_child(-1)
		_check(drop.quantity == 7 and drop.get_node("QuantityLabel").text == "x7" and not drop.get_node("QuantityLabel").visible, item_id + ": only the world count is hidden")
		drop.free()
	var key: StringName = runtime.RESOURCE_STOCK_META
	var had_stock: bool = WorkStateRuntime.has_meta(key)
	var prior_stock: Variant = WorkStateRuntime.get_meta(key) if had_stock else null
	WorkStateRuntime.set_meta(key, {"day": TimeComponentManager.current_day, "sites": {}, "storages": {}, "ground": [{"item_id": "wood_log", "quantity": 9, "position": Vector2(140, 100), "site": ""}]})
	runtime._restore_resource_stock()
	var restored: Node = runtime.get_node("GroundOutput").get_child(-1)
	_check(restored.quantity == 9 and restored.get_node("QuantityLabel").text == "x9" and not restored.get_node("QuantityLabel").visible, "Restored content pile preserves its quantity and hides its world count")
	restored.free()
	if had_stock:
		WorkStateRuntime.set_meta(key, prior_stock)
	else:
		WorkStateRuntime.remove_meta(key)

func _test_active_prompt_positions() -> void:
	var player: Player = runtime.player
	var previous: Vector2 = player.global_position
	for site_id: String in ["ClaySiteA", "WoodSite", "ReedSite", "StrawSite", "WaterSite"]:
		var site: Marker2D = runtime.get_node("WorksiteMarkers/" + site_id)
		var fixed_box: Rect2 = site.get_node("InteractPrompt").get_global_transform() * Rect2(Vector2.ZERO, Vector2(16, 16))
		var side: float = -1.0 # East-column palms own E when approached from the outside.
		for pose: Vector2 in [Vector2(side * 18.0, 10.0), Vector2(side * 20.0, -10.0)]:
			player._set_current_interactable(null)
			player.global_position = site.global_position + pose
			if capture_camera != null:
				capture_camera.global_position = player.global_position
				await get_tree().process_frame
			runtime._process(0.0)
			var prompt: InteractableLabelComponent = site.get_node("InteractPrompt")
			var suffix: String = "-alt" if pose.y < 0.0 else ""
			_check(runtime._highlighted_site == site and prompt.visible, site_id + suffix + ": actual nearby worksite owns the visible E")
			if site_id not in ["ClaySiteA", "ReedSite"]:
				_check(not site.get_node("Label").visible, site_id + suffix + ": its world label yields to the E above the art")
			await _capture("active-E-" + site_id + suffix, player.global_position)
			_check(runtime._highlighted_site == site and prompt.visible, site_id + suffix + ": worksite still owns E after rendering")
			_check_target_prompt(prompt, site.get_node("ResourceIcon"), fixed_box, site_id + suffix)
			var before_walk: Vector2 = player.global_position
			Input.action_press(&"move_down")
			for _step: int in range(6):
				await get_tree().physics_frame
			Input.action_release(&"move_down")
			await get_tree().process_frame
			_check(player.global_position.distance_to(before_walk) >= 2.0, site_id + suffix + ": native movement advances the player")
			_check(runtime._highlighted_site == site and prompt.visible, site_id + suffix + ": E remains focused through native movement")
			_check_target_prompt(prompt, site.get_node("ResourceIcon"), fixed_box, site_id + suffix + "-walked")
			if suffix.is_empty():
				await _capture("active-E-" + site_id + "-walked", player.global_position)
	var storage: Node = runtime.get_node("CityStorageArea")
	player._set_current_interactable(null)
	player.global_position = storage.get_node("Board").global_position + Vector2(-17, 13)
	for _frame: int in range(3):
		await get_tree().physics_frame
	player._refresh_current_interactable()
	runtime._process(0.0)
	var storage_prompt: InteractableLabelComponent = storage.interactable_label_component
	_check(player.current_interactable == storage and storage_prompt.visible and storage.has_player_access(), "City Storage board access owns the visible E")
	_check(storage.get_node("Label").visible, "City Storage caption remains visible while its board is focused")
	_check_board_prompt(storage_prompt, storage.get_node("Board"))
	await _capture("active-E-CityStorage", player.global_position)
	var board_prompt_box: Rect2 = storage_prompt.get_global_transform() * Rect2(Vector2.ZERO, storage_prompt.size)
	Input.action_press(&"move_right")
	for _step: int in range(5):
		await get_tree().physics_frame
	Input.action_release(&"move_right")
	await get_tree().process_frame
	_check(player.current_interactable == storage and storage.has_player_access(), "Normal movement inside the front board access keeps City Storage focused")
	_check((storage_prompt.get_global_transform() * Rect2(Vector2.ZERO, storage_prompt.size)).is_equal_approx(board_prompt_box), "City Storage E stays on the board while the player moves")
	await _capture("active-E-CityStorage-walked", player.global_position)
	storage.on_player_interact(player)
	_check(is_instance_valid(storage.menu) and storage.menu.visible, "E at the front board opens the normal City Storage menu")
	storage.close_menu()
	player.global_position = previous
	player._set_current_interactable(null)

func _check_board_prompt(prompt: InteractableLabelComponent, board: Node) -> void:
	var art: Rect2 = VISIBLE_BOUNDS.measure(board)
	var box: Rect2 = prompt.get_global_transform() * Rect2(Vector2.ZERO, prompt.size)
	_check(_above_with_gap(box, art), "City Storage E sits centered two world pixels above its front board")
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var art_screen: Rect2 = canvas * art
	var box_screen: Rect2 = prompt.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, prompt.size)
	_check(is_equal_approx(art_screen.position.y - box_screen.end.y, 2.0 * canvas.get_scale().y), "City Storage board and E retain their gap through the camera")
	print("ActivePrompt ", JSON.stringify({"owner": "CityStorageBoard", "world_box": str(box), "canvas_box": str(box_screen)}))

func _check_target_prompt(prompt: InteractableLabelComponent, icon: Node, initial_box: Rect2, label: String) -> void:
	var art: Rect2 = VISIBLE_BOUNDS.measure(icon)
	var box: Rect2 = prompt.get_global_transform() * Rect2(Vector2.ZERO, prompt.size)
	_check(box.is_equal_approx(initial_box), label + ": E remains fixed on the selected site while the player changes sides")
	_check(_above_with_gap(box, art), label + ": E stays centered two world pixels above its resource icon")
	for neighbor: Marker2D in runtime.get_node("WorksiteMarkers").get_children():
		if neighbor.get_node("ResourceIcon") != icon:
			_check(not box.intersects(VISIBLE_BOUNDS.measure(neighbor.get_node("ResourceIcon"))), label + ": E avoids " + str(neighbor.name) + " artwork")
	var canvas_box: Rect2 = get_viewport().get_canvas_transform() * box
	var prompt_canvas_box: Rect2 = prompt.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, prompt.size)
	_check(canvas_box.is_equal_approx(prompt_canvas_box), label + ": prompt and viewport agree on the camera transform")
	if capture_camera != null:
		_check(get_viewport().get_visible_rect().encloses(canvas_box), label + ": camera keeps the E inside the viewport")
	print("ActivePrompt ", JSON.stringify({"owner": label, "world_box": str(box), "canvas_box": str(canvas_box), "prompt_canvas_box": str(prompt_canvas_box)}))

func _above_with_gap(box: Rect2, art: Rect2) -> bool:
	return is_equal_approx(box.get_center().x, art.get_center().x) and is_equal_approx(art.position.y - box.end.y, 2.0)

func _test_transformed_prompt() -> void:
	var site := Marker2D.new()
	site.position = Vector2(37, 11)
	site.scale = Vector2(2, 1.5)
	var icon := Sprite2D.new()
	icon.name = "ResourceIcon"
	var image := Image.create(48, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(35, 18, 7, 10), Color.WHITE)
	image.fill_rect(Rect2i(19, 18, 10, 5), Color.WHITE)
	icon.texture = ImageTexture.create_from_image(image)
	icon.region_enabled = true
	icon.region_rect = Rect2(16, 0, 32, 32)
	icon.hframes = 2
	icon.vframes = 2
	icon.frame_coords = Vector2i(1, 1)
	icon.flip_h = true
	icon.flip_v = true
	icon.offset = Vector2(5, -3)
	icon.position = Vector2(10, -20)
	icon.scale = Vector2(1.5, 2)
	site.add_child(icon)
	var prompt: InteractableLabelComponent = PROMPT.instantiate()
	prompt.name = "InteractPrompt"
	site.add_child(prompt)
	add_child(site)
	PRESENTATION.position_prompt(site, icon)
	var art: Rect2 = VISIBLE_BOUNDS.measure(icon)
	_check(art.is_equal_approx(Rect2(66, -40, 21, 30)), "Prompt bounds use the actual flipped region frame, alpha margins, offset and inherited scale")
	var bounds: Rect2 = prompt.get_global_transform() * Rect2(Vector2.ZERO, prompt.size)
	_check(_above_with_gap(bounds, art), "Transformed art retains a centered E above and two logical pixel gap")
	var position_before: Vector2 = prompt.position
	icon.frame_coords = Vector2i(0, 1)
	icon.flip_h = false
	icon.flip_v = false
	PRESENTATION.position_prompt(site, icon)
	art = VISIBLE_BOUNDS.measure(icon)
	bounds = prompt.get_global_transform() * Rect2(Vector2.ZERO, prompt.size)
	_check(prompt.position != position_before and _above_with_gap(bounds, art), "A different visible frame receives its own correct prompt anchor")
	site.rotation_degrees = 33.0
	PRESENTATION.position_prompt(site, icon)
	art = VISIBLE_BOUNDS.measure(icon)
	bounds = prompt.get_global_transform() * Rect2(Vector2.ZERO, prompt.size)
	_check(_above_with_gap(bounds, art), "Rotated nonuniformly scaled site keeps E above visible art")
	site.name = "ClaySiteA"
	PRESENTATION.position_prompt(site, icon)
	art = VISIBLE_BOUNDS.measure(icon)
	bounds = prompt.get_global_transform() * Rect2(Vector2.ZERO, prompt.size)
	_check(_above_with_gap(bounds, art), "Rotated scaled left-column site keeps E clear of the art")
	site.name = "StrawSite"
	PRESENTATION.position_prompt(site, icon)
	art = VISIBLE_BOUNDS.measure(icon)
	bounds = prompt.get_global_transform() * Rect2(Vector2.ZERO, prompt.size)
	_check(_above_with_gap(bounds, art), "Rotated scaled right-column site keeps E clear of the art")
	site.free()

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
