class_name Player extends CharacterBody2D

var player_sprite_direction: Vector2
var current_interactable: NPCBase

var can_dialouge: bool = false
var dialouge_finished: bool = false
var speed = 50

@onready var player_movement_state: Node = $PlayerStateMachine/PlayerMovementState

func _ready() -> void:
	get_tree().call_group("npcs", "interactable_component.interactable_activated.connect(_on_interactable_activated)")
	get_tree().call_group("npcs", "interactable_component.interactable_deactivated.connect(_on_interactable_deactivated)")
	BaseDialougeManager.dialouge_deactivated.connect(on_dialouge_deactivated)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and can_dialouge:
		
		current_interactable.can_walk = false
		current_interactable.walk_cycle_duration.stop()
		current_interactable.start_dialouge()
		process_mode = Node.PROCESS_MODE_DISABLED
		
		if current_interactable.global_position.x >= global_position.x:
			current_interactable.animated_sprite_2d.flip_h = true
		else:
			current_interactable.animated_sprite_2d.flip_h = false
		current_interactable.interactable_label_component.hide()
		
func _process(_delta: float) -> void:
	pass
	
func _on_interactable_activated(npc):
	current_interactable = npc
	if dialouge_finished == false:
		current_interactable.interactable_label_component.show()
		can_dialouge = true
		
func _on_interactable_deactivated(npc):
	if current_interactable == npc:
		can_dialouge = false
		current_interactable = null
		dialouge_finished = false
	
	npc.interactable_label_component.hide()

func on_dialouge_deactivated() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
