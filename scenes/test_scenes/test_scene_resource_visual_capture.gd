extends Node

## QA-only stills of the authored map, with presentation state set explicitly.
## No checkpoint is loaded or written by this fixture.
const CITY = preload("res://scenes/content_scene/content_scene.tscn")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var out_dir: String = OS.get_environment("TIP_RESOURCE_VISUAL_OUTPUT")
	if out_dir.is_empty() or not out_dir.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("A graphical display and absolute isolated capture directory are required.")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1200, 675)
	TimeComponentManager.set_process(false)
	var city: Node2D = CITY.instantiate()
	get_tree().root.add_child(city)
	get_tree().current_scene = city
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Player = city.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.debug_disable_fatigue = true
	player.hide()
	for path: String in ["TopHUD", "BottomHUD", "TimeDebugOverlay"]:
		var hud: Node = city.get_node_or_null(path)
		if hud is CanvasLayer or hud is CanvasItem:
			hud.hide()
	var work: Node = city.get_node("YSortWorld/WorkerRuntime")
	var camera := Camera2D.new()
	city.add_child(camera)
	camera.zoom = Vector2.ONE
	camera.make_current()
	for site_name: StringName in [&"WoodSite", &"ReedSite"]:
		var marker: Node2D = work.get_node("WorksiteMarkers/" + str(site_name))
		camera.global_position = marker.global_position + Vector2(0, -15)
		for phase: String in ["ready", "cut", "recovered"]:
			var cut: bool = phase == "cut"
			work._set_site_depleted_presentation(site_name, cut)
			await get_tree().create_timer(1.8).timeout
			await RenderingServer.frame_post_draw
			var particles: CPUParticles2D = marker.get_node("ReadyParticles")
			var cut_sprite: CanvasItem = marker.get_node("WoodGrove/Stump0" if site_name == &"WoodSite" else "CuttedReed")
			var ready_sprite: CanvasItem = marker.get_node("WoodGrove/Tree0" if site_name == &"WoodSite" else "ResourceIcon")
			if particles.emitting == cut or particles.visible == cut or cut_sprite.visible != cut or ready_sprite.visible == cut:
				push_error("Unexpected visible state for %s %s" % [site_name, phase])
				get_tree().quit(1)
				return
			var img: Image = get_viewport().get_texture().get_image()
			var file: String = out_dir.path_join("%s-%s.png" % [site_name, phase])
			var error: Error = img.save_png(file)
			if error != OK:
				push_error("Capture failed %s: %s" % [file, error])
				get_tree().quit(1)
				return
			print("RESOURCE_CAPTURE ", site_name, " ", phase, " image=", img.get_size(), " particles=", particles.emitting, " cut=", cut_sprite.visible, " pos=", marker.global_position)
	print("ResourceVisualCapture: PASS")
	get_tree().quit(0)
