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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


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
	press.physical_keycode = key
	press.pressed = true
	get_viewport().push_input(press)
	await _frames(1)
	var release := InputEventKey.new()
	release.keycode = key
	release.physical_keycode = key
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


func _rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in [WORKER_ID, LEGACY_ID]:
		var person: WorkerData = WorkerDatabase.get_worker_data(id)
		if person == null:
			continue
		rows.append({"id": id, "name": person.get_resolved_display_name(),
			"profession": "Laborer", "working": false, "can_fire": true,
			"can_goto": true, "star": 1, "wage": "6 Shekel / 3 days", "needs": {}})
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
		"tree_paused": get_tree().paused, "clock_paused": TimeComponentManager.is_paused,
		"clock_processing": TimeComponentManager.is_processing()}
	get_tree().paused = false
	TimeComponentManager.is_paused = false
	TimeComponentManager.set_process(false)
	var starting_clock: Vector3i = Vector3i(TimeComponentManager.current_day,
		TimeComponentManager.current_hour, TimeComponentManager.current_minute)
	WorkerDatabase.onboarding_period_rates[WorkerData.Profession.LABORER] = 6
	Inventory.items["shekel"] = 100
	CitizenManager.citizens_by_id[WORKER_ID] = _new_citizen(WORKER_ID, "Linked Worker", true)
	CitizenManager.citizens_by_id[RESIDENT_ID] = _new_citizen(RESIDENT_ID, "Resident", false)
	worker = _new_worker(WORKER_ID, "Linked Worker")
	WorkerDatabase.workers_by_id[WORKER_ID] = worker
	WorkerDatabase.workers_by_id[LEGACY_ID] = _new_worker(LEGACY_ID, "Legacy Worker")

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
	controller = CONTROLLER_SCRIPT.new()
	controller.configure(runtime, visuals)
	runtime.add_child(controller)
	panel = controller.get("panel") as CanvasLayer
	await _frames()

	await _click(Vector2(70, 70))
	_expect(panel.visible and panel.get("selected_id") == WORKER_ID and not get_tree().paused,
		"Map click opens the linked worker's shared card without pausing.")
	var shared_panel_id: int = panel.get_instance_id()
	await _press_key(KEY_C)
	_expect(not panel.visible and city_shortcuts == 1 and not get_tree().paused,
		"C closes the map card and reaches the City Hub shortcut without changing pause.")

	await _click(Vector2(70, 70))
	panel.emit_signal("renew_requested", WORKER_ID)
	await _frames()
	_expect(hub.visible and hub.contract_window.visible and not panel.visible and get_tree().paused,
		"Map Renew opens the existing paused contract window.")
	var before_wallet: int = int(Inventory.items.get("shekel", 0))
	var before_end: int = worker.payroll_paid_until_day
	var price: int = WorkerDatabase.get_contract_price(worker.profession, 3)
	hub.manage_renew_button.pressed.emit()
	_expect(int(Inventory.items.get("shekel", 0)) == before_wallet - price
		and worker.payroll_paid_until_day == before_end + 3,
		"One map-origin Renew debits once and extends the existing contract.")
	hub.contract_close_button.pressed.emit()
	await _frames()
	_expect(panel.visible and panel.get_instance_id() == shared_panel_id and panel.get("selected_id") == WORKER_ID
		and not hub.visible and not get_tree().paused,
		"Closing map-origin Contract restores the same nonmodal card and pause.")

	panel.emit_signal("actions_requested", WORKER_ID)
	_expect(hub.visible and hub.manage_window.visible and hub._manage_worker_id == WORKER_ID,
		"Map Actions opens the original worker action menu.")
	hub.manage_goto_button.pressed.emit()
	_expect(goto_id == WORKER_ID, "Go To retains the selected worker identity.")
	hub.manage_contract_button.pressed.emit()
	_expect(hub.contract_window.visible, "Actions still offers the existing Contract window.")
	hub.contract_close_button.pressed.emit()
	_expect(hub.manage_window.visible, "Closing Contract entered from Actions returns to Actions.")
	hub.manage_fire_button.pressed.emit()
	_expect(hub._confirmation_overlay.visible, "Fire still asks for confirmation.")
	hub._cancel_remove_confirmation()
	_expect(WorkerDatabase.get_worker_data(WORKER_ID) == worker, "Cancelling Fire retains the worker.")
	hub._close_manage()
	await _frames()
	_expect(panel.visible and not get_tree().paused, "Closing map Actions returns to the card.")
	panel.call("close")

	await _click(Vector2(110, 70))
	_expect(panel.visible and panel.get("selected_id") == LEGACY_ID,
		"A legacy worker without a linked citizen remains inspectable.")
	panel.emit_signal("renew_requested", LEGACY_ID)
	_expect(hub.contract_window.visible and hub._manage_worker_id == LEGACY_ID,
		"A legacy worker can reach the existing contract window.")
	hub.contract_close_button.pressed.emit()
	panel.call("close")
	await _click(Vector2(150, 70))
	panel.emit_signal("renew_requested", RESIDENT_ID)
	_expect(panel.visible and panel.get("selected_id") == RESIDENT_ID and not hub.visible,
		"A nonworker cannot enter the contract flow.")
	panel.call("close")

	await _press_key(KEY_K)
	_expect(hub.visible and get_tree().paused, "K opens and pauses the existing worker list.")
	var row_button: Button = hub._find_manage_button(WORKER_ID)
	_expect(is_instance_valid(row_button) and row_button.text == "Details", "The worker row is labeled Details.")
	if is_instance_valid(row_button):
		row_button.pressed.emit()
	await _frames()
	_expect(panel.visible and panel.get_instance_id() == shared_panel_id and panel.get("selected_id") == WORKER_ID
		and panel.layer > hub.layer and get_tree().paused,
		"K Details opens the very same card for that worker above the paused list.")
	var panel_focus: Control = get_viewport().gui_get_focus_owner()
	_expect(is_instance_valid(panel_focus) and panel.is_ancestor_of(panel_focus),
		"Keyboard focus moves into the shared card while the hub remains underneath.")
	var underlay := Button.new()
	underlay.position = Vector2.ZERO
	underlay.size = Vector2(16, 16)
	underlay.pressed.connect(func(): underlay_presses += 1)
	hub.get_node("Root").add_child(underlay)
	await _frames()
	await _click(Vector2(4, 4))
	_expect(underlay_presses == 0 and panel.visible, "Clicks outside the card cannot reach the worker list beneath it.")

	panel.emit_signal("renew_requested", WORKER_ID)
	_expect(hub.contract_window.visible and not panel.visible and get_tree().paused,
		"K-origin Renew opens the same existing Contract window.")
	before_wallet = int(Inventory.items.get("shekel", 0))
	before_end = worker.payroll_paid_until_day
	hub.manage_renew_button.pressed.emit()
	_expect(int(Inventory.items.get("shekel", 0)) == before_wallet - price
		and worker.payroll_paid_until_day == before_end + 3,
		"One K-origin Renew also debits once and extends the existing contract.")
	hub.contract_close_button.pressed.emit()
	await _frames()
	_expect(panel.visible and panel.get_instance_id() == shared_panel_id and hub.visible and get_tree().paused,
		"Closing K-origin Contract returns to the shared card without releasing pause.")
	await _press_key(KEY_C)
	_expect(not panel.visible and hub.visible and get_tree().paused and city_shortcuts == 1,
		"C closes K-origin details, preserves the list's pause, and does not reach City Hub.")

	hub._show_tools_tab()
	var tool_card: WorkerToolCard = hub.tools_worker_list.get_child(0) as WorkerToolCard
	if is_instance_valid(tool_card):
		tool_card.details_button.pressed.emit()
	await _frames()
	_expect(panel.visible and panel.get_instance_id() == shared_panel_id,
		"The Tools information button also opens the shared card.")
	await _press_key(KEY_ESCAPE)
	_expect(not panel.visible and hub.visible and get_tree().paused and hub.tools_page.visible
		and hub.tools_tab_button.has_focus(),
		"Escape returns focus to the previous Tools tab with pause retained.")
	hub._show_status_tab()
	row_button = hub._find_manage_button(WORKER_ID)
	if is_instance_valid(row_button):
		row_button.pressed.emit()
	await _press_key(KEY_K)
	_expect(not panel.visible and not hub.visible and not get_tree().paused,
		"K closes both the shared card and list and restores the previous pause.")
	_expect(Vector3i(TimeComponentManager.current_day, TimeComponentManager.current_hour,
		TimeComponentManager.current_minute) == starting_clock,
		"Opening and closing the details flows does not advance the paused clock.")

	# The hub already preserves a prior pause. The shared card must not release it.
	hub.can_open = func(): return true
	get_tree().paused = true
	hub.open()
	row_button = hub._find_manage_button(WORKER_ID)
	if is_instance_valid(row_button):
		row_button.pressed.emit()
	await _press_key(KEY_K)
	_expect(not panel.visible and not hub.visible and get_tree().paused,
		"Closing shared details preserves a pause that predated the hub.")
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
	Inventory.items.assign(saved.inventory)
	TimeComponentManager.is_paused = bool(saved.clock_paused)
	TimeComponentManager.set_process(bool(saved.clock_processing))
	get_tree().paused = bool(saved.tree_paused)
	if failures == 0:
		print("UnifiedDetailsBridgeTest PASSED")
	else:
		print("UnifiedDetailsBridgeTest FAILED: %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
