class_name NPCBase extends CharacterBody2D

const GAME_DIALOUGE_BALLOON = preload("uid://73jm5qjy52vq")

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D

var npc_sprite_direction: Vector2
var on_dialouge: bool = false
var player_reff

func _ready() -> void:
	print("node_name: ", self.name, " is_ready: ", is_node_ready())
	interactable_label_component.hide()
	player_reff = get_tree().get_first_node_in_group("player")
	
	if player_reff:
		# Connect signal dari InteractableComponent ke fungsi Player
		interactable_component.interactable_activated.connect(player_reff._on_interactable_activated.bind(self))  # "self" = NPC ini sendiri)
		interactable_component.interactable_deactivated.connect(player_reff._on_interactable_deactivated.bind(self))
		
func _process(delta: float) -> void:
	pass

func start_dialouge() -> void:
	
	var balloon: BaseGameDialougeBalloon = GAME_DIALOUGE_BALLOON.instantiate()
	get_tree().current_scene.add_child(balloon)
	balloon.start(load("res://dialouge/game_dialouge_conversations/test.dialogue"), "start")
