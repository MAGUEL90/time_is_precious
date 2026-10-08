extends Node2D

## Wall caretaker: dialogue requests work; the persistent HUD remains read-only.
const BALLOON: PackedScene = preload("res://dialogue/game_dialogue_balloon/game_dialogue_balloon.tscn")
const DIALOGUE: DialogueResource = preload("res://dialogue/game_dialogue_conversations/wall_caretaker.dialogue")
var greeting_balloon: BaseGameDialogueBalloon
var _work_selected: bool = false
var _end_pending: bool = false
var _dialogue_manager: Node
@onready var interactable_label_component: Control = $InteractableLabelComponent
@onready var interaction_area: Area2D = $InteractionArea
var player: Player

func _ready() -> void:
	add_to_group("wall_management_spots")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_dialogue_manager = get_node("/root/DialogueManager")
	_dialogue_manager.dialogue_ended.connect(_on_dialogue_ended)
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player = body
		player._on_interactable_activated(self)

func _on_body_exited(body: Node2D) -> void:
	if body == player:
		_cancel_greeting()
		player._on_interactable_deactivated(self)
		player = null

func has_player_access() -> bool:
	if not is_instance_valid(player) or not player.is_inside_tree():
		return false
	if player.current_interactable != self or player.is_sleeping or player.is_collapsing:
		return false
	if get_tree().paused or TimeComponentManager.is_paused or SceneTransition.is_transitioning:
		return false
	var shape: CollisionShape2D = $InteractionArea/CollisionShape2D
	var body_shape: CollisionShape2D = player.get_node("CollisionShape2D")
	# The geometry check rejects a click immediately after teleport, before body_exited.
	return not shape.disabled and not body_shape.disabled and interaction_area.overlaps_body(player) and shape.shape.collide(shape.global_transform, body_shape.shape, body_shape.global_transform)

func on_player_interact(interacting_player: Player) -> void:
	if interacting_player != player or not has_player_access() or not player.can_move or _has_live_greeting_balloon():
		return
	_work_selected = false
	_end_pending = false
	player.set_movement_locked(&"wall_npc", true)
	interactable_label_component.hide()
	greeting_balloon = BALLOON.instantiate()
	add_child(greeting_balloon)
	_fit_dialogue()
	greeting_balloon.speaker_chat_box_vertical_offset = 0.0
	greeting_balloon.start(DIALOGUE, "wall_caretaker", [$CaretakerVisual, self])
	set_process(true)
	get_viewport().set_input_as_handled()

func wall_is_attacking() -> bool:
	var state: Node = WorkStateRuntime.get_node_or_null("CityRaid")
	return state != null and state.phase == "attacking"

func wall_work_available() -> bool:
	var state: Node = WorkStateRuntime.get_node_or_null("CityRaid")
	if state == null:
		return false
	var status: Dictionary = state.get_status()
	return bool(status.get("can_build", false)) or bool(status.get("can_repair", false))

func wall_select_work() -> void:
	_work_selected = _has_live_greeting_balloon() and has_player_access() and wall_work_available()

func wall_select_leave() -> void:
	_work_selected = false

func _on_dialogue_ended(resource: DialogueResource) -> void:
	if resource != DIALOGUE or not _has_live_greeting_balloon() or _end_pending:
		return
	_end_pending = true
	_finish_dialogue.call_deferred()

func _finish_dialogue() -> void:
	var completed: BaseGameDialogueBalloon = greeting_balloon
	await get_tree().process_frame
	if greeting_balloon != completed:
		return
	var requested: bool = _work_selected
	greeting_balloon = null
	_work_selected = false
	_end_pending = false
	_release_lock()
	set_process(false)
	# Revalidate after the response, since raids and player availability may change.
	if requested and has_player_access() and player.can_move:
		var state: Node = WorkStateRuntime.get_node_or_null("CityRaid")
		if state != null:
			if bool(state.get_status().get("can_build", false)):
				state.build_wall()
			elif state.can_repair_wall():
				state.repair_wall()

func _has_live_greeting_balloon() -> bool:
	return is_instance_valid(greeting_balloon) and not greeting_balloon.is_queued_for_deletion()

func _process(_delta: float) -> void:
	if not has_player_access():
		_cancel_greeting()

func _cancel_greeting() -> void:
	_work_selected = false
	_end_pending = false
	if is_instance_valid(greeting_balloon):
		greeting_balloon.queue_free()
	greeting_balloon = null
	_release_lock()
	set_process(false)

func _release_lock() -> void:
	if is_instance_valid(player):
		player.set_movement_locked(&"wall_npc", false)
		if player.is_inside_tree() and has_player_access() and player.can_move:
			interactable_label_component.show()

func _fit_dialogue() -> void:
	# Match the existing merchant balloon's 400x225 layout.
	var root: Control = greeting_balloon.chat_box_root
	root.custom_minimum_size = Vector2(196, 66)
	root.size = root.custom_minimum_size
	var panel: Control = root.get_node("TemplateDialogue")
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2.ZERO
	panel.size = root.custom_minimum_size
	panel.scale = Vector2.ONE
	var portrait: Node2D = preload("res://scenes/worker_visual/base_worker_visual.tscn").instantiate()
	portrait.skin_tone = $CaretakerVisual.skin_tone
	portrait.hair_style = $CaretakerVisual.hair_style
	portrait.clothes_id = $CaretakerVisual.clothes_id
	portrait.default_direction = "right"
	portrait.position = Vector2(20, 20)
	portrait.scale = Vector2(1.25, 1.25)
	panel.get_node("TexturePhoto").add_child(portrait)
	greeting_balloon.dialogue_label.add_theme_constant_override("line_separation", 2)
	var responses: Control = greeting_balloon.responses_menu
	responses.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	responses.offset_left = -65.0
	responses.offset_right = 65.0
	responses.offset_top = -16.0
	responses.offset_bottom = 16.0
	var choice: Button = responses.get_node("ResponseExample")
	choice.custom_minimum_size = Vector2(130, 14)
	choice.add_theme_font_size_override("font_size", 6)

func _exit_tree() -> void:
	_cancel_greeting()
	if is_instance_valid(_dialogue_manager):
		_dialogue_manager.dialogue_ended.disconnect(_on_dialogue_ended)
	if is_instance_valid(player):
		player._on_interactable_deactivated(self)
