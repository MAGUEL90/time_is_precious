@tool
class_name WorkOrderCard
extends Button

signal details_requested

enum WorkOrderType {
	JOB,
	PROCESS
}

@export var work_order_id: String = ""
@export var work_order_type: WorkOrderType = WorkOrderType.JOB

@export var card_title: String = "Work":
	set(value):
		card_title = value
		_refresh_visuals()

@export var card_icon: Texture2D:
	set(value):
		card_icon = value
		_refresh_visuals()

@export var progression_locked: bool = false:
	set(value):
		progression_locked = value
		_refresh_visuals()

@onready var work_icon: TextureRect = $ContentMargin/ContentVBox/IconCenter/WorkIcon
@onready var name_label: Label = $ContentMargin/ContentVBox/NameLabel
@onready var lock_overlay: ColorRect = $LockOverlay
@onready var selection_frame: NinePatchRect = $SelectionFrame

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var info := Button.new()
	info.name = "InfoButton"
	info.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info.offset_left = -9
	info.offset_right = -2
	info.offset_top = 2
	info.offset_bottom = 15
	info.focus_mode = Control.FOCUS_NONE
	info.mouse_filter = Control.MOUSE_FILTER_STOP
	info.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	info.icon = preload("res://assets/ui/ui_icon/exclamation_mark_icon.png")
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		info.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	info.add_theme_color_override("icon_hover_color", Color(1.4, 1.4, 1.2))
	info.add_theme_color_override("icon_pressed_color", Color(0.65, 0.65, 0.65))
	info.add_theme_color_override("icon_hover_pressed_color", Color(0.65, 0.65, 0.65))
	info.pressed.connect(func(): details_requested.emit())
	info.visible = not work_order_id.is_empty()
	add_child(info)
	# Inventory selection uses its selector rather than changing the panel fill.
	var normal_style: StyleBox = get_theme_stylebox("normal")
	for state in ["hover", "pressed", "hover_pressed"]:
		add_theme_stylebox_override(state, normal_style)
	mouse_entered.connect(_show_hover_frame)
	mouse_exited.connect(_hide_hover_frame)
	toggled.connect(_on_selection_toggled)
	_refresh_visuals()

func _show_hover_frame() -> void:
	selection_frame.visible = not progression_locked

func _refresh_selection_frame() -> void:
	selection_frame.visible = not progression_locked and (button_pressed or is_hovered())

func _hide_hover_frame() -> void:
	selection_frame.visible = not progression_locked and button_pressed

func _on_selection_toggled(_selected: bool) -> void:
	_refresh_selection_frame()

func _refresh_visuals() -> void:
	if not is_node_ready():
		return
	
	work_icon.texture = card_icon
	name_label.text = card_title
	lock_overlay.visible = progression_locked
	disabled = progression_locked

	if progression_locked:
		button_pressed = false
	_refresh_selection_frame()

func set_selected(value: bool) -> void:
	button_pressed = value and not progression_locked
	_refresh_selection_frame()
