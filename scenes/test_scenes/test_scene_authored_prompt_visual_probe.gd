extends Node

## Visual review of normal focus from staged collision-free player positions.
## It uses the real authored city and existing gameplay artwork and widgets.
const CITY: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
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
	for site_id: String in ["WoodSite", "ClaySiteA", "ReedSite"]:
		var site: Node2D = work.get_node("WorksiteMarkers/" + site_id)
		var offset: Vector2 = Vector2(14.14214, 14.14214) if site_id == "ReedSite" else Vector2(20, 0)
		player._set_current_interactable(null)
		player.global_position = site.global_position + offset
		await _settle()
		player._refresh_current_interactable()
		work._process(0.0)
		_check(work._highlighted_site == site and site.get_node("InteractPrompt").visible, "The expected prompt is visible for " + site_id)
		await _capture(directory, "focus-" + site_id)
	var storage: Node = work.get_node("CityStorageArea")
	player._set_current_interactable(null)
	player.global_position = storage.get_node("Board").global_position + Vector2(-17, 13)
	await _settle()
	player._refresh_current_interactable()
	work._process(0.0)
	_check(player.current_interactable == storage and storage.interactable_label_component.visible and storage.has_player_access(), "City Storage board owns the visible E")
	await _capture(directory, "focus-CityStorage")
	print("AuthoredPromptVisualProbe: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
