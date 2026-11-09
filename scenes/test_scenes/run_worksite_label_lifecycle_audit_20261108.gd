extends SceneTree

func _initialize() -> void:
	var probe: Node = load("res://scenes/test_scenes/test_scene_worksite_label_lifecycle_audit_20261108.gd").new()
	root.call_deferred("add_child", probe)
