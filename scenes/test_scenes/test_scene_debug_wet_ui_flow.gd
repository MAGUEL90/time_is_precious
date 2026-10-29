extends "res://scenes/test_scenes/mudbrick_player_flow_test.gd"

## Real Debug button click followed by the ordinary Assign Work menus.
const CONTENT = preload("res://scenes/content_scene/content_scene.tscn")
var content: Node
var debug: Node

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	content = CONTENT.instantiate()
	add_child(content)
	player = content.get_node("YSortWorld/Player")
	plot = content.get_node("YSortWorld/WorkshopPlot")
	debug = content.get_node("TimeDebugOverlay")
	debug.set_process(false)
	plot.construction.phase = "built" # A completed workshop fixture, not a free output.
	plot._sync_construction()
	workshop = plot.get_node("BuiltWorkshop")
	worker = WorkerData.new()
	worker.worker_id = "debug_wet_ui_fixture"
	worker.display_name = "Wet UI fixture"
	worker.profession = JOB.requirement_profession
	WorkerDatabase.workers_by_id[worker.worker_id] = worker
	player.global_position = workshop.get_node("InteractableComponent").global_position + Vector2(0, 4)
	await _frames(4)
	debug.panel.show()
	var button: Button = debug.wet_inputs_button
	var scroll: ScrollContainer = button.get_parent().get_parent() as ScrollContainer
	scroll.ensure_control_visible(button)
	await _frames(3)
	_expect(button.is_visible_in_tree() and not button.disabled and get_viewport_rect().encloses(button.get_global_rect()), "Wet inputs button is visible and clickable in Debug.")
	await _capture("debug-wet-before.png")
	var scale_to_window: Vector2 = Vector2(get_window().size) / get_viewport_rect().size
	var click: Vector2 = button.get_global_rect().get_center() * scale_to_window
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = click
	press.global_position = click
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(press)
	await _frames(2)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = click
	release.global_position = click
	release.pressed = false
	release.button_mask = 0
	get_viewport().push_input(release)
	await _frames(3)
	for item_id_value: Variant in JOB.inputs:
		var item_id: String = str(item_id_value)
		_expect(WorkShopStorage.get_free_item_quantity(item_id) == int(JOB.inputs[item_id_value]), "Visible Debug click supplies " + item_id)
	_expect(Inventory.items.is_empty() and not WorkShopStorage.items.has("wet_mudbrick") and WorkManager.active_orders.is_empty(), "Debug click grants no personal stock, output or order.")
	await _capture("debug-wet-after.png")
	debug.panel.hide()
	await _open_workshop()
	var menu: WorkshopMenuUI = _ui(WorkshopMenuUI)
	await _press(menu.assign_button)
	var production: WorkshopProductionUI = _ui(WorkshopProductionUI)
	await _choose_order(production, JOB.job_id)
	var assignment: WorkshopWorkerAssignmentUI = _ui(WorkshopWorkerAssignmentUI)
	if assignment._get_selected_worker_ids().is_empty():
		await _press(assignment.slot_grid.get_child(0) as BaseButton)
		await _press(assignment.worker_list.get_child(0) as BaseButton)
	await _press(assignment.next_button)
	var job_ui: WorkshopJobUI = _ui(WorkshopJobUI)
	await _capture("debug-wet-assign-review.png")
	await _press(job_ui.start_button)
	_expect(job_ui.job_started and WorkManager.active_orders.size() == 1 and not worker.physical_approach.arrived,
		"Ordinary Assign Work starts wet_mudbrick with physical arrival still pending.")
	print("DebugWetUIFlowTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().paused = false
	get_tree().quit(0 if failures == 0 else 1)
