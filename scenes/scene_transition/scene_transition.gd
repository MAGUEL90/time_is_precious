extends CanvasLayer

@onready var fade_overlay: ColorRect = $FadeOverlay
@onready var message_label: Label = $MessageLabel

var is_transitioning: bool = false

# Setup

func _ready() -> void:
	message_label.offset_left = 60
	message_label.offset_right = -60
	message_label.visible = false

# Fade effects

func fade_out(duration: float = 0.35) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 1.0, duration)
	await tween.finished

func fade_in(duration: float = 0.35) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 0.0, duration)
	await tween.finished

# Transition orchestration

func run_with_fade(
	action: Callable,
	fade_duration: float = 0.35,
	hold_duration: float = 2.5,
	message: String = "") -> bool:

	if is_transitioning:
		return false

	is_transitioning = true
	await fade_out(fade_duration)

	show_message(message)

	var action_succeeded: bool = action.call()

	await get_tree().process_frame
	await get_tree().create_timer(hold_duration).timeout

	hide_message()
	await fade_in(fade_duration)

	is_transitioning = false
	return action_succeeded

# Message presentation

func show_message(message: String) -> void:
	message_label.text = message
	message_label.visible = not message.is_empty()

func hide_message() -> void:
	message_label.hide()
	message_label.text = ""
