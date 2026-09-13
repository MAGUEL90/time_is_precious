extends WorkshopWorkerAssignmentUI

# Reuse the real workshop scene and slot/card builders. Only roster ownership,
# Daily assignment ownership and modal exit behavior differ in the worksite fixture.
signal participant_toggled(id: String)
signal returned
signal close_requested
signal discard_requested
var roster_provider: Callable
var discard_overlay: Control
var discard_panel: NinePatchRect
var keep_button: Button
var discard_button: Button
var destination_choices_provider: Callable
var hauler_assignment: Callable
var hauler_setup: Control

func _ready() -> void:
	super._ready()
	hauler_setup = preload("res://scenes/test_scenes/ui_sandbox/clay_worksite_inspector/hauler_delivery_setup.tscn").instantiate()
	$Root.add_child(hauler_setup)
	hauler_setup.confirmed.connect(_confirm_hauler)
	hauler_setup.cancelled.connect(_cancel_hauler)
	worker_list.get_parent().resized.connect(_update_worker_columns)
	discard_overlay = Control.new()
	$Root.add_child(discard_overlay)
	discard_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	discard_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	discard_panel = preload("res://scenes/ui/confirm_discard_panel/confirm_discard_panel.tscn").instantiate()
	center.add_child(discard_panel)
	discard_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var label: Label = discard_panel.get_node("ConfirmMargin/ConfirmVBox/ConfirmLabel")
	label.text = "Your settings will be lost.\nDiscard worker setup?"
	label.add_theme_font_size_override("font_size", 6)
	keep_button = discard_panel.get_node("ConfirmMargin/ConfirmVBox/ConfirmButtons/KeepButton")
	discard_button = discard_panel.get_node("ConfirmMargin/ConfirmVBox/ConfirmButtons/DiscardButton")
	keep_button.text = "No"
	discard_button.text = "Yes"
	keep_button.pressed.connect(func(): discard_overlay.hide(); back_button.grab_focus())
	discard_button.pressed.connect(func():
		discard_requested.emit()
		discard_overlay.hide()
		hide()
		returned.emit()
	)
	discard_overlay.hide()
	_clear_tooltips(self)

func _clear_tooltips(node: Node) -> void:
	if node is Control:
		node.tooltip_text = ""
	for child in node.get_children():
		_clear_tooltips(child)

func _refresh_slots() -> void:
	super._refresh_slots()
	_clear_tooltips(slot_grid)

func _add_locked_slot() -> void:
	# Small worksite shows only its real capacity, with no future locked slot.
	pass

func _update_worker_columns() -> void:
	var scroll: ScrollContainer = worker_list.get_parent()
	var available_width: float = scroll.size.x
	var scrollbar: VScrollBar = scroll.get_v_scroll_bar()
	if scrollbar.visible:
		available_width -= scrollbar.size.x
	var gap: int = worker_list.get_theme_constant("h_separation")
	worker_list.columns = maxi(1, int(floor((available_width + gap) / (SLOT_SIZE.x + gap))))

func open_team(provider: Callable) -> void:
	hauler_setup.hide()
	$Root/Center.show()
	discard_overlay.hide()
	roster_provider = provider
	max_worker_slots = 2
	for entry: Dictionary in provider.call():
		max_worker_slots = int(entry.get("slots_available", 2))
		break
	sync_team()
	visible = true
	_show_overview()

func sync_team() -> void:
	selected_worker_ids.clear()
	selected_worker_ids.resize(max_worker_slots)
	selected_worker_ids.fill("")
	var index: int = 0
	var names: PackedStringArray = []
	for entry: Dictionary in roster_provider.call():
		if entry.selected and index < max_worker_slots:
			selected_worker_ids[index] = str(entry.id)
			index += 1
			names.append(str(entry.name))
	feedback_label.text = ", ".join(names)
	_refresh_info_label()
	_refresh_slots()
	_refresh_next_state()

func _get_workers_in_requirement_order() -> Array:
	var roster: Array = []
	var entries: Array = roster_provider.call()
	entries.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.reason).is_empty() and not str(b.reason).is_empty())
	for entry: Dictionary in entries:
		var worker: WorkerData = WorkerDatabase.get_worker_data(str(entry.id))
		if worker != null:
			roster.append(worker)
	return roster

func _refresh_worker_list() -> void:
	selection_title_label.remove_theme_color_override("font_color")
	super._refresh_worker_list()
	call_deferred("_update_worker_columns")
	var roster: Array = _get_workers_in_requirement_order()
	var entries: Array = roster_provider.call()
	for index: int in range(roster.size()):
		var worker: WorkerData = roster[index]
		var card: Button = worker_list.get_child(index)
		card.name = "Participant_" + worker.worker_id
		for entry: Dictionary in entries:
			if entry.id == worker.worker_id and not str(entry.reason).is_empty():
				card.disabled = true
				if str(entry.reason).begins_with("Requires a cart"):
					card.modulate = Color(1.0, 0.4, 0.4)
					card.disabled = false
					card.set_meta("missing_tool", true)
	_clear_tooltips(worker_list)

func _on_worker_selected(id: String) -> void:
	for entry: Dictionary in roster_provider.call():
		if entry.id == id and str(entry.reason).begins_with("Requires a cart"):
			selection_title_label.text = str(entry.reason)
			selection_title_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
			return
	selection_title_label.remove_theme_color_override("font_color")
	if _get_assigned_worker_count() >= max_worker_slots or selected_worker_ids.has(id):
		return
	var worker: WorkerData = WorkerDatabase.get_worker_data(id)
	if worker != null and worker.profession == WorkerData.Profession.HAULER:
		var choices: Array[Dictionary] = []
		if destination_choices_provider.is_valid():
			choices.assign(destination_choices_provider.call())
		$Root/Center.hide()
		hauler_setup.open_for(id, worker.get_resolved_display_name(), choices)
		return
	participant_toggled.emit(id)
	sync_team()
	_show_overview()

func _confirm_hauler(id: String, destination_path: NodePath, daily_target: int) -> void:
	var reason: String = "Hauler setup is unavailable."
	if hauler_assignment.is_valid():
		reason = str(hauler_assignment.call(id, destination_path, daily_target))
	if not reason.is_empty():
		hauler_setup.set_error(reason)
		return
	hauler_setup.hide()
	$Root/Center.show()
	sync_team()
	_show_overview()
	next_button.grab_focus()

func _cancel_hauler() -> void:
	hauler_setup.hide()
	$Root/Center.show()
	selection_back_button.grab_focus()

func _remove_worker_from_slot(index: int) -> void:
	if index < 0 or index >= selected_worker_ids.size() or selected_worker_ids[index].is_empty():
		return
	participant_toggled.emit(selected_worker_ids[index])
	sync_team()
	_show_overview()

func _refresh_info_label() -> void:
	assigned_info_label.text = "Assigned: %d/%d" % [_get_assigned_worker_count(), max_worker_slots]
	total_workers_label.text = "Workers: %d" % (roster_provider.call().size() if roster_provider.is_valid() else 0)
	total_workers_label.hide()
	$Root/Center/TextureWindow/Margin/MainVBox/InfoRow/SeparatorIcon.hide()

func _refresh_next_state() -> void:
	# Empty is valid when withdrawing the last standing assignment.
	next_button.disabled = false

func _on_next_pressed() -> void:
	if discard_overlay.visible:
		return
	hide()
	returned.emit()

func _on_back_pressed() -> void:
	if _get_assigned_worker_count() > 0:
		discard_overlay.show()
		keep_button.grab_focus()
		return
	hide()
	returned.emit()

func _on_cancel_pressed() -> void:
	hide()
	close_requested.emit()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if hauler_setup.visible:
		if hauler_setup.destination_button.get_popup().visible:
			return
		if event.is_action_pressed("ui_cancel"):
			_cancel_hauler()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact") or event.is_action_pressed("open_inventory") or event.is_action_pressed("open_work_progress"):
			get_viewport().set_input_as_handled()
		return
	if discard_overlay.visible:
		if event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
			if keep_button.has_focus():
				discard_button.grab_focus()
			else:
				keep_button.grab_focus()
			get_viewport().set_input_as_handled()
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
			discard_overlay.hide()
			back_button.grab_focus()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		if worker_info_layer.visible:
			_hide_worker_info()
		elif worker_selection_page.visible:
			_show_overview()
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_inventory") or event.is_action_pressed("open_work_progress"):
		get_viewport().set_input_as_handled()
