class_name NPCBase extends CharacterBody2D

const GAME_DIALOUGE_BALLOON = preload("uid://73jm5qjy52vq")

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent

var base_sprite_direction: Vector2

func _ready() -> void:
	interactable_label_component.hide()
	interactable_component.interactable_activated.connect(on_interactable_activated)
	interactable_component.interactable_deactivated.connect(on_interactable_deactivated)

func on_interactable_activated() -> void:
	interactable_label_component.show()

func on_interactable_deactivated() -> void:
	interactable_label_component.hide()



#func _unhandled_input(event: InputEvent) -> void:
	#if event.is_action_pressed("interact"):
		#var balloon: BaseGameDialougeBalloon = GAME_DIALOUGE_BALLOON.instantiate()
		#get_tree().current_scene.add_child(balloon)
		#balloon.start(load("res://dialouge/game_dialouge_conversations/test.dialogue"), "start")
