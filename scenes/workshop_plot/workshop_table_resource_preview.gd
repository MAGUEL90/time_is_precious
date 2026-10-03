@tool
extends Node2D

## Table reference for arranging recipe icons in the editor, never in gameplay.
const BUILT_PLOT: Texture2D = preload("res://assets/ui/building/plot_level_1.png")

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	if Engine.is_editor_hint():
		draw_texture_rect_region(BUILT_PLOT, Rect2(-16, -21, 32, 21), Rect2(8, 13, 32, 21))
