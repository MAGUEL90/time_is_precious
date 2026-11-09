extends Node

## Memory-only bridge fixture. It does not create, load, or inspect city saves.
const HUB_SCENE: PackedScene = preload("res://scenes/test_scenes/ui_sandbox/worker_control/worker_control.tscn")
const CONTROLLER_SCRIPT = preload("res://scenes/content_scene/citizen_inspection_controller.gd")
const WORKER_ID: String = "unified_details_bridge_worker"
const LEGACY_ID: String = "unified_details_bridge_legacy"
const RESIDENT_ID: String = "unified_details_bridge_resident"

class VisualOwner extends Node2D:
	var actors: Dictionary = {}

class RuntimeStub extends Node2D:
	var worker_control: WorkerControlUI
	var player: Node
	var inventory_ui: CanvasLayer
	var inspector: Control
	var checkpoint_handoff: bool = false
	func _can_open_worker_hub() -> bool:
		return not checkpoint_handoff and not get_tree().paused

var failures: int = 0
var saved: Dictionary = {}
var runtime: RuntimeStub
var visuals: VisualOwner
var hub: WorkerControlUI
var controller: Node
var panel: CanvasLayer
var worker: WorkerData
var city_shortcuts: int = 0
var underlay_presses: int = 0
var goto_id: String = ""
var removed_ids: Array[String] = []
var fire_available: bool = true
var goto_available: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _expect_ui_name(label: Label, expected: String, context: String) -> void:
	if not is_instance_valid(label) or not label.is_visible_in_tree():
		_expect(false, context + " name label is unavailable or hidden.")
		return
	_expect(label.text == expected and label.text not in ["Linked Worker", "Legacy Worker", "Resident"],
		"%s must show %s rather than a technical label (actual: %s)." % [context, expected, label.text])


func _expect_roster_name(worker_id: String, expected: String) -> void:
	var button: Button = hub._find_manage_button(worker_id)
	if not is_instance_valid(button):
		_expect(false, "Status row is missing for " + expected + ".")
		return
	_expect_ui_name(button.get_parent().get_node_or_null("NameLabel") as Label, expected, "Status row")


func _unhandled_input(event: InputEvent) -> void:
	# Models the existing City Hub's unhandled C shortcut. A map-origin card
	# must allow this through; a K-origin card must consume it.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		city_shortcuts += 1


func _frames(count: int = 2) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _press_key(key: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = key
	if key != KEY_TAB:
		press.physical_keycode = key
	press.pressed = true
	if key == KEY_TAB:
		Input.parse_input_event(press)
	else:
		get_viewport().push_input(press)
	await _frames(1)
	var release := InputEventKey.new()
	release.keycode = key
	release.physical_keycode = key
	if key == KEY_TAB:
		Input.parse_input_event(release)
	else:
		get_viewport().push_input(release)
	await _frames(1)


func _click(point: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	press.global_position = point
	press.pressed = true
	get_viewport().push_input(press, true)
	await _frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	release.global_position = point
	get_viewport().push_input(release, true)
	await _frames(1)


func _click_control(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_visible_in_tree():
		_expect(false, "Expected visible GUI control is unavailable.")
		return
	if control is BaseButton and control.disabled:
		_expect(false, "Expected GUI control is disabled: " + str(control.get_path()))
		return
	var bounds: Rect2 = control.get_global_rect()
	if not get_viewport().get_visible_rect().encloses(bounds) or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		_expect(false, "Expected GUI control is outside the viewport: " + str(control.get_path()))
		return
	await _click(bounds.get_center())


func _capture(stage: String) -> void:
	var directory: String = OS.get_environment("TIP_WORKER_ACCESS_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	if not directory.is_absolute_path() or DirAccess.make_dir_recursive_absolute(directory) != OK:
		_expect(false, "Unable to create the requested capture directory.")
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	if frame.get_size() != Vector2i(400, 225):
		_expect(false, "The worker capture must use the native 400x225 viewport.")
		return
	_expect(frame.save_png(directory.path_join(stage + ".png")) == OK, "Saved capture: " + stage)


func _rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in [WORKER_ID, LEGACY_ID]:
		var person: WorkerData = WorkerDatabase.get_worker_data(id)
		if person == null:
			continue
		rows.append({"id": id, "name": person.get_resolved_display_name(),
			"profession": "Laborer", "working": false, "can_fire": fire_available,
			"can_goto": goto_available, "star": 1, "wage": "6 Shekel / 3 days", "needs": {}})
	return rows


func _no_tools(_worker_id: String) -> Array:
	return []


func _add_actor(id: String, position_in_viewport: Vector2) -> void:
	var actor := Node2D.new()
	visuals.add_child(actor)
	actor.global_position = get_viewport().get_canvas_transform().affine_inverse() * position_in_viewport
	visuals.actors[id] = actor


func _new_citizen(id: String, name_text: String, hired: bool) -> CitizenData:
	var citizen := CitizenData.new()
	citizen.citizen_id = id
	citizen.display_name = name_text
	citizen.population_status = CitizenData.PopulationStatus.RESIDENT
	citizen.employment_status = CitizenData.EmploymentStatus.HIRED if hired else CitizenData.EmploymentStatus.UNEMPLOYED
	citizen.satisfaction = 0.8
	return citizen


func _new_worker(id: String, name_text: String) -> WorkerData:
	var person := WorkerData.new()
	person.worker_id = id
	person.display_name = name_text
	person.profession = WorkerData.Profession.LABORER
	person.satisfaction = 0.8
	person.payroll_start_day = TimeComponentManager.current_day
	WorkerDatabase._start_contract(person, 3, 6)
	return person


func _run() -> void:
	saved = {"workers": WorkerDatabase.workers_by_id.duplicate(),
		"citizens": CitizenManager.citizens_by_id.duplicate(),
		"inventory": Inventory.items.duplicate(true),
		"rates": WorkerDatabase.onboarding_period_rates.duplicate(true),
		"dismissed": WorkerDatabase.dismissed_workers.duplicate(),
		"tree_paused": get_tree().paused, "clock_paused": TimeComponentManager.is_paused,
		"clock_processing": TimeComponentManager.is_processing()}
	get_tree().paused = false
	TimeComponentManager.is_paused = false
	TimeComponentManager.set_process(false)
	var starting_clock: Vector3i = Vector3i(TimeComponentManager.current_day,
		TimeComponentManager.current_hour, TimeComponentManager.current_minute)
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 6
	Inventory.items["shekel"] = 100
	CitizenManager.citizens_by_id[WORKER_ID] = _new_citizen(WORKER_ID, "Naram", true)
	CitizenManager.citizens_by_id[RESIDENT_ID] = _new_citizen(RESIDENT_ID, "Nabu", false)
	worker = _new_worker(WORKER_ID, "Naram")
	WorkerDatabase.workers_by_id[WORKER_ID] = worker
	WorkerDatabase.workers_by_id[LEGACY_ID] = _new_worker(LEGACY_ID, "Lugal")

	runtime = RuntimeStub.new()
	add_child(runtime)
	runtime.player = Node.new()
	runtime.add_child(runtime.player)
	visuals = VisualOwner.new()
	runtime.add_child(visuals)
	_add_actor(WORKER_ID, Vector2(70, 70))
	_add_actor(LEGACY_ID, Vector2(110, 70))
	_add_actor(RESIDENT_ID, Vector2(150, 70))
	hub = HUB_SCENE.instantiate() as WorkerControlUI
	hub.rows_provider = _rows
	hub.tools_provider = _no_tools
	hub.can_open = runtime._can_open_worker_hub
	runtime.worker_control = hub
	runtime.add_child(hub)
	hub.goto_requested.connect(func(id: String): goto_id = id)
	# The stub owns no worksite, so its dismissal adapter calls the existing
	# WorkerDatabase exactly as a host would and refreshes the visible roster.
	hub.remove_requested.connect(func(id: String):
		removed_ids.append(id)
		WorkerDatabase.dismiss_worker(id)
		hub.refresh.call_deferred()
	)
	controller = CONTROLLER_SCRIPT.new()
	controller.configure(runtime, visuals)
	runtime.add_child(controller)
	panel = controller.get("panel") as CanvasLayer
	await _frames()
	var name_label: Label = panel.get_node("Root/Frame/Margin/Contents/NameRow/NameLabel") as Label

	await _click(Vector2(70, 70))
	_expect(panel.visible and panel.get("selected_id") == WORKER_ID and not get_tree().paused,
		"Map click opens the worker's shared needs card without pausing.")
	_expect_ui_name(name_label, "Naram", "Map worker card")
	var shared_panel_id: int = panel.get_instance_id()
	await _press_key(KEY_C)
	_expect(not panel.visible and city_shortcuts == 1 and not get_tree().paused,
		"C closes the map card and still reaches the City shortcut.")

	# Compatibility-only checks for the retained host-facing signals. The card
	# has no such buttons; these assertions are not evidence of a playable route.
	await _click(Vector2(70, 70))
	panel.emit_signal("renew_requested", WORKER_ID)
	await _frames()
	_expect(hub.visible and hub.contract_window.visible and not panel.visible and get_tree().paused,
		"Synthetic host Renew signal still opens Contract for a worker.")
	await _click_control(hub.contract_close_button)
	_expect(panel.visible and panel.get_instance_id() == shared_panel_id and not hub.visible and not get_tree().paused,
		"Closing synthetic map-origin Contract restores the nonmodal card and pause.")
	panel.emit_signal("actions_requested", WORKER_ID)
	await _frames()
	_expect(hub.visible and hub.manage_window.visible and hub._manage_worker_id == WORKER_ID and get_tree().paused,
		"Synthetic host Actions signal still opens the worker menu.")
	await _click_control(hub.manage_contract_button)
	await _click_control(hub.contract_close_button)
	_expect(hub.manage_window.visible and hub.manage_contract_button.has_focus(),
		"Contract opened through the host API returns to Manage.")
	await _press_key(KEY_ESCAPE)
	_expect(panel.visible and not hub.visible and not get_tree().paused,
		"Closing synthetic map-origin Manage restores the nonmodal card.")
	await _press_key(KEY_ESCAPE)
	await _click(Vector2(110, 70))
	_expect(panel.visible and panel.get("selected_id") == LEGACY_ID, "A legacy worker remains inspectable from the map.")
	_expect_ui_name(name_label, "Lugal", "Map legacy card")
	panel.emit_signal("renew_requested", LEGACY_ID)
	await _frames()
	_expect(hub.contract_window.visible and hub._manage_worker_id == LEGACY_ID,
		"The retained host Renew signal also accepts a legacy worker.")
	await _click_control(hub.contract_close_button)
	await _press_key(KEY_ESCAPE)

	await _click(Vector2(150, 70))
	_expect(panel.visible and panel.get("selected_id") == RESIDENT_ID and not hub.visible,
		"A nonworker still opens the same nonmodal needs card.")
	_expect_ui_name(name_label, "Nabu", "Map resident card")
	panel.emit_signal("renew_requested", RESIDENT_ID)
	_expect(panel.visible and not hub.visible, "The retained host Renew signal rejects a nonworker.")
	_expect(panel.find_child("ActionsButton", true, false) == null and panel.find_child("RenewButton", true, false) == null,
		"The nonworker needs card has no worker actions.")
	await _press_key(KEY_ESCAPE)
	_expect(not panel.visible and not get_tree().paused, "Escape closes the map card without changing pause.")

	# Test the real rendered row with both eligibility-dependent actions disabled.
	fire_available = false
	goto_available = false
	await _press_key(KEY_K)
	_expect(hub.visible and get_tree().paused, "K opens and pauses the existing Worker Hub.")
	var row_button: Button = hub._find_manage_button(WORKER_ID)
	_expect_roster_name(WORKER_ID, "Naram")
	_expect_roster_name(LEGACY_ID, "Lugal")
	await _capture("01-status")
	_expect(is_instance_valid(row_button) and row_button.text == "Manage" and row_button.is_visible_in_tree(),
		"The visible Status row offers Manage for the correct worker.")
	await _click_control(row_button)
	_expect(hub.manage_window.visible and hub._manage_worker_id == WORKER_ID and not panel.visible,
		"Clicking the row opens the worker's actual Manage popup.")
	await _capture("02-manage-disabled-fire")
	_expect(hub.manage_fire_button.disabled and hub.manage_goto_button.disabled and hub.manage_details_button.has_focus(),
		"When Fire and Go To are unavailable, keyboard focus starts on Details.")
	await _press_key(KEY_TAB)
	var tab_focus: Control = get_viewport().gui_get_focus_owner()
	_expect(hub.manage_contract_button.has_focus(), "Tab reaches Contract from Details (focus: %s)." % (str(tab_focus.get_path()) if is_instance_valid(tab_focus) else "none"))
	await _press_key(KEY_TAB)
	_expect(hub.manage_details_button.has_focus(), "Tab wraps inside Manage without focusing disabled actions or the background.")
	await _press_key(KEY_ENTER)
	await _frames()
	_expect(panel.visible and panel.get_instance_id() == shared_panel_id and panel.get("selected_id") == WORKER_ID
		and panel.layer > hub.layer and hub.manage_window.visible and get_tree().paused,
		"Keyboard Details opens the same worker card above the paused Manage popup.")
	_expect_ui_name(name_label, "Naram", "Worker Hub Details")
	await _capture("03-details")
	var panel_focus: Control = get_viewport().gui_get_focus_owner()
	_expect(is_instance_valid(panel_focus) and panel.is_ancestor_of(panel_focus), "Focus moves into the shared card.")
	var frame: Control = panel.get_node("Root/Frame") as Control
	var name_plate: TextureRect = name_label.get_node("NamePlate") as TextureRect
	var bar: TextureProgressBar = panel.get_node("Root/Frame/Margin/Contents/BodyScroll/Body/SatisfactionBar") as TextureProgressBar
	_expect(name_plate.size.is_equal_approx(Vector2(54, 11)) and name_label.get_theme_font_size("font_size") == 6
		and frame.get_global_rect().encloses(bar.get_global_rect()) and bar.visible,
		"Details keeps the native 54x11 nameplate, font size 6 and visible satisfaction bar.")
	var underlay := Button.new()
	underlay.position = Vector2.ZERO
	underlay.size = Vector2(16, 16)
	underlay.pressed.connect(func(): underlay_presses += 1)
	hub.get_node("Root").add_child(underlay)
	await _frames()
	await _click(Vector2(4, 4))
	_expect(underlay_presses == 0 and panel.visible, "The shared card blocks clicks to the Hub underneath.")
	await _press_key(KEY_ESCAPE)
	await _frames()
	_expect(not panel.visible and hub.manage_window.visible and hub.manage_details_button.has_focus() and get_tree().paused,
		"Closing Details returns focus to its Manage button and preserves pause.")
	await _press_key(KEY_ESCAPE)
	_expect(not hub.manage_window.visible and row_button.has_focus() and hub.visible and get_tree().paused,
		"Escape closes Manage and returns focus to its Status row.")

	# Normal eligibility: interact only through rendered controls, never by
	# emitting panel action signals or calling a renewal/dismissal backend.
	fire_available = true
	goto_available = true
	hub.refresh()
	await _frames()
	row_button = hub._find_manage_button(WORKER_ID)
	await _click_control(row_button)
	_expect(hub.manage_fire_button.has_focus(), "An available Fire action receives initial focus.")
	await _click_control(hub.manage_goto_button)
	_expect(goto_id == WORKER_ID, "The visible Go To button routes the selected worker ID to its host.")
	var before_wallet: int = int(Inventory.items.get("shekel", 0))
	var before_treasury: int = CityStockManager.treasury_shekel
	var before_end: int = worker.payroll_paid_until_day
	var price: int = WorkerDatabase.get_contract_price(worker.profession, 3)
	await _click_control(hub.manage_contract_button)
	_expect(hub.contract_window.visible and not hub.manage_window.visible and get_tree().paused,
		"The visible Contract action opens the existing paused contract panel.")
	await _capture("04-contract")
	await _click_control(hub.contract_day_buttons[0])
	_expect(int(Inventory.items.get("shekel", 0)) == before_wallet and worker.payroll_paid_until_day == before_end,
		"Opening Contract and selecting a duration do not charge or extend it.")
	await _click_control(hub.manage_renew_button)
	await _frames(3)
	_expect(int(Inventory.items.get("shekel", 0)) == before_wallet - price
		and worker.payroll_paid_until_day == before_end + 3 and CityStockManager.treasury_shekel == before_treasury,
		"One visible Renew click debits the wallet once and extends the worker's contract by three days.")
	await _press_key(KEY_ESCAPE)
	_expect(not hub.contract_window.visible and hub.manage_window.visible and hub.manage_contract_button.has_focus(),
		"Escape returns from Contract to its Manage button.")
	await _click_control(hub.manage_fire_button)
	_expect(hub._confirmation_overlay.visible and hub._confirm_no_button.has_focus(), "The visible Fire control opens confirmation with No focused.")
	await _click_control(hub._confirm_no_button)
	_expect(not hub._confirmation_overlay.visible and WorkerDatabase.get_worker_data(WORKER_ID) == worker
		and removed_ids.is_empty() and hub.manage_fire_button.has_focus(),
		"No cancels Fire, preserves the worker and returns focus to Manage.")
	await _press_key(KEY_ESCAPE)
	await _click_control(hub.tools_tab_button)
	var tool_card: WorkerToolCard = hub.tools_worker_list.get_child(0) as WorkerToolCard
	if is_instance_valid(tool_card):
		await _click_control(tool_card.details_button)
	_expect(panel.visible and panel.get_instance_id() == shared_panel_id and panel.get("selected_id") == WORKER_ID,
		"Tools still opens the same shared needs card.")
	await _press_key(KEY_ESCAPE)
	await _frames()
	_expect(not panel.visible and hub.visible and get_tree().paused and hub.tools_page.visible and hub.tools_tab_button.has_focus(),
		"Escape from Tools Details returns to the Tools tab without unpausing.")
	await _click_control(hub.status_tab_button)
	row_button = hub._find_manage_button(WORKER_ID)
	await _click_control(row_button)
	await _click_control(hub.manage_details_button)
	await _press_key(KEY_K)
	_expect(not panel.visible and not hub.visible and not get_tree().paused,
		"K closes shared Details and Worker Hub and restores the previous pause.")
	_expect(Vector3i(TimeComponentManager.current_day, TimeComponentManager.current_hour,
		TimeComponentManager.current_minute) == starting_clock, "The paused Hub does not advance the game clock.")

	# Confirm Fire via a second worker so the renewal subject remains available.
	await _press_key(KEY_K)
	row_button = hub._find_manage_button(LEGACY_ID)
	await _click_control(row_button)
	await _click_control(hub.manage_fire_button)
	await _click_control(hub._confirm_yes_button)
	await _frames(3)
	_expect(removed_ids == [LEGACY_ID] and WorkerDatabase.get_worker_data(LEGACY_ID) == null
		and hub._find_manage_button(LEGACY_ID) == null and WorkerDatabase.get_worker_data(WORKER_ID) == worker,
		"Yes routes one dismissal and removes only that worker from the refreshed Status list.")
	_expect(int(Inventory.items.get("shekel", 0)) == before_wallet - price
		and CityStockManager.treasury_shekel == before_treasury,
		"The Fire cancel and confirmation do not alter either balance.")

	# Long names must not hide the only Manage entry at 400x225.
	var long_name: String = "Naram Lugal Ashur Nabu Enlil Ishtar Gilgamesh Shamash Marduk Sargon Adad Sin"
	CitizenManager.citizens_by_id[WORKER_ID].display_name = long_name
	hub.refresh()
	await _frames(3)
	row_button = hub._find_manage_button(WORKER_ID)
	var status_scroll: ScrollContainer = hub.status_list.get_parent() as ScrollContainer
	var row_in_bounds: bool = is_instance_valid(row_button) and row_button.is_visible_in_tree() \
		and get_viewport().get_visible_rect().encloses(row_button.get_global_rect()) \
		and status_scroll.get_global_rect().encloses(row_button.get_global_rect())
	_expect(row_in_bounds, "An unusually long worker name keeps Manage inside the visible Status list and viewport.")
	await _capture("05-long-name-status")
	if row_in_bounds:
		var roster_name: Label = row_button.get_parent().get_node("NameLabel") as Label
		_expect(roster_name.clip_text and roster_name.accessibility_name == long_name,
			"The bounded roster name retains its full accessible identity.")
		await _click_control(row_button)
		await _click_control(hub.manage_details_button)
		_expect(panel.visible and name_label.text == long_name and name_label.accessibility_name == long_name,
			"A long-name worker remains reachable through Manage and Details.")
		await _capture("06-long-name-details")
		await _press_key(KEY_ESCAPE)
		await _press_key(KEY_ESCAPE)
	await _press_key(KEY_K)
	_expect(not hub.visible and not get_tree().paused, "Closing the Hub restores live play.")

	# Preserve an already-paused caller as well.
	hub.can_open = func(): return true
	get_tree().paused = true
	await _press_key(KEY_K)
	_expect(hub.visible and get_tree().paused, "K can open without taking ownership of an existing pause.")
	await _press_key(KEY_K)
	_expect(not hub.visible and get_tree().paused, "Closing the Hub preserves a pause that predated it.")
	get_tree().paused = false

	_finish()


func _finish() -> void:
	if is_instance_valid(hub) and hub.visible:
		hub.close()
	if is_instance_valid(runtime):
		runtime.free()
	WorkerDatabase.workers_by_id.assign(saved.workers)
	CitizenManager.citizens_by_id.assign(saved.citizens)
	WorkerDatabase.onboarding_period_rates.assign(saved.rates)
	WorkerDatabase.dismissed_workers.assign(saved.dismissed)
	Inventory.items.assign(saved.inventory)
	TimeComponentManager.is_paused = bool(saved.clock_paused)
	TimeComponentManager.set_process(bool(saved.clock_processing))
	get_tree().paused = bool(saved.tree_paused)
	if failures == 0:
		print("UnifiedDetailsBridgeTest PASSED")
	else:
		print("UnifiedDetailsBridgeTest FAILED: %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
