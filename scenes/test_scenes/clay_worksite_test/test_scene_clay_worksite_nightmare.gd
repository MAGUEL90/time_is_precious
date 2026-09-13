extends Node

var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var fixture = load("res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn").instantiate()
	add_child(fixture)
	await get_tree().process_frame
	fixture.sites[&"ClaySiteA"].toggle_participant("player")
	fixture.sites[&"ClaySiteB"].toggle_participant("player")
	var player: Player = fixture.player
	var nightmare: NightmareWorld = fixture.get_node("NightmareWorld")
	var panel = fixture.inspector
	var cover: ColorRect = fixture.get_node("WorkTransition/Blackout")
	for timed_out: bool in [false, true]:
		player.fatigue = 0.88775
		player.hunger = 0.0
		player.focus = 1.0
		player.global_position = fixture.get_node("WorksiteMarkers/ClaySiteA").global_position
		var return_position: Vector2 = player.global_position
		var event := InputEventAction.new()
		event.action = "interact"
		event.pressed = true
		Input.parse_input_event(event)
		await get_tree().process_frame
		_expect(panel.visible, "Work panel opens before collapse test.")
		panel.hourly_button.pressed.emit()
		panel.next_button.pressed.emit() # Next returns to the main work confirmation.
		panel.start_button.pressed.emit()
		await get_tree().create_timer(0.3, true).timeout
		_expect(cover.modulate.a > 0.999 and player.is_collapsing, "Interruption begins on opaque black.")
		var deadline: int = Time.get_ticks_msec() + 10000
		while fixture._working and Time.get_ticks_msec() < deadline:
			_expect(cover.visible and cover.modulate.a > 0.999, "Local cover never reveals worksite before global handoff.")
			await get_tree().process_frame
		_expect(not fixture._working and not panel.visible, "Handoff closes worksite panel.")
		_expect(SceneTransition.fade_overlay.modulate.a >= 0.999, "Global transition owns opaque black on handoff.")
		await _wait_until(func(): return not SceneTransition.is_transitioning, "Nightmare entry transition completes.")
		_expect(nightmare.is_active and player.can_move, "Nightmare is playable after entry.")
		_expect(player.global_position.distance_to(nightmare.spawn_point.global_position) < 1.0, "Player reaches Nightmare spawn.")
		_expect(nightmare.return_position == return_position, "Original worksite return position retained.")
		_expect(not fixture.get_node("TopHUD").visible and TimeComponentManager.is_paused, "World HUD/time suspended inside Nightmare.")
		var fatigue_before: float = player.fatigue
		var hunger_before: float = player.hunger
		if OS.get_environment("TIP_CAPTURE_NIGHTMARE") == "1" and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("tip-clay-feedback-20260907/nightmare-playable.png"))
		if timed_out:
			nightmare.elapsed_seconds = nightmare.max_duration_seconds
		else:
			nightmare.exit_npc.body_entered.emit(player)
		await _wait_until(func(): return SceneTransition.continue_button.visible, "Nightmare result offers Continue.")
		_expect(player.global_position == return_position, "Result returns player to exact worksite position.")
		_expect(is_equal_approx(player.fatigue, maxf(fatigue_before - player.collapse_fatigue_recovery, player.min_fatigue)), "Existing collapse recovery increases Energy.")
		_expect(player.hunger >= hunger_before + player.collapse_hunger_cost - 0.00001, "Existing collapse cost decreases Satiety.")
		SceneTransition.continue_button.pressed.emit()
		await _wait_until(func(): return not SceneTransition.is_transitioning, "Nightmare return fade finishes.")
		await get_tree().process_frame
		_expect(not nightmare.is_active and not get_tree().paused and not TimeComponentManager.is_paused, "Escape/timeout restores world time.")
		_expect(player.can_move and fixture.get_node("TopHUD").visible and not panel.visible, "Movement/HUD restored without reopening panel.")
	_expect(fixture.sites[&"ClaySiteA"].stock < 72, "Stock survives Nightmare return.")
	fixture.queue_free()
	await get_tree().process_frame
	print("ClayWorksiteNightmareTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)

func _wait_until(predicate: Callable, message: String) -> void:
	var deadline: int = Time.get_ticks_msec() + 10000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(predicate.call(), message)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
