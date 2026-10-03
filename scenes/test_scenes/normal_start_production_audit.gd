extends "res://scenes/test_scenes/mudbrick_player_flow_test.gd"

## Audit actual starting map without granted items, money, or workers.
## Teleport to interaction points and advance clock only to shorten the test.
var content: Node
var sites: Node

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	content = preload("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	player = content.get_node("YSortWorld/Player")
	sites = content.get_node("YSortWorld/Worksites")
	plot = content.get_node("YSortWorld/WorkshopPlot")
	await _settle()
	_expect(Inventory.items.is_empty() and WorkerDatabase.get_all_workers().is_empty(), "Real startup has no personal supplies or hired workers.")
	var board: JobBoard = content.get_node("YSortWorld/InitialWorksites/JobBoard")
	await _interact(board)
	if not is_instance_valid(board.job_board_ui):
		_expect(false, "Board must open.")
		get_tree().quit(1)
		return
	for index: int in range(board.job_board_ui.applicants.size()):
		if board.job_board_ui.applicants[index].profession == WorkerData.Profession.LABORER:
			board.job_board_ui.applicant_list.select(index)
			board.job_board_ui.hire_button.pressed.emit()
			break
	worker = WorkerDatabase.get_worker_data("initial_workshop_laborer")
	board.job_board_ui.close_button.pressed.emit()
	_expect(worker != null, "Normal Job Board hires the construction/production Laborer.")
	for site_id: String in ["WoodSite", "ReedSite", "ClaySiteA"]:
		await _gather(site_id)
	print("AUDIT construction inventory: ", Inventory.items)
	await _interact(plot)
	if not is_instance_valid(plot.menu):
		_expect(false, "Cleaning panel opens.")
		get_tree().quit(1)
		return
	plot.menu._on_worker_assignment_next_requested([worker.worker_id] as Array[String])
	plot.menu.build_button.pressed.emit()
	TimeComponentManager.advance_minutes(180)
	await _settle()
	await _interact(plot)
	plot.menu._on_worker_assignment_next_requested([worker.worker_id] as Array[String])
	plot.menu.build_button.pressed.emit()
	_expect(plot.construction.phase == "building", "Earned materials fund construction.")
	TimeComponentManager.advance_minutes(4320)
	await _settle()
	_expect(plot.construction.phase == "built" and not worker.is_reserved(), "Construction finishes and releases builder.")
	workshop = plot.get_node("BuiltWorkshop")
	player.global_position = workshop.get_node("InteractableComponent").global_position + Vector2(0, 4)
	await _settle()
	await _deposit_all()
	for site_id: String in ["StrawSite", "WaterSite"]:
		await _gather(site_id)
		player.global_position = workshop.get_node("InteractableComponent").global_position + Vector2(0, 4)
		await _settle()
		await _deposit_all()
	print("AUDIT production stock: ", WorkShopStorage.items, " wallet: ", Inventory.items)
	if not await _try_shape():
		get_tree().paused = false
		get_tree().quit(1)
		return
	print("AUDIT held wet: ", WorkShopStorage.get_held_item_quantity("wet_mudbrick"), " wallet: ", Inventory.items)
	await _open_workshop()
	var menu: WorkshopMenuUI = _ui(WorkshopMenuUI)
	await _press(menu.manage_button)
	var storage: WorkshopStorageMenuUI = _ui(WorkshopStorageMenuUI)
	await _press(storage.held_grid.get_child(0))
	var popup: WorkshopFeeConfirmUI = _ui(WorkshopFeeConfirmUI)
	await _capture("normal-start-fee.png")
	await _press(popup.fee_panel.primary_button)
	_expect(Inventory.items.get("shekel", 0) == 0, "Normal start still has zero Shekel.")
	_expect(WorkShopStorage.get_held_item_quantity("wet_mudbrick") > 0 and WorkShopStorage.get_free_item_quantity("wet_mudbrick") == 0, "Payment cannot release wet bricks without Shekel.")
	print("AUDIT payment feedback: ", storage.feedback_label.text)
	await _capture("normal-start-payment-blocked.png")
	print("NormalStartProductionAudit: ", "PASS - EXPECTED SHEKEL BLOCKER" if failures == 0 else "FAIL")
	get_tree().paused = false
	get_tree().quit(0 if failures == 0 else 1)

func _settle() -> void:
	for index: int in range(5):
		await get_tree().physics_frame
	await get_tree().process_frame

func _interact(target: Node2D) -> void:
	var area: Node2D = target.get_node_or_null("InteractableComponent")
	player.global_position = (area.global_position if area != null else target.global_position) + Vector2(0, 8)
	await _settle()
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventAction.new()
	event.action = "interact"
	get_viewport().push_input(event)
	await _frames(3)

func _gather(site_id: String) -> void:
	await _interact(sites.get_node("WorksiteMarkers/" + site_id))
	_expect(sites.inspector.visible, "E opens " + site_id)
	sites.inspector.hourly_button.pressed.emit()
	sites.inspector.next_button.pressed.emit()
	sites.inspector.start_button.pressed.emit()
	await sites.work_finished
	await _settle()

func _deposit_all() -> void:
	var carried: Dictionary = Inventory.items.duplicate()
	# Deposit two production batches; keep surplus in the bag instead of filling storage.
	for id: String in ["straw_bundle", "water_jar"]:
		if carried.has(id):
			carried[id] = mini(int(carried[id]), maxi(0, 6 - WorkShopStorage.get_free_item_quantity(id)))
	var before: Dictionary = WorkShopStorage.items.duplicate()
	await _open_workshop()
	var menu: WorkshopMenuUI = _ui(WorkshopMenuUI)
	await _press(menu.manage_button)
	var storage: WorkshopStorageMenuUI = _ui(WorkshopStorageMenuUI)
	await _press(storage.deposit_button)
	var transfer: ItemTransferUI = _ui(ItemTransferUI)
	for slot: ItemSlot in transfer.grid_container.get_children():
		for index: int in range(int(carried.get(slot._item_id, 0))):
			slot.slot_clicked.emit(slot._item_id, slot._quantity, slot)
	await _press(transfer.confirm_button)
	for id: String in carried:
		_expect(WorkShopStorage.get_free_item_quantity(id) == int(before.get(id, 0)) + int(carried[id]), "Deposit conserves " + id)

func _try_shape() -> bool:
	await _open_workshop()
	var menu: WorkshopMenuUI = _ui(WorkshopMenuUI)
	await _press(menu.assign_button)
	var production: WorkshopProductionUI = _ui(WorkshopProductionUI)
	await _choose_order(production, JOB.job_id)
	var assignment: WorkshopWorkerAssignmentUI = _ui(WorkshopWorkerAssignmentUI)
	await _press(assignment.slot_grid.get_child(0))
	await _press(assignment.worker_list.get_child(0))
	await _press(assignment.next_button)
	var job_ui: WorkshopJobUI = _ui(WorkshopJobUI)
	await _press(job_ui.start_button)
	print("AUDIT start result: ", job_ui.job_started, " reason: ", workshop.get_last_start_job_error())
	await _capture("normal-start-job.png")
	if not job_ui.job_started:
		_expect(false, "Normal production start blocked: " + workshop.get_last_start_job_error())
		return false
	await _press(job_ui.close_button)
	seed(42)
	TimeComponentManager.advance_minutes(JOB.base_duration_minutes)
	await _frames(3)
	var output: int = WorkShopStorage.get_held_item_quantity("wet_mudbrick")
	_expect(output > 0 and output <= 20, "Real hired worker produces output within the existing yield rules; no fixture stat overrides.")
	return WorkShopStorage.get_held_item_quantity("wet_mudbrick") > 0
