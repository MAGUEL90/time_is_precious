extends Node

## Isolated fixture: exercise the production dialog and physical City Storage API.
const CITY_UI: PackedScene = preload("res://scenes/storage_destination/city_storage_access_ui.tscn")
const CITY_STORAGE: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const HAUL_UI: PackedScene = preload("res://scenes/storage_destination/city_storage_haul_ui.tscn")
const BACK_ICON: Texture2D = preload("res://assets/ui/ui_icon/back_button.png")
const DEPOSIT_ICON: Texture2D = preload("res://assets/ui/ui_icon/deposit_icon.png")
const SEND_ICON: Texture2D = preload("res://assets/ui/ui_icon/send_forward_icon.png")

class HaulFixture extends Node:
	var route: Dictionary = {}
	var succeed: bool = false
	var calls: int = 0
	func eligible_workers() -> Array:
		return [{"worker_id": "test", "display_name": "Test"}]
	func available_items(_source: String) -> Dictionary:
		return {"stone": 2}
	func start(_worker: String, _source: String, _item: String, _quantity: int) -> bool:
		calls += 1
		return succeed

var failures: int = 0
var access_allowed: bool = true
var storage
var panel
var deposit_notifications: int = 0

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _select(transfer: ItemTransferUI, item_id: String, quantity: int) -> void:
	for slot: ItemSlot in transfer.grid_container.get_children():
		if slot._item_id == item_id:
			for _index: int in range(quantity):
				transfer._on_item_slot_clicked(item_id, int(transfer.source_items[item_id]), slot)
			return
	_expect(false, "Missing deposit slot: " + item_id)

func _stock_changed() -> void:
	deposit_notifications += 1

func _capture(filename: String) -> void:
	var directory: String = OS.get_environment("TIP_STORAGE_FEEDBACK_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_expect(get_viewport().get_texture().get_image().save_png(directory.path_join(filename)) == OK, "Saved feedback screenshot: " + filename)

func _run() -> void:
	TimeComponentManager.is_paused = true
	Inventory.items.clear()
	Inventory.items["shekel"] = 3
	Inventory.items["stone"] = 2
	CityStockManager.treasury_shekel = 100
	storage = CITY_STORAGE.new()
	add_child(storage)
	storage.changed.connect(_stock_changed)
	panel = CITY_UI.instantiate()
	add_child(panel)
	panel.open(storage, func() -> bool: return access_allowed)
	var physical_c := InputEventKey.new()
	physical_c.keycode = KEY_C
	physical_c.physical_keycode = KEY_C
	physical_c.pressed = true
	get_viewport().push_input(physical_c)
	await get_tree().process_frame
	_expect(is_instance_valid(panel) and panel.visible and get_tree().paused,
		"C does not close physical City Storage.")
	panel._open_transfer("deposit")
	var transfer: ItemTransferUI = panel.transfer_ui
	_expect(Inventory.items.get("shekel", 0) == 3 and CityStockManager.treasury_shekel == 100 and storage.items.is_empty(), "Opening deposit changes no balances.")
	_expect(not transfer.close_button.visible and transfer.back_button.visible, "Deposit offers Back without duplicate Close.")
	_expect(transfer.back_button.text == "Back" and transfer.back_button.icon == BACK_ICON
		and transfer.back_button.icon.get_size() == Vector2(16, 16)
		and transfer.confirm_button.text == "Deposit" and transfer.confirm_button.icon == DEPOSIT_ICON,
		"The City Storage deposit dialog keeps labeled Back and Deposit actions with native icons.")
	var transfer_window: Control = transfer.get_node("Root/Center/Window") as Control
	_expect(panel.clear_button.custom_minimum_size == Vector2(64, 18)
		and transfer.back_button.custom_minimum_size == Vector2(64, 18)
		and transfer.confirm_button.custom_minimum_size == Vector2(64, 18)
		and transfer_window.custom_minimum_size == Vector2(240, 156),
		"City Storage deposit actions fit in the compact transfer dialog.")
	await get_tree().process_frame
	await get_tree().process_frame
	var transfer_rect: Rect2 = transfer_window.get_global_rect()
	var title_font: Font = transfer.title_label.get_theme_font("font")
	_expect(title_font.get_string_size(transfer.title_label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, transfer.title_label.get_theme_font_size("font_size")).x <= transfer.title_label.size.x,
		"The Deposit title is fully visible inside the smaller frame.")
	_expect(transfer.title_label.get_theme_font_size("font_size") == 12, "The Deposit title uses the crisp native 12-pixel font size.")
	_expect(transfer.item_scroll.size.y == 76 and transfer.grid_container.columns == 6 and not transfer.item_scroll.get_v_scroll_bar().visible,
		"Deposit keeps three item rows and hides its scrollbar for short lists.")
	var transfer_back_rect: Rect2 = transfer.back_button.get_global_rect()
	var clear_rect: Rect2 = panel.clear_button.get_global_rect()
	var deposit_rect: Rect2 = transfer.confirm_button.get_global_rect()
	_expect(is_equal_approx(clear_rect.position.x - transfer_back_rect.end.x, 8.0)
		and is_equal_approx(deposit_rect.position.x - clear_rect.end.x, 8.0),
		"Back, Clear and Deposit are separated by equal eight-pixel gaps.")
	_expect(is_equal_approx(transfer_back_rect.position.x - transfer_rect.position.x, 16.0)
		and is_equal_approx(transfer_rect.end.y - transfer_back_rect.end.y, 16.0)
		and transfer.selected_summary_label.get_global_rect().end.y <= transfer_back_rect.position.y
		and not transfer_back_rect.intersects(panel.clear_button.get_global_rect())
		and not panel.clear_button.get_global_rect().intersects(transfer.confirm_button.get_global_rect()),
		"Deposit places Back in the lower-left inset with the summary and other actions clear of it.")
	_expect(transfer.transfer_confirmed.get_connections().size() == 1, "Deposit has one commit callback.")
	var many_items: Dictionary = {}
	for item: ItemData in ItemDatabase.get_all_items():
		if many_items.size() < 24:
			many_items[item.id] = 1
	_expect(many_items.size() == 24, "Scroll fixture contains four item rows.")
	transfer.open_transfer("Deposit to City (no return)", many_items, "Deposit")
	for i in range(5):
		await get_tree().process_frame
	var scrollbar: VScrollBar = transfer.item_scroll.get_v_scroll_bar()
	_expect(scrollbar.visible and scrollbar.size == Vector2(8, 76) and scrollbar.get_theme_stylebox("scroll") is StyleBoxTexture,
		"Long Deposit lists show the same fixed three-row scrollbar as Inventory.")
	var grabber: StyleBoxTexture = scrollbar.get_theme_stylebox("grabber") as StyleBoxTexture
	var highlight: AtlasTexture = grabber.texture as AtlasTexture if is_instance_valid(grabber) else null
	_expect(highlight != null and highlight.atlas == panel.ITEM_SCROLLBAR_TEXTURE and highlight.region == Rect2(3, 3, 2, 1),
		"Deposit scrollbar uses the existing yellow highlight asset.")
	await _capture("city-deposit-compact-scroll.png")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = transfer.item_scroll.get_global_rect().get_center()
	wheel.global_position = wheel.position
	get_viewport().push_input(wheel, true)
	wheel = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.position = transfer.item_scroll.get_global_rect().get_center()
	wheel.global_position = wheel.position
	get_viewport().push_input(wheel, true)
	await get_tree().process_frame
	_expect(transfer.item_scroll.scroll_vertical > 0, "Mouse wheel scrolls the Deposit item list.")
	transfer.item_scroll.scroll_vertical = 0
	await get_tree().process_frame
	var start: Vector2 = scrollbar.get_global_rect().position + Vector2(scrollbar.size.x * 0.5, 5.0)
	var end: Vector2 = scrollbar.get_global_rect().position + Vector2(scrollbar.size.x * 0.5, scrollbar.size.y - 5.0)
	var hover := InputEventMouseMotion.new()
	hover.position = start
	hover.global_position = start
	get_viewport().push_input(hover, true)
	await get_tree().process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = start
	click.global_position = start
	get_viewport().push_input(click, true)
	await get_tree().process_frame
	var drag := InputEventMouseMotion.new()
	drag.position = end
	drag.global_position = end
	drag.relative = end - start
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(drag, true)
	await get_tree().process_frame
	click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = end
	click.global_position = end
	get_viewport().push_input(click, true)
	await get_tree().process_frame
	_expect(transfer.item_scroll.scroll_vertical > 0, "Dragging the yellow scrollbar scrolls the Deposit list.")
	panel._refresh_transfer()
	for i in range(3):
		await get_tree().process_frame
	_select(transfer, "shekel", 1)
	_select(transfer, "stone", 1)
	transfer.confirm_button.pressed.emit()
	await get_tree().process_frame
	_expect(is_instance_valid(transfer) and panel.transfer_ui == transfer and transfer.visible and get_tree().paused, "First deposit retains the same paused dialog.")
	_expect(Inventory.items.get("shekel", 0) == 2 and Inventory.items.get("stone", 0) == 1, "First selection leaves the remaining inventory available.")
	_expect(CityStockManager.treasury_shekel == 101 and storage.items.get("stone", 0) == 1 and not storage.items.has("shekel"), "Physical deposit routes shekels into treasury and resources into city stock.")
	_expect(panel._currency_amounts[0].text == "0" and panel._currency_amounts[1].text == "0" and panel._currency_amounts[2].text == "0", "Currency placeholders remain unchanged after deposit.")
	_expect(panel.feedback.visible and panel.feedback.text == "Deposited." and panel.feedback.get_parent() == transfer_window and panel.feedback.get_theme_color("font_color") == Color(0.28, 0.68, 0.31), "Successful deposit shows green feedback in the transfer panel.")
	await get_tree().create_timer(0.45, true).timeout
	await _capture("city-deposit-success-feedback.png")
	_expect(transfer.selected_items.is_empty() and transfer.confirm_button.disabled, "Success clears selection and prevents a duplicate commit.")
	transfer.confirm_button.pressed.emit()
	_expect(deposit_notifications == 1, "An unselected repeated confirm cannot deposit again.")
	# A rejected provider transaction must keep the dialog available for correction.
	storage._transfer_in_progress = true
	_select(transfer, "stone", 1)
	transfer.confirm_button.pressed.emit()
	_expect(transfer.visible and panel.feedback.visible and not panel.feedback.text.is_empty() and panel.feedback.get_theme_color("font_color") == Color(0.90, 0.38, 0.32) and not transfer.feedback_label.visible, "Rejected deposit shows red overlay feedback.")
	await get_tree().create_timer(0.2, true).timeout
	await _capture("city-deposit-failure-feedback.png")
	_expect(panel.feedback.get_theme_color("font_shadow_color").is_equal_approx(Color(0.12, 0.08, 0.05, 0.85)) and panel.feedback.get_theme_constant("shadow_offset_x") == 1 and panel.feedback.get_theme_constant("shadow_offset_y") == 1, "Transaction feedback uses the previous dark one-pixel shadow.")
	for is_error: bool in [false, true]:
		panel._show_transaction_feedback("Motion check", is_error)
		var origin: Vector2 = panel.feedback.position
		var moved_x := false
		var moved_y := false
		var finish: int = Time.get_ticks_msec() + 800
		while Time.get_ticks_msec() < finish:
			await get_tree().process_frame
			moved_x = moved_x or absf(panel.feedback.position.x - origin.x) > 0.1
			moved_y = moved_y or absf(panel.feedback.position.y - origin.y) > 0.1
		_expect(moved_x == is_error and moved_y == not is_error, "Transaction feedback shakes for failure and bounces for success.")
	var long_message: String = "A long deposit failure message must remain readable without changing the panel or cutting any words."
	var pages: Array[String] = panel._split_transaction_feedback(long_message)
	_expect(pages.size() > 1 and " ".join(pages) == long_message, "Long transaction feedback retains all words.")
	var stable_transfer_rect: Rect2 = transfer_window.get_global_rect()
	panel._show_transaction_feedback(long_message, true)
	await get_tree().create_timer(0.2, true).timeout
	for index in range(pages.size()):
		_expect(panel.feedback.text == pages[index] and panel.feedback.modulate.a > 0.9, "Each part of a long message becomes visible.")
		_expect(transfer_window.get_global_rect() == stable_transfer_rect, "Transaction feedback does not resize the panel.")
		if index + 1 < pages.size():
			var deadline: int = Time.get_ticks_msec() + 5000
			while panel.feedback.text != pages[index + 1] and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
	await get_tree().create_timer(2.0, true).timeout
	_expect(not panel.feedback.visible, "Feedback fades out while the game is paused.")
	_expect(Inventory.items.get("stone", 0) == 1 and storage.items.get("stone", 0) == 1, "Rejected deposit changes no stock.")
	storage._transfer_in_progress = false
	_select(transfer, "shekel", 2)
	_select(transfer, "stone", 1)
	transfer.confirm_button.pressed.emit()
	await get_tree().process_frame
	_expect(panel.transfer_ui == transfer and transfer.visible and get_tree().paused, "Second deposit still retains the same dialog.")
	_expect(Inventory.items.is_empty() and CityStockManager.treasury_shekel == 103 and storage.items.get("stone", 0) == 2, "Repeated deposit transfers exactly the remaining selection.")
	_expect(deposit_notifications == 2 and transfer.transfer_confirmed.get_connections().size() == 1, "Repeated refresh does not duplicate callbacks or commits.")
	_expect(transfer.selected_summary_label.text == "No items to deposit." and transfer.confirm_button.disabled and transfer.grid_container.get_child_count() == 0, "Empty source shows its empty state and disables Deposit.")
	var summary_text_width: float = transfer.selected_summary_label.get_theme_font("font").get_string_size(
		transfer.selected_summary_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		transfer.selected_summary_label.get_theme_font_size("font_size")).x
	_expect(summary_text_width <= transfer.selected_summary_label.size.x,
		"The empty-state summary remains readable after moving Back.")
	transfer.back_button.pressed.emit()
	await get_tree().process_frame
	_expect(panel.transfer_ui == null and panel.get_node("Root").visible and get_tree().paused, "Back returns to City Storage and keeps the owner pause.")
	_expect(not panel.feedback.visible, "Returning does not show feedback.")
	panel.view.get_node("Margin/Content/Footer/Back").pressed.emit()
	await get_tree().process_frame
	_expect(not get_tree().paused, "Leaving City Storage restores the original pause state.")
	# Reopen with supplies, then lose access before Confirm.
	Inventory.items["shekel"] = 1
	panel = CITY_UI.instantiate()
	add_child(panel)
	panel.open(storage, func() -> bool: return access_allowed)
	panel._open_transfer("deposit")
	transfer = panel.transfer_ui
	_select(transfer, "shekel", 1)
	access_allowed = false
	transfer.confirm_button.pressed.emit()
	await get_tree().process_frame
	_expect(Inventory.items.get("shekel", 0) == 1 and CityStockManager.treasury_shekel == 103 and deposit_notifications == 2, "Losing access blocks deposit before any balance changes.")
	_expect(not is_instance_valid(panel) and not get_tree().paused, "Access loss closes the dialog and releases its pause.")
	# Hub browsing must not bypass the physical Deposit or Send requirement.
	access_allowed = true
	var transport := Node.new()
	add_child(transport)
	transport.add_to_group("city_storage_transport")
	panel = CITY_UI.instantiate()
	add_child(panel)
	panel.open(storage, func() -> bool: return access_allowed, "city", true)
	_expect(panel.deposit_button.disabled and panel.haul_button.disabled and not panel.context.visible,
		"Remote storage keeps Deposit and Send disabled without a message below the title.")
	var main_back: Button = panel.view.get_node("Margin/Content/Footer/Back") as Button
	_expect(main_back.icon == BACK_ICON and main_back.text == "Back"
		and panel.deposit_button.icon == DEPOSIT_ICON and panel.deposit_button.text == "Deposit"
		and panel.haul_button.icon == SEND_ICON and panel.haul_button.text == "Send"
		and main_back.custom_minimum_size == Vector2(64, 18)
		and panel.deposit_button.custom_minimum_size == Vector2(64, 18)
		and panel.haul_button.custom_minimum_size == Vector2(64, 18),
		"City Storage Back, Deposit and Send use their native icons, labels and equal button widths.")
	panel._open_transfer("deposit")
	panel._open_haul()
	_expect(not is_instance_valid(panel.transfer_ui) and not is_instance_valid(panel.haul_ui)
		and Inventory.items.get("shekel", 0) == 1 and CityStockManager.treasury_shekel == 103,
		"Direct calls cannot use remote storage to transfer stock.")
	panel.close()
	transport.free()
	await get_tree().process_frame
	_expect(not get_tree().paused, "Leaving remote storage releases its pause.")
	storage.free()
	var haul_view: Control = HAUL_UI.instantiate()
	add_child(haul_view)
	var fixture := HaulFixture.new()
	add_child(fixture)
	var outcomes: Array = []
	haul_view.action_feedback.connect(func(message: String, is_error: bool): outcomes.append([message, is_error]))
	haul_view.open(fixture, "city")
	haul_view._start_route()
	_expect(fixture.calls == 1 and outcomes.size() == 1 and outcomes[0][1] and not haul_view.feedback_label.visible, "Failed Send emits failure feedback.")
	fixture.succeed = true
	haul_view._start_route()
	_expect(fixture.calls == 2 and outcomes.size() == 2 and not outcomes[1][1] and not haul_view.feedback_label.visible, "Successful Send emits success feedback.")
	fixture.free()
	haul_view.show()
	await get_tree().process_frame
	await get_tree().process_frame
	var haul_panel: Control = haul_view.get_node("Center/Panel") as Control
	var haul_content: Control = haul_view.get_node("Center/Panel/Margin/Content") as Control
	var haul_footer: Control = haul_view.get_node("Center/Panel/Margin/Content/Footer") as Control
	var haul_back: Button = haul_footer.get_node("Back") as Button
	var start_button: Button = haul_footer.get_node("Start") as Button
	var cancel_route_button: Button = haul_footer.get_node("CancelRoute") as Button
	_expect(start_button.custom_minimum_size == Vector2(64, 18)
		and cancel_route_button.custom_minimum_size == Vector2(64, 18)
		and haul_back.custom_minimum_size == Vector2(64, 18)
		and cancel_route_button.text == "Cancel Route" and haul_back.icon == BACK_ICON,
		"Hauling actions share 64x18 controls while preserving the Cancel Route label and Back icon.")
	var haul_panel_rect: Rect2 = haul_panel.get_global_rect()
	var haul_content_rect: Rect2 = haul_content.get_global_rect()
	var haul_back_rect: Rect2 = haul_back.get_global_rect()
	_expect(is_equal_approx(haul_back_rect.position.x - haul_panel_rect.position.x, 16.0)
		and is_equal_approx(haul_panel_rect.end.y - haul_back_rect.end.y, 16.0)
		and not haul_back_rect.intersects(start_button.get_global_rect())
		and not haul_back_rect.intersects(cancel_route_button.get_global_rect()),
		"Hauling places Back in the lower-left inset without overlapping other actions.")
	_expect(is_equal_approx(haul_content_rect.position.x - haul_panel_rect.position.x, 16.0)
		and is_equal_approx(haul_panel_rect.end.x - haul_content_rect.end.x, 16.0)
		and is_equal_approx(haul_content_rect.position.y - haul_panel_rect.position.y, 16.0)
		and is_equal_approx(haul_panel_rect.end.y - haul_content_rect.end.y, 16.0)
		and haul_panel_rect.encloses(haul_footer.get_global_rect()),
		"The hauling panel retains 16-pixel insets and contains the footer controls.")
	haul_view.queue_free()
	await get_tree().process_frame
	print("ContentDepositUITest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)
