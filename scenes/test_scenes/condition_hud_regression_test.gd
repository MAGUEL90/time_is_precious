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
	var hud = load("res://scenes/ui/bottom_hud/bottom_hud.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame
	_expect(hud.fatigue_bar.value == 80 and hud.hunger_bar.value == 90, "Both bars must display remaining healthy condition.")
	_expect(not hud.status_drawer.visible, "The EXP drawer must start closed.")
	_expect(hud.find_child("ConditionHelp", true, false) == null and hud.find_child("ConditionAlert", true, false) == null, "HUD must not create help notes or text alerts.")
	_expect(hud.fatigue_label.text == "Energy" and hud.hunger_label.text == "Belly", "The two hover labels use the approved names.")
	_expect(not hud.fatigue_label.visible and not hud.hunger_label.visible, "Condition names start hidden.")
	_expect(hud.status_drawer.get_node("StatusNames").get_child_count() == 1 and hud.status_drawer.get_node("IndicatorRow").get_child_count() == 1, "The Tab drawer retains EXP only.")
	_expect(hud.get_node("Root/ConditionRow").get_child_count() == 2, "Only Energy and Belly appear in the top row.")
	player.fatigue = 0.79
	player.condition_changed.emit()
	await get_tree().process_frame
	_expect(hud.fatigue_bar.modulate == Color.WHITE and not hud.condition_tweens.has(hud.fatigue_bar), "Energy above 20 percent is normal.")
	player.fatigue = 0.80
	player.condition_changed.emit()
	_expect(hud.fatigue_bar.modulate == hud.CONDITION_CRITICAL_COLOR and hud.condition_tweens.has(hud.fatigue_bar), "At 20 percent Energy the bar begins the red warning.")
	var energy_tween: Tween = hud.condition_tweens[hud.fatigue_bar]
	energy_tween.custom_step(hud.CONDITION_BLINK_HALF_PERIOD * 0.5)
	_expect(not hud.fatigue_bar.modulate.is_equal_approx(hud.CONDITION_CRITICAL_COLOR), "The critical Energy bar changes color slowly.")
	player.fatigue = 1.0
	player.hunger = 1.0
	player.condition_changed.emit()
	_expect(hud.fatigue_bar.value == 0 and hud.hunger_bar.value == 0 and hud.fatigue_bar.tint_under == hud.CONDITION_CRITICAL_TRACK_TINT and hud.hunger_bar.tint_under == hud.CONDITION_CRITICAL_TRACK_TINT and hud.condition_tweens[hud.fatigue_bar] == energy_tween and hud.condition_tweens.has(hud.hunger_bar), "Both empty tracks warn, without restarting Energy's existing blink.")
	player.fatigue = 0.2
	player.hunger = 0.1
	player.condition_changed.emit()
	await get_tree().process_frame
	_expect(hud.fatigue_bar.modulate == Color.WHITE and hud.hunger_bar.modulate == Color.WHITE and hud.fatigue_bar.tint_under == Color.WHITE and hud.hunger_bar.tint_under == Color.WHITE and hud.condition_tweens.is_empty(), "Recovery stops the warning and restores both normal bars.")
	player.hunger = 0.80
	player.condition_changed.emit()
	_expect(hud.hunger_bar.value == 20 and hud.condition_tweens.has(hud.hunger_bar) and not hud.condition_tweens.has(hud.fatigue_bar), "Belly starts its own warning at 20 percent.")
	player.hunger = 0.79
	player.condition_changed.emit()
	_expect(hud.hunger_bar.modulate == Color.WHITE and not hud.condition_tweens.has(hud.hunger_bar), "Belly above 20 percent returns to normal.")
	var before_hunger: float = player.hunger
	var before_fatigue: float = player.fatigue
	player.on_minute_changed(1)
	_expect(is_equal_approx(player.hunger, before_hunger + player.hunger_increase_per_min) and is_equal_approx(player.fatigue, before_fatigue + player.fatigue_increase_per_min), "Normal time applies both existing needs exactly once.")
	var fatigue_after_time: float = player.fatigue
	player.reduce_hunger(0.01)
	_expect(player.fatigue == fatigue_after_time, "Reducing Hunger alone does not directly restore Energy.")
	player.fatigue = 0.2
	player.hunger = 1.0
	_expect(not player.has_critical_condition(), "Zero Satiety alone must not trigger collapse.")
	player.on_minute_changed(2)
	_expect(not player.is_collapsing and is_equal_approx(player.fatigue, 0.2 + player.fatigue_increase_per_min), "A hungry player with healthy Energy stays awake and loses the normal amount of Energy.")
	player.hunger = 0.0
	_expect(is_equal_approx(player.get_sleep_recovery_quality(), 1.0), "A fed player retains full sleep recovery quality.")
	player.hunger = 1.0
	_expect(is_equal_approx(player.get_sleep_recovery_quality(), 0.25), "Full Hunger retains the existing lower sleep recovery quality.")
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
	await get_tree().process_frame
	var names: HBoxContainer = hud.status_drawer.get_node("StatusNames")
	var indicators: HBoxContainer = hud.status_drawer.get_node("IndicatorRow")
	for index: int in range(1):
		var name_label: Control = names.get_child(index) as Control
		var indicator: Control = indicators.get_child(index) as Control
		_expect(is_equal_approx(name_label.global_position.x, indicator.global_position.x), "Each status label remains aligned with its indicator.")
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
	await _test_eating_and_sleep(player)
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

func _test_eating_and_sleep(player: Player) -> void:
	get_tree().paused = false
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 1
	TimeComponentManager.current_hour = 8
	TimeComponentManager.current_minute = 0
	var original_inventory: Dictionary = Inventory.items.duplicate(true)
	Inventory.items.assign({"date_cluster": 2})
	var inventory_ui: InventoryUI = load("res://scenes/ui/inventory_ui/inventory_ui.tscn").instantiate()
	add_child(inventory_ui)
	player.hunger = 0.5
	player.fatigue = 0.5
	await inventory_ui._execute_use_item("date_cluster", 1)
	_expect(is_equal_approx(player.hunger, 0.46) and is_equal_approx(player.fatigue, 0.49) and Inventory.items.get("date_cluster") == 1, "Eating a date preserves both its Hunger and Energy effects and consumes one item.")
	player.hunger = 0.0
	player.fatigue = 0.0
	await inventory_ui._execute_use_item("date_cluster", 1)
	_expect(Inventory.items.get("date_cluster") == 1, "Eating with no possible effect does not consume another date.")
	player.hunger = 0.0
	player.fatigue = 0.8
	player.last_sleep_day = -1
	var start: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	_expect(player.sleep(), "Normal sleep succeeds.")
	var after_sleep: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	_expect(after_sleep - start == 420 and is_equal_approx(player.hunger, 0.42) and is_equal_approx(player.fatigue, 0.15), "Fed sleep advances seven hours, grows Hunger and restores the existing Energy amount.")
	_expect(not player.sleep() and TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute == after_sleep and is_equal_approx(player.hunger, 0.42) and is_equal_approx(player.fatigue, 0.15), "A repeated sleep on the same day changes neither time nor conditions.")
	player.last_sleep_day = -1
	player.hunger = 1.0
	player.fatigue = 0.8
	_expect(player.sleep() and is_equal_approx(player.fatigue, 0.6375) and is_equal_approx(player.hunger, 1.0), "Hungry sleep keeps the existing reduced recovery and Hunger cap.")
	inventory_ui.free()
	Inventory.items.assign(original_inventory)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
