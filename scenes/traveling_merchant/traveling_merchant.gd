extends Node2D

const STATE: Script = preload("res://scenes/traveling_merchant/merchant_state.gd")
const MENU: PackedScene = preload("res://scenes/ui/traveling_merchant_ui/traveling_merchant_ui.tscn")
const STATE_NAME: String = "CommonTravelingMerchant"

@onready var interactable_label_component: Control = $InteractableLabelComponent
@onready var interaction_area: Area2D = $InteractionArea
var state: Node
var player: Player
var menu: CanvasLayer

func _ready() -> void:
	add_to_group("traveling_merchants")
	process_mode = Node.PROCESS_MODE_ALWAYS
	state = WorkStateRuntime.get_node_or_null(STATE_NAME)
	if state == null:
		state = STATE.new()
		state.name = STATE_NAME
		WorkStateRuntime.add_child(state)
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	state.changed.connect(_refresh)
	_refresh()

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player = body
		if state.is_present():
			player._on_interactable_activated(self)

func _on_body_exited(body: Node2D) -> void:
	if body == player:
		close_menu()
		player._on_interactable_deactivated(self)
		player = null

func has_player_access() -> bool:
	if not state.is_present() or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	if player.is_sleeping or player.is_collapsing or SceneTransition.is_transitioning:
		return false
	var shape: CollisionShape2D = $InteractionArea/CollisionShape2D
	var body_shape: CollisionShape2D = player.get_node("CollisionShape2D")
	return not shape.disabled and not body_shape.disabled and interaction_area.overlaps_body(player) and shape.shape.collide(shape.global_transform, body_shape.shape, body_shape.global_transform)

func on_player_interact(interacting_player: Player) -> void:
	if interacting_player != player or is_instance_valid(menu) or not has_player_access():
		return
	if not player.can_move or player.current_interactable != self or get_tree().paused:
		return
	player.set_movement_locked(&"traveling_merchant", true)
	interactable_label_component.hide()
	menu = MENU.instantiate()
	add_child(menu)
	menu.closed.connect(_on_menu_closed)
	menu.trade_requested.connect(_on_trade_requested)
	menu.open_menu(state)
	get_viewport().set_input_as_handled()

func _on_trade_requested(item_id: String, quantity: int, buying: bool) -> void:
	if not is_instance_valid(menu):
		return
	if not has_player_access() or get_tree().paused:
		close_menu()
		return
	var result: Dictionary = state.trade(item_id, quantity, buying)
	if is_instance_valid(menu):
		menu.show_result(result.message)

func _refresh() -> void:
	var present: bool = state.is_present()
	$MerchantVisual.visible = present
	$VisitNotice/Label.text = state.get_status_text()
	$Caption.text = "Traveling Merchant" if present else "Merchant Stop"
	if not present:
		close_menu()
		interactable_label_component.hide()
		if is_instance_valid(player):
			player._on_interactable_deactivated(self)
	elif is_instance_valid(player) and has_player_access():
		player._on_interactable_activated(self)
		if is_instance_valid(menu):
			interactable_label_component.hide()

func _process(_delta: float) -> void:
	# Catch collapse, fades and teleports even when no physics exit has fired yet.
	if is_instance_valid(menu) and (not has_player_access() or get_tree().paused):
		close_menu()

func close_menu() -> void:
	if is_instance_valid(menu):
		menu.close_menu()

func _on_menu_closed() -> void:
	menu = null
	if is_instance_valid(player):
		player.set_movement_locked(&"traveling_merchant", false)
		if has_player_access() and player.current_interactable == self:
			interactable_label_component.show()

func _exit_tree() -> void:
	close_menu()
	if is_instance_valid(player) and player.is_inside_tree():
		player.set_movement_locked(&"traveling_merchant", false)
		player._on_interactable_deactivated(self)
