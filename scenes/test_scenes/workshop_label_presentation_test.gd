extends Node2D

## Isolated visual fixture: no save files, transactions, or progression are used.
const PLOT_UI: PackedScene = preload("res://scenes/ui/workshop_plot_ui/workshop_plot_ui.tscn")
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const CONSTRUCTION: Script = preload("res://scenes/workshop_plot/workshop_construction_state.gd")
var failures: int = 0
var build_requests: int = 0
var close_requests: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _check_footer(panel: WorkshopPlotUI, stage: String) -> void:
	var frame: Rect2 = panel.window.get_global_rect()
	for button: Button in [panel.cancel_button, panel.build_button]:
		var gap: float = frame.end.y - button.get_global_rect().end.y
		_expect(is_equal_approx(gap, 16.0), stage + ": " + button.name + " keeps a 16-pixel inset from the frame's outer bottom.")
		_expect(frame.encloses(button.get_global_rect()), stage + ": " + button.name + " stays completely inside the frame.")
		print("Footer ", stage, " ", button.name, " outer-bottom-gap=", gap)

func _can_focus(panel: WorkshopPlotUI, target: Control) -> bool:
	panel.assign_workers_button.grab_focus()
	for _step: int in range(8):
		if target.has_focus():
			return true
		var event := InputEventAction.new()
		event.action = "ui_focus_next"
		event.pressed = true
		get_viewport().push_input(event)
		event = InputEventAction.new()
		event.action = "ui_focus_next"
		get_viewport().push_input(event)
		await get_tree().process_frame
	return target.has_focus()

func _on_build_requested(_ids: Array[String]) -> void:
	build_requests += 1

func _on_panel_closed() -> void:
	close_requests += 1

func _capture(name: String) -> void:
	var directory: String = OS.get_environment("TIP_MVP_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	_expect(get_window().size == Vector2i(1200, 675) and frame.get_size() == Vector2i(400, 225), "Render uses the configured window and logical viewport.")
	frame.save_png(directory.path_join(name + "-400x225.png"))
	frame.resize(1200, 675, Image.INTERPOLATE_NEAREST)
	frame.save_png(directory.path_join(name + "-1200x675.png"))

func _run() -> void:
	TimeComponentManager.set_process(false)
	var state: Node = CONSTRUCTION.new()
	add_child(state)
	state.phase = "empty"
	for item_id: String in state.get_requirements():
		Inventory.items[item_id] = state.get_requirements()[item_id]
	var panel: WorkshopPlotUI = PLOT_UI.instantiate()
	add_child(panel)
	panel.build_requested.connect(_on_build_requested)
	panel.closed.connect(_on_panel_closed)
	panel.open_menu(state)
	await get_tree().process_frame
	await get_tree().process_frame
	var title: Label = panel.get_node("Root/Center/Window/Margin/MainVBox/TitleHeader/TitleLabel")
	print("Build title frame: ", panel.window.get_global_rect(), " title: ", title.get_global_rect())
	var window_box: Rect2 = panel.window.get_global_rect()
	_expect(title.text == "BUILD WORKSHOP" and title.get_theme_font_size("font_size") == 12, "Build title and pixel-font size are preserved.")
	_expect(is_equal_approx(title.get_global_rect().position.y - window_box.position.y, 13.0), "Build title retains its existing visible top margin.")
	_expect(title.get_theme_font("font").get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= title.size.x, "Build title fits without horizontal clipping.")
	_check_footer(panel, "no workers")
	_expect(panel.assign_workers_button.has_focus() and await _can_focus(panel, panel.cancel_button), "Keyboard focus can reach Cancel from the initial Assign control.")
	await _capture("build-workshop")
	var worker_ids: Array[String] = []
	for index: int in range(8):
		var worker := WorkerData.new()
		worker.worker_id = "label_fixture_%d" % index
		worker.display_name = "Builder %d" % index
		WorkerDatabase.workers_by_id[worker.worker_id] = worker
		worker_ids.append(worker.worker_id)
	panel._selected_worker_ids = worker_ids
	panel._refresh_view()
	await get_tree().process_frame
	await get_tree().process_frame
	var first_card: Control = panel.worker_list.get_child(0)
	var scrollbar: HScrollBar = panel.worker_scroll.get_h_scroll_bar()
	_check_footer(panel, "eight workers")
	var visible_bottom: float = scrollbar.get_global_rect().position.y if scrollbar.visible else panel.worker_scroll.get_global_rect().end.y
	_expect(panel.worker_list.get_child_count() == 8 and scrollbar.visible, "All eight builders are present in the scrollable row.")
	_expect(first_card.get_global_rect().end.y <= visible_bottom + 0.1, "Builder portraits remain fully visible when the horizontal scrollbar is present.")
	await _capture("build-workshop-workers")
	var last_card: Control = panel.worker_list.get_child(7)
	panel.worker_scroll.ensure_control_visible(last_card)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(last_card.get_global_rect().end.x <= panel.worker_scroll.get_global_rect().end.x + 0.1, "The last builder can be reached by scrolling.")
	_expect(not panel.build_button.disabled and await _can_focus(panel, panel.build_button) and await _can_focus(panel, panel.cancel_button), "Keyboard focus can reach both enabled footer buttons.")
	Inventory.items.erase("wood_log")
	panel._refresh_view()
	await get_tree().process_frame
	await get_tree().process_frame
	_check_footer(panel, "workers and missing materials")
	_expect(panel.status_label.visible and panel.status_label.text == "Missing materials in Inventory.", "The missing-material status remains visible.")
	_expect(panel.status_label.get_line_count() * panel.status_label.get_line_height() <= panel.status_label.size.y, "The status text fits vertically without clipping.")
	await _capture("build-workshop-missing-material")
	panel.show_error("Materials changed; construction was not started.")
	await get_tree().process_frame
	await get_tree().process_frame
	_check_footer(panel, "workers and construction error")
	_expect(panel.status_label.visible and panel.status_label.get_line_count() * panel.status_label.get_line_height() <= panel.status_label.size.y, "A construction error remains readable without clipping.")
	if panel.status_label.get_line_count() == 1:
		var status_width: float = panel.status_label.get_theme_font("font").get_string_size(panel.status_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, panel.status_label.get_theme_font_size("font_size")).x
		_expect(status_width <= panel.status_label.size.x, "The construction error fits horizontally without clipping.")
	await _capture("build-workshop-error")
	Inventory.items["wood_log"] = state.get_requirements()["wood_log"]
	panel._status_override = ""
	state.phase = "uncleared"
	panel._selected_worker_ids.clear()
	panel._refresh_view()
	await get_tree().process_frame
	await get_tree().process_frame
	_check_footer(panel, "clearing")
	_expect(title.text == "CLEAR SITE" and not panel.materials_list.visible, "The neighboring clearing layout retains its title and content.")
	state.phase = "building"
	panel._refresh_view()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(panel.progress_page.visible and panel.window.get_global_rect().encloses(panel.progress_close_button.get_global_rect()) and panel.progress_close_button.has_focus(), "The progress page keeps its Close button inside the frame and focused.")
	state.phase = "empty"
	panel._selected_worker_ids = worker_ids
	panel._refresh_view()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not panel.build_button.disabled, "Build is enabled before the Cancel check.")
	var inventory_before_cancel: Dictionary = Inventory.items.duplicate(true)
	panel.cancel_button.grab_focus()
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = "ui_accept"
	get_viewport().push_input(event)
	await get_tree().process_frame
	_expect(build_requests == 0 and close_requests == 1 and state.phase == "empty" and Inventory.items == inventory_before_cancel, "Cancel closes once without starting construction or consuming inventory.")
	state.free()
	for worker_id: String in worker_ids:
		WorkerDatabase.workers_by_id.erase(worker_id)
	var content: Node = CONTENT.instantiate()
	add_child(content)
	var plot: Node2D = content.get_node("YSortWorld/WorkshopPlot")
	plot.construction.phase = "empty"
	plot._sync_construction()
	_expect(plot.get_node("Label").text.is_empty(), "An empty plot has no floating building name.")
	var storage: Node = content.get_node("YSortWorld/WorkerRuntime/CityStorageArea")
	_expect(not storage.get_node("Label").visible and storage.get_node("DeliveryPoint").display_name == "City Storage", "City Storage hides only the world name and keeps its delivery identity.")
	_expect(content.get_node("YSortWorld/HomeDoor/Label").text == "Sleep", "The home action remains visible without the building name.")
	plot.construction.phase = "building"
	plot.construction.worker_ids = ["expired_label_fixture"] as Array[String]
	plot._sync_construction()
	_expect(plot.get_node("Label").text == "Contract expired" and plot.get_node("Label").visible, "Important contract-expiry feedback remains visible.")
	plot.construction.worker_ids.clear()
	plot.construction.phase = "empty"
	plot._sync_construction()
	plot.construction.phase = "built"
	plot._sync_construction()
	_expect(plot.get_node("Label").text.is_empty() and plot.get_node("FinishedBuilding").visible, "The completed workshop keeps its art and has no floating name.")
	_expect(plot.get_node("BuiltWorkshop/InteractableLabelComponent/NinePatchRect/Label").text == "E", "Completed workshop retains its E prompt.")
	var camera := Camera2D.new()
	camera.position = plot.global_position + Vector2(0, -5)
	camera.zoom = Vector2(2, 2)
	add_child(camera)
	camera.make_current()
	await _capture("built-workshop")
	content.free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("WorkshopLabelPresentationTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
