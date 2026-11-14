class_name Gabbi extends NPCBase

@export var use_city_rebuilding_dialogue: bool = false

func _ready() -> void:
	# The initial-scene guide uses her authored spawn, not the old template origin.
	# Each visit owns this transient state without modifying the template resource.
	if use_city_rebuilding_dialogue and npc_state != null:
		npc_state = npc_state.duplicate(true)
		npc_state.current_position = global_position
		npc_state.last_position = global_position
	super._ready()
	if not allow_random_walk:
		walk_cycle_duration.stop()
		can_walk = false

func can_start_dialogue() -> bool:
	if use_city_rebuilding_dialogue:
		return npc_unique_dialogue != null and npc_unique_dialogue.get_titles().has("contract_1")
	return super.can_start_dialogue()

func start_dialogue() -> bool:
	if not use_city_rebuilding_dialogue:
		return super.start_dialogue()
	if not can_start_dialogue():
		return false
	# This existing title is a city conversation, not a hiring action.
	var balloon: BaseGameDialogueBalloon = GAME_dialogue_BALLOON.instantiate()
	get_tree().current_scene.add_child(balloon)
	# Clamp using the actual scaled artwork so its border stays on screen.
	var panel: TextureRect = balloon.chat_box_root.get_node("TemplateDialogue")
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_KEEP_SIZE)
	panel.size = Vector2(176, 60)
	panel.position = Vector2.ZERO
	balloon.chat_box_root.custom_minimum_size = panel.size * panel.scale
	balloon.chat_box_root.size = balloon.chat_box_root.custom_minimum_size
	# The legacy response offsets fall below the 400x225 gameplay viewport.
	# Center this conversation's choices without changing other dialogue layouts.
	balloon.responses_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	var photo: TextureRect = panel.get_node("TexturePhoto")
	var portrait := preload("res://scenes/npc_children/npc_gabbi/gabbi_dialogue_portrait.gd").new()
	portrait.name = "GabbiPortrait"
	photo.add_child(portrait)
	portrait.size = photo.size
	portrait.show_visual($GabbiVisual)
	balloon.start(npc_unique_dialogue, "contract_1", [self])
	return true
