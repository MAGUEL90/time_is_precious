class_name SleepSpot extends Node2D

const DEFAULT_PROMPT_TEXT: String = "press E\nto sleep"

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent

var player_ref: Player = null

# Setup and signal bindings

func _ready() -> void:
	player_ref = get_tree().get_first_node_in_group("player")

	if player_ref == null:
		push_warning("SleepSpot could not find Player.")
		return

	interactable_component.interactable_activated.connect(player_ref._on_interactable_activated.bind(self))
	interactable_component.interactable_deactivated.connect(player_ref._on_interactable_deactivated.bind(self))
	interactable_component.interactable_activated.connect(_on_interact_range_entered)
	interactable_component.interactable_deactivated.connect(_on_interact_range_exited)

# Proximity feedback

func _on_interact_range_entered() -> void:
	interactable_label_component.set_text(DEFAULT_PROMPT_TEXT)
	interactable_label_component.show()

func _on_interact_range_exited() -> void:
	interactable_label_component.hide()

# Sleep interaction

func on_player_interact(player: Player) -> void:
	if SceneTransition.is_transitioning:
		return

	if not player.can_sleep():
		interactable_label_component.set_text("You already slept today")
		return

	var previous_can_move: bool = player.can_move
	player.can_move = false

	var sleep_succeeded: bool = await SceneTransition.run_with_fade(Callable(player, "sleep"))

	player.can_move = previous_can_move

	if sleep_succeeded:
		interactable_label_component.hide()
	else:
		interactable_label_component.set_text("Cannot sleep right now")
