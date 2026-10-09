extends Node2D

const STATE: Script = preload("res://scenes/traveling_merchant/merchant_state.gd")
const MENU: PackedScene = preload("res://scenes/ui/traveling_merchant_ui/traveling_merchant_ui.tscn")
const BALLOON: PackedScene = preload("res://dialogue/game_dialogue_balloon/game_dialogue_balloon.tscn")
const GREETING_DIALOGUE: DialogueResource = preload("res://dialogue/game_dialogue_conversations/traveling_merchant.dialogue")
const STATE_NAME: String = "CommonTravelingMerchant"

## Main-map playtest: show the first visit on day zero without changing the template.
@export var debug_first_day_visit: bool = false

@onready var interactable_label_component: Control = $InteractableLabelComponent
@onready var interaction_area: Area2D = $InteractionArea
var state: Node
var player: Player
var menu: CanvasLayer
var greeting_balloon: BaseGameDialogueBalloon
var _greeting_dialogue_active: bool = false
var _greeting_end_pending: bool = false
var _greeting_trade_selected: bool = false
var _dialogue_manager: Node

func _ready() -> void:
	add_to_group("traveling_merchants")
	process_mode = Node.PROCESS_MODE_ALWAYS
	state = WorkStateRuntime.get_node_or_null(STATE_NAME)
	if state == null:
		state = STATE.new()
		state.name = STATE_NAME
		if OS.is_debug_build() and debug_first_day_visit:
			state.config = state.config.duplicate(true)
			state.config.first_day = 0
		WorkStateRuntime.add_child(state)
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	state.changed.connect(_refresh)
	_dialogue_manager = get_node_or_null("/root/DialogueManager")
	if is_instance_valid(_dialogue_manager):
		_dialogue_manager.dialogue_ended.connect(_on_dialogue_ended)
	_bind_notification_ui()
	_refresh()

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player = body
		if state.is_present():
			player._on_interactable_activated(self)

func _on_body_exited(body: Node2D) -> void:
	if body == player:
		close_menu()
		_cancel_greeting()
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
	if interacting_player != player or is_instance_valid(menu) or _has_live_greeting_balloon() or not has_player_access():
		return
	if not player.can_move or player.current_interactable != self or get_tree().paused:
		return
	player.set_movement_locked(&"traveling_merchant", true)
	interactable_label_component.hide()
	_start_greeting()
	get_viewport().set_input_as_handled()

func _open_trade_menu() -> void:
	if not is_instance_valid(player) or is_instance_valid(menu) or not has_player_access():
		_release_interaction_lock()
		return
	player.set_movement_locked(&"traveling_merchant", true)
	interactable_label_component.hide()
	menu = MENU.instantiate()
	add_child(menu)
	menu.closed.connect(_on_menu_closed)
	menu.trade_requested.connect(_on_trade_requested)
	menu.open_menu(state)

func _start_greeting() -> void:
	_greeting_trade_selected = false
	_greeting_end_pending = false
	greeting_balloon = BALLOON.instantiate() as BaseGameDialogueBalloon
	if not is_instance_valid(greeting_balloon):
		_release_interaction_lock()
		return
	add_child(greeting_balloon)
	_fit_greeting_to_viewport()
	greeting_balloon.speaker_chat_box_vertical_offset = 0.0
	# Limit speaker bounds to the NPC sprites, excluding the balloon progress icon.
	greeting_balloon.start(GREETING_DIALOGUE, "traveling_merchant_greeting", [$MerchantVisual, self])

func _fit_greeting_to_viewport() -> void:
	# Reuse the existing balloon artwork; its generic defaults exceed 400x225.
	var root: Control = greeting_balloon.chat_box_root
	root.custom_minimum_size = Vector2(176, 60)
	root.size = root.custom_minimum_size
	var panel: Control = root.get_node("TemplateDialogue")
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2.ZERO
	panel.size = Vector2(176, 60)
	panel.scale = Vector2.ONE
	greeting_balloon.dialogue_label.add_theme_constant_override("line_separation", 2)
	var responses: Control = greeting_balloon.responses_menu
	responses.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	responses.offset_left = -45.0
	responses.offset_right = 45.0
	responses.offset_top = -16.0
	responses.offset_bottom = 16.0
	var choice: Button = responses.get_node("ResponseExample")
	choice.custom_minimum_size = Vector2(90, 14)
	choice.add_theme_font_size_override("font_size", 6)

func merchant_dialogue_started() -> void:
	if _greeting_dialogue_active or not _has_live_greeting_balloon():
		return
	_greeting_dialogue_active = true
	BaseDialogueManager.dialogue_activated.emit()
	TimeComponentManager.toggle_pause()

func merchant_select_trade() -> void:
	_greeting_trade_selected = true

func merchant_select_leave() -> void:
	_greeting_trade_selected = false

func merchant_dialogue_finished() -> void:
	if not _greeting_dialogue_active:
		return
	_greeting_dialogue_active = false
	BaseDialogueManager.dialogue_deactivated.emit()
	if not is_instance_valid(player) or not player.is_inside_tree():
		TimeComponentManager.is_paused = false

func _on_dialogue_ended(resource: DialogueResource) -> void:
	if resource != GREETING_DIALOGUE or not _has_live_greeting_balloon() or _greeting_end_pending:
		return
	_greeting_end_pending = true
	_finish_greeting_after_dialogue.call_deferred()

func _finish_greeting_after_dialogue() -> void:
	var completed_balloon: BaseGameDialogueBalloon = greeting_balloon
	await get_tree().process_frame
	if greeting_balloon != completed_balloon:
		return
	greeting_balloon = null
	_greeting_end_pending = false
	if _greeting_dialogue_active:
		merchant_dialogue_finished()
	if _greeting_trade_selected and _can_continue_interaction():
		_greeting_trade_selected = false
		_open_trade_menu()
		return
	_greeting_trade_selected = false
	_release_interaction_lock()

func _can_continue_interaction() -> bool:
	return is_instance_valid(player) and has_player_access() and player.current_interactable == self and not get_tree().paused

func _has_live_greeting_balloon() -> bool:
	return is_instance_valid(greeting_balloon) and not greeting_balloon.is_queued_for_deletion()

func _cancel_greeting() -> void:
	_greeting_end_pending = false
	_greeting_trade_selected = false
	if _has_live_greeting_balloon():
		greeting_balloon.queue_free()
	greeting_balloon = null
	if _greeting_dialogue_active:
		merchant_dialogue_finished()
	_release_interaction_lock()

func _release_interaction_lock() -> void:
	if is_instance_valid(player):
		player.set_movement_locked(&"traveling_merchant", false)
		if has_player_access() and player.current_interactable == self and not is_instance_valid(menu):
			interactable_label_component.show()

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
	$VisitNotice.hide()
	_bind_notification_ui()
	$Caption.text = "Traveling Merchant" if present else "Merchant Stop"
	if not present:
		close_menu()
		_cancel_greeting()
		interactable_label_component.hide()
		if is_instance_valid(player):
			player._on_interactable_deactivated(self)
	elif is_instance_valid(player) and has_player_access():
		player._on_interactable_activated(self)
		if is_instance_valid(menu):
			interactable_label_component.hide()

func _bind_notification_ui() -> void:
	var notification_ui: Node = get_tree().get_first_node_in_group("city_notification_ui")
	if is_instance_valid(notification_ui) and notification_ui.has_method("bind_merchant_state"):
		notification_ui.call("bind_merchant_state", state)

func _process(_delta: float) -> void:
	# Catch collapse, fades and teleports even when no physics exit has fired yet.
	if (is_instance_valid(menu) or _has_live_greeting_balloon()) and (not has_player_access() or get_tree().paused):
		close_menu()
		_cancel_greeting()

func close_menu() -> void:
	if is_instance_valid(menu):
		menu.close_menu()

func _on_menu_closed() -> void:
	menu = null
	_release_interaction_lock()

func _exit_tree() -> void:
	close_menu()
	_cancel_greeting()
	if is_instance_valid(_dialogue_manager):
		var ended_callable: Callable = Callable(self, "_on_dialogue_ended")
		if _dialogue_manager.dialogue_ended.is_connected(ended_callable):
			_dialogue_manager.dialogue_ended.disconnect(ended_callable)
	if is_instance_valid(player) and player.is_inside_tree():
		player.set_movement_locked(&"traveling_merchant", false)
		player._on_interactable_deactivated(self)
