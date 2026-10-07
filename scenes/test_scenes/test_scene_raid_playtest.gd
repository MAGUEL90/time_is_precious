extends Node

var failures: int = 0
var content: Node
var state: Node
var ui: CanvasLayer
var debug: CanvasLayer

func _ready() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _load_map() -> void:
	content = preload("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	content.get_node("YSortWorld/Player").debug_disable_player_needs = true
	state = content.get_node("RaidBootstrap").state
	ui = state.get_node("RaidUI")
	debug = content.get_node("TimeDebugOverlay")

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	_load_map()
	await get_tree().process_frame
	debug.panel.show()
	debug._refresh_controls()
	_expect(debug.raid_light_button.disabled and debug.raid_heavy_button.disabled, "Raid debug controls require a built wall.")
	_expect(not debug.trigger_raid_test(false), "A direct debug request cannot bypass initial construction.")
	ui.open_details()
	ui.build_button.pressed.emit()
	debug._refresh_controls()
	_expect(not debug.raid_light_button.disabled, "Building enables the explicit raid tests.")
	# This isolated fixture enables the free-repair API even if its live balance is pending.
	state.config.instant_repair_enabled = true
	var config_before: Resource = state.config.duplicate(true)
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	debug.raid_light_button.pressed.emit()
	_expect(state.phase == "attacking" and not debug.panel.visible and not ui.details_panel.visible, "Starting the real debug action focuses the live HP bar.")
	_expect(not debug.trigger_raid_test(true), "A second debug click cannot replace an active attack.")
	if OS.get_environment("TIP_RAID_REALTIME_TEST") == "1":
		TimeComponentManager.is_paused = true
		var before_pause: float = state._elapsed
		await get_tree().create_timer(0.2).timeout
		_expect(state._elapsed == before_pause, "Clock pause freezes a real running attack.")
		TimeComponentManager.is_paused = false
		await get_tree().create_timer(5.1).timeout
		state.set_process(false)
		_expect(state._elapsed >= 5.0 and state._elapsed < 10.0, "Real gameplay processing reaches the first five-second hit.")
	else:
		state.set_process(false)
		state.advance_attack(5.0)
	_expect(state.wall_hp == 47 and ui.hp_bar.value == 47, "One live-state hit updates the real main-map HP bar.")
	await _capture("raid-playtest-first-hit.png")
	var elapsed: float = state._elapsed
	debug.set_speed(60)
	debug._process(1.0)
	debug.set_speed(1)
	_expect(state._elapsed == elapsed, "Accelerating world minutes never accelerates real raid seconds.")
	state.advance_attack(55.0)
	_expect(state.phase == "recovery" and state.wall_hp == 14, "The light test survives twelve hits with persistent damage.")
	_expect(ui.details_panel.visible and ui.repair_button.visible, "The real result panel exposes allowed repair after survival.")
	await _capture("raid-playtest-survived.png")
	var report: Dictionary = state.get_last_report()
	var next_attack: int = state._attack_at
	ui.repair_button.pressed.emit()
	_expect(state.wall_hp == 50 and state._attack_at == next_attack and state.get_last_report() == report, "Repair restores HP without rerolling threats or results.")
	_expect(Inventory.items == inventory_before, "Free fixture repair does not spend personal Inventory.")
	_expect(state.config.attack_min == config_before.attack_min and state.config.attack_max == config_before.attack_max and state.config.raids_enabled == config_before.raids_enabled, "Debug raid overrides do not rewrite live raid balance.")
	debug.raid_heavy_button.pressed.emit()
	state.set_process(false)
	state.advance_attack(20.0)
	var ledger: Node = state
	content.free()
	await get_tree().process_frame
	var home: Node = preload("res://scenes/player_home_interior/player_home_interior.tscn").instantiate()
	add_child(home)
	await get_tree().process_frame
	_expect(ledger.wall_hp == 30 and ledger.phase == "attacking", "An active raid survives going home.")
	ledger.advance_attack(30.0)
	_expect(ledger.wall_hp == 0 and ledger.get_last_report().hits == 10, "The heavy test breaches at fifty seconds, including while away from the map.")
	_expect(ui.details_panel.visible and ui.build_button.visible, "A breach opens the report and offers rebuilding.")
	await _capture("raid-playtest-breached.png")
	home.free()
	await get_tree().process_frame
	_load_map()
	await get_tree().process_frame
	_expect(state == ledger and state.get_last_report().outcome == "breached", "Map return retains the exact breach report and ledger.")
	ui.build_button.pressed.emit()
	_expect(state.wall_hp == 50 and state.wall_level == 1, "Rebuild returns the ruined wall to level 1 without granting an upgrade.")
	_expect(ui.repair_requested.get_connections().size() == 1, "Map reload does not duplicate repair callbacks.")
	# Debug reset remains useful when gameplay repair is not enabled.
	state.config.instant_repair_enabled = false
	_expect(debug.trigger_raid_test(false), "A subsequent manual raid can be started after rebuilding.")
	state.set_process(false)
	state.advance_attack(60.0)
	var reset_report: Dictionary = state.get_last_report()
	var reset_schedule: int = state._attack_at
	_expect(not ui.repair_button.visible, "An unapproved gameplay repair action stays hidden.")
	get_tree().paused = true
	_expect(not debug.reset_wall_test(), "Debug reset respects another system's pause.")
	get_tree().paused = false
	debug.raid_reset_button.pressed.emit()
	_expect(state.wall_hp == 50 and not state.config.instant_repair_enabled, "Explicit debug reset restores HP without enabling free gameplay repair.")
	_expect(state.get_last_report() == reset_report and state._attack_at == reset_schedule, "Debug reset preserves raid results and schedule.")
	ui.close_details()
	debug.panel.show()
	debug._refresh_controls()
	var scroll: ScrollContainer = debug.panel.get_child(0)
	scroll.scroll_vertical = 0
	await get_tree().process_frame
	await _capture("raid-playtest-debug.png")
	content.free()
	print("RaidPlaytestTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _capture(file_name: String) -> void:
	var folder: String = OS.get_environment("TIP_RAID_CAPTURE_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(file_name))
