extends Node

## The existing resident/worker visual owner maps a person ID to one moving
## actor. Hit-test its visible sprite area without adding physics bodies.
const PANEL: PackedScene = preload("res://scenes/ui/citizen_inspection/citizen_inspection_panel.tscn")
const ACTOR_HIT_RECT: Rect2 = Rect2(-10, -16, 20, 32)

## One reusable, non-interactive world-space marker; it does not participate in
## physics picking or GUI input. Its brackets sit just outside the hit area.
class HoverIndicator extends Node2D:
	const BRACKET_COLOR: Color = Color(1.0, 0.88, 0.43)
	const BORDER_COLOR: Color = Color(0.20, 0.12, 0.06)
	const BRACKETS: Array[Rect2] = [
		Rect2(-12, -18, 5, 1), Rect2(-12, -18, 1, 5),
		Rect2(8, -18, 5, 1), Rect2(12, -18, 1, 5),
		Rect2(-12, 18, 5, 1), Rect2(-12, 14, 1, 5),
		Rect2(8, 18, 5, 1), Rect2(12, 14, 1, 5),
	]

	func _draw() -> void:
		for bracket: Rect2 in BRACKETS:
			draw_rect(bracket.grow(1), BORDER_COLOR)
		for bracket: Rect2 in BRACKETS:
			draw_rect(bracket, BRACKET_COLOR)

var runtime: Node
var visuals: Node
var panel: CanvasLayer
var hover_indicator: Node2D
var hovered_person_id: String = ""
var _mouse_in_window: bool = true
var worker_control: WorkerControlUI
var _details_source: String = ""
var _details_person_id: String = ""
var _action_pending: bool = false
var _suspending_panel: bool = false
var _returning_to_map: bool = false
var _map_panel_layer: int = 8
var _hub_blocker_layer: CanvasLayer

func configure(worksite: Node, visual_owner: Node) -> void:
	runtime = worksite
	visuals = visual_owner

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PANEL.instantiate()
	panel.name = "CitizenInspectionPanel"
	panel.summary_provider = Callable(CitizenNeedsManager, "get_person_needs_summary")
	panel.worker_details_provider = Callable(self, "_worker_details_for")
	add_child(panel)
	_map_panel_layer = panel.layer
	panel.connect("closed", _on_panel_closed)
	panel.connect("renew_requested", _on_renew_requested)
	panel.connect("actions_requested", _on_actions_requested)
	_build_hub_blocker()
	worker_control = runtime.get("worker_control") as WorkerControlUI
	if is_instance_valid(worker_control):
		worker_control.details_requested.connect(_on_worker_details_requested)
		worker_control.shared_details_close_requested.connect(_on_shared_details_close_requested)
		worker_control.shared_action_closed.connect(_on_shared_action_closed)
		worker_control.close_requested.connect(_on_worker_control_closed)
	hover_indicator = HoverIndicator.new()
	hover_indicator.name = "CitizenHoverIndicator"
	hover_indicator.z_index = 100
	hover_indicator.hide()
	add_child(hover_indicator)
	get_window().mouse_entered.connect(_on_window_mouse_entered)
	get_window().mouse_exited.connect(_on_window_mouse_exited)

func _build_hub_blocker() -> void:
	# The card is a nonmodal map surface, but it must intercept input above the
	# paused Worker Hub when it is opened from the roster.
	_hub_blocker_layer = CanvasLayer.new()
	_hub_blocker_layer.name = "WorkerDetailsInputBlocker"
	_hub_blocker_layer.layer = 11
	add_child(_hub_blocker_layer)
	var blocker := Control.new()
	blocker.name = "Blocker"
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_hub_blocker_layer.add_child(blocker)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hub_blocker_layer.visible = false

func _input(event: InputEvent) -> void:
	# City Hub listens in _unhandled_input. Close the map card first, while
	# leaving this shortcut unhandled so City Hub can still open normally.
	if _details_source == "map" and is_instance_valid(panel) and panel.visible \
			and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_C and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		panel.close()

func _process(_delta: float) -> void:
	var viewport: Viewport = get_viewport()
	_update_hover_at(viewport.get_mouse_position(), _mouse_in_window, _gui_blocks_mouse())

func _update_hover_at(mouse_position: Vector2, mouse_in_window: bool, gui_blocked: bool) -> void:
	# Do not leave the nonmodal card above a later worksite/other modal or a
	# scene transition; opening and closing it never changes the pause state.
	if _details_source == "hub" and is_instance_valid(panel) and panel.visible:
		if not _hub_details_can_remain():
			panel.close()
		_clear_hover()
		return
	if not _can_inspect():
		if is_instance_valid(panel) and panel.visible:
			panel.close()
		_clear_hover()
		return
	var viewport: Viewport = get_viewport()
	if not mouse_in_window or not viewport.get_visible_rect().has_point(mouse_position) or gui_blocked:
		_clear_hover()
		return
	var world_point: Vector2 = viewport.get_canvas_transform().affine_inverse() * mouse_position
	var person_id: String = _person_at(world_point)
	if person_id.is_empty():
		_clear_hover()
		return
	var actor: Node2D = visuals.actors.get(person_id) as Node2D
	if not is_instance_valid(actor):
		_clear_hover()
		return
	hovered_person_id = person_id
	hover_indicator.global_position = actor.global_position
	hover_indicator.show()

func _clear_hover() -> void:
	hovered_person_id = ""
	if is_instance_valid(hover_indicator):
		hover_indicator.hide()

func _gui_blocks_mouse() -> bool:
	# A PASS control can still let a click reach _unhandled_input; only hide for
	# a STOP control in its ancestry, as with the inspection card's frame.
	var control: Control = get_viewport().gui_get_hovered_control()
	while is_instance_valid(control):
		if control.mouse_filter == Control.MOUSE_FILTER_STOP:
			return true
		control = control.get_parent() as Control
	return false

func _on_window_mouse_entered() -> void:
	_mouse_in_window = true

func _on_window_mouse_exited() -> void:
	_mouse_in_window = false
	_clear_hover()

func _unhandled_input(event: InputEvent) -> void:
	if not _can_inspect():
		return
	if event.is_action_pressed("ui_cancel") and is_instance_valid(panel) and panel.visible:
		panel.close()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var world_point: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
	var person_id: String = _person_at(world_point)
	if person_id.is_empty():
		return
	_show_details_for(person_id, "map")
	get_viewport().set_input_as_handled()

func _show_details_for(person_id: String, source: String) -> void:
	if not is_instance_valid(panel):
		return
	_details_person_id = person_id
	_details_source = source
	var from_hub: bool = source == "hub" and is_instance_valid(worker_control) and worker_control.visible
	panel.layer = 12 if from_hub else _map_panel_layer
	_hub_blocker_layer.visible = from_hub
	if from_hub:
		worker_control.set_shared_details_active(true)
	panel.open_for(person_id)
	if from_hub and panel.visible:
		panel.call("focus_primary")

func _on_worker_details_requested(worker_id: String) -> void:
	if not is_instance_valid(worker_control) or not worker_control.visible:
		return
	_show_details_for(worker_id, "hub")

func _worker_details_for(worker_id: String) -> Dictionary:
	if not is_instance_valid(worker_control):
		return {}
	for row: Dictionary in worker_control._get_worker_rows():
		if str(row.get("id", "")) == worker_id:
			return row
	return {}

func _on_shared_details_close_requested() -> void:
	if is_instance_valid(panel) and panel.visible:
		panel.close()

func _on_panel_closed() -> void:
	if _suspending_panel:
		return
	var previous_source: String = _details_source
	var previous_id: String = _details_person_id
	_details_source = ""
	_details_person_id = ""
	_action_pending = false
	_hub_blocker_layer.visible = false
	panel.layer = _map_panel_layer
	if previous_source == "hub" and is_instance_valid(worker_control):
		worker_control.set_shared_details_active(false)
		worker_control.restore_shared_details_focus(previous_id)

func _on_renew_requested(person_id: String) -> void:
	_open_worker_action(person_id, "contract")

func _on_actions_requested(person_id: String) -> void:
	_open_worker_action(person_id, "actions")

func _open_worker_action(person_id: String, action: String) -> void:
	if not is_instance_valid(panel) or not panel.visible or person_id != _details_person_id \
			or WorkerDatabase.get_worker_data(person_id) == null or not is_instance_valid(worker_control):
		return
	_action_pending = true
	_suspending_panel = true
	panel.close()
	_suspending_panel = false
	_hub_blocker_layer.visible = false
	worker_control.set_shared_details_active(false)
	if not worker_control.open_shared_worker_action(person_id, action):
		_restore_details_after_action(person_id)

func _on_shared_action_closed(worker_id: String) -> void:
	if _action_pending and worker_id == _details_person_id:
		_restore_details_after_action(worker_id)

func _restore_details_after_action(person_id: String) -> void:
	_action_pending = false
	if _details_source == "map":
		# A map-origin action temporarily opens the existing paused Worker Hub.
		# Close only that temporary owner before restoring the nonmodal card.
		_returning_to_map = true
		if is_instance_valid(worker_control) and worker_control.visible:
			worker_control.close()
		_returning_to_map = false
		if _can_inspect():
			_show_details_for(person_id, "map")
		else:
			_details_source = ""
			_details_person_id = ""
	elif _details_source == "hub" and is_instance_valid(worker_control) and worker_control.visible:
		_show_details_for(person_id, "hub")

func _on_worker_control_closed() -> void:
	if _returning_to_map:
		return
	if _action_pending or _details_source == "hub":
		_action_pending = false
		if is_instance_valid(panel) and panel.visible:
			panel.close()
		else:
			_details_source = ""
			_details_person_id = ""
			_hub_blocker_layer.visible = false

func _hub_details_can_remain() -> bool:
	if not is_instance_valid(runtime) or not runtime.is_inside_tree() \
			or not is_instance_valid(worker_control) or not worker_control.visible \
			or bool(runtime.get("checkpoint_handoff")) or not is_instance_valid(runtime.get("player")) \
			or SceneTransition.is_transitioning or _city_surface_is_open():
		return false
	var inventory_ui: CanvasLayer = runtime.get("inventory_ui") as CanvasLayer
	var worksite_inspector: Control = runtime.get("inspector") as Control
	return (not is_instance_valid(inventory_ui) or not inventory_ui.visible) \
		and (not is_instance_valid(worksite_inspector) or not worksite_inspector.visible)

func _can_inspect() -> bool:
	if not is_instance_valid(runtime) or not runtime.is_inside_tree() or not is_instance_valid(visuals):
		return false
	if bool(runtime.get("checkpoint_handoff")) or not is_instance_valid(runtime.get("player")):
		return false
	if _city_surface_is_open():
		return false
	return runtime.has_method("_can_open_worker_hub") and bool(runtime._can_open_worker_hub())

func _city_surface_is_open() -> bool:
	# City Hub and notifications do not pause the tree, but their lower canvas
	# layer must remain accessible and must not permit world-click inspection.
	for node: Node in get_tree().get_nodes_in_group("city_notification_ui"):
		var city_ui: RaidUI = node as RaidUI
		if not is_instance_valid(city_ui) or not city_ui.visible:
			continue
		for surface: Control in [city_ui.details_panel, city_ui.inspection_panel, city_ui.notifications_popup]:
			if is_instance_valid(surface) and surface.is_visible_in_tree():
				return true
	return false

func _person_at(world_point: Vector2) -> String:
	var chosen: String = ""
	var nearest: float = INF
	for id: String in visuals.actors:
		var actor: Variant = visuals.actors[id]
		if not is_instance_valid(actor) or not actor is Node2D or not actor.is_visible_in_tree():
			continue
		if not ACTOR_HIT_RECT.has_point(actor.to_local(world_point)):
			continue
		if CitizenNeedsManager.get_person_needs_summary(id).is_empty():
			continue
		var distance: float = actor.global_position.distance_squared_to(world_point)
		if distance < nearest:
			chosen = id
			nearest = distance
	return chosen
