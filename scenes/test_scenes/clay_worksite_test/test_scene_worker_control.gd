extends Node

var failures: int = 0
var fixture
var ids: Array[String] = ["control_laborer", "control_hauler", "control_other"]

func _ready() -> void:
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	fixture = preload("res://scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.tscn").instantiate()
	fixture.prepare_nightmare_test = false
	fixture.test_hauler_carts = 1
	add_child(fixture)
	fixture.player.debug_disable_player_needs = true
	var management = fixture.worker_management
	var glove: ItemData = ItemDatabase.get_item_data("basic_glove")
	_expect(glove != null and glove.category == ItemEnums.ItemCategory.EQUIPMENT and glove.icon != null, "Basic Glove is registered equipment with supplied icon.")
	for index: int in range(ids.size()):
		var worker := WorkerData.new()
		worker.worker_id = ids[index]
		worker.display_name = ids[index]
		worker.profession = WorkerData.Profession.LABORER if index == 0 else WorkerData.Profession.HAULER
		WorkerDatabase.workers_by_id[worker.worker_id] = worker
	fixture.city_tools.add_tool_unit("hammer_a", "stone_hammer", "Stone Hammer A")
	fixture.city_tools.add_tool_unit("hammer_b", "stone_hammer", "Stone Hammer B")
	fixture.city_tools.add_tool_unit("glove_a", "basic_glove", "Basic Glove")
	_expect(management.tool_slot("basic_glove") == "hands", "Glove occupies Primary independently of requirements.")
	_expect(management.equip(ids[0], "glove_a") == "Tool equipped.", "Laborer can equip optional glove.")
	_expect(management.unequip(ids[0], "glove_a") == "Tool returned to City Storage.", "Optional glove can be returned before assignment.")
	_expect(management.equip(ids[0], "hammer_a") == "Tool equipped.", "Optional tool equips on Laborer.")
	_expect(management.equip(ids[0], "glove_a") == "Tool equipped.", "Hands glove and Tool hammer can be equipped together.")
	_expect(management.equip(ids[2], "glove_a") != "Tool equipped.", "Glove cannot be shared between workers.")
	_expect(management.equip(ids[0], "hammer_b") != "Tool equipped.", "One equipment slot cannot contain two tool units.")
	_expect(management.equip(ids[2], "hammer_b") == "Tool equipped.", "Same tool type has separate physical units.")
	_expect(not fixture.daily.toggle(&"ClaySiteA", ids[1]), "Un-equipped Hauler cannot be assigned.")
	fixture._selected_site = fixture.get_node("WorksiteMarkers/ClaySiteA")
	var assignment = fixture.inspector.assignment_ui
	assignment.open_team(fixture._get_roster)
	assignment._open_worker_selection(0)
	assignment._on_worker_selected(ids[1])
	_expect(assignment.selection_title_label.text.begins_with("Requires a cart") and fixture.daily.selected[&"ClaySiteA"].is_empty(), "Missing cart shows requirement without assigning the worker.")
	await _capture("worker-cart-required.png")
	assignment.hide()
	_expect(management.equip(ids[1], "test_cart_0") == "Tool equipped.", "Hauler equips cart from City Storage.")
	_expect(management.equip(ids[2], "test_cart_0") != "Tool equipped.", "One cart cannot be shared.")
	var storage = preload("res://scenes/test_scenes/clay_worksite_test/hauler_test_storage.gd").new()
	fixture.add_child(storage)
	var destination = preload("res://scenes/storage_destination/storage_destination.tscn").instantiate()
	destination.position = Vector2(40, -45)
	fixture.add_child(destination)
	destination.storage_path = destination.get_path_to(storage)
	fixture.storage_destinations[&"ClaySiteA"] = fixture.get_path_to(destination)
	fixture.daily.toggle(&"ClaySiteA", ids[0])
	fixture.daily.select_hauler(&"ClaySiteA", ids[1], fixture.get_path_to(destination), destination.display_name, 1000)
	fixture.daily.start(&"ClaySiteA", fixture._drop_daily_output.bind(fixture.get_node("WorksiteMarkers/ClaySiteA")))
	var start: int = fixture.daily.jobs[&"ClaySiteA"].starts[ids[0]]
	TimeComponentManager.advance_minutes(start - fixture.daily.now() + 5)
	_expect(WorkerDatabase.get_worker_data(ids[0]).profession_xp == 0 and management.productive_days.get(ids[0], []).size() == 0, "Unfinished gathering gives no XP or productive day.")
	_expect(management.unequip(ids[0], "hammer_a") != "Tool returned to City Storage.", "Equipment cannot change during work.")
	_expect(management.unequip(ids[1], "test_cart_0") != "Tool returned to City Storage.", "Hauler cannot lose required cart during shift.")
	TimeComponentManager.advance_minutes(5)
	_expect(WorkerDatabase.get_worker_data(ids[0]).profession_xp == 1 and management.productive_days[ids[0]].size() == 1, "First completed clay awards one XP and one productive day.")
	TimeComponentManager.advance_minutes(60)
	_expect(WorkerDatabase.get_worker_data(ids[0]).profession_xp == 7, "Partial shift awards XP proportional to seven completed items.")
	_expect(storage.quantity >= 3 and WorkerDatabase.get_worker_data(ids[1]).profession_xp == storage.quantity, "Hauler earns XP only for successfully delivered items.")
	_expect(WorkerDatabase.get_worker_data(ids[0]).profession_star == 1, "No automatic level increase.")
	fixture.worker_control.open()
	_expect(fixture.worker_control.visible and get_tree().paused, "Worker Hub opens and pauses.")
	await _capture("worker-hub-status.png")
	var status_row: Control = fixture.worker_control.status_list.get_child(0)
	for index: int in [0, 2, 4]:
		_expect(status_row.get_child(index).size.x > 5, "Status text keeps its natural width.")
	_expect(fixture.worker_control.status_list.get_parent().get_v_scroll_bar().size.x <= 4.0, "Status scrollbar stays at four logical pixels.")
	_expect(fixture.worker_control.find_child("FooterCloseButton", true, false) == null, "Only the top close control remains.")
	fixture.worker_control._show_manage(ids[0])
	_expect(fixture.worker_control.manage_fire_button.disabled and not fixture.worker_control.manage_goto_button.disabled, "Working enables Go to and disables Fire.")
	fixture.worker_control.manage_details_button.pressed.emit()
	_expect(fixture.worker_control.details_label.text.contains("Productive days:") and fixture.worker_control.details_label.text.contains("Wage:"), "Details exposes requested worker data.")
	await _capture("worker-hub-details.png")
	fixture.worker_control._close_manage()
	fixture.worker_control._show_manage(ids[0])
	var player_before: Vector2 = fixture.player.global_position
	var camera_offset_before: Vector2 = fixture.player.get_node("Camera2D").offset
	fixture.worker_control.manage_goto_button.pressed.emit()
	_expect(not fixture.worker_control.visible and fixture.player.global_position == player_before, "Go to closes Hub without moving Player.")
	_expect(fixture.player.get_node("Camera2D").offset == camera_offset_before, "Go to leaves camera offset unchanged.")
	_expect(fixture.inspector.visible and fixture._selected_site.name == &"ClaySiteA", "Go to opens the assigned worksite panel.")
	_expect(not fixture.player.can_move, "Worksite panel locks movement.")
	await _capture("worker-hub-go-to-worksite.png")
	fixture._close_inspector()
	_expect(fixture.player.can_move and not get_tree().paused, "Closing worksite restores movement and releases Hub pause.")
	fixture.worker_control.open()
	fixture.worker_control.tools_tab_button.pressed.emit()
	fixture.worker_control._select_worker_for_tools(ids[0])
	await _capture("worker-hub-tools.png")
	var tools_positions := [fixture.worker_control.tools_tool_button.global_position, fixture.worker_control.tools_selected_label.global_position, fixture.worker_control.tools_preview_anchor.global_position]
	fixture.worker_control.set_feedback("")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(tools_positions == [fixture.worker_control.tools_tool_button.global_position, fixture.worker_control.tools_selected_label.global_position, fixture.worker_control.tools_preview_anchor.global_position], "Clearing feedback preserves slot, name and preview layout.")
	fixture.worker_control.set_feedback("Tools locked while working.")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(tools_positions == [fixture.worker_control.tools_tool_button.global_position, fixture.worker_control.tools_selected_label.global_position, fixture.worker_control.tools_preview_anchor.global_position], "Restoring feedback preserves layout.")
	_expect(fixture.worker_control.tools_worker_list.columns == 4, "Tools worker cards fill four columns before wrapping.")
	for card: Node in fixture.worker_control.tools_worker_list.get_children():
		if card.worker_id == ids[0]:
			card.details_button.pressed.emit()
			break
	_expect(fixture.worker_control.details_window.visible and fixture.worker_control.details_header_label.text == ids[0], "Card exclamation opens that worker's Details.")
	fixture.worker_control.details_close_button.pressed.emit()
	_expect(fixture.worker_control.tools_page.visible and not fixture.worker_control.details_window.visible, "Details close returns to Tools.")
	for card: Node in fixture.worker_control.tools_worker_list.get_children():
		if card.worker_id == ids[1]:
			card.pressed.emit()
			break
	_expect(fixture.worker_control.tools_selected_label.text == ids[1], "Selecting a portrait updates the worker name and equipment.")
	await _capture("worker-hub-hauler-tools.png")
	_expect(str(fixture.worker_control._tools_preview_visual.body_sprite.animation).contains("idle_cart"), "Equipped cart preview uses idle_cart.")
	_expect(fixture.worker_control._tools_preview_visual.cart_visual.visible, "Cart is visible in Hauler preview.")
	_expect(is_equal_approx(fixture.worker_control._tools_preview_visual.idle_anim_speed, 1.0 / 3.0), "Idle runs three times slower.")
	fixture.worker_control.tools_tool_button.pressed.emit()
	_expect(fixture.worker_control.city_storage_view.visible and not fixture.worker_control.window.visible, "Primary navigates directly to City Storage.")
	_expect(not fixture.worker_control.tools_picker_window.visible, "Primary skips the embedded picker.")
	var equipped_slot = _tool_action("test_cart_0")
	_expect(equipped_slot.selected_qty.visible and equipped_slot.selected_qty.text == "E", "Equipped tool uses the Inventory quantity highlight for E.")
	var categories = fixture.worker_control.city_storage_view.get_node("Margin/Content/Header/Categories")
	categories.next_button.pressed.emit()
	_expect(fixture.worker_control.city_storage_list.get_child(0) is ItemSlot, "Resource category contains empty slots when storage only has equipment.")
	categories.prev_button.pressed.emit()
	_expect(fixture.worker_control.city_storage_list.get_child_count() > 0, "City Storage displays physical tool units.")
	await _capture("worker-hub-city-storage.png")
	_tool_action("test_cart_0").mouse_entered.emit()
	_expect(fixture.worker_control.city_item_info.visible and fixture.worker_control.city_item_info.effect_label.text.contains("3 items"), "Cart uses Inventory detail panel with known capacity.")
	_expect(fixture.worker_control.city_item_info.category_label.text == "category: EQUIP (Tool)", "Primary equipment is identified in details.")
	await _capture("worker-hub-city-storage-details.png")
	_tool_action("test_cart_0").mouse_exited.emit()
	_expect(not fixture.worker_control.city_item_info.visible, "Leaving item hides details.")
	_tool_action("hammer_a").mouse_entered.emit()
	_expect(fixture.worker_control.city_item_info.name_label.text == "name: Stone Hammer", "Registered tool details use player Inventory data.")
	_expect(fixture.worker_control.city_item_info.category_label.text == "category: EQUIP (Tool)", "Other equipment omits Primary suffix.")
	_tool_action("hammer_a").mouse_exited.emit()
	fixture.worker_control.refresh()
	_expect(fixture.worker_control.city_storage_view.visible and not fixture.worker_control.window.visible, "Storage refresh preserves navigation.")
	fixture.worker_control.city_storage_view.get_node("Margin/Content/TitleRow/Close").pressed.emit()
	_expect(fixture.worker_control.window.visible and not fixture.worker_control.city_storage_view.visible, "Storage Back returns to Hub.")
	for accessory: Button in [fixture.worker_control.tools_accessory_button_1, fixture.worker_control.tools_accessory_button_2]:
		_expect(not accessory.disabled, "Accessory opens storage.")
		accessory.pressed.emit()
		_expect(fixture.worker_control.city_storage_view.visible and _tool_action("test_cart_0").disabled, "Accessory storage rejects incompatible carts.")
		fixture.worker_control.city_storage_view.get_node("Margin/Content/TitleRow/Close").pressed.emit()
	management.unequip(ids[2], "hammer_b")
	fixture.city_tools.add_tool_unit("storage_cart", "cart", "Spare Cart")
	fixture.worker_control._select_worker_for_tools(ids[2])
	fixture.worker_control.tools_tool_button.pressed.emit()
	for row: Node in fixture.worker_control.city_storage_list.get_children():
		for action: Node in row.get_children():
			if action is Button and action.get_meta("unit_id", "") == "storage_cart":
				_expect(not action.disabled, "Available City Storage unit can be equipped by idle worker.")
				action.pressed.emit()
				_expect(is_instance_valid(fixture.worker_control.city_action_panel), "Click opens equipment actions.")
				fixture.worker_control.city_action_panel.use_button.pressed.emit()
				break
	await get_tree().process_frame
	_expect(fixture.city_tools.has_equipped(ids[2], "cart"), "Primary storage action allocates the real cart unit.")
	for row: Node in fixture.worker_control.city_storage_list.get_children():
		for action: Node in row.get_children():
			if action is Button and action.get_meta("unit_id", "") == "storage_cart":
				action.pressed.emit()
				_expect(is_instance_valid(fixture.worker_control.city_action_panel), "Click opens equipment actions.")
				fixture.worker_control.city_action_panel.use_button.pressed.emit()
				break
	await get_tree().process_frame
	_expect(not fixture.city_tools.has_equipped(ids[2], "cart"), "Storage returns the unequipped cart to shared stock.")
	fixture.worker_control._close_tools_picker()
	fixture.worker_control._select_worker_for_tools(ids[0])
	fixture.worker_control.tools_tool_button.pressed.emit()
	await get_tree().process_frame
	_expect(_tool_action("hammer_a").disabled, "Actual Unequip button is locked during work.")
	await _capture("worker-hub-tool-picker.png")
	fixture.worker_control._close_tools_picker()
	fixture.worker_control.level_tab_button.pressed.emit()
	await _capture("worker-hub-level.png")
	fixture.worker_control.close()
	TimeComponentManager.advance_minutes(17 * 60 - fixture.daily.now() % 1440)
	fixture.worker_control.open()
	fixture.worker_control.tools_tab_button.pressed.emit()
	fixture.worker_control.tools_tool_button.pressed.emit()
	await get_tree().process_frame
	var unequip: Button = _tool_action("hammer_a")
	_expect(not unequip.disabled, "Actual Unequip button unlocks after shift.")
	unequip.pressed.emit()
	_expect(fixture.city_tools.has_equipped(ids[0], "stone_hammer"), "Item click does not unequip immediately.")
	await _capture("worker-hub-equipment-actions.png")
	fixture.worker_control.city_action_panel.drop_button.pressed.emit()
	_expect(fixture.city_tools.has_equipped(ids[0], "stone_hammer"), "Cancel preserves equipment.")
	unequip.pressed.emit()
	fixture.worker_control.city_action_panel.use_button.pressed.emit()
	await get_tree().process_frame
	_expect(not fixture.city_tools.has_equipped(ids[0], "stone_hammer"), "Tools UI returns optional tool to City Storage.")
	_expect(not _tool_action("hammer_a").disabled, "Picker enables Equip after the slot is freed.")
	_tool_action("hammer_a").pressed.emit()
	fixture.worker_control.city_action_panel.use_button.pressed.emit()
	await get_tree().process_frame
	_expect(fixture.city_tools.has_equipped(ids[0], "stone_hammer"), "Picker equips the physical tool unit.")
	fixture.worker_control.close()
	_expect(management.unequip(ids[1], "test_cart_0") != "Tool returned to City Storage.", "Standing Hauler retains mandatory equipment until unassigned.")
	var xp_before: int = WorkerDatabase.get_worker_data(ids[1]).profession_xp
	fixture.worker_control.open()
	fixture.worker_control.status_tab_button.pressed.emit()
	fixture.worker_control._show_manage(ids[1])
	_expect(not fixture.worker_control.manage_fire_button.disabled and fixture.worker_control.manage_goto_button.disabled, "Idle enables Fire and disables Go to.")
	await _capture("worker-hub-manage.png")
	_expect(fixture.worker_control.window.visible and fixture.worker_control.manage_window.visible, "Manage is a popup over the Status list.")
	_expect(fixture.worker_control.manage_window.size.x <= 100 and fixture.worker_control.manage_window.size.y <= 90, "Manage fits three compact actions.")
	var outside_click := InputEventMouseButton.new()
	outside_click.button_index = MOUSE_BUTTON_LEFT
	outside_click.pressed = true
	outside_click.position = Vector2(1, 1)
	fixture.worker_control._input(outside_click)
	_expect(not fixture.worker_control.manage_window.visible and fixture.worker_control.visible, "Outside click closes only Manage popup.")
	fixture.worker_control._show_manage(ids[1])
	fixture.worker_control.manage_fire_button.pressed.emit()
	_expect(fixture.worker_control._confirmation_overlay.visible and WorkerDatabase.get_worker_data(ids[1]).is_reserved(), "Fire asks before dismissing worker.")
	await _capture("worker-hub-remove.png")
	fixture.worker_control._confirm_no_button.pressed.emit()
	_expect(WorkerDatabase.get_worker_data(ids[1]).is_reserved(), "No preserves assignment.")
	fixture.worker_control.manage_fire_button.pressed.emit()
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	fixture.worker_control._input(escape)
	_expect(fixture.worker_control.visible and not fixture.worker_control._confirmation_overlay.visible, "Escape cancels confirmation, retaining Hub.")
	fixture.worker_control.manage_fire_button.pressed.emit()
	fixture.worker_control._confirm_yes_button.pressed.emit()
	await get_tree().process_frame
	_expect(not WorkerDatabase.has_worker_data(ids[1]) and not fixture.daily.jobs[&"ClaySiteA"].ids.has(ids[1]), "Yes dismisses worker and cancels Daily assignment.")
	fixture.worker_control.close()
	_expect(not fixture.city_tools.has_equipped(ids[1], "cart"), "Firing returns equipped cart to City Storage.")
	_expect(management.equip(ids[2], "test_cart_0") == "Tool equipped.", "Released cart can be allocated to another worker.")
	_expect(WorkerDatabase.dismissed_workers[ids[1]].profession_xp == xp_before and management.productive_days[ids[1]].size() == 1, "Dismissal preserves archived XP and productive history.")
	fixture.daily.cleanup()
	for id: String in ids:
		WorkerDatabase.workers_by_id.erase(id)
		WorkerDatabase.dismissed_workers.erase(id)
	var citizen := CitizenData.new()
	citizen.citizen_id = "control_linked"
	citizen.display_name = "Linked worker"
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.APPLICANT
	citizen.profession = WorkerData.Profession.LABORER
	CitizenManager.add_citizen(citizen)
	var hired: WorkerData = WorkerDatabase.hire_applicant(citizen.citizen_id, 2)
	hired.profession_xp = 9
	hired.profession_star = 2
	hired.start_work("test_busy", "test_job")
	_expect(not WorkerDatabase.dismiss_worker(hired.worker_id), "Employment API refuses reserved worker dismissal.")
	hired.finish_work("test_busy")
	_expect(WorkerDatabase.dismiss_worker(hired.worker_id) and citizen.employment_status == CitizenData.EmploymentStatus.UNEMPLOYED, "Dismissal updates linked citizen employment.")
	citizen.employment_status = CitizenData.EmploymentStatus.APPLICANT
	var rehired: WorkerData = WorkerDatabase.hire_applicant(citizen.citizen_id, 3)
	_expect(rehired == hired and rehired.profession_xp == 9 and rehired.profession_star == 2 and rehired.wage_shekel_per_day == 3, "Rehire preserves progression and accepts the new wage.")
	WorkerDatabase.workers_by_id.erase(citizen.citizen_id)
	WorkerDatabase.dismissed_workers.erase(citizen.citizen_id)
	CitizenManager.citizens_by_id.erase(citizen.citizen_id)
	print("WorkerControlTest %s" % ("PASSED" if failures == 0 else "FAILED"))
	get_tree().quit(0 if failures == 0 else 1)

func _capture(filename: String) -> void:
	# Geometry checks depend on container layout even without a renderer.
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join(filename))

func _tool_action(unit_id: String) -> Button:
	for node: Node in fixture.worker_control.city_storage_list.find_children("*", "Button", true, false):
		if str(node.get_meta("unit_id", "")) == unit_id or str(node.get_parent().get_meta("unit_id", "")) == unit_id:
			return node as Button
	push_error("Missing tool action: " + unit_id)
	return null
