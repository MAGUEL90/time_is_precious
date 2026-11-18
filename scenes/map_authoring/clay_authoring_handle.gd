@tool
extends Node2D

## Event-driven refresh of the parent Clay guides while editing a handle.
func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
		item_rect_changed.connect(_refresh)
		_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_refresh()

func _draw() -> void:
	if Engine.is_editor_hint():
		_refresh()

func _refresh() -> void:
	var ancestor: Node = get_parent()
	while ancestor != null:
		if ancestor.has_method("refresh_editor_preview"):
			ancestor.refresh_editor_preview()
			return
		ancestor = ancestor.get_parent()
