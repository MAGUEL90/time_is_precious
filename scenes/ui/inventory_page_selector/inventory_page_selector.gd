class_name InventoryPageSelector extends HBoxContainer

signal page_changed(page: int)

@export var dot_active_texture: Texture2D
@export var dot_inactive_texture: Texture2D

@onready var dots_container: HBoxContainer = $DotsContainer
@onready var dot_template: TextureRect = $DotsContainer/DotTemplate
@onready var prev_button: Button = $PrevButton
@onready var next_button: Button = $NextButton
@onready var item_info_panel_root: Control = $"../../../../../ItemInfoPanelRoot"

var current_page: int = 0
var total_pages: int = 1

# Setup / Public API

func _ready() -> void:
	item_info_panel_root.visible = false
	prev_button.pressed.connect(_on_prev_button_pressed)
	next_button.pressed.connect(_on_next_button_pressed)

func set_page_data(new_current_page: int, new_total_pages: int) -> void:
	total_pages = max(new_total_pages, 1)
	current_page = clampi(new_current_page, 0, total_pages - 1)

	modulate.a = 1.0 if total_pages > 1 else 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP if total_pages > 1 else Control.MOUSE_FILTER_IGNORE

	prev_button.disabled = total_pages <= 1 or current_page <= 0
	next_button.disabled = total_pages <= 1 or current_page >= total_pages - 1

	_refresh_dots()

# Page navigation

func _on_prev_button_pressed() -> void:
	if current_page <= 0:
		return

	page_changed.emit(current_page - 1)

func _on_next_button_pressed() -> void:
	if current_page >= total_pages - 1:
		return

	page_changed.emit(current_page + 1)

# Dot display

func _refresh_dots() -> void:
	for child in dots_container.get_children():
		if child != dot_template:
			child.queue_free()

	dot_template.visible = false

	for i in range(total_pages):
		var dot: TextureRect = dot_template.duplicate()
		dot.visible = true
		dot.texture = dot_active_texture if i == current_page else dot_inactive_texture
		dots_container.add_child(dot)
