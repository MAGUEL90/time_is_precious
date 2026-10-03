@tool
extends Node

## One-time editor migration; deliberately never saves the open scene.
static func compare_saved(root: Node) -> Dictionary:
	var saved: Node = load(root.scene_file_path).instantiate()
	var differences: Array[String] = []
	_compare_nodes(root, saved, ".", differences)
	saved.free()
	return {"differences": differences}

static func _compare_nodes(current: Node, saved: Node, path: String, differences: Array[String]) -> void:
	if current.get_class() != saved.get_class():
		differences.append(path + ": class")
	for property: Dictionary in current.get_property_list():
		if not int(property.usage) & PROPERTY_USAGE_STORAGE:
			continue
		var key: String = property.name
		if _value(current.get(key)) != _value(saved.get(key)):
			differences.append(path + ": " + key)
	var current_count: int = current.get_child_count() - (1 if current.has_node("_IconMigrationHelper") else 0)
	if current_count != saved.get_child_count():
		differences.append(path + ": child count")
	for child: Node in current.get_children():
		if child.name == "_IconMigrationHelper":
			continue
		var saved_child: Node = saved.get_node_or_null(NodePath(str(child.name)))
		if saved_child == null:
			differences.append(path + "/" + str(child.name) + ": added")
		else:
			_compare_nodes(child, saved_child, path + "/" + str(child.name), differences)

static func _value(value: Variant) -> String:
	if value is Resource:
		if value is Shape2D:
			var fields: Array[String] = [value.get_class()]
			for property: Dictionary in value.get_property_list():
				if int(property.usage) & PROPERTY_USAGE_STORAGE and property.name not in ["resource_path", "script"]:
					fields.append(str(property.name) + ":" + str(value.get(property.name)))
			return str(fields)
		return value.get_class() + ":" + value.resource_path
	return str(value)

static func configure(root: Node) -> Dictionary:
	if root.scene_file_path != "res://scenes/workshop_plot/workshop_plot.tscn":
		return {"error": "Open workshop_plot first."}
	var container: Node2D = root.get_node("TableResources")
	var icon: Sprite2D = root.get_node_or_null("ResourceIcon")
	if icon == null or container.get_child_count() != 0:
		return {"error": "Layout already migrated or differs from the expected scene."}
	var second := Sprite2D.new()
	second.name = "ResourceIcon2"
	second.position = Vector2(7, -6)
	second.texture = load("res://assets/items/clay_lump.png")
	second.editor_description = "Move this preview icon. Runtime swaps only its texture to the workshop recipe's first input."
	var old_index: int = icon.get_index()
	var undo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	undo.create_action("Arrange workshop table icons", UndoRedo.MERGE_DISABLE, root)
	undo.add_do_method(icon, "reparent", container)
	undo.add_undo_method(icon, "reparent", root)
	undo.add_undo_method(root, "move_child", icon, old_index)
	for key: String in ["position", "offset", "texture", "editor_description"]:
		var new_value: Variant
		match key:
			"position": new_value = Vector2(-7, -12)
			"offset": new_value = Vector2.ZERO
			"texture": new_value = second.texture
			"editor_description": new_value = second.editor_description
		undo.add_do_property(icon, key, new_value)
		undo.add_undo_property(icon, key, icon.get(key))
	undo.add_do_method(container, "add_child", second)
	undo.add_do_method(second, "set_owner", root)
	undo.add_do_reference(second)
	undo.add_undo_method(container, "remove_child", second)
	undo.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(icon)
	EditorInterface.edit_node(icon)
	return {"ok": true, "saved": false, "icons": ["TableResources/ResourceIcon", "TableResources/ResourceIcon2"]}
