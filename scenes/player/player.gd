class_name Player extends CharacterBody2D

var player_sprite_direction: Vector2 = Vector2.RIGHT
var current_interactable: NPCBase
var current_npc_dialouge: NPCBase

var can_dialouge: bool = false
var dialouge_finished: bool = false
var speed = 50

@onready var player_movement_state: Node = $PlayerStateMachine/PlayerMovementState
@onready var time_component_manager = TimeComponentManager

func _ready() -> void:
	get_tree().call_group("npcs", "interactable_component.interactable_activated.connect(_on_interactable_activated)")
	get_tree().call_group("npcs", "interactable_component.interactable_deactivated.connect(_on_interactable_deactivated)")
	BaseDialougeManager.dialouge_activated.connect(on_dialouge_activated)
	BaseDialougeManager.dialouge_deactivated.connect(on_dialouge_deactivated)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and can_dialouge and current_interactable != null:
		current_npc_dialouge = current_interactable
		
		if current_npc_dialouge.global_position.x >= global_position.x:
			current_npc_dialouge.animated_sprite_2d.flip_h = true
		else:
			current_npc_dialouge.animated_sprite_2d.flip_h = false
		
		current_interactable.start_dialouge()
		current_interactable.interactable_label_component.hide()

func _process(_delta: float) -> void:
	pass
	
func _on_interactable_activated(npc):
	current_interactable = npc
	current_interactable.interactable_label_component.show()
	can_dialouge = true

func _on_interactable_deactivated(npc):
	current_interactable = null
	can_dialouge = false
	
	npc.interactable_label_component.hide()

func on_dialouge_activated() -> void:
	
	if current_npc_dialouge:
		time_component_manager.toggle_pause()
		current_npc_dialouge.on_dialouge = true
		current_npc_dialouge.can_walk = false
		current_npc_dialouge.walk_cycle_duration.stop()
		

	process_mode = Node.PROCESS_MODE_DISABLED

func on_dialouge_deactivated() -> void:
	if current_npc_dialouge:
		time_component_manager.toggle_pause()
		current_npc_dialouge.on_dialouge = false
		current_npc_dialouge.can_walk = true
		current_npc_dialouge.walk_cycle_duration.start()
	
	current_npc_dialouge = null
	process_mode = Node.PROCESS_MODE_INHERIT
	
