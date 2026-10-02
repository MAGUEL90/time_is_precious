extends Node

var failures: int = 0
var captures: String = ""

func _ready() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = action
	get_viewport().push_input(event)
	await get_tree().process_frame

func _capture(suffix: String) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(captures.path_join("construction-" + suffix + ".png"))

func _assignment_worker_button(assignment: Node, worker_id: String) -> Button:
	var worker_list: GridContainer = assignment.get_node(
		"Root/Center/TextureWindow/Margin/MainVBox/WorkerSelectionPage/WorkerScroll/WorkerList"
	)
	for child: Node in worker_list.get_children():
		if child is Button and str(child.get_meta("worker_id", "")) == worker_id:
			return child as Button
	return null

func _assign_worker_from_slot(
	assignment: Node,
	worker_id: String,
	slot_index: int
) -> void:
	var slot_grid: GridContainer = assignment.get_node(
		"Root/Center/TextureWindow/Margin/MainVBox/OverviewPage/SlotCenter/SlotGrid"
	)
	if slot_index < 0 or slot_index >= slot_grid.get_child_count():
		_expect(false, "Assignment UI has an empty slot at index %d (found %d)." % [
			slot_index,
			slot_grid.get_child_count()
		])
		return
	var slot_button: Button = slot_grid.get_child(slot_index) as Button
	if slot_button == null:
		_expect(false, "Assignment UI slot %d is a button." % slot_index)
		return
	slot_button.pressed.emit()
	await get_tree().process_frame
	var worker_button: Button = _assignment_worker_button(assignment, worker_id)
	_expect(worker_button != null, "Assignment UI lists the requested worker.")
	if worker_button == null or worker_button.disabled:
		_expect(false, "The requested worker must be available to select.")
		return
	worker_button.pressed.emit()
	await get_tree().process_frame

func _run() -> void:
	captures = OS.get_environment("TIP_PLOT_CAPTURE_DIR")
	TimeComponentManager.is_paused = true
	var content = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	var plot = content.get_node("YSortWorld/WorkshopPlot")
	var player: Player = content.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	var state: Node = plot.construction
	var ids: Array[String] = []
	for i in range(3):
		var worker := WorkerData.new()
		worker.worker_id = "construction_ui_%d" % i
		worker.display_name = "Builder %d" % (i + 1)
		WorkerDatabase.workers_by_id[worker.worker_id] = worker
		ids.append(worker.worker_id)
	var busy_worker := WorkerData.new()
	busy_worker.worker_id = "construction_ui_busy"
	busy_worker.display_name = "Busy Builder"
	busy_worker.current_work_status = WorkerData.WorkStatus.RESTING
	WorkerDatabase.workers_by_id[busy_worker.worker_id] = busy_worker
	for id: String in state.get_requirements():
		Inventory.add_item(id, int(state.get_requirements()[id]))
	player.global_position = plot.get_node("InteractableComponent").global_position + Vector2(0, 4)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	await _press("interact")
	_expect(is_instance_valid(plot.menu), "Construction UI opens through E.")
	if not is_instance_valid(plot.menu):
		_finish(content, state, ids)
		return
	plot.menu.assign_workers_button.pressed.emit()
	await get_tree().process_frame
	var clearing_assignment = plot.menu._worker_assignment_menu
	_expect(clearing_assignment.max_worker_slots == 1, "Clearing allows exactly one worker slot.")
	await _assign_worker_from_slot(clearing_assignment, ids[0], 0)
	clearing_assignment.get_node("Root/Center/TextureWindow/Margin/MainVBox/OverviewPage/Footer/BackButton").pressed.emit()
	await get_tree().process_frame
	plot.menu.build_button.pressed.emit()
	_expect(state.phase == "clearing" and player.can_move and not get_tree().paused, "Worker clearing frees player movement.")
	TimeComponentManager.advance_minutes(state.CLEARING_MINUTES)
	await _press("interact")
	var build: Button = plot.menu.find_child("BuildButton", true, false)
	var assign_workers: Button = plot.menu.find_child("AssignWorkersButton", true, false)
	_expect(plot.menu.find_child("DebugBagButton", true, false) == null, "Construction UI contains no debug bag button.")
	_expect(build.disabled, "Build requires a selected team even with materials.")
	_expect(assign_workers != null, "Builder team opens the shared worker assignment flow.")
	assign_workers.pressed.emit()
	await get_tree().process_frame
	var assignment: Node = plot.menu.get("_worker_assignment_menu") as Node
	_expect(assignment != null and get_tree().paused, "Worker assignment opens above the paused construction panel.")
	if assignment == null:
		_finish(content, state, ids)
		return
	var slot_grid: GridContainer = assignment.get_node(
		"Root/Center/TextureWindow/Margin/MainVBox/OverviewPage/SlotCenter/SlotGrid"
	)
	var first_slot: Button = slot_grid.get_child(0) as Button
	first_slot.pressed.emit()
	await get_tree().process_frame
	var busy_button: Button = _assignment_worker_button(assignment, "construction_ui_busy")
	_expect(busy_button != null and busy_button.disabled, "Construction-ineligible workers stay disabled in the shared selector.")
	var first_worker: Button = _assignment_worker_button(assignment, ids[0])
	_expect(first_worker != null and not first_worker.disabled, "An available construction worker remains selectable.")
	if first_worker != null and not first_worker.disabled:
		first_worker.pressed.emit()
		await get_tree().process_frame
	var back: Button = assignment.get_node(
		"Root/Center/TextureWindow/Margin/MainVBox/OverviewPage/Footer/BackButton"
	)
	back.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(is_instance_valid(plot.menu) and get_tree().paused, "Returning from worker assignment keeps the construction panel open and paused.")
	_expect((plot.menu.get("_selected_worker_ids") as Array).size() == 1, "Worker choices persist when returning to construction.")
	assign_workers.pressed.emit()
	await get_tree().process_frame
	assignment = plot.menu.get("_worker_assignment_menu") as Node
	_expect(assignment != null, "Builder assignment reopens after returning to construction.")
	if assignment == null:
		_finish(content, state, ids)
		return
	await _press("ui_cancel")
	await get_tree().process_frame
	_expect(
		is_instance_valid(plot.menu)
		and not is_instance_valid(plot.menu.get("_worker_assignment_menu"))
		and get_tree().paused,
		"Escape closes only worker assignment and keeps construction open."
	)
	assign_workers.pressed.emit()
	await get_tree().process_frame
	assignment = plot.menu.get("_worker_assignment_menu") as Node
	_expect(assignment != null, "Builder assignment can be reopened with its previous selection.")
	if assignment == null:
		_finish(content, state, ids)
		return
	await _assign_worker_from_slot(assignment, ids[1], 1)
	await _assign_worker_from_slot(assignment, ids[2], 2)
	var next: Button = assignment.get_node(
		"Root/Center/TextureWindow/Margin/MainVBox/OverviewPage/Footer/NextButton"
	)
	next.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not build.disabled, "Selected idle builders and materials enable Build.")
	await get_tree().process_frame
	await _capture("ready")
	if build.disabled:
		_finish(content, state, ids)
		return
	build.pressed.emit()
	await get_tree().process_frame
	_expect(state.phase == "building", "Build button starts construction.")
	_expect(state.worker_ids.size() == 3 and state.completes_at - state.started_at == 1440, "Three selected builders take one game day.")
	_expect(not get_tree().paused and not is_instance_valid(plot.menu), "Successful Build closes the panel and resumes world simulation.")
	await _press("interact")
	_expect(is_instance_valid(plot.menu), "Building plot exposes its progress panel.")
	await _capture("progress")
	await _press("ui_cancel")
	var finish: int = state.completes_at
	TimeComponentManager.current_day = finish / 1440
	TimeComponentManager.current_hour = (finish % 1440) / 60
	TimeComponentManager.current_minute = finish % 60
	TimeComponentManager.emit_time_signal()
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect(state.phase == "built" and plot.has_node("BuiltWorkshop"), "Completion instantiates the existing workshop.")
	_expect(plot.get_node("Plot").texture.resource_path.ends_with("plot_level_1.png") and not plot.get_node("ToBeClean").visible, "Completed workshop uses the level 1 artwork without debris.")
	_expect(plot.get_node("TableResources").get_child_count() == 2, "Completed workshop shows material props on the table.")
	_expect(plot.get_node("TableResources").get_child(0).texture == ItemDatabase.get_item_data("clay_lump").icon, "Mudbrick work is identified by clay from its recipe.")
	_expect(plot.get_node("BuiltWorkshop/InteractableComponent").global_position == plot.get_node("InteractableComponent").global_position, "Built workshop interaction remains anchored to Board.")
	_expect(plot.get_node("BuiltWorkshop/InteractableLabelComponent").global_position == plot.get_node("InteractableLabelComponent").global_position, "E prompt stays in the same Board position as hand and hammer.")
	await get_tree().create_timer(0.15).timeout
	await _capture("level-1")
	player.global_position = plot.get_node("InteractableComponent").global_position + Vector2(0, 4)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	await _press("interact")
	_expect(player.claim_menu_is_open, "E enters the real Workshop menu after construction.")
	_expect(Inventory.max_load == 100.0, "Gameplay menus preserve normal bag capacity.")
	await _capture("built")
	_finish(content, state, ids)

func _finish(content: Node, state: Node, ids: Array[String]) -> void:
	get_tree().paused = false
	content.free()
	state.free()
	for id: String in ids:
		WorkerDatabase.workers_by_id.erase(id)
	WorkerDatabase.workers_by_id.erase("construction_ui_busy")
	print("WorkshopConstructionUITest: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
