extends "res://scenes/test_scenes/mudbrick_player_flow_test.gd"

## Exercises the actual debug buttons, hired worker, and current map production UI.
var content: Node
var debug: Node
@export var include_hauling: bool = false

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	content = preload("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	player = content.get_node("YSortWorld/Player")
	plot = content.get_node("YSortWorld/WorkshopPlot")
	debug = content.get_node("TimeDebugOverlay")
	debug.set_process(false)
	await _settle()
	_expect(Inventory.items.is_empty(), "Opening the map never grants debug supplies.")
	var hud = content.get_node("BottomHUD")
	_expect(hud.shekel_label.text == "0", "Shekel HUD starts with the actual empty balance.")
	debug.panel.show()
	await _frames(4)
	await _capture("debug-production-controls.png")
	_expect(get_viewport_rect().encloses(debug.panel.get_global_rect()), "Expanded Debug panel fits the logical viewport.")
	var capacity: float = Inventory.max_load
	Inventory.max_load = 1.0
	_expect(not debug.give_production_materials() and Inventory.items.is_empty(), "Production kit fails atomically in a full bag.")
	Inventory.max_load = capacity
	debug.inventory_capacity_button.set_pressed(true)
	_expect(Inventory.max_load == 500.0, "Inventory debug toggle raises personal capacity to 500.")
	_expect(Inventory.try_add_item("wood_log", 166), "Expanded bag accepts 498 weight through the existing inventory API.")
	_expect(not Inventory.try_add_item("wood_log", 1), "Expanded bag still enforces its 500 limit.")
	var held_items: Dictionary = Inventory.items.duplicate()
	_expect(not debug.set_large_inventory(false) and Inventory.items == held_items and Inventory.max_load == 500.0,
		"Overweight bag refuses shrinking without discarding items.")
	var replacement = preload("res://scenes/debug/time_debug_overlay.gd").new()
	add_child(replacement)
	_expect(replacement.inventory_capacity_button.button_pressed, "Recreated debug panel reflects the runtime capacity override.")
	replacement.free()
	Inventory.remove_item("wood_log", 166)
	_expect(debug.set_large_inventory(false) and Inventory.max_load == capacity, "Unloaded bag restores its original capacity.")
	var board: JobBoard = content.get_node("YSortWorld/InitialWorksites/JobBoard")
	await _interact(board)
	for index: int in range(board.job_board_ui.applicants.size()):
		if board.job_board_ui.applicants[index].profession == WorkerData.Profession.LABORER:
			board.job_board_ui.applicant_list.select(index)
			board.job_board_ui.hire_button.pressed.emit()
			break
	worker = WorkerDatabase.get_worker_data("initial_workshop_laborer")
	if include_hauling:
		board.job_board_ui.applicant_list.select(0)
		board.job_board_ui.hire_button.pressed.emit()
	board.job_board_ui.close_button.pressed.emit()
	_expect(worker != null, "The real Job Board supplies the builder, not a fixture worker.")
	if include_hauling:
		await _haul_before_building()
	debug.set_worker_guard(true)
	debug.set_player_guard(true)
	get_tree().paused = true
	var supply_time: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	debug.shekel_button.pressed.emit()
	debug.shekel_button.pressed.emit()
	_expect(Inventory.items.get("shekel", 0) == 100, "Shekel refill tops up rather than stacking.")
	_expect(hud.shekel_label.text == "100", "Shekel HUD refreshes even while a menu pauses the world.")
	_expect(TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute == supply_time, "Supplies work in a paused menu without advancing time.")
	get_tree().paused = false
	debug.materials_button.pressed.emit()
	debug.panel.hide()
	await _interact(plot)
	plot.menu._on_worker_assignment_next_requested([worker.worker_id] as Array[String])
	plot.menu.build_button.pressed.emit()
	debug.step_minutes(180)
	await _settle()
	_expect(plot.construction.phase == "empty", "Debug +3h completes normal worker cleaning.")
	await _interact(plot)
	plot.menu._on_worker_assignment_next_requested([worker.worker_id] as Array[String])
	plot.menu.build_button.pressed.emit()
	debug.step_minutes(4320)
	await _settle()
	_expect(plot.construction.phase == "built" and not worker.is_reserved(), "Debug time completes construction and releases the hired worker.")
	_expect(is_equal_approx(worker.get_resolved_satisfaction(), 0.5) and is_equal_approx(worker.get_resolved_reliability(), 0.9), "Worker guard survives day transitions on linked citizen stats.")
	workshop = plot.get_node("BuiltWorkshop")
	debug.production_button.pressed.emit()
	initial_materials.assign(Inventory.items)
	initial_materials.erase("shekel")
	var supplied: Dictionary = Inventory.items.duplicate()
	debug.production_button.pressed.emit()
	_expect(Inventory.items == supplied, "Repeated production refill preserves surplus without stacking.")
	_expect(not Inventory.items.has("wet_mudbrick") and not Inventory.items.has("sun_dried_mudbrick"), "Debug never grants completed production outputs.")
	player.global_position = workshop.get_node("InteractableComponent").global_position + Vector2(0, 4)
	await _settle()
	await _open_workshop()
	var menu: WorkshopMenuUI = _ui(WorkshopMenuUI)
	await _deposit_materials(menu)
	await _shape_wet_bricks()
	await _pay_output("wet_mudbrick", "Build & Upgrade")
	await _build_or_upgrade_yard(1)
	await _dry_wet_bricks()
	await _pay_output("sun_dried_mudbrick", "sun-dried")
	await _build_or_upgrade_yard(2)
	await _shape_wet_bricks()
	await _pay_output("wet_mudbrick", "Assign Work")
	await _dry_wet_bricks()
	await _pay_output("sun_dried_mudbrick", "sun-dried")
	await _check_withdrawal()
	_expect(completed_cycles == 2, "Two full cycles complete through normal production UI.")
	_expect(Inventory.items.get("shekel", 0) == 86, "Actual payments consume 14 Shekel.")
	_expect(hud.shekel_label.text == "86", "Shekel HUD reflects output fee payments.")
	_expect(Inventory.items.get("sun_dried_mudbrick", 0) == 1 and WorkShopStorage.get_free_item_quantity("sun_dried_mudbrick") == 29, "40 produced, 10 upgraded, 1 withdrawn, 29 remain.")
	debug.set_worker_guard(false)
	worker.get_linked_citizen().satisfaction = 0.31
	TimeComponentManager.emit_time_signal()
	_expect(is_equal_approx(worker.get_resolved_satisfaction(), 0.31), "Disabled guard leaves ordinary worker state alone.")
	debug.set_player_guard(false)
	_expect(not player.debug_disable_player_needs and not player.debug_disable_fatigue, "Player guard can be disabled.")
	debug.set_player_guard(true)
	print("BranchAcceptanceFlowTest: " if include_hauling else "DebugProductionFlowTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().paused = false
	get_tree().quit(0 if failures == 0 else 1)

func _settle() -> void:
	for index: int in range(5):
		await get_tree().physics_frame
	await _frames(2)

func _haul_before_building() -> void:
	var route_audit = preload("res://scenes/test_scenes/main_map_hauler_start_test.gd").new()
	route_audit.run_automatically = false
	add_child(route_audit)
	route_audit.content = content
	route_audit.player = player
	route_audit.worksites = content.get_node("YSortWorld/Worksites")
	await route_audit._equip_and_haul()
	failures += route_audit.failures
	var worksites = route_audit.worksites
	player.global_position = worksites.get_node("WorksiteMarkers/WoodSite").global_position + Vector2(0, 8)
	await _settle()
	await route_audit._press(&"interact")
	for id: String in ["initial_worksite_hauler", "initial_workshop_laborer"]:
		worksites.inspector._request_remove(id)
		worksites.inspector.remove_yes_button.pressed.emit()
		await _frames(2)
	worksites.inspector.close_button.pressed.emit()
	debug.step_minutes(60)
	await _settle()
	_expect(not worker.is_reserved(), "Laborer is released from Daily work before clearing and construction.")
	_expect(Inventory.items.get("wood_log", 0) == 3, "Hauler-earned Wood stays in Inventory and contributes to the following build kit.")
	route_audit.free()

func _interact(target: Node2D) -> void:
	player.global_position = target.get_node("InteractableComponent").global_position + Vector2(0, 8)
	await _settle()
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventAction.new()
	event.action = "interact"
	get_viewport().push_input(event)
	await _frames(3)
