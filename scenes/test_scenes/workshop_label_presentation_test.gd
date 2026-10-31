extends Node2D

## Isolated visual fixture: no save files, transactions, or progression are used.
const PLOT_UI: PackedScene = preload("res://scenes/ui/workshop_plot_ui/workshop_plot_ui.tscn")
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const CONSTRUCTION: Script = preload("res://scenes/workshop_plot/workshop_construction_state.gd")
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

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
	panel.open_menu(state)
	await get_tree().process_frame
	await get_tree().process_frame
	var title: Label = panel.get_node("Root/Center/Window/Margin/MainVBox/TitleHeader/TitleLabel")
	print("Build title frame: ", panel.window.get_global_rect(), " title: ", title.get_global_rect())
	var window_box: Rect2 = panel.window.get_global_rect()
	_expect(title.text == "BUILD WORKSHOP" and title.get_theme_font_size("font_size") == 12, "Build title and pixel-font size are preserved.")
	_expect(title.get_global_rect().position.y >= window_box.position.y + 12.0, "Build title has a clear top margin inside its frame.")
	_expect(title.get_theme_font("font").get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= title.size.x, "Build title fits without horizontal clipping.")
	_expect(window_box.end.y - panel.cancel_button.get_global_rect().end.y >= 8.0 and window_box.end.y - panel.build_button.get_global_rect().end.y >= 8.0, "Footer buttons remain inside the lower frame.")
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
	var visible_bottom: float = scrollbar.get_global_rect().position.y if scrollbar.visible else panel.worker_scroll.get_global_rect().end.y
	_expect(panel.worker_list.get_child_count() == 8 and scrollbar.visible, "All eight builders are present in the scrollable row.")
	_expect(first_card.get_global_rect().end.y <= visible_bottom + 0.1, "Builder portraits remain fully visible when the horizontal scrollbar is present.")
	await _capture("build-workshop-workers")
	var last_card: Control = panel.worker_list.get_child(7)
	panel.worker_scroll.ensure_control_visible(last_card)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(last_card.get_global_rect().end.x <= panel.worker_scroll.get_global_rect().end.x + 0.1, "The last builder can be reached by scrolling.")
	panel.free()
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
	print("WorkshopLabelPresentationTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
