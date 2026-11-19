extends Node

## Visual review of normal focus from staged collision-free player positions.
## It uses the real authored city and existing gameplay artwork and widgets.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const VISIBLE_BOUNDS = preload("res://scenes/workshop_plot/keeper/workshop_visual_bounds.gd")
const RESOURCE_PRESENTATION = preload("res://scenes/content_scene/worksites/resource_site_presentation.gd")
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _settle() -> void:
	for _i: int in range(8):
		await get_tree().physics_frame
		await get_tree().process_frame

func _capture(directory: String, stem: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	_check(frame.get_size() == Vector2i(400, 225), stem + ": use the native 400x225 viewport")
	_check(frame.save_png(directory.path_join(stem + ".png")) == OK, stem + ": save captured frame")

func _run() -> void:
	var data_root: String = OS.get_environment("XDG_DATA_HOME").simplify_path().trim_suffix("/")
	var directory: String = OS.get_environment("TIP_QA_CAPTURE_ROOT").simplify_path()
	_check(data_root.is_absolute_path() and ProjectSettings.globalize_path("user://").simplify_path().begins_with(data_root + "/"), "Use an isolated XDG profile")
	_check(directory.is_absolute_path() and directory.begins_with(data_root + "/"), "Capture files stay in the isolated profile")
	_check(DisplayServer.get_name() != "headless", "The visual probe requires a graphical display")
	if failures:
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_size = Vector2i(400, 225)
	get_window().size = Vector2i(1200, 675)
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	var city: Node = CITY.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	await _settle()
	var work: Node = city.get_node("YSortWorld/WorkerRuntime")
	var player: Player = city.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	player.get_node("Camera2D").make_current()
	for site_id: String in ["WoodSite", "WoodSiteB", "WoodSiteC", "WoodSiteD", "WoodSiteE", "ClaySiteA", "ClaySiteB", "ReedSite"]:
		var site: Node2D = work.get_node("WorksiteMarkers/" + site_id)
		var offset: Vector2 = Vector2(14.14214, 14.14214) if site_id.begins_with("Reed") else Vector2(20, 0)
		player._set_current_interactable(null)
		player.global_position = site.global_position + offset
		await _settle()
		player._refresh_current_interactable()
		work._process(0.0)
		_check(work._highlighted_site == site and site.get_node("InteractPrompt").visible, "The expected prompt is visible for " + site_id)
		var art: CanvasItem = site.get_node("WoodGrove/Tree0" if site_id.begins_with("Wood") else "ResourceIcon")
		_check_gap(site.get_node("InteractPrompt"), art, site_id)
		var particles: CPUParticles2D = site.get_node("ReadyParticles")
		var visual_center: Vector2 = VISIBLE_BOUNDS.measure(art).get_center()
		_check(particles.visible and particles.emitting and particles.global_position.distance_to(visual_center) <= 0.72,
			site_id + ": ready particle emitter is centered on visible resource art")
		await _capture(directory, "focus-" + site_id)
		if site_id == "WoodSite":
			RESOURCE_PRESENTATION.set_wood_depleted(site, true)
			await get_tree().process_frame
			_check_gap(site.get_node("InteractPrompt"), site.get_node("WoodGrove/Stump0"), "Depleted wood")
			RESOURCE_PRESENTATION.set_wood_depleted(site, false)
			await get_tree().process_frame
			_check_gap(site.get_node("InteractPrompt"), site.get_node("WoodGrove/Tree0"), "Regrown wood")
		var press := InputEventAction.new()
		press.action = "interact"
		press.pressed = true
		get_viewport().push_input(press)
		await get_tree().process_frame
		_check(work.inspector.visible, site_id + ": interact still opens the worksite panel")
		if work.inspector.visible:
			work._close_inspector()
		var release := InputEventAction.new()
		release.action = "interact"
		get_viewport().push_input(release)
		await get_tree().process_frame
	for site_id: String in ["WoodSiteD", "ClaySiteA", "ReedSite"]:
		var site: Node = work.get_node("WorksiteMarkers/" + site_id)
		var particles: CPUParticles2D = site.get_node("ReadyParticles")
		var stock: int = work.sites[StringName(site_id)].stock
		work._set_site_depleted_presentation(StringName(site_id), true)
		_check(not particles.visible and not particles.emitting, site_id + ": depleted particles stay hidden")
		work._set_site_depleted_presentation(StringName(site_id), false)
		_check(particles.visible and particles.emitting and work.sites[StringName(site_id)].stock == stock,
			site_id + ": restored particles return without changing stock")
	var storage: Node = work.get_node("CityStorageArea")
	player._set_current_interactable(null)
	player.global_position = storage.get_node("Board").global_position + Vector2(-17, 13)
	await _settle()
	player._refresh_current_interactable()
	work._process(0.0)
	if storage.get_node("Board").is_visible_in_tree():
		_check(player.current_interactable == storage and storage.interactable_label_component.visible and storage.has_player_access(), "City Storage board owns the visible E")
		_check_gap(storage.interactable_label_component, storage.get_node("Board"), "City Storage")
		await _capture(directory, "focus-CityStorage")
	var gabbi: Node = city.get_node("YSortWorld/Gabbi")
	_check_gap(gabbi.interactable_label_component, gabbi.get_node("GabbiVisual"), "Gabbi")
	player.global_position = work.get_node("WorksiteMarkers/ClaySiteA").global_position + Vector2(20, 0)
	await _settle()
	var pickup: PickUpItem = load("res://scenes/pickup_item/pickup_item.tscn").instantiate()
	pickup.item_id = "wood_log"
	city.add_child(pickup)
	pickup.global_position = player.global_position + Vector2(20, 0)
	await _settle()
	pickup.interactable_label_component.show()
	await get_tree().process_frame
	var pickup_art: Rect2 = VISIBLE_BOUNDS.measure(pickup.icon)
	var pickup_box: Rect2 = pickup.interactable_label_component.get_global_transform() * Rect2(Vector2.ZERO, pickup.interactable_label_component.size)
	var pickup_gap: float = pickup_art.position.y - pickup_box.end.y
	_check(pickup_art.has_area() and pickup_gap >= 3.0 and pickup_gap <= 5.0,
		"Floating pickup keeps E three to five game pixels above its visible art")
	pickup.queue_free()
	var cot: SleepSpot = load("res://scenes/sleep_spot/sleep_spot.tscn").instantiate()
	city.add_child(cot)
	cot.global_position = player.global_position
	await get_tree().process_frame
	_check_gap(cot.interactable_label_component, cot.get_node("Sprite2D"), "Sleep spot")
	cot.queue_free()
	print("AuthoredPromptVisualProbe: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_gap(prompt: InteractableLabelComponent, target: CanvasItem, label: String) -> void:
	var art: Rect2 = VISIBLE_BOUNDS.measure(target)
	var box: Rect2 = prompt.get_global_transform() * Rect2(Vector2.ZERO, prompt.size)
	var screen_box: Rect2 = prompt.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, prompt.size)
	var art_screen: Rect2 = get_viewport().get_canvas_transform() * art
	var ideal := Rect2(Vector2(art_screen.get_center().x - screen_box.size.x * 0.5,
		art_screen.position.y - 4.0 - screen_box.size.y), screen_box.size)
	var safe: Rect2 = get_viewport().get_visible_rect().grow(-4.0)
	if safe.encloses(ideal):
		_check(art.has_area() and is_equal_approx(art.position.y - box.end.y, 4.0)
			and is_equal_approx(art.get_center().x, box.get_center().x),
			label + ": E is centered four game pixels above visible art")
	else:
		_check(safe.encloses(screen_box), label + ": E stays in the viewport near an edge")
