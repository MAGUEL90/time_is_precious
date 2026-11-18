class_name Gabbi extends NPCBase

@export var use_city_rebuilding_dialogue: bool = false

func _ready() -> void:
	_align_visual_sort_to_feet()
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

func _align_visual_sort_to_feet() -> void:
	var visual: Node2D = $GabbiVisual
	var feet_y: float = $CollisionShape2D.position.y
	# Keep all layer paths and their drawn positions; only the sort anchor moves.
	y_sort_enabled = true
	visual.position.y += feet_y
	for layer: Node in visual.get_children():
		if layer is Node2D:
			(layer as Node2D).position.y -= feet_y

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
	# Use the same native-pixel frame as other NPC conversations.
	_configure_compact_dialogue(balloon)
	var panel: TextureRect = balloon.chat_box_root.get_node("TemplateDialogue")
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
