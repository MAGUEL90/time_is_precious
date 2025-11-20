class_name NPCBase extends CharacterBody2D

const GAME_DIALOUGE_BALLOON = preload("uid://73jm5qjy52vq")

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent

var base_sprite_direction: Vector2

func _ready() -> void:
	interactable_label_component.hide()
	var player = get_tree().get_first_node_in_group("player")
	
	if player:
		# Connect signal dari InteractableComponent ke fungsi Player
		interactable_component.interactable_activated.connect(
			player._on_interactable_activated.bind(self))  # "self" = NPC ini sendiri)
		interactable_component.interactable_deactivated.connect(
			player._on_interactable_deactivated.bind(self))
	
func start_dialouge() -> void:
	var balloon: BaseGameDialougeBalloon = GAME_DIALOUGE_BALLOON.instantiate()
	get_tree().current_scene.add_child(balloon)
	balloon.start(load("res://dialouge/game_dialouge_conversations/test.dialogue"), "start")
