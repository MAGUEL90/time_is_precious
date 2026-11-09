extends "res://scenes/test_scenes/test_scene_walked_city_journey.gd"

## Continuation of the real walked New Game checkpoint. No grants, teleports,
## protection or forced seed. Like the parent driver it can accelerate idle
## one normal minute at a time; every interaction is player/UI driven.
## The worksite approach is adapted from the current authored-map walk probe:
## account for the asymmetric wood area and end on the 8px routing grid.
func _site_approach(marker: Marker2D, avoided: Array[Vector2] = []) -> Vector2:
	var candidates: Array[Vector2] = []
	var area: Area2D = marker.get_node_or_null("WoodInteractionArea")
	var shape_node: CollisionShape2D = area.get_child(0) as CollisionShape2D if area != null else null
	var center: Vector2i = Vector2i((marker.global_position / 8.0).round())
	for x: int in range(center.x - 4, center.x + 5):
		for y: int in range(center.y - 4, center.y + 5):
			var candidate: Vector2 = Vector2(x * 8, y * 8)
			var radius: float = candidate.distance_to(marker.global_position)
			if radius < 12.0 or radius > 29.0:
				continue
			if shape_node != null and not shape_node.shape.get_rect().grow(-4.0).has_point(shape_node.to_local(candidate)):
				continue
			var nearest: bool = true
			for obstruction: Vector2 in avoided:
				if candidate.distance_to(obstruction) < 8.0:
					nearest = false
					break
			for other: Marker2D in runtime.get_node("WorksiteMarkers").get_children():
				if other != marker and candidate.distance_to(other.global_position) <= radius + 1.5:
					nearest = false
					break
			if nearest:
				candidates.append(candidate)
	return _reachable_approach(candidates, marker.global_position)

func walk_to_site(marker: Marker2D) -> void:
	var avoided: Array[Vector2] = []
	for _attempt: int in range(12):
		var approach: Vector2 = _site_approach(marker, avoided)
		_expect(approach != Vector2.INF, "A collision-clear and reachable worksite approach exists")
		if stopped:
			return
		await walk(approach)
		if stopped:
			return
		if not is_instance_valid(player.current_interactable) and not runtime._pickup_focused and runtime._nearest_interaction_site() == marker:
			return
		avoided.append(approach)
	_expect(false, "A walking approach reaches the intended worksite focus")

func open_workshop() -> void:
	workshop = plot.get_node_or_null("BuiltWorkshop")
	_expect(is_instance_valid(workshop), "The earned workshop exists before opening it.")
	if stopped:
		return
	await _walk_to_interactable(workshop)
	await interact(workshop)

func _verify_walked_continue() -> void:
	if OS.get_cmdline_user_args().has("--checkpoint-only"):
		await _verify_partial_checkpoint()
		return
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(WALKED_DIR + "/expected.json"))
	_expect(expected is Dictionary and same(expected, restored_snapshot), "A new process restores the complete earned sleep checkpoint.")
	if stopped:
		return
	print("TERRA_CONTINUE_SNAPSHOT PASS")
	await leave_home()
	_expect(content.get_node("YSortWorld/CitizenHousePlot").construction.phase == "built" and plot.construction.phase == "built", "Both earned buildings return after Continue.")
	if stopped:
		return
	var sites: Dictionary = {"clay_lump": "ClaySiteA", "straw_bundle": "StrawSite", "water_jar": "WaterSite"}
	for id: String in JOB.inputs:
		while int(Inventory.items.get(id, 0)) < int(JOB.inputs[id]) and not stopped:
			await gather(sites[id])
		if stopped:
			return
	print("TERRA_EARNED_INPUTS ", JSON.stringify({"minute": now(), "inventory": Inventory.items, "walked_pixels": walked}))
	await open_workshop()
	if stopped:
		return
	await press(ui(WorkshopMenuUI).manage_button)
	await press(ui(WorkshopStorageMenuUI).deposit_button)
	var transfer: ItemTransferUI = ui(ItemTransferUI)
	if stopped:
		return
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var storage_before: Dictionary = WorkShopStorage.items.duplicate(true)
	for slot: ItemSlot in transfer.grid_container.get_children():
		for _index: int in range(int(JOB.inputs.get(slot._item_id, 0))):
			slot.pressed.emit()
	for id: String in JOB.inputs:
		_expect(int(transfer.selected_items.get(id, 0)) == int(JOB.inputs[id]), "Select each earned production input: " + id)
	if stopped:
		return
	await press(transfer.confirm_button)
	for id: String in JOB.inputs:
		_expect(int(inventory_before.get(id, 0)) - int(Inventory.items.get(id, 0)) == int(JOB.inputs[id]) and int(WorkShopStorage.items.get(id, 0)) - int(storage_before.get(id, 0)) == int(JOB.inputs[id]), "The workshop receives each earned input exactly once: " + id)
	if stopped:
		return
	await press(transfer.back_button)
	await press(ui(WorkshopStorageMenuUI).back_button)
	await press(ui(WorkshopMenuUI).close_button)
	print("TERRA_DEPOSIT PASS ", JSON.stringify({"inventory": Inventory.items, "workshop_stock": WorkShopStorage.items}))
	worker = WorkerDatabase.get_worker_data(FIRST)
	_expect(worker != null, "The earned worker is available after Continue.")
	if stopped:
		return
	var deadline: int = now() + 5 * 1440
	while not stopped and now() < deadline and (worker.is_payroll_blocked() or worker.is_reserved()):
		await upkeep()
		await _market()
		if worker.is_payroll_blocked():
			var price: int = WorkerDatabase.get_contract_price(worker.profession, 9)
			if int(Inventory.items.get("shekel", 0)) >= price:
				await _renew_worker()
			elif int(Inventory.items.get("wood_log", 0)) < 8:
				await gather("WoodSite")
			else:
				await wait_minutes(30)
		else:
			await wait_minutes(30)
	_expect(not worker.is_payroll_blocked() and not worker.is_reserved(), "The earned worker is paid and free for production.")
	if stopped:
		return
	await open_workshop()
	await press(ui(WorkshopMenuUI).assign_button)
	await choose(ui(WorkshopProductionUI), JOB.job_id)
	if stopped:
		return
	var assignment: WorkshopWorkerAssignmentUI = ui(WorkshopWorkerAssignmentUI)
	if assignment._get_selected_worker_ids().is_empty():
		await press(assignment.slot_grid.get_child(0))
		var worker_button: Button
		for child: Node in assignment.worker_list.get_children():
			if child is Button and str(child.get_meta("worker_id", "")) == worker.worker_id:
				worker_button = child
		await press(worker_button)
	await press(assignment.next_button)
	if stopped:
		return
	var job_ui: WorkshopJobUI = ui(WorkshopJobUI)
	print("TERRA_JOB_READY ", JSON.stringify({"text": job_ui.requirement_label.text, "disabled": job_ui.start_button.disabled, "worker": worker.worker_id, "wallet": Inventory.items.get("shekel", 0)}))
	var inputs_before: Dictionary = WorkShopStorage.items.duplicate(true)
	await press(job_ui.start_button)
	_expect(job_ui.job_started, "The actual UI starts the earned worker's Shape job: " + job_ui.requirement_label.text)
	for id: String in JOB.inputs:
		_expect(int(inputs_before.get(id, 0)) - int(WorkShopStorage.items.get(id, 0)) == int(JOB.inputs[id]), "Starting Shape consumes each workshop input exactly once: " + id)
	if stopped:
		return
	print("TERRA_SHAPE_STARTED PASS ", JSON.stringify({"minute": now(), "inputs_before": inputs_before, "inputs_after": WorkShopStorage.items, "active_orders": WorkManager.active_orders.size()}))
	await press(job_ui.close_button)
	var completion_deadline: int = now() + 3 * 1440
	while not stopped and WorkShopStorage.get_held_item_quantity("wet_mudbrick") <= 0 and now() < completion_deadline:
		await upkeep()
		await wait_minutes(30)
	var held: int = WorkShopStorage.get_held_item_quantity("wet_mudbrick")
	print("TERRA_SHAPE_RESULT ", JSON.stringify({"status": "PASS" if held > 0 and not stopped else "PARTIAL", "minute": now(), "held_wet_bricks": held, "active_orders": WorkManager.active_orders.size(), "fast_idle_minutes": fast_idle_minutes, "inventory": Inventory.items, "lots": WorkShopStorage.output_lots}))
	get_tree().quit(0 if held > 0 and not stopped else 2)

## Observe the actual shared-card controls without emitting action signals or
## invoking the backend. Stop with PARTIAL if renewal is inaccessible.
func _renew_worker() -> void:
	var action := InputEventAction.new()
	action.action = "open_worker_hub"
	action.pressed = true
	get_viewport().push_input(action)
	action.pressed = false
	get_viewport().push_input(action)
	await _frames(3)
	var hub: WorkerControlUI = runtime.worker_control
	_expect(hub.visible, "The actual Worker Hub opens for the expired worker.")
	if stopped:
		return
	# Prefer an actual visible Manage button for this worker if the roster
	# provides one; otherwise inspect the existing worker-specific row button.
	var row: Button
	for candidate: Node in hub.find_children("*", "Button", true, false):
		if candidate is Button and candidate.is_visible_in_tree() and not candidate.disabled \
				and candidate.text.to_lower() == "manage" and str(candidate.get_meta("worker_id", "")) == worker.worker_id:
			row = candidate
			break
	if not is_instance_valid(row):
		row = hub._find_manage_button(worker.worker_id)
	print("TERRA_RENEW_ROW ", JSON.stringify({"label": row.text if is_instance_valid(row) else "missing", "visible": is_instance_valid(row) and row.is_visible_in_tree()}))
	await press(row)
	if stopped:
		return
	var controller: Node = runtime.get_node_or_null("CitizenInspectionController")
	var panel: CitizenInspectionPanel = controller.get("panel") if is_instance_valid(controller) else null
	if not hub.manage_window.visible and not hub.contract_window.visible:
		_expect(is_instance_valid(panel) and panel.visible and panel.selected_id == worker.worker_id, "The selected worker's real card opens.")
		if stopped:
			return
		var controls: Array = []
		var usable_action: Button
		for candidate: Node in panel.find_children("*", "BaseButton", true, false):
			if candidate is BaseButton and candidate.is_visible_in_tree():
				var label: String = candidate.text if candidate is Button else ""
				controls.append({"path": str(panel.get_path_to(candidate)), "label": label, "disabled": candidate.disabled})
				if candidate is Button and not candidate.disabled and label.to_lower() in ["manage", "actions", "contract", "renew"]:
					usable_action = candidate
		print("TERRA_RENEW_VISIBLE_CONTROLS ", JSON.stringify(controls))
		if not is_instance_valid(usable_action):
			print("TERRA_RENEW_UI_BLOCK no visible Manage, Actions, Contract, or Renew control; no signal or backend bypass")
			stopped = true
			release_input()
			get_tree().quit(2)
			return
		await press(usable_action)
		if stopped:
			return
	if hub.manage_window.visible:
		_expect(hub._manage_worker_id == worker.worker_id, "Manage is visible for the selected worker.")
		if stopped:
			return
		await press(hub.manage_contract_button)
	_expect(hub.contract_window.visible and hub._manage_worker_id == worker.worker_id, "The real visible Manage or card control opens this worker's Contract window.")
	if stopped:
		return
	var days_button: Button
	for button: Button in hub.contract_day_buttons:
		if int(button.get_meta("contract_days", -1)) == 9:
			days_button = button
	await press(days_button)
	var before: int = int(Inventory.items.get("shekel", 0))
	var treasury_before: int = CityStockManager.treasury_shekel
	var price: int = WorkerDatabase.get_contract_price(worker.profession, 9)
	await press(hub.manage_renew_button)
	_expect(not worker.is_payroll_blocked() and before - int(Inventory.items.get("shekel", 0)) == price and CityStockManager.treasury_shekel == treasury_before, "Real Contract UI renews once from earned wallet funds.")
	if stopped:
		return
	renewed += 1
	print("TERRA_RENEWED ", JSON.stringify({"minute": now(), "wallet_before": before, "price": price, "wallet_after": Inventory.items.get("shekel", 0), "actual_visible_ui": true}))
	await press(hub.contract_close_button)
	_expect(hub.visible and get_tree().paused and (hub.manage_window.visible or (is_instance_valid(panel) and panel.visible)), "Closing Contract returns to its actual visible parent.")
	if stopped:
		return
	action = InputEventAction.new()
	action.action = "open_worker_hub"
	action.pressed = true
	get_viewport().push_input(action)
	action.pressed = false
	get_viewport().push_input(action)
	await _frames(3)
	_expect(not hub.visible and (not is_instance_valid(panel) or not panel.visible) and not get_tree().paused, "K closes Worker Hub and returns to live play.")

## Compare the actual pre-block sleep document with the snapshot captured by
## session_started before the clock advances, then leave home normally.
func _verify_partial_checkpoint() -> void:
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(checkpoint_path))
	_expect(expected is Dictionary and same(expected, restored_snapshot), "A separate process restores the entire earned checkpoint without clock drift.")
	if stopped:
		return
	print("TERRA_PARTIAL_CONTINUE_SNAPSHOT PASS ", JSON.stringify({"checkpoint_sha256": FileAccess.get_file_as_string(checkpoint_path).sha256_text(), "day": TimeComponentManager.current_day, "hour": TimeComponentManager.current_hour, "minute": TimeComponentManager.current_minute}))
	await leave_home()
	_expect(content.name == "ContentScene" and content.get_node("YSortWorld/CitizenHousePlot").construction.phase == "built", "The earned house and normal home exit return after Continue.")
	_expect(plot.construction.phase == "building" and WorkerDatabase.get_worker_data(FIRST) != null, "The hired worker and in-progress workshop return after Continue.")
	if stopped:
		return
	print("TERRA_PARTIAL_CONTINUED_CITY PASS ", JSON.stringify({"construction": plot.construction.phase, "worker": FIRST, "inventory": Inventory.items, "walked_after_continue": walked}))
	release_input()
	get_tree().quit(0)
