extends "res://scenes/workshop_plot/workshop_plot.gd"

## This view shares the workshop construction state, but has no workshop backend.
## The rubble itself is the interaction target; there is no keeper NPC.
const HOUSE_FOOTPRINTS: Array[Rect2] = [Rect2(-19, -4, 38, 20)]
var _manual_house_work: bool = false
var _uses_authored_site_footprint: bool = false


func is_citizen_house_plot() -> bool:
	return true


func get_built_footprints() -> Array[Rect2]:
	return HOUSE_FOOTPRINTS


func use_authored_site_footprint(enabled: bool) -> void:
	_uses_authored_site_footprint = enabled
	if is_inside_tree() and is_node_ready() and is_instance_valid(construction):
		_sync_construction()


func on_player_interact(interacting_player: Player) -> void:
	super.on_player_interact(interacting_player)
	if is_instance_valid(menu):
		if not menu.player_build_requested.is_connected(_on_player_build_requested):
			menu.player_build_requested.connect(_on_player_build_requested)
		if not menu.player_resume_requested.is_connected(_on_player_resume_requested):
			menu.player_resume_requested.connect(_on_player_resume_requested)


func _on_player_build_requested() -> void:
	_run_player_house_work(false)


func _on_player_resume_requested() -> void:
	_run_player_house_work(true)


func _on_clearing_requested(ids: Array[String], use_player: bool) -> void:
	if not use_player:
		super._on_clearing_requested(ids, false)
		return
	_run_player_house_work(false, true, ids)


func _run_player_house_work(resuming: bool, starting_clearing: bool = false, ids: Array[String] = []) -> void:
	if _manual_clearing or not is_instance_valid(menu) or not has_player_access():
		return
	if player.has_critical_condition() or TimeComponentManager.is_paused:
		menu.show_error("Recover before working, and resume time.")
		return
	# Keep the same modal lock and fade as the existing manual clearing flow.
	# The guard is set before calling the state because its signals can re-enter.
	var was_clearing: bool = starting_clearing or (resuming and construction.phase == "clearing")
	_manual_house_work = true
	_manual_clearing = true
	var result: Dictionary
	if resuming:
		result = construction.resume_player_work()
	elif starting_clearing:
		result = construction.start_clearing(ids, true)
	else:
		result = construction.start_build([] as Array[String], true)
	if not bool(result.get("success", false)):
		_manual_house_work = false
		_manual_clearing = false
		if is_instance_valid(menu):
			menu.show_error(str(result.get("message", "Could not start construction.")))
		return
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(menu):
		construction.interrupt_player_work()
		_manual_house_work = false
		_manual_clearing = false
		return
	menu.hide()
	var cover := CanvasLayer.new()
	cover.layer = 90
	var shade := ColorRect.new()
	shade.color = Color.BLACK
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(shade)
	add_child(cover)
	var tree: SceneTree = get_tree()
	await tree.create_timer(0.15, true).timeout
	# Work through existing minute signals, which charge the player's needs.
	# Limit each session to the same three hours as a plot-clearing session.
	var minutes: int = 0
	while is_inside_tree() and not is_queued_for_deletion() and is_instance_valid(construction) and construction.is_player_work_active() and minutes < construction.CLEARING_MINUTES:
		if not is_instance_valid(player) or not has_player_access() or player.has_critical_condition():
			break
		if construction.phase == "building" and bool(construction.get_preview([] as Array[String]).get("shelter_blocked", false)):
			break
		if not TimeComponentManager.advance_minutes(1):
			break
		minutes += 1
	if is_instance_valid(construction):
		construction.interrupt_player_work()
	if is_inside_tree() and not is_queued_for_deletion():
		await tree.create_timer(0.5, true).timeout
	if is_instance_valid(cover):
		cover.queue_free()
	_manual_house_work = false
	_manual_clearing = false
	close_menu()
	if was_clearing:
		clearing_finished.emit()


func close_menu() -> void:
	if is_instance_valid(construction) and construction.is_player_work_active():
		construction.interrupt_player_work()
	if _manual_house_work or _manual_clearing:
		return
	super.close_menu()


func _sync_construction() -> void:
	_sync_build_progress()
	var built: bool = construction.phase == "built"
	for path: String in ["Plot", "LeftWall", "LeftWallTop", "RightWall", "RightWallTop", "Table", "TableLegs", "TableResources", "Board"]:
		get_node(path).hide()
	$ToBeClean.visible = not _uses_authored_site_footprint and construction.phase in ["uncleared", "clearing"]
	$SiteHouse.visible = not _uses_authored_site_footprint and construction.phase in ["empty", "building"]
	$FinishedHouse.visible = built
	$HouseBody/CollisionShape2D.set_deferred("disabled", not built)
	interaction_area.position = Vector2(0, 8)
	interactable_label_component.position = Vector2(-8, -34)
	$InteractableLabelComponent/HammerIcon.texture = HAND_ICON if construction.phase in ["uncleared", "clearing"] else HAMMER_ICON
	interaction_area.set_deferred("monitoring", not built)
	if built:
		close_menu()
		interactable_label_component.hide()
		if is_instance_valid(player):
			player._on_interactable_deactivated(self)
		$Label.text = ""
	elif construction.phase == "clearing":
		$Label.text = "No worker" if construction.worker_ids.is_empty() and not construction.is_player_work_active() else ("Contract expired" if construction._all_workers_payroll_blocked() and not construction.is_player_work_active() else "Clearing")
	elif construction.phase == "building":
		$Label.text = "No workers" if construction.worker_ids.is_empty() and not construction.is_player_work_active() else ("Contract expired" if construction._all_workers_payroll_blocked() and not construction.is_player_work_active() else "Building")
	else:
		$Label.text = ""


func _exit_tree() -> void:
	if is_instance_valid(construction) and construction.is_player_work_active():
		construction.interrupt_player_work()
	_manual_house_work = false
	_manual_clearing = false
	super._exit_tree()
