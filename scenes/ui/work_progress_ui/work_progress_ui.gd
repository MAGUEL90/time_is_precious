class_name WorkProgressUI extends CanvasLayer

const OPEN_ACTION: StringName = &"open_work_progress"
const ENTRY_SCENE: PackedScene = preload("res://scenes/ui/work_progress_entry/work_progress_entry.tscn")

@onready var root: Control = $Root
@onready var empty_label: Label = $Root/Center/Window/Margin/MainVBox/EmptyLabel
@onready var work_scroll: ScrollContainer = $Root/Center/Window/Margin/MainVBox/WorkScroll
@onready var work_list: VBoxContainer = $Root/Center/Window/Margin/MainVBox/WorkScroll/WorkList
@onready var close_button: BaseButton = $Root/Center/Window/CloseButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	root.hide()
	close_button.pressed.connect(close_panel)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(OPEN_ACTION):
		toggle_panel()
		get_viewport().set_input_as_handled()
		return

	if root.visible and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()

func toggle_panel() -> void:
	if root.visible:
		close_panel()
	else:
		open_panel()

func open_panel() -> void:
	if root.visible:
		return
	if get_tree().paused:
		return

	_refresh_entries()
	root.show()
	get_tree().paused = true
	close_button.grab_focus()

func close_panel() -> void:
	if not root.visible:
		return

	root.hide()
	get_tree().paused = false

func _refresh_entries() -> void:
	_clear_entries()

	var progress_entries: Array[Dictionary] = []

	progress_entries.append_array(WorkManager.get_active_progress_entries())
	progress_entries.append_array(ProcessManager.get_active_progress_entries())

	for progress_data in progress_entries:
		var entry: WorkProgressEntry = (
			ENTRY_SCENE.instantiate() as WorkProgressEntry
		)

		if entry == null:
			continue

		work_list.add_child(entry)
		entry.setup(progress_data)

	var has_entries: bool = not progress_entries.is_empty()
	empty_label.visible = not has_entries
	work_scroll.visible = has_entries

func _clear_entries() -> void:
	for child in work_list.get_children():
		work_list.remove_child(child)
		child.queue_free()
