class_name Player extends CharacterBody2D

var player_sprite_direction: Vector2 = Vector2.RIGHT
var current_interactable: NPCBase
var current_npc_dialogue: NPCBase

var can_dialogue : bool = false
var dialogue_finished: bool = false
var speed = 50

@onready var player_movement_state: Node = $PlayerStateMachine/PlayerMovementState
@onready var time_component_manager = TimeComponentManager

func _ready() -> void:
	# get_tree().call_group("npcs", "interactable_component.interactable_activated.connect(_on_interactable_activated)")
	# get_tree().call_group("npcs", "interactable_component.interactable_deactivated.connect(_on_interactable_deactivated)")
	BaseDialogueManager.dialogue_activated.connect(on_dialogue_activated)
	BaseDialogueManager.dialogue_deactivated.connect(on_dialogue_deactivated)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and can_dialogue  and current_interactable != null:
		current_npc_dialogue  = current_interactable
		
		if current_npc_dialogue .global_position.x >= global_position.x:
			current_npc_dialogue .animated_sprite_2d.flip_h = true
		else:
			current_npc_dialogue .animated_sprite_2d.flip_h = false
		
		current_interactable.start_dialogue ()
		time_component_manager.toggle_pause()
		current_interactable.interactable_label_component.hide()

func _process(_delta: float) -> void:
	pass
	
func _on_interactable_activated(npc):
	if current_interactable:
		return
	
	current_interactable = npc
	current_interactable.interactable_label_component.show()
	can_dialogue  = true

func _on_interactable_deactivated(npc):
	current_interactable = null
	can_dialogue  = false
	
	npc.interactable_label_component.hide()

func on_dialogue_activated() -> void:
	
	if current_npc_dialogue:
		current_npc_dialogue.on_dialogue  = true
		current_npc_dialogue.can_walk = false
		current_npc_dialogue.walk_cycle_duration.stop()
		

	process_mode = Node.PROCESS_MODE_DISABLED
	

func on_dialogue_deactivated() -> void:
	time_component_manager.toggle_pause()
	if current_npc_dialogue:
		current_npc_dialogue.on_dialogue  = false
		current_npc_dialogue.can_walk = true
		current_npc_dialogue.walk_cycle_duration.start()
	
	current_npc_dialogue  = null
	process_mode = Node.PROCESS_MODE_INHERIT
	
