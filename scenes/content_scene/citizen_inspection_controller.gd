extends Node

## The existing resident/worker visual owner maps a person ID to one moving
## actor. Hit-test its visible sprite area without adding physics bodies.
const PANEL: PackedScene = preload("res://scenes/ui/citizen_inspection/citizen_inspection_panel.tscn")
const ACTOR_HIT_RECT: Rect2 = Rect2(-10, -16, 20, 32)

var runtime: Node
var visuals: Node
var panel: CanvasLayer

func configure(worksite: Node, visual_owner: Node) -> void:
	runtime = worksite
	visuals = visual_owner

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PANEL.instantiate()
	panel.name = "CitizenInspectionPanel"
	panel.summary_provider = Callable(CitizenNeedsManager, "get_person_needs_summary")
	add_child(panel)

func _process(_delta: float) -> void:
	# Do not leave the nonmodal card above a later worksite/other modal or a
	# scene transition; opening and closing it never changes the pause state.
	if is_instance_valid(panel) and panel.visible and not _can_inspect():
		panel.close()

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
	panel.open_for(person_id)
	get_viewport().set_input_as_handled()

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
