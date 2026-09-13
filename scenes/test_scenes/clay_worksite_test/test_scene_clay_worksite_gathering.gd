extends Node

var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var fixture = load("res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn").instantiate()
	get_tree().root.add_child(fixture)
	await get_tree().process_frame
	get_tree().paused = true
	fixture.sites[&"ClaySiteA"].toggle_participant("player")
	fixture.sites[&"ClaySiteB"].toggle_participant("player")
	var player: Player = fixture.player
	var site = fixture.sites[&"ClaySiteA"]
	var other = fixture.sites[&"ClaySiteB"]
	Inventory.items.clear()
	Inventory.max_load = 100.0
	var test_scene: Node = get_tree().current_scene
	get_tree().current_scene = fixture
	var original_position: Vector2 = player.global_position
	fixture._prepare_nightmare_test()
	_expect(is_equal_approx(player.fatigue, 0.89) and player.global_position == fixture.get_node("WorksiteMarkers/ClaySiteA").global_position, "Nightmare debug preset starts near collapse at the worksite.")
	player.global_position = original_position
	fixture.prepare_overflow_test = true # Explicitly enable this regression's inventory preset.
	fixture._prepare_overflow_test()
	get_tree().current_scene = test_scene
	_expect(Inventory.items.get("clay_lump", 0) == 48 and Inventory.get_remaining_capacity() == 4.0, "Overflow preset leaves room for two clay.")
	_expect(site.stock == 72 and site.WORKER_CAPACITY == 2, "Small worksite test configuration.")
	var exp_before: int = player.current_experience
	for rejected: int in [60, 65, 720]:
		var before: int = _now()
		_expect(not site.preview(rejected, player).reason.is_empty(), "Reject removed duration.")
		_expect(site.execute(rejected, player, fixture).minutes == 0 and _now() == before, "Rejected duration has no cost.")
	var before: int = _now()
	var result: Dictionary = site.execute(180, player, fixture, fixture._drop_output)
	_expect(result.units == 18 and result.minutes == 180 and _now() - before == 180, "Three-hour output and clock.")
	_expect(result.to_bag == 2 and result.to_ground == 16, "Three-hour overflow splits two/sixteen.")
	var drop: PickUpItem = fixture.get_node("GroundOutput").get_child(0)
	_expect(drop.quantity == 16 and site.stock == 54 and other.stock == 72, "Exact stack and separate stocks.")
	_expect(is_equal_approx(player.fatigue, 0.59) and is_equal_approx(player.hunger, 0.18), "Three-hour normal condition costs.")
	drop.on_player_interact(player)
	_expect(not drop.is_collecting, "Full bag preserves stack.")
	Inventory.max_load = 1000.0
	var clay_before: int = Inventory.items.get("clay_lump", 0)
	drop.on_player_interact(player)
	drop.on_player_interact(player)
	_expect(Inventory.items.get("clay_lump", 0) == clay_before + 16, "Stack collects once after freeing space.")
	player.fatigue = 0.0
	player.hunger = 0.0
	player.focus = 1.0
	before = _now()
	result = other.execute(540, player, fixture, fixture._drop_output)
	_expect(result.units == 54 and _now() - before == 540 and not result.interrupted, "Player completes nine hours without worker requirement.")
	_expect(is_equal_approx(player.fatigue, 0.27) and is_equal_approx(player.hunger, 0.54), "Nine-hour condition costs.")
	get_tree().paused = false
	await get_tree().create_timer(0.5).timeout
	player.global_position = fixture.get_node("WorksiteMarkers/ClaySiteA").global_position
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	_expect(fixture.inspector.visible, "Panel opens.")
	fixture.inspector.hourly_button.pressed.emit()
	fixture.inspector.next_button.pressed.emit() # Next confirms setup only.
	before = _now()
	fixture.inspector.start_button.pressed.emit()
	fixture.inspector.start_button.pressed.emit()
	await get_tree().create_timer(0.3, true).timeout
	while fixture._working:
		if fixture.get_node("WorkTransition/Blackout").modulate.a < 0.999:
			_expect(not fixture.inspector.window.is_visible_in_tree(), "No panel flash on return fade.")
		await get_tree().process_frame
	_expect(_now() - before == 180 and fixture.last_work_result.units == 18, "Default UI starts three hours exactly once.")
	_expect(player.can_move and not get_tree().paused and not fixture.inspector.visible, "Completion releases modal.")
	get_tree().paused = true
	site.stock = 5
	result = site.execute(360, player, fixture, fixture._drop_output)
	_expect(result.units == 5 and result.minutes == 50 and site.stock == 0, "Stock still caps work.")
	other.stock = 72
	player.fatigue = 0.88775
	player.hunger = 0.0
	player.focus = 1.0
	result = other.execute(540, player, fixture, fixture._drop_output)
	_expect(player.is_collapsing and result.minutes == 25 and result.units == 2, "Long selection still stops on actual collapse.")
	_expect(player.current_experience == exp_before, "No EXP tuning.")
	fixture.queue_free()
	await get_tree().process_frame
	get_tree().paused = false
	print("ClayWorksiteGatheringTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)

func _now() -> int:
	return (TimeComponentManager.current_day * 24 + TimeComponentManager.current_hour) * 60 + TimeComponentManager.current_minute

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
