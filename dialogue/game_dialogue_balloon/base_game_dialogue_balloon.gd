class_name BaseGameDialogueBalloon extends CanvasLayer
## A basic dialogue balloon for use with Dialogue Manager.

## The dialogue resource
@export var dialogue_resource: DialogueResource

## Start from a given title when using balloon as a [Node] in a scene.
@export var start_from_title: String = ""

## If running as a [Node] in a scene then auto start the dialogue.
@export var auto_start: bool = false

## The action to use for advancing the dialogue
@export var next_action: StringName = &"ui_accept"

## The action to use to skip typing the dialogue
@export var skip_action: StringName = &"ui_cancel"

@export var speaker_head_gap: float = 8.0
@export var speaker_chat_box_vertical_offset: float = 48.0
@export var fallback_speaker_head_offset: Vector2 = Vector2(0, -24)
@export var screen_margin: float = 4.0

## A sound player for voice lines (if they exist).
@onready var audio_stream_player: AudioStreamPlayer = %AudioStreamPlayer

## Temporary game states
var temporary_game_states: Array = []
var speaker_node: Node2D

## See if we are waiting for the player
var is_waiting_for_input: bool = false
var is_waiting_to_show_responses: bool = false

## See if we are running a long mutation and should hide the balloon
var will_hide_balloon: bool = false

## A dictionary to store any ephemeral variables
var locals: Dictionary = {}

var _locale: String = TranslationServer.get_locale()

## The current line
var dialogue_line: DialogueLine:
	set(value):
		if value:
			dialogue_line = value
			apply_dialogue_line()
		else:
			# The dialogue has finished so close the balloon
			if owner == null:
				queue_free()
			else:
				hide()
	get:
		return dialogue_line

## A cooldown timer for delaying the balloon hide when encountering a mutation.
var mutation_cooldown: Timer = Timer.new()

## The base balloon anchor
@onready var balloon: Control = %Balloon

@onready var chat_box_root: Control = $Balloon/BottomCornerContainer/ChatBoxRoot

## The label showing the name of the currently speaking character
@onready var character_label: RichTextLabel = %CharacterLabel

## The label showing the currently spoken dialogue
@onready var dialogue_label: DialogueLabel = %DialogueLabel

## The menu of responses
@onready var responses_menu: DialogueResponsesMenu = %ResponsesMenu

## Indicator to show that player can progress dialogue.
@onready var progress: CanvasItem = %Progress


func _ready() -> void:
	balloon.hide()
	chat_box_root.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	chat_box_root.size = chat_box_root.custom_minimum_size
	Engine.get_singleton("DialogueManager").mutated.connect(_on_mutated)

	# If the responses menu doesn't have a next action set, use this one
	if responses_menu.next_action.is_empty():
		responses_menu.next_action = next_action

	mutation_cooldown.timeout.connect(_on_mutation_cooldown_timeout)
	add_child(mutation_cooldown)

	if auto_start:
		if not is_instance_valid(dialogue_resource):
			assert(false, DMConstants.get_error_message(DMConstants.ERR_MISSING_RESOURCE_FOR_AUTOSTART))
		start()


func _process(_delta: float) -> void:
	if is_instance_valid(dialogue_line):
		progress.visible = not dialogue_label.is_typing and (dialogue_line.responses.size() == 0 or is_waiting_to_show_responses) and not dialogue_line.has_tag("voice")
		if chat_box_root.visible:
			position_chat_box()


func _unhandled_input(_event: InputEvent) -> void:
	# Only the balloon is allowed to handle input while it's showing
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	## Detect a change of locale and update the current dialogue line to show the new language
	if what == NOTIFICATION_TRANSLATION_CHANGED and _locale != TranslationServer.get_locale() and is_instance_valid(dialogue_label):
		_locale = TranslationServer.get_locale()
		var visible_ratio = dialogue_label.visible_ratio
		dialogue_line = await dialogue_resource.get_next_dialogue_line(dialogue_line.id)
		if visible_ratio < 1:
			dialogue_label.skip_typing()


## Start some dialogue
func start(with_dialogue_resource: DialogueResource = null, title: String = "", extra_game_states: Array = []) -> void:
	temporary_game_states = [self] + extra_game_states
	speaker_node = find_speaker_node(extra_game_states)
	is_waiting_for_input = false
	is_waiting_to_show_responses = false
	if is_instance_valid(with_dialogue_resource):
		dialogue_resource = with_dialogue_resource
	if not title.is_empty():
		start_from_title = title
	dialogue_line = await dialogue_resource.get_next_dialogue_line(start_from_title, temporary_game_states)
	show()


## Apply any changes to the balloon given a new [DialogueLine].
func apply_dialogue_line() -> void:
	mutation_cooldown.stop()

	progress.hide()
	is_waiting_for_input = false
	is_waiting_to_show_responses = false
	balloon.focus_mode = Control.FOCUS_ALL
	balloon.grab_focus()

	character_label.visible = not dialogue_line.character.is_empty()
	character_label.text = tr(dialogue_line.character, "dialogue")

	dialogue_label.hide()
	dialogue_label.dialogue_line = dialogue_line

	responses_menu.hide()
	responses_menu.responses = dialogue_line.responses
	chat_box_root.show()

	# Show our balloon
	balloon.show()
	position_chat_box()
	will_hide_balloon = false

	dialogue_label.show()
	if not dialogue_line.text.is_empty():
		dialogue_label.type_out()
		await dialogue_label.finished_typing

	# Wait for next line
	if dialogue_line.has_tag("voice"):
		audio_stream_player.stream = load(dialogue_line.get_tag_value("voice"))
		audio_stream_player.play()
		await audio_stream_player.finished
		next(dialogue_line.next_id)
	elif dialogue_line.responses.size() > 0:
		is_waiting_for_input = true
		is_waiting_to_show_responses = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()
	elif dialogue_line.time != "":
		var time = dialogue_line.text.length() * 0.02 if dialogue_line.time == "auto" else dialogue_line.time.to_float()
		await get_tree().create_timer(time).timeout
		next(dialogue_line.next_id)
	else:
		is_waiting_for_input = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()


## Go to the next line
func next(next_id: String) -> void:
	dialogue_line = await dialogue_resource.get_next_dialogue_line(next_id, temporary_game_states)


func find_speaker_node(extra_game_states: Array) -> Node2D:
	for state in extra_game_states:
		if state is Node2D:
			return state
	return null


func position_chat_box() -> void:
	var viewport_size: Vector2 = get_dialogue_viewport_size()
	var chat_box_size: Vector2 = chat_box_root.size
	if chat_box_size == Vector2.ZERO:
		chat_box_size = chat_box_root.custom_minimum_size

	var chat_box_position: Vector2
	if is_instance_valid(speaker_node):
		var speaker_head_position: Vector2 = get_speaker_head_global_position()
		var speaker_screen_position: Vector2 = get_viewport().get_canvas_transform() * speaker_head_position
		chat_box_position = Vector2(
			speaker_screen_position.x - chat_box_size.x * 0.5,
			speaker_screen_position.y - speaker_head_gap - chat_box_size.y + speaker_chat_box_vertical_offset
		)
	else:
		chat_box_position = Vector2(
			(viewport_size.x - chat_box_size.x) * 0.5,
			viewport_size.y - chat_box_size.y - 16.0
		)

	var max_position: Vector2 = Vector2(
		maxf(screen_margin, viewport_size.x - chat_box_size.x - screen_margin),
		maxf(screen_margin, viewport_size.y - chat_box_size.y - screen_margin)
	)
	chat_box_position.x = clampf(chat_box_position.x, screen_margin, max_position.x)
	chat_box_position.y = clampf(chat_box_position.y, screen_margin, max_position.y)
	chat_box_root.position = chat_box_position.round()


func get_dialogue_viewport_size() -> Vector2:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x > 0.0 and viewport_size.y > 0.0:
		return viewport_size

	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)


func get_speaker_head_global_position() -> Vector2:
	var sprite_bounds: Rect2 = Rect2()
	var has_sprite_bounds: bool = false

	for sprite in get_visible_animated_sprites(speaker_node):
		var frame_texture: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		if frame_texture == null:
			continue

		var frame_size: Vector2 = frame_texture.get_size()
		var top_left: Vector2 = sprite.offset
		if sprite.centered:
			top_left -= frame_size * 0.5

		var bottom_right: Vector2 = top_left + frame_size
		var corners: Array[Vector2] = [
			top_left,
			Vector2(bottom_right.x, top_left.y),
			bottom_right,
			Vector2(top_left.x, bottom_right.y)
		]

		for corner in corners:
			var global_corner: Vector2 = sprite.to_global(corner)
			if has_sprite_bounds:
				sprite_bounds = sprite_bounds.expand(global_corner)
			else:
				sprite_bounds = Rect2(global_corner, Vector2.ZERO)
				has_sprite_bounds = true

	if has_sprite_bounds:
		return Vector2(sprite_bounds.get_center().x, sprite_bounds.position.y)

	return speaker_node.global_position + fallback_speaker_head_offset


func get_visible_animated_sprites(root_node: Node) -> Array[AnimatedSprite2D]:
	var sprites: Array[AnimatedSprite2D] = []
	collect_visible_animated_sprites(root_node, sprites)
	return sprites


func collect_visible_animated_sprites(root_node: Node, sprites: Array[AnimatedSprite2D]) -> void:
	for child in root_node.get_children():
		if child is AnimatedSprite2D and child.is_visible_in_tree() and child.sprite_frames:
			sprites.append(child)
		collect_visible_animated_sprites(child, sprites)


#region Signals


func _on_mutation_cooldown_timeout() -> void:
	if will_hide_balloon:
		will_hide_balloon = false
		balloon.hide()


func _on_mutated(_mutation: Dictionary) -> void:
	if not _mutation.is_inline:
		is_waiting_for_input = false
		will_hide_balloon = true
		mutation_cooldown.start(0.1)


func _on_balloon_gui_input(event: InputEvent) -> void:
	# See if we need to skip typing of the dialogue
	if dialogue_label.is_typing:
		var mouse_was_clicked: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()
		var skip_button_was_pressed: bool = event.is_action_pressed(skip_action)
		if mouse_was_clicked or skip_button_was_pressed:
			get_viewport().set_input_as_handled()
			dialogue_label.skip_typing()
			return

	if not is_waiting_for_input: return

	# When there are no response options the balloon itself is the clickable thing
	get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		if dialogue_line.responses.size() > 0:
			show_responses()
		else:
			next(dialogue_line.next_id)
	elif event.is_action_pressed(next_action) and get_viewport().gui_get_focus_owner() == balloon:
		if dialogue_line.responses.size() > 0:
			show_responses()
		else:
			next(dialogue_line.next_id)


func show_responses() -> void:
	is_waiting_for_input = false
	is_waiting_to_show_responses = false
	balloon.focus_mode = Control.FOCUS_NONE
	chat_box_root.hide()
	responses_menu.show()


func _on_responses_menu_response_selected(response: DialogueResponse) -> void:
	next(response.next_id)


#endregion
