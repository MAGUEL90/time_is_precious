extends Node

## Actual map and board with an explicitly controlled clock; no personal save.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const EXPECTED_TEXT: String = "akses job board jam 08.00 -17.00"
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _frames(count: int = 5) -> void:
	for _index: int in range(count):
		await get_tree().process_frame

func _capture(label: String) -> void:
	var directory: String = OS.get_environment("TIP_MVP_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	_expect(frame.get_size() == Vector2i(400, 225), "Capture uses the native logical viewport.")
	if frame.get_size() != Vector2i(400, 225):
		return
	_expect(frame.save_png(directory.path_join(label + "-400x225.png")) == OK, "Logical capture is saved.")
	frame.resize(1200, 675, Image.INTERPOLATE_NEAREST)
	_expect(frame.save_png(directory.path_join(label + "-1200x675.png")) == OK, "Scaled capture is saved.")

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.current_hour = 7
	TimeComponentManager.current_minute = 59
	var content: Node = CONTENT.instantiate()
	add_child(content)
	await _frames()
	var board: JobBoard = content.get_node("YSortWorld/InitialWorksites/JobBoard")
	var player: Player = content.get_node("YSortWorld/Player")
	player.debug_disable_player_needs = true
	player.global_position = board.global_position + Vector2(0, 12)
	await _frames(10)
	for _step: int in range(5):
		await get_tree().physics_frame
	var label: Label = board.get_node("ClosedFeedbackLabel")
	var prompt: InteractableLabelComponent = board.interactable_label_component
	board._on_interact_range_entered()
	var prompt_position: Vector2 = prompt.position
	var board_position: Vector2 = board.global_position
	_expect(not label.visible, "Entering the range alone does not produce closed feedback.")
	_expect(prompt.label.text == "E", "The original E prompt remains intact.")
	_expect(player.current_interactable == board, "The actual player interaction target is the Job Board.")
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	get_viewport().push_input(interact)
	interact = InputEventAction.new()
	interact.action = "interact"
	get_viewport().push_input(interact)
	await get_tree().process_frame
	_expect(not is_instance_valid(board.job_board_ui), "07:59 is closed and cannot open the menu.")
	_expect(label.visible and label.text == EXPECTED_TEXT, "An attempt produces the exact feedback.")
	_expect(label.get_theme_color("font_color").r > 0.9 and label.get_theme_color("font_color").g < 0.2, "Closed feedback is red.")
	_expect(label.get_parent() == board and label.position.y + label.size.y <= prompt.position.y, "Feedback is anchored above the board without covering E.")
	await get_tree().create_timer(0.6).timeout
	await _capture("job-board-closed-rise")
	var rising_y: float = label.position.y
	_expect(rising_y < board.CLOSED_FEEDBACK_HOME_POSITION.y, "Feedback slides upward.")
	var old_tween: Tween = board._closed_feedback_tween
	board.on_player_interact(player)
	board.on_player_interact(player)
	_expect(not old_tween.is_valid() and board._closed_feedback_tween.is_valid(), "Repeated attempts replace the existing animation.")
	_expect(board.find_children("ClosedFeedbackLabel", "Label", false, false).size() == 1, "Repeated attempts never stack labels.")
	_expect(label.position.is_equal_approx(board.CLOSED_FEEDBACK_HOME_POSITION), "Repeated attempt restarts from the board anchor.")
	await get_tree().create_timer(1.0).timeout
	_expect(label.visible and label.position.y < board.CLOSED_FEEDBACK_HOME_POSITION.y, "Feedback remains visible while rising over two seconds.")
	await get_tree().create_timer(1.05).timeout
	var shake_x: float = label.position.x
	await get_tree().create_timer(0.05).timeout
	_expect(not is_equal_approx(label.position.x, shake_x), "Feedback briefly shakes after rising.")
	await _capture("job-board-closed-shake")
	await get_tree().create_timer(0.25).timeout
	_expect(label.visible and label.position.y > board.CLOSED_FEEDBACK_HOME_POSITION.y - board.CLOSED_FEEDBACK_RISE, "Feedback slides back down after shaking.")
	await _capture("job-board-closed-fade")
	await get_tree().create_timer(0.6).timeout
	_expect(not label.visible and board._closed_feedback_tween == null, "Feedback disappears and the tween is cleaned up.")
	_expect(prompt.position == prompt_position and board.global_position == board_position and prompt.label.text == "E", "Board and accepted E position remain unchanged.")
	for time: Vector2i in [Vector2i(8, 0), Vector2i(16, 59)]:
		TimeComponentManager.current_hour = time.x
		TimeComponentManager.current_minute = time.y
		board.on_player_interact(player)
		_expect(is_instance_valid(board.job_board_ui) and board.job_board_ui.visible, "%02d:%02d opens the board." % [time.x, time.y])
		if is_instance_valid(board.job_board_ui):
			board.job_board_ui.close()
		await _frames(2)
	TimeComponentManager.current_hour = 17
	TimeComponentManager.current_minute = 0
	board.on_player_interact(player)
	_expect(not is_instance_valid(board.job_board_ui) and label.visible, "17:00 is closed and shows feedback.")
	var animation_directory: String = OS.get_environment("TIP_JOB_BOARD_ANIMATION_DIR")
	if not animation_directory.is_empty() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(animation_directory)
		board.on_player_interact(player)
		for frame: int in range(180):
			await RenderingServer.frame_post_draw
			if frame % 4 == 0:
				var image: Image = get_viewport().get_texture().get_image()
				_expect(image.save_png(animation_directory.path_join("frame-%03d.png" % (frame / 4))) == OK, "Animation frame is saved.")
		_expect(not label.visible, "Recorded feedback ends hidden.")
	board.queue_free()
	await _frames(2)
	_expect(not is_instance_valid(board), "Freeing the board during feedback is safe.")
	get_tree().paused = false
	print("JobBoardClosedFeedbackTest: %s (%d failed)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
