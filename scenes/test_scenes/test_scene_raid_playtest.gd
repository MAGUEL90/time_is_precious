extends Node

var failures: int = 0
var content: Node
var state: Node
var ui: CanvasLayer
var debug: CanvasLayer
var player: Player
var wall_spot: Node2D
var wall_map: TileMapLayer

func _ready() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _load_map() -> void:
	content = preload("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	player = content.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	wall_spot = content.get_node("YSortWorld/WallManagementSpot")
	wall_map = content.get_node("YSortWorld/WallStone")
	state = content.get_node("RaidBootstrap").state
	ui = state.get_node("RaidUI")
	debug = content.get_node("TimeDebugOverlay")

func _move_to_wall_spot() -> void:
	player.global_position = wall_spot.global_position + Vector2(0, 15)
	await _settle_physics()
	player._refresh_current_interactable()
	await get_tree().process_frame

func _interact_with_wall_spot() -> void:
	var interact_event := InputEventAction.new()
	interact_event.action = &"interact"
	interact_event.pressed = true
	player._unhandled_input(interact_event)
	await get_tree().process_frame

func _settle_physics() -> void:
	for frame: int in range(5):
		await get_tree().physics_frame

func _wall_atlas_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for cell: Vector2i in wall_map.get_used_cells():
		snapshot[cell] = wall_map.get_cell_atlas_coords(cell)
	return snapshot

func _expect_wall_visual(source_id: int, atlas_snapshot: Dictionary, message: String) -> void:
	var current_cells: Array[Vector2i] = wall_map.get_used_cells()
	_expect(current_cells.size() == atlas_snapshot.size(), "%s (same tile count)" % message)
	for cell: Vector2i in atlas_snapshot:
		_expect(current_cells.has(cell), "%s (cell %s remains)" % [message, cell])
		_expect(wall_map.get_cell_source_id(cell) == source_id, "%s (cell %s source)" % [message, cell])
		_expect(wall_map.get_cell_atlas_coords(cell) == atlas_snapshot[cell], "%s (cell %s atlas)" % [message, cell])

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	_load_map()
	await _settle_physics()
	var wall_atlas: Dictionary = _wall_atlas_snapshot()
	debug.panel.show()
	debug._refresh_controls()
	_expect(debug.raid_light_button.disabled and debug.raid_heavy_button.disabled, "Raid debug controls require a built wall.")
	_expect(not debug.trigger_raid_test(false), "A direct debug request cannot bypass initial construction.")

	# Details stays read-only. Build through the selected nearby spot and the Player action.
	ui.open_details()
	await get_tree().process_frame
	_expect(ui.details_panel.visible and not ui.build_button.visible, "Read-only Details does not offer wall construction.")
	ui.build_button.pressed.emit()
	await get_tree().process_frame
	_expect(state.wall_hp == 0 and state.wall_level == 0, "A forced Details Build signal cannot construct the wall.")
	ui.close_details()
	await _move_to_wall_spot()
	_expect(player.current_interactable == wall_spot, "The wall spot is selected when Player enters its range.")
	await _interact_with_wall_spot()
	_expect(ui.build_button.visible and player.can_move, "E opens management and leaves Player movement enabled.")
	ui.build_button.pressed.emit()
	await get_tree().process_frame
	debug._refresh_controls()
	_expect(state.wall_hp == 50 and state.wall_level == 1, "Initial wall construction uses the real management action.")
	_expect_wall_visual(1, wall_atlas, "Building changes every existing wall cell to the intact tile source while preserving coordinates")
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
	_expect(ui.details_panel.visible and not ui.repair_button.visible, "The real result report stays read-only until Player reaches the wall.")
	await _capture("raid-playtest-survived.png")
	var report: Dictionary = state.get_last_report()
	var next_attack: int = state._attack_at
	await _move_to_wall_spot()
	await _interact_with_wall_spot()
	_expect(ui.repair_button.visible, "Wall management exposes the allowed repair after Player reaches the wall.")
	ui.repair_button.pressed.emit()
	_expect(state.wall_hp == 50 and state._attack_at == next_attack and state.get_last_report() == report, "Repair restores HP without rerolling threats or results.")
	_expect(Inventory.items == inventory_before, "Free fixture repair does not spend personal Inventory.")
	_expect(state.config.attack_min == config_before.attack_min and state.config.attack_max == config_before.attack_max and state.config.raids_enabled == config_before.raids_enabled, "Debug raid overrides do not rewrite live raid balance.")
	debug.raid_heavy_button.pressed.emit()
	state.set_process(false)
	state.advance_attack(20.0)
	var ledger: Node = state
	content.free()
	await _settle_physics()
	_expect(not ui.details_panel.visible, "Leaving the map frees the wall spot and closes management/report details.")
	var home: Node = preload("res://scenes/player_home_interior/player_home_interior.tscn").instantiate()
	add_child(home)
	await get_tree().process_frame
	_expect(ledger.wall_hp == 30 and ledger.phase == "attacking", "An active raid survives going home.")
	ledger.advance_attack(30.0)
	_expect(ledger.wall_hp == 0 and ledger.get_last_report().hits == 10, "The heavy test breaches at fifty seconds, including while away from the map.")
	_expect(ui.details_panel.visible and not ui.build_button.visible, "The breach report is read-only and does not offer Build away from the wall.")
	await _capture("raid-playtest-breached.png")
	home.free()
	await get_tree().process_frame
	_load_map()
	await _settle_physics()
	_expect(state == ledger and state.get_last_report().outcome == "breached", "Map return retains the exact breach report and ledger.")
	_expect(not ui.build_button.visible, "Map return retains no stale wall management authority.")
	_expect_wall_visual(0, wall_atlas, "A breach changes every existing wall cell to the ruined tile source while preserving coordinates")
	await _move_to_wall_spot()
	_expect(player.current_interactable == wall_spot, "Returning to range selects the wall spot for rebuilding.")
	await _interact_with_wall_spot()
	_expect(ui.details_panel.visible and ui.build_button.visible, "E at the wall opens management and offers rebuilding after breach.")
	ui.build_button.pressed.emit()
	await get_tree().process_frame
	_expect(state.wall_hp == 50 and state.wall_level == 1, "Rebuild returns the ruined wall to level 1 without granting an upgrade.")
	_expect_wall_visual(1, wall_atlas, "Rebuilding restores intact tile sources and preserves cell coordinates")
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
