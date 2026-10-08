extends Node2D

## One physical access point for wall work; the persistent HUD remains read-only.
@onready var interactable_label_component: Control = $InteractableLabelComponent
@onready var interaction_area: Area2D = $InteractionArea
var player: Player

func _ready() -> void:
	add_to_group("wall_management_spots")
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player = body
		player._on_interactable_activated(self)

func _on_body_exited(body: Node2D) -> void:
	if body == player:
		_close_management()
		player._on_interactable_deactivated(self)
		player = null

func has_player_access() -> bool:
	if not is_instance_valid(player) or not player.is_inside_tree():
		return false
	if not player.can_move or player.current_interactable != self or player.is_sleeping or player.is_collapsing:
		return false
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return false
	var shape: CollisionShape2D = $InteractionArea/CollisionShape2D
	var body_shape: CollisionShape2D = player.get_node("CollisionShape2D")
	# The geometry check rejects a click immediately after teleport, before body_exited.
	return not shape.disabled and not body_shape.disabled and interaction_area.overlaps_body(player) and shape.shape.collide(shape.global_transform, body_shape.shape, body_shape.global_transform)

func on_player_interact(interacting_player: Player) -> void:
	if interacting_player != player or not has_player_access():
		return
	var ui: Node = _get_ui()
	if ui != null:
		ui.open_management(self)
		get_viewport().set_input_as_handled()

func _get_ui() -> Node:
	return WorkStateRuntime.get_node_or_null("CityRaid/RaidUI")

func _close_management() -> void:
	var ui: Node = _get_ui()
	if ui != null:
		ui.close_management(self)

func _exit_tree() -> void:
	_close_management()
	if is_instance_valid(player):
		player._on_interactable_deactivated(self)
