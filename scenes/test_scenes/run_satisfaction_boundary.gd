extends SceneTree

func _initialize() -> void:
	var test: Node = load("res://scenes/test_scenes/test_scene_satisfaction_boundary.gd").new()
	root.call_deferred("add_child", test)
