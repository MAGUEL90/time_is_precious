extends Node2D

## Test-owned supplies and worker only; production content receives no free items.
@export var run_automatically: bool = true
@export var use_authored_map: bool = false
@export var authored_map_scene: PackedScene = preload("res://scenes/test_scenes/fixtures/content_worksites_map.tscn")
var plot: Node
var completed_cycles: int = 0
const JOB: JobData = preload("res://resources/job_data/mudbrick_make.tres")
const DRYING: ProcessData = preload("res://resources/process_data/drying_mudbrick.tres")

var failures: int = 0
var player: Player
var workshop: WorkShop
var initial_materials: Dictionary[String, int] = {}
var worker: WorkerData


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_prepare_fixture()
	await _frames(3)
	if not run_automatically:
		TimeComponentManager.is_paused = false
		return
	if use_authored_map:
		await _construct_workshop()
	await _open_workshop()
	var menu: WorkshopMenuUI = _ui(WorkshopMenuUI) as WorkshopMenuUI
	_check_hint(menu, ["Manage Storage", "Assign Work"])
	await _capture("mvp-start.png")
	await _deposit_materials(menu)
	await _shape_wet_bricks()
	await _pay_output("wet_mudbrick", "Build & Upgrade")
	await _build_or_upgrade_yard(1)
	await _dry_wet_bricks()
	await _pay_output("sun_dried_mudbrick", "sun-dried")
	await _build_or_upgrade_yard(2)
	_expect(WorkShopStorage.get_free_item_quantity("sun_dried_mudbrick") == 10,
		"The existing level-2 upgrade consumes ten finished bricks as visible progression.")
	# Repeat through the same menus; no stock or process is reset between cycles.
	await _shape_wet_bricks()
	await _pay_output("wet_mudbrick", "Assign Work")
	await _dry_wet_bricks()
	await _pay_output("sun_dried_mudbrick", "sun-dried")
	await _check_withdrawal()
	await _check_edge_hints()
	_expect(Inventory.items.get("clay_lump", 0) == 0,
		"Test inputs were deposited and consumed through the workshop, not granted to outputs.")
	_expect(completed_cycles == 2, "Both production cycles must finish before reporting success.")
	print("MudbrickPlayerFlowTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().paused = false
	get_tree().quit(0 if failures == 0 else 1)


func _prepare_fixture() -> void:
	TimeComponentManager.is_paused = true
	TimeComponentManager.current_day = 0
	TimeComponentManager.current_hour = 10
	TimeComponentManager.current_minute = 0
	TimeComponentManager.current_weather = "clear"
	Inventory.items.clear()
	WorkShopStorage.items.clear()
	WorkShopStorage.output_lots.clear()
	WorkShopStorage.claimable_outputs.clear()
	WorkShopStorage.unpaid_claims_ledger.clear()
	WorkManager.active_orders.clear()
	WorkManager.source_item_store_by_order_id.clear()
	WorkManager.output_item_store_by_order_id.clear()
	WorkManager.service_fee_by_order.clear()
	WorkManager.service_fee_currency_by_order.clear()
	ProcessManager.stations.clear()
	WorkshopFacilityManager.reset_facilities()
	ProcessManager._last_total_minutes = 600
	WorkManager._last_total_minutes = 600
	CitizenManager.citizens_by_id.clear()
	WorkerDatabase.workers_by_id.clear()
	worker = WorkerData.new()
	worker.worker_id = "mvp_fixture_laborer"
	worker.display_name = "MVP Laborer"
	worker.profession = WorkerData.Profession.LABORER
	worker.satisfaction = 0.5
	worker.reliability = 0.9
	WorkerDatabase.workers_by_id[worker.worker_id] = worker
	# Two recipes, plus existing yard requirements. Finished bricks are never seeded.
	for item_id: String in JOB.inputs:
		initial_materials[item_id] = int(JOB.inputs[item_id]) * 2
	for level: int in [1, 2]:
		var requirements: Dictionary = WorkshopFacilityManager.get_facility_upgrade_requirements("drying_yard", level)
		for item_id: String in requirements:
			if item_id != DRYING.output_item_id:
				initial_materials[item_id] = int(initial_materials.get(item_id, 0)) + int(requirements[item_id])
	Inventory.items.assign(initial_materials)
	Inventory.add_item("shekel", 100)
	if use_authored_map:
		var content = authored_map_scene.instantiate()
		content.get_node("YSortWorld/Worksites").seed_playtest_hauler = false
		add_child(content)
		player = content.get_node("YSortWorld/Player")
		plot = content.get_node("YSortWorld/WorkshopPlot")
		player.global_position = plot.get_node("InteractableComponent").global_position + Vector2(0, 4)
	else:
		var backdrop := CanvasLayer.new()
		backdrop.layer = -10
		var floor_rect := ColorRect.new()
		floor_rect.color = Color(0.28, 0.34, 0.30)
		floor_rect.size = get_viewport_rect().size
		floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backdrop.add_child(floor_rect)
		add_child(backdrop)
		player = preload("res://scenes/player/player.tscn").instantiate() as Player
		player.debug_disable_player_needs = true
		player.position = Vector2(200, 145)
		add_child(player)
		workshop = preload("res://scenes/workshop/workshop.tscn").instantiate() as WorkShop
		workshop.position = Vector2(200, 127)
		add_child(workshop)
		add_child(preload("res://scenes/ui/inventory_ui/inventory_ui.tscn").instantiate())
		add_child(preload("res://scenes/ui/work_progress_ui/work_progress_ui.tscn").instantiate())
		add_child(preload("res://scenes/ui/top_hud/top_hud.tscn").instantiate())
	var instructions := CanvasLayer.new()
	var note := Label.new()
	note.position = Vector2(10, 205)
	note.theme = preload("res://resources/ui_gameplay_theme/ui_gameplay_theme.tres")
	note.add_theme_font_size_override("font_size", 6)
	note.text = "MVP test: supplies + Laborer preloaded. E: workshop | J: progress"
	instructions.add_child(note)
	add_child(instructions)
	TimeComponentManager.emit_time_signal()


func _construct_workshop() -> void:
	for id: String in plot.construction.get_requirements():
		Inventory.add_item(id, int(plot.construction.get_requirements()[id]))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventAction.new()
	event.action = "interact"
	get_viewport().push_input(event)
	await _frames(3)
	_expect(is_instance_valid(plot.menu), "Authored plot opens construction requirements through E.")
	plot.menu._on_worker_assignment_next_requested([worker.worker_id] as Array[String])
	plot.menu.build_button.pressed.emit()
	TimeComponentManager.advance_minutes(plot.construction.CLEARING_MINUTES)
	await get_tree().process_frame
	plot.on_player_interact(player)
	plot.menu._on_worker_assignment_next_requested([worker.worker_id] as Array[String])
	await _press(plot.menu.build_button)
	_expect(plot.construction.phase == "building", "Build starts the construction order.")
	TimeComponentManager.advance_minutes(plot.construction.SOLO_MINUTES)
	await _frames(3)
	_expect(plot.construction.phase == "built", "Construction finishes before production starts.")
	_expect(not worker.is_reserved(), "Builder is released for production work.")
	workshop = plot.get_node("BuiltWorkshop") as WorkShop
	player.global_position = workshop.get_node("InteractableComponent").global_position + Vector2(0, 4)
	# The isolated fixture retains deterministic production conditions after three days.
	worker.satisfaction = 0.5
	worker.reliability = 0.9


func _open_workshop() -> void:
	for index: int in range(3):
		await get_tree().physics_frame
	_expect(player.current_interactable == workshop, "The physical Workshop area is reachable by the fixture player.")
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventAction.new()
	event.action = "interact"
	event.pressed = false
	get_viewport().push_input(event)
	await _frames(3)



func _deposit_materials(menu: WorkshopMenuUI) -> void:
	await _press(menu.manage_button)
	var storage_ui: WorkshopStorageMenuUI = _ui(WorkshopStorageMenuUI) as WorkshopStorageMenuUI
	await _press(storage_ui.deposit_button)
	var transfer: ItemTransferUI = _ui(ItemTransferUI) as ItemTransferUI
	for slot: ItemSlot in transfer.grid_container.get_children():
		var needed: int = int(initial_materials.get(slot._item_id, 0))
		for index: int in range(needed):
			slot.slot_clicked.emit(slot._item_id, slot._quantity, slot)
	await _press(transfer.confirm_button)
	_expect(WorkShopStorage.items == initial_materials,
		"The player's selected raw materials reach Workshop Free Stock through Deposit.")
	# Deposit returns to world; the remaining flow starts from the normal menu.


func _shape_wet_bricks() -> void:
	await _open_workshop()
	var menu: WorkshopMenuUI = _ui(WorkshopMenuUI) as WorkshopMenuUI
	await _press(menu.assign_button)
	var production: WorkshopProductionUI = _ui(WorkshopProductionUI) as WorkshopProductionUI
	await _choose_order(production, JOB.job_id)
	var assignment: WorkshopWorkerAssignmentUI = _ui(WorkshopWorkerAssignmentUI) as WorkshopWorkerAssignmentUI
	if assignment._get_selected_worker_ids().is_empty():
		await _press(assignment.slot_grid.get_child(0) as BaseButton)
		await _press(assignment.worker_list.get_child(0) as BaseButton)
	_expect(not assignment.next_button.disabled, "The existing Laborer can be assigned through the UI.")
	await _press(assignment.next_button)
	var job_ui: WorkshopJobUI = _ui(WorkshopJobUI) as WorkshopJobUI
	await _capture("mvp-job-review-before-start.png")
	await _press(job_ui.start_button)
	_expect(job_ui.job_started and worker.is_working(), "Starting Shape creates the actual WorkManager order.")
	await _press(job_ui.close_button)
	if not OS.get_environment("TIP_MVP_CAPTURE_DIR").is_empty():
		var progress = preload("res://scenes/ui/work_progress_ui/work_progress_ui.tscn").instantiate()
		add_child(progress)
		progress.open_panel()
		await _capture("mvp-active-work-progress.png")
		progress.close_panel()
		progress.queue_free()
	# Keep the real worker success rules; a fixed test RNG makes the two runs repeatable.
	seed(42)
	TimeComponentManager.advance_minutes(JOB.base_duration_minutes)
	await _frames(3)
	_expect(WorkShopStorage.get_held_item_quantity("wet_mudbrick") == 20,
		"The real job finishes with twenty Held wet bricks for this deterministic fixture.")
	_expect(WorkShopStorage.get_free_item_quantity("wet_mudbrick") == 0,
		"Shaping output cannot be processed before its existing fee is paid.")


func _pay_output(item_id: String, expected_next: String) -> void:
	await _open_workshop()
	var menu: WorkshopMenuUI = _ui(WorkshopMenuUI) as WorkshopMenuUI
	_check_hint(menu, ["Held Output", "fee"])
	await _capture("mvp-held-%s.png" % item_id)
	await _press(menu.manage_button)
	var storage_ui: WorkshopStorageMenuUI = _ui(WorkshopStorageMenuUI) as WorkshopStorageMenuUI
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var storage_before: Dictionary = WorkShopStorage.get_storage_state().duplicate(true)
	var lots: Array = storage_ui.storage_state.get("held_lots", [])
	_expect(not lots.is_empty(), "The storage UI exposes the completed output lot.")
	await _press(storage_ui.held_grid.get_child(0) as BaseButton)
	var popup: WorkshopFeeConfirmUI = _ui(WorkshopFeeConfirmUI) as WorkshopFeeConfirmUI
	await _capture("mvp-fee-confirmation.png")
	await _press(popup.fee_panel.secondary_button)
	_expect(Inventory.items == inventory_before and WorkShopStorage.get_storage_state() == storage_before,
		"Cancelling a fee prompt changes neither currency nor output ownership.")
	await _press(storage_ui.held_grid.get_child(0) as BaseButton)
	popup = _ui(WorkshopFeeConfirmUI) as WorkshopFeeConfirmUI
	await _press(popup.fee_panel.primary_button)
	_expect(WorkShopStorage.get_held_item_quantity(item_id) == 0,
		"Paying a visible Held lot releases it using the existing payment controller.")
	_check_hint(storage_ui, [expected_next])
	await _capture("mvp-free-%s.png" % item_id)
	await _press(storage_ui.back_button)
	menu = _ui(WorkshopMenuUI) as WorkshopMenuUI
	await _press(menu.close_button)


func _build_or_upgrade_yard(target_level: int) -> void:
	await _open_workshop()
	var menu: WorkshopMenuUI = _ui(WorkshopMenuUI) as WorkshopMenuUI
	await _press(menu.build_button)
	var build: WorkshopBuildUI = _ui(WorkshopBuildUI) as WorkshopBuildUI
	await _press(build.facility_list.get_child(0) as BaseButton)
	_expect(not build.build_button.disabled, "Existing Free Stock requirements make the yard action available.")
	await _press(build.build_button)
	await _press(build.confirm_panel.secondary_button)
	_expect(WorkshopFacilityManager.get_facility_level("drying_yard") == target_level - 1,
		"Cancelling construction leaves its previous level intact.")
	await _press(build.build_button)
	await _press(build.confirm_panel.primary_button)
	_expect(WorkshopFacilityManager.get_facility_level("drying_yard") == target_level,
		"Confirming consumes the existing requirements and visibly advances the yard.")
	await _capture("mvp-yard-level-%d.png" % target_level)
	await _press(build.close_button)


func _dry_wet_bricks() -> void:
	await _open_workshop()
	var menu: WorkshopMenuUI = _ui(WorkshopMenuUI) as WorkshopMenuUI
	_check_hint(menu, ["Assign Work"])
	await _press(menu.assign_button)
	var production: WorkshopProductionUI = _ui(WorkshopProductionUI) as WorkshopProductionUI
	await _choose_order(production, DRYING.process_id)
	_expect(production.awaiting_process_confirmation,
		"Drying opens the existing explicit Start confirmation.")
	await _capture("mvp-process-confirmation.png")
	var before: Dictionary = WorkShopStorage.items.duplicate(true)
	await _press(production.process_confirm_panel.secondary_button)
	_expect(WorkShopStorage.items == before and ProcessManager.get_active_progress_entries().is_empty(),
		"Cancel Drying preserves all inputs and starts no process.")
	await _press(production.next_button)
	await _press(production.process_confirm_panel.primary_button)
	_expect(WorkShopStorage.get_free_item_quantity("wet_mudbrick") == 0
		and not ProcessManager.get_active_progress_entries().is_empty(),
		"Confirmed Drying moves its actual input from Free Stock into the process.")
	await _open_workshop()
	menu = _ui(WorkshopMenuUI) as WorkshopMenuUI
	_check_hint(menu, ["progress"])
	await _capture("mvp-drying.png")
	await _press(menu.close_button)
	TimeComponentManager.advance_minutes(DRYING.base_duration_minutes)
	await _frames(3)
	_expect(WorkShopStorage.get_held_item_quantity("sun_dried_mudbrick") == 20,
		"The process delivers finished bricks as Held Output with its existing rent.")
	_expect(ProcessManager.get_active_progress_entries().is_empty(), "The finished process frees its slot.")
	completed_cycles += 1


func _check_withdrawal() -> void:
	await _open_workshop()
	var menu: WorkshopMenuUI = _ui(WorkshopMenuUI) as WorkshopMenuUI
	await _press(menu.manage_button)
	var storage_ui: WorkshopStorageMenuUI = _ui(WorkshopStorageMenuUI) as WorkshopStorageMenuUI
	var before: int = WorkShopStorage.get_free_item_quantity("sun_dried_mudbrick")
	var slot: ItemSlot = storage_ui.free_slots_by_item_id["sun_dried_mudbrick"]
	await _press(slot)
	await _press(storage_ui.withdraw_button)
	_expect(Inventory.items.get("sun_dried_mudbrick", 0) == 1
		and WorkShopStorage.get_free_item_quantity("sun_dried_mudbrick") == before - 1,
		"The existing personal workshop stock supports withdrawing a finished brick exactly once.")
	await _press(storage_ui.back_button)
	menu = _ui(WorkshopMenuUI) as WorkshopMenuUI
	await _press(menu.close_button)


func _check_edge_hints() -> void:
	var menu: WorkshopMenuUI = preload("res://scenes/ui/workshop_menu_ui/workshop_menu_ui.tscn").instantiate()
	add_child(menu)
	var stock_before: Dictionary = WorkShopStorage.get_storage_state().duplicate(true)
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	menu.open_menu({"pending_count": 999999999, "free_items": {}, "held_lots": [],
		"held_fee_totals": {"shekel": 999999999}})
	await _frames(3)
	_check_hint(menu, ["Pending Delivery"])
	await _capture("mvp-pending-long.png")
	# Synthetic display state only; the real stock is untouched.
	menu.open_menu({"free_items": {"wet_mudbrick": 1}, "held_lots": [], "pending_count": 0})
	await _frames(3)
	_check_hint(menu, ["batch"])
	_expect(WorkShopStorage.get_storage_state() == stock_before and Inventory.items == inventory_before,
		"Opening and refreshing guidance never consumes, pays, reserves or transfers goods.")
	await _press(menu.close_button)


func _choose_order(production: WorkshopProductionUI, order_id: String) -> void:
	for child: Node in production.work_order_grid.get_children():
		var card: WorkOrderCard = child as WorkOrderCard
		if card != null and card.work_order_id == order_id:
			var capture_key: String = order_id.replace("/", "_")
			await _capture("mvp-production-%s-list.png" % capture_key)
			var info_button: BaseButton = card.get_node_or_null("InfoButton") as BaseButton
			if info_button != null and info_button.is_visible_in_tree():
				await _press(info_button)
				await _capture("mvp-production-%s-details.png" % capture_key)
			await _press(card)
			await _capture("mvp-production-%s-selected.png" % capture_key)
			await _press(production.next_button)
			return
	_expect(false, "Missing production card: " + order_id)


func _check_hint(menu: CanvasLayer, expected: Array[String]) -> void:
	var label: Label = menu.find_child("NextStepLabel", true, false) as Label
	_expect(label != null and label.is_visible_in_tree(), "Workshop displays its next-step guidance.")
	if label == null:
		return
	for part: String in expected:
		_expect(label.text.to_lower().contains(part.to_lower()), "Guidance includes: " + part)
	var window: Control = menu.find_child("Window", true, false) as Control
	if window == null:
		window = menu.find_child("TextureWindow", true, false) as Control
	_expect(get_viewport_rect().encloses(window.get_global_rect()),
		"The complete menu remains inside the 400x225 logical viewport.")
	_expect(window.get_global_rect().encloses(label.get_global_rect())
		and label.get_visible_line_count() == label.get_line_count(),
		"The next step is fully readable without clipped lines.")
	for button_name: String in ["ManageButton", "AssignButton", "BuildButton", "DepositButton", "PayAllButton", "BackButton"]:
		var action: Control = window.find_child(button_name, true, false) as Control
		if action != null and action.is_visible_in_tree():
			_expect(window.get_global_rect().encloses(action.get_global_rect()),
				"Action stays inside the parchment panel: " + button_name)


func _ui(script_type: Script) -> Node:
	for child: Node in get_tree().current_scene.get_children():
		if child.get_script() == script_type and not child.is_queued_for_deletion():
			return child
	_expect(false, "The expected UI did not open: " + script_type.resource_path)
	get_tree().quit(1)
	return null


func _press(button: BaseButton) -> void:
	_expect(is_instance_valid(button) and not button.disabled and button.is_visible_in_tree(),
		"The next action is visible and enabled.")
	if is_instance_valid(button) and not button.disabled:
		button.pressed.emit()
	await _frames(3)


func _frames(count: int) -> void:
	for index: int in range(count):
		await get_tree().process_frame


func _capture(filename: String) -> void:
	var directory: String = OS.get_environment("TIP_MVP_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_expect(get_viewport().get_texture().get_image().save_png(directory.path_join(filename)) == OK,
		"Saved rendered UI evidence: " + filename)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
