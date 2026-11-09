extends SceneTree

func _initialize() -> void:
	var test: Node = load("res://scenes/test_scenes/test_scene_authored_date_palm_binding.gd").new()
	root.call_deferred("add_child", test)
