extends Node

## Isolated fixture: exercise the production dialog and physical City Storage API.
const CITY_UI: PackedScene = preload("res://scenes/storage_destination/city_storage_access_ui.tscn")
const CITY_STORAGE: Script = preload("res://scenes/storage_destination/city_tool_storage.gd")
const HAUL_UI: PackedScene = preload("res://scenes/storage_destination/city_storage_haul_ui.tscn")
const BACK_ICON: Texture2D = preload("res://assets/ui/ui_icon/back_button.png")
const DEPOSIT_ICON: Texture2D = preload("res://assets/ui/ui_icon/deposit_icon.png")
const SEND_ICON: Texture2D = preload("res://assets/ui/ui_icon/send_forward_icon.png")

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
	_expect(transfer.back_button.text.is_empty() and transfer.back_button.accessibility_name == "Back" and transfer.back_button.icon == BACK_ICON
		and transfer.back_button.icon.get_size() == Vector2(16, 16)
		and transfer.confirm_button.text.is_empty() and transfer.confirm_button.accessibility_name == "Deposit" and transfer.confirm_button.icon == DEPOSIT_ICON,
		"The City Storage deposit dialog uses native icon-only Back and Deposit actions.")
	var transfer_window: Control = transfer.get_node("Root/Center/Window") as Control
	_expect(panel.clear_button.custom_minimum_size == Vector2(64, 18)
		and transfer.back_button.custom_minimum_size == Vector2(16, 16)
		and transfer.confirm_button.custom_minimum_size == Vector2(16, 16)
		and transfer_window.custom_minimum_size.x == 300.0,
		"City Storage deposit uses compact icon actions and retains the labeled Clear button.")
	_expect(transfer.transfer_confirmed.get_connections().size() == 1, "Deposit has one commit callback.")
	_select(transfer, "shekel", 1)
	_select(transfer, "stone", 1)
	transfer.confirm_button.pressed.emit()
	await get_tree().process_frame
	_expect(is_instance_valid(transfer) and panel.transfer_ui == transfer and transfer.visible and get_tree().paused, "First deposit retains the same paused dialog.")
	_expect(Inventory.items.get("shekel", 0) == 2 and Inventory.items.get("stone", 0) == 1, "First selection leaves the remaining inventory available.")
	_expect(CityStockManager.treasury_shekel == 101 and storage.items.get("stone", 0) == 1 and not storage.items.has("shekel"), "Physical deposit routes shekels into treasury and resources into city stock.")
	_expect(panel._currency_amounts[0].text == "--" and panel._currency_amounts[1].text == "101" and panel._currency_amounts[2].text == "--", "Treasury shows the actual Shekel balance and unavailable denominations after deposit.")
	_expect(transfer.selected_items.is_empty() and transfer.confirm_button.disabled, "Success clears selection and prevents a duplicate commit.")
	transfer.confirm_button.pressed.emit()
	_expect(deposit_notifications == 1, "An unselected repeated confirm cannot deposit again.")
	# A rejected provider transaction must keep the dialog available for correction.
	storage._transfer_in_progress = true
	_select(transfer, "stone", 1)
	transfer.confirm_button.pressed.emit()
	_expect(transfer.visible and transfer.feedback_label.visible and not transfer.feedback_label.text.is_empty(), "Transaction rejection stays in the dialog with feedback.")
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
	transfer.back_button.pressed.emit()
	await get_tree().process_frame
	_expect(panel.transfer_ui == null and panel.get_node("Root").visible and get_tree().paused, "Back returns to City Storage and keeps the owner pause.")
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
	_expect(main_back.icon == BACK_ICON and main_back.text.is_empty() and main_back.accessibility_name == "Back"
		and panel.deposit_button.icon == DEPOSIT_ICON and panel.deposit_button.text.is_empty() and panel.deposit_button.accessibility_name == "Deposit"
		and panel.haul_button.icon == SEND_ICON and panel.haul_button.text.is_empty() and panel.haul_button.accessibility_name == "Send"
		and main_back.custom_minimum_size == Vector2(16, 16)
		and panel.deposit_button.custom_minimum_size == Vector2(16, 16)
		and panel.haul_button.custom_minimum_size == Vector2(16, 16),
		"City Storage Back, Deposit and Send use 16x16 icon-only controls with accessible names.")
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
		and haul_back.custom_minimum_size == Vector2(16, 16)
		and cancel_route_button.text == "Cancel Route" and haul_back.text.is_empty()
		and haul_back.accessibility_name == "Back" and haul_back.icon == BACK_ICON,
		"Hauling keeps its labeled actions and a 16x16 icon-only Back control.")
	var haul_panel_rect: Rect2 = haul_panel.get_global_rect()
	var haul_content_rect: Rect2 = haul_content.get_global_rect()
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
