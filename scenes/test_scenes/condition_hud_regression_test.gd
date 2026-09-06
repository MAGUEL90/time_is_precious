extends Node

var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	get_tree().paused = true
	var player: Player = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	_expect(not player.debug_disable_player_needs, "Player needs must be enabled by default.")
	player.fatigue = 0.2
	player.hunger = 0.1
	player.focus = 0.9
	var hud = load("res://scenes/ui/bottom_hud/bottom_hud.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame
	_expect(hud.fatigue_bar.value == 80 and hud.hunger_bar.value == 90 and hud.focus_bar.value == 90, "All bars must display remaining healthy condition.")
	_expect(not hud.status_drawer.visible, "Healthy initial HUD must be closed.")
	_expect(hud.find_child("ConditionHelp", true, false) == null and hud.find_child("ConditionAlert", true, false) == null, "HUD must not create help notes or text alerts.")
	_expect(hud.status_drawer.get_node("StatusNames").get_child(0).text == "Energy", "Fatigue must be presented as Energy.")
	_expect(hud.status_drawer.get_node("StatusNames").get_child(2).text == "Satiety", "Hunger must be presented as Satiety.")
	player.fatigue_warning_threshold = 0.65
	player.fatigue = 0.65
	player.condition_changed.emit()
	await get_tree().process_frame
	_expect(hud.fatigue_indicator.modulate == hud.CONDITION_WARNING_COLOR, "HUD must follow the player's configured severity.")
	player.condition_changed.emit()
	await get_tree().process_frame
	_expect(hud.find_child("ConditionAlert", true, false) == null, "Condition updates must not create text alerts.")
	player.fatigue = 0.91
	player.focus = 0.09
	player.condition_changed.emit()
	await get_tree().process_frame
	_expect(hud.fatigue_indicator.modulate == hud.CONDITION_CRITICAL_COLOR, "Critical color must match player critical severity.")
	_expect(hud.focus_indicator.modulate == hud.CONDITION_CRITICAL_COLOR, "Focus must also reflect critical severity.")
	player.fatigue = 0.2
	player.focus = 0.9
	player.condition_changed.emit()
	await get_tree().process_frame
	_expect(hud.fatigue_indicator.modulate == hud.CONDITION_NORMAL_COLOR, "Recovery must restore the normal color.")
	var before_hunger: float = player.hunger
	var before_fatigue: float = player.fatigue
	var before_focus: float = player.focus
	player.on_minute_changed(1)
	_expect(player.hunger > before_hunger and player.fatigue > before_fatigue and player.focus < before_focus, "Normal time must affect all needs again.")
	var focus_after_time: float = player.focus
	player.reduce_hunger(0.01)
	_expect(player.focus == focus_after_time, "Eating must not directly refill Focus.")
	player.fatigue = 0.2
	player.hunger = 1.0
	player.focus = 0.9
	_expect(not player.has_critical_condition(), "Zero Satiety alone must not trigger collapse.")
	player.on_minute_changed(2)
	_expect(not player.is_collapsing, "A hungry player with healthy Energy and Focus must stay awake.")
	player.focus = 0.9
	player.hunger = 0.0
	player._apply_awake_focus_loss()
	var fed_focus_loss: float = 0.9 - player.focus
	player.focus = 0.9
	player.hunger = 1.0
	player._apply_awake_focus_loss()
	var hungry_focus_loss: float = 0.9 - player.focus
	_expect(hungry_focus_loss > fed_focus_loss, "Low Satiety must still accelerate Focus drain.")
	_expect(is_equal_approx(hungry_focus_loss, player.focus_loss_per_min + player.focus_loss_from_hunger_per_min), "Existing hunger Focus penalty must be unchanged.")
	player.focus = player.focus_critical_threshold
	_expect(player.has_critical_condition(), "Critical Focus must still trigger collapse.")
	player.focus = 0.9
	player.fatigue = player.fatigue_critical_threshold
	_expect(player.has_critical_condition(), "Critical fatigue must still trigger collapse.")
	player.fatigue = 0.2
	player.hunger = 0.1
	player.condition_changed.emit()
	hud._animate_drawer(hud.DRAWER_OPEN_Y, 0.0)
	# Finish tween deterministically while the gameplay tree is paused.
	hud.drawer_tween.custom_step(1.0)
	_expect(hud.status_drawer.visible, "Status action must open the drawer.")
	_expect(is_equal_approx(hud.status_drawer.position.y, get_viewport().get_visible_rect().size.y - 60), "Drawer must stay anchored to the viewport bottom.")
	hud._animate_drawer(hud.DRAWER_CLOSED_Y, 0.0)
	hud.drawer_tween.custom_step(1.0)
	_expect(not hud.status_drawer.visible, "Closing must hide labels as well as bars.")
	hud._animate_drawer(hud.DRAWER_OPEN_Y, 0.0)
	hud.drawer_tween.custom_step(1.0)
	_expect(hud.status_drawer.visible, "Repeated opening must still work.")
	player.current_experience = 12
	player.experience_changed.emit()
	_expect(hud.experience_bar.value == 12, "EXP binding must remain intact.")
	hud._on_nightmare_active_changed(true)
	_expect(not hud.visible and not hud.status_drawer.visible, "Nightmare must hide all condition UI.")
	hud._on_nightmare_active_changed(false)
	_expect(hud.visible and not hud.status_drawer.visible, "Return must restore the HUD without a stuck drawer.")
	if "--capture-hud" in OS.get_cmdline_user_args():
		hud._animate_drawer(hud.DRAWER_OPEN_Y, 0.0)
		hud.drawer_tween.custom_step(1.0)
		player.fatigue = 0.8
		player.condition_changed.emit()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var capture_path: String = OS.get_environment("TEMP").path_join("condition-hud-review.png")
		get_viewport().get_texture().get_image().save_png(capture_path)
		print("HUD_CAPTURE: " + capture_path)
	await get_tree().process_frame
	hud.free()
	player.free()
	print("ConditionHUDRegressionTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
