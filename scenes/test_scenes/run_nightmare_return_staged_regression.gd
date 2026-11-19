extends SceneTree
func _initialize() -> void:
	var probe: Node = load("res://scenes/test_scenes/test_scene_nightmare_return_staged_regression.gd").new()
	root.call_deferred("add_child", probe)
