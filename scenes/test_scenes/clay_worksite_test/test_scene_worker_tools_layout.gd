extends Node

const HUB: PackedScene = preload("res://scenes/test_scenes/ui_sandbox/worker_control/worker_control.tscn")

var hub: WorkerControlUI
var failures: int = 0
var rows: Array = [
	{"id": "layout_working", "name": "Arad", "profession": "Laborer", "tools_locked": true, "working": true},
	{"id": "layout_idle", "name": "Dumuzi", "profession": "Farmer", "tools_locked": false},
	{"id": "layout_hauler", "name": "Bani", "profession": "Hauler", "tools_locked": false}
]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	hub = HUB.instantiate()
	hub.rows_provider = func(): return rows
	hub.tools_provider = func(_id: String): return []
	add_child(hub)
	hub.open()
	hub.tools_tab_button.pressed.emit()
	await _settle()
	var baseline := _positions()
	_check_layout("working")
	await _capture("worker-tools-layout-working.png")
	for id: String in ["layout_idle", "layout_hauler", "layout_working", "layout_idle"]:
		hub._select_worker_for_tools(id)
		await _settle()
		_check_layout(id)
		_expect(_positions() == baseline, "Name, six slots and preview keep their positions: " + id)
		if id == "layout_idle":
			_expect(hub.tools_feedback_label.text.is_empty(), "Idle has no working-lock message")
		elif id == "layout_working":
			_expect(hub.tools_feedback_label.text == "Tools locked while working.", "Selecting a working worker retains lock feedback")
		await _capture("worker-tools-layout-" + id + ".png")
	hub.set_feedback("Unequip the current tool from this slot first.")
	await _settle()
	_check_layout("long feedback")
	_expect(_positions() == baseline, "Long feedback does not resize equipment")
	hub.close()
	hub.open()
	await _settle()
	_check_layout("reopen")
	_expect(_positions() == baseline, "Reopening retains Tools geometry")
	hub.close()
	hub.queue_free()
	await get_tree().process_frame
	print("WorkerToolsLayoutTest ", "PASSED" if failures == 0 else "FAILED")
	get_tree().quit(0 if failures == 0 else 1)

func _check_layout(context: String) -> void:
	var tabs := hub.tools_tab_button.get_parent() as Control
	var page := hub.tools_page.get_parent() as Control
	var page_rect := page.get_global_rect()
	_expect(page_rect.position.y >= tabs.get_global_rect().end.y + 2, context + ": content starts below tabs")
	_expect(page_rect.encloses(hub.tools_page.get_global_rect()), context + ": Tools stays inside PageStack")
	var controls: Array[Control] = _controls()
	controls.append(hub.tools_worker_scroll)
	controls.append(hub.tools_feedback_label)
	for control: Control in controls:
		if control.is_visible_in_tree():
			_expect(page_rect.encloses(control.get_global_rect()), context + ": inside page: " + control.name)
	var name_bottom := hub.tools_selected_label.get_global_rect().end.y
	_expect(hub.tools_tool_button.global_position.y >= name_bottom + 2, context + ": slots have space below name")
	var slots_bottom := hub.tools_extra_accessory_button.get_global_rect().end.y
	var feedback: Label = hub.tools_feedback_label if hub.tools_feedback_label.visible else hub.tools_cart_required_label
	_expect(feedback.global_position.y >= slots_bottom + 2, context + ": feedback stays below equipment")
	_expect(hub.window.size == Vector2(330, 200), context + ": human panel size is preserved")

func _controls() -> Array[Control]:
	return [hub.tools_selected_label, hub.tools_tool_button, hub.tools_hands_button,
		hub.tools_feet_button, hub.tools_accessory_button_1, hub.tools_accessory_button_2,
		hub.tools_extra_accessory_button, hub.tools_preview_anchor]

func _positions() -> Array:
	var result: Array = []
	for control: Control in _controls():
		result.append(control.get_global_rect())
	result.append(hub._tools_preview_visual.global_position)
	return result

func _settle() -> void:
	for frame: int in range(4):
		await get_tree().process_frame

func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join(filename))

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
