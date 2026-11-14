extends "res://scenes/workshop_plot/workshop_plot.gd"

## This view shares the workshop construction state, but has no workshop backend.
## The rubble itself is the interaction target; there is no keeper NPC.
const HOUSE_FOOTPRINTS: Array[Rect2] = [Rect2(-19, -4, 38, 20)]
@export var authored_marker_path: NodePath = NodePath()
var _manual_house_work: bool = false
var _uses_authored_site_marker: bool = false
var _uses_authored_site_footprint: bool = false


func _enter_tree() -> void:
	if not authored_marker_path.is_empty():
		var authored_marker: Node2D = get_node_or_null(authored_marker_path) as Node2D
		if authored_marker == null or not authored_marker.is_inside_tree():
			push_error("Citizen house plot authored marker path must resolve to an in-tree Node2D.")
		else:
			global_position = authored_marker.global_position
	super._enter_tree()


func is_citizen_house_plot() -> bool:
	return true

func _sync_build_progress() -> void:
	super._sync_build_progress()
	var label: Label = get_node_or_null("BuildingProgress/ProgressPercent") as Label
	if label == null or not is_instance_valid(construction):
		return
	label.visible = construction.phase == "building"
	if not label.visible:
		return
	var total: int = construction.work_total_units
	if total <= 0:
		# Legacy saves may not contain work_total_units; match the existing bar.
		total = maxi(1, (construction.completes_at - construction.started_at) * maxi(1, construction.worker_ids.size()))
	var completed: int = clampi(total - construction._remaining_work_units(), 0, total)
	var hundredths: int = clampi(floori(10000.0 * float(completed) / float(total)), 0, 9999)
	label.text = "0%" if hundredths == 0 else "%d.%02d%%" % [floori(hundredths / 100.0), hundredths % 100]


func get_built_footprints() -> Array[Rect2]:
	return HOUSE_FOOTPRINTS


func use_authored_site_marker(enabled: bool) -> void:
	_uses_authored_site_marker = enabled
	if is_inside_tree() and is_node_ready() and is_instance_valid(construction):
		_sync_construction()


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
	var session_menu: CanvasLayer = menu
	var session_player: Player = player
	var session_scene: Node = get_tree().current_scene
	var session_construction: Node = construction
	var session_tree: SceneTree = get_tree()
	if not is_instance_valid(session_menu) or not session_menu.is_inside_tree() or session_menu.is_queued_for_deletion() or not is_instance_valid(session_player) or not session_player.is_inside_tree() or session_player.is_queued_for_deletion() or not is_instance_valid(session_construction) or session_player.current_interactable != self or not get_tree().paused or session_scene == null or get_tree().current_scene != session_scene or not session_scene.is_ancestor_of(self) or not session_scene.is_ancestor_of(session_player):
		return
	var clearing_minutes: int = session_construction.CLEARING_MINUTES
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
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(session_menu) or not session_menu.is_inside_tree() or session_menu.is_queued_for_deletion() or not is_instance_valid(session_construction):
		if is_instance_valid(session_construction):
			session_construction.interrupt_player_work()
		_manual_house_work = false
		_manual_clearing = false
		if is_instance_valid(self) and is_inside_tree() and not is_queued_for_deletion():
			_finish_manual_session(session_menu, session_player, session_scene)
			if was_clearing:
				await session_tree.process_frame
				if is_instance_valid(self) and is_inside_tree() and not is_queued_for_deletion():
					clearing_finished.emit()
		return
	var session_phase: String = session_construction.phase
	var owns_player_work: bool = session_construction.clearing_by_player if session_phase == "clearing" else session_construction.player_building
	if session_phase not in ["clearing", "building"] or not owns_player_work or not session_construction.is_player_work_active():
		if session_construction.is_player_work_active():
			session_construction.interrupt_player_work()
		_manual_house_work = false
		_manual_clearing = false
		_finish_manual_session(session_menu, session_player, session_scene)
		if was_clearing:
			await session_tree.process_frame
			if is_instance_valid(self) and is_inside_tree() and not is_queued_for_deletion():
				clearing_finished.emit()
		return
	menu.hide()
	var cover := CanvasLayer.new()
	cover.layer = 90
	var shade := ColorRect.new()
	shade.color = Color.BLACK
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(shade)
	add_child(cover)
	await session_tree.create_timer(0.15, true).timeout
	if not is_instance_valid(self):
		return
	var guard: Callable = Callable(self, "_manual_house_work_guard").bind(session_menu, session_player, session_scene, session_construction, session_phase)
	await TimeComponentManager.advance_minutes_staged(clearing_minutes, self, guard)
	if not is_instance_valid(self):
		return
	if is_instance_valid(session_construction) and session_construction.is_player_work_active():
		session_construction.interrupt_player_work()
	if is_inside_tree() and not is_queued_for_deletion() and is_instance_valid(session_scene) and get_tree().current_scene == session_scene:
		await session_tree.create_timer(0.5, true).timeout
		if not is_instance_valid(self):
			return
	if is_instance_valid(cover):
		cover.queue_free()
	_manual_house_work = false
	_manual_clearing = false
	_finish_manual_session(session_menu, session_player, session_scene)
	if was_clearing:
		clearing_finished.emit()

func _manual_house_work_guard(session_menu: Variant, session_player: Variant, session_scene: Variant, session_construction: Variant, session_phase: String) -> bool:
	if not is_instance_valid(self) or not is_inside_tree() or is_queued_for_deletion():
		return false
	if not is_instance_valid(session_menu) or menu != session_menu or not session_menu.is_inside_tree() or session_menu.is_queued_for_deletion():
		return false
	if not is_instance_valid(session_player) or player != session_player or not session_player.is_inside_tree() or session_player.is_queued_for_deletion():
		return false
	if not is_instance_valid(session_scene) or session_scene.is_queued_for_deletion() or get_tree().current_scene != session_scene or not session_scene.is_ancestor_of(self) or not session_scene.is_ancestor_of(session_player):
		return false
	if not is_instance_valid(session_construction) or construction != session_construction or session_construction.phase != session_phase or not session_construction.is_player_work_active():
		return false
	if session_phase == "clearing" and not session_construction.clearing_by_player:
		return false
	if session_phase == "building" and not session_construction.player_building:
		return false
	if not _manual_house_work or not _manual_clearing or session_player.current_interactable != self or not has_player_access() or session_player.has_critical_condition():
		return false
	if session_phase == "building" and bool(session_construction.get_preview([] as Array[String]).get("shelter_blocked", false)):
		return false
	return get_tree().paused and not TimeComponentManager.is_paused

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
	$ToBeClean.visible = not _uses_authored_site_marker and construction.phase in ["uncleared", "clearing"]
	$SiteHouse.visible = not _uses_authored_site_footprint and construction.phase in ["empty", "building"]
	$FinishedHouse.visible = built
	$HouseBody/CollisionShape2D.set_deferred("disabled", not built)
	interaction_area.position = Vector2(0, 8)
	interactable_label_component.position = Vector2(-8, -34)
	$InteractableLabelComponent/HammerIcon.texture = HAND_ICON if construction.phase in ["uncleared", "clearing"] else HAMMER_ICON
	_set_plot_monitoring(not built)
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
	_apply_world_access()


func _exit_tree() -> void:
	if is_instance_valid(construction) and construction.is_player_work_active():
		construction.interrupt_player_work()
	_manual_house_work = false
	_manual_clearing = false
	super._exit_tree()
