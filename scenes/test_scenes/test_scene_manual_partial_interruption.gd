extends Node

const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
@export var kind: String = "house"
@export var critical: bool = false
var failures: int = 0
var plot: Node
var player: Player
var start: int = -1
var closed: bool = false
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
func _expect(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
		push_error(text)
func _now() -> int:
	return TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
func _close_after_five(_day: int, _hour: int, _minute: int, _weather: String) -> void:
	if not critical and not closed and start >= 0 and _now() == start + 5:
		closed = true
		plot.close_menu()
func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	TimeComponentManager.current_day = 1
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	TimeComponentManager.emit_time_signal()
	var content: Node = CONTENT.instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	for frame: int in range(4):
		await get_tree().process_frame
	player = content.get_node("YSortWorld/Player")
	plot = content.get_node("YSortWorld/WorkshopPlot" if kind == "workshop" else "YSortWorld/CitizenHousePlot")
	player.debug_disable_player_needs = false
	player.debug_disable_fatigue = false
	player.hunger = 0.1
	player.fatigue = player.fatigue_critical_threshold - player.fatigue_increase_per_min * 4.5 if critical else 0.1
	if kind == "house":
		plot.construction.phase = "empty"
		plot.construction.changed.emit()
		Inventory.add_bulk_item(plot.construction.get_requirements())
	player.global_position = plot.get_node("InteractableComponent").global_position + Vector2(0, 12 if kind == "workshop" else 4)
	for frame: int in range(6):
		await get_tree().physics_frame
	plot.on_player_interact(player)
	if is_instance_valid(plot.get("keeper_dialogue")):
		plot.keeper_dialogue.continued.emit()
	_expect(is_instance_valid(plot.menu), "Real manual menu opens")
	if not is_instance_valid(plot.menu):
		_finish()
		return
	var before_items: Dictionary = Inventory.items.duplicate(true)
	var hunger: float = player.hunger
	var fatigue: float = player.fatigue
	var expected_remaining: int = (2880 if kind == "house" else 180) - 5
	TimeComponentManager.time_changed.connect(_close_after_five)
	plot.menu.player_button.button_pressed = true
	start = _now()
	plot.menu.build_button.pressed.emit()
	var deadline: int = Time.get_ticks_msec() + 15000
	while (plot._manual_clearing or is_instance_valid(plot.menu) or TimeComponentManager.is_dispatching_time()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(_now() == start + 5 and plot.construction._remaining_work_units() == expected_remaining,
		"Exactly five completed minutes are retained after interruption")
	_expect(not plot._manual_clearing and not plot.construction.is_player_work_active() and not is_instance_valid(plot.menu) and not TimeComponentManager.is_dispatching_time() and not TimeComponentManager.is_staged_advance_active() and not get_tree().paused,
		"Full manual action, modal and clock cleanup completes")
	_expect(is_equal_approx(player.hunger, hunger + 5 * player.hunger_increase_per_min) and is_equal_approx(player.fatigue, fatigue + 5 * player.fatigue_increase_per_min),
		"The five elapsed minutes charge normal player needs once")
	if kind == "house":
		for item: String in plot.construction.get_requirements():
			_expect(int(before_items.get(item, 0)) - int(Inventory.items.get(item, 0)) == int(plot.construction.get_requirements()[item]), "House material cost is charged once")
	else:
		_expect(Inventory.items == before_items, "Clearing consumes no materials")
	if critical:
		var nightmare: Node = content.get_node("YSortWorld/NightmareWorld")
		deadline = Time.get_ticks_msec() + 15000
		while (not nightmare.is_active or player.is_collapsing or SceneTransition.is_transitioning) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		_expect(nightmare.is_active and not player.is_collapsing and not SceneTransition.is_transitioning and player.can_move,
			"Genuine critical condition finishes the existing Nightmare entry without stranding controls")
	else:
		_expect(closed and player.can_move, "Closing after five minutes restores player control")
	print("MANUAL_PARTIAL_RESULT ", JSON.stringify({"kind":kind,"critical":critical,"elapsed":_now()-start,"remaining":plot.construction._remaining_work_units(),"checks":failures}))
	_finish()
func _finish() -> void:
	print("ManualPartialInterruptionTest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
