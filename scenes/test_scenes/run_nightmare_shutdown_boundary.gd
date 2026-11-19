extends SceneTree

func _initialize() -> void:
	var probe: Node = load("res://scenes/test_scenes/test_scene_nightmare_shutdown_boundary.gd").new()
	root.call_deferred("add_child", probe)
