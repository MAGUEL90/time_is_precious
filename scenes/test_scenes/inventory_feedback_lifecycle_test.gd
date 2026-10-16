extends Node
var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	TimeComponentManager.set_process(false)
	var map = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(map)
	await get_tree().process_frame
	var ui = map.get_node("InventoryUI")
	ui.open_inventory()
	ui._show_inventory_feedback("First")
	var first: Tween = ui.action_feedback_tween
	ui._show_inventory_feedback("Second")
	check(not first.is_valid(), "Replacement cancels previous feedback")
	check(ui.action_feedback_label.text == "Second", "Newest feedback visible")
	var deadline: int = Time.get_ticks_msec() + 5000
	while ui.action_feedback_label.modulate.a > 0.0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(is_zero_approx(ui.action_feedback_label.modulate.a), "Feedback expires even while inventory pauses game")
	ui._show_inventory_feedback("Closing")
	var closing: Tween = ui.action_feedback_tween
	ui._clear_inventory_feedback()
	check(not closing.is_valid(), "Clearing feedback cancels pending hide")
	ui.close_inventory()
	ui._show_inventory_feedback("Scene exit")
	var leaving: Tween = ui.action_feedback_tween
	map.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not leaving.is_valid(), "Scene exit destroys pending feedback")
	print("InventoryFeedbackLifecycleTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)
