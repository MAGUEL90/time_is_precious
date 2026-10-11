class_name SleepSpot extends Node2D

const DEFAULT_PROMPT_TEXT: String = "press E\nto sleep"

@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var interactable_label_component: InteractableLabelComponent = $InteractableLabelComponent

var player_ref: Player = null
var _save_feedback: Label
var _feedback_tween: Tween

# Setup and signal bindings

func _ready() -> void:
	_save_feedback = Label.new()
	_save_feedback.name = "SaveFeedback"
	_save_feedback.theme = preload("res://resources/ui_gameplay_theme/ui_gameplay_theme.tres")
	_save_feedback.add_theme_font_size_override("font_size", 6)
	_save_feedback.add_theme_color_override("font_shadow_color", Color(0.20, 0.14, 0.10))
	_save_feedback.add_theme_constant_override("shadow_offset_x", 1)
	_save_feedback.add_theme_constant_override("shadow_offset_y", 1)
	_save_feedback.position = Vector2(-48, -24)
	_save_feedback.size = Vector2(96, 10)
	_save_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_save_feedback.hide()
	add_child(_save_feedback)
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
		_show_save_feedback("Already rested today")
		return

	var previous_can_move: bool = player.can_move
	player.can_move = false

	var sleep_succeeded: bool = await SceneTransition.run_with_fade(Callable(player, "sleep"))

	player.can_move = previous_can_move

	if sleep_succeeded:
		var checkpoint: Node = WorkStateRuntime.get_node_or_null("CitySave")
		if checkpoint != null:
			var saved: bool = checkpoint.save_after_sleep(player)
			interactable_label_component.hide()
			_show_save_feedback("Game saved" if saved else "Save failed")
		else:
			interactable_label_component.hide()
	else:
		interactable_label_component.set_text("Cannot sleep right now")

func _show_save_feedback(message: String) -> void:
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_save_feedback.text = message
	_save_feedback.modulate.a = 1.0
	_save_feedback.show()
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(3.0)
	_feedback_tween.tween_property(_save_feedback, "modulate:a", 0.0, 0.5)
	_feedback_tween.tween_callback(_save_feedback.hide)
