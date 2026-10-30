extends CanvasLayer
## Use the wall caretaker's exact native balloon and formatter, without a wall world instance.
signal continued
signal cancelled
const BALLOON: PackedScene = preload("res://dialogue/game_dialogue_balloon/game_dialogue_balloon.tscn")
const WALL_FORMATTER: Script = preload("res://scenes/raid/wall_management_spot.gd")
var balloon: BaseGameDialogueBalloon
var resource: DialogueResource
var message: DialogueLabel
var _requested := false
var _ending := false
func _ready() -> void:
	get_node("/root/DialogueManager").dialogue_ended.connect(_on_dialogue_ended)
func open(text: String, speaker: Node2D) -> void:
	balloon = BALLOON.instantiate()
	# Before _ready, replacing the scene script also replaces its unattached Timer.
	if is_instance_valid(balloon.mutation_cooldown) and balloon.mutation_cooldown.get_parent()==null:
		balloon.mutation_cooldown.free()
	balloon.set_script(preload("res://scenes/workshop_plot/keeper/workshop_keeper_balloon.gd"))
	balloon.anchor_player = get_tree().get_first_node_in_group("player")
	add_child(balloon)
	# This method only formats greeting_balloon controls. Never add formatter to tree.
	var formatter: Node = WALL_FORMATTER.new()
	formatter.greeting_balloon = balloon
	formatter._fit_dialogue()
	formatter.free()
	balloon.responses_menu.position = Vector2.ZERO
	balloon.chat_box_root.get_node("TemplateDialogue").position = Vector2(0,18)
	balloon.speaker_chat_box_vertical_offset = 0.0
	balloon.speaker_head_gap = 4.0
	resource = get_node("/root/DialogueManager").create_resource_from_text("~ keeper\nBrickmaker: "+text+"\n- Continue\n\tdo keeper_continue()\n\t=> END\n- Not now\n\t=> END")
	message = balloon.dialogue_label
	balloon.start(resource,"keeper",[speaker,self])
func keeper_continue() -> void:
	_requested = true
func _on_dialogue_ended(ended: DialogueResource) -> void:
	if ended!=resource or _ending:
		return
	_ending = true
	_finish.call_deferred()
func _finish() -> void:
	await get_tree().process_frame
	if _requested:
		continued.emit()
	else:
		cancelled.emit()
func _exit_tree() -> void:
	var manager: Node = get_node_or_null("/root/DialogueManager")
	if manager!=null and manager.dialogue_ended.is_connected(_on_dialogue_ended):
		manager.dialogue_ended.disconnect(_on_dialogue_ended)