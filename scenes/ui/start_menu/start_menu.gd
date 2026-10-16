extends CanvasLayer

signal session_started(continued: bool)

const CITY_PATH: String = "res://scenes/content_scene/content_scene.tscn"
const SAVE_FILE = preload("res://scenes/new_scenes/save_game/city_save_file.gd")
const ARCHIVE = preload("res://scenes/ui/start_menu/checkpoint_archive.gd")

@onready var actions: VBoxContainer = $Root/Center/Frame/Margin/Contents/Actions
@onready var continue_button: Button = $Root/Center/Frame/Margin/Contents/Actions/Continue
@onready var new_game_button: Button = $Root/Center/Frame/Margin/Contents/Actions/NewGame
@onready var confirmation: VBoxContainer = $Root/Center/Frame/Margin/Contents/Confirmation
@onready var message: Label = $Root/Center/Frame/Margin/Contents/Message

# Tests inject an isolated checkpoint path before adding the menu to the tree.
var checkpoint_file = SAVE_FILE.new()
var archive = ARCHIVE.new()
var _confirmed_files: Dictionary = {}
var _busy: bool = false
var _city: Node

func _ready() -> void:
	get_tree().paused = true
	continue_button.pressed.connect(_continue_game)
	new_game_button.pressed.connect(_request_new_game)
	actions.get_node("Quit").pressed.connect(func(): get_tree().quit())
	confirmation.get_node("Buttons/Start").pressed.connect(_start_new_game)
	confirmation.get_node("Buttons/Cancel").pressed.connect(_cancel_new_game)
	_refresh_buttons()
	if continue_button.disabled:
		new_game_button.grab_focus()
	else:
		continue_button.grab_focus()

func _input(event: InputEvent) -> void:
	if _busy:
		get_viewport().set_input_as_handled()
	elif confirmation.visible and event.is_action_pressed("ui_cancel"):
		_cancel_new_game()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var navigation: bool = false
		for action: StringName in [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"ui_focus_next", &"ui_focus_prev"]:
			navigation = navigation or event.is_action(action)
		if not navigation:
			get_viewport().set_input_as_handled()

func _refresh_buttons() -> void:
	continue_button.disabled = _busy or not checkpoint_file.exists()
	new_game_button.disabled = _busy
	actions.get_node("Quit").disabled = _busy

func _set_busy(text: String) -> void:
	_busy = true
	confirmation.hide()
	actions.show()
	message.text = text
	_refresh_buttons()

func _request_new_game() -> void:
	if _busy:
		return
	_confirmed_files = archive.observe(checkpoint_file.path)
	if not archive.error.is_empty():
		message.text = archive.error
		return
	if _confirmed_files.is_empty():
		_start_new_game()
		return
	message.text = ""
	actions.hide()
	confirmation.show()
	confirmation.get_node("Buttons/Cancel").grab_focus()

func _cancel_new_game() -> void:
	confirmation.hide()
	actions.show()
	_confirmed_files.clear()
	_refresh_buttons()
	new_game_button.grab_focus()

func _start_new_game() -> void:
	if _busy:
		return
	_set_busy("Starting...")
	if not await _open_city():
		return
	if not archive.archive(checkpoint_file.path, _confirmed_files):
		_fail(archive.error)
		return
	var store: Node = WorkStateRuntime.get_node("CitySave")
	store.refresh_checkpoint_slot()
	_finish(false)

func _continue_game() -> void:
	if _busy or not checkpoint_file.exists():
		_refresh_buttons()
		return
	_set_busy("Loading...")
	if not await _open_city():
		return
	var store: Node = WorkStateRuntime.get_node("CitySave")
	# Validation requires an idle, unpaused map. No frame elapses before loading.
	get_tree().paused = false
	if not store.load_checkpoint():
		_fail("Could not load this save. You can retry or start a new game. The existing save is unchanged.")
		return
	# Home saves use the existing fade and scene handoff. That path freezes the
	# clock/raid itself until restoration completes; the menu blocks player input.
	while store.status == "Loading":
		await store.changed
	if store.status != "Loaded":
		_fail("Could not open the saved location. Restart the game to try again.")
		continue_button.disabled = true
		new_game_button.disabled = true
		return
	_finish(true)

func _open_city() -> bool:
	if not is_instance_valid(_city):
		# Retain this menu over the real scene transition until startup succeeds.
		if get_tree().current_scene == self:
			get_tree().current_scene = null
		var result: Error = get_tree().change_scene_to_file(CITY_PATH)
		if result != OK:
			_fail("Could not open the city. Please try again.")
			return false
		await get_tree().scene_changed
		_city = get_tree().current_scene
		for frame: int in range(3):
			await get_tree().process_frame
	var store: Node = WorkStateRuntime.get_node_or_null("CitySave")
	if store == null or store.map != _city:
		_fail("The city is not ready. Please try again.")
		return false
	store.disk.path = checkpoint_file.path
	return true

func _fail(text: String) -> void:
	get_tree().paused = true
	_busy = false
	message.text = text
	_refresh_buttons()

func _finish(continued: bool) -> void:
	get_tree().paused = false
	session_started.emit(continued)
	queue_free()
