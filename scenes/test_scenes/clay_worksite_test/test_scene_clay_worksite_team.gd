extends Node

var failures: int = 0
var fixture
var panel
var ids: Array[String] = ["daily_test_a", "daily_test_b"]

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for id: String in ids:
		var worker := WorkerData.new()
		worker.worker_id = id
		worker.display_name = id
		worker.profession = WorkerData.Profession.LABORER
		WorkerDatabase.workers_by_id[id] = worker
	fixture = load("res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn").instantiate()
	fixture.enable_worker_commute = false
	add_child(fixture)
	await get_tree().process_frame
	fixture.player.debug_disable_player_needs = true
	panel = fixture.inspector
	var schedule = fixture.daily
	var site = fixture.sites[&"ClaySiteA"]
	fixture.player.position = Vector2(-90, 0)
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	fixture._unhandled_input(event)
	_expect(panel.work_mode.is_empty() and not panel.start_button.visible, "Opening offers only Hourly / Daily.")
	_expect(panel.find_child("OutputLabel", true, false) == null and panel.find_child("AddWorkerButton", true, false) == null, "Output and old Add Worker hidden.")
	panel.daily_button.pressed.emit()
	_expect(panel.assignment_ui.visible and not panel.assignment_ui.selected_worker_ids.has("player"), "Daily opens empty NPC-only assignment.")
	panel.assignment_ui._open_worker_selection(0)
	_expect(panel.assignment_ui.worker_list.get_node_or_null("Participant_player") == null, "Player absent from Daily cards.")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(panel.assignment_ui.worker_list.columns >= 4, "Cards fill row before wrapping.")
	_toggle(ids[0])
	_toggle(ids[1])
	var ui = panel.assignment_ui
	_expect(ui.slot_grid.get_child(0).tooltip_text.is_empty(), "Assigned worker cards have no hover tooltip.")
	ui.back_button.pressed.emit()
	_expect(ui.discard_overlay.visible and ui.visible, "Back with workers asks before discarding.")
	await _capture("worker-discard.png")
	ui.keep_button.pressed.emit()
	_expect(not ui.discard_overlay.visible and schedule.selected[&"ClaySiteA"].size() == 2, "No preserves worker settings.")
	ui.back_button.pressed.emit()
	ui.discard_button.pressed.emit()
	_expect(schedule.selected[&"ClaySiteA"].is_empty() and panel.work_mode.is_empty(), "Yes clears draft and returns to initial menu.")
	panel.daily_button.pressed.emit()
	_toggle(ids[0])
	_toggle(ids[1])
	_expect(schedule.selected[&"ClaySiteA"].size() == 2 and not schedule.toggle(&"ClaySiteA", "player"), "Two NPC slots and no Player admission.")
	panel.assignment_ui.next_button.pressed.emit()
	_expect(panel.hourly_button.disabled, "Worker setup locks Player choice.")
	panel.close_button.pressed.emit()
	_expect(schedule.selected[&"ClaySiteA"].is_empty(), "Close clears unstarted worker settings.")
	fixture._unhandled_input(event)
	_expect(not panel.hourly_button.disabled and not panel.daily_button.disabled, "Reopening after Close restores both choices.")
	panel.daily_button.pressed.emit()
	_toggle(ids[0])
	_toggle(ids[1])
	panel.assignment_ui.next_button.pressed.emit()
	_expect(not panel.start_button.disabled and not panel.duration_buttons.is_visible_in_tree(), "Daily returns to Start without hourly duration.")
	_expect(not panel.assignment_ui.total_workers_label.visible and panel.assignment_ui.feedback_label.text.contains(ids[0]), "Assignment shows names without redundant total workers.")
	await _capture("daily-ready.png")
	# Assign at 14:00: reserve now, first shift starts tomorrow.
	TimeComponentManager.current_hour = 14
	TimeComponentManager.current_minute = 0
	schedule.last_tick = schedule.now()
	var before: int = schedule.now()
	panel.start_button.pressed.emit()
	_expect(schedule.jobs.has(&"ClaySiteA") and not panel.visible and fixture.player.can_move, "Daily activates a standing assignment and releases Player.")
	_expect(schedule.now() == before, "Daily Start has no time skip.")
	_expect(not WorkerDatabase.get_worker_data(ids[0]).is_working(), "New assignment waits until tomorrow.")
	_expect(not schedule.toggle(&"ClaySiteB", ids[0]), "Reservation prevents second assignment.")
	site.participants.assign(["player"])
	_expect(site.preview(180, fixture.player).reason.is_empty(), "Future Daily members do not consume active site capacity.")
	get_tree().paused = true
	var bag: Dictionary = Inventory.items.duplicate()
	TimeComponentManager.advance_minutes(60)
	_expect(site.stock == 72 and fixture.get_node("GroundOutput").get_child_count() == 0, "No production on assignment day.")
	TimeComponentManager.advance_minutes(23 * 60)
	_expect(fixture.get_node("GroundOutput").get_child_count() == 1, "First workday has depleted output.")
	TimeComponentManager.advance_minutes(60)
	var stack: PickUpItem = fixture.get_node("GroundOutput").get_child(0)
	_expect(stack.quantity == 72 and site.stock == 0, "14:00 assignment first gathers tomorrow, capped by stock.")
	_expect(schedule.minutes_by_worker[ids[0]] == 360 and schedule.status(&"ClaySiteA").contains("Resting"), "Shift ends exactly at 15:00.")
	_expect(WorkerDatabase.get_worker_data(ids[0]).current_work_status == WorkerData.WorkStatus.RESTING, "Worker activity changes to Resting at 15:00.")
	_expect(WorkerDatabase.get_worker_data(ids[0]).is_reserved() and not WorkerDatabase.get_worker_data(ids[0]).is_working(), "Resting retains reservation without claiming active work.")
	_expect(not schedule.toggle(&"ClaySiteB", ids[0]), "Resting worker cannot take a second assignment.")
	var clay_job := JobData.new()
	clay_job.requirement_profession = WorkerData.Profession.LABORER
	_expect(WorkManager._resolve_worker_id(WorkOrder.Worker_Type.NPC, ids[0], clay_job).is_empty(), "Workshop backend rejects a resting reserved worker.")
	_expect(panel.assignment_ui._get_worker_status_text(WorkerDatabase.get_worker_data(ids[0])) == "Resting", "Shared assignment UI displays actual activity.")
	_expect(schedule.active_count(&"ClaySiteA") == 0, "Resting workers do not occupy active gathering capacity.")
	_expect(Inventory.items == bag, "Daily output never goes to Player bag.")
	# Rest, replace natural stock at midnight, resume automatically at 07:00.
	TimeComponentManager.advance_minutes(16 * 60)
	_expect(site.stock == 72 and stack.quantity == 72, "New-day stock replaces remainder without changing ground output.")
	_expect(WorkerDatabase.get_worker_data(ids[0]).is_working(), "Standing assignment resumes at 07:00.")
	TimeComponentManager.advance_minutes(6 * 60)
	_expect(WorkerDatabase.get_worker_data(ids[0]).current_work_status == WorkerData.WorkStatus.WAITING_FOR_RESOURCES, "Depletion at 13:00 changes worker activity to Waiting for resources.")
	_expect(WorkerDatabase.get_worker_data(ids[0]).is_reserved() and schedule.active_count(&"ClaySiteA") == 0, "Depleted assignment remains reserved but frees active gathering capacity.")
	_expect(WorkManager._resolve_worker_id(WorkOrder.Worker_Type.NPC, ids[0], clay_job).is_empty(), "Workshop backend rejects a worker waiting for site resources.")
	var worked_at_depletion: int = schedule.minutes_by_worker[ids[0]]
	TimeComponentManager.advance_minutes(2 * 60)
	_expect(schedule.minutes_by_worker[ids[0]] == worked_at_depletion, "Waiting does not consume worked-minute budget.")
	_expect(site.stock == 0 and stack.quantity == 144, "Next day resumes automatically and merges depleted output into existing stack.")
	_expect(fixture.get_node("GroundOutput").get_child_count() == 1, "Daily outputs do not create unbounded pickup objects.")
	_expect(int(schedule.minutes_by_worker[ids[0]]) <= 480, "Worker stays within eight-hour ceiling.")
	# Withdraw via the reused UI; reservation and capacity release immediately.
	get_tree().paused = false
	fixture.player.current_interactable = null
	fixture._pickup_focused = false
	fixture._unhandled_input(event)
	_expect(panel.daily_button.disabled and panel.progress_button.visible and not panel.start_button.visible, "Full team locks assignment and exposes progress only.")
	_expect(not panel.status_label.visible, "Main menu omits active work feedback.")
	_expect(not panel.get_node("Center/TextureWindow/Margin/MainVBox/Confirmation/WorkersLabel").text.contains(ids[0]), "Main menu omits names.")
	await _capture("worksite-active-clean.png")
	panel.progress_button.pressed.emit()
	_expect(panel.progress_panel.visible and panel.progress_list.get_child_count() == 2, "Progress lists both confirmed workers.")
	_expect(schedule.progress_rows(&"ClaySiteA")[0].days == 2 and schedule.progress_rows(&"ClaySiteA")[0].output == 72, "Progress counts productive days and individual output.")
	await _capture("worksite-worker-progress.png")
	panel.progress_list.get_child(0).get_child(1).pressed.emit()
	_expect(panel.remove_overlay.visible and WorkerDatabase.get_worker_data(ids[0]).is_reserved(), "Remove asks first without releasing the worker.")
	await _capture("worksite-remove-confirmation.png")
	panel.remove_no_button.pressed.emit()
	_expect(not panel.remove_overlay.visible and panel.progress_panel.visible and schedule.reserved_count(&"ClaySiteA") == 2, "No preserves both assignments.")
	panel.progress_list.get_child(0).get_child(1).pressed.emit()
	var cancel_event := InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	panel._input(cancel_event)
	_expect(not panel.remove_overlay.visible and panel.progress_panel.visible and schedule.reserved_count(&"ClaySiteA") == 2, "Escape cancels removal without closing progress.")
	panel.progress_list.get_child(0).get_child(1).pressed.emit()
	panel.remove_yes_button.pressed.emit()
	await get_tree().process_frame
	_expect(not WorkerDatabase.get_worker_data(ids[0]).is_working(), "Withdrawal releases global worker reservation.")
	_expect(not WorkerDatabase.get_worker_data(ids[0]).is_reserved() and WorkerDatabase.get_worker_data(ids[0]).current_work_status == WorkerData.WorkStatus.IDLE, "Withdrawal clears reservation and returns Idle.")
	panel._show_progress(false)
	panel.daily_button.pressed.emit()
	_expect(panel.assignment_ui._get_assigned_worker_count() == 0 and panel.assignment_ui.max_worker_slots == 1, "Assignment opens empty with only remaining capacity.")
	panel.assignment_ui._open_worker_selection(0)
	var sorted_roster: Array = panel.assignment_ui._get_workers_in_requirement_order()
	_expect(sorted_roster[-1].is_reserved(), "Reserved workers sort behind available workers.")
	_expect(not schedule.toggle(&"ClaySiteA", ids[1]), "Assignment cannot remove a confirmed worker.")
	await _capture("worksite-assignment-sorted.png")
	panel.assignment_ui._show_overview()
	panel.assignment_ui.next_button.pressed.emit()
	panel.progress_button.pressed.emit()
	panel.progress_list.get_child(0).get_child(1).pressed.emit()
	panel.remove_yes_button.pressed.emit()
	await get_tree().process_frame
	panel._show_progress(false)
	_expect(not schedule.jobs.has(&"ClaySiteA") and panel.start_button.disabled, "Last withdrawal stops recurrence.")
	panel.hourly_button.pressed.emit()
	_expect(panel.work_mode == "Hourly" and panel.duration_buttons.visible, "Hourly offers 3/6/9 only for Player.")
	await _capture("hourly.png")
	panel.close_button.pressed.emit()
	get_tree().paused = true
	# Large stock allows a full shift: exactly 480 minutes and 48 clay per worker.
	TimeComponentManager.advance_minutes(16 * 60)
	site.stock = 1000
	schedule.toggle(&"ClaySiteA", ids[0])
	schedule.start(&"ClaySiteA", fixture._drop_daily_output.bind(fixture.get_node("WorksiteMarkers/ClaySiteA")))
	TimeComponentManager.advance_minutes(24 * 60)
	site.stock = 1000
	var hourly: Dictionary = site.execute(180, fixture.player, fixture, fixture._drop_output)
	_expect(hourly.units == 18 and schedule.minutes_by_worker[ids[0]] == 180 and site.stock == 964, "One Player and one Daily worker share capacity, stock, and elapsed time.")
	TimeComponentManager.advance_minutes(5 * 60)
	_expect(schedule.minutes_by_worker[ids[0]] == 480 and site.stock == 934, "Full worker shift is eight hours, with separate Player output accounted once.")
	# Moving an exhausted worker does not reset their daily ledger or extend the shift.
	schedule.withdraw(&"ClaySiteA", ids[0])
	schedule.toggle(&"ClaySiteB", ids[0])
	schedule.start(&"ClaySiteB", fixture._drop_output)
	var other_stock: int = fixture.sites[&"ClaySiteB"].stock
	TimeComponentManager.advance_minutes(60)
	_expect(fixture.sites[&"ClaySiteB"].stock == other_stock and schedule.minutes_by_worker[ids[0]] == 480, "Reassignment after 15:00 creates no extra work.")
	# Configurable replacement generator includes scarcity, without changing live balance.
	schedule.stock_min = 2
	schedule.stock_max = 4
	TimeComponentManager.advance_minutes(8 * 60)
	_expect(site.stock >= 2 and site.stock <= 4, "Test-only random range replaces natural stock.")
	var rolled: int = site.stock
	schedule.tick()
	_expect(site.stock == rolled, "Same-minute refresh cannot reroll stock.")
	schedule.withdraw(&"ClaySiteB", ids[0])
	schedule.toggle(&"ClaySiteA", ids[0])
	schedule.toggle(&"ClaySiteA", ids[1])
	TimeComponentManager.current_hour = 6
	TimeComponentManager.current_minute = 59
	schedule.last_tick = schedule.now()
	site.stock = 72
	schedule.start(&"ClaySiteA", fixture._drop_daily_output.bind(fixture.get_node("WorksiteMarkers/ClaySiteA")))
	_expect(WorkerDatabase.get_worker_data(ids[0]).current_work_status == WorkerData.WorkStatus.RESTING, "Starting at 06:59 reserves the worker but waits for 07:00.")
	TimeComponentManager.advance_minutes(24 * 60)
	site.stock = 72
	var handoff: Dictionary = site.execute(180, fixture.player, fixture, fixture._drop_output)
	_expect(handoff.interrupted and handoff.minutes == 1 and handoff.units == 0, "Hourly stops when 07:00 starts a full two-worker shift.")
	Inventory.max_load = Inventory.get_total_inventory_weight() + 4.0
	var pile_before: int = stack.quantity
	var bag_before: int = Inventory.items.get("clay_lump", 0)
	stack.on_player_interact(fixture.player)
	stack.on_player_interact(fixture.player)
	_expect(Inventory.items.get("clay_lump", 0) == bag_before + 2, "Oversized daily pile allows partial pickup exactly once.")
	var remainder: PickUpItem = fixture.get_node("GroundOutput").get_child(-1)
	_expect(remainder != stack and remainder.quantity == pile_before - 2, "Uncollected quantity remains at site.")
	fixture._drop_daily_output(3, fixture.get_node("WorksiteMarkers/ClaySiteA"))
	_expect(remainder.quantity == pile_before + 1, "New output merges into remainder, never into the collecting pile.")
	# 00:01 still schedules the following calendar day, never today's 07:00.
	schedule.cleanup()
	schedule.setup(fixture.sites)
	schedule.stock_min = 72
	schedule.stock_max = 72
	TimeComponentManager.current_day += 1
	TimeComponentManager.current_hour = 0
	TimeComponentManager.current_minute = 1
	schedule.last_tick = schedule.now()
	var target_day: int = TimeComponentManager.current_day + 1
	schedule.toggle(&"ClaySiteA", ids[0])
	_expect(schedule.start_day_text(&"ClaySiteA") == "Start work: Day %d" % target_day, "Draft start label uses current day plus one.")
	schedule.start(&"ClaySiteA", fixture._drop_output)
	TimeComponentManager.advance_minutes(419)
	_expect(not WorkerDatabase.get_worker_data(ids[0]).is_working() and schedule.active_count(&"ClaySiteA") == 0, "00:01 assignment does not start at today's 07:00.")
	TimeComponentManager.advance_minutes(1439)
	_expect(not WorkerDatabase.get_worker_data(ids[0]).is_working(), "Worker waits through next-day 06:59.")
	TimeComponentManager.advance_minutes(1)
	_expect(WorkerDatabase.get_worker_data(ids[0]).is_working(), "Worker starts exactly next-day 07:00.")
	_expect(schedule.start_day_text(&"ClaySiteA") == "Start work: Day %d" % target_day, "Confirmed start date does not drift after midnight.")
	schedule.toggle(&"ClaySiteA", ids[1])
	schedule.start(&"ClaySiteA", fixture._drop_output)
	_expect(WorkerDatabase.get_worker_data(ids[0]).is_working() and not WorkerDatabase.get_worker_data(ids[1]).is_working(), "Added worker waits tomorrow without delaying existing worker.")
	var stock_before: int = site.stock
	TimeComponentManager.advance_minutes(10)
	_expect(site.stock == stock_before - 1, "Only the eligible worker produces output.")
	get_tree().paused = false
	fixture.queue_free()
	await get_tree().process_frame
	for id: String in ids:
		_expect(not WorkerDatabase.get_worker_data(id).is_working(), "Scene exit releases standing assignments.")
		WorkerDatabase.workers_by_id.erase(id)
	_expect(not get_tree().paused, "UI cleanup releases pause.")
	print("ClayWorksiteDailyTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)

func _toggle(id: String) -> void:
	var ui = panel.assignment_ui
	if ui.selected_worker_ids.has(id):
		ui._remove_worker_from_slot(ui.selected_worker_ids.find(id))
	else:
		ui._open_worker_selection(ui._get_first_empty_slot_index())
		ui.worker_list.get_node("Participant_" + id).pressed.emit()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _capture(filename: String) -> void:
	if OS.get_environment("TIP_CAPTURE_TEAM") == "1" and DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("tip-clay-feedback-20260907/" + filename))
