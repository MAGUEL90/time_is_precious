extends Node
var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	TimeComponentManager.set_process(false)
	var map = load("res://scenes/content_scene/content_scene.tscn").instantiate()
	add_child(map)
	await get_tree().process_frame
	var ui = map.get_node("InventoryUI")
	ui.open_inventory()
	for i in range(4):
		await get_tree().process_frame
	var initial_rect: Rect2 = ui.inventory_window.get_global_rect()
	Inventory.items = {"wood_log": 2}
	Inventory.items_changed.emit()
	await ui._execute_drop_item("wood_log", 1)
	await get_tree().create_timer(0.8, true).timeout
	check(ui.action_feedback_label.text.begins_with("Dropped "), "Successful drop displays feedback")
	check(ui.action_feedback_label.get_theme_color("font_color") == Color(0.28, 0.68, 0.31, 1.0), "Successful feedback is subdued green")
	check(ui.action_feedback_label.get_theme_color("font_shadow_color").is_equal_approx(Color(0.12, 0.08, 0.05, 0.85)) and ui.action_feedback_label.get_theme_constant("shadow_offset_x") == 1 and ui.action_feedback_label.get_theme_constant("shadow_offset_y") == 1, "Feedback uses the previous dark one-pixel shadow")
	check(ui.inventory_window.get_global_rect() == initial_rect, "Success does not resize or move Inventory")
	await capture("inventory-feedback-success.png")
	ui._execute_drop_item("wood_log", 99)
	await get_tree().create_timer(0.8, true).timeout
	check(ui.action_feedback_label.text.begins_with("Not enough "), "Failed drop displays feedback")
	check(ui.action_feedback_label.get_theme_color("font_color") == Color(0.90, 0.38, 0.32, 1.0), "Failure feedback uses the clearer red")
	check(ui.inventory_window.get_global_rect() == initial_rect, "Failure does not resize or move Inventory")
	await capture("inventory-feedback-failure.png")
	var long_message := "This is a deliberately long feedback message to verify that even multiple wrapped lines cannot resize the inventory panel."
	var pages: Array[String] = ui._split_feedback_pages(long_message)
	check(pages.size() > 1 and " ".join(pages) == long_message, "Long feedback retains the entire message across pages")
	var font: Font = ui.action_feedback_label.get_theme_font("font")
	for page: String in pages:
		check(font.get_string_size(page, HORIZONTAL_ALIGNMENT_LEFT, -1, ui.action_feedback_label.get_theme_font_size("font_size")).x <= ui.action_feedback_label.size.x, "Each feedback page fits within the label")
	ui._show_inventory_feedback(long_message, true)
	await get_tree().create_timer(0.8, true).timeout
	check(ui.inventory_window.get_global_rect() == initial_rect, "Long feedback cannot resize or move Inventory")
	for index in range(pages.size()):
		check(ui.action_feedback_label.text == pages[index] and ui.action_feedback_label.modulate.a == 1.0, "Each feedback page becomes visible")
		check(ui.inventory_window.get_global_rect() == initial_rect, "Changing pages preserves panel size and position")
		await capture("inventory-feedback-long-%d.png" % index)
		if index < pages.size() - 1:
			var page_deadline: int = Time.get_ticks_msec() + 5000
			while ui.action_feedback_label.text != pages[index + 1] and Time.get_ticks_msec() < page_deadline:
				await get_tree().process_frame
	var long_word := "SupercalifragilisticexpialidociousSupercalifragilisticexpialidocious"
	var word_pages: Array[String] = ui._split_feedback_pages("Test " + long_word + " selesai")
	check(word_pages.has(long_word), "An oversized word is never split between pages")
	ui._show_inventory_feedback(long_word, true)
	await get_tree().process_frame
	check(ui.action_feedback_label.text == long_word, "The complete oversized word is displayed")
	check(font.get_string_size(long_word, HORIZONTAL_ALIGNMENT_LEFT, -1, ui.action_feedback_label.get_theme_font_size("font_size")).x <= ui.action_feedback_label.size.x, "The oversized word fits inside the label")
	check(ui.inventory_window.get_global_rect() == initial_rect, "Fitting a long word does not resize Inventory")
	ui._show_inventory_feedback("Normal", false)
	check(ui.action_feedback_label.get_theme_font_size("font_size") == ui.feedback_base_font_size, "Normal text restores the original font size")
	ui._clear_inventory_feedback()
	for i in range(4):
		await get_tree().process_frame
	check(ui.inventory_window.get_global_rect() == initial_rect, "Clearing feedback cannot resize or move Inventory")
	for is_error: bool in [false, true]:
		ui._show_inventory_feedback("Motion check", is_error)
		var origin: Vector2 = ui.action_feedback_label.position
		var moved_x := false
		var moved_y := false
		var started_faded: bool = is_zero_approx(ui.action_feedback_label.modulate.a)
		var until: int = Time.get_ticks_msec() + 800
		while Time.get_ticks_msec() < until:
			await get_tree().process_frame
			moved_x = moved_x or absf(ui.action_feedback_label.position.x - origin.x) > 0.1
			moved_y = moved_y or absf(ui.action_feedback_label.position.y - origin.y) > 0.1
		check(started_faded and moved_x == is_error and moved_y == not is_error,
			"Feedback fades in, shakes on failure and bounces on success")
		check(ui.inventory_window.get_global_rect() == initial_rect, "Motion never moves the Inventory panel")
	ui._show_inventory_feedback("First")
	var first: Tween = ui.action_feedback_tween
	ui._show_inventory_feedback("Second")
	check(not first.is_valid(), "Replacement cancels previous feedback")
	check(ui.action_feedback_label.text == "Second", "Newest feedback visible")
	await get_tree().create_timer(0.8, true).timeout
	var deadline: int = Time.get_ticks_msec() + 5000
	while ui.action_feedback_label.modulate.a > 0.0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(is_zero_approx(ui.action_feedback_label.modulate.a), "Feedback expires even while inventory pauses game")
	check(ui.inventory_window.get_global_rect() == initial_rect, "Expired feedback cannot resize or move Inventory")
	ui._show_inventory_feedback("Closing")
	var closing: Tween = ui.action_feedback_tween
	ui._clear_inventory_feedback()
	check(not closing.is_valid(), "Clearing feedback cancels pending hide")
	ui.close_inventory()
	ui._show_inventory_feedback("Scene exit")
	var leaving: Tween = ui.action_feedback_tween
	map.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not leaving.is_valid(), "Scene exit destroys pending feedback")
	print("InventoryFeedbackLifecycleTest: ", "PASS" if failures == 0 else "FAIL")
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)

func capture(filename: String) -> void:
	var directory := OS.get_environment("TIP_INVENTORY_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(directory.path_join(filename)) == OK, "Feedback screenshot saved")
