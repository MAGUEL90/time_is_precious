class_name NPCBase extends CharacterBody2D

const GAME_DIALOUGE_BALLOON = preload("uid://73jm5qjy52vq")

enum NPCState {
	NPCIdleState,
	NPCWalkState,
	NPCWorkingState,
	NPCSleepState,
	NPCWanderState
}

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var walk_cycle_duration: Timer = $WalkCycleDuration
@onready var navigation_agent_2d: NavigationAgent2D = $NavigationAgent2D

var npc_sprite_direction: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT]
var on_dialouge: bool = false
var can_walk: bool = false
var npc_name: String
var player_reff: Player

@export var npc_unique_dialouge: DialogueResource

func _ready() -> void:
	
	interactable_label_component.hide()
	player_reff = get_tree().get_first_node_in_group("player")
	
	walk_cycle_duration.wait_time = randf_range(2.0, 3.5)
	walk_cycle_duration.start()
	
	if player_reff:
		# Connect signal dari InteractableComponent ke fungsi Player
		interactable_component.interactable_activated.connect(player_reff._on_interactable_activated.bind(self))  # "self" = NPC ini sendiri)
		interactable_component.interactable_deactivated.connect(player_reff._on_interactable_deactivated.bind(self))
	
func _process(_delta: float) -> void:
	pass
	# print(walk_cycle_duration.time_left)

func start_dialouge() -> void:
	
	var balloon: BaseGameDialougeBalloon = GAME_DIALOUGE_BALLOON.instantiate()
	get_tree().current_scene.add_child(balloon)
	if npc_unique_dialouge:
		balloon.start(npc_unique_dialouge, "start_%s" % [npc_name])
	else:
		balloon.start(load("res://dialouge/game_dialouge_conversations/test.dialogue"), "start")

func _on_walk_cycle_duration_timeout() -> void:
	can_walk = true
