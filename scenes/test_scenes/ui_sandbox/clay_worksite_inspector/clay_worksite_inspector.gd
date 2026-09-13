extends Control

signal close_requested
signal work_requested(duration_minutes: int)
signal participant_toggled(id: String)
signal worker_setup_discarded
signal worker_removed(id: String)
var progress_panel: NinePatchRect
var progress_list: VBoxContainer
var _progress_open: bool = false
var remove_overlay: CenterContainer
var remove_no_button: Button
var remove_yes_button: Button
var _pending_remove_id: String = ""
@onready var progress_button: Button = $Center/TextureWindow/Margin/MainVBox/Footer/WorkerProgressButton

@onready var window: NinePatchRect = $Center/TextureWindow
@onready var title: Label = $Center/TextureWindow/Margin/MainVBox/Header/TitleLabel
@onready var close_button: TextureButton = $Center/TextureWindow/Margin/MainVBox/Header/CloseButton
@onready var duration_buttons: HBoxContainer = $Center/HourlySetup/Margin/Body/DurationRow/DurationButtons
const DURATIONS: Array[int] = [180, 360, 540]
var selected_duration: int = 180
var busy: bool = false
var work_mode: String = ""
var _hourly_setup: bool = false
var _previous_mode: String = ""
var _previous_duration: int = 180
@onready var hourly_setup_panel: NinePatchRect = $Center/HourlySetup
@onready var next_button: Button = $Center/HourlySetup/Margin/Body/Footer/NextButton
@onready var back_button: Button = $Center/HourlySetup/Margin/Body/Footer/BackButton
@onready var hourly_button: Button = $Center/TextureWindow/Margin/MainVBox/ModeRow/HourlyButton
@onready var daily_button: Button = $Center/TextureWindow/Margin/MainVBox/ModeRow/DailyButton
@onready var energy_label: Label = $Center/TextureWindow/Margin/MainVBox/Confirmation/EnergyLabel
@onready var satiety_label: Label = $Center/TextureWindow/Margin/MainVBox/Confirmation/SatietyLabel
@onready var status_label: Label = $Center/TextureWindow/Margin/MainVBox/StatusLabel
@onready var start_button: Button = $Center/TextureWindow/Margin/MainVBox/Footer/StartButton
const ASSIGNMENT_SCENE: PackedScene = preload("res://scenes/ui/workshop_worker_assignment_ui/workshop_worker_assignment_ui.tscn")
const ASSIGNMENT_SCRIPT = preload("res://scenes/test_scenes/clay_worksite_test/clay_worksite_assignment_ui.gd")
var assignment_ui: WorkshopWorkerAssignmentUI
var _roster_provider: Callable
var _roster_open: bool = false

var _player_ref: Player = null
var _previous_tree_paused: bool = false
var _owns_pause: bool = false
var _preview_provider: Callable
var _scene_panel_sizes: Dictionary = {}
var _panel_fit_queued: bool = false

func _ready() -> void:
	hide()
	_build_progress_panel()
	_build_remove_confirmation()
	progress_button.pressed.connect(func(): _show_progress(true))
	# Scene-authored dimensions and captions remain the presentation authority.
	for panel: NinePatchRect in [window, hourly_setup_panel]:
		_scene_panel_sizes[panel] = panel.custom_minimum_size
		panel.get_node("Margin").minimum_size_changed.connect(_queue_panel_fit)
	back_button.pressed.connect(_cancel_hourly_setup)
	next_button.pressed.connect(_confirm_hourly_setup)
	hourly_button.pressed.connect(func(): select_mode("Hourly"))
	daily_button.pressed.connect(func(): select_mode("Daily"))
	assignment_ui = ASSIGNMENT_SCENE.instantiate()
	assignment_ui.set_script(ASSIGNMENT_SCRIPT)
	assignment_ui.layer = 6
	add_child(assignment_ui)
	assignment_ui.participant_toggled.connect(func(id: String): participant_toggled.emit(id))
	assignment_ui.discard_requested.connect(func(): worker_setup_discarded.emit())
	assignment_ui.returned.connect(func(): _show_roster(false))
	assignment_ui.close_requested.connect(func():
		_show_roster(false)
		close_requested.emit()
	)
	close_button.pressed.connect(func(): close_requested.emit())
	start_button.pressed.connect(_request_work)
	for index: int in range(duration_buttons.get_child_count()):
		duration_buttons.get_child(index).pressed.connect(select_duration.bind(index))
	Inventory.items_changed.connect(_refresh_preview)

func _exit_tree() -> void:
	if Inventory.items_changed.is_connected(_refresh_preview):
		Inventory.items_changed.disconnect(_refresh_preview)
	_disconnect_player()
	_restore_pause()

func _input(event: InputEvent) -> void:
	if not visible or _roster_open:
		return
	if busy:
		get_viewport().set_input_as_handled()
		return
	if remove_overlay.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
			_cancel_remove()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev"):
			if remove_no_button.has_focus():
				remove_yes_button.grab_focus()
			else:
				remove_no_button.grab_focus()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("open_inventory") or event.is_action_pressed("open_work_progress"):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		if _progress_open:
			_show_progress(false)
		elif _hourly_setup:
			_cancel_hourly_setup()
		else:
			close_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_inventory") or event.is_action_pressed("open_work_progress"):
		get_viewport().set_input_as_handled()

func show_site(site_name: String, player_ref: Player = null, preview_provider: Callable = Callable(), roster_provider: Callable = Callable()) -> void:
	work_mode = ""
	_hourly_setup = false
	if not _owns_pause:
		_previous_tree_paused = get_tree().paused
		_owns_pause = true
	_disconnect_player()
	_player_ref = player_ref
	_preview_provider = preview_provider
	_roster_provider = roster_provider
	_show_roster(false)
	if is_instance_valid(_player_ref):
		_player_ref.condition_changed.connect(_refresh_preview)
	title.text = site_name
	title.tooltip_text = site_name
	busy = false
	select_duration(0)
	show()
	get_tree().paused = true
	_refresh_preview()
	hourly_button.grab_focus()

func select_mode(mode: String) -> void:
	if busy:
		return
	if (mode == "Hourly" and hourly_button.disabled) or (mode == "Daily" and daily_button.disabled):
		return
	if mode == "Hourly":
		_previous_mode = work_mode
		_previous_duration = selected_duration
		_hourly_setup = true
	work_mode = mode
	_refresh_preview()
	if mode == "Daily":
		_show_roster(true)

func _cancel_hourly_setup() -> void:
	if busy:
		return
	_hourly_setup = false
	work_mode = _previous_mode
	select_duration(DURATIONS.find(_previous_duration))
	hourly_button.grab_focus()

func close_panel() -> void:
	_pending_remove_id = ""
	remove_overlay.hide()
	_progress_open = false
	progress_panel.hide()
	for button: Button in duration_buttons.get_children():
		button.release_focus()
	close_button.release_focus()
	hide()
	assignment_ui.hide()
	work_mode = ""
	_hourly_setup = false
	_roster_open = false
	selected_duration = DURATIONS[0]
	_disconnect_player()
	_restore_pause()

func _disconnect_player() -> void:
	if is_instance_valid(_player_ref) and _player_ref.condition_changed.is_connected(_refresh_preview):
		_player_ref.condition_changed.disconnect(_refresh_preview)
	_player_ref = null

func _show_roster(open: bool) -> void:
	if busy:
		return
	_roster_open = open
	window.visible = not open and not _hourly_setup
	hourly_setup_panel.hide()
	if open and _roster_provider.is_valid():
		# Reopening edits the same setup; only explicit discard or Close resets it.
		assignment_ui.open_team(_roster_provider)
	else:
		assignment_ui.hide()
		if work_mode == "Daily" and _roster_provider.is_valid():
			var has_workers: bool = false
			for entry: Dictionary in _roster_provider.call():
				has_workers = has_workers or bool(entry.selected)
			if not has_workers:
				work_mode = ""
		_refresh_preview()
		if visible:
			daily_button.grab_focus()

func refresh_team() -> void:
	if _roster_open:
		assignment_ui.sync_team()
	_refresh_preview()

func _restore_pause() -> void:
	if _owns_pause:
		get_tree().paused = _previous_tree_paused
		_owns_pause = false

func get_duration_minutes() -> int:
	return selected_duration

func select_duration(index: int) -> void:
	if busy or index < 0 or index >= DURATIONS.size():
		return
	selected_duration = DURATIONS[index]
	for i: int in range(duration_buttons.get_child_count()):
		duration_buttons.get_child(i).set_pressed_no_signal(i == index)
	_refresh_preview()

func set_busy(value: bool) -> void:
	busy = value
	hourly_button.disabled = value
	daily_button.disabled = value
	close_button.disabled = value
	back_button.disabled = value
	next_button.disabled = value
	for button: Button in duration_buttons.get_children():
		button.disabled = value
	_refresh_preview()

func _confirm_hourly_setup() -> void:
	if not visible or busy or not _hourly_setup:
		return
	_hourly_setup = false
	_refresh_preview()
	start_button.grab_focus()

func _request_work() -> void:
	if not visible or busy or _roster_open or _hourly_setup:
		return
	_refresh_preview()
	if not start_button.disabled:
		start_button.disabled = true
		work_requested.emit(get_duration_minutes())

func _refresh_preview() -> void:
	if not visible:
		return
	if _progress_open:
		_refresh_progress_rows()
		return
	_queue_panel_fit()
	var hourly: bool = work_mode == "Hourly"
	hourly_button.disabled = busy or work_mode == "Daily"
	daily_button.disabled = busy or (hourly and not _hourly_setup)
	window.visible = not _hourly_setup and not _roster_open
	hourly_setup_panel.visible = _hourly_setup and not _roster_open
	if _hourly_setup:
		return
	$Center/TextureWindow/Margin/MainVBox/QuestionLabel.visible = work_mode.is_empty()
	$Center/TextureWindow/Margin/MainVBox/Confirmation.visible = not work_mode.is_empty()
	energy_label.visible = hourly
	$Center/TextureWindow/Margin/MainVBox/Confirmation/DurationLabel.visible = hourly
	$Center/TextureWindow/Margin/MainVBox/Confirmation/DurationLabel.text = "Duration: %dh" % (selected_duration / 60)
	satiety_label.visible = hourly
	$Center/TextureWindow/Margin/MainVBox/Confirmation/ToolEffectLabel.visible = hourly
	$Center/TextureWindow/Margin/MainVBox/Confirmation/WorkersLabel.visible = hourly or work_mode == "Daily"
	start_button.visible = not work_mode.is_empty()
	progress_button.hide()
	if work_mode.is_empty():
		status_label.text = ""
		status_label.hide()
		start_button.disabled = true
		if _preview_provider.is_valid():
			var overview: Dictionary = _preview_provider.call(get_duration_minutes())
			progress_button.visible = int(overview.get("active_count", 0)) > 0
			daily_button.disabled = int(overview.get("active_count", 0)) >= 2
			var workers_label: Label = $Center/TextureWindow/Margin/MainVBox/Confirmation/WorkersLabel
			workers_label.text = "Workers: %d / %d" % [int(overview.worker_count), int(overview.worker_capacity)]
			workers_label.hide()
			if int(overview.worker_count) > 0:
				$Center/TextureWindow/Margin/MainVBox/QuestionLabel.hide()
				hourly_button.disabled = true
				$Center/TextureWindow/Margin/MainVBox/Confirmation.show()
				workers_label.show()
				_show_daily_duration(overview)
		return
	# The sandbox view reads a provider; the fixture owns stock and execution.
	start_button.disabled = true
	status_label.text = "Worksite unavailable."
	var effective_minutes: int = get_duration_minutes()
	var includes_player: bool = true
	if _preview_provider.is_valid():
		var plan: Dictionary = _preview_provider.call(get_duration_minutes())
		effective_minutes = int(plan.minutes)
		includes_player = bool(plan.includes_player)
		$Center/TextureWindow/Margin/MainVBox/Confirmation/WorkersLabel.text = "Workers: %d / %d" % [int(plan.worker_count), int(plan.worker_capacity)]
		if hourly:
			$Center/TextureWindow/Margin/MainVBox/Confirmation/WorkersLabel.text = "Worker: Player"
		if work_mode == "Daily" and plan.has("worker_names") and not str(plan.worker_names).is_empty():
			_show_daily_duration(plan)
		if work_mode == "Daily":
			progress_button.visible = int(plan.get("active_count", 0)) > 0
			daily_button.disabled = int(plan.get("active_count", 0)) >= 2
			start_button.visible = bool(plan.get("has_draft", false))
		status_label.text = ""
		if not str(plan.reason).is_empty():
			status_label.text = str(plan.reason)
		start_button.disabled = busy or not str(plan.reason).is_empty()

	status_label.visible = not status_label.text.is_empty()
	if not includes_player:
		energy_label.text = "Energy --"
		satiety_label.text = "Satiety --"
		return
	energy_label.text = "Energy --"
	satiety_label.text = "Satiety --"
	if not is_instance_valid(_player_ref):
		return
	# Forecast normal awake clock drain only. Fixture debug settings may suppress live needs.
	# This is read-only: no advance_minutes() or condition mutation occurs in the preview.
	var minutes: float = float(effective_minutes)
	var fatigue_span: float = _player_ref.max_fatigue - _player_ref.min_fatigue
	var hunger_span: float = _player_ref.max_hunger - _player_ref.min_hunger
	if fatigue_span > 0.0:
		var energy_used: float = maxf(_player_ref.fatigue_increase_per_min * minutes, 0.0)
		energy_label.text = "Energy -%.0f%%" % (energy_used / fatigue_span * 100.0)
	if hunger_span > 0.0:
		var satiety_used: float = maxf(_player_ref.hunger_increase_per_min * minutes, 0.0)
		satiety_label.text = "Satiety -%.0f%%" % (satiety_used / hunger_span * 100.0)

func _show_daily_duration(plan: Dictionary) -> void:
	var label: Label = $Center/TextureWindow/Margin/MainVBox/Confirmation/DurationLabel
	label.text = str(plan.get("duration_text", ""))
	label.visible = not label.text.is_empty()

func _build_progress_panel() -> void:
	progress_panel = window.duplicate(0)
	progress_panel.name = "WorkerProgress"
	$Center.add_child(progress_panel)
	var margin: MarginContainer = progress_panel.get_node("Margin")
	for child in margin.get_children():
		child.free()
	var box := VBoxContainer.new()
	box.name = "ProgressContent"
	margin.add_child(box)
	var header := HBoxContainer.new()
	header.name = "Header"
	box.add_child(header)
	var heading := Label.new()
	heading.name = "TitleLabel"
	heading.text = "WORKER PROGRESS"
	heading.theme_type_variation = &"HudLabelMain"
	heading.add_theme_font_size_override("font_size", 12)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var close: TextureButton = preload("res://scenes/ui/close_icon_button/close_icon_button.tscn").instantiate()
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(close)
	close.pressed.connect(func(): close_requested.emit())
	progress_list = VBoxContainer.new()
	progress_list.name = "WorkerRows"
	progress_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(progress_list)
	progress_panel.hide()

func _show_progress(open: bool) -> void:
	_progress_open = open
	progress_panel.visible = open
	window.visible = not open
	if not open and _preview_provider.is_valid():
		var plan: Dictionary = _preview_provider.call(get_duration_minutes())
		if int(plan.get("active_count", 0)) == 0 and not bool(plan.get("has_draft", false)):
			work_mode = ""
	_refresh_preview()

func _refresh_progress_rows() -> void:
	for child in progress_list.get_children():
		child.free()
	var plan: Dictionary = _preview_provider.call(get_duration_minutes())
	for worker: Dictionary in plan.get("worker_progress", []):
		var row := HBoxContainer.new()
		progress_list.add_child(row)
		var label := Label.new()
		label.theme_type_variation = &"HudLabelShortcut"
		label.text = "%s\nProductive days: %d | Output: %d clay" % [worker.name, worker.days, worker.output]
		if worker.get("hauler", false):
			label.text = "%s\nProductive days: %d | Delivered: %d clay" % [worker.name, worker.days, worker.output]
			if int(worker.get("daily_target", 0)) > 0:
				label.text += "\nTo: %s\nToday: %d / %d items" % [worker.destination_name, worker.delivered_today, worker.daily_target]
				label.clip_text = true
				label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_font_size_override("font_size", 6)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var remove := Button.new()
		remove.text = "Remove"
		remove.custom_minimum_size.y = 16
		remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if worker.get("removing", false):
			remove.text = "Finishing"
			remove.disabled = true
		remove.theme_type_variation = &"HudShortcutButton"
		remove.add_theme_font_size_override("font_size", 6)
		row.add_child(remove)
		remove.pressed.connect(_request_remove.bind(str(worker.id)))
	progress_panel.custom_minimum_size = _scene_panel_sizes[window].max(progress_panel.get_node("Margin").get_combined_minimum_size())

func _build_remove_confirmation() -> void:
	remove_overlay = CenterContainer.new()
	add_child(remove_overlay)
	remove_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: NinePatchRect = preload("res://scenes/ui/confirm_discard_panel/confirm_discard_panel.tscn").instantiate()
	remove_overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var label: Label = panel.get_node("ConfirmMargin/ConfirmVBox/ConfirmLabel")
	label.text = "Stop this worker now?\nCompleted clay will be kept.\nUnfinished progress will be lost."
	label.add_theme_font_size_override("font_size", 6)
	panel.custom_minimum_size = Vector2(180, 64)
	remove_no_button = panel.get_node("ConfirmMargin/ConfirmVBox/ConfirmButtons/KeepButton")
	remove_yes_button = panel.get_node("ConfirmMargin/ConfirmVBox/ConfirmButtons/DiscardButton")
	remove_no_button.text = "No"
	remove_yes_button.text = "Yes"
	remove_no_button.pressed.connect(_cancel_remove)
	remove_yes_button.pressed.connect(func():
		var id: String = _pending_remove_id
		if id.is_empty():
			return
		_pending_remove_id = ""
		remove_overlay.hide()
		progress_panel.show()
		worker_removed.emit(id)
		_focus_progress_remove.call_deferred()
	)
	remove_overlay.hide()

func _request_remove(id: String) -> void:
	if not _pending_remove_id.is_empty():
		return
	_pending_remove_id = id
	var label: Label = remove_overlay.get_child(0).get_node("ConfirmMargin/ConfirmVBox/ConfirmLabel")
	label.text = "Stop this worker now?\nCompleted clay will be kept.\nUnfinished progress will be lost."
	var plan: Dictionary = _preview_provider.call(selected_duration)
	for worker: Dictionary in plan.get("worker_progress", []):
		if str(worker.id) == id and worker.get("hauler", false):
			label.text = "Remove this Hauler?\nThe current trip will finish first.\nNo new loads will be collected."
	progress_panel.hide()
	remove_overlay.show()
	remove_no_button.grab_focus()

func _cancel_remove() -> void:
	_pending_remove_id = ""
	remove_overlay.hide()
	progress_panel.show()
	_focus_progress_remove()

func _focus_progress_remove() -> void:
	if visible and _progress_open:
		if progress_list.get_child_count() > 0:
			progress_list.get_child(0).get_child(1).grab_focus()
		else:
			_show_progress(false)
			hourly_button.grab_focus()

func _queue_panel_fit() -> void:
	if not _panel_fit_queued and is_inside_tree():
		_panel_fit_queued = true
		_fit_panels.call_deferred()

func _fit_panels() -> void:
	_panel_fit_queued = false
	if not is_inside_tree():
		return
	for panel: NinePatchRect in [window, hourly_setup_panel]:
		if not panel.is_visible_in_tree():
			continue
		var authored: Vector2 = _scene_panel_sizes[panel]
		var content: Vector2 = panel.get_node("Margin").get_combined_minimum_size()
		var required: Vector2 = authored.max(content)
		if panel.custom_minimum_size != required:
			panel.custom_minimum_size = required
