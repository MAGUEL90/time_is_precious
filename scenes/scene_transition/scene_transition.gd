extends CanvasLayer

@onready var fade_overlay: ColorRect = $FadeOverlay
@onready var message_label: Label = $MessageLabel
@onready var scoreboard_panel: Control = $ScoreBoardPanel
@onready var scoreboard_label: Label = $ScoreBoardPanel/ScoreboardLabel
@onready var continue_button: Button = $ScoreBoardPanel/ContinueButton

var is_transitioning: bool = false
var _pending_spawn_point: StringName = &""

# Setup

func _ready() -> void:
	message_label.offset_left = 60
	message_label.offset_right = -60
	message_label.visible = false
	continue_button.hide()
	scoreboard_panel.hide()

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
	message: String = "",
	wait_for_continue: bool = false
) -> bool:

	if is_transitioning:
		return false

	is_transitioning = true
	await fade_out(fade_duration)

	if wait_for_continue:
		show_scoreboard(message)
	else:
		show_message(message)

	var action_succeeded: bool = action.call()

	if action_succeeded and not _pending_spawn_point.is_empty():
		# Destination nodes are available only after SceneTree finishes the swap.
		await get_tree().scene_changed
		_place_player_at_pending_spawn()
	else:
		if not action_succeeded:
			clear_spawn_point()
		await get_tree().process_frame

	if wait_for_continue:
		continue_button.show()
		continue_button.grab_focus()

		await continue_button.pressed

		continue_button.hide()
		continue_button.release_focus()
		hide_scoreboard()
	else:
		await get_tree().create_timer(hold_duration).timeout

	hide_message()
	await fade_in(fade_duration)

	is_transitioning = false
	return action_succeeded

# Spawn routing

func queue_spawn_point(spawn_point_name: StringName) -> void:
	_pending_spawn_point = spawn_point_name

func clear_spawn_point() -> void:
	_pending_spawn_point = &""

func _place_player_at_pending_spawn() -> void:
	if _pending_spawn_point.is_empty():
		return

	var spawn_point_name: StringName = _pending_spawn_point
	_pending_spawn_point = &""

	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		push_warning("SceneTransition could not find the current scene.")
		return

	var spawn_point: Marker2D = current_scene.find_child(
		String(spawn_point_name),
		true,
		false) as Marker2D

	var player: Player = get_tree().get_first_node_in_group("player") as Player

	if spawn_point == null:
		push_warning(
			"SceneTransition could not find spawn point: %s"
			% spawn_point_name
		)
		return

	if player == null:
		push_warning("SceneTransition could not find Player.")
		return

	player.global_position = spawn_point.global_position

# Message presentation

func show_message(message: String) -> void:
	message_label.text = message
	message_label.visible = not message.is_empty()

func hide_message() -> void:
	message_label.hide()
	message_label.text = ""

func show_scoreboard(message: String) -> void:
	scoreboard_label.text = message
	scoreboard_panel.visible = not message.is_empty()

func hide_scoreboard() -> void:
	scoreboard_panel.hide()
	scoreboard_label.text = ""
