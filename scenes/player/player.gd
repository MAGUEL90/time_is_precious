class_name Player extends CharacterBody2D

var player_sprite_direction: Vector2
var current_interactable: NPCBase

func _ready() -> void:
	get_tree().call_group("npcs", "interactable_component.interactable_activated.connect(_on_interactable_activated)")
	get_tree().call_group("npcs", "interactable_component.interactable_deactivated.connect(_on_interactable_deactivated)")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and current_interactable:
		current_interactable.start_dialouge()

func _on_interactable_activated(npc):
	current_interactable = npc
	current_interactable.interactable_label_component.show()

func _on_interactable_deactivated(npc):
	if current_interactable == npc:
		current_interactable = null
	npc.interactable_label_component.hide()
