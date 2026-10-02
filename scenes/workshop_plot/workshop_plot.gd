extends Node2D

## Fixed authored plot. Construction state outlives this map under WorkStateRuntime.
const PLOT_MENU: PackedScene = preload("res://scenes/ui/workshop_plot_ui/workshop_plot_ui.tscn")
const CONSTRUCTION_STATE: Script = preload("res://scenes/workshop_plot/workshop_construction_state.gd")
const WORKSHOP: PackedScene = preload("res://scenes/workshop/workshop.tscn")
const HAND_ICON: Texture2D = preload("res://assets/ui/ui_icon/hand_job_icon.png")
const HAMMER_ICON: Texture2D = preload("res://assets/items/stone_hammer.png")
const BUILT_PLOT: Texture2D = preload("res://assets/ui/building/plot_level_1.png")
const BUILT_BOARD: Texture2D = preload("res://assets/objects/object_board_1.png")

## Stable unique identity for this authored plot across map reloads.
@export var plot_id: String = ""

@onready var interaction_area: Area2D = $InteractableComponent
@onready var interactable_label_component: TextureRect = $InteractableLabelComponent

var player: Player
var menu: CanvasLayer
var construction: Node
var _previous_can_move: bool = true
var _previous_paused: bool = false
var _manual_clearing: bool = false
signal clearing_finished

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("workshop_plots")
	# The authored board anchors both construction and completed-workshop access.
	interaction_area.position = $Board.position + $Board.offset
	$InteractableComponent/CollisionShape2D.position = Vector2.ZERO
	interactable_label_component.position = interaction_area.position + Vector2(-8, -26)
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	var identity: String = plot_id if not plot_id.is_empty() else str(name)
	if identity == "WorkshopPlot":
		identity = "main_workshop"
	var state_name: String = "MainWorkshopConstruction" if identity == "main_workshop" else "WorkshopConstruction_" + identity.sha256_text()
	construction = WorkStateRuntime.get_node_or_null(state_name)
	if construction == null:
		construction = CONSTRUCTION_STATE.new()
		construction.name = state_name
		construction.order_id = "construction:" + identity
		WorkStateRuntime.add_child(construction)
	construction.changed.connect(_sync_construction)
	_sync_construction()

func _on_body_entered(body: Node2D) -> void:
	if body is Player and construction.phase != "built":
		player = body
		player._on_interactable_activated(self)

func _on_body_exited(body: Node2D) -> void:
	if body == player:
		close_menu()
		player._on_interactable_deactivated(self)

func has_player_access() -> bool:
	if construction == null or construction.phase == "built":
		return false
	if not is_instance_valid(player) or not player.is_inside_tree():
		return false
	if player.is_sleeping or player.is_collapsing or SceneTransition.is_transitioning:
		return false
	var shape: CollisionShape2D = $InteractableComponent/CollisionShape2D
	var player_shape: CollisionShape2D = player.get_node("CollisionShape2D")
	# Match the body's overlap that displays the prompt, not the Player origin.
	# Check current transforms too: physics overlap lists can be stale while paused.
	return not shape.disabled and not player_shape.disabled and interaction_area.overlaps_body(player) and shape.shape.collide(shape.global_transform, player_shape.shape, player_shape.global_transform)

func on_player_interact(interacting_player: Player) -> void:
	if interacting_player != player or is_instance_valid(menu) or not has_player_access():
		return
	if not player.can_move or player.current_interactable != self or get_tree().paused:
		return
	_previous_can_move = player.can_move
	_previous_paused = get_tree().paused
	player.can_move = false
	player.velocity = Vector2.ZERO
	interactable_label_component.hide()
	menu = PLOT_MENU.instantiate()
	add_child(menu)
	menu.closed.connect(_on_menu_closed)
	menu.build_requested.connect(_on_build_requested)
	menu.clearing_requested.connect(_on_clearing_requested)
	get_tree().paused = true
	menu.open_menu(construction)
	get_viewport().set_input_as_handled()

func _on_build_requested(ids: Array[String]) -> void:
	if not is_instance_valid(menu) or not has_player_access():
		close_menu()
		return
	var result: Dictionary = construction.start_build(ids)
	if bool(result.get("success", false)):
		close_menu()
	else:
		menu.show_error(str(result.get("message", "Could not start construction.")))

func _sync_construction() -> void:
	$ToBeClean.visible = construction.phase in ["uncleared", "clearing"]
	$TableResources.visible = construction.phase == "built"
	$InteractableLabelComponent/HammerIcon.texture = HAND_ICON if construction.phase in ["uncleared", "clearing"] else HAMMER_ICON
	if construction.phase == "built":
		close_menu()
		interactable_label_component.hide()
		interaction_area.set_deferred("monitoring", false)
		if is_instance_valid(player):
			player._on_interactable_deactivated(self)
		# Regions retain the complete authored texture while sorting rear wall,
		# side posts and table at their own ground contact points.
		for art: Sprite2D in [$Plot, $LeftWall, $LeftWallTop, $RightWall, $RightWallTop, $Table, $TableLegs]:
			art.texture = BUILT_PLOT
		$Board.texture = BUILT_BOARD
		$Label.text = "Workshop"
		if not has_node("BuiltWorkshop"):
			var workshop: WorkShop = WORKSHOP.instantiate()
			workshop.name = "BuiltWorkshop"
			workshop.set_meta("interaction_highlight_root", self)
			# Keep the existing production/claim backend; this plot owns its artwork.
			workshop.get_node("Sprite2D").hide()
			workshop.get_node("InteractableComponent").position = interaction_area.position
			workshop.get_node("InteractableComponent/CollisionShape2D").shape = $InteractableComponent/CollisionShape2D.shape.duplicate()
			var prompt: InteractableLabelComponent = workshop.get_node("InteractableLabelComponent")
			prompt.position_offset = interactable_label_component.position
			prompt.size = Vector2(16, 16)
			add_child(workshop)
			_show_table_resource(workshop)
	elif construction.phase == "clearing":
		var preview: Dictionary = construction.get_clearing_preview([] as Array[String], false)
		$Label.text = "Clearing %d%%" % roundi(float(preview.progress_ratio) * 100.0)
	elif construction.phase == "building":
		var preview: Dictionary = construction.get_preview([] as Array[String])
		$Label.text = "Building %d%%" % roundi(float(preview.progress_ratio) * 100.0)
	else:
		$Label.text = "Bekas Workshop" if construction.phase == "uncleared" else "Workshop Site"

func _show_table_resource(workshop: WorkShop) -> void:
	# Sprite positions/scales belong to the authored scene. Recipes swap only
	# the texture, so arranging these preview icons works for every material.
	$TableResources.hide()
	if workshop.available_jobs.is_empty() or workshop.available_jobs[0] == null:
		return
	var job: JobData = workshop.available_jobs[0]
	if job.inputs.is_empty():
		return
	var item = ItemDatabase.get_item_data(job.inputs.keys()[0])
	if item == null:
		return
	for prop: Node in $TableResources.get_children():
		if prop is Sprite2D:
			prop.texture = item.icon
	$TableResources.show()

func _process(_delta: float) -> void:
	if not _manual_clearing and is_instance_valid(menu) and not has_player_access():
		close_menu()

func _on_clearing_requested(ids: Array[String], use_player: bool) -> void:
	if _manual_clearing or not is_instance_valid(menu) or not has_player_access():
		return
	if use_player and (player.has_critical_condition() or TimeComponentManager.is_paused):
		menu.show_error("Recover before working, and resume time.")
		return
	var result: Dictionary = construction.start_clearing(ids, use_player)
	if not result.success:
		menu.show_error(result.message)
		return
	if not use_player:
		close_menu()
		return
	_manual_clearing = true
	menu.hide()
	var cover := CanvasLayer.new()
	cover.layer = 90
	var shade := ColorRect.new()
	shade.color = Color.BLACK
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.add_child(shade)
	add_child(cover)
	await get_tree().create_timer(0.15, true).timeout
	# Match manual worksites: existing minute signals charge needs exactly once.
	# Restore movement only during synchronous ticks so collapse remembers its prior state.
	player.can_move = _previous_can_move
	while construction.phase == "clearing" and is_inside_tree() and not is_queued_for_deletion():
		if not has_player_access() or player.has_critical_condition():
			break
		TimeComponentManager.advance_minutes(1)
	construction.interrupt_player_clearing()
	player.can_move = false
	await get_tree().create_timer(0.5, true).timeout
	cover.queue_free()
	_manual_clearing = false
	close_menu()
	clearing_finished.emit()



func close_menu() -> void:
	if is_instance_valid(menu):
		menu.close_menu()

func _on_menu_closed() -> void:
	menu = null
	get_tree().paused = _previous_paused
	if is_instance_valid(player):
		player.can_move = _previous_can_move and not player.is_sleeping and not player.is_collapsing and not SceneTransition.is_transitioning
		if has_player_access() and player.current_interactable == self:
			interactable_label_component.show()

func _exit_tree() -> void:
	if _manual_clearing and is_instance_valid(construction):
		construction.interrupt_player_clearing()
	close_menu()
	if is_instance_valid(player) and player.is_inside_tree():
		player._on_interactable_deactivated(self)
