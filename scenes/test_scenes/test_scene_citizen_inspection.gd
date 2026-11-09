extends Node

## Current-map integration coverage for citizen inspection. This fixture uses
## memory-only state and never opens a city save slot.
const CONTENT: PackedScene = preload("res://scenes/content_scene/content_scene.tscn")
const FOOD_ITEM_ID: String = "date_cluster"
const CLOTHING_ITEM_ID: String = "simple_clothes"

var failures: int = 0
var content: Node
var controller: Node
var panel: CanvasLayer
var visuals: Node
var runtime: Node
var inventory_ui: InventoryUI
var primary_id: String = ""
var removal_id: String = ""
var primary_citizen: CitizenData
var removal_citizen: CitizenData
var primary_actor: Node2D
var removal_actor: Node2D
var capture_directory: String = ""
var saved_state: Dictionary = {}
var original_storage: Node
var original_storage_existed: bool = false
var original_transport: Node
var original_transport_existed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	capture_directory = OS.get_environment("TIP_CITIZEN_CAPTURE_DIR")
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _frames(count: int = 1) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _wait_for_panel_refresh() -> void:
	await get_tree().create_timer(0.25, true, false, true).timeout


func _snapshot() -> void:
	var storage: Node = WorkStateRuntime.get_node_or_null("CityToolStorage")
	original_storage_existed = is_instance_valid(storage)
	original_storage = storage
	var transport: Node = WorkStateRuntime.get_node_or_null("CityStorageTransport")
	original_transport_existed = is_instance_valid(transport)
	original_transport = transport
	saved_state = {
		"inventory": Inventory.items.duplicate(true),
		"workers": WorkerDatabase.workers_by_id.duplicate(),
		"dismissed": WorkerDatabase.dismissed_workers.duplicate(),
		"citizens": CitizenManager.citizens_by_id.duplicate(),
		"rates": WorkerDatabase.onboarding_period_rates.duplicate(true),
		"needs_results": CitizenNeedsManager.last_needs_results.duplicate(true),
		"clothing_allocations": CitizenNeedsManager.clothing_allocations.duplicate(true),
		"food_supply": CityStockManager.food_supply,
		"clothing_supply": CityStockManager.clothing_supply,
		"treasury": CityStockManager.treasury_shekel,
		"shelter": CityStockManager.shelter_capacity,
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"weather": TimeComponentManager.current_weather,
		"clock_paused": TimeComponentManager.is_paused,
		"clock_processing": TimeComponentManager.is_processing(),
		"tree_paused": get_tree().paused,
		"current_scene": get_tree().current_scene,
		"storage_units": storage.get("units").duplicate(true) if original_storage_existed else {},
		"storage_items": storage.get("items").duplicate(true) if original_storage_existed else {},
		"food_portions": storage.get("food_portions").duplicate(true) if original_storage_existed else {},
		"storage_sequence": int(storage.get("_unit_sequence")) if original_storage_existed else 0,
		"cart_meta_present": storage.has_meta(&"initial_worksite_cart_supplied") if original_storage_existed else false,
		"cart_meta": storage.get_meta(&"initial_worksite_cart_supplied", false) if original_storage_existed else false,
		"transport_route": transport.get("route").duplicate(true) if original_transport_existed else {},
		"transport_last_tick": int(transport.get("last_tick")) if original_transport_existed else -1,
		"transport_worker_ids": transport.get("worker_ids").duplicate() if original_transport_existed else [],
		"transport_storage": transport.get("_central_storage") if original_transport_existed else null,
		"transport_central_position": transport.get("_central_position") if original_transport_existed else Vector2.ZERO,
		"transport_annex_position": transport.get("_annex_position") if original_transport_existed else Vector2.ZERO,
	}


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_window().size = Vector2i(1200, 675)
		await _frames(3)
	_expect(get_window().size == Vector2i(1200, 675)
		and get_viewport().get_visible_rect().size == Vector2(400, 225),
		"Citizen inspection is tested in the 1200x675 window at 400x225 logical size.")
	_snapshot()
	TimeComponentManager.set_process(false)
	TimeComponentManager.is_paused = false
	get_tree().paused = false
	TimeComponentManager.current_hour = 10
	primary_id = "citizen_inspection_%d" % Time.get_ticks_usec()
	removal_id = primary_id + "_remove"

	content = CONTENT.instantiate()
	get_tree().root.add_child(content)
	get_tree().current_scene = content
	await _frames(6)
	runtime = content.get_node_or_null("YSortWorld/WorkerRuntime")
	visuals = runtime.get_node_or_null("WorkerVisuals") if is_instance_valid(runtime) else null
	controller = runtime.get_node_or_null("CitizenInspectionController") if is_instance_valid(runtime) else null
	panel = controller.get("panel") as CanvasLayer if is_instance_valid(controller) else null
	inventory_ui = content.get_node_or_null("InventoryUI") as InventoryUI
	_expect(is_instance_valid(runtime) and is_instance_valid(visuals), "The real ContentScene provides WorkerRuntime and WorkerVisuals.")
	_expect(is_instance_valid(controller) and is_instance_valid(panel), "The city runtime exposes its CitizenInspectionController and panel.")
	_expect(is_instance_valid(inventory_ui), "The real ContentScene provides its InventoryUI for the modal-input check.")
	if not is_instance_valid(controller) or not is_instance_valid(panel) or not is_instance_valid(visuals):
		await _finish()
		return

	await _test_added_residents_and_mouse_selection()
	if is_instance_valid(panel):
		await _test_needs_and_storage()
		await _test_hire_reuses_and_tracks_actor()
		await _test_modal_pause_and_close_button()
		await _test_city_management_precedence()
		await _test_home_transition()
	await _finish()


func _new_citizen(id: String, display_name: String) -> CitizenData:
	var citizen := CitizenData.new()
	citizen.citizen_id = id
	citizen.display_name = display_name
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.UNEMPLOYED
	citizen.satisfaction = 0.65
	return citizen


func _add_test_citizens() -> void:
	primary_citizen = _new_citizen(primary_id, "Naram")
	removal_citizen = _new_citizen(removal_id, "Lugal")
	CitizenManager.add_citizen(primary_citizen)
	CitizenManager.add_citizen(removal_citizen)
	await _frames(2)
	primary_actor = visuals.actors.get(primary_id) as Node2D
	removal_actor = visuals.actors.get(removal_id) as Node2D
	_expect(is_instance_valid(primary_actor) and primary_actor.is_visible_in_tree(), "Adding an unemployed resident creates a visible city actor.")
	_expect(is_instance_valid(removal_actor) and removal_actor.is_visible_in_tree(), "A second added resident creates a separate visible actor.")
	if is_instance_valid(primary_actor):
		_position_actor_on_screen(primary_actor, Vector2(90, 80))
	if is_instance_valid(removal_actor):
		_position_actor_on_screen(removal_actor, Vector2(130, 80))


func _position_actor_on_screen(actor: Node2D, viewport_position: Vector2) -> void:
	actor.global_position = get_viewport().get_canvas_transform().affine_inverse() * viewport_position


func _mouse_click(viewport_position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = viewport_position
	press.global_position = viewport_position
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = viewport_position
	release.global_position = viewport_position
	get_viewport().push_input(release, true)
	await get_tree().process_frame


func _synthetic_hover_at(viewport_position: Vector2, gui_blocked: bool = false, mouse_in_window: bool = true) -> void:
	controller.call("_update_hover_at", viewport_position, mouse_in_window, gui_blocked)


func _press_key(keycode: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.physical_keycode = keycode
	press.pressed = true
	get_viewport().push_input(press)
	await get_tree().process_frame
	var release := InputEventKey.new()
	release.keycode = keycode
	release.physical_keycode = keycode
	release.pressed = false
	get_viewport().push_input(release)
	await get_tree().process_frame


func _wait_for_scene(path: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var scene: Node = get_tree().current_scene
		if scene != null and scene.scene_file_path == path and not SceneTransition.is_transitioning:
			await _frames(3)
			return true
		await get_tree().process_frame
	_expect(false, "The real door transition completes to " + path)
	return false


func _click_actor(actor: Node2D) -> void:
	var viewport_position: Vector2 = get_viewport().get_canvas_transform() * actor.global_position
	await _mouse_click(viewport_position)


func _name_label() -> Label:
	return panel.get_node("Root/Frame/Margin/Contents/NameRow/NameLabel") as Label


func _daily_label(path: String) -> Label:
	return panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/" + path) as Label



func _need_matches(need: String, value: Variant) -> bool:
	var card: Control = panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/DailyNeedsRow/" + need + "Status") as Control
	var label: Label = card.get_node("Status/Label") as Label
	var icon: TextureRect = card.get_node("Status/MetIcon") as TextureRect
	var met: bool = value != null and bool(value)
	var text: String = "Unknown" if value == null else ("Met" if met else "Missing")
	var texture: AtlasTexture = icon.texture as AtlasTexture
	return card.get_node("Label").text == need and icon.visible == met and label.visible == not met \
		and label.text == text and card.accessibility_name == need + ": " + text \
		and card.tooltip_text.is_empty() and card.get_node("Icon").tooltip_text.is_empty() \
		and card.get_node("Status").tooltip_text.is_empty() and icon.accessibility_name == need + ": " + text \
		and texture != null and texture.region == Rect2(84, 68, 8, 8) \
		and icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST

func _test_added_residents_and_mouse_selection() -> void:
	await _add_test_citizens()
	_expect(not CitizenNeedsManager.last_needs_results.has(primary_id), "The newly added citizen has no daily needs ledger yet.")
	if not is_instance_valid(primary_actor) or not is_instance_valid(removal_actor):
		return
	await _test_hover_feedback()

	var starting_satisfaction: float = primary_citizen.satisfaction
	var starting_inventory: Dictionary = Inventory.items.duplicate(true)
	var starting_ledger: Dictionary = CitizenNeedsManager.last_needs_results.duplicate(true)
	var starting_storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var starting_city_items: Dictionary = starting_storage.get("items").duplicate(true)
	var starting_food_portions: Dictionary = starting_storage.get("food_portions").duplicate(true)
	var starting_shelter_capacity: int = CityStockManager.shelter_capacity
	var starting_tree_pause: bool = get_tree().paused
	var starting_clock_pause: bool = TimeComponentManager.is_paused
	var starting_minute: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	await _click_actor(primary_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id, "A real viewport mouse click opens the panel for the hit unemployed resident ID.")
	_expect(_name_label().text == primary_citizen.display_name, "The panel shows the selected resident's real name.")
	_expect(panel.find_child("DailyCheckLabel", true, false) == null,
		"The compact card omits the Last Daily Check banner.")
	_expect(_need_matches("Food", primary_citizen.food_fulfilled)
		and _need_matches("Clothing", primary_citizen.clothing_fulfilled)
		and _need_matches("Shelter", primary_citizen.shelter_fulfilled),
		"The card shows the resident's current service flags before a daily snapshot exists.")
	_expect(panel.find_child("ConditionLabel", true, false) == null
		and panel.find_child("ClothingDaysLabel", true, false) == null
		and panel.find_child("DailyChangeLabel", true, false) == null,
		"Condition and lower daily detail rows are omitted from the compact Needs card.")
	_expect(get_tree().paused == starting_tree_pause and TimeComponentManager.is_paused == starting_clock_pause
		and starting_minute == TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute,
		"Opening the inspection panel does not pause or advance the city clock.")
	_expect(primary_citizen.satisfaction == starting_satisfaction and Inventory.items == starting_inventory,
		"Opening the panel does not mutate citizen satisfaction or Inventory.")
	_expect(CitizenNeedsManager.last_needs_results == starting_ledger
		and starting_storage.get("items") == starting_city_items
		and starting_storage.get("food_portions") == starting_food_portions
		and CityStockManager.shelter_capacity == starting_shelter_capacity
		and CityStockManager.food_supply == int(saved_state.food_supply)
		and CityStockManager.clothing_supply == int(saved_state.clothing_supply),
		"Opening the panel does not settle needs or change any city supply stock.")
	await _test_panel_pixel_layout()
	await _capture("citizen-unevaluated")

	# Place a different real actor underneath the visible frame. If the frame
	# leaks the mouse event to _unhandled_input, the selected ID changes.
	var original_removal_position: Vector2 = removal_actor.global_position
	var frame: Control = panel.get_node("Root/Frame") as Control
	var frame_center: Vector2 = frame.get_global_rect().get_center()
	removal_actor.global_position = get_viewport().get_canvas_transform().affine_inverse() * frame_center
	await _mouse_click(frame_center)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id,
		"Clicking the panel frame cannot select the resident positioned behind it.")
	removal_actor.global_position = original_removal_position

	await _click_actor(removal_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == removal_id and _name_label().text == removal_citizen.display_name,
		"A real viewport click on the second actor selects that exact resident.")
	_expect(CitizenManager.leave_city(removal_id), "The fixture can remove its open, unemployed resident through the real CitizenManager API.")
	await _wait_for_panel_refresh()
	_expect(not panel.visible and str(panel.get("selected_id")).is_empty(),
		"Removing a resident while inspected closes the stale panel safely.")
	_expect(not visuals.actors.has(removal_id), "The removed resident is retired from the real city actor map.")

	await _click_actor(primary_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id,
		"The remaining resident can still be inspected after another resident leaves.")


func _test_hover_feedback() -> void:
	var indicator: Node2D = controller.get("hover_indicator") as Node2D
	_expect(is_instance_valid(indicator) and indicator.get_parent() == controller,
		"The controller owns one non-interactive hover indicator.")
	if not is_instance_valid(indicator):
		return
	var indicator_id: int = indicator.get_instance_id()
	# The production poll reads the real pointer; inject positions instead so
	# the fixture works headlessly and never moves the user's mouse.
	var controller_was_processing: bool = controller.is_processing()
	controller.set_process(false)
	var was_processing: bool = visuals.is_processing()
	visuals.set_process(false)
	var other_visibility: Dictionary = {}
	for actor: Node2D in visuals.actors.values():
		if is_instance_valid(actor) and actor != primary_actor and actor != removal_actor:
			other_visibility[actor] = actor.visible
			actor.hide()
	_position_actor_on_screen(primary_actor, Vector2(90, 80))
	_position_actor_on_screen(removal_actor, Vector2(130, 80))
	_synthetic_hover_at(Vector2(90, 80))
	_expect(indicator.visible and str(controller.get("hovered_person_id")) == primary_id
		and indicator.global_position.is_equal_approx(primary_actor.global_position),
		"Hovering a visible resident shows the marker at that actor without a click.")
	await _capture("citizen-hover")
	await _click_actor(primary_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id,
		"Clicking the highlighted resident still opens its inspection card.")
	_synthetic_hover_at(Vector2(130, 80))
	_expect(indicator.visible and indicator.get_instance_id() == indicator_id
		and str(controller.get("hovered_person_id")) == removal_id
		and str(panel.get("selected_id")) == primary_id,
		"Hover moves the same marker to another resident without changing the selection.")
	removal_actor.hide()
	_synthetic_hover_at(Vector2(130, 80))
	_expect(not indicator.visible and str(controller.get("hovered_person_id")).is_empty(),
		"A resident hidden under a stationary pointer has no marker.")
	removal_actor.show()
	_synthetic_hover_at(Vector2(130, 80))
	_expect(indicator.visible and str(controller.get("hovered_person_id")) == removal_id,
		"The marker returns when that resident becomes visible again.")
	_position_actor_on_screen(removal_actor, Vector2(135, 80))
	_synthetic_hover_at(Vector2(130, 80))
	_expect(indicator.visible and indicator.global_position.is_equal_approx(removal_actor.global_position),
		"The marker follows the resident while the stationary pointer remains inside its hit area.")
	_position_actor_on_screen(removal_actor, Vector2(145, 80))
	_synthetic_hover_at(Vector2(130, 80))
	_expect(not indicator.visible and str(panel.get("selected_id")) == primary_id,
		"A moving resident leaves no stale marker and does not change selection.")
	var frame: Control = panel.get_node("Root/Frame") as Control
	var frame_center: Vector2 = frame.get_global_rect().get_center()
	_position_actor_on_screen(removal_actor, frame_center)
	_synthetic_hover_at(frame_center)
	_expect(indicator.visible and str(controller.get("hovered_person_id")) == removal_id,
		"The underlying resident is a valid hit before applying the GUI block.")
	_synthetic_hover_at(frame_center, true)
	_expect(not indicator.visible and str(panel.get("selected_id")) == primary_id,
		"A GUI-blocked pointer hides hover over a resident without changing selection.")
	_position_actor_on_screen(removal_actor, Vector2(130, 80))
	_synthetic_hover_at(Vector2(90, 80))
	_expect(indicator.visible, "Hover is restored over the first resident before opening Inventory.")
	inventory_ui.open_inventory()
	await _frames(2)
	_synthetic_hover_at(Vector2(90, 80))
	_expect(get_tree().paused and not indicator.visible and not panel.visible,
		"Opening the paused Inventory modal clears the marker and closes the card.")
	inventory_ui.close_inventory()
	_synthetic_hover_at(Vector2(90, 80))
	_expect(not get_tree().paused and indicator.visible and str(controller.get("hovered_person_id")) == primary_id,
		"Hover works again after Inventory closes and restores its prior pause state.")
	_synthetic_hover_at(Vector2(90, 80), false, false)
	_expect(not indicator.visible, "Leaving the window clears the hover marker.")
	_synthetic_hover_at(Vector2(-1, -1))
	_expect(not indicator.visible, "A pointer outside the viewport has no hover marker.")
	_synthetic_hover_at(Vector2(50, 110))
	_expect(not indicator.visible and str(controller.get("hovered_person_id")).is_empty(),
		"Moving the pointer into empty world space hides the marker.")
	for actor: Node2D in other_visibility:
		if is_instance_valid(actor):
			actor.visible = bool(other_visibility[actor])
	visuals.set_process(was_processing)
	controller.set_process(controller_was_processing)


func _test_panel_pixel_layout() -> void:
	var frame: Control = panel.get_node("Root/Frame") as Control
	var body_scroll: ScrollContainer = panel.get_node("Root/Frame/Margin/Contents/BodyScroll") as ScrollContainer
	var refresh_timer: Timer = panel.get_node("RefreshTimer") as Timer
	refresh_timer.stop()
	var name_label: Label = _name_label()
	_expect(name_label.tooltip_text.is_empty() and name_label.accessibility_name == primary_citizen.display_name,
		"The complete citizen name remains available to accessibility without a tooltip.")
	name_label.text = "Naram Lugal Ashur Nabu"
	var food: Label = _daily_label("DailyNeedsRow/FoodStatus/Label")
	var clothing: Label = _daily_label("DailyNeedsRow/ClothingStatus/Label")
	var shelter: Label = _daily_label("DailyNeedsRow/ShelterStatus/Label")
	food.text = "Food"
	clothing.text = "Clothing"
	shelter.text = "Shelter"
	_daily_label("SatisfactionLabel").text = "Actual satisfaction: 100%"
	await _frames(4)
	_expect(get_viewport().get_visible_rect().encloses(frame.get_global_rect()),
		"The compact card remains inside the logical gameplay viewport.")
	_expect(body_scroll.size.y > 0.0 and frame.get_global_rect().encloses(body_scroll.get_global_rect()),
		"The scrollable body has a usable viewport inside the card.")
	_expect(panel.find_child("CityStockLabel", true, false) == null
		and panel.find_child("CityStockRow", true, false) == null,
		"The individual card does not include the removed City Supply section.")
	_expect(name_label.get_theme_font_size("font_size") == 6
		and name_label.get_line_count() <= name_label.get_visible_line_count()
		and frame.get_global_rect().encloses(name_label.get_global_rect()),
		"A longer citizen name fits at 6 pixels (font=%s, lines=%s, visible=%s, line_height=%s, spacing=%s, label=%s, frame=%s)." % [
			name_label.get_theme_font_size("font_size"), name_label.get_line_count(), name_label.get_visible_line_count(),
			name_label.get_line_height(), name_label.get_theme_constant("line_spacing"), name_label.get_global_rect(), frame.get_global_rect(),
		])
	for path: String in [
		"DailyNeedsRow/FoodStatus", "DailyNeedsRow/ClothingStatus", "DailyNeedsRow/ShelterStatus",
	]:
		var icon: TextureRect = panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/" + path + "/Icon") as TextureRect
		var label: Label = _daily_label(path + "/Label")
		var column: Control = icon.get_parent() as Control
		body_scroll.ensure_control_visible(column)
		await _frames(2)
		_expect(icon.size == Vector2(16, 16) and icon.texture.get_size() == Vector2(16, 16)
			and column.get_global_rect().encloses(icon.get_global_rect())
			and body_scroll.get_global_rect().encloses(column.get_global_rect()),
			"The %s icon stays at its 16-pixel native size within the card." % path)
		_expect(label.get_theme_font_size("font_size") == 6
			and label.get_line_count() <= label.get_visible_line_count()
			and column.get_global_rect().encloses(label.get_global_rect()),
			"The %s value fits within the card at the 6-pixel font size." % path)
	var satisfaction_label: Label = _daily_label("SatisfactionLabel")
	var satisfaction_width: float = satisfaction_label.get_theme_font("font").get_string_size(
		satisfaction_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, satisfaction_label.get_theme_font_size("font_size")).x
	_expect(satisfaction_label.get_theme_font_size("font_size") == 6
		and satisfaction_width <= satisfaction_label.size.x
		and body_scroll.get_global_rect().encloses(satisfaction_label.get_global_rect())
		and panel.find_child("ConditionLabel", true, false) == null
		and panel.find_child("ClothingDaysLabel", true, false) == null
		and panel.find_child("DailyChangeLabel", true, false) == null,
		"Satisfaction fits at 6 pixels, with condition and lower daily details omitted.")
	body_scroll.scroll_vertical = 0
	panel.call("_refresh_view")
	refresh_timer.start(0.2)
	await _frames(2)


func _test_needs_and_storage() -> void:
	if not panel.visible or not is_instance_valid(primary_citizen):
		return
	var initial_storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var initial_food: int = int(initial_storage.call("get_food_supply_points"))
	var initial_clothing: int = int(initial_storage.call("get_clothing_item_count"))
	var initial_shelter: int = CityStockManager.shelter_capacity
	var food_coverage_before: Dictionary = CitizenNeedsManager.food_coverage_until.duplicate(true)
	var now: int = TimeComponentManager.current_day * 1440 + TimeComponentManager.current_hour * 60 + TimeComponentManager.current_minute
	Inventory.items.clear()
	Inventory.items.assign({FOOD_ITEM_ID: 1, CLOTHING_ITEM_ID: 1, "shekel": 100})
	Inventory.items_changed.emit()
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var deposit: Dictionary = storage.call("deposit_items_from_inventory", {FOOD_ITEM_ID: 1, CLOTHING_ITEM_ID: 1})
	_expect(bool(deposit.get("ok", false)), "The real City Storage accepts one valid food item and one valid clothing item.")
	if CityStockManager.shelter_capacity < CityStockManager.MAX_SHELTER_CAPACITY:
		CityStockManager.shelter_capacity += 1
	await _wait_for_panel_refresh()
	var current_food: int = int(storage.call("get_food_supply_points"))
	var current_clothing: int = int(storage.call("get_clothing_item_count"))
	var summary: Dictionary = CitizenNeedsManager.get_person_needs_summary(primary_id)
	var new_food_entitlements: int = 0
	for id_value: Variant in CitizenNeedsManager.food_coverage_until:
		if int(food_coverage_before.get(id_value, -1)) <= now and int(CitizenNeedsManager.food_coverage_until[id_value]) > now:
			new_food_entitlements += 1
	_expect(int(summary.get("food_stock", -1)) == current_food
		and current_food - initial_food + new_food_entitlements == 1,
		"The deposited date remains in shared stock or is consumed into live food entitlements.")
	_expect(int(summary.get("clothing_stock", -1)) == current_clothing and current_clothing >= initial_clothing + 1,
		"Real City Storage clothing stock increases without a needs settlement.")
	_expect(int(summary.get("shelter_capacity", -1)) == CityStockManager.shelter_capacity
		and (initial_shelter >= CityStockManager.MAX_SHELTER_CAPACITY or CityStockManager.shelter_capacity == initial_shelter + 1),
		"Current shelter capacity changes without settling Shelter fulfillment.")
	_expect(panel.find_child("CityStockLabel", true, false) == null
		and panel.find_child("CityStockRow", true, false) == null,
		"Restocking does not restore City Supply to the individual card.")
	_expect(_need_matches("Food", primary_citizen.food_fulfilled)
		and _need_matches("Clothing", primary_citizen.clothing_fulfilled)
		and _need_matches("Shelter", primary_citizen.shelter_fulfilled)
		and panel.find_child("ConditionLabel", true, false) == null,
		"Restocking refreshes actual Food, Clothing, and Shelter status while condition stays omitted.")

	primary_citizen.satisfaction = 0.24
	var live_food: bool = primary_citizen.food_fulfilled
	var live_clothing: bool = primary_citizen.clothing_fulfilled
	var live_shelter: bool = primary_citizen.shelter_fulfilled
	CitizenNeedsManager.last_needs_results[primary_id] = {
		"evaluated": true,
		"day": TimeComponentManager.current_day,
		"food": not live_food,
		"clothing": not live_clothing,
		"shelter": not live_shelter,
		"clothing_days_left": 0,
		"satisfaction": 0.24,
		"satisfaction_delta": 0.05,
		"missing": ["clothing"],
	}
	await _wait_for_panel_refresh()
	_expect(panel.find_child("DailyCheckLabel", true, false) == null,
		"The card continues to omit the daily-check banner after a real ledger update.")
	_expect(_need_matches("Food", live_food)
		and _need_matches("Clothing", live_clothing)
		and _need_matches("Shelter", live_shelter),
		"The UI reports live service flags even when the stored daily result disagrees.")
	_expect(_daily_label("SatisfactionLabel").text == "Actual satisfaction: 24%"
		and panel.find_child("ClothingDaysLabel", true, false) == null
		and panel.find_child("DailyChangeLabel", true, false) == null
		and panel.find_child("ConditionLabel", true, false) == null,
		"Current satisfaction stays visible while lower daily details remain omitted.")
	await _capture("citizen-evaluated-ledger")
	# Simulate an outside change such as a raid without rewriting the daily
	# ledger: the open card must update the actual value and keep its target.
	var ledger_before: Dictionary = CitizenNeedsManager.last_needs_results[primary_id].duplicate(true)
	primary_citizen.satisfaction = 0.19
	await _wait_for_panel_refresh()
	_expect(_daily_label("SatisfactionLabel").text == "Actual satisfaction: 19%"
		and panel.find_child("ConditionLabel", true, false) == null
		and CitizenNeedsManager.last_needs_results[primary_id] == ledger_before,
		"An open card reflects live Satisfaction without altering the last daily result or showing condition.")


func _test_hire_reuses_and_tracks_actor() -> void:
	if not is_instance_valid(primary_actor):
		return
	primary_citizen.satisfaction = CitizenData.MIN_APPLICANT_SATISFACTION
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 1
	_expect(CitizenManager.register_applicant(primary_id, WorkerData.Profession.LABORER),
		"The unemployed resident can enter the normal applicant state before recruitment.")
	var original_actor_id: int = primary_actor.get_instance_id()
	var contract_price: int = WorkerDatabase.get_contract_price(WorkerData.Profession.LABORER, 3)
	Inventory.items["shekel"] = maxi(contract_price, 1)
	Inventory.items_changed.emit()
	var worker: WorkerData = WorkerDatabase.hire_applicant(primary_id, 1, 3)
	_expect(worker != null and CitizenManager.get_citizen(primary_id).employment_status == CitizenData.EmploymentStatus.HIRED,
		"The applicant is recruited through the real WorkerDatabase hiring API.")
	await _frames(2)
	var hired_actor: Node2D = visuals.actors.get(primary_id) as Node2D
	_expect(is_instance_valid(hired_actor) and hired_actor.get_instance_id() == original_actor_id
		and hired_actor.get_meta("worker_id", "") == primary_id,
		"Hiring keeps exactly the resident actor already registered for that same ID.")
	if not is_instance_valid(hired_actor):
		return
	primary_actor = hired_actor
	if panel.visible:
		panel.call("close")
	await _click_actor(primary_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id,
		"Clicking the hired worker's existing actor continues to inspect the same citizen ID.")

	# Drive the ordinary city roaming step along an open, short route so the
	# actor's real position changes while the non-modal card remains selected.
	var origin: Vector2 = primary_actor.global_position
	var target: Vector2 = origin
	var nav: Variant = runtime.get("worksite_navigation")
	# Renderer timing can leave the test actor in a different idle position.
	# Find a visible, collision-clear fixture segment before driving _roam.
	var found_segment: bool = false
	if nav != null:
		for y: int in range(70, 180, 8):
			for x: int in range(50, 145, 8):
				var point: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * Vector2(x, y)
				var endpoint: Vector2 = point + Vector2(8, 0)
				if not nav.segment_clear(point + Vector2(0, 16), endpoint + Vector2(0, 16)):
					continue
				var actor_clear: bool = true
				for other in visuals.actors.values():
					if is_instance_valid(other) and other != primary_actor and other.is_visible_in_tree() and other.global_position.distance_to(point) < 24:
						actor_clear = false
						break
				if actor_clear:
					origin = point
					target = endpoint
					primary_actor.global_position = origin
					found_segment = true
					break
			if found_segment:
				break
	_expect(found_segment, "The real city navigation fixture offers a clear short resident-roaming step.")
	if found_segment:
		visuals.roaming[primary_id] = {"target": target, "idle": 0.0, "direction": "right"}
		visuals.call("_roam", primary_id, primary_actor, 0.2)
		_expect(primary_actor.global_position != origin and panel.visible and str(panel.get("selected_id")) == primary_id,
			"A real city-roaming step moves the hired actor while the panel stays tied to its stable person ID.")


func _test_modal_pause_and_close_button() -> void:
	if not is_instance_valid(inventory_ui) or not is_instance_valid(primary_actor):
		return
	var close_button: Control = panel.get_node("Root/Frame/Margin/Contents/NameRow/CloseButton") as Control
	await _mouse_click(close_button.get_global_rect().get_center())
	_expect(not panel.visible and str(panel.get("selected_id")).is_empty(), "A real viewport click on the panel close button closes it.")
	_expect(not get_tree().paused and not TimeComponentManager.is_paused, "Closing the non-modal panel does not change either pause state.")

	await _click_actor(primary_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id, "The hired resident can be reopened before modal coverage.")
	inventory_ui.open_inventory()
	await _frames(2)
	_expect(inventory_ui.visible and get_tree().paused, "The real Inventory modal owns its pause while open.")
	await _click_actor(primary_actor)
	_expect(not panel.visible and str(panel.get("selected_id")).is_empty(), "An Inventory modal prevents actor click-through into inspection.")
	_expect(get_tree().paused, "A blocked actor click leaves Inventory's pause intact.")
	inventory_ui.close_inventory()
	_expect(not inventory_ui.visible and not get_tree().paused, "Inventory close restores the unpaused state it captured before opening.")

	get_tree().paused = true
	TimeComponentManager.is_paused = true
	inventory_ui.open_inventory()
	await _click_actor(primary_actor)
	_expect(not panel.visible and get_tree().paused and TimeComponentManager.is_paused,
		"Inspection stays blocked under Inventory when both pause flags were already true.")
	inventory_ui.close_inventory()
	_expect(not inventory_ui.visible and get_tree().paused and TimeComponentManager.is_paused,
		"Closing Inventory restores the previously paused state instead of resuming the city.")
	get_tree().paused = false
	TimeComponentManager.is_paused = false


func _test_city_management_precedence() -> void:
	if not is_instance_valid(primary_actor):
		return
	var city_ui: RaidUI = get_tree().get_first_node_in_group("city_notification_ui") as RaidUI
	_expect(is_instance_valid(city_ui), "The real city scene provides the City Management dashboard and notification popup.")
	if not is_instance_valid(city_ui):
		return

	if not panel.visible:
		_position_actor_on_screen(primary_actor, Vector2(90, 80))
		await _click_actor(primary_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id,
		"The resident panel is open before testing the City Management shortcut.")
	var prior_tree_pause: bool = get_tree().paused
	var prior_clock_pause: bool = TimeComponentManager.is_paused
	var indicator: Node2D = controller.get("hover_indicator") as Node2D
	var controller_was_processing: bool = controller.is_processing()
	controller.set_process(false)
	_synthetic_hover_at(get_viewport().get_canvas_transform() * primary_actor.global_position)
	_expect(is_instance_valid(indicator) and indicator.visible,
		"The resident is highlighted before the City Management shortcut.")
	controller.set_process(controller_was_processing)
	await _press_key(KEY_C)
	await _frames(2)
	_expect(city_ui.details_panel.visible,
		"Pressing C through real viewport input opens City Management over the main map.")
	_expect(not panel.visible and str(panel.get("selected_id")).is_empty(),
		"Opening City Management closes the higher-layer citizen card.")
	_expect(is_instance_valid(indicator) and not indicator.visible,
		"Opening City Management with C also clears the resident hover marker.")
	_expect(get_tree().paused == prior_tree_pause and TimeComponentManager.is_paused == prior_clock_pause,
		"Opening City Management and dismissing the citizen card preserve the existing pause state.")

	# The dashboard is centered, leaving a narrow visible strip of world at the
	# left. Use a real actor in that strip to exercise unhandled mouse routing.
	var world_screen_position: Vector2 = Vector2(35, 80)
	_position_actor_on_screen(primary_actor, world_screen_position)
	var details_rect: Rect2 = city_ui.details_panel.get_global_rect()
	_expect(not details_rect.has_point(world_screen_position),
		"The click-through probe is in visible world space outside the City Management panel.")
	await _click_actor(primary_actor)
	_expect(city_ui.details_panel.visible and not panel.visible and str(panel.get("selected_id")).is_empty(),
		"Clicking a world actor outside the dashboard cannot open inspection or disturb City Management.")
	_expect(get_tree().paused == prior_tree_pause and TimeComponentManager.is_paused == prior_clock_pause,
		"The blocked world click leaves the dashboard pause state unchanged.")

	await _press_key(KEY_C)
	await _frames(2)
	_expect(not city_ui.details_panel.visible and not city_ui.notifications_popup.visible,
		"Pressing C again closes City Management and its related surfaces.")
	_position_actor_on_screen(primary_actor, Vector2(90, 80))
	await _click_actor(primary_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id,
		"After City Management closes, a real viewport click can inspect the resident again.")
	prior_tree_pause = get_tree().paused
	prior_clock_pause = TimeComponentManager.is_paused
	await _press_key(KEY_ESCAPE)
	_expect(not panel.visible and str(panel.get("selected_id")).is_empty()
		and get_tree().paused == prior_tree_pause and TimeComponentManager.is_paused == prior_clock_pause,
		"Escape closes the citizen card without changing either pause state.")
	await _click_actor(primary_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id,
		"The citizen card can be reopened after Escape closes it.")

	# Notifications are another foreground City Management surface. Confirm its
	# real button opens the popup, blocks an actor underneath, and can be closed.
	var notification_button: Button = city_ui.notification_button
	_expect(is_instance_valid(notification_button) and notification_button.is_visible_in_tree(),
		"The main city exposes its notifications button for the input check.")
	if is_instance_valid(notification_button) and notification_button.is_visible_in_tree():
		await _mouse_click(notification_button.get_global_rect().get_center())
		await _frames(2)
		_expect(city_ui.notifications_popup.visible and not city_ui.details_panel.visible,
			"The real notifications button opens its popup above the city world.")
		_expect(not panel.visible and str(panel.get("selected_id")).is_empty(),
			"Opening the notifications popup closes the citizen card.")
		var popup_rect: Rect2 = city_ui.notifications_popup.get_global_rect()
		var popup_probe: Vector2 = popup_rect.position + Vector2(2, 2)
		_position_actor_on_screen(primary_actor, popup_probe)
		await _click_actor(primary_actor)
		_expect(city_ui.notifications_popup.visible and not panel.visible and str(panel.get("selected_id")).is_empty(),
			"Clicking a real actor behind the notifications frame cannot open citizen inspection.")
		var outside_popup: Vector2 = Vector2(popup_rect.end.x + 20.0, popup_rect.position.y + 25.0)
		_expect(not popup_rect.has_point(outside_popup) and get_viewport().get_visible_rect().has_point(outside_popup),
			"The second notifications probe is visible world outside the popup.")
		_position_actor_on_screen(primary_actor, outside_popup)
		await _click_actor(primary_actor)
		_expect(city_ui.notifications_popup.visible and not panel.visible and str(panel.get("selected_id")).is_empty(),
			"Clicking world outside the open notifications popup cannot reopen the citizen card.")
		var popup_close: Control = city_ui.get_node("Root/NotificationsPopup/Margin/Contents/ActionsRow/CloseButton") as Control
		await _mouse_click(popup_close.get_global_rect().get_center())
		_expect(not city_ui.notifications_popup.visible,
			"The notifications popup closes through its real close button.")
		_position_actor_on_screen(primary_actor, Vector2(90, 80))
		await _click_actor(primary_actor)
		_expect(panel.visible and str(panel.get("selected_id")) == primary_id,
			"The resident remains inspectable after the notifications popup closes.")
		var citizen_close: Control = panel.get_node("Root/Frame/Margin/Contents/NameRow/CloseButton") as Control
		await _mouse_click(citizen_close.get_global_rect().get_center())
		_expect(not panel.visible, "The citizen card closes after the notifications input check.")
	else:
		# The City Management check above is mandatory; notification availability
		# is optional for isolated map variants.
		if panel.visible:
			panel.call("close")
	city_ui.call("close_details")
	city_ui.call("_close_notifications")
	_expect(not panel.visible and not city_ui.details_panel.visible and not city_ui.notifications_popup.visible,
		"The dashboard, notifications, and citizen card are all closed after this test.")


func _test_home_transition() -> void:
	if not is_instance_valid(primary_actor) or not is_instance_valid(content):
		return
	var store: Node = WorkStateRuntime.get_node_or_null("CitySave")
	var home_door: Node = content.get_node_or_null("YSortWorld/HomeDoor")
	_expect(is_instance_valid(store) and is_instance_valid(home_door),
		"The real city map provides its CitySave handoff and HomeDoor.")
	if not is_instance_valid(store) or not is_instance_valid(home_door):
		return

	# Let normal authored collider refreshes settle before using the production
	# handoff guard. This exercises the in-memory city park, without save I/O.
	for _frame: int in range(60):
		if not bool(runtime.get("navigation_refresh_pending")):
			break
		await get_tree().process_frame
	_expect(not bool(runtime.get("navigation_refresh_pending")) and not bool(runtime.get("_working")),
		"The real city runtime is ready for a home handoff without an active work transaction.")
	if bool(runtime.get("navigation_refresh_pending")) or bool(runtime.get("_working")):
		return

	if not panel.visible:
		_position_actor_on_screen(primary_actor, Vector2(90, 80))
		await _click_actor(primary_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id,
		"The citizen card is open before entering home through HomeDoor.")
	var city_panel: CanvasLayer = panel
	var city_indicator: Node2D = controller.get("hover_indicator") as Node2D
	var inventory_before: Dictionary = Inventory.items.duplicate(true)
	var storage: Node = WorkStateRuntime.get_node("CityToolStorage")
	var storage_items_before: Dictionary = storage.get("items").duplicate(true)
	var storage_units_before: Dictionary = storage.get("units").duplicate(true)
	var needs_before: Dictionary = CitizenNeedsManager.last_needs_results.duplicate(true)
	var satisfaction_before: float = primary_citizen.satisfaction
	var clock_before: Dictionary = {
		"day": TimeComponentManager.current_day,
		"hour": TimeComponentManager.current_hour,
		"minute": TimeComponentManager.current_minute,
		"clock_paused": TimeComponentManager.is_paused,
		"tree_paused": get_tree().paused,
	}
	var save_status_before: String = str(store.get("status"))
	var parked_runtime: Node = runtime

	# Calling the real Area2D body callback is the same interaction entry used
	# after physics reports the player overlap; SceneTransition performs the fade
	# and scene swap asynchronously.
	home_door.call("_on_body_entered", content.get_node("YSortWorld/Player"))
	var home_path: String = store.snapshot.HOME_PATH
	if not await _wait_for_scene(home_path):
		return
	var home: Node = get_tree().current_scene
	_expect(store.get("map") == home and store.get("parked_worksite") == parked_runtime
		and parked_runtime.get_parent() == store and bool(parked_runtime.get("checkpoint_handoff"))
		and not parked_runtime.visible,
		"HomeDoor parks the same live city runtime in CitySave without serializing a checkpoint.")
	_expect(not city_panel.visible and str(city_panel.get("selected_id")).is_empty(),
		"The citizen inspection card closes as the city runtime is handed to the home scene.")
	_expect(is_instance_valid(city_indicator) and not city_indicator.visible,
		"The retained city controller hides its hover marker during the home handoff.")
	_expect(not get_tree().paused and not TimeComponentManager.is_paused
		and TimeComponentManager.current_day == int(clock_before.day)
		and TimeComponentManager.current_hour == int(clock_before.hour)
		and TimeComponentManager.current_minute == int(clock_before.minute)
		and str(store.get("status")) == save_status_before,
		"The in-memory home handoff neither pauses nor advances the clock, nor writes a save.")
	_expect(Inventory.items == inventory_before and storage.get("items") == storage_items_before
		and storage.get("units") == storage_units_before
		and CitizenNeedsManager.last_needs_results == needs_before
		and primary_citizen.satisfaction == satisfaction_before,
		"Entering home leaves Inventory, City Storage, the daily needs ledger, and resident Satisfaction unchanged.")
	if home == null or not home.has_node("YSortWorld/ExitDoor"):
		_expect(false, "The real home scene provides its ExitDoor for the return trip.")
		return

	var home_player: Node = home.get_node("YSortWorld/Player")
	home.get_node("YSortWorld/ExitDoor").call("_on_body_entered", home_player)
	if not await _wait_for_scene("res://scenes/content_scene/content_scene.tscn"):
		return
	content = get_tree().current_scene
	get_tree().current_scene = content
	runtime = content.get_node_or_null("YSortWorld/WorkerRuntime")
	visuals = runtime.get_node_or_null("WorkerVisuals") if is_instance_valid(runtime) else null
	controller = runtime.get_node_or_null("CitizenInspectionController") if is_instance_valid(runtime) else null
	panel = controller.get("panel") as CanvasLayer if is_instance_valid(controller) else null
	inventory_ui = content.get_node_or_null("InventoryUI") as InventoryUI
	for _frame: int in range(120):
		if store.get("parked_worksite") == null:
			break
		await get_tree().process_frame
	_expect(store.get("map") == content and store.get("parked_worksite") == null
		and not store.snapshot.is_home(content),
		"ExitDoor returns to the city and CitySave adopts the live runtime into the new map.")
	_expect(is_instance_valid(runtime) and is_instance_valid(visuals) and is_instance_valid(controller) and is_instance_valid(panel),
		"The returned ContentScene installs a fresh, usable citizen inspection controller.")
	_expect(not get_tree().paused and not TimeComponentManager.is_paused
		and TimeComponentManager.current_day == int(clock_before.day)
		and TimeComponentManager.current_hour == int(clock_before.hour)
		and TimeComponentManager.current_minute == int(clock_before.minute),
		"Returning from home preserves the unpaused city clock without advancing it.")
	_expect(Inventory.items == inventory_before and storage.get("items") == storage_items_before
		and storage.get("units") == storage_units_before
		and CitizenNeedsManager.last_needs_results == needs_before
		and CitizenManager.get_citizen(primary_id) == primary_citizen
		and primary_citizen.satisfaction == satisfaction_before,
		"The resident, daily result, City Storage, and Inventory remain intact after the home round trip.")
	if not is_instance_valid(visuals) or not is_instance_valid(panel):
		return
	for _frame: int in range(30):
		if visuals.actors.has(primary_id):
			break
		await get_tree().process_frame
	primary_actor = visuals.actors.get(primary_id) as Node2D
	_expect(is_instance_valid(primary_actor) and primary_actor.is_visible_in_tree(),
		"The hired resident actor is restored in the city after returning from home.")
	if not is_instance_valid(primary_actor):
		return
	_position_actor_on_screen(primary_actor, Vector2(90, 80))
	await _click_actor(primary_actor)
	_expect(panel.visible and str(panel.get("selected_id")) == primary_id,
		"The restored resident can be inspected again with a real viewport click after the home round trip.")
	var returned_panel_close: Control = panel.get_node("Root/Frame/Margin/Contents/NameRow/CloseButton") as Control
	await _mouse_click(returned_panel_close.get_global_rect().get_center())
	_expect(not panel.visible, "The inspection card closes after the home return check.")
	var returned_city_ui: RaidUI = get_tree().get_first_node_in_group("city_notification_ui") as RaidUI
	if is_instance_valid(returned_city_ui):
		returned_city_ui.call("close_details")
		returned_city_ui.call("_close_notifications")
	_expect(not panel.visible and (not is_instance_valid(returned_city_ui)
		or (not returned_city_ui.details_panel.visible and not returned_city_ui.notifications_popup.visible)),
		"The returned map leaves no citizen, dashboard, or notification surface open.")


func _capture(filename: String) -> void:
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(capture_directory)
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(capture_directory.path_join(filename + ".png"))
	_expect(error == OK, "Rendered citizen inspection evidence is saved: " + filename)


func _finish() -> void:
	var city_ui: RaidUI = get_tree().get_first_node_in_group("city_notification_ui") as RaidUI
	if is_instance_valid(city_ui):
		city_ui.call("close_details")
		city_ui.call("_close_notifications")
	if is_instance_valid(inventory_ui) and inventory_ui.visible:
		inventory_ui.close_inventory()
	get_tree().paused = false
	TimeComponentManager.is_paused = false
	if is_instance_valid(panel):
		panel.call("close")
	var indicator: Node2D = controller.get("hover_indicator") as Node2D if is_instance_valid(controller) else null
	if is_instance_valid(content):
		content.free()
	_expect(not is_instance_valid(indicator), "Freeing the city controller also frees its hover marker.")
	content = null
	if original_transport_existed:
		if is_instance_valid(original_transport):
			original_transport.set("route", saved_state.transport_route)
			original_transport.set("last_tick", saved_state.transport_last_tick)
			original_transport.set("worker_ids", saved_state.transport_worker_ids)
			original_transport.set("_central_storage", saved_state.transport_storage)
			original_transport.set("_central_position", saved_state.transport_central_position)
			original_transport.set("_annex_position", saved_state.transport_annex_position)
	else:
		var new_transport: Node = WorkStateRuntime.get_node_or_null("CityStorageTransport")
		if is_instance_valid(new_transport):
			new_transport.free()
	if original_storage_existed and is_instance_valid(original_storage):
		var units: Dictionary = original_storage.get("units")
		var items: Dictionary = original_storage.get("items")
		var portions: Dictionary = original_storage.get("food_portions")
		units.assign(saved_state.storage_units)
		items.assign(saved_state.storage_items)
		portions.assign(saved_state.food_portions)
		original_storage.set("_unit_sequence", saved_state.storage_sequence)
		if bool(saved_state.cart_meta_present):
			original_storage.set_meta(&"initial_worksite_cart_supplied", saved_state.cart_meta)
		else:
			original_storage.remove_meta(&"initial_worksite_cart_supplied")
		original_storage.emit_signal("changed")
	else:
		var new_storage: Node = WorkStateRuntime.get_node_or_null("CityToolStorage")
		if is_instance_valid(new_storage):
			new_storage.free()
	Inventory.items.assign(saved_state.inventory)
	Inventory.items_changed.emit()
	WorkerDatabase.workers_by_id.assign(saved_state.workers)
	WorkerDatabase.dismissed_workers.assign(saved_state.dismissed)
	WorkerDatabase.onboarding_period_rates.assign(saved_state.rates)
	CitizenManager.citizens_by_id.assign(saved_state.citizens)
	CitizenNeedsManager.last_needs_results.assign(saved_state.needs_results)
	CitizenNeedsManager.clothing_allocations.assign(saved_state.clothing_allocations)
	CityStockManager.food_supply = int(saved_state.food_supply)
	CityStockManager.clothing_supply = int(saved_state.clothing_supply)
	CityStockManager.treasury_shekel = int(saved_state.treasury)
	CityStockManager.shelter_capacity = int(saved_state.shelter)
	TimeComponentManager.current_day = int(saved_state.day)
	TimeComponentManager.current_hour = int(saved_state.hour)
	TimeComponentManager.current_minute = int(saved_state.minute)
	TimeComponentManager.current_weather = str(saved_state.weather)
	TimeComponentManager.is_paused = bool(saved_state.clock_paused)
	TimeComponentManager.set_process(bool(saved_state.clock_processing))
	get_tree().paused = bool(saved_state.tree_paused)
	get_tree().current_scene = saved_state.current_scene if is_instance_valid(saved_state.current_scene) else self
	if failures == 0:
		print("CitizenInspectionTest PASSED")
	else:
		print("CitizenInspectionTest FAILED: %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
