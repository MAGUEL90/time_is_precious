extends Node

var failures: int = 0
var content: Node
var hub: WorkerControlUI

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _frames() -> void:
	for _frame: int in range(5):
		await get_tree().process_frame

func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	get_viewport().push_input(event)
	await _frames()

func _run() -> void:
	TimeComponentManager.set_process(false)
	TimeComponentManager.environment.color = Color.WHITE
	content = preload("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(content)
	hub = content.get_node("YSortWorld/Worksites/WorkerControlUI")
	await _frames()
	await _key(KEY_K)
	_expect(hub.visible and get_tree().paused, "Physical K opens Worker Hub and pauses the world.")
	_expect(hub.window.is_visible_in_tree(), "Worker Hub window is visible while the world is paused.")
	var rect: Rect2 = hub.window.get_global_rect()
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	print("Worker Hub geometry: ", rect, " viewport: ", viewport_rect, " canvas: ", hub.window.get_global_transform_with_canvas())
	_expect(viewport_rect.encloses(rect), "Worker Hub is fully inside the viewport.")
	await _capture("worker-hub-k-empty.png")
	await _key(KEY_K)
	_expect(not hub.visible and not get_tree().paused, "Second K closes Worker Hub and resumes the world.")
	var startup: Node = content.get_node("YSortWorld/InitialWorksites")
	WorkerDatabase.hire_applicant(startup.APPLICANT_ID)
	WorkerDatabase.hire_applicant(startup.HAULER_APPLICANT_ID)
	await _key(KEY_K)
	_expect(hub.visible and hub.status_list.get_child_count() == 2, "K reopens with both hired workers.")
	await _capture("worker-hub-k-hired.png")
	hub.tools_tab_button.pressed.emit()
	await _frames()
	_expect(hub.tools_page.is_visible_in_tree(), "Tools remains usable while paused.")
	await _key(KEY_ESCAPE)
	_expect(not hub.visible and not get_tree().paused, "Escape closes Worker Hub and resumes the world.")
	await _key(KEY_K)
	hub.close_button.pressed.emit()
	await _frames()
	_expect(not hub.visible and not get_tree().paused, "Close button also releases the pause.")
	var progress: WorkProgressUI = content.get_node("WorkProgressUI")
	await _key(KEY_J)
	_expect(progress.visible and progress.root.is_visible_in_tree() and get_tree().paused, "Work Progress must show its panel whenever it takes the modal pause.")
	await _capture("worker-hub-progress-pause.png")
	await _key(KEY_K)
	_expect(not hub.visible and progress.root.visible, "K cannot steal the pause from another open panel.")
	await _key(KEY_J)
	_expect(not progress.root.visible and not get_tree().paused, "Second J closes Work Progress and resumes the world.")
	await _key(KEY_J)
	await _key(KEY_ESCAPE)
	_expect(not get_tree().paused, "Closing Work Progress releases its modal pause.")
	await _key(KEY_K)
	_expect(hub.visible and get_tree().paused, "K can open Worker Hub again after the other panel closes.")
	hub.close_button.pressed.emit()
	get_tree().paused = false
	print("MainMapWorkerHubTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func _capture(filename: String) -> void:
	var directory: String = OS.get_environment("TIP_WORKER_HUB_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join(filename))
