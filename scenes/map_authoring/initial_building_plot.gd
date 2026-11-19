extends "res://scenes/citizen_house_plot/citizen_house_plot.gd"

## Authored land with a building choice; fixed legacy plots keep their own rules.
const BUILDING_MENU: PackedScene = preload("res://scenes/ui/building_selection_ui/building_selection_ui.tscn")
const PLOT_RULES = preload("res://scenes/map_authoring/plot_interaction_rules.gd")

## Scene-authored classification, not a runtime quest flag or saved player choice.
## Existing scenes default to General; no authored layout needs to be rewritten.
@export_enum("General", "Story / NPC") var plot_purpose: int = PLOT_RULES.Purpose.GENERAL

func _ready() -> void:
	# Copy only the existing workshop solid body; never enter its production backend.
	var detached: Node = WORKSHOP.instantiate()
	var body: Node = detached.get_node("StaticBody2D").duplicate()
	body.name = "WorkshopBody"
	detached.free()
	add_child(body)
	body.get_node("CollisionShape2D").disabled = true
	super._ready()

func get_built_footprints() -> Array[Rect2]:
	if is_instance_valid(construction) and construction.is_selected_workshop():
		var shape: CollisionShape2D = $WorkshopBody/CollisionShape2D
		return [($WorkshopBody.transform * shape.transform) * shape.shape.get_rect()]
	return super.get_built_footprints()

func get_plot_interaction_step() -> int:
	if not is_instance_valid(construction):
		return PLOT_RULES.Step.NONE
	return PLOT_RULES.get_interaction_step(plot_purpose, construction.phase)

func allows_building_selection() -> bool:
	# Persistent state capability stays stable; permission belongs to plot rules.
	return true

func has_player_access() -> bool:
	return get_plot_interaction_step() != PLOT_RULES.Step.NONE and super.has_player_access()

func _on_body_entered(body: Node2D) -> void:
	if get_plot_interaction_step() != PLOT_RULES.Step.NONE:
		super._on_body_entered(body)

func is_citizen_house_plot() -> bool:
	# This is the authored binding kind. The state owns the committed choice.
	return false

func _sync_construction() -> void:
	super._sync_construction()
	var workshop: bool = construction.building_kind == "mudbrick_workshop"
	var built: bool = construction.phase == "built"
	$FinishedClayWorkshop.visible = workshop and built
	$FinishedHouse.visible = not workshop and built
	$HouseBody/CollisionShape2D.set_deferred("disabled", workshop or not built)
	$WorkshopBody/CollisionShape2D.set_deferred("disabled", not workshop or not built)
	if construction.building_kind != "house" or construction.phase != "building":
		$SiteHouse.hide()
	if get_plot_interaction_step() == PLOT_RULES.Step.NONE:
		_set_plot_monitoring(false)
		close_menu()
		interactable_label_component.hide()
		if is_instance_valid(player):
			player._on_interactable_deactivated(self)

func on_player_interact(interacting_player: Player) -> void:
	match get_plot_interaction_step():
		PLOT_RULES.Step.CLEAR, PLOT_RULES.Step.BUILD:
			super.on_player_interact(interacting_player)
		PLOT_RULES.Step.CHOOSE_BUILDING:
			_open_building_menu(interacting_player)

func _open_building_menu(interacting_player: Player) -> void:
	if _manual_clearing or interacting_player != player or is_instance_valid(menu) or not has_player_access():
		return
	if not player.can_move or player.current_interactable != self or get_tree().paused:
		return
	# Reuse the construction modal's ownership and close path, including scene exit.
	_previous_paused = get_tree().paused
	player.set_movement_locked(&"workshop_plot", true)
	interactable_label_component.hide()
	menu = BUILDING_MENU.instantiate()
	_menu_session_player = player
	_menu_session_scene = get_tree().current_scene
	_menu_session_menu = menu
	add_child(menu)
	menu.closed.connect(_on_menu_closed.bind(menu))
	menu.house_requested.connect(_on_house_requested)
	menu.workshop_requested.connect(_on_workshop_requested)
	menu.workshop_available = construction.can_choose_workshop()
	menu.workshop_enabled = construction.INITIAL_WORKSHOP_SELECTION_ENABLED
	get_tree().paused = true
	var marker: Node = get_node_or_null(authored_marker_path)
	var plot_label: String = "Plot " + str(marker.name).trim_prefix("ToBeClean") if marker != null else "Building plot"
	menu.open_menu(plot_label)
	get_viewport().set_input_as_handled()

func _on_house_requested() -> void:
	_open_construction_preview("house")

func _on_workshop_requested() -> void:
	_open_construction_preview("mudbrick_workshop")

func _open_construction_preview(kind: String) -> void:
	if not is_instance_valid(menu) or menu.get_scene_file_path() != BUILDING_MENU.resource_path or not has_player_access() or get_plot_interaction_step() != PLOT_RULES.Step.CHOOSE_BUILDING:
		return
	close_menu()
	if not construction.begin_building_preview(kind):
		return
	super.on_player_interact(player)
	if not is_instance_valid(menu):
		construction.clear_building_preview()

func _on_menu_closed(closed_menu: CanvasLayer) -> void:
	super._on_menu_closed(closed_menu)
	if is_instance_valid(construction):
		construction.clear_building_preview()

func _on_build_requested(ids: Array[String]) -> void:
	if is_instance_valid(construction) and construction.is_citizen_house():
		super._on_build_requested(ids)

func _on_player_build_requested() -> void:
	if is_instance_valid(construction) and construction.allows_player_construction():
		super._on_player_build_requested()

func _on_player_resume_requested() -> void:
	if is_instance_valid(construction) and (construction.phase == "clearing" or (construction.phase == "building" and construction.building_kind in ["house", "mudbrick_workshop"])):
		super._on_player_resume_requested()
